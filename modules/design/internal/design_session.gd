class_name DesignSession
extends Node
## The design room's logic, apart from any scene: the tools, picking, snapping, drags with
## soft locks, undo and redo, levels, and the design library. The room scene feeds it pointer
## positions (world metres, already on the working level's floor plane) and draws what it
## says; tests drive it the same way, two sessions on two buses for co-op.
##
##   var s := DesignSession.new()
##   s.setup(net, building_model, building_sync)
##   s.set_tool("wall"); s.press(Vector3(0, 0, 0)); s.press(Vector3(5, 0, 0))   # one wall
##
## Tools (TOOLS): select, wall, partition, room, slab, raft, roof, column, beam, footing,
## pad, door, window, fixture. Two-point tools (walls, beams, rooms, slabs) take a press for
## each corner, or one press-drag-release.

signal tool_changed(tool: String)
signal level_changed(level: int)
signal status(text: String, warn: bool)
## The ghost of what the current tool would place, or the drag offset (see preview()).
signal preview_changed

const C := preload("res://modules/building/api/building_commands.gd")

const TOOLS: Array[Dictionary] = [
	{"id": "select", "label": "Select / move", "key": KEY_1, "hint": "Click to select (Shift adds), drag to move, Del deletes"},
	{"id": "room", "label": "Room", "key": KEY_2, "hint": "Drag a rectangle to paint a room; walls go round it when Walls is on"},
	{"id": "wall", "label": "Wall", "key": KEY_3, "hint": "Click the start, then each corner; right click or Esc ends the run"},
	{"id": "partition", "label": "Partition", "key": KEY_4, "hint": "Like Wall, for internal non-load-bearing walls"},
	{"id": "door", "label": "Door", "key": KEY_5, "hint": "Click on a wall to put a door in it"},
	{"id": "window", "label": "Window", "key": KEY_6, "hint": "Click on a wall to put a window in it"},
	{"id": "slab", "label": "Floor slab", "key": KEY_7, "hint": "Drag a rectangle for a floor slab on this level"},
	{"id": "column", "label": "Column", "key": KEY_8, "hint": "Click to place a column"},
	{"id": "beam", "label": "Beam", "key": KEY_9, "hint": "Click both ends; beams sit at the ceiling of this level"},
	{"id": "roof", "label": "Roof", "key": KEY_0, "hint": "Drag a rectangle for a flat roof over this level"},
	{"id": "raft", "label": "Raft", "key": KEY_NONE, "hint": "Drag a rectangle for a raft foundation (ground level)"},
	{"id": "footing", "label": "Strip footing", "key": KEY_NONE, "hint": "Click both ends of a strip footing under a wall"},
	{"id": "pad", "label": "Pad footing", "key": KEY_NONE, "hint": "Click to place a pad footing under a column"},
	{"id": "fixture", "label": "Furniture", "key": KEY_NONE, "hint": "Click to place the chosen fixture; R turns it"},
]
## Catalog kind each placing tool makes.
const KIND := {"wall": "wall_loadbearing", "partition": "wall_partition", "slab": "slab", "roof": "roof_flat",
		"raft": "raft", "column": "column", "beam": "beam", "footing": "strip_footing", "pad": "pad_footing"}
const TWO_POINT := ["wall", "partition", "beam", "footing"]
const RECT := ["room", "slab", "roof", "raft"]
const POINT := ["column", "pad", "fixture"]
const OPENING := ["door", "window"]
## How near the pointer must be to pick a line part beyond its half-thickness, m.
const PICK_REACH := 0.35
## Pointer travel that turns a press into a drag, m.
const DRAG_START := 0.1
const GRIDS: Array[float] = [0.1, 0.25, 0.5, 1.0]

var net: MultiplayerBus
var model: BuildingModel
var sync: BuildingSync
var presence: DesignPresence
var catalog: BuildingCatalog

var tool := "select"
var level := 0
var grid := 0.25
## Tool options: room type, door and window kinds, fixture kind and turn, wall material.
var room_type := "bedroom"
var door_kind := "door_internal"
var window_kind := "window_medium"
var fixture_kind := "bed_double"
var fixture_rot := 0.0
var wall_material := "masonry"
var frame_material := "steel"
## Room tool: put walls round each new room where none stand yet.
var auto_walls := true

