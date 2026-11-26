class_name DesignSnap
extends RefCounted
## Snapping in the design room: to the grid (DesignBus grid size, 0.25 m by default), to
## existing corners nearby, and for walls and beams to 45° steps from their start point.
## Pure functions, so tests and every view snap the same way.

## How close a corner must be to win over the grid, m.
const CORNER_REACH := 0.4


static func to_grid(p: Vector3, grid: float) -> Vector3:
	if grid <= 0.0:
		return p
	return Vector3(snappedf(p.x, grid), p.y, snappedf(p.z, grid))


## The nearest of `corners` within CORNER_REACH on the same level, else the grid point.
static func point(p: Vector3, grid: float, corners: Array = []) -> Vector3:
	var best: Variant = null
	var best_d := CORNER_REACH
	for c: Vector3 in corners:
		if absf(c.y - p.y) > 0.01:
			continue
		var d := Vector2(c.x - p.x, c.z - p.z).length()
		if d < best_d:
			best_d = d
			best = c
	return best if best != null else to_grid(p, grid)


## A run from `start` toward `p` held to the nearest 45°, its length snapped to the grid.
static func run(start: Vector3, p: Vector3, grid: float) -> Vector3:
	var d := Vector2(p.x - start.x, p.z - start.z)
	if d.length() < 0.001:
		return start
	var step := PI / 4.0
	var ang := snappedf(d.angle(), step)
	var length := d.length()
	if grid > 0.0:
		length = maxf(grid, snappedf(length, grid))
	var dir := Vector2.from_angle(ang)
	var out := Vector3(start.x + dir.x * length, start.y, start.z + dir.y * length)
	# Square runs land on the grid exactly; diagonals keep their snapped length.
	if is_zero_approx(fmod(absf(ang), PI / 2.0)):
		out = Vector3(snappedf(out.x, 0.001), out.y, snappedf(out.z, 0.001))
	return out


## The axis-aligned rectangle two corners span, as [min corner, max corner] on the grid.
static func rect(a: Vector3, b: Vector3, grid: float) -> Array[Vector3]:
	var p := to_grid(a, grid)
	var q := to_grid(b, grid)
	return [Vector3(minf(p.x, q.x), p.y, minf(p.z, q.z)), Vector3(maxf(p.x, q.x), p.y, maxf(p.z, q.z))]


## Distance from p to the segment a-b in plan (x, z), m.
static func plan_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var pp := Vector2(p.x, p.z)
	var aa := Vector2(a.x, a.z)
	var bb := Vector2(b.x, b.z)
	var ab := bb - aa
	var t := 0.0 if ab.length_squared() < 1e-9 else clampf((pp - aa).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return pp.distance_to(aa + ab * t)


## How far along a-b (m from a) the point nearest p lies.
static func along(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var len := ab.length()
	if len < 1e-6:
		return 0.0
	return clampf(Vector2(p.x - a.x, p.z - a.z).dot(ab / len), 0.0, len)


## True if the plan point lies inside the polygon (x, z).
static func in_polygon(p: Vector3, poly: PackedVector2Array) -> bool:
	return Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), poly)
