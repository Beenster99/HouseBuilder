"""Turns parsed OSM data into site pack features in local metres."""

from __future__ import annotations

import math
import re
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

from . import geo
from .osm import OsmData, assemble_rings

VEHICLE_ROADS = {
    # kind: (default width m, lanes)
    "motorway": (11.0, 3), "trunk": (10.0, 2), "primary": (9.0, 2), "secondary": (8.0, 2),
    "tertiary": (7.0, 2), "unclassified": (6.0, 2), "residential": (6.0, 2),
    "motorway_link": (6.0, 1), "trunk_link": (6.0, 1), "primary_link": (6.0, 1),
    "secondary_link": (6.0, 1), "tertiary_link": (6.0, 1),
    "living_street": (5.0, 1), "service": (3.5, 1), "track": (3.0, 1), "road": (6.0, 2),
    "busway": (6.5, 2),
}
PATHS = {"footway": 2.0, "path": 1.5, "cycleway": 2.5, "pedestrian": 5.0, "steps": 2.0,
         "bridleway": 2.5, "corridor": 2.0}
NARROW_ROAD_KINDS = {"service", "track", "living_street"}

AREA_TAGS = {
    "landuse": None,  # every value
    "natural": {"water", "wood", "scrub", "grassland", "wetland", "heath", "bare_rock",
                "sand", "beach", "scree", "shingle", "mud"},
    "leisure": {"park", "garden", "pitch", "playground", "common", "recreation_ground",
                "nature_reserve", "golf_course", "sports_centre", "track"},
    "amenity": {"parking", "school", "hospital", "university", "college", "grave_yard"},
    "waterway": {"riverbank", "dock"},
    "water": None,
    "man_made": {"bridge", "pier", "wastewater_plant", "works"},
}
WATERWAY_LINES = {"river": 8.0, "stream": 2.0, "canal": 10.0, "ditch": 1.0, "drain": 1.0, "brook": 1.5}
BARRIERS = {"wall", "fence", "hedge", "retaining_wall", "city_wall", "guard_rail", "gate", "kerb"}

# Default heights by building type when OSM has no height or levels.
DEFAULT_HEIGHTS = {
    "house": 7.5, "detached": 7.5, "semidetached_house": 7.5, "terrace": 8.0, "bungalow": 4.5,
    "residential": 9.0, "apartments": 13.0, "garage": 2.8, "garages": 2.8, "shed": 2.5,
    "carport": 2.6, "hut": 2.8, "cabin": 3.5, "roof": 4.0, "greenhouse": 3.0,
    "commercial": 10.0, "retail": 6.5, "supermarket": 7.5, "office": 14.0, "industrial": 9.0,
    "warehouse": 10.0, "school": 8.0, "hospital": 18.0, "university": 14.0, "college": 12.0,
    "church": 15.0, "cathedral": 30.0, "chapel": 8.0, "civic": 10.0, "public": 10.0,
    "hotel": 15.0, "train_station": 10.0, "farm_auxiliary": 6.0, "barn": 7.0, "stable": 4.0,
    "service": 3.0, "transformer_tower": 4.0, "kiosk": 3.0, "toilets": 3.0,
}
DEFAULT_HEIGHT = 7.0
LEVEL_HEIGHT = 3.0


def parse_length(value: Optional[str]) -> Optional[float]:
    """Parses OSM length tags such as '12', '12.5 m', "40'", "10'6\"". Metres."""
    if not value:
        return None
    v = value.strip().lower().replace(",", ".")
    m = re.match(r"^(\d+(?:\.\d+)?)\s*'\s*(?:(\d+(?:\.\d+)?)\s*\")?$", v)
    if m:
        return float(m.group(1)) * 0.3048 + (float(m.group(2)) * 0.0254 if m.group(2) else 0.0)
    m = re.match(r"^(\d+(?:\.\d+)?)\s*(m|metres|meters|ft|feet)?$", v)
    if m:
        n = float(m.group(1))
        return n * 0.3048 if m.group(2) in ("ft", "feet") else n
    m = re.match(r"^(\d+(?:\.\d+)?)", v)
    return float(m.group(1)) if m else None


