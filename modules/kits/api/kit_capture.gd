class_name KitCapture
extends RefCounted
## Room modules ("kits") as plain data: a room and everything in it, cut out of a building
## model, and the ops that put a copy of it back anywhere, turned in quarter turns.
##
##   var kit := KitCapture.capture(model, "r3", "En-suite", "Bathrooms")
##   var ops := KitCapture.place_ops(model, kit, 1, Vector3(10, 0, 4), 90.0)
##   sync.edit(BuildingCommands.batch(ops))        # one edit, one undo, checked by the host
##
## A kit: {format, name, group, room: {type, name, outline}, size: [w, d], parts: [{ref,
## entry}], connections: [{a, b, kind, at?}], level_height, author, saved}. Coordinates are
## level-local plan metres from the room outline's low corner; refs are the parts' ids when
## captured ("p12"), and openings' hosts are refs. Parts on the room's level are in the kit
## when they lie inside the outline or on its edge (walls round the room, its slab, fittings,
## columns, beams); stairs and lifts span levels and stay out.
##
## Placing: walls that an existing wall on that level already covers are not doubled (rooms
## side by side share a wall); the doors and windows in them move onto the existing wall.

const C := preload("res://modules/building/api/building_commands.gd")

const FORMAT := 1
## On the outline's edge, m.
const EDGE := 0.06
## Families a kit never takes: they reach other levels.
const SKIP_FAMILIES: PackedStringArray = ["circulation"]
## Largest kit, entries (keeps a shared library message small).
const MAX_PARTS := 600


## The room `room_id` and its contents as a kit ({} when there is no such room).
static func capture(model: BuildingModel, room_id: String, kit_name: String, group: String = "") -> Dictionary:
	if not model.rooms.has(room_id):
		return {}
	var room: Dictionary = model.rooms[room_id]
	var level := int(room.level)
	var outline: Array = _plain_outline(room.outline)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Array in outline:
		lo = Vector2(minf(lo.x, p[0]), minf(lo.y, p[1]))
		hi = Vector2(maxf(hi.x, p[0]), maxf(hi.y, p[1]))
	var cat := model.catalog
	var kept: Dictionary = {}
	for pid: String in model.parts_on(level):
		var e: Dictionary = model.parts[pid]
		if e.has("host") or str(cat.family_of(str(e.kind))) in SKIP_FAMILIES:
			continue
		if _part_inside(e, outline):
			kept[pid] = true
	# Doors and windows in the kept walls.
	for pid: String in model.parts:
		var e: Dictionary = model.parts[pid]
		if e.has("host") and kept.has(str(e.host)):
			kept[pid] = true
	var ids: Array = kept.keys()
	ids.sort_custom(_id_less)
	var parts: Array = []
	for pid: String in ids:
		var e: Dictionary = (model.parts[pid] as Dictionary).duplicate(true)
		e.erase("id")
		e.erase("level")
		parts.append({"ref": pid, "entry": _shift(e, -lo)})
	var conns: Array = []
	for cid: String in model.connections:
		var c: Dictionary = model.connections[cid]
		if kept.has(str(c.a)) and kept.has(str(c.b)):
			var out := {"a": str(c.a), "b": str(c.b), "kind": str(c.kind)}
			if c.has("at"):
				var at := _v3(c.at)
				out["at"] = [_r(at.x - lo.x), _r(at.y - model.level_elevation(level)), _r(at.z - lo.y)]
			conns.append(out)
	var rel: Array = []
	for p: Array in outline:
		rel.append([_r(p[0] - lo.x), _r(p[1] - lo.y)])
	return {
		"format": FORMAT,
		"name": kit_name.strip_edges(),
		"group": group.strip_edges(),
		"room": {"type": str(room.type), "name": str(room.get("name", "")), "outline": rel},
		"size": [_r(hi.x - lo.x), _r(hi.y - lo.y)],
		"parts": parts,
		"connections": conns,
		"level_height": model.level_height(level),
	}


## Why a kit can't be shared ("" when it can): used by the host before it takes one.
static func problem(kit: Dictionary) -> String:
	if str(kit.get("name", "")).strip_edges() == "":
		return "Give the module a name"
	if str(kit.get("name", "")).length() > 48:
		return "Module names are 48 letters at most"
	var room: Variant = kit.get("room")
	if not room is Dictionary or not (room as Dictionary).get("outline") is Array or ((room as Dictionary).outline as Array).size() < 3:
		return "A module needs its room"
	if not kit.get("parts") is Array or not kit.get("connections") is Array:
		return "That module is damaged"
	if (kit.parts as Array).size() > MAX_PARTS:
		return "Modules hold %d parts at most" % MAX_PARTS
	return ""


