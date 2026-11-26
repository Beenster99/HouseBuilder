"""Small 2D geometry helpers. Pure Python, no dependencies.

All plan coordinates are (x, z) pairs in metres, using the game's axes:
x points east, z points south (so -z is north, matching Godot's -Z forward).
"""

from __future__ import annotations

import math
from typing import Iterable, List, Sequence, Tuple

Point = Tuple[float, float]
Ring = List[Point]

# WGS84
_A = 6378137.0
_F = 1 / 298.257223563
_E2 = _F * (2 - _F)


class LocalProjection:
    """Projects lat/lon to local metres around an origin.

    Uses the local radii of curvature at the origin (an equirectangular
    tangent approximation). Over a 300 m radius the error is well under 1 cm,
    far below OSM's own accuracy.
    """

    def __init__(self, lat0: float, lon0: float):
        self.lat0 = lat0
        self.lon0 = lon0
        phi = math.radians(lat0)
        s = math.sin(phi)
        w = math.sqrt(1 - _E2 * s * s)
        self.m_per_deg_lat = math.radians(1) * _A * (1 - _E2) / (w ** 3)
        self.m_per_deg_lon = math.radians(1) * _A * math.cos(phi) / w

    def to_local(self, lat: float, lon: float) -> Point:
        east = (lon - self.lon0) * self.m_per_deg_lon
        north = (lat - self.lat0) * self.m_per_deg_lat
        return (east, -north)

    def to_latlon(self, x: float, z: float) -> Tuple[float, float]:
        lat = self.lat0 + (-z) / self.m_per_deg_lat
        lon = self.lon0 + x / self.m_per_deg_lon
        return (lat, lon)

    def bbox_deg(self, radius_m: float) -> Tuple[float, float, float, float]:
        """(south, west, north, east) bounding box of a radius in degrees."""
        dlat = radius_m / self.m_per_deg_lat
        dlon = radius_m / self.m_per_deg_lon
        return (self.lat0 - dlat, self.lon0 - dlon, self.lat0 + dlat, self.lon0 + dlon)


def dist(a: Point, b: Point) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def point_segment_dist(p: Point, a: Point, b: Point) -> float:
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    l2 = dx * dx + dz * dz
    if l2 == 0:
        return dist(p, a)
    t = ((p[0] - ax) * dx + (p[1] - az) * dz) / l2
    t = max(0.0, min(1.0, t))
    return math.hypot(p[0] - (ax + t * dx), p[1] - (az + t * dz))


def _segments(pts: Sequence[Point], closed: bool):
    n = len(pts)
    if n < 2:
        return
    last = n if closed else n - 1
    for i in range(last):
        yield pts[i], pts[(i + 1) % n]


def _seg_intersect(p1: Point, p2: Point, p3: Point, p4: Point) -> bool:
    def orient(a, b, c):
        v = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
        return 0 if abs(v) < 1e-12 else (1 if v > 0 else -1)

    o1, o2 = orient(p1, p2, p3), orient(p1, p2, p4)
    o3, o4 = orient(p3, p4, p1), orient(p3, p4, p2)
    if o1 != o2 and o3 != o4:
        return True
    return False


def line_line_dist(a: Sequence[Point], b: Sequence[Point], a_closed=False, b_closed=False) -> float:
    """Minimum distance between two polylines (or rings). 0 if they cross."""
    best = math.inf
    segs_a = list(_segments(a, a_closed))
    segs_b = list(_segments(b, b_closed))
    if not segs_a:
        segs_a = [(a[0], a[0])]
    if not segs_b:
        segs_b = [(b[0], b[0])]
    for p1, p2 in segs_a:
        for p3, p4 in segs_b:
            if _seg_intersect(p1, p2, p3, p4):
                return 0.0
            best = min(best,
                       point_segment_dist(p1, p3, p4), point_segment_dist(p2, p3, p4),
                       point_segment_dist(p3, p1, p2), point_segment_dist(p4, p1, p2))
    return best


def point_in_ring(p: Point, ring: Sequence[Point]) -> bool:
    x, z = p
    inside = False
    n = len(ring)
    j = n - 1
    for i in range(n):
        xi, zi = ring[i]
        xj, zj = ring[j]
        if (zi > z) != (zj > z):
            xc = (xj - xi) * (z - zi) / (zj - zi) + xi
            if x < xc:
                inside = not inside
        j = i
    return inside


def point_in_polygon(p: Point, outer: Sequence[Point], holes: Iterable[Sequence[Point]] = ()) -> bool:
    if not point_in_ring(p, outer):
        return False
    return not any(point_in_ring(p, h) for h in holes)


def signed_area(ring: Sequence[Point]) -> float:
    """Shoelace area in the x/z plane. Positive when the ring is clockwise
    as seen on a north-up map (because z points south)."""
    s = 0.0
    n = len(ring)
    for i in range(n):
        x1, z1 = ring[i]
        x2, z2 = ring[(i + 1) % n]
        s += x1 * z2 - x2 * z1
    return s / 2.0


def area(ring: Sequence[Point]) -> float:
    return abs(signed_area(ring))


