"""Choosing the build plot and rating how awkward it is.

The plan wants real plots that are often not ideal for the brief. This module
measures each plot's real problems (slope, wet or made ground, cramped or odd
shape, poor access, neighbours on the boundary, trees, overhead lines, an
existing building to clear) and turns them into a 1 to 5 difficulty rating.
The contracts thread decides what the rating does to cost and pay; the pack
only carries the facts and a suggested multiplier.
"""

from __future__ import annotations

import math
from typing import Callable, Dict, List, Optional, Sequence, Tuple

from . import geo
from .features import (NARROW_ROAD_KINDS, Features, Polygon, is_heritage, road_width)

CANDIDATE_AREA_KINDS = {
    "landuse:brownfield", "landuse:greenfield", "landuse:construction", "landuse:grass",
    "landuse:meadow", "landuse:vacant", "landuse:flowerbed", "amenity:parking",
    "natural:scrub", "natural:grassland", "leisure:garden", "landuse:village_green",
    "landuse:allotments", "landuse:garages",
}
MADE_GROUND_KINDS = {"landuse:brownfield", "landuse:industrial", "landuse:railway",
                     "landuse:landfill", "landuse:construction", "amenity:parking", "landuse:garages"}
INTERNAL_SERVICE = {"parking_aisle", "driveway", "drive-through"}
# Artificial water (canals, basins) is held in by linings and embankments, so it
# only counts as wet ground when it is right next to the plot.
ARTIFICIAL_WATER = {"canal", "basin", "reservoir", "lock", "moat", "wastewater", "fountain", "reflecting_pool"}
WET_KINDS = {"natural:water", "natural:wetland", "landuse:reservoir", "landuse:basin",
             "waterway:riverbank", "natural:mud"}


# --------------------------------------------------------------------------- #
# Selection

def survey(feat: Features, radius: float, min_area=120.0, max_area=25000.0) -> List[dict]:
    """Lists candidate plots: open areas and existing buildings near the centre."""
    out = []
    for poly in feat.areas:
        kind = _kind(poly)
        if kind not in CANDIDATE_AREA_KINDS:
            continue
        a = poly.area
        c = geo.centroid(poly.outer)
        d = math.hypot(*c)
        if min_area <= a <= max_area and d <= radius * 0.75:
            out.append({"osm": poly.osm, "kind": kind, "area_m2": round(a), "dist_m": round(d),
                        "name": poly.tags.get("name", "")})
    for b in feat.buildings:
        a = b.area
        c = geo.centroid(b.outer)
        d = math.hypot(*c)
        if 60 <= a <= max_area and d <= radius * 0.5:
            out.append({"osm": b.osm, "kind": "building:" + b.tags.get("building", "yes"),
                        "area_m2": round(a), "dist_m": round(d), "name": b.tags.get("name", "")})
    out.sort(key=lambda r: (r["kind"].startswith("building:"), r["dist_m"]))
    return out


def _kind(poly: Polygon) -> str:
    for k in ("landuse", "natural", "leisure", "amenity", "waterway", "man_made"):
        if k in poly.tags:
            return f"{k}:{poly.tags[k]}"
    if "water" in poly.tags:
        return "natural:water"
    return "other"


def nearest_road_angle(feat: Features, p: geo.Point) -> float:
    best, ang = math.inf, 0.0
    for r in feat.roads:
        for a, b in zip(r.pts, r.pts[1:]):
            d = geo.point_segment_dist(p, a, b)
            if d < best:
                best, ang = d, math.atan2(b[1] - a[1], b[0] - a[0])
    return ang


