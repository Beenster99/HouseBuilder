extends RefCounted
## The edits walk-inside makes, as BuildingModel ops (BSX WalkInside's put_down, turn,
## door_here and push_wall, on the building model). Pure: nothing is applied here; the view
## sends each op through BuildingSync so the host checks it and everyone gets it.

const C := preload("res://modules/building/api/building_commands.gd")

## A wall end or outline corner this near a pushed wall's line moves with it, m.
const JOIN := 0.06
## Floor to ceiling limits when the ceiling is pushed, m.
const MIN_STOREY := 2.2
const MAX_STOREY := 12.0


static func grid(model: BuildingModel) -> float:
	return maxf(float(model.meta.get("grid", BuildingModel.DEFAULT_GRID)), 0.05)


static func snap(v: float, step: float) -> float:
	return snappedf(snappedf(v, step), 0.0001)


## The level whose floor is at or just under world height y.
static func level_at(model: BuildingModel, y: float) -> int:
	var out := 0
	for i in model.level_count():
		if model.level_elevation(i) <= y + 0.3:
			out = i
	return out


## The room (id) on `level` that contains plan point p, or "".
static func room_at(model: BuildingModel, level: int, p: Vector2) -> String:
	for rid in model.rooms_on(level):
		if BuildingModel.outline_has_point(model.rooms[rid].outline, p.x, p.y):
			return rid
	return ""


## A new point part (a fitting, a column) standing at world point `at`, snapped to the grid
## (unless `on_grid` is false: the spot is already snapped, or lined up on a guide).
static func place(model: BuildingModel, kind: String, at: Vector3, rot: float, on_grid := true) -> Dictionary:
	var level := level_at(model, at.y)
	var g := grid(model) if on_grid else 0.0
	var p := Vector3(snap(at.x, g), 0.0, snap(at.z, g))
	return C.place_part(kind, level, {"at": p, "rot": fposmod(rot, 360.0)})


## A placed point part moved to world point `at` (and turned to rot): one undo step.
static func move_to(model: BuildingModel, id: String, at: Vector3, rot: float, on_grid := true) -> Dictionary:
	var e: Dictionary = model.parts.get(id, {})
	if e.is_empty() or not e.has("at"):
		return {}
	var level := level_at(model, at.y)
	var g := grid(model) if on_grid else 0.0
	var fields := {"at": [snap(at.x, g), float(e.at[1]), snap(at.z, g)], "rot": fposmod(rot, 360.0)}
	if level != int(e.level):
		fields["level"] = level
	return C.set_fields(id, fields)


## A part turned a quarter.
static func turn(model: BuildingModel, id: String, by := 90.0) -> Dictionary:
	var e: Dictionary = model.parts.get(id, {})
	if e.is_empty() or not e.has("at"):
		return {}
	return C.set_fields(id, {"rot": snappedf(fposmod(float(e.get("rot", 0.0)) + by, 360.0), 0.001)})


## Half the plan box (x, z) of a w by d footprint turned rot degrees: what it takes up.
static func turned_half(w: float, d: float, rot: float) -> Vector2:
	var r := deg_to_rad(rot)
	var c := absf(cos(r))
	var s := absf(sin(r))
	return Vector2(c * w + s * d, s * w + c * d) * 0.5


## A door or window of `kind` in a wall where world point `at` is, centred on the nearest
## grid step; {} when it would not fit or would overlap one already there.
static func opening_at(model: BuildingModel, wall_id: String, at: Vector3, kind: String) -> Dictionary:
	var wall: Dictionary = model.parts.get(wall_id, {})
	if wall.is_empty() or model.catalog.family_of(str(wall.kind)) != "wall":
		return {}
	var a := Vector2(float(wall.a[0]), float(wall.a[2]))
	var b := Vector2(float(wall.b[0]), float(wall.b[2]))
	var length := a.distance_to(b)
	var w := float(model.catalog.kind(kind).get("w", 0.9))
	if length < w + 0.1:
		return {}
	var dir := (b - a) / length
	var t := clampf(snap((Vector2(at.x, at.z) - a).dot(dir), 0.05), w / 2.0 + 0.05, length - w / 2.0 - 0.05)
	for oid in model.openings_in(wall_id):
		var o: Dictionary = model.parts[oid]
		var ow := float(o.get("w", model.catalog.kind(str(o.kind)).get("w", 0.9)))
		if absf(float(o.t) - t) < (ow + w) / 2.0 + 0.05:
			return {}
	return C.place_opening(kind, wall_id, t)


