extends RefCounted
## Smart guides in walk-inside, the same as the designer's (DesignGuides, ported from BSX's
## plan): a part in your hands lines up, edge or middle, with the rooms and parts round it, and
## the lines it lines up on are drawn on the floor. Alt held turns them off.

const WalkEdits := preload("res://modules/walk/internal/walk_edits.gd")

## How near (m) an edge or middle has to come to another's to snap to it.
const SNAP := 0.18
## Only things this near (m) count, so a big building doesn't fill the floor with lines.
const NEAR := 8.0
const COLOUR := DesignGuides.COLOUR


## What a part held at `at` (`size` in plan, x by z) lines up on: the designer's guides
## (DesignGuides, from BSX), against the rooms and parts on `level` near it, but not `skip`.
## {offset: Vector2, guides: [[Vector2, Vector2], ...]}
static func align_at(model: BuildingModel, level: int, at: Vector3, size: Vector2, skip: String) -> Dictionary:
	var here := Vector2(at.x, at.z)
	var near: Array[Rect2] = []
	for r: Rect2 in DesignGuides.boxes(model, level, PackedStringArray([skip])):
		var c := Vector2(clampf(here.x, r.position.x, r.end.x), clampf(here.y, r.position.y, r.end.y))
		if c.distance_to(here) <= NEAR:
			near.append(r)
	var tol := minf(SNAP, WalkEdits.grid(model) * 0.5) if WalkEdits.grid(model) > 0.0 else SNAP
	return DesignGuides.align(Rect2(here - size * 0.5, size), near, tol)


## The guides as dashed strips on the floor at height `y`, with a post at each end, to be
## drawn through everything.
static func mesh(guides: Array, y: float) -> ImmediateMesh:
	var im := ImmediateMesh.new()
	if guides.is_empty():
		return im
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for g: Array in guides:
		var a := Vector3(g[0].x, y, g[0].y)
		var b := Vector3(g[1].x, y, g[1].y)
		var ln := a.distance_to(b)
		var dir := (b - a) / maxf(ln, 0.001)
		var side := dir.cross(Vector3.UP) * 0.025
		var s := 0.0
		while s < ln:
			_quad(im, a + dir * s, a + dir * minf(s + 0.16, ln), side)
			s += 0.26
		for p: Vector3 in [a, b]:
			_quad(im, p, p + Vector3(0, 0.6, 0), side)
			_quad(im, p, p + Vector3(0, 0.6, 0), dir * 0.025)
	im.surface_end()
	return im


static func _quad(im: ImmediateMesh, from: Vector3, to: Vector3, side: Vector3) -> void:
	for v: Vector3 in [from - side, from + side, to + side, from - side, to + side, to - side]:
		im.surface_add_vertex(v)
