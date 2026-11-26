"""Builds a site pack (format version 1, see tools/osm/FORMAT.md)."""

from __future__ import annotations

import base64
import datetime as _dt
import json
import math
import os
import struct
from typing import Dict, List, Optional

from . import geo
from .elevation import ATTRIBUTION as TERRAIN_ATTRIBUTION, FlatSampler, TerrainSampler
from .features import (Features, building_height, extract, is_heritage, parse_length, parse_number,
                       road_width, WATERWAY_LINES)
from .osm import fetch_osm, parse_osm_xml
from .plot import assess, choose_plot

FORMAT_ID = "housebuilder.sitepack"
FORMAT_VERSION = 1
OSM_ATTRIBUTION = "© OpenStreetMap contributors"
SIMPLIFY = {"building": 0.25, "area": 0.75, "line": 0.5, "plot": 0.1}


class TerrainGrid:
    """Regular height grid in local metres; bilinear lookups."""

    def __init__(self, x0: float, z0: float, spacing: float, nx: int, nz: int, heights: List[float]):
        self.x0, self.z0, self.spacing, self.nx, self.nz = x0, z0, spacing, nx, nz
        self.h = heights

    @classmethod
    def sample(cls, sampler, proj: geo.LocalProjection, radius: float, spacing: float) -> "TerrainGrid":
        half = math.ceil(radius / spacing) * spacing
        n = int(round(2 * half / spacing)) + 1
        heights = []
        for j in range(n):
            z = -half + j * spacing
            for i in range(n):
                x = -half + i * spacing
                heights.append(sampler.height(*proj.to_latlon(x, z)))
        return cls(-half, -half, spacing, n, n, heights)

    def at(self, x: float, z: float) -> float:
        fx = (x - self.x0) / self.spacing
        fz = (z - self.z0) / self.spacing
        fx = min(max(fx, 0.0), self.nx - 1.000001)
        fz = min(max(fz, 0.0), self.nz - 1.000001)
        i, j = int(fx), int(fz)
        tx, tz = fx - i, fz - j
        h = self.h
        n = self.nx
        return (h[j * n + i] * (1 - tx) * (1 - tz) + h[j * n + i + 1] * tx * (1 - tz)
                + h[(j + 1) * n + i] * (1 - tx) * tz + h[(j + 1) * n + i + 1] * tx * tz)

    def shifted(self, dy: float) -> "TerrainGrid":
        return TerrainGrid(self.x0, self.z0, self.spacing, self.nx, self.nz, [v + dy for v in self.h])


def _within(pts, radius: float) -> bool:
    return any(math.hypot(*p) <= radius for p in pts)


def _rpts(pts, tol, closed):
    return geo.round_pts(geo.simplify(pts, tol, closed=closed))


def build_site(site: dict, cache_dir: str, *, spacing: float = 4.0, elevation: bool = True,
               source: str = "auto", log=print) -> dict:
    lat, lon = float(site["lat"]), float(site["lon"])
    radius = float(site.get("radius_m", 300))
    proj = geo.LocalProjection(lat, lon)

    log(f"[{site['id']}] fetching OSM data")
    raw = fetch_osm(proj.bbox_deg(radius * 1.1), os.path.join(cache_dir, "osm"), source=source, log=log)
    sampler = TerrainSampler(os.path.join(cache_dir, "terrain"), log=log) if elevation else FlatSampler()
    return build_from_osm(site, raw, sampler, spacing=spacing, elevation=elevation, log=log)


