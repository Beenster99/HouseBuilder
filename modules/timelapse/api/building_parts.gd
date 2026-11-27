class_name BuildingParts
extends RefCounted
## The building model as plain part Dictionaries, the input of TimelapseSchedule and the
## demolition module:
##   {"id", "kind", "family", "material", "aabb": AABB (world, m), "supported_by": [ids],
##    "cost", "mass", "level"}
## `kind` is the schedule's word for the part (column, beam, slab, wall, window, door, roof,
## fitout, stairs...). What a part rests on comes from three places: the model's explicit
## connections (the lower part carries the upper), an opening's host wall, and geometry
## (anything whose top meets this part's underside and overlaps it in plan). Stair cores and
## lift shafts (rooms) become "stairs" and "lift" parts.
##
##   var parts := BuildingParts.from_model((Modules.bus("building") as BuildingBus).model)

const FAMILY_KIND := {
	"foundation": "foundation", "column": "column", "beam": "beam", "brace": "brace",
	"truss": "truss", "slab": "slab", "roof": "roof", "wall": "wall", "fixture": "fitout",
}
## Lower ranks carry higher ones when two parts sit at the same height.
const RANK := {"foundation": 0, "column": 1, "wall": 1, "beam": 2, "brace": 2, "truss": 2,
		"slab": 3, "roof": 4, "fixture": 5, "opening": 5, "room": 5}
## A carrier's top may sit this far below a part's underside, or EMBED above it (a wall
## standing in its footing's top), to count as carrying it, m.
const TOUCH := 0.2
const EMBED := 0.4
const SERVICE_ROOMS := {"stair_core": "stairs", "lift_shaft": "lift"}


static func from_model(model: BuildingModel) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var by_id: Dictionary = {}
	for pid: String in BuildingModel.sort_ids(model.parts.keys()):
		var e: Dictionary = model.parts[pid]
		var family := model.catalog.family_of(str(e.kind))
		var box := model.aabb_of(pid)
		if box.size == Vector3.ZERO and box.position == Vector3.ZERO:
			continue
		var kind: String = FAMILY_KIND.get(family, "frame")
		if family == "opening":
			kind = "door" if str(e.kind).contains("door") else "window"
		var q := BuildingQuantities.part(model, pid)
		var p := {"id": pid, "kind": kind, "family": family, "material": str(e.get("material", "")),
				"aabb": box, "supported_by": [], "cost": float(q.get("cost", 0.0)),
				"mass": float(q.get("mass", 0.0)), "level": model.level_of(pid)}
		var shape := shape_of(model, pid)
		if not shape.is_empty():
			p.shape = shape
		if family == "opening" and e.has("host"):
			p.supported_by.append(str(e.host))
		out.append(p)
		by_id[pid] = p
	for rid: String in BuildingModel.sort_ids(model.rooms.keys()):
		var r: Dictionary = model.rooms[rid]
		if not SERVICE_ROOMS.has(str(r.get("type", ""))):
			continue
		var level := int(r.get("level", 0))
		var box := AABB()
		var first := true
		for pt: Variant in r.get("outline", []):
			var v := Vector3(float(pt[0]), model.level_elevation(level), float(pt[1]))
			box = AABB(v, Vector3.ZERO) if first else box.expand(v)
			first = false
		box.size.y = model.level_height(level)
		var p := {"id": rid, "kind": SERVICE_ROOMS[str(r.type)], "family": "room", "material": "",
				"aabb": box, "supported_by": [], "cost": 0.0, "mass": 0.0, "level": level,
				"shape": _outline_shape(r.get("outline", []), box.end.y, box.size.y)}
		out.append(p)
		by_id[rid] = p

	# Explicit connections: the lower part (then the lower rank) carries the other.
	for cid: String in BuildingModel.sort_ids(model.connections.keys()):
		var c: Dictionary = model.connections[cid]
		var a: Dictionary = by_id.get(str(c.get("a", "")), {})
		var b: Dictionary = by_id.get(str(c.get("b", "")), {})
		if a.is_empty() or b.is_empty():
			continue
		var lower := _carries(a, b)
		if lower == 0:
			continue
		var upper: Dictionary = b if lower < 0 else a
		var carrier: Dictionary = a if lower < 0 else b
		_add_support(upper, carrier.id)

	# Geometry: index tops by height, then look under each part.
	var tops: Dictionary = {}  # round(top * 10) -> parts
	for p in out:
		var key := roundi((p.aabb as AABB).end.y * 10.0)
		if not tops.has(key):
			tops[key] = []
		tops[key].append(p)
	var reach := ceili(TOUCH * 10.0)
	for p in out:
		if p.family == "opening":
			continue
		var box: AABB = p.aabb
		var under := roundi(box.position.y * 10.0)
		for k in range(under - reach, under + ceili(EMBED * 10.0) + 1):
			for q: Dictionary in tops.get(k, []):
				if q == p or q.family == "opening":
					continue
				# Only something lower and no higher in the build order carries it.
				if (q.aabb as AABB).position.y > box.position.y - 0.05 or RANK.get(q.family, 3) > RANK.get(p.family, 3):
					continue
				if _overlap_plan(q.aabb, box):
					_add_support(p, q.id)
	return out