## Where the pointer is (snapped) or null; the first corner of a two-point tool or null.
var cursor: Variant = null
var anchor: Variant = null
## The drag in progress: {ids, from, by, group} or {}.
var drag: Dictionary = {}
var _press: Variant = null
var _pressed_on := ""
var _group_n := 0


func setup(bus: MultiplayerBus, m: BuildingModel, s: BuildingSync) -> void:
	net = bus
	model = m
	sync = s
	catalog = m.catalog
	grid = float(model.meta.get("grid", BuildingModel.DEFAULT_GRID))
	presence = DesignPresence.new()
	presence.name = "Presence"
	add_child(presence)
	presence.bind(net)
	sync.rejected.connect(_on_sync_rejected)
	net.request_rejected.connect(_on_rejected)
	model.loaded.connect(_on_loaded)
	model.levels_changed.connect(_on_levels_changed)


func teardown() -> void:
	cancel()
	if presence:
		presence.unlock(presence.my_locks())
		presence.select(PackedStringArray())
		presence.unbind()
	if sync and sync.rejected.is_connected(_on_sync_rejected):
		sync.rejected.disconnect(_on_sync_rejected)
		net.request_rejected.disconnect(_on_rejected)
		model.loaded.disconnect(_on_loaded)
		model.levels_changed.disconnect(_on_levels_changed)


func _on_sync_rejected(why: String) -> void:
	status.emit("Refused: %s" % why, true)


func _on_levels_changed() -> void:
	set_level(level)


func _on_rejected(event_name: String, why: String) -> void:
	if event_name.begins_with("design.") or event_name.begins_with("net."):
		status.emit("Refused: %s" % why, true)


func _on_loaded() -> void:
	cancel()
	set_level(clampi(level, 0, model.level_count() - 1))
	presence.select(PackedStringArray())


# --- Tools, levels, grid ----------------------------------------------------------------

func set_tool(id: String) -> void:
	cancel()
	tool = id
	tool_changed.emit(id)
	for t: Dictionary in TOOLS:
		if t.id == id:
			status.emit(str(t.hint), false)
	net.set_activity("Design: %s" % id)


func set_level(l: int) -> void:
	level = clampi(l, 0, model.level_count() - 1)
	cancel()
	level_changed.emit(level)


func floor_y() -> float:
	return model.level_elevation(level)


func set_grid(g: float) -> void:
	grid = g


## Adds a storey on top and moves up to it.
func add_level() -> void:
	sync.edit(C.add_level(model.level_height(model.level_count() - 1), "Level %d" % model.level_count()))
	set_level.call_deferred(model.level_count() - 1)


func snap(p: Vector3) -> Vector3:
	var corners: Array = []
	for pid in model.parts_on(level):
		var e: Dictionary = model.parts[pid]
		if e.has("a"):
			for k: String in ["a", "b"]:
				corners.append(Vector3(float(e[k][0]), 0.0, float(e[k][2])) + Vector3(0, floor_y(), 0))
	var at := DesignSnap.point(Vector3(p.x, floor_y(), p.z), grid, corners)
	return at


# --- Pointer ----------------------------------------------------------------------------

## The pointer moved to p (on the working floor), or off the plot (null).
func hover(p: Variant) -> void:
	if p == null:
		cursor = null
		presence.set_cursor(null)
		preview_changed.emit()
		return
	var at := snap(p)
	if anchor != null and tool in TWO_POINT:
		at = DesignSnap.run(anchor, at, grid)
	cursor = at
	presence.set_cursor(at)
	if not drag.is_empty():
		var by: Vector3 = at - (drag.from as Vector3)
		by.y = 0.0
		drag.by = by
		presence.lock(PackedStringArray(drag.ids))
	elif _press != null and tool == "select" and _pressed_on != "" \
			and (at - (_press as Vector3)).length() >= DRAG_START:
		_start_drag()
	preview_changed.emit()


