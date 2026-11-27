extends ModuleTest
## Walk-inside (BSX's walk-inside on the building model): the designer's "Walk inside" button
## opens the building round you at full size in a world of its own; you start outside the
## front door, walk in through it (it swings open), and design from inside: push a wall away
## and pull it back, raise the ceiling, take a fitting from Tab and put it down, pick it up and
## move it, turn it, put a door in a wall, edit and remove parts, fly, swap the look, and Esc
## takes you back. Every change goes through BuildingSync.
##   tools/run_tests.sh walk

const C := preload("res://modules/building/api/building_commands.gd")
const WalkInside := preload("res://modules/walk/internal/walk_inside.gd")
const WalkBuild := preload("res://modules/walk/internal/walk_build.gd")


## A stand-in for the design bus: just the top bar's actions.
class FakeDesign:
	extends Node
	var actions := {}

	func register_action(id: String, label: String, press: Callable, order: int = 50) -> void:
		actions[id] = {"label": label, "press": press, "order": order}

	func unregister_action(id: String) -> void:
		actions.erase(id)


func run_tests() -> void:
	var walk := Modules.bus("walk") as WalkBus
	var b := Modules.bus("building") as BuildingBus
	check(walk != null, "the walk module is loaded")
	var model := b.model
	_house(b)
	check(model.parts_of_family("wall").size() == 5 and model.rooms.size() == 2, "a two-room house with an upstairs")

	# The designer's top bar gets a Walk inside button; pressing it opens the walk.
	var design := FakeDesign.new()
	add_child(design)
	walk.hook_design(design)
	check(design.actions.has(WalkBus.ACTION) and str(design.actions[WalkBus.ACTION].label) == "Walk inside", "a Walk inside button for the designer")
	var opened := [0]
	walk.opened.connect(func() -> void: opened[0] += 1)
	(design.actions[WalkBus.ACTION].press as Callable).call(model)
	await frames(2)
	var v: WalkInside = walk.view
	check(walk.is_open() and v != null and opened[0] == 1, "it opens walk-inside")
	check(HudSlots.pointer_claimed() and v.camera.current, "you see through the walker's eyes, the room's own pointer stood down")
	check(v.viewport.own_world_3d and v.world.get_world_3d() != get_viewport().world_3d, "built in a world of its own")
	var bld: WalkBuild = v.builder
	check(bld.doors.size() == 2 and bld.ramps.size() == 1 and bld.lamps.size() == 2,
			"a door leaf in each doorway, the stair as a ramp, a lamp in each room: %d %d %d" % [bld.doors.size(), bld.ramps.size(), bld.lamps.size()])
	check(bld.batch_count() > 0 and bld.batch_count() < 40, "drawn in a few batches: %d" % bld.batch_count())
	var sofa_node: Node = null

	# You start outside the front door, facing it, standing on the ground.
	await _physics(20)
	var front: String = _of_kind(model, "door_external")
	var door_pts := model.points_of(front)
	var door_mid := (door_pts[0] + door_pts[1]) / 2.0
	check(v.feet().distance_to(door_mid) < 2.6 and v.feet().z > 6.0, "you start just outside the front door: %s" % v.feet())
	check(v.body.is_on_floor(), "standing on the ground")
	check(str(v.where().room) == "", "outside")

	# Walk in: the door swings open as you come up to it and you're in the hall.
	Input.action_press(Keys.FORWARD)
	var widest := 0.0
	for i in 90:
		await get_tree().physics_frame
		widest = maxf(widest, bld.door_open(front))
	Input.action_release(Keys.FORWARD)
	check(str(v.where().room) == _room(model, "Hall"), "the forward key walks you in through the front door: %s at %s" % [v.where(), v.feet()])
	check(widest > 0.9, "the front door swung open as you came to it: %.2f" % widest)
	check(v._where.text.contains("HALL"), "the corner says where you are: %s" % v._where.text)

	# Push the back wall away and pull it back: the side walls and the room follow.
	v.body.position = Vector3(2.0, 0.95, 4.0)
	_face(v, Vector3(2.0, 1.5, 0.0))
	await _physics(2)
	var back: String = _wall_at(model, 0.0)
	check(v.aimed_part() == back, "aiming at the back wall: %s" % v.aimed_part())
	check(v._aim_text().contains("Wheel push"), "the hint says the wheel pushes it")
	var room: String = _room(model, "Hall")
	var area0 := BuildingModel.outline_area(model.rooms[room].outline)
	check(v.push(1), "the wheel pushes it")
	await frames(1)
	check(is_equal_approx(float(model.parts[back].a[2]), -0.25), "the wall went a grid step away: z %.2f" % float(model.parts[back].a[2]))
	check(is_equal_approx(BuildingModel.outline_area(model.rooms[room].outline), area0 + 0.25 * 4.0), "the hall grew with it")
	var side: String = _wall_from(model, Vector2(0, 6))
	check(_ends_at(model, side, Vector2(0, -0.25)), "the side wall stretched to meet it")
	await _physics(2)
	check(v.push(-1), "and pulls it back towards you")
	await frames(1)
	check(is_equal_approx(float(model.parts[back].a[2]), 0.0) and is_equal_approx(BuildingModel.outline_area(model.rooms[room].outline), area0), "back where it was")
	b.sync.undo()
	await frames(1)
	check(is_equal_approx(float(model.parts[back].a[2]), 0.0), "one undo takes both wheel steps back")

	# Raise the ceiling: the storey gets taller.
	v.body.position = Vector3(2.0, 0.95, 3.0)
	v.look(Vector2(0, -1000))
	await _physics(2)
	var h0 := model.level_height(0)
	check(v._aim_text().contains("Ceiling"), "looking up at the ceiling: %s" % v._aim_text())
	check(v.push(1), "the wheel raises it")
	await frames(1)
	check(is_equal_approx(model.level_height(0), h0 + 0.25), "the storey is a grid step taller: %.2f" % model.level_height(0))
	b.sync.undo()
	await frames(1)
	check(is_equal_approx(model.level_height(0), h0), "undo puts it back")

	# Take a sofa from Tab and put it down on the floor in front of you.
	v.body.position = Vector3(2.0, 0.95, 4.5)
	_face(v, Vector3(2.0, 0.0, 2.5))
	v.toggle_palette()
	check(v.is_palette_open() and v._palette.find_child("Part_sofa", true, false) != null, "Tab lists the fittings")
	(v._palette.find_child("Part_sofa", true, false) as Button).pressed.emit()
	check(not v.is_palette_open() and str(v.holding.get("type", "")) == "sofa", "a sofa in your hands")
	await _physics(2)
	check(v.spot.has("at") and bool(v.spot.ok), "it fits where you aim: %s" % v.spot)
	check(v._ghost != null and v._ghost.visible, "its ghost shows there")
	var parts_before := model.parts.size()
	check(v.put_down(), "click puts it down")
	await frames(2)
	check(model.parts.size() == parts_before + 1, "the sofa is in the building")
	var sofa: String = _of_kind(model, "sofa")
	sofa_node = bld.node_of(sofa)
	check(sofa_node != null, "and stands in the walk")

	# Pick it up, turn it, move it.
	await _physics(2)
	check(v.aimed_part() == sofa, "aiming at the sofa")
	check(v.pick_up(sofa) and str(v.holding.id) == sofa, "click picks it up")
	v.turn()
	_face(v, Vector3(1.5, 0.0, 3.5))
	await _physics(2)
	var was: Array = model.parts[sofa].at
	check(v.put_down(), "and puts it down somewhere else")
	await frames(1)
	var now: Array = model.parts[sofa].at
	check(not (is_equal_approx(float(was[0]), float(now[0])) and is_equal_approx(float(was[2]), float(now[2]))), "it moved: %s -> %s" % [was, now])
	check(is_equal_approx(float(model.parts[sofa].rot), 90.0), "turned a quarter")
	await _physics(2)

	# E edits what you aim at; X removes it.
	v.body.position = Vector3(2.0, 0.95, 3.0)
	_face(v, Vector3(2.0, 1.5, 0.0))
	await _physics(2)
	check(v.edit_aimed() and v.is_palette_open() and v.edit_id == back, "E opens the wall's rows")
	var kind0 := str(model.parts[back].kind)
	(v._palette.find_child("EditKind", true, false) as Button).pressed.emit()
	await frames(1)
	check(str(model.parts[back].kind) != kind0, "its kind steps on: %s -> %s" % [kind0, model.parts[back].kind])
	b.sync.undo()
	v.toggle_palette()
	await _physics(2)

	# F puts a door in the wall.
	var openings := model.openings_in(back).size()
	check(v.door_here(), "F asks for a door")
	await frames(2)
	check(model.openings_in(back).size() == openings + 1 and bld.doors.size() == 3, "a door in the back wall, and its leaf")
	b.sync.undo()
	await frames(1)

	# X removes the sofa.
	v.body.position = Vector3(float(model.parts[sofa].at[0]), 0.95, float(model.parts[sofa].at[2]) + 2.0)
	_face(v, Vector3(float(model.parts[sofa].at[0]), 0.3, float(model.parts[sofa].at[2])))
	await _physics(2)
	check(v.aimed_part() == sofa and v.remove_aimed(), "X removes the part you aim at")
	await frames(2)
	check(not model.parts.has(sofa), "the sofa is gone")

	# Fly: up through the ceiling.
	v.toggle_fly()
	check(v.flying and v.body.collision_mask == 0, "Q flies, through walls")
	var y0 := v.body.position.y
	Input.action_press(Keys.JUMP)
	await _physics(40)
	Input.action_release(Keys.JUMP)
	check(v.body.position.y > y0 + 2.0, "Space takes you up: %.2f -> %.2f" % [y0, v.body.position.y])
	check(bool(walk.walkers[walk.local_peer()].flying), "the crew see you flying")
	v.toggle_fly()

	# V swaps the model look for the realistic one, and back.
	var real0 := ArtStyle.realistic()
	v.toggle_look()
	await frames(2)
	check(ArtStyle.realistic() != real0 and v._look.text.contains("REALISTIC" if not real0 else "MODEL"), "V swaps the look: %s" % v._look.text)
	v.toggle_look()
	await frames(2)
	check(ArtStyle.realistic() == real0, "and back")

	# You're on the crew's list with where you are.
	var me: Dictionary = walk.walkers.get(walk.local_peer(), {})
	await frames(1)
	check(not me.is_empty() and (me.pos as Vector3).distance_to(v.feet()) < 0.01, "walkers has you, at your feet")

	# Esc goes back.
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await frames(3)
	check(not walk.is_open() and not HudSlots.pointer_claimed(), "Esc goes back to the designer and gives the pointer back: %s %s" % [walk.is_open(), HudSlots._pointer])
	check(not walk.walkers.has(walk.local_peer()), "and you're off the walkers")

	# Opened from a designer drawn in a SubViewport (the hall): that view's camera is lent
	# away while walking, so it stands down, and comes back when the walk closes.
	var box := SubViewportContainer.new()
	add_child(box)
	var dvp := SubViewport.new()
	dvp.own_world_3d = true
	box.add_child(dvp)
	var dcam := Camera3D.new()
	dvp.add_child(dcam)
	dcam.make_current()
	await frames(1)
	walk.open(model, dvp)
	await frames(2)
	check(walk.is_open() and dvp.get_camera_3d() != dcam and dvp.get_camera_3d() == walk.lent_camera(), "the designer's view lends its camera")
	check(walk.view.get_parent() != dvp, "the walk itself is drawn full screen, not in the designer's view")
	walk.close()
	await frames(2)
	check(dvp.get_camera_3d() == dcam, "and gets it back when the walk closes")
	box.queue_free()
	walk.unregister_module()
	design.queue_free()


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Turns the walker to look at a point.
func _face(v: WalkInside, at: Vector3) -> void:
	var eye := v.body.position + Vector3(0, 0.7, 0)
	var d := at - eye
	v.body.rotation.y = atan2(-d.x, -d.z)
	v._pitch = atan2(d.y, Vector2(d.x, d.z).length())
	v.camera.rotation.x = v._pitch


