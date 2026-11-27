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
## The Note tool was clicked: the HUD asks for the text, then calls add_note().
signal note_requested(at: Vector3, target: String)
## This player's tape measure changed: a and b in world space, or nulls.
signal measure_changed(a: Variant, b: Variant)

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
	{"id": "roof", "label": "Roof", "key": KEY_0, "hint": "Drag a rectangle for a roof over this level: flat, gable, hip or mono-pitch"},
	{"id": "raft", "label": "Raft", "key": KEY_NONE, "hint": "Drag a rectangle for a raft foundation (ground level)"},
	{"id": "footing", "label": "Strip footing", "key": KEY_NONE, "hint": "Click both ends of a strip footing under a wall"},
	{"id": "pad", "label": "Pad footing", "key": KEY_NONE, "hint": "Click to place a pad footing under a column"},
	{"id": "stair", "label": "Stair", "key": KEY_NONE, "hint": "Click the foot of the flight, then its head; it rises to the level above"},
	{"id": "lift", "label": "Lift", "key": KEY_NONE, "hint": "Click to place a lift shaft running up to the top level"},
	{"id": "fixture", "label": "Furniture", "key": KEY_NONE, "hint": "Click to place the chosen fixture; R turns it"},
	{"id": "note", "label": "Note", "key": KEY_N, "hint": "Click a spot or a part to pin a note for the team"},
	{"id": "measure", "label": "Measure", "key": KEY_M, "hint": "Click two points to measure between them"},
]
## Catalog kind each placing tool makes.
const KIND := {"wall": "wall_loadbearing", "partition": "wall_partition", "slab": "slab", "roof": "roof_flat",
		"raft": "raft", "column": "column", "beam": "beam", "footing": "strip_footing", "pad": "pad_footing"}
const TWO_POINT := ["wall", "partition", "beam", "footing", "measure", "stair"]
const RECT := ["room", "slab", "roof", "raft"]
const POINT := ["column", "pad", "fixture", "lift"]
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
## Snapping to the grid (G) and lining up with the alignment guides (Shift+G); Alt held skips
## both for a moment.
var snap_grid := true
## The Roof tool's form and pitch (degrees) for pitched forms.
var roof_form := "flat"
var roof_pitch := 35.0
const ROOF_KINDS := {"flat": "roof_flat", "gable": "roof_pitched", "hip": "roof_hip", "mono": "roof_mono"}
const ROOF_LABELS := {"flat": "Flat", "gable": "Gable (pitched)", "hip": "Hipped", "mono": "Mono-pitch"}
var snap_guides := true
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
## Reshaping a room (select tool, one room selected): {room, base: Array[Vector2], mode
## ("corner", "mid" or "edge"), i, from: Vector3, outline: Array[Vector2]} or {}.
var shape: Dictionary = {}
## How near the pointer must be to a corner or edge handle, m (the room sets it from zoom).
var handle_reach := 0.35
## A left drag on empty floor with nothing selected pans the view (the room moves the camera).
var pan_drag := false
## Alignment guides showing now ([[Vector2, Vector2], ...], plan metres): what's being placed
## or moved lines up with another room's or part's edge or middle. Alt held: none.
var guides: Array = []
## The room sets this while it places something of its own (a saved module): guides then too.
var placing := false
## Its plan size while placing (a paste), so the guides line up its edges, not just its middle.
var placing_size := Vector2.ZERO
var _guide_boxes: Array[Rect2] = []
var _guide_key := ""
## The pan moved the view (the room says so); a press and release on empty floor that didn't
## pan clears the selection instead.
var pan_moved := false
## Shift-drag on empty floor: the box being drawn, {a, b} (plan points), or empty.
var box := {}
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


## Arms the tool that places a catalog kind: Furniture, Door or Window (the palette, kits).
func use_kind(kind: String) -> bool:
	if not catalog.has_kind(kind):
		return false
	var fam := catalog.family_of(kind)
	if fam == "opening":
		if kind.begins_with("window") or bool(catalog.kind(kind).get("glass", false)):
			window_kind = kind
			set_tool("window")
		else:
			door_kind = kind
			set_tool("door")
	elif fam == "fixture":
		fixture_kind = kind
		set_tool("fixture")
	else:
		return false
	status.emit("%s: click to place it (R turns it)" % str(catalog.kind(kind).get("label", kind)), false)
	return true


## Arms the Room tool with a room type: drag on the plan to size it, let go to draw it.
func use_room_type(type_id: String) -> void:
	room_type = type_id
	set_tool("room")
	status.emit("%s: drag on the plan to size it, let go to draw it" % str(catalog.room_type(type_id).get("label", type_id)), false)


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


## The roof forms the catalog has kinds for.
func roof_forms() -> PackedStringArray:
	var out := PackedStringArray()
	for f: String in ROOF_KINDS:
		if catalog.has_kind(str(ROOF_KINDS[f])):
			out.append(f)
	return out


## The step points snap to: the grid, or 0 with grid snapping off (or Alt held).
func snap_step() -> float:
	return grid if snap_grid and not Input.is_key_pressed(KEY_ALT) else 0.0


## The smallest room or slab side that counts as drawn (not a slip of the mouse).
func min_size() -> float:
	return maxf(snap_step(), 0.1)