func press(p: Vector3, add := false) -> void:
	hover(p)
	var at: Vector3 = cursor
	if tool == "select":
		var hit := pick(at)
		_press = at
		_pressed_on = hit
		var sel := presence.my_selection()
		if hit == "":
			if not add:
				presence.select(PackedStringArray())
		elif add:
			if hit in sel:
				var keep := PackedStringArray()
				for id in sel:
					if id != hit:
						keep.append(id)
				presence.select(keep)
			else:
				sel.append(hit)
				presence.select(sel)
		elif not hit in sel:
			presence.select(PackedStringArray([hit]))
		return
	if tool in POINT:
		_place_point(at)
	elif tool in OPENING:
		_place_opening(at)
	elif tool in TWO_POINT or tool in RECT:
		if anchor == null:
			anchor = at
			presence.set_anchor(at)
		else:
			_finish_two_point(at)
	preview_changed.emit()


func release(p: Vector3) -> void:
	hover(p)
	if tool == "select":
		if not drag.is_empty():
			_end_drag()
		_press = null
		_pressed_on = ""
		return
	# A press-drag-release draws a rectangle in one go.
	if tool in RECT and anchor != null and cursor != null:
		var span: Vector3 = (cursor as Vector3) - (anchor as Vector3)
		if absf(span.x) >= grid and absf(span.z) >= grid:
			_finish_two_point(cursor)


## Esc or right click: drops the drag or the half-drawn part.
func cancel() -> void:
	if not drag.is_empty():
		presence.unlock(PackedStringArray(drag.ids))
		drag = {}
	_press = null
	_pressed_on = ""
	anchor = null
	if presence:
		presence.set_anchor(null)
	preview_changed.emit()


func _start_drag() -> void:
	var ids := presence.my_selection()
	if not _pressed_on in ids:
		ids = PackedStringArray([_pressed_on])
	for id in ids:
		if not presence.may_edit(id):
			status.emit("%s is moving that" % net.player_name(presence.locked_by(id)), true)
			_press = null
			return
	_group_n += 1
	drag = {"ids": Array(ids), "from": _press, "by": Vector3.ZERO,
			"group": "drag-%d-%d" % [net.local_peer_id(), _group_n]}
	presence.lock(ids)


func _end_drag() -> void:
	var by: Vector3 = drag.by
	var ids: Array = drag.ids
	if by.length() > 0.001:
		sync.edit(C.move(ids, by), drag.group)
	presence.unlock(PackedStringArray(ids))
	drag = {}
	preview_changed.emit()


# --- Placing ----------------------------------------------------------------------------

func _local(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)


func _place_point(at: Vector3) -> void:
	var kind := fixture_kind if tool == "fixture" else str(KIND[tool])
	var mat := frame_material if tool == "column" else ""
	if not mat in catalog.materials_for(kind):
		mat = ""
	var geom := {"at": _local(at)}
	if tool == "fixture":
		geom["rot"] = fixture_rot
	sync.edit(C.place_part(kind, level, geom, mat))


func _place_opening(at: Vector3) -> void:
	var wall := wall_at(at)
	if wall == "":
		status.emit("Point at a wall to put a %s in it" % tool, true)
		return
	var e: Dictionary = model.parts[wall]
	var a := _v3(e.a)
	var b := _v3(e.b)
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	var kind := door_kind if tool == "door" else window_kind
	var w := float(catalog.kind(kind).get("w", 1.0))
	var t := snappedf(DesignSnap.along(_local(at), a, b), grid)
	t = clampf(t, w / 2.0, maxf(w / 2.0, length - w / 2.0))
	sync.edit(C.place_opening(kind, wall, t))


func _finish_two_point(end: Vector3) -> void:
	var start: Vector3 = anchor
	if tool in RECT:
		var r := DesignSnap.rect(start, end, grid)
		var w := r[1].x - r[0].x
		var d := r[1].z - r[0].z
		if w < grid or d < grid:
			return
		var outline := C.rect(r[0].x, r[0].z, w, d)
		match tool:
			"room":
				_place_room(outline)
			"roof":
				sync.edit(C.place_part("roof_flat", level, {"outline": outline, "y": model.level_height(level)}, "timber"))
			"raft":
				sync.edit(C.place_part("raft", 0, {"outline": outline, "y": 0.0}))
			_:
				sync.edit(C.place_part("slab", level, {"outline": outline, "y": 0.0}, "concrete" if level == 0 else "timber"))
		anchor = null
		presence.set_anchor(null)
		return
	if (end - start).length() < BuildingModel.MIN_LENGTH:
		return
	var kind := str(KIND[tool])
	var a := _local(start)
	var b := _local(end)
	var mat := ""
	match tool:
		"wall":
			mat = wall_material
		"partition":
			mat = "timber"
		"beam":
			mat = frame_material
			a.y = model.level_height(level)
			b.y = a.y
	if not mat in catalog.materials_for(kind):
		mat = ""
	sync.edit(C.place_part(kind, level, {"a": a, "b": b}, mat))
	# Walls chain: the next one starts where this one ended.
	if tool in ["wall", "partition"]:
		anchor = end
		presence.set_anchor(end)
	else:
		anchor = null
		presence.set_anchor(null)


