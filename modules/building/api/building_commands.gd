class_name BuildingCommands
extends RefCounted
## Builds the ops BuildingModel.apply() takes, so tools never spell them by hand. Every
## function returns a plain Dictionary op; nothing is applied here.
##
##   var op := BuildingCommands.place_part("column", 0, {"at": Vector3(0, 0, 0)}, "steel")
##   history.commit(op, author)
##
## Geometry may be given as Vector3 / Vector2 / PackedVector2Array; it is turned into
## arrays here, since ops travel as plain data.


## A part of a catalog kind on a level. geometry holds the shape's fields (see
## BuildingModel): {at, rot?, height?}, {a, b, height?}, {outline, y?, pitch?}.
## material and section default to the kind's first.
static func place_part(kind: String, level: int, geometry: Dictionary, material: String = "", section: String = "") -> Dictionary:
	var e := plain(geometry) as Dictionary
	e["kind"] = kind
	e["level"] = level
	if material != "":
		e["material"] = material
	if section != "":
		e["section"] = section
	return {"op": "add", "table": "parts", "entry": e}


## A door or window in a wall, its centre t metres from the wall's a end.
static func place_opening(kind: String, wall_id: String, t: float, material: String = "") -> Dictionary:
	var e := {"kind": kind, "host": wall_id, "t": t}
	if material != "":
		e["material"] = material
	return {"op": "add", "table": "parts", "entry": e}


## A room of a catalog type painted on a level.
static func place_room(type: String, level: int, outline: Variant, room_name: String = "") -> Dictionary:
	return {"op": "add", "table": "rooms", "entry": {"type": type, "level": level, "outline": plain(outline), "name": room_name}}


## A rectangle outline from one corner (x, z) and its size, for rooms and slabs.
static func rect(x: float, z: float, w: float, d: float) -> Array:
	return [[x, z], [x + w, z], [x + w, z + d], [x, z + d]]


static func connect_parts(a: String, b: String, kind: String = "pinned") -> Dictionary:
	return {"op": "add", "table": "connections", "entry": {"a": a, "b": b, "kind": kind}}


static func move(ids: Array, by: Vector3) -> Dictionary:
	return {"op": "move", "ids": ids.duplicate(), "by": [by.x, by.y, by.z]}


## Deletes parts, rooms or connections (with what depends on them).
static func delete(ids: Array) -> Dictionary:
	return {"op": "remove", "ids": ids.duplicate()}


## A room's new type, or a part's new kind.
static func retag(id: String, type: String) -> Dictionary:
	return {"op": "retag", "id": id, "type": type}


## Any other change to an entry: material, section, height, name... (null removes a field).
static func set_fields(id: String, fields: Dictionary) -> Dictionary:
	return {"op": "set", "id": id, "fields": plain(fields)}


static func add_level(height: float = BuildingModel.DEFAULT_LEVEL_HEIGHT, level_name: String = "", index: int = -1) -> Dictionary:
	var op := {"op": "add_level", "height": height, "name": level_name}
	if index >= 0:
		op["index"] = index
	return op


static func set_level(index: int, fields: Dictionary) -> Dictionary:
	return {"op": "set_level", "index": index, "fields": fields.duplicate()}


static func remove_level(index: int) -> Dictionary:
	return {"op": "remove_level", "index": index}


static func set_design_meta(fields: Dictionary) -> Dictionary:
	return {"op": "set_meta", "fields": plain(fields)}


## Several ops as one edit: all apply or none, and one undo takes them all back.
static func batch(ops: Array) -> Dictionary:
	return {"op": "batch", "ops": ops.duplicate(true)}


## Vectors and packed arrays turned into plain arrays, recursively.
static func plain(v: Variant) -> Variant:
	if v is Vector3:
		return [v.x, v.y, v.z]
	if v is Vector2:
		return [v.x, v.y]
	if v is PackedVector2Array:
		var out: Array = []
		for p: Vector2 in v:
			out.append([p.x, p.y])
		return out
	if v is PackedVector3Array:
		var out3: Array = []
		for p: Vector3 in v:
			out3.append([p.x, p.y, p.z])
		return out3
	if v is Array:
		var a: Array = []
		for x: Variant in v:
			a.append(plain(x))
		return a
	if v is Dictionary:
		var d := {}
		for k: Variant in v:
			d[k] = plain(v[k])
		return d
	return v
