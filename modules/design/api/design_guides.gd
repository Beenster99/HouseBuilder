class_name DesignGuides
extends RefCounted
## Smart alignment guides, as BSX's plan has them ("like you get in PowerPoint"): while
## something is placed or moved, where its left, middle or right (and top, middle, bottom) on
## the plan come within a few pixels of another room's or part's, it snaps to line up and a
## guide line is drawn along the shared edge. Plan coordinates are (x, z) in metres.
##
##   var others := DesignGuides.boxes(model, level, skip_ids)    # rooms and parts on a level
##   var al := DesignGuides.align(Rect2(at - size / 2, size), others, tol)
##   at += al.offset                                              # lined up
##   for g in al.guides: draw_line(g[0], g[1])                    # [[Vector2, Vector2], ...]
##
## Pure functions, so walk-inside or anything else placing things can use the same guides.

const COLOUR := Color(1.0, 0.3, 0.85)
## How near, in screen pixels, an edge or middle has to come to another's to snap.
const SNAP_PX := 8.0


## Where `box`'s edges or middle come within `tol` of any of `others`' on each axis: the shift
## that lines them up and the guide lines to draw. {offset: Vector2, guides: [[from, to], ...]}
static func align(box: Rect2, others: Array[Rect2], tol: float) -> Dictionary:
	var out := {"offset": Vector2.ZERO, "guides": []}
	if tol <= 0.0 or others.is_empty():
		return out
	var best := [INF, INF]
	var hit := [[], []]
	for axis in 2:
		var mine := [box.position[axis], box.get_center()[axis], box.end[axis]]
		for o in others:
			var theirs := [o.position[axis], o.get_center()[axis], o.end[axis]]
			for m: float in mine:
				for t: float in theirs:
					var d := t - m
					if absf(d) <= tol and absf(d) <= absf(best[axis]) + 0.0001:
						if absf(d) < absf(best[axis]) - 0.0001:
							hit[axis] = []
						best[axis] = d
						hit[axis].append([t, o])
	var off := Vector2(best[0] if best[0] != INF else 0.0, best[1] if best[1] != INF else 0.0)
	var moved := Rect2(box.position + off, box.size)
	for axis in 2:
		for h: Array in hit[axis]:
			var o: Rect2 = h[1]
			var t: float = h[0]
			var lo := minf(moved.position[1 - axis], o.position[1 - axis])
			var hi := maxf(moved.end[1 - axis], o.end[1 - axis])
			if axis == 0:
				out.guides.append([Vector2(t, lo), Vector2(t, hi)])
			else:
				out.guides.append([Vector2(lo, t), Vector2(hi, t)])
	out.offset = off
	return out


## The plan boxes of every room and part on `level`, but those in `skip`.
static func boxes(model: BuildingModel, level: int, skip: PackedStringArray = PackedStringArray()) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for rid in model.rooms_on(level):
		if rid in skip:
			continue
		var r := room_box(model, rid)
		if r.size != Vector2.ZERO:
			out.append(r)
	for pid in model.parts_on(level):
		if pid in skip:
			continue
		var bb: AABB = model.aabb_of(pid)
		out.append(Rect2(Vector2(bb.position.x, bb.position.z), Vector2(bb.size.x, bb.size.z)))
	return out


## A room's plan box (its outline's bounds).
static func room_box(model: BuildingModel, rid: String) -> Rect2:
	var o: Array = model.rooms.get(rid, {}).get("outline", [])
	if o.is_empty():
		return Rect2()
	var r := Rect2(Vector2(float(o[0][0]), float(o[0][1])), Vector2.ZERO)
	for c: Array in o:
		r = r.expand(Vector2(float(c[0]), float(c[1])))
	return r


## The plan box round several entries (rooms and parts).
static func box_of(model: BuildingModel, ids: PackedStringArray) -> Rect2:
	var out := Rect2()
	var first := true
	for id in ids:
		var r := Rect2()
		if model.rooms.has(id):
			r = room_box(model, id)
		elif model.parts.has(id):
			var bb: AABB = model.aabb_of(id)
			r = Rect2(Vector2(bb.position.x, bb.position.z), Vector2(bb.size.x, bb.size.z))
		else:
			continue
		out = r if first else out.merge(r)
		first = false
	return out