## Pushes a wall `by` metres along its normal, away from `viewer` (world, plan) when by > 0,
## towards when by < 0 (BSX push_wall: the mouse wheel by a grid step). The walls that meet
## it stretch to follow (their openings stay put), and the rooms and floors whose edges lie
## on it move their corners with it: one batch, so one undo.
static func push_wall(model: BuildingModel, wall_id: String, viewer: Vector3, by: float) -> Dictionary:
	var wall: Dictionary = model.parts.get(wall_id, {})
	if wall.is_empty() or model.catalog.family_of(str(wall.kind)) != "wall" or absf(by) < 0.001:
		return {}
	var level := int(wall.level)
	var a := Vector2(float(wall.a[0]), float(wall.a[2]))
	var b := Vector2(float(wall.b[0]), float(wall.b[2]))
	if a.distance_to(b) < 0.05:
		return {}
	var dir := (b - a).normalized()
	var n := Vector2(-dir.y, dir.x)
	var mid := (a + b) / 2.0
	if n.dot(mid - Vector2(viewer.x, viewer.z)) < 0.0:
		n = -n
	var d := n * by
	d = Vector2(snappedf(d.x, 0.0001), snappedf(d.y, 0.0001))
	var ops: Array = [C.move([wall_id], Vector3(d.x, 0, d.y))]
	var thick := float(model.catalog.section(str(wall.get("section", ""))).get("d", 0.2))
	for pid in model.parts_on(level):
		if pid == wall_id:
			continue
		var e: Dictionary = model.parts[pid]
		var fam := model.catalog.family_of(str(e.kind))
		if fam == "wall":
			ops.append_array(_stretch(model, pid, e, a, b, d, JOIN + thick / 2.0))
		elif fam == "slab" and e.has("outline"):
			var o := _shift_outline(e.outline, a, b, d, JOIN + thick)
			if not o.is_empty():
				ops.append(C.set_fields(pid, {"outline": o}))
	# The floor above sits on it too.
	if level + 1 < model.level_count():
		for pid in model.parts_on(level + 1):
			var e2: Dictionary = model.parts[pid]
			if model.catalog.family_of(str(e2.kind)) == "slab" and e2.has("outline") and absf(float(e2.get("y", 0.0))) < 0.05:
				var o2 := _shift_outline(e2.outline, a, b, d, JOIN + thick)
				if not o2.is_empty():
					ops.append(C.set_fields(pid, {"outline": o2}))
	for rid in model.rooms_on(level):
		var o3 := _shift_outline(model.rooms[rid].outline, a, b, d, JOIN + thick / 2.0)
		if not o3.is_empty():
			ops.append(C.set_fields(rid, {"outline": o3}))
	return C.batch(ops)