## An 8 x 6 house: a hall and a lounge split by a partition with a door, a front door in the
## front (+z) wall, a floor slab, an upper floor slab with a stair up to it.
func _house(b: BuildingBus) -> void:
	b.reset_data()
	var s := b.sync
	s.edit(C.place_part("slab", 0, {"outline": C.rect(-0.2, -0.2, 8.4, 6.4), "y": 0.0}))
	var walls := [[Vector3(0, 0, 0), Vector3(8, 0, 0)], [Vector3(8, 0, 0), Vector3(8, 0, 6)],
			[Vector3(8, 0, 6), Vector3(0, 0, 6)], [Vector3(0, 0, 6), Vector3(0, 0, 0)], [Vector3(4, 0, 0), Vector3(4, 0, 6)]]
	for i in walls.size():
		s.edit(C.place_part("wall_partition" if i == 4 else "wall_loadbearing", 0, {"a": walls[i][0], "b": walls[i][1]}))
	var front := _wall_at(b.model, 6.0)
	s.edit(C.place_opening("door_external", front, 6.0))
	s.edit(C.place_opening("door_internal", _wall_from(b.model, Vector2(4, 0)), 4.5))
	s.edit(C.place_room(_room_type(b), 0, C.rect(0, 0, 4, 6), "Hall"))
	s.edit(C.place_room(_room_type(b), 0, C.rect(4, 0, 4, 6), "Lounge"))
	s.edit(C.add_level())
	s.edit(C.place_stair(0, Vector3(6, 0, 1), Vector3(6, 0, 5)))
	s.edit(C.place_part("slab", 1, {"outline": C.rect(-0.2, -0.2, 8.4, 6.4), "y": 0.0}))