def build_from_osm(site: dict, raw: bytes, sampler, *, spacing: float = 4.0, elevation: bool = True,
                   log=print) -> dict:
    """Builds a pack from OSM XML already in hand and a height sampler with a
    height(lat, lon) method. build_site() wraps this with the downloads."""
    lat, lon = float(site["lat"]), float(site["lon"])
    radius = float(site.get("radius_m", 300))
    proj = geo.LocalProjection(lat, lon)
    osm = parse_osm_xml(raw)
    feat = extract(osm, proj)
    log(f"  {len(feat.buildings)} buildings, {len(feat.roads)} roads, {len(feat.areas)} areas, "
        f"{len(feat.trees)} trees")

    log(f"[{site['id']}] sampling terrain")
    grid_abs = TerrainGrid.sample(sampler, proj, radius, spacing)

    ring, plot_info = choose_plot(feat, site.get("plot", "auto"), proj, radius)
    ring = geo.make_ccw_on_map(geo.simplify(ring, SIMPLIFY["plot"], closed=True))
    datum = sum(grid_abs.at(*p) for p in _interior_samples(ring)) / max(1, len(_interior_samples(ring)))
    grid = grid_abs.shifted(-datum)
    plot_osm = plot_info.get("osm")
    plot = {"outline": geo.round_pts(ring), "source": plot_info}
    plot.update(assess(ring, feat, grid.at, plot_osm=plot_osm))
    if site.get("notes"):
        plot["notes"] = site["notes"]

    on_plot = set(plot["existing_buildings"])

    buildings = []
    for b in feat.buildings:
        if not _within(b.outer, radius):
            continue
        h, levels, hsrc = building_height(b.tags)
        outer = geo.make_ccw_on_map(geo.simplify(b.outer, SIMPLIFY["building"], closed=True))
        if len(outer) < 3:
            continue
        base = min(grid.at(*p) for p in outer)
        top_ground = max(grid.at(*p) for p in outer)
        entry = {
            "id": b.osm,
            "kind": b.tags.get("building", "yes"),
            "outline": geo.round_pts(outer),
            "base_y": round(base, 2),
            "ground_max_y": round(top_ground, 2),
            "height_m": round(h, 2),
            "height_source": hsrc,
            "on_plot": b.osm in on_plot,
            "protected": is_heritage(b.tags),
        }
        if b.holes:
            entry["holes"] = [geo.round_pts(geo.make_cw_on_map(geo.simplify(hh, SIMPLIFY["building"], True)))
                              for hh in b.holes]
        if levels is not None:
            entry["levels"] = levels
        mh = parse_length(b.tags.get("min_height"))
        if mh:
            entry["min_height_m"] = round(mh, 2)
        for k_src, k_dst in (("roof:shape", "roof_shape"), ("name", "name"),
                             ("building:material", "material"), ("addr:housenumber", "house_number")):
            if b.tags.get(k_src):
                entry[k_dst] = b.tags[k_src]
        buildings.append(entry)

    def line_entries(lines, kind_key, width_fn=None, extra=None):
        out = []
        for ln in lines:
            for run in geo.clip_polyline_to_circle(ln.pts, radius):
                pts = _rpts(run, SIMPLIFY["line"], False)
                e = {"id": ln.osm, "kind": ln.tags.get(kind_key), "line": pts}
                if width_fn:
                    e["width_m"] = round(width_fn(ln.tags), 2)
                if extra:
                    e.update(extra(ln.tags))
                out.append(e)
        return out

    def road_extra(t):
        e = {}
        for k in ("name", "surface", "ref"):
            if t.get(k):
                e[k] = t[k]
        if t.get("oneway") in ("yes", "-1"):
            e["oneway"] = t["oneway"] == "yes" or -1
        lanes = parse_number(t.get("lanes"))
        if lanes:
            e["lanes"] = int(lanes)
        if t.get("bridge") and t["bridge"] != "no":
            e["bridge"] = True
        if t.get("tunnel") and t["tunnel"] != "no":
            e["tunnel"] = True
        if t.get("sidewalk") or t.get("footway"):
            e["sidewalk"] = t.get("sidewalk") or t.get("footway")
        layer = parse_number(t.get("layer"))
        if layer:
            e["layer"] = int(layer)
        return e

    areas = []
    for a in feat.areas:
        if not _within(a.outer, radius) and not geo.point_in_ring((0, 0), a.outer):
            continue
        kind = next((f"{k}:{a.tags[k]}" for k in ("landuse", "natural", "leisure", "amenity", "waterway", "man_made")
                     if k in a.tags), "natural:water" if "water" in a.tags else "other")
        outer = geo.make_ccw_on_map(geo.simplify(a.outer, SIMPLIFY["area"], closed=True))
        if len(outer) < 3:
            continue
        e = {"id": a.osm, "kind": kind, "outline": geo.round_pts(outer)}
        if a.holes:
            e["holes"] = [geo.round_pts(geo.make_cw_on_map(geo.simplify(h, SIMPLIFY["area"], True))) for h in a.holes]
        if a.tags.get("name"):
            e["name"] = a.tags["name"]
        if a.tags.get("surface"):
            e["surface"] = a.tags["surface"]
        areas.append(e)

    trees = []
    for tid, p, t in feat.trees:
        if math.hypot(*p) > radius:
            continue
        e = {"id": tid, "pos": [round(p[0], 2), round(p[1], 2)], "base_y": round(grid.at(*p), 2),
             "height_m": round(parse_length(t.get("height")) or 9.0, 1),
             "crown_m": round(parse_length(t.get("diameter_crown")) or 6.0, 1)}
        if t.get("leaf_type"):
            e["leaf_type"] = t["leaf_type"]
        if t.get("protected") == "yes" or t.get("denotation") in ("natural_monument", "landmark"):
            e["protected"] = True
        trees.append(e)

    def power_extra(t):
        dflt = {"line": 15.0, "minor_line": 8.0, "cable": -1.0}.get(t.get("power"), 8.0)
        e = {"height_m": round(parse_length(t.get("height")) or dflt, 1)}
        if t.get("voltage"):
            e["voltage"] = t["voltage"]
        return e

    def water_width(t):
        return parse_length(t.get("width")) or WATERWAY_LINES.get(t.get("waterway"), 2.0)

    def barrier_extra(t):
        dflt = {"wall": 1.8, "fence": 1.5, "hedge": 1.5, "retaining_wall": 1.5, "city_wall": 5.0}.get(t.get("barrier"), 1.0)
        return {"height_m": round(parse_length(t.get("height")) or dflt, 1)}

    terrain_bytes = b"".join(struct.pack("<f", v) for v in grid.h)
    pack = {
        "format": FORMAT_ID,
        "version": FORMAT_VERSION,
        "id": site["id"],
        "name": site.get("name", site["id"]),
        "description": site.get("description", ""),
        "suited_to": site.get("suited_to", []),
        "attribution": [OSM_ATTRIBUTION] + ([TERRAIN_ATTRIBUTION] if elevation else []),
        "licence": {
            "osm_derived": "ODbL-1.0",
            "note": "Derived from OpenStreetMap data, available under the Open Database Licence. "
                    "Show '© OpenStreetMap contributors' wherever this site is used.",
        },
        "generator": {"tool": "tools/osm/sitepack", "version": FORMAT_VERSION,
                      "created": _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                      "osm_source": "cached download of OSM XML", "simplify_m": SIMPLIFY},
        "origin": {"lat": lat, "lon": lon, "elevation_m": round(datum, 2)},
        "axes": "metres; x east, y up, z south (-z is north); y = 0 is the plot's mean ground level",
        "radius_m": radius,
        "terrain": {
            "origin": [grid.x0, grid.z0],
            "spacing_m": spacing,
            "size": [grid.nx, grid.nz],
            "min_y": round(min(grid.h), 2),
            "max_y": round(max(grid.h), 2),
            "sea_level_y": round(-datum, 2),
            "encoding": "float32le, row-major, rows run +z (north to south), columns run +x (west to east)",
            "heights_b64": base64.b64encode(terrain_bytes).decode("ascii"),
            "source": "terrain tiles" if elevation else "flat",
        },
        "plot": plot,
        "buildings": buildings,
        "roads": line_entries(feat.roads, "highway", road_width, road_extra),
        "paths": line_entries(feat.paths, "highway", road_width, road_extra),
        "railways": line_entries(feat.railways, "railway", None,
                                 lambda t: {"tunnel": True} if t.get("tunnel", "no") != "no" else {}),
        "waterways": line_entries(feat.waterways, "waterway", water_width),
        "areas": areas,
        "trees": trees,
        "power_lines": line_entries(feat.power, "power", None, power_extra),
        "barriers": line_entries(feat.barriers, "barrier", None, barrier_extra),
    }
    d = plot["difficulty"]
    log(f"[{site['id']}] plot {plot['area_m2']:.0f} m2, difficulty {d['rating']}/5 "
        f"({', '.join(f['id'] for f in d['factors']) or 'no issues'})")
    return pack