def choose_plot(feat: Features, spec, proj: geo.LocalProjection, radius: float) -> Tuple[geo.Ring, dict]:
    """Returns (outline ring, info) for a plot spec.

    spec forms:
      "auto"
      {"osm": "w123"}                   an OSM area or building outline
      {"osm": "w123", "buffer_m": 4}    building outline grown by a margin (brownfield)
      {"rect": {"width": 20, "depth": 35, "centre": [x, z] | "latlon": [lat, lon],
                "angle_deg": 0 | "align": "road"}}
      {"polygon_latlon": [[lat, lon], ...]}
    """
    if spec in (None, "auto"):
        for poly in sorted(feat.areas, key=lambda p: p.area):
            if _kind(poly) in CANDIDATE_AREA_KINDS and geo.point_in_ring((0, 0), poly.outer) and poly.area <= 25000:
                return list(poly.outer), {"method": "auto-area", "osm": poly.osm}
        spec = {"rect": {"width": 20, "depth": 30, "centre": [0, 0], "align": "road"}}
        info = {"method": "auto-rect"}
    else:
        info = {"method": "spec"}
    if "osm" in spec:
        target = spec["osm"]
        for poly in feat.all_polygons():
            if poly.osm == target:
                ring = list(poly.outer)
                if spec.get("buffer_m"):
                    ring = _grow(ring, float(spec["buffer_m"]))
                info.update({"osm": target})
                return ring, info
        raise ValueError(f"plot {target} not found in the downloaded data")
    if "rect" in spec:
        r = spec["rect"]
        if "latlon" in r:
            cx, cz = proj.to_local(*r["latlon"])
        else:
            cx, cz = r.get("centre", [0, 0])
        if r.get("align") == "road":
            ang = nearest_road_angle(feat, (cx, cz))
        else:
            ang = math.radians(r.get("angle_deg", 0.0))
        return geo.rect(cx, cz, float(r["width"]), float(r["depth"]), ang), info
    if "polygon_latlon" in spec:
        return [proj.to_local(lat, lon) for lat, lon in spec["polygon_latlon"]], info
    raise ValueError(f"bad plot spec: {spec}")


def _grow(ring: geo.Ring, margin: float) -> geo.Ring:
    """Grows a ring outwards by roughly margin metres (minimum-area-rect based,
    good enough for a demolition plot around an existing building)."""
    w, d, ang, _ = geo.min_area_rect(ring)
    c = geo.centroid(ring)
    return geo.rect(c[0], c[1], w + 2 * margin, d + 2 * margin, ang)


# --------------------------------------------------------------------------- #
# Assessment

def _boundary_samples(ring: Sequence[geo.Point], step: float = 1.0) -> List[geo.Point]:
    pts = []
    n = len(ring)
    for i in range(n):
        a, b = ring[i], ring[(i + 1) % n]
        seg = geo.dist(a, b)
        k = max(1, int(seg / step))
        for j in range(k):
            t = j / k
            pts.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return pts


def _underground(tags) -> bool:
    return (tags.get("tunnel", "no") != "no" or tags.get("layer", "0").strip().startswith("-")
            or tags.get("railway") == "subway" or tags.get("location") == "underground")


def _along_line(pts, step):
    out = []
    for a, b in zip(pts, pts[1:]):
        k = max(1, int(geo.dist(a, b) / step))
        out += [(a[0] + (b[0] - a[0]) * i / k, a[1] + (b[1] - a[1]) * i / k) for i in range(k)]
    if pts:
        out.append(pts[-1])
    return out


def _plane_fit(samples: List[Tuple[float, float, float]]) -> Tuple[float, float]:
    """Least-squares plane y = a x + b z + c. Returns (gradient, aspect_rad)
    where gradient is rise/run and aspect is the downhill direction from +x."""
    n = len(samples)
    if n < 3:
        return 0.0, 0.0
    mx = sum(s[0] for s in samples) / n
    mz = sum(s[1] for s in samples) / n
    my = sum(s[2] for s in samples) / n
    sxx = sum((s[0] - mx) ** 2 for s in samples)
    szz = sum((s[1] - mz) ** 2 for s in samples)
    sxz = sum((s[0] - mx) * (s[1] - mz) for s in samples)
    sxy = sum((s[0] - mx) * (s[2] - my) for s in samples)
    szy = sum((s[1] - mz) * (s[2] - my) for s in samples)
    det = sxx * szz - sxz * sxz
    if abs(det) < 1e-9:
        return 0.0, 0.0
    a = (sxy * szz - szy * sxz) / det
    b = (szy * sxx - sxy * sxz) / det
    return math.hypot(a, b), math.atan2(-b, -a)