## The ops that stretch a wall meeting the pushed one (a corner or a T): its new ends, and
## its openings' t so they stay where they stand (openings are placed from a). Ordered so
## the openings fit the wall at every step. [] if it doesn't meet it.
static func _stretch(model: BuildingModel, id: String, e: Dictionary, a: Vector2, b: Vector2, d: Vector2, reach: float) -> Array:
	var oa := Vector2(float(e.a[0]), float(e.a[2]))
	var ob := Vector2(float(e.b[0]), float(e.b[2]))
	var move_a := _on_segment(oa, a, b, reach)
	var move_b := _on_segment(ob, a, b, reach)
	if not move_a and not move_b:
		return []
	if move_a != move_b and absf((ob - oa).normalized().dot((b - a).normalized())) > 0.98:
		return []  # a run of wall in line with it: left as it is, not skewed
	var na := oa + d if move_a else oa
	var nb := ob + d if move_b else ob
	if na.distance_to(nb) < BuildingModel.MIN_LENGTH:
		return []
	var f := {}
	if move_a:
		f["a"] = [snappedf(na.x, 0.0001), float(e.a[1]), snappedf(na.y, 0.0001)]
	if move_b:
		f["b"] = [snappedf(nb.x, 0.0001), float(e.b[1]), snappedf(nb.y, 0.0001)]
	var wall_op := C.set_fields(id, f)
	if not move_a or move_b:
		return [wall_op]
	var dir := (nb - na).normalized()
	var olddir := (ob - oa).normalized()
	var opening_ops: Array = []
	for oid in model.openings_in(id):
		var o: Dictionary = model.parts[oid]
		var at := oa + olddir * float(o.t)
		var nt := snappedf((at - na).dot(dir), 0.0001)
		if absf(nt - float(o.t)) > 0.0001:
			opening_ops.append(C.set_fields(oid, {"t": nt}))
	if na.distance_to(nb) < oa.distance_to(ob):
		return opening_ops + [wall_op]
	return [wall_op] + opening_ops


static func _on_segment(p: Vector2, a: Vector2, b: Vector2, reach: float) -> bool:
	var q := Geometry2D.get_closest_point_to_segment(p, a, b)
	return q.distance_to(p) <= reach


## An outline with the corners that lie on segment a-b moved by d, or [] if none do.
static func _shift_outline(outline: Array, a: Vector2, b: Vector2, d: Vector2, reach: float) -> Array:
	var out: Array = []
	var moved := false
	for p: Variant in outline:
		var v := Vector2(float(p[0]), float(p[1]))
		if _on_segment(v, a, b, reach):
			v += d
			moved = true
		out.append([snappedf(v.x, 0.0001), snappedf(v.y, 0.0001)])
	if not moved or BuildingModel.outline_area(out) < BuildingModel.MIN_AREA:
		return []
	return out


## Moves the ceiling over `level` by `by` metres (up is away when by > 0): the storey's
## height, so the floors above follow.
static func push_ceiling(model: BuildingModel, level: int, by: float) -> Dictionary:
	if level < 0 or level >= model.level_count():
		return {}
	var h := clampf(snappedf(model.level_height(level) + by, 0.0001), MIN_STOREY, MAX_STOREY)
	if absf(h - model.level_height(level)) < 0.0001:
		return {}
	return C.set_level(level, {"height": h})


## The next material or section a part's kind allows (E's rows): {} at none.
static func cycle(model: BuildingModel, id: String, field: String) -> Dictionary:
	var e: Dictionary = model.parts.get(id, {})
	if e.is_empty():
		return {}
	var kind := str(e.kind)
	var choices: PackedStringArray = model.catalog.materials_for(kind) if field == "material" \
			else model.catalog.sections_for(kind, str(e.get("material", "")))
	if choices.size() < 2:
		return {}
	var i := choices.find(str(e.get(field, "")))
	return C.set_fields(id, {field: choices[(i + 1) % choices.size()]})


## The next kind in the same family (a partition to a load-bearing wall, a door to a fire
## door, a bed to a double bed): {} at none.
static func next_kind(model: BuildingModel, id: String) -> Dictionary:
	var e: Dictionary = model.parts.get(id, {})
	if e.is_empty():
		return {}
	var fam := model.catalog.family_of(str(e.kind))
	var shape := model.catalog.shape_of(str(e.kind))
	var same: PackedStringArray = []
	for k in model.catalog.kinds_in(fam):
		if model.catalog.shape_of(k) == shape:
			same.append(k)
	if same.size() < 2:
		return {}
	var i := same.find(str(e.kind))
	return C.retag(id, same[(i + 1) % same.size()])