func snap(p: Vector3) -> Vector3:
	var corners: Array = []
	for pid in model.parts_on(level):
		var e: Dictionary = model.parts[pid]
		if e.has("a"):
			for k: String in ["a", "b"]:
				corners.append(Vector3(float(e[k][0]), 0.0, float(e[k][2])) + Vector3(0, floor_y(), 0))
	var at := DesignSnap.point(Vector3(p.x, floor_y(), p.z), snap_step(), corners)
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
	if anchor != null and tool in TWO_POINT and tool != "measure":
		at = DesignSnap.run(anchor, at, snap_step())
	at = _align(at)
	cursor = at
	presence.set_cursor(at)
	if not shape.is_empty():
		_update_shape(at)
	elif not box.is_empty():
		box.b = at
	elif not drag.is_empty():
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
		var sh := shape_hit(p)
		if not sh.is_empty() and not add:
			_begin_shape(sh, at)
			return
		var hit := pick(at)
		# Empty floor: a drag pans the plan (a click clears the selection); with Shift, a
		# drag draws a box that selects everything inside it.
		pan_drag = hit == "" and not add
		pan_moved = false
		if pan_drag:
			_press = null
			_pressed_on = ""
			return
		if hit == "" and add:
			box = {"a": at, "b": at}
			_press = null
			_pressed_on = ""
			preview_changed.emit()
			return
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
	if tool == "note":
		note_requested.emit(at, pick(at))
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
		if pan_drag and not pan_moved:
			presence.select(PackedStringArray())
		pan_drag = false
		if not box.is_empty():
			box.b = cursor if cursor != null else box.b
			var ids := ids_in_box(box.a as Vector3, box.b as Vector3)
			box = {}
			var sel := presence.my_selection()
			for id in ids:
				if not id in sel:
					sel.append(id)
			presence.select(sel)
			if not ids.is_empty():
				status.emit("%d selected: Del deletes them, drag one to move them all" % sel.size(), false)
			preview_changed.emit()
		if not shape.is_empty():
			_end_shape()
		if not drag.is_empty():
			_end_drag()
		_press = null
		_pressed_on = ""
		return
	# A press-drag-release draws a rectangle in one go.
	if tool in RECT and anchor != null and cursor != null:
		var span: Vector3 = (cursor as Vector3) - (anchor as Vector3)
		if absf(span.x) >= min_size() and absf(span.z) >= min_size():
			_finish_two_point(cursor)


## Every room and part on this level that lies wholly inside the plan box a..b.
func ids_in_box(a: Vector3, b: Vector3) -> PackedStringArray:
	var lo := Vector2(minf(a.x, b.x), minf(a.z, b.z))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.z, b.z))
	var out := PackedStringArray()
	if hi.x - lo.x < 0.01 and hi.y - lo.y < 0.01:
		return out
	var inside := func(pts: Array) -> bool:
		for q: Vector2 in pts:
			if q.x < lo.x - 0.001 or q.x > hi.x + 0.001 or q.y < lo.y - 0.001 or q.y > hi.y + 0.001:
				return false
		return not pts.is_empty()
	for rid in model.rooms_on(level):
		var pts: Array = []
		for c: Array in model.rooms[rid].get("outline", []):
			pts.append(Vector2(float(c[0]), float(c[1])))
		if inside.call(pts):
			out.append(rid)
	for pid in model.parts_on(level):
		var bb: AABB = model.aabb_of(pid)
		if inside.call([Vector2(bb.position.x, bb.position.z), Vector2(bb.end.x, bb.end.z)]):
			out.append(pid)
	return out


## Lines `at` up with nearby rooms and parts (DesignGuides) while something is being placed,
## drawn, reshaped or moved; sets `guides`.
func _align(at: Vector3) -> Vector3:
	guides = []
	if not snap_guides or Input.is_key_pressed(KEY_ALT):
		return at
	var skip := PackedStringArray()
	var box := Rect2()
	var p2 := Vector2(at.x, at.z)
	if not drag.is_empty():
		skip = PackedStringArray(drag.ids)
		var from := drag.from as Vector3
		box = DesignGuides.box_of(model, skip)
		box.position += Vector2(at.x - from.x, at.z - from.z)
	elif not shape.is_empty():
		skip = PackedStringArray([str(shape.room)])
		box = Rect2(p2, Vector2.ZERO)
	elif placing:
		# A stamp or paste: its plan size (turned), so its edges and middle line up.
		box = Rect2(p2 - placing_size * 0.5, placing_size)
	elif tool in TWO_POINT or tool in RECT:
		box = Rect2(p2, Vector2.ZERO)
	elif tool in POINT:
		var k := catalog.kind(fixture_kind if tool == "fixture" else str(KIND.get(tool, tool)))
		var w := float(k.get("w", 0.5))
		var size := Vector2(w, float(k.get("d", w)))
		box = Rect2(p2 - size * 0.5, size)
	else:
		return at
	var key := "%d|%d|%s" % [model.revision, level, ",".join(skip)]
	if key != _guide_key or _guide_boxes.is_empty():
		_guide_key = key
		_guide_boxes = DesignGuides.boxes(model, level, skip)
	# A few pixels on screen, but under half a grid step, so every grid point stays reachable.
	var tol := minf(handle_reach * DesignGuides.SNAP_PX / 12.0, grid * 0.5)
	var al := DesignGuides.align(box, _guide_boxes, tol)
	guides = al.guides
	var off: Vector2 = al.offset
	return at + Vector3(off.x, 0.0, off.y)