def parse_number(value: Optional[str]) -> Optional[float]:
    if not value:
        return None
    m = re.match(r"^\s*(\d+(?:[.,]\d+)?)", value)
    return float(m.group(1).replace(",", ".")) if m else None


@dataclass
class Polygon:
    osm: str  # "w123" or "r456"
    tags: Dict[str, str]
    outer: geo.Ring
    holes: List[geo.Ring] = field(default_factory=list)

    @property
    def area(self) -> float:
        return geo.area(self.outer) - sum(geo.area(h) for h in self.holes)


@dataclass
class Line:
    osm: str
    tags: Dict[str, str]
    pts: List[geo.Point]


@dataclass
class Features:
    buildings: List[Polygon] = field(default_factory=list)
    areas: List[Polygon] = field(default_factory=list)
    roads: List[Line] = field(default_factory=list)
    paths: List[Line] = field(default_factory=list)
    waterways: List[Line] = field(default_factory=list)
    railways: List[Line] = field(default_factory=list)
    power: List[Line] = field(default_factory=list)
    barriers: List[Line] = field(default_factory=list)
    trees: List[Tuple[str, geo.Point, Dict[str, str]]] = field(default_factory=list)
    heritage_points: List[Tuple[str, geo.Point, Dict[str, str]]] = field(default_factory=list)

    def all_polygons(self) -> List[Polygon]:
        return self.buildings + self.areas


def _area_kind(tags: Dict[str, str]) -> Optional[str]:
    for key, allowed in AREA_TAGS.items():
        v = tags.get(key)
        if v and (allowed is None or v in allowed):
            if key == "water":
                return "natural:water"
            return f"{key}:{v}"
    return None


def extract(osm: OsmData, proj: geo.LocalProjection) -> Features:
    f = Features()
    used_in_mp = set()

    def ring_local(node_ids: List[int]) -> geo.Ring:
        pts = [proj.to_local(*osm.nodes[n]) for n in node_ids]
        if len(pts) > 1 and pts[0] == pts[-1]:
            pts = pts[:-1]
        return pts

    # Multipolygon relations first, so their member ways aren't double counted.
    for rel in osm.relations.values():
        if rel.tags.get("type") not in ("multipolygon", "building"):
            continue
        outers = [ref for t, ref, role in rel.members if t == "way" and role in ("outer", "")]
        inners = [ref for t, ref, role in rel.members if t == "way" and role == "inner"]
        o_rings = assemble_rings(osm, outers)
        i_rings = [ring_local(r) for r in assemble_rings(osm, inners)]
        if not o_rings:
            continue
        tags = dict(rel.tags)
        # Old-style multipolygons keep tags on the outer way.
        if len(tags) <= 1 and len(outers) == 1 and outers[0] in osm.ways:
            tags.update(osm.ways[outers[0]].tags)
        is_building = "building" in tags and tags.get("building") != "no"
        kind = None if is_building else _area_kind(tags)
        if not is_building and not kind:
            continue
        for ref in outers:
            if ref in osm.ways and (len(osm.ways[ref].tags) == 0 or osm.ways[ref].tags == {k: v for k, v in osm.ways[ref].tags.items() if k in tags}):
                used_in_mp.add(ref)
        for k, o in enumerate(o_rings):
            outer = ring_local(o)
            holes = [h for h in i_rings if geo.point_in_ring(h[0], outer)]
            poly = Polygon(f"r{rel.id}" + (f".{k}" if len(o_rings) > 1 else ""), tags, outer, holes)
            (f.buildings if is_building else f.areas).append(poly)

    for way in osm.ways.values():
        if way.id in used_in_mp:
            continue
        latlon = osm.way_latlon(way)
        if not latlon or len(latlon) < 2:
            continue
        t = way.tags
        pts = [proj.to_local(*ll) for ll in latlon]
        oid = f"w{way.id}"
        if "building" in t and t.get("building") != "no" and way.closed:
            f.buildings.append(Polygon(oid, t, pts[:-1]))
            continue
        hw = t.get("highway")
        if hw:
            if hw in VEHICLE_ROADS:
                f.roads.append(Line(oid, t, pts))
            elif hw in PATHS:
                if t.get("area") == "yes" and way.closed:
                    f.areas.append(Polygon(oid, {**t, "landuse": "pedestrian"}, pts[:-1]))
                else:
                    f.paths.append(Line(oid, t, pts))
            continue
        if t.get("waterway") in WATERWAY_LINES:
            f.waterways.append(Line(oid, t, pts))
            continue
        if t.get("railway") in ("rail", "light_rail", "tram", "subway", "narrow_gauge") and not way.closed:
            f.railways.append(Line(oid, t, pts))
            continue
        if t.get("power") in ("line", "minor_line", "cable"):
            f.power.append(Line(oid, t, pts))
            continue
        if t.get("natural") == "tree_row":
            for p in _along(pts, 6.0):
                f.trees.append((oid, p, t))
            continue
        if t.get("barrier") in BARRIERS and not _area_kind(t):
            f.barriers.append(Line(oid, t, pts))
            continue
        kind = _area_kind(t)
        if kind and way.closed:
            f.areas.append(Polygon(oid, t, pts[:-1]))
        elif "historic" in t and way.closed:
            f.heritage_points.append((oid, geo.centroid(pts[:-1]), t))

    for nid, t in osm.node_tags.items():
        if t.get("natural") == "tree":
            f.trees.append((f"n{nid}", proj.to_local(*osm.nodes[nid]), t))
        elif "historic" in t:
            f.heritage_points.append((f"n{nid}", proj.to_local(*osm.nodes[nid]), t))
    return f