def _interior_samples(ring):
    xs = [p[0] for p in ring]
    zs = [p[1] for p in ring]
    step = max(1.0, math.sqrt(geo.area(ring)) / 10)
    out = list(ring)
    x = min(xs)
    while x <= max(xs):
        z = min(zs)
        while z <= max(zs):
            if geo.point_in_ring((x, z), ring):
                out.append((x, z))
            z += step
        x += step
    return out


def write_pack(pack: dict, out_dir: str) -> str:
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"{pack['id']}.sitepack.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(pack, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    return path


def summary(pack: dict) -> str:
    p = pack["plot"]
    d = p["difficulty"]
    lines = [
        f"{pack['name']} ({pack['id']})",
        f"  origin {pack['origin']['lat']:.5f}, {pack['origin']['lon']:.5f}, {pack['origin']['elevation_m']} m",
        f"  {len(pack['buildings'])} buildings, {len(pack['roads'])} road runs, {len(pack['areas'])} areas, "
        f"{len(pack['trees'])} trees, terrain {pack['terrain']['size'][0]}x{pack['terrain']['size'][1]} "
        f"@ {pack['terrain']['spacing_m']} m, relief {pack['terrain']['max_y'] - pack['terrain']['min_y']:.1f} m",
        f"  plot {p['area_m2']:.0f} m2, {p['bounding_rect']['width_m']:.0f} x {p['bounding_rect']['depth_m']:.0f} m, "
        f"slope {p['ground']['slope_pct']}%, soil {p['ground']['soil']}",
        f"  difficulty {d['rating']}/5 (score {d['score']}, cost x{d['cost_multiplier_hint']})",
    ]
    for f in d["factors"]:
        lines.append(f"    [{f['severity']}] {f['label']}: {f['detail']}")
    return "\n".join(lines)