func _place_room(outline: Array) -> void:
	var ops: Array = [C.place_room(room_type, level, outline)]
	if auto_walls:
		for i in outline.size():
			var p: Array = outline[i]
			var q: Array = outline[(i + 1) % outline.size()]
			for run: Array in uncovered(Vector3(p[0], 0, p[1]), Vector3(q[0], 0, q[1])):
				ops.append(C.place_part("wall_loadbearing", level, {"a": run[0], "b": run[1]}, wall_material))
	sync.edit(C.batch(ops) if ops.size() > 1 else ops[0])


## The parts of the line a-b (level-local, plan) that no wall on this level already covers,
## as [[from, to], ...], so rooms side by side share one wall.
func uncovered(a: Vector3, b: Vector3) -> Array:
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	if length < BuildingModel.MIN_LENGTH:
		return []
	var covered: Array = []
	for pid in model.parts_on(level):
		var e: Dictionary = model.parts[pid]
		if catalog.family_of(str(e.kind)) != "wall":
			continue
		var wa := _v3(e.a)
		var wb := _v3(e.b)
		if DesignSnap.plan_distance(wa, a, b) > 0.05 or DesignSnap.plan_distance(wb, a, b) > 0.05:
			continue
		var s := DesignSnap.along(wa, a, b)
		var t := DesignSnap.along(wb, a, b)
		covered.append([minf(s, t), maxf(s, t)])
	covered.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var out: Array = []
	var at := 0.0
	var dir := (b - a) / length
	for c: Array in covered:
		if c[0] - at > BuildingModel.MIN_LENGTH:
			out.append([a + dir * at, a + dir * c[0]])
		at = maxf(at, c[1])
	if length - at > BuildingModel.MIN_LENGTH:
		out.append([a + dir * at, b])
	return out


# --- Selection, delete, undo --------------------------------------------------------------

func delete_selection() -> void:
	var ids := presence.my_selection()
	var ok: Array = []
	for id in ids:
		if model.has(id):
			if presence.may_edit(id):
				ok.append(id)
			else:
				status.emit("%s is moving that" % net.player_name(presence.locked_by(id)), true)
	if not ok.is_empty():
		sync.edit(C.delete(ok))
		presence.select(PackedStringArray())


## Turns the fixture ghost, or the selected fixtures, a quarter turn.
func rotate() -> void:
	if tool == "fixture":
		fixture_rot = fposmod(fixture_rot + 90.0, 360.0)
		preview_changed.emit()
		return
	var ops: Array = []
	for id in presence.my_selection():
		var e: Dictionary = model.parts.get(id, {})
		if e.has("rot") and presence.may_edit(id):
			ops.append(C.set_fields(id, {"rot": fposmod(float(e.rot) + 90.0, 360.0)}))
	if not ops.is_empty():
		sync.edit(C.batch(ops))


## Retags the selected rooms to the current room type.
func retag_selection() -> void:
	for id in presence.my_selection():
		if model.rooms.has(id) and presence.may_edit(id):
			sync.edit(C.retag(id, room_type))


func undo() -> void:
	cancel()
	sync.undo()


func redo() -> void:
	cancel()
	sync.redo()


# --- Picking ------------------------------------------------------------------------------