def _compass(angle_rad: float) -> str:
    # angle from +x (east), z south. Convert to bearing from north, clockwise.
    bearing = (math.degrees(angle_rad) + 90.0) % 360.0
    names = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
    return names[int((bearing + 22.5) // 45) % 8]


def _band(value: float, bands: Sequence[float]) -> int:
    """Severity 0..len(bands) for a value against ascending thresholds."""
    s = 0
    for t in bands:
        if value >= t:
            s += 1
    return s


def assess(ring: geo.Ring, feat: Features, height_at: Callable[[float, float], float],
           plot_osm: Optional[str] = None) -> dict:
    """Measures the plot and returns the pack's "plot" section, minus outline."""
    factors: List[dict] = []

    def add(fid: str, severity: int, label: str, detail: str, **metrics):
        if severity > 0:
            factors.append({"id": fid, "severity": min(3, severity), "label": label,
                            "detail": detail, "metrics": metrics})

    a = geo.area(ring)
    w, d, ang, mbr = geo.min_area_rect(ring)
    compact = a / mbr if mbr else 1.0
    cen = geo.centroid(ring)

    # Ground levels across the plot.
    xs = [p[0] for p in ring]
    zs = [p[1] for p in ring]
    samples = []
    step = max(2.0, math.sqrt(a) / 12)
    x = min(xs)
    while x <= max(xs):
        z = min(zs)
        while z <= max(zs):
            if geo.point_in_ring((x, z), ring):
                samples.append((x, z, height_at(x, z)))
            z += step
        x += step
    for p in ring:
        samples.append((p[0], p[1], height_at(*p)))
    ys = [s[2] for s in samples]
    grad, aspect = _plane_fit(samples)
    slope_pct = grad * 100
    relief = max(ys) - min(ys)
    add("slope", _band(slope_pct, (3.0, 7.0, 14.0)), "Sloping site",
        f"Falls about {slope_pct:.0f}% to the {_compass(aspect)}, {relief:.1f} m across the plot. "
        "Expect cut and fill, retaining walls or stepped foundations.",
        slope_pct=round(slope_pct, 1), relief_m=round(relief, 2), downhill=_compass(aspect))

    # Shape.
    shape_sev = _band(1 - compact, (0.25, 0.45)) + (1 if w / max(d, 0.1) > 3 else 0) + (1 if d < 9 else 0)
    shape_bits = []
    if compact < 0.75:
        shape_bits.append(f"irregular outline (fills {compact * 100:.0f}% of its bounding rectangle)")
    if w / max(d, 0.1) > 3:
        shape_bits.append(f"long and thin ({w:.0f} by {d:.0f} m)")
    if d < 9:
        shape_bits.append(f"only {d:.1f} m at its narrowest")
    add("shape", shape_sev, "Awkward plot shape", "; ".join(shape_bits).capitalize() + ".",
        compactness=round(compact, 2), width_m=round(w, 1), depth_m=round(d, 1))

    # Access: vehicle road frontage.
    bsamples = _boundary_samples(ring, 1.0)
    best_road = None
    frontage = 0.0
    road_hits: Dict[str, dict] = {}
    for r in feat.roads:
        if r.tags.get("service") in INTERNAL_SERVICE or _underground(r.tags):
            continue
        rw = road_width(r.tags)
        reach = rw / 2 + 4.0  # carriageway half width plus a pavement or verge
        dmin = geo.line_line_dist(r.pts, ring, False, True)
        if dmin <= reach:
            hits = sum(1 for p in bsamples
                       if min(geo.point_segment_dist(p, a_, b_) for a_, b_ in zip(r.pts, r.pts[1:])) <= reach)
            info = road_hits.setdefault(r.tags.get("name") or r.osm, {
                "road": r.osm, "name": r.tags.get("name", ""), "kind": r.tags.get("highway"),
                "width_m": round(rw, 1), "frontage_m": 0.0})
            info["frontage_m"] = round(info["frontage_m"] + hits * 1.0, 1)
            frontage += hits
        if best_road is None or dmin < best_road[0]:
            best_road = (dmin, r)
    access = sorted(road_hits.values(), key=lambda r: -r["frontage_m"])
    if not access:
        dist_txt = f"{best_road[0]:.0f} m away" if best_road else "none in range"
        add("access", 3 if not best_road or best_road[0] > 30 else 2, "No road frontage",
            f"No vehicle road touches the plot (nearest {dist_txt}). Deliveries and cranes need a "
            "temporary haul road or a lift over neighbours.",
            nearest_road_m=round(best_road[0], 1) if best_road else None)
    else:
        sev = 0
        bits = []
        if all(r["kind"] in NARROW_ROAD_KINDS or r["width_m"] < 4.5 for r in access):
            sev += 2
            bits.append(f"only a narrow {access[0]['kind'].replace('_', ' ')} road ({access[0]['width_m']} m wide)")
        if len(access) == 1:
            sev += 1
            bits.append("a single road")
        if frontage < 8:
            sev += 1
            bits.append(f"just {frontage:.0f} m of road frontage")
        add("access", sev, "Tight access", "Access is by " + ", ".join(bits) + ". Limits crane and delivery sizes.",
            frontage_m=round(frontage, 1), roads=len(access))

    # Roads or public paths running through the plot.
    crossing = []
    for ln in feat.roads + feat.paths:
        if ln.tags.get("service") in INTERNAL_SERVICE or _underground(ln.tags):
            continue
        if any(geo.point_in_ring(q, ring) for q in _along_line(ln.pts, 2.0)):
            crossing.append(ln.tags.get("name") or ln.tags.get("highway", "path").replace("_", " "))
    if crossing:
        add("right_of_way", 2, "Road or path crosses the plot",
            "Crossed by " + ", ".join(dict.fromkeys(crossing)) + ". It must be diverted or kept open.",
            count=len(crossing))

    # Neighbours on or near the boundary, and protected ones.
    on_plot = []
    neighbours = []
    for b in feat.buildings:
        if b.osm == plot_osm:
            on_plot.append(b)
            continue
        if math.hypot(*(geo.centroid(b.outer)[i] - cen[i] for i in (0, 1))) > 120 + math.sqrt(a):
            continue
        frac = geo.ring_inside_fraction(b.outer, ring)
        if frac >= 0.5:
            on_plot.append(b)
            continue
        dmin = 0.0 if frac > 0.02 else geo.line_line_dist(b.outer, ring, True, True)
        if dmin <= 25:
            neighbours.append((dmin, b))
    neighbours.sort(key=lambda t: t[0])
    close = [n for n in neighbours if n[0] <= 6]
    if close:
        nearest = close[0][0]
        sev = 3 if nearest < 0.6 else (2 if nearest < 2.5 else 1)
        if len(close) >= 3:
            sev += 1
        add("neighbours", sev, "Neighbours close to the boundary",
            f"{len(close)} building(s) within 6 m of the boundary, the nearest "
            + ("right on it (party wall or shared boundary)" if nearest < 0.6 else f"{nearest:.1f} m away")
            + ". Needs careful excavation, scaffolding and demolition.",
            count=len(close), nearest_m=round(nearest, 2))
    protected = [n for n in neighbours if is_heritage(n[1].tags)]
    protected += [(geo.dist(p, cen), None) for _, p, t in feat.heritage_points
                  if geo.point_in_ring(p, ring) or min(geo.point_segment_dist(p, a_, b_)
                     for a_, b_ in zip(ring, ring[1:] + ring[:1])) < 20]
    if protected:
        add("heritage", 2 if protected[0][0] < 8 else 1, "Protected neighbours",
            f"{len(protected)} listed or historic feature(s) within 25 m. Vibration and damage "
            "limits apply during build and demolition.", count=len(protected))

    # Existing buildings on the plot (brownfield).
    if on_plot:
        foot = sum(b.area for b in on_plot)
        add("existing_buildings", 2 if foot > 80 else 1, "Existing buildings to clear",
            f"{len(on_plot)} building(s) ({foot:.0f} m2 of footprint) stand on the plot and must be "
            "demolished and cleared first.", count=len(on_plot), footprint_m2=round(foot))

    # Trees.
    ring_closed = list(ring) + [ring[0]]
    near_trees = []
    for tid, p, t in feat.trees:
        inside = geo.point_in_ring(p, ring)
        if inside or min(geo.point_segment_dist(p, a_, b_) for a_, b_ in zip(ring_closed, ring_closed[1:])) <= 4:
            near_trees.append((tid, inside, t))
    if near_trees:
        prot = [t for t in near_trees if t[2].get("protected") == "yes" or t[2].get("denotation") in
                ("natural_monument", "landmark")]
        inside_n = sum(1 for t in near_trees if t[1])
        sev = (1 if near_trees else 0) + (1 if len(near_trees) > 4 else 0) + (1 if prot else 0)
        add("trees", sev, "Trees to protect",
            f"{inside_n} tree(s) on the plot and {len(near_trees) - inside_n} on the boundary"
            + (f", {len(prot)} protected" if prot else "") + ". Root zones limit where foundations can go.",
            on_plot=inside_n, boundary=len(near_trees) - inside_n, protected=len(prot))
    for poly in feat.areas:
        if _kind(poly) in ("natural:wood", "landuse:forest") and poly.osm != plot_osm:
            if geo.line_line_dist(poly.outer, ring, True, True) == 0.0:
                if not any(f["id"] == "trees" for f in factors):
                    add("trees", 1, "Woodland edge", "The plot runs into woodland.")
                break

    # Overhead and buried lines.
    worst = 0
    lines_txt = []
    for pl in feat.power:
        dmin = geo.line_line_dist(pl.pts, ring, False, True)
        kind = pl.tags.get("power")
        if kind == "cable":
            if dmin <= 3:
                worst = max(worst, 1)
                lines_txt.append("a buried power cable beside the plot")
            continue
        lim = 25 if kind == "line" else 10
        if dmin <= lim:
            sev = (3 if dmin == 0 else 2) if kind == "line" else (2 if dmin == 0 else 1)
            worst = max(worst, sev)
            lines_txt.append(("a high voltage line" if kind == "line" else "an overhead power line")
                             + (" crossing the plot" if dmin == 0 else f" {dmin:.0f} m away"))
    add("overhead_lines", worst, "Overhead or buried lines",
        ("There is " + " and ".join(dict.fromkeys(lines_txt)) + ". Crane slewing and height limits apply.")
        if lines_txt else "")

    for rl in feat.railways:
        if _underground(rl.tags):
            continue
        dmin = geo.line_line_dist(rl.pts, ring, False, True)
        if dmin <= 20:
            add("railway", 2 if dmin < 8 else 1, "Next to a railway",
                f"Railway {dmin:.0f} m from the boundary. Possessions and vibration limits apply.",
                distance_m=round(dmin, 1))
            break

    # Ground conditions.
    wet_reasons = []
    made = False
    mean_y = sum(ys) / len(ys)
    low = []  # (height above water, distance, what)
    for poly in feat.areas:
        kind = _kind(poly)
        if kind in WET_KINDS:
            artificial = (poly.tags.get("water") in ARTIFICIAL_WATER or kind in ("landuse:reservoir", "landuse:basin"))
            what = poly.tags.get("water") or kind.split(":")[1]
            dmin = geo.line_line_dist(poly.outer, ring, True, True)
            if dmin <= (5 if artificial else 40):
                wet_reasons.append(what + (" on the plot" if dmin == 0 else f" {dmin:.0f} m away"))
            elif not artificial and dmin <= 200:
                low.append((mean_y - height_at(*geo.centroid(poly.outer)), dmin, what))
        if kind in MADE_GROUND_KINDS and poly.osm != plot_osm:
            if geo.ring_inside_fraction(ring, poly.outer) > 0.3:
                made = True
        if poly.osm == plot_osm and kind in MADE_GROUND_KINDS:
            made = True
    for wl in feat.waterways:
        if _underground(wl.tags):
            continue  # culverted, like London's buried rivers
        kind = wl.tags.get("waterway")
        artificial = kind in ("canal", "drain")
        dmin = geo.line_line_dist(wl.pts, ring, False, True)
        if dmin <= (5 if artificial else 40):
            wet_reasons.append(f"{kind} {dmin:.0f} m away" if dmin else f"{kind} crossing the plot")
        elif not artificial and kind in ("river", "stream") and dmin <= 200:
            low.append((mean_y - min(height_at(*p) for p in wl.pts), dmin, kind))
    low = [l for l in low if l[0] < 2.0]
    if low:
        h, dmin, what = min(low, key=lambda l: l[1])
        wet_reasons.append(f"only {max(h, 0):.1f} m above the {what} {dmin:.0f} m away")
    if on_plot:
        made = True
    wet = bool(wet_reasons)
    soil = "soft_wet" if wet else ("made_ground" if made else "firm")
    if wet:
        add("ground", 3 if any("on the plot" in r or "crossing" in r for r in wet_reasons) else 2,
            "Poor, wet ground", "Likely soft or waterlogged ground ("
            + "; ".join(list(dict.fromkeys(wet_reasons))[:3]) + "). Plan for piles or a raft.",
            reasons=list(dict.fromkeys(wet_reasons)))
    elif made:
        add("ground", 1, "Made ground", "Previously developed land: buried foundations, fill and "
            "possible contamination. Trial pits recommended.")

    score = sum(f["severity"] for f in factors)
    rating = 1 if score <= 1 else 2 if score <= 3 else 3 if score <= 6 else 4 if score <= 9 else 5
    factors.sort(key=lambda f: -f["severity"])
    return {
        "area_m2": round(a, 1),
        "perimeter_m": round(geo.perimeter(ring), 1),
        "bounding_rect": {"width_m": round(w, 2), "depth_m": round(d, 2),
                          "angle_deg": round(math.degrees(ang) % 180, 1)},
        "compactness": round(compact, 3),
        "ground": {"min_y": round(min(ys), 2), "max_y": round(max(ys), 2), "mean_y": round(mean_y, 2),
                   "slope_pct": round(slope_pct, 1), "downhill": _compass(aspect),
                   "soil": soil, "wet": wet, "piles_suggested": wet or (made and slope_pct > 10)},
        "access": access,
        "existing_buildings": [b.osm for b in on_plot],
        "difficulty": {"rating": rating, "score": score,
                       "cost_multiplier_hint": round(1 + 0.06 * score, 2),
                       "factors": factors},
    }