## The ops that put a copy of `kit` on `level` with its centre at plan point `at` (x, z;
## y ignored), turned rot_deg about the vertical (quarter turns are exact). New parts get
## fresh ids so doors find their walls inside the one batch.
static func place_ops(model: BuildingModel, kit: Dictionary, level: int, at: Vector3, rot_deg: float = 0.0) -> Array:
	if kit.is_empty() or level < 0 or level >= model.level_count():
		return []
	var xf := placement(kit, at, rot_deg)
	var cat := model.catalog
	var ops: Array = []
	var room: Dictionary = kit.room
	var outline: Array = []
	for p: Array in room.outline:
		var q := xf * Vector3(p[0], 0, p[1])
		outline.append([_r(q.x), _r(q.z)])
	if cat.has_room_type(str(room.type)):
		ops.append(C.place_room(str(room.type), level, outline, str(room.get("name", ""))))
	var fresh := _Fresh.new(model)
	var ids := {}  # ref -> id in the model (new, or the existing wall it merged into)
	var merged := {}  # ref -> true when that wall was not added
	var placed_walls: Array = []
	for row: Dictionary in kit.parts:
		var e: Dictionary = row.entry
		if e.has("host") or not cat.has_kind(str(e.get("kind", ""))):
			continue
		var out := _transform(e, xf, rot_deg)
		if cat.family_of(str(e.kind)) == "wall" and out.has("a"):
			var cover := _covering_wall(model, level, _v3(out.a), _v3(out.b), placed_walls)
			if cover != "":
				ids[row.ref] = cover
				merged[row.ref] = out
				continue
		var nid := fresh.next()
		ids[row.ref] = nid
		out["id"] = nid
		out["level"] = level
		if cat.family_of(str(e.kind)) == "wall" and out.has("a"):
			placed_walls.append([_v3(out.a), _v3(out.b)])
		ops.append({"op": "add", "table": "parts", "entry": out})
	for row: Dictionary in kit.parts:
		var e: Dictionary = row.entry
		if not e.has("host") or not ids.has(str(e.host)) or not cat.has_kind(str(e.get("kind", ""))):
			continue
		var out: Dictionary = e.duplicate(true)
		var host := str(e.host)
		out["host"] = ids[host]
		if merged.has(host):
			# Re-measure along the wall it merged into.
			var mine: Dictionary = merged[host]
			var ma := _v3(mine.a)
			var mb := _v3(mine.b)
			var centre := ma + (mb - ma).normalized() * float(e.t)
			var w: Dictionary = model.parts[ids[host]]
			var wa := _v3(w.a)
			var wb := _v3(w.b)
			var t := Vector2(centre.x - wa.x, centre.z - wa.z).dot(Vector2(wb.x - wa.x, wb.z - wa.z).normalized())
			if _opening_near(model, str(ids[host]), t, float(cat.kind(str(e.kind)).get("w", 1.0))):
				continue
			out["t"] = _r(t)
		var nid := fresh.next()
		ids[row.ref] = nid
		out["id"] = nid
		ops.append({"op": "add", "table": "parts", "entry": out})
	for c: Dictionary in kit.connections:
		if not ids.has(str(c.a)) or not ids.has(str(c.b)) or merged.has(str(c.a)) or merged.has(str(c.b)):
			continue
		var out := {"a": ids[c.a], "b": ids[c.b], "kind": str(c.kind)}
		if c.has("at"):
			var p := xf * _v3(c.at)
			out["at"] = [_r(p.x), _r(p.y + model.level_elevation(level)), _r(p.z)]
		ops.append({"op": "add", "table": "connections", "entry": out})
	return ops


## Kit coordinates to level-local plan: centre on `at`, turned rot_deg (y kept).
static func placement(kit: Dictionary, at: Vector3, rot_deg: float) -> Transform3D:
	var size: Array = kit.get("size", [0, 0])
	var centre := Vector3(snappedf(float(size[0]) / 2.0, 0.25), 0, snappedf(float(size[1]) / 2.0, 0.25))
	var basis := Basis(Vector3.UP, deg_to_rad(rot_deg))
	return Transform3D(basis, Vector3(at.x, 0, at.z)) * Transform3D(Basis.IDENTITY, -centre)


## Totals for a kit: {area, parts, cost, mass, fittings: {kind: n}} from the catalog rates.
static func summary(kit: Dictionary, catalog: BuildingCatalog) -> Dictionary:
	var room: Dictionary = kit.get("room", {})
	var fittings := {}
	var n := 0
	for row: Dictionary in kit.get("parts", []):
		var k := str(row.entry.get("kind", ""))
		n += 1
		if catalog.family_of(k) == "fixture":
			fittings[k] = int(fittings.get(k, 0)) + 1
	return {"area": absf(BuildingModel.outline_area(room.get("outline", []))), "parts": n, "fittings": fittings}


## A kit's parts as a throwaway BuildingModel (one level), for previews and costing.
static func as_model(kit: Dictionary, catalog: BuildingCatalog) -> BuildingModel:
	var m := BuildingModel.new("", str(kit.get("name", "Module")), catalog)
	var h := float(kit.get("level_height", BuildingModel.DEFAULT_LEVEL_HEIGHT))
	if m.level_count() > 0 and absf(m.level_height(0) - h) > 0.001:
		m.apply(C.set_level(0, {"height": h}))
	var size: Array = kit.get("size", [0, 0])
	var ops := place_ops(m, kit, 0, Vector3(snappedf(float(size[0]) / 2.0, 0.25), 0, snappedf(float(size[1]) / 2.0, 0.25)), 0.0)
	if not ops.is_empty():
		m.apply(C.batch(ops))
	return m