def _along(pts: List[geo.Point], step: float) -> List[geo.Point]:
    out = []
    carry = 0.0
    for a, b in zip(pts, pts[1:]):
        seg = geo.dist(a, b)
        d = carry
        while d < seg:
            t = d / seg
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
            d += step
        carry = d - seg
    return out


def building_height(tags: Dict[str, str]) -> Tuple[float, Optional[int], str]:
    """(height m, levels, source) where source is tag, levels or default."""
    levels = parse_number(tags.get("building:levels"))
    roof_levels = parse_number(tags.get("roof:levels")) or 0.0
    h = parse_length(tags.get("height")) or parse_length(tags.get("building:height"))
    lv = int(levels) if levels is not None else None
    if h and 1.5 <= h <= 1000:
        return h, lv, "tag"
    if levels is not None and 0 < levels < 200:
        pitched = tags.get("roof:shape") not in (None, "flat")
        return levels * LEVEL_HEIGHT + roof_levels * 2.5 + (1.5 if pitched else 0.5), lv, "levels"
    kind = tags.get("building", "yes")
    return DEFAULT_HEIGHTS.get(kind, DEFAULT_HEIGHT), None, "default"


def is_heritage(tags: Dict[str, str]) -> bool:
    return bool(tags.get("heritage") or tags.get("listed_status") or tags.get("historic")
                or tags.get("building") in ("church", "cathedral", "chapel", "castle")
                or tags.get("HE_ref"))


def road_width(tags: Dict[str, str]) -> float:
    w = parse_length(tags.get("width")) or parse_length(tags.get("est_width"))
    if w and 1 <= w <= 60:
        return w
    hw = tags.get("highway")
    if hw in VEHICLE_ROADS:
        base, lanes = VEHICLE_ROADS[hw]
        tl = parse_number(tags.get("lanes"))
        if tl and hw not in NARROW_ROAD_KINDS:
            return max(base, tl * 3.25)
        if tags.get("oneway") == "yes" and hw in ("residential", "unclassified", "tertiary"):
            return base * 0.75
        return base
    return PATHS.get(hw, 2.0)