## Every kind a part could be changed to: the same family and shape (a fitting to any other
## fitting, a door to another door or a window), in catalog order.
static func kinds_like(model: BuildingModel, id: String) -> PackedStringArray:
	var e: Dictionary = model.parts.get(id, {})
	var out: PackedStringArray = []
	if e.is_empty():
		return out
	var fam := model.catalog.family_of(str(e.kind))
	var shape := model.catalog.shape_of(str(e.kind))
	for k in model.catalog.kinds_in(fam):
		if model.catalog.shape_of(k) == shape:
			out.append(k)
	return out


## A part changed to another kind (keeping where it is and how it's turned). {} if not one of
## kinds_like.
static func change_kind(model: BuildingModel, id: String, kind: String) -> Dictionary:
	if not kind in kinds_like(model, id) or str(model.parts[id].kind) == kind:
		return {}
	return C.retag(id, kind)


## A fitting's size (w, h, d): its own if resized, else its kind's.
static func size_of(model: BuildingModel, kind: String, e: Dictionary = {}) -> Vector3:
	var spec := model.catalog.kind(kind)
	return Vector3(float(e.get("w", spec.get("w", 0.5))), float(e.get("height", spec.get("h", 0.8))),
			float(e.get("d", spec.get("d", 0.5))))


## The sizes Edit can change on a part: [{field, label, value}] (m). A fitting's width, depth
## and height; a door's or window's width, height and sill; a wall's length and height; a
## stair's width.
static func dims(model: BuildingModel, id: String) -> Array:
	var e: Dictionary = model.parts.get(id, {})
	if e.is_empty():
		return []
	var spec := model.catalog.kind(str(e.kind))
	var fam := model.catalog.family_of(str(e.kind))
	var shape := model.catalog.shape_of(str(e.kind))
	var out: Array = []
	if fam == "fixture" and shape == "point":
		var s := size_of(model, str(e.kind), e)
		out = [{"field": "w", "label": "Width", "value": s.x}, {"field": "d", "label": "Depth", "value": s.z},
				{"field": "height", "label": "Height", "value": s.y}]
	elif shape == "opening":
		out = [{"field": "w", "label": "Width", "value": float(e.get("w", spec.get("w", 1.0)))},
				{"field": "h", "label": "Height", "value": float(e.get("h", spec.get("h", 2.0)))},
				{"field": "sill", "label": "Sill", "value": float(e.get("sill", spec.get("sill", 0.0)))}]
	elif fam == "wall":
		var a := Vector3(float(e.a[0]), float(e.a[1]), float(e.a[2]))
		var b := Vector3(float(e.b[0]), float(e.b[1]), float(e.b[2]))
		out = [{"field": "length", "label": "Length", "value": a.distance_to(b)},
				{"field": "height", "label": "Height", "value": model.part_height(id)}]
	elif str(e.kind) == "stair":
		out = [{"field": "w", "label": "Width", "value": model.stair_width(id)}]
	if e.has("at"):
		out.append({"field": "rot", "label": "Angle", "value": float(e.get("rot", 0.0)), "unit": "°", "step": 15.0})
	for d: Dictionary in out:
		d.value = snappedf(float(d.value), 0.001)
	return out


## A part with one of its dims set to `value` m: one undo step. A wall's length moves its b
## end along the wall. {} if the value can't be.
static func resize(model: BuildingModel, id: String, field: String, value: float) -> Dictionary:
	var e: Dictionary = model.parts.get(id, {})
	if e.is_empty():
		return {}
	if field == "rot":
		return C.set_fields(id, {"rot": snappedf(fposmod(value, 360.0), 0.001)}) if e.has("at") else {}
	if value < (0.0 if field == "sill" else 0.05) or value > 200.0:
		return {}
	if field == "length":
		var a := Vector3(float(e.a[0]), float(e.a[1]), float(e.a[2]))
		var b := Vector3(float(e.b[0]), float(e.b[1]), float(e.b[2]))
		var dir := (b - a).normalized()
		var nb := a + dir * value
		return C.set_fields(id, {"b": [nb.x, b.y, nb.z]})
	return C.set_fields(id, {field: value})