## The entry under a point on this level: openings, then point and line parts, then rooms,
## then slabs and roofs. "" for none.
func pick(at: Vector3) -> String:
	var p := _local(at)
	var best := ""
	var best_d := INF
	for pid in model.parts_on(level):
		var e: Dictionary = model.parts[pid]
		var kind := str(e.kind)
		var sec := catalog.section(str(e.get("section", "")))
		var d := INF
		var reach := PICK_REACH
		match catalog.shape_of(kind):
			"opening":
				var pts := model.points_of(pid)
				d = DesignSnap.plan_distance(p + Vector3(0, floor_y(), 0), pts[0], pts[1]) - 0.2
			"point":
				var spec := catalog.kind(kind)
				var r := maxf(float(spec.get("w", sec.get("w", 0.3))), float(spec.get("d", sec.get("d", 0.3)))) * 0.5
				d = Vector2(p.x - float(e.at[0]), p.z - float(e.at[2])).length() - r
			"line":
				d = DesignSnap.plan_distance(p, _v3(e.a), _v3(e.b)) - float(sec.get("d", 0.2)) * 0.5
		# Small things (openings, columns, fixtures) win over the walls and beams they sit on.
		if catalog.shape_of(kind) == "line":
			d += reach
		if d < reach * 2.0 and d < best_d and (catalog.shape_of(kind) == "line" or d < reach):
			best_d = d
			best = pid
	if best != "":
		return best
	for rid in model.rooms_on(level):
		if BuildingModel.outline_has_point(model.rooms[rid].outline, p.x, p.z):
			return rid
	for pid in model.parts_on(level):
		var e: Dictionary = model.parts[pid]
		if catalog.shape_of(str(e.kind)) == "area" and BuildingModel.outline_has_point(e.outline, p.x, p.z):
			return pid
	return ""


## The wall on this level nearest the point, within reach; "".
func wall_at(at: Vector3) -> String:
	var p := _local(at)
	var best := ""
	var best_d := 0.6
	for pid in model.parts_on(level):
		var e: Dictionary = model.parts[pid]
		if catalog.family_of(str(e.kind)) == "wall":
			var d := DesignSnap.plan_distance(p, _v3(e.a), _v3(e.b))
			if d < best_d:
				best_d = d
				best = pid
	return best


## What the views should draw for this player's tool right now:
##   {"kind": "line", "a", "b"} · {"kind": "rect", "a", "b"} · {"kind": "point", "at"}
##   {"kind": "move", "ids", "by"} · {"kind": "opening", "wall", "at"} · {} for nothing.
func preview() -> Dictionary:
	if not drag.is_empty():
		return {"kind": "move", "ids": drag.ids, "by": drag.by}
	if cursor == null:
		return {}
	if tool in TWO_POINT and anchor != null:
		return {"kind": "line", "a": anchor, "b": cursor}
	if tool in RECT and anchor != null:
		var r := DesignSnap.rect(anchor, cursor, grid)
		return {"kind": "rect", "a": r[0], "b": r[1]}
	if tool in OPENING:
		return {"kind": "opening", "wall": wall_at(cursor), "at": cursor}
	if tool in POINT:
		return {"kind": "point", "at": cursor}
	return {}


# --- Design library -------------------------------------------------------------------------

const LIBRARY := "user://designs"


static func design_path(design_name: String) -> String:
	var safe := design_name.strip_edges().validate_filename().replace(" ", "_")
	return "%s/%s.json" % [LIBRARY, safe if safe != "" else "design"]


## Saves the open design to the library under a name. Every player can save their own copy.
func save_design(design_name: String) -> Error:
	DirAccess.make_dir_recursive_absolute(LIBRARY)
	var data := model.to_data()
	data.name = design_name
	var f := FileAccess.open(design_path(design_name), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	status.emit("Saved \"%s\"" % design_name, false)
	return OK


## Loads a saved design for everyone in the session (the host checks it).
func load_design(design_name: String) -> Error:
	var text := FileAccess.get_file_as_string(design_path(design_name))
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		status.emit("No design called \"%s\"" % design_name, true)
		return ERR_FILE_NOT_FOUND
	sync.load_design(data)
	status.emit("Loading \"%s\" for everyone" % design_name, false)
	return OK


func new_design() -> void:
	sync.load_design(BuildingModel.new("", "New building", catalog).to_data())


static func list_designs() -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(LIBRARY)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".json"):
			out.append(f.trim_suffix(".json").replace("_", " "))
	out.sort()
	return out


static func _v3(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