def centroid(ring: Sequence[Point]) -> Point:
    a = signed_area(ring)
    if abs(a) < 1e-9:
        n = len(ring)
        return (sum(p[0] for p in ring) / n, sum(p[1] for p in ring) / n)
    cx = cz = 0.0
    n = len(ring)
    for i in range(n):
        x1, z1 = ring[i]
        x2, z2 = ring[(i + 1) % n]
        c = x1 * z2 - x2 * z1
        cx += (x1 + x2) * c
        cz += (z1 + z2) * c
    return (cx / (6 * a), cz / (6 * a))


def perimeter(pts: Sequence[Point], closed=True) -> float:
    return sum(dist(a, b) for a, b in _segments(pts, closed))


def make_ccw_on_map(ring: Ring) -> Ring:
    """Orient a ring counter-clockwise as seen on a north-up map
    (negative signed area in x/z, since z points south)."""
    return ring if signed_area(ring) < 0 else list(reversed(ring))


def make_cw_on_map(ring: Ring) -> Ring:
    return ring if signed_area(ring) > 0 else list(reversed(ring))


def simplify(pts: Sequence[Point], tolerance: float, closed: bool = False) -> List[Point]:
    """Douglas-Peucker simplification. Keeps at least 3 points for rings."""
    pts = list(pts)
    if closed and len(pts) > 1 and pts[0] == pts[-1]:
        pts = pts[:-1]
    if len(pts) <= 3 or tolerance <= 0:
        return pts
    if closed:
        # Split the ring at the vertex farthest from the first one.
        far = max(range(len(pts)), key=lambda i: dist(pts[0], pts[i]))
        a = _dp(pts[: far + 1], tolerance)
        b = _dp(pts[far:] + [pts[0]], tolerance)
        out = a[:-1] + b[:-1]
        if len(out) < 3:
            return pts
        return out
    return _dp(pts, tolerance)


def _dp(pts: List[Point], tol: float) -> List[Point]:
    if len(pts) < 3:
        return list(pts)
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        i, j = stack.pop()
        best, idx = -1.0, -1
        for k in range(i + 1, j):
            d = point_segment_dist(pts[k], pts[i], pts[j])
            if d > best:
                best, idx = d, k
        if best > tol and idx > 0:
            keep[idx] = True
            stack.append((i, idx))
            stack.append((idx, j))
    return [p for p, k in zip(pts, keep) if k]


def convex_hull(points: Iterable[Point]) -> List[Point]:
    pts = sorted(set(points))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower: List[Point] = []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    upper: List[Point] = []
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def min_area_rect(ring: Sequence[Point]):
    """Minimum-area bounding rectangle. Returns (width, depth, angle_rad, area)
    with width >= depth, angle of the long side measured from +x."""
    hull = convex_hull(ring)
    if len(hull) < 3:
        return (0.0, 0.0, 0.0, 0.0)
    best = None
    n = len(hull)
    for i in range(n):
        a, b = hull[i], hull[(i + 1) % n]
        ang = math.atan2(b[1] - a[1], b[0] - a[0])
        c, s = math.cos(-ang), math.sin(-ang)
        xs = [p[0] * c - p[1] * s for p in hull]
        zs = [p[0] * s + p[1] * c for p in hull]
        w, d = max(xs) - min(xs), max(zs) - min(zs)
        ar = w * d
        if best is None or ar < best[3]:
            if w >= d:
                best = (w, d, ang, ar)
            else:
                best = (d, w, ang + math.pi / 2, ar)
    return best


def rect(cx: float, cz: float, width: float, depth: float, angle: float) -> Ring:
    """Rectangle centred on (cx, cz), width along angle (radians from +x)."""
    c, s = math.cos(angle), math.sin(angle)
    hw, hd = width / 2, depth / 2
    corners = [(-hw, -hd), (hw, -hd), (hw, hd), (-hw, hd)]
    return [(cx + u * c - v * s, cz + u * s + v * c) for u, v in corners]


def ring_inside_fraction(ring: Sequence[Point], container: Sequence[Point], samples: int = 6) -> float:
    """Rough fraction of a ring's area lying inside another ring, by sampling
    a grid over the ring's bounding box."""
    xs = [p[0] for p in ring]
    zs = [p[1] for p in ring]
    x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
    total = inside = 0
    for i in range(samples):
        for j in range(samples):
            p = (x0 + (i + 0.5) * (x1 - x0) / samples, z0 + (j + 0.5) * (z1 - z0) / samples)
            if point_in_ring(p, ring):
                total += 1
                if point_in_ring(p, container):
                    inside += 1
    if total == 0:
        return 1.0 if point_in_ring(centroid(ring), container) else 0.0
    return inside / total


def clip_polyline_to_circle(pts: Sequence[Point], radius: float) -> List[List[Point]]:
    """Splits a polyline into the runs that lie within radius of the origin,
    keeping one vertex beyond the edge on each side so roads reach the rim."""
    runs: List[List[Point]] = []
    cur: List[Point] = []
    n = len(pts)
    inside = [math.hypot(*p) <= radius for p in pts]
    for i, p in enumerate(pts):
        near = inside[i] or (i > 0 and inside[i - 1]) or (i + 1 < n and inside[i + 1])
        if near:
            cur.append(p)
        elif cur:
            if len(cur) >= 2:
                runs.append(cur)
            cur = []
    if len(cur) >= 2:
        runs.append(cur)
    return runs


def round_pts(pts: Iterable[Point], nd: int = 2) -> List[List[float]]:
    return [[round(p[0], nd), round(p[1], nd)] for p in pts]