## Each room's fit-out (finishes, kitchens, bathrooms) as a thin "fitout" part on its floor
## costed from BuildingQuantities, so a timelapse spends what the design room's cost panel
## shows (stair cores and lift shafts included: their parts carry no cost of their own).
static func fit_out(model: BuildingModel) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rid: String in BuildingModel.sort_ids(model.rooms.keys()):
		var r: Dictionary = model.rooms[rid]
		var cost := float(BuildingQuantities.room(model, rid).get("fit_out", 0.0))
		var level := int(r.get("level", 0))
		var box := AABB()
		var first := true
		for pt: Variant in r.get("outline", []):
			var v := Vector3(float(pt[0]), model.level_elevation(level), float(pt[1]))
			box = AABB(v, Vector3.ZERO) if first else box.expand(v)
			first = false
		if first or cost <= 0.0:
			continue
		box.size.y = 0.05
		out.append({"id": "fit:" + rid, "kind": "fitout", "family": "fixture", "material": "",
				"aabb": box, "supported_by": [], "cost": cost, "mass": 0.0, "level": level,
				"shape": _outline_shape(r.get("outline", []), box.end.y, box.size.y)})
	return out


## -1 when `a` carries `b`, 1 when `b` carries `a`, 0 when neither is below the other.
static func _carries(a: Dictionary, b: Dictionary) -> int:
	var ya := (a.aabb as AABB).position.y
	var yb := (b.aabb as AABB).position.y
	if absf(ya - yb) > 0.05:
		return -1 if ya < yb else 1
	var ra: int = RANK.get(a.family, 3)
	var rb: int = RANK.get(b.family, 3)
	if ra == rb:
		return 0
	return -1 if ra < rb else 1


static func _overlap_plan(a: AABB, b: AABB) -> bool:
	return a.position.x < b.end.x - 0.01 and b.position.x < a.end.x - 0.01 \
			and a.position.z < b.end.z - 0.01 and b.position.z < a.end.z - 0.01


static func _add_support(p: Dictionary, carrier: String) -> void:
	if not (p.supported_by as Array).has(carrier):
		p.supported_by.append(carrier)


## A part's exact shape for drawing, beyond its box: walls, beams, braces and openings at
## their real angle ({"obb": Transform3D}, a unit box's transform), slabs, roofs and rooms
## as their real outline ({"outline": PackedVector2Array (x, z), "top": y, "thick": m}).
## {} when the box is the shape (columns, pads, fixtures).
static func shape_of(model: BuildingModel, pid: String) -> Dictionary:
	var e: Dictionary = model.parts.get(pid, {})
	if e.is_empty():
		return {}
	var spec := model.catalog.kind(str(e.kind))
	var sec := model.catalog.section(str(e.get("section", "")))
	var pts := model.points_of(pid)
	var fam := str(spec.get("family", ""))
	match str(spec.get("shape", "")):
		"line":
			if pts.size() < 2 or str(e.kind) == "stair":
				return {}
			var a := pts[0]
			var b := pts[1]
			if a.distance_to(b) < 0.01:
				return {}
			if fam == "wall":
				var h := model.part_height(pid)
				var d := float(sec.get("d", 0.1))
				var y0 := minf(a.y, b.y)
				return {"obb": _box_along(Vector3(a.x, y0, a.z), Vector3(b.x, y0, b.z), d, h, 0.0)}
			var w := float(sec.get("w", sec.get("dia", sec.get("d", 0.2))))
			var depth := float(sec.get("d", w))
			return {"obb": _box_along(a, b, w, depth, -depth * 0.5)}
		"opening":
			if pts.size() < 2:
				return {}
			var host: Dictionary = model.parts.get(str(e.get("host", "")), {})
			var d := float(model.catalog.section(str(host.get("section", ""))).get("d", 0.1)) + 0.02
			var h := float(e.get("h", spec.get("h", 2.0)))
			return {"obb": _box_along(pts[0], pts[1], d, h, 0.0)}
		"area":
			if pts.size() < 3:
				return {}
			var outline: Array = []
			for q in pts:
				outline.append([q.x, q.z])
			var top := pts[0].y
			return _outline_shape(outline, top, maxf(float(sec.get("d", 0.0)), 0.05))
	return {}


## A box `width` across and `height` tall along the line a-b, its bottom at `lift` (m)
## from the line: the transform of a unit box centred at the origin.
static func _box_along(a: Vector3, b: Vector3, width: float, height: float, lift: float) -> Transform3D:
	var along := b - a
	var x := along.normalized()
	var flat := Vector3(along.x, 0, along.z)
	var up := Vector3.UP if flat.length() > 0.001 else Vector3.BACK
	var z := x.cross(up).normalized()
	var y := z.cross(x).normalized()
	var basis := Basis(x * along.length(), y * height, z * width)
	var centre := (a + b) * 0.5 + y * (lift + height * 0.5)
	return Transform3D(basis, centre)


static func _outline_shape(outline: Array, top: float, thick: float) -> Dictionary:
	var poly := PackedVector2Array()
	for q: Variant in outline:
		poly.append(Vector2(float(q[0]), float(q[1])))
	if poly.size() < 3:
		return {}
	return {"outline": poly, "top": top, "thick": thick}