# --- Helpers -------------------------------------------------------------------------------

class _Fresh:
	var model: BuildingModel
	var n := 0

	func _init(m: BuildingModel) -> void:
		model = m
		for t: String in ["parts", "rooms", "connections"]:
			for eid: String in model.get(t):
				var s := eid.substr(1)
				if s.is_valid_int():
					n = maxi(n, s.to_int())
		# A gap after the highest id, so two players placing at once rarely pick the same one.
		n += 1 + (randi() % 50)

	func next() -> String:
		n += 1
		while model.has("p%d" % n):
			n += 1
		return "p%d" % n


static func _transform(e: Dictionary, xf: Transform3D, rot_deg: float) -> Dictionary:
	var out: Dictionary = e.duplicate(true)
	for key: String in ["at", "a", "b"]:
		if out.has(key):
			var p := xf * _v3(out[key])
			out[key] = [_r(p.x), _r(p.y), _r(p.z)]
	if out.has("outline"):
		var o: Array = []
		for p: Variant in out.outline:
			var q := xf * Vector3(_xz(p).x, 0, _xz(p).y)
			o.append([_r(q.x), _r(q.z)])
		out["outline"] = o
	if out.has("rot"):
		out["rot"] = _r(fposmod(float(out.rot) + rot_deg, 360.0))
	return out


static func _shift(e: Dictionary, by: Vector2) -> Dictionary:
	for key: String in ["at", "a", "b"]:
		if e.has(key):
			var p := _v3(e[key])
			e[key] = [_r(p.x + by.x), _r(p.y), _r(p.z + by.y)]
	if e.has("outline"):
		var o: Array = []
		for p: Variant in e.outline:
			o.append([_r(_xz(p).x + by.x), _r(_xz(p).y + by.y)])
		e["outline"] = o
	return e


static func _part_inside(e: Dictionary, outline: Array) -> bool:
	if e.has("at"):
		return _in(outline, _v3(e.at))
	if e.has("a") and e.has("b"):
		var a := _v3(e.a)
		var b := _v3(e.b)
		return _in(outline, a) and _in(outline, b) and _in(outline, (a + b) / 2.0)
	if e.has("outline"):
		var pts: Array = e.outline
		if pts.is_empty():
			return false
		for p: Variant in pts:
			if not _in(outline, Vector3(_xz(p).x, 0, _xz(p).y)):
				return false
		return true
	return false


static func _in(outline: Array, p: Vector3) -> bool:
	if BuildingModel.outline_has_point(outline, p.x, p.z):
		return true
	var q := Vector2(p.x, p.z)
	for i in outline.size():
		var a := _xz(outline[i])
		var b := _xz(outline[(i + 1) % outline.size()])
		if Geometry2D.get_closest_point_to_segment(q, a, b).distance_to(q) <= EDGE:
			return true
	return false


## An existing wall on `level` (or one already placed in this batch) that covers a-b.
static func _covering_wall(model: BuildingModel, level: int, a: Vector3, b: Vector3, _placed: Array) -> String:
	for pid: String in model.parts_on(level):
		var e: Dictionary = model.parts[pid]
		if model.catalog.family_of(str(e.kind)) != "wall" or not e.has("a"):
			continue
		var wa := Vector2(_v3(e.a).x, _v3(e.a).z)
		var wb := Vector2(_v3(e.b).x, _v3(e.b).z)
		var ok := true
		for p: Vector3 in [a, b]:
			var q := Vector2(p.x, p.z)
			if Geometry2D.get_closest_point_to_segment(q, wa, wb).distance_to(q) > EDGE:
				ok = false
				break
		if ok:
			return pid
	return ""


static func _opening_near(model: BuildingModel, wall: String, t: float, w: float) -> bool:
	for pid: String in model.parts:
		var e: Dictionary = model.parts[pid]
		if str(e.get("host", "")) == wall:
			var ow := float(model.catalog.kind(str(e.kind)).get("w", 1.0))
			if absf(float(e.t) - t) < (ow + w) / 2.0:
				return true
	return false


static func _plain_outline(o: Variant) -> Array:
	var out: Array = []
	for p: Variant in o:
		var v := _xz(p)
		out.append([v.x, v.y])
	return out


static func _xz(p: Variant) -> Vector2:
	if p is Vector2:
		return p
	if p is Array:
		return Vector2(float(p[0]), float(p[1]))
	return Vector2.ZERO


static func _v3(a: Variant) -> Vector3:
	if a is Vector3:
		return a
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


static func _r(v: float) -> float:
	return snappedf(v, 0.001)


static func _id_less(x: String, y: String) -> bool:
	var a := x.substr(1).to_int()
	var b := y.substr(1).to_int()
	return a < b if a != b else x < y