func _room_type(b: BuildingBus) -> String:
	for t: String in ["living_room", "hall", "office"]:
		if b.catalog.has_room_type(t):
			return t
	return str(b.catalog.room_types_in("")[0])


func _of_kind(m: BuildingModel, kind: String) -> String:
	for id: String in BuildingModel.sort_ids(m.parts.keys()):
		if str(m.parts[id].kind) == kind:
			return id
	return ""


func _room(m: BuildingModel, room_name: String) -> String:
	for id: String in m.rooms:
		if str(m.rooms[id].name) == room_name:
			return id
	return ""


## The level-0 wall along z = z (the whole width).
func _wall_at(m: BuildingModel, z: float) -> String:
	for id in m.parts_of_family("wall"):
		var e: Dictionary = m.parts[id]
		if is_equal_approx(float(e.a[2]), z) and is_equal_approx(float(e.b[2]), z) and absf(float(e.a[0]) - float(e.b[0])) > 7.0:
			return id
	return ""


## The wall starting at a plan point.
func _wall_from(m: BuildingModel, p: Vector2) -> String:
	for id in m.parts_of_family("wall"):
		var e: Dictionary = m.parts[id]
		if Vector2(float(e.a[0]), float(e.a[2])).distance_to(p) < 0.01:
			return id
	return ""


func _ends_at(m: BuildingModel, id: String, p: Vector2) -> bool:
	var e: Dictionary = m.parts[id]
	return Vector2(float(e.a[0]), float(e.a[2])).distance_to(p) < 0.01 or Vector2(float(e.b[0]), float(e.b[2])).distance_to(p) < 0.01