## Esc or right click: drops the drag or the half-drawn part.
func cancel() -> void:
	pan_drag = false
	box = {}
	if not shape.is_empty():
		presence.unlock(PackedStringArray([str(shape.room)]))
		shape = {}
	if not drag.is_empty():
		presence.unlock(PackedStringArray(drag.ids))
		drag = {}
	_press = null
	_pressed_on = ""
	anchor = null
	if presence:
		presence.set_anchor(null)
	if tool == "measure":
		measure_changed.emit(null, null)
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
	ids = carried(ids)
	_group_n += 1
	drag = {"ids": Array(ids), "from": _press, "by": Vector3.ZERO,
			"group": "drag-%d-%d" % [net.local_peer_id(), _group_n]}
	presence.lock(ids)


## `ids` plus what moves with the rooms among them: the walls on a room's outline (but those it
## shares with a room that stays) and the parts standing inside it. Doors and windows ride on
## their walls. Without this a room slid along one axis left its walls behind, still lined up
## with its edges, and looked as if it had not moved. shared_walls: shared ones too.
func carried(ids: PackedStringArray, shared_walls := false) -> PackedStringArray:
	var out := ids.duplicate()
	var moving: Array = []
	var staying: Array = []
	for rid in model.rooms_on(level):
		var o := _outline_2d(rid)
		if o.size() >= 3:
			(moving if rid in ids else staying).append(o)
	if moving.is_empty():
		return out
	for pid in model.parts_on(level):
		if pid in out or not presence.may_edit(pid):
			continue
		var e: Dictionary = model.parts[pid]
		var take := false
		if e.has("a") and e.has("b"):
			if catalog.family_of(str(e.kind)) != "wall":
				continue
			var pa := Vector2(float(e.a[0]), float(e.a[2]))
			var pb := Vector2(float(e.b[0]), float(e.b[2]))
			take = moving.any(func(o: PackedVector2Array) -> bool: return _on_outline(pa, pb, o)) \
					and (shared_walls or not staying.any(func(o: PackedVector2Array) -> bool: return _on_outline(pa, pb, o)))
		elif e.has("at"):
			var q := Vector2(float(e.at[0]), float(e.at[2]))
			take = moving.any(func(o: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(q, o))
		if take:
			out.append(pid)
	return out


func _outline_2d(rid: String) -> PackedVector2Array:
	var o := PackedVector2Array()
	for c: Array in model.rooms[rid].get("outline", []):
		o.append(Vector2(float(c[0]), float(c[1])))
	return o


## Whether the run pa-pb lies along one of the outline's edges.
static func _on_outline(pa: Vector2, pb: Vector2, o: PackedVector2Array) -> bool:
	for j in o.size():
		var a := o[j]
		var b := o[(j + 1) % o.size()]
		var len2 := a.distance_squared_to(b)
		if len2 < 0.0001:
			continue
		var t1 := (pa - a).dot(b - a) / len2
		var t2 := (pb - a).dot(b - a) / len2
		if t1 < -0.001 or t1 > 1.001 or t2 < -0.001 or t2 > 1.001:
			continue
		if pa.distance_to(a.lerp(b, t1)) <= 0.02 and pb.distance_to(a.lerp(b, t2)) <= 0.02:
			return true
	return false


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
	if tool == "lift":
		if level >= model.level_count() - 1:
			status.emit("A lift needs a storey above: add one with + Storey first", true)
			return
		sync.edit(C.place_lift(level, _local(at), model.level_count() - 1))
		return
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
	var t := snappedf(DesignSnap.along(_local(at), a, b), snap_step())
	t = clampf(t, w / 2.0, maxf(w / 2.0, length - w / 2.0))
	sync.edit(C.place_opening(kind, wall, t))


func _finish_two_point(end: Vector3) -> void:
	var start: Vector3 = anchor
	if tool in RECT:
		var r := DesignSnap.rect(start, end, snap_step())
		var w := r[1].x - r[0].x
		var d := r[1].z - r[0].z
		if w < min_size() or d < min_size():
			return
		var outline := C.rect(r[0].x, r[0].z, w, d)
		match tool:
			"room":
				_place_room(outline)
			"roof":
				var kind := str(ROOF_KINDS.get(roof_form, "roof_flat"))
				if not catalog.has_kind(kind):
					kind = "roof_flat"
				var geo := {"outline": outline, "y": model.level_height(level)}
				if kind != "roof_flat":
					geo["pitch"] = roof_pitch
				sync.edit(C.place_part(kind, level, geo, "timber"))
			"raft":
				sync.edit(C.place_part("raft", 0, {"outline": outline, "y": 0.0}))
			_:
				sync.edit(C.place_part("slab", level, {"outline": outline, "y": 0.0}, "concrete" if level == 0 else "timber"))
		anchor = null
		presence.set_anchor(null)
		return
	if (end - start).length() < BuildingModel.MIN_LENGTH:
		return
	if tool == "measure":
		measure_changed.emit(start, end)
		anchor = null
		presence.set_anchor(null)
		return
	if tool == "stair":
		anchor = null
		presence.set_anchor(null)
		if level >= model.level_count() - 1:
			status.emit("A stair rises to the level above: add a storey with + Storey first", true)
			return
		sync.edit(C.place_stair(level, _local(start), _local(end), "concrete" if level == 0 else "timber"))
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
	rotate_selection(90.0)


## Turns the selection (rooms with their walls and contents, and parts) by `deg` about its
## middle, as one undo step (or into `group`'s). A lone part turns where it stands.
func rotate_selection(deg: float) -> void:
	var t := _turn_set()
	if t.is_empty():
		return
	var ops := turn_ops(model, t.base, t.centre, deg)
	if not ops.is_empty():
		sync.edit(C.batch(ops))


## Free turning (hold R and move the mouse): begin_turn(), then turn_to(total degrees) as the
## mouse moves, then end_turn(). Every step is set from where things were at the start, so
## it lands the same for everyone however the steps arrive, and the turn is one undo step.
var turn := {}

func begin_turn() -> bool:
	end_turn()
	if tool == "fixture":
		return false
	var t := _turn_set()
	if t.is_empty():
		return false
	_group_n += 1
	t["group"] = "turn-%d-%d" % [net.local_peer_id() if net else 0, _group_n]
	t["deg"] = 0.0
	turn = t
	presence.lock(PackedStringArray(t.base.keys()))
	return true


func turn_to(deg: float) -> void:
	if turn.is_empty() or is_equal_approx(deg, float(turn.deg)):
		return
	turn.deg = deg
	var ops := turn_ops(model, turn.base, turn.centre, deg)
	if not ops.is_empty():
		sync.edit(C.batch(ops), str(turn.group))
	status.emit("Turned %.0f°" % deg if is_equal_approx(deg, roundf(deg)) else "Turned %.1f°" % deg, false)


func end_turn() -> void:
	if turn.is_empty():
		return
	presence.unlock(PackedStringArray(turn.base.keys()))
	turn = {}


## What a turn moves: {base: id -> a copy of the entry as it is, centre: Vector3} or {}.
func _turn_set() -> Dictionary:
	var sel := PackedStringArray()
	for id in presence.my_selection():
		if model.has(id) and presence.may_edit(id):
			sel.append(id)
	if sel.is_empty():
		return {}
	var ids := carried(sel)
	var base := {}
	for id in ids:
		var e := model.entry(id)
		if not e.has("host"):
			base[id] = e.duplicate(true)
	var box := _set_out_box(ids)
	var c := box.get_center()
	if sel.size() == 1 and model.parts.has(sel[0]) and model.parts[sel[0]].has("at"):
		var at: Array = model.parts[sel[0]].at
		c = Vector2(float(at[0]), float(at[2]))
	return {"base": base, "centre": Vector3(c.x, 0, c.y)}


## The ops that set the entries in `base` (id -> entry) turned by `deg` about `centre` (plan),
## as the parts' own "rot" turns: Basis(Vector3.UP, deg). Doors and windows ride on their walls.
static func turn_ops(m: BuildingModel, base: Dictionary, centre: Vector3, deg: float) -> Array:
	var r := deg_to_rad(deg)
	var p3 := func(v: Array) -> Array:
		var q := (Vector3(float(v[0]), 0, float(v[2])) - centre).rotated(Vector3.UP, r) + centre
		return [snappedf(q.x, 0.0001), float(v[1]), snappedf(q.z, 0.0001)]
	var o2 := func(o: Array) -> Array:
		var out: Array = []
		for c: Array in o:
			var q := (Vector3(float(c[0]), 0, float(c[1])) - centre).rotated(Vector3.UP, r) + centre
			out.append([snappedf(q.x, 0.0001), snappedf(q.z, 0.0001)])
		return out
	var ops: Array = []
	for id: String in base:
		if not m.has(id):
			continue
		var e: Dictionary = base[id]
		var fields := {}
		if e.has("at"):
			fields["at"] = p3.call(e.at)
			fields["rot"] = snappedf(fposmod(float(e.get("rot", 0.0)) + deg, 360.0), 0.01)
		elif e.has("a") and e.has("b"):
			fields["a"] = p3.call(e.a)
			fields["b"] = p3.call(e.b)
		elif e.has("outline"):
			fields["outline"] = o2.call(e.outline)
		if not fields.is_empty() and not _same_fields(m.entry(id), fields):
			ops.append(C.set_fields(id, fields))
	return ops


## Retags the selected rooms to the current room type.
func retag_selection() -> void:
	for id in presence.my_selection():
		if model.rooms.has(id) and presence.may_edit(id):
			sync.edit(C.retag(id, room_type))


## Mirrors the selection (with its rooms' walls and what stands in them) for symmetrical
## designs, as one undo step. axis 0 mirrors left-right (x), 1 up-down (z). As a copy, the
## mirror line is the selection's right (or bottom) edge, so the copy sits beside it and the
## pair is symmetrical; else the selection flips in place about its middle. Walls and parts
## that land on themselves (on the mirror line) aren't doubled. The copy is selected.
## Returns how many entries it made or moved.
func mirror_selection(axis: int, copy: bool) -> int:
	var sel := PackedStringArray()
	for id in presence.my_selection():
		if model.has(id) and presence.may_edit(id):
			sel.append(id)
	if sel.is_empty():
		status.emit("Select something to mirror first", true)
		return 0
	# A copy takes every wall round its rooms (a shared one too: the copy needs its own
	# mirror of it); a flip leaves a shared wall to the room that stays.
	var ids := carried(sel, copy)
	var box := _set_out_box(ids)
	var line := box.end[axis] if copy else box.get_center()[axis]
	var ops := mirror_ops(model, ids, axis, line, copy, _fresh_ids(ids.size()))
	if ops.is_empty():
		return 0
	sync.edit(C.batch(ops))
	if copy:
		var made := PackedStringArray()
		for op: Dictionary in ops:
			var nid := str((op.get("entry", {}) as Dictionary).get("id", ""))
			if nid != "" and model.has(nid) and (model.rooms.has(nid) or not model.parts[nid].has("host")):
				made.append(nid)
		if not made.is_empty():
			presence.select(made)
	status.emit("Mirrored %s %s" % ["a copy" if copy else "it", "left to right" if axis == 0 else "top to bottom"], false)
	return ops.size()


## The ops that mirror `ids` about the line x = line (axis 0) or z = line (axis 1): adds of
## mirrored copies with ids from `fresh` (copy), else sets that flip them in place.
static func mirror_ops(m: BuildingModel, ids: PackedStringArray, axis: int, line: float, copy: bool, fresh: Array) -> Array:
	var flip2 := func(p: Vector2) -> Vector2:
		var q := p
		q[axis] = snappedf(2.0 * line - q[axis], 0.0001)
		return q
	var flip3 := func(v: Array) -> Array:
		var out := v.duplicate()
		var k := 0 if axis == 0 else 2
		out[k] = snappedf(2.0 * line - float(out[k]), 0.0001)
		return out
	var outline := func(o: Array) -> Array:
		var out: Array = []
		for c: Array in o:
			var q: Vector2 = flip2.call(Vector2(float(c[0]), float(c[1])))
			out.append([q.x, q.y])
		out.reverse()  # the same winding after a mirror
		return out
	var same := func(a: Array, b: Array) -> bool:
		return Vector3(float(a[0]), float(a[1]), float(a[2])).is_equal_approx(Vector3(float(b[0]), float(b[1]), float(b[2])))
	var ops: Array = []
	var new_id := {}
	var n := [0]  # (a lambda keeps its own copy of a plain int)
	var take := func(old: String) -> String:
		var nid: String = fresh[n[0]] if n[0] < fresh.size() else ""
		n[0] += 1
		new_id[old] = nid
		return nid
	for id in ids:
		if not m.rooms.has(id):
			continue
		var e: Dictionary = m.rooms[id]
		var o: Array = outline.call(e.outline)
		if copy:
			var r := C.place_room(str(e.type), int(e.level), o, str(e.get("name", "")))
			var nid := "r" + str(take.call(id)).substr(1)
			r.entry["id"] = nid
			ops.append(r)
		elif not _same_fields(e, {"outline": o}):
			ops.append(C.set_fields(id, {"outline": o}))
	for id in ids:
		if not m.parts.has(id) or m.parts[id].has("host"):
			continue
		var e: Dictionary = m.parts[id]
		var fields := {}
		if e.has("at"):
			fields["at"] = flip3.call(e.at)
			var rot := float(e.get("rot", 0.0))
			fields["rot"] = fposmod(-rot if axis == 0 else 180.0 - rot, 360.0)
		elif e.has("a") and e.has("b"):
			fields["a"] = flip3.call(e.a)
			fields["b"] = flip3.call(e.b)
		elif e.has("outline"):
			fields["outline"] = outline.call(e.outline)
		else:
			continue
		if copy:
			# On the mirror line it lands on itself: one is enough.
			if e.has("at") and same.call(fields.at, e.at):
				continue
			if e.has("a") and ((same.call(fields.a, e.a) and same.call(fields.b, e.b)) or (same.call(fields.a, e.b) and same.call(fields.b, e.a))):
				continue
			var c: Dictionary = e.duplicate(true)
			c.merge(fields, true)
			c["id"] = take.call(id)
			ops.append({"op": "add", "table": "parts", "entry": c})
		elif not _same_fields(e, fields):
			ops.append(C.set_fields(id, fields))
	# Doors and windows: in place they ride on their flipped wall (t is from its a end, which
	# flipped with it); a copy goes on the copied wall.
	if copy:
		for id in m.parts:
			var e: Dictionary = m.parts[id]
			if e.has("host") and new_id.has(str(e.host)) and (id in ids or str(e.host) in ids):
				var c: Dictionary = e.duplicate(true)
				c["host"] = new_id[str(e.host)]
				c["id"] = take.call(id)
				ops.append({"op": "add", "table": "parts", "entry": c})
	return ops


## The plan box round entries as they are set out: room outlines, wall and beam centre lines,
## the points parts stand on (not their thickness, so a mirror line falls on a wall's line).
func _set_out_box(ids: PackedStringArray) -> Rect2:
	var pts: Array[Vector2] = []
	for id in ids:
		var e := model.entry(id)
		for c: Array in e.get("outline", []):
			pts.append(Vector2(float(c[0]), float(c[1])))
		for k: String in ["at", "a", "b"]:
			if e.has(k):
				pts.append(Vector2(float(e[k][0]), float(e[k][2])))
	if pts.is_empty():
		return Rect2()
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


## Copies the selection (rooms with their walls, doors and contents) for pasting: see
## DesignBus.clipboard. Returns it ({} when nothing is selected).
func copy_selection() -> Dictionary:
	var sel := PackedStringArray()
	for id in presence.my_selection():
		if model.has(id):
			sel.append(id)
	if sel.is_empty():
		status.emit("Select something to copy first", true)
		return {}
	var ids := carried(sel, true)
	for pid in model.parts:
		if model.parts[pid].has("host") and str(model.parts[pid].host) in ids and not pid in ids:
			ids.append(pid)
	var box := _set_out_box(ids)
	var c := box.get_center()
	var items: Array = []
	for id in ids:
		var e: Dictionary = model.entry(id).duplicate(true)
		if e.has("at"):
			e.at = [float(e.at[0]) - c.x, float(e.at[1]), float(e.at[2]) - c.y]
		for k: String in ["a", "b"]:
			if e.has(k):
				e[k] = [float(e[k][0]) - c.x, float(e[k][1]), float(e[k][2]) - c.y]
		if e.has("outline"):
			var o: Array = []
			for q: Array in e.outline:
				o.append([float(q[0]) - c.x, float(q[1]) - c.y])
			e.outline = o
		items.append({"table": "rooms" if model.rooms.has(id) else "parts", "id": id, "entry": e})
	var what := label_of(sel[0]) if sel.size() == 1 else "%d things" % sel.size()
	var clip := {"label": what, "size": box.size, "items": items}
	status.emit("Copied %s: Ctrl+V to place copies" % what, false)
	return clip


## The ops that put a copy of `clip` (DesignBus.clipboard) on `level` with its middle at `at`
## (plan), turned `rot` degrees as parts' "rot" turns; new ids from `fresh`.
static func paste_ops(clip: Dictionary, level: int, at: Vector3, rot: float, fresh: Array) -> Array:
	var r := deg_to_rad(rot)
	var p3 := func(v: Array) -> Array:
		var q := Vector3(float(v[0]), 0, float(v[2])).rotated(Vector3.UP, r)
		return [snappedf(q.x + at.x, 0.0001), float(v[1]), snappedf(q.z + at.z, 0.0001)]
	var ops: Array = []
	var new_id := {}
	var n := 0
	for pass_hosted in [false, true]:
		for it: Dictionary in clip.get("items", []):
			var e: Dictionary = (it.entry as Dictionary).duplicate(true)
			if e.has("host") != pass_hosted:
				continue
			if pass_hosted:
				if not new_id.has(str(e.host)):
					continue
				e.host = new_id[str(e.host)]
			if e.has("at"):
				e.at = p3.call(e.at)
				e.rot = snappedf(fposmod(float(e.get("rot", 0.0)) + rot, 360.0), 0.01)
			for k: String in ["a", "b"]:
				if e.has(k):
					e[k] = p3.call(e[k])
			if e.has("outline"):
				var o: Array = []
				for q: Array in e.outline:
					var v: Array = p3.call([q[0], 0.0, q[1]])
					o.append([v[0], v[2]])
				e.outline = o
			if not pass_hosted:
				e.level = level
			if n >= fresh.size():
				break
			var nid := str(fresh[n])
			n += 1
			if str(it.table) == "rooms":
				nid = "r" + nid.substr(1)
			e.id = nid
			new_id[str(it.id)] = nid
			ops.append({"op": "add", "table": str(it.table), "entry": e})
	return ops


## paste_ops() with fresh ids for this model.
func paste_here(clip: Dictionary, at: Vector3, rot: float) -> Array:
	return paste_ops(clip, level, at, rot, _fresh_ids((clip.get("items", []) as Array).size()))


## Whether an entry already has these values (a set of them would change nothing, and the
## model refuses a batch with a no-op in it).
static func _same_fields(e: Dictionary, fields: Dictionary) -> bool:
	for k: String in fields:
		if JSON.stringify(C.plain(e.get(k))) != JSON.stringify(C.plain(fields[k])):
			var a: Variant = e.get(k)
			var b: Variant = fields[k]
			if a is Array and b is Array and str(a).replace(".0", "") == str(b).replace(".0", ""):
				continue
			if (a is float or a is int) and (b is float or b is int) and is_equal_approx(float(a), float(b)):
				continue
			return false
	return true


## `count` part ids not yet in the model ("p..."), so a batch can refer to what it adds.
func _fresh_ids(count: int) -> Array:
	var top := 0
	for t: Dictionary in [model.parts, model.rooms, model.connections]:
		for id: String in t:
			top = maxi(top, id.substr(1).to_int())
	# Peers start apart so two players mirroring at once don't pick the same ids.
	top += 1 + (net.local_peer_id() % 97) * 7 if net else 1
	var out: Array = []
	for i in count * 2 + 4:
		out.append("p%d" % (top + i))
	return out


## Furnishes the selected rooms: the room type's usual layout, or what `text` describes
## ("2 single beds either side of the window and a desk"). One undo takes it all back.
func furnish_selection(text: String = "") -> void:
	var ops: Array = []
	var placed := 0
	var wanted := 0
	var rooms := 0
	var missing := {}
	var unknown: PackedStringArray = []
	for id in presence.my_selection():
		if not model.rooms.has(id) or not presence.may_edit(id):
			continue
		rooms += 1
		var items: Array
		if text.strip_edges() != "":
			var said := DesignFitout.read(text, catalog, str(model.rooms[id].type))
			items = said.items
			unknown = said.unknown
		else:
			items = DesignFitout.preset(model, id)
		var r := DesignFitout.furnish(model, id, items)
		ops.append_array(r.ops)
		placed += int(r.placed)
		wanted += int(r.wanted)
		for k: String in r.get("missing", {}):
			missing[k] = int(missing.get(k, 0)) + int(r.missing[k])
	if rooms == 0:
		status.emit("Select a room first, then Furnish", true)
		return
	if wanted == 0:
		var why := "Nothing I know in \"%s\": try \"2 single beds and a desk\"" % ", ".join(unknown) if not unknown.is_empty() \
				else ("Nothing to put in: try \"2 single beds and a desk\"" if text != "" else "No usual layout for that room")
		status.emit(why, true)
		return
	if not ops.is_empty():
		sync.edit(C.batch(ops))
	var note := ""
	if not missing.is_empty():
		var names: PackedStringArray = []
		for k: String in missing:
			names.append("%d %s" % [missing[k], str(catalog.kind(k).get("label", k)).to_lower()])
		note = " (no room for %s)" % ", ".join(names)
	if not unknown.is_empty():
		note += " (didn't know \"%s\")" % ", ".join(unknown)
	status.emit("Furnished: %d of %d pieces%s" % [placed, wanted, note], placed < wanted or not unknown.is_empty())


func undo() -> void:
	cancel()
	sync.undo()


func redo() -> void:
	cancel()
	sync.redo()


# --- Notes ------------------------------------------------------------------------------

var _note_n := 0


## Pins a note for the team at a point (world), linked to an entry ("" for none). Notes live
## in the design's metadata, so they are shared, saved with it and undoable.
func add_note(at: Vector3, target: String, text: String) -> void:
	text = text.strip_edges().left(280)
	if text == "":
		return
	_note_n += 1
	var key := "note:%d-%d-%d" % [net.local_peer_id(), Time.get_ticks_msec(), _note_n]
	sync.edit(C.set_design_meta({key: {"at": [at.x, at.y, at.z], "level": level, "target": target, "text": text,
			"author": net.player_name(net.local_peer_id()), "colour": net.player_colour(net.local_peer_id()).to_html(false)}}))


func remove_note(key: String) -> void:
	if model.meta.has(key):
		sync.edit(C.set_design_meta({key: null}))


## A label for an entry, for pings and notes ("Kitchen", "Load-bearing wall").
func label_of(id: String) -> String:
	if model.rooms.has(id):
		var r: Dictionary = model.rooms[id]
		return str(r.get("name", "")) if str(r.get("name", "")) != "" else str(catalog.room_type(str(r.type)).get("label", r.type))
	if model.parts.has(id):
		return str(catalog.kind(str(model.parts[id].kind)).get("label", model.parts[id].kind))
	return ""


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
	if not shape.is_empty():
		return {"kind": "shape", "outline": shape.outline}
	if not box.is_empty():
		return {"kind": "box", "a": box.a, "b": box.b}
	if not drag.is_empty():
		return {"kind": "move", "ids": drag.ids, "by": drag.by}
	if cursor == null:
		return {}
	if tool in TWO_POINT and anchor != null:
		return {"kind": "line", "a": anchor, "b": cursor}
	if tool in RECT and anchor != null:
		var r := DesignSnap.rect(anchor, cursor, snap_step())
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


# --- Reshaping rooms ----------------------------------------------------------------------
# With one room selected, its corners and the middles of its edges have handles: drag a
# corner to move it, drag an edge to push or pull that side, drag an edge's middle to add a
# corner there (for L-shapes and the like). Walls that end on a moved corner follow it.

## The room whose handles show: the one room this player has selected, on this level.
func shape_room() -> String:
	var sel := presence.my_selection()
	if sel.size() != 1 or not model.rooms.has(sel[0]) or int(model.rooms[sel[0]].level) != level:
		return ""
	return sel[0]


## The room's corners and edge middles (plan m), for drawing handles.
func shape_handles() -> Dictionary:
	var rid := shape_room()
	if rid == "":
		return {}
	var pts := _outline2(model.rooms[rid].outline)
	var mids: Array[Vector2] = []
	for i in pts.size():
		mids.append((pts[i] + pts[(i + 1) % pts.size()]) * 0.5)
	return {"room": rid, "corners": pts, "mids": mids}


## What the pointer is on: {mode: "corner"|"mid"|"edge", i} or {} (raw, unsnapped point).
func shape_hit(p: Vector3) -> Dictionary:
	var h := shape_handles()
	if h.is_empty():
		return {}
	var at := Vector2(p.x, p.z)
	var pts: Array[Vector2] = h.corners
	for i in pts.size():
		if at.distance_to(pts[i]) <= handle_reach:
			return {"mode": "corner", "i": i}
	var mids: Array[Vector2] = h.mids
	for i in mids.size():
		if at.distance_to(mids[i]) <= handle_reach:
			return {"mode": "mid", "i": i}
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		if Geometry2D.get_closest_point_to_segment(at, a, b).distance_to(at) <= handle_reach * 0.6:
			return {"mode": "edge", "i": i}
	return {}


## Takes away one corner of the selected room (a room keeps at least three).
func remove_corner(i: int) -> bool:
	var rid := shape_room()
	if rid == "" or not presence.may_edit(rid):
		return false
	var pts := _outline2(model.rooms[rid].outline)
	if pts.size() <= 3 or i < 0 or i >= pts.size():
		return false
	pts.remove_at(i)
	sync.edit(C.set_fields(rid, {"outline": _outline_data(pts)}))
	return true


func _begin_shape(hit: Dictionary, at: Vector3) -> void:
	var rid := shape_room()
	if not presence.may_edit(rid):
		status.emit("%s is moving that" % net.player_name(presence.locked_by(rid)), true)
		return
	var base := _outline2(model.rooms[rid].outline)
	shape = {"room": rid, "base": base, "mode": hit.mode, "i": int(hit.i), "from": at, "outline": base.duplicate()}
	presence.lock(PackedStringArray([rid]))
	status.emit({"corner": "Drag the corner", "mid": "Drag to add a corner here",
			"edge": "Drag to push or pull this side"}[hit.mode], false)


func _update_shape(at: Vector3) -> void:
	var d := Vector2(at.x - (shape.from as Vector3).x, at.z - (shape.from as Vector3).z)
	var base: Array[Vector2] = shape.base
	var out: Array[Vector2] = base.duplicate()
	var i := int(shape.i)
	var n := base.size()
	match str(shape.mode):
		"corner":
			out[i] = base[i] + d
		"mid":
			out.insert(i + 1, (base[i] + base[(i + 1) % n]) * 0.5 + d)
		"edge":
			var a := base[i]
			var b := base[(i + 1) % n]
			var normal := (b - a).orthogonal().normalized()
			var push := normal * d.dot(normal)
			out[i] = a + push
			out[(i + 1) % n] = b + push
	shape.outline = out
	presence.lock(PackedStringArray([str(shape.room)]))


func _end_shape() -> void:
	var rid := str(shape.room)
	var base: Array[Vector2] = shape.base
	var out: Array[Vector2] = shape.outline
	var mode := str(shape.mode)
	var shape_i := int(shape.i)
	shape = {}
	presence.unlock(PackedStringArray([rid]))
	preview_changed.emit()
	if out == base or absf(_area2(out)) < 0.25:
		return
	var ops: Array = [C.set_fields(rid, {"outline": _outline_data(out)})]
	ops.append_array(_walls_follow(base, out, mode, int(shape_i)))
	sync.edit(C.batch(ops) if ops.size() > 1 else ops[0])


## The edits that make the walls along a room's outline follow its new shape: a wall lying on
## an old edge keeps its place along that edge (ends on corners follow the corners), and when a
## corner is added mid-edge, a wall across that point is split in two at the new corner.
func _walls_follow(base: Array[Vector2], out: Array[Vector2], mode: String, i: int) -> Array:
	var ops: Array = []
	var n := base.size()
	for pid in model.parts_on(level):
		var e: Dictionary = model.parts[pid]
		if catalog.family_of(str(e.kind)) != "wall" or not e.has("a") or not e.has("b"):
			continue
		var pa := Vector2(float(e.a[0]), float(e.a[2]))
		var pb := Vector2(float(e.b[0]), float(e.b[2]))
		var edge := -1
		var ta := 0.0
		var tb := 0.0
		for j in n:
			var a := base[j]
			var b := base[(j + 1) % n]
			var len2 := a.distance_squared_to(b)
			if len2 < 0.0001:
				continue
			var t1 := (pa - a).dot(b - a) / len2
			var t2 := (pb - a).dot(b - a) / len2
			if t1 < -0.001 or t1 > 1.001 or t2 < -0.001 or t2 > 1.001:
				continue
			if pa.distance_to(a.lerp(b, t1)) > 0.02 or pb.distance_to(a.lerp(b, t2)) > 0.02:
				continue
			edge = j
			ta = clampf(t1, 0.0, 1.0)
			tb = clampf(t2, 0.0, 1.0)
			break
		if edge < 0 or not presence.may_edit(pid):
			continue
		var ya := float(e.a[1])
		var yb := float(e.b[1])
		if mode == "mid" and edge == i:
			# The edge is now base[i] -> M -> base[i+1].
			var a := out[i]
			var m := out[i + 1]
			var b := out[(i + 2) % out.size()]
			var at_t := func(t: float) -> Vector2: return a.lerp(m, t * 2.0) if t <= 0.5 else m.lerp(b, t * 2.0 - 1.0)
			if (ta < 0.5 and tb > 0.5) or (tb < 0.5 and ta > 0.5):
				# Across the new corner: this wall runs to it, a copy runs on from it.
				var qa: Vector2 = at_t.call(ta)
				var qb: Vector2 = at_t.call(tb)
				ops.append(C.set_fields(pid, {"a": [qa.x, ya, qa.y], "b": [m.x, yb, m.y]}))
				var copy := e.duplicate(true)
				copy.erase("id")
				copy["a"] = [m.x, ya, m.y]
				copy["b"] = [qb.x, yb, qb.y]
				ops.append({"op": "add", "table": "parts", "entry": copy})
			else:
				var qa: Vector2 = at_t.call(ta)
				var qb: Vector2 = at_t.call(tb)
				ops.append(C.set_fields(pid, {"a": [qa.x, ya, qa.y], "b": [qb.x, yb, qb.y]}))
			continue
		var j2 := edge
		if mode == "mid" and edge > i:
			j2 = edge + 1  # indices after the new corner shift by one
		var na := out[j2].lerp(out[(j2 + 1) % out.size()], ta)
		var nb := out[j2].lerp(out[(j2 + 1) % out.size()], tb)
		if na.distance_to(pa) > 0.001 or nb.distance_to(pb) > 0.001:
			ops.append(C.set_fields(pid, {"a": [na.x, ya, na.y], "b": [nb.x, yb, nb.y]}))
	return ops


static func _outline2(outline: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p: Variant in outline:
		out.append(p as Vector2 if p is Vector2 else Vector2(float(p[0]), float(p[1])))
	return out


static func _outline_data(pts: Array[Vector2]) -> Array:
	var out: Array = []
	for v in pts:
		out.append([snappedf(v.x, 0.001), snappedf(v.y, 0.001)])
	return out


static func _area2(pts: Array[Vector2]) -> float:
	var a := 0.0
	for i in pts.size():
		a += pts[i].cross(pts[(i + 1) % pts.size()])
	return a * 0.5
