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
	# Clicks take straight away in most of this test; another module's preview (kits) is put
	# back at the end, and the preview-then-TAKE flow is checked with a stand-in below.
	var kept_preview: Callable = walk._preview
	walk.set_preview_maker(Callable())
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
	var ext: Vector2 = bld._joins.ends(back)
	check(ext != Vector2.ZERO and (bld._wall_nb.get(back, PackedStringArray()) as PackedStringArray).size() >= 2,
			"its corners join as the designer draws them (WallJoins): %s" % ext)
	check(v._aim_text().contains("push it away"), "the hint says the wheel pushes it")
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
	await frames(1)
	check(v.help_text().begins_with("PARTS MENU"), "the help bar follows you into the Tab menu: %s" % v.help_text())
	check(v.is_palette_open() and v._palette.find_child("Group_living", true, false) != null
			and v._palette.find_child("Group_doors", true, false) != null, "Tab lists the objects in groups")
	check(v._palette.find_child("Item_sofa", true, false) == null, "the groups start folded")
	(v._palette.find_child("Group_living", true, false) as Button).pressed.emit()
	check(v._palette.find_child("Item_sofa", true, false) != null, "a group opens to its items")
	v._search.text = "bath"
	v._search.text_changed.emit("bath")
	var names: Array = v.palette_groups().map(func(g: Dictionary) -> String: return str(g.id))
	# The asset library (flag building.library) adds its own "lib:<group>" groups.
	check(names.has("bathroom") and names.all(func(n: String) -> bool: return n == "bathroom" or n.begins_with("lib:")) and v._palette.find_child("Item_bath", true, false) != null
			and v._palette.find_child("Item_sofa", true, false) == null, "the filter narrows them, groups open: %s" % [names])
	v._search.text = ""
	v._search.text_changed.emit("")
	(v._palette.find_child("Item_sofa", true, false) as Button).pressed.emit()
	check(not v.is_palette_open() and str(v.holding.get("type", "")) == "sofa", "a sofa in your hands")
	await _physics(2)
	check(v.spot.has("at") and bool(v.spot.ok), "it fits where you aim: %s" % v.spot)
	await frames(1)
	check(v.help_text().begins_with("SOFA: FITS") and v.help_text().contains("R quarter turn"),
			"the help bar at the bottom says what you hold and its keys: %s" % v.help_text())
	var bar: Control = v.help.get_node("Bar")
	check(v.help is HelpBar and is_equal_approx(bar.position.y + bar.size.y, bar.get_viewport_rect().size.y - HelpBar.MARGIN),
			"on the shared help bar along the bottom: %s in %s" % [bar.position, bar.get_viewport_rect().size])
	check(v._ghost != null and v._ghost.visible, "its ghost shows there")
	check(v._ghost.find_child("FrontArrow", true, false) != null and v._ghost.find_child("FrontTag", true, false) != null,
			"with an arrow and FRONT on the side it faces")
	check(v._ghost.find_children("*", "MeshInstance3D", true, false).size() >= 3, "drawn as the part's model with its outline")
	var front_was: Vector3 = (v._ghost.find_child("FrontTag", true, false) as Node3D).global_position - v._ghost.global_position
	v.turn()
	await _settle()
	var front_now: Vector3 = (v._ghost.find_child("FrontTag", true, false) as Node3D).global_position - v._ghost.global_position
	check(absf(Vector2(front_was.x, front_was.z).angle_to(Vector2(front_now.x, front_now.z))) > 1.4, "R turns its front a quarter")
	v.turn()
	v.turn()
	v.turn()
	# Free turning: the wheel turns what you hold 15°, Alt 1°, Shift+R 15°.
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	v._input(wheel)
	check(is_equal_approx(float(v.holding.rot), 15.0), "the wheel turns it 15°: %s" % v.holding.rot)
	wheel.alt_pressed = true
	v._input(wheel)
	check(is_equal_approx(float(v.holding.rot), 16.0), "with Alt, 1°: %s" % v.holding.rot)
	var shift_r := InputEventKey.new()
	shift_r.physical_keycode = KEY_R
	shift_r.pressed = true
	shift_r.shift_pressed = true
	v._input(shift_r)
	await _settle()
	check(is_equal_approx(float(v.holding.rot), 31.0) and is_equal_approx(v._ghost.rotation.y, deg_to_rad(31.0)) or not v.spot.has("at"),
			"Shift+R 15° more, and the ghost turns with it: %s" % v.holding.rot)
	v.turn(-31.0)
	# Hold R and move the mouse: a precise turn; a tap is still a quarter.
	var r0 := float(v.holding.rot)
	v.r_press()
	v.r_drag(30.0, false)
	v.r_drag(12.0, false)
	check(v.r_turning() and is_equal_approx(float(v.holding.rot), r0 + 10.0), "hold R, mouse 42 px: 10° (snapped to 5°): %s" % v.holding.rot)
	v.r_drag(4.0, true)
	check(is_equal_approx(float(v.holding.rot), r0 + 11.5), "with Alt, free: %s" % v.holding.rot)
	await frames(1)
	check(v._aim_text().begins_with("Turning"), "the help bar says you're turning it")
	v.r_release()
	check(is_equal_approx(float(v.holding.rot), r0 + 11.5), "let go: it stays there, no quarter turn")
	v.r_press()
	v.r_release()
	check(is_equal_approx(float(v.holding.rot), r0 + 101.5), "a tap of R still turns a quarter: %s" % v.holding.rot)
	v.turn(-101.5)
	var aim_was := v._pitch
	v.look(Vector2(0, -2000))
	v.toggle_fly()
	v.body.position.y += 30.0
	await _settle()
	var in_view: Vector3 = v._ghost.global_position - v.camera.global_position
	check(not v.spot.has("at") and v._ghost.visible and in_view.length() < 2.5 and v._ghost.scale.x <= 1.0,
			"aimed at nothing, it's held up in front of you: %s" % in_view)
	v.toggle_fly()
	v.body.position = Vector3(2.0, 0.95, 4.5)
	_face(v, Vector3(2.0, 0.0, 2.5))
	await _settle()
	check(v.spot.has("at") and is_equal_approx(v._ghost.scale.x, 1.0), "and back on the floor at full size when you aim at it (pitch was %.2f)" % aim_was)
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

	# Smart guides (the designer's, from BSX): a part in your hands lines up with the ones round it.
	v.take_new("sofa")
	v.body.position = Vector3(float(now[0]) + 0.6, 0.95, float(now[2]) + 2.2)
	_face(v, Vector3(float(now[0]) + 1.6, 0.0, float(now[2]) + 0.07))
	await _settle()
	var spec: Dictionary = model.catalog.kind("sofa")
	var at: Vector3 = v.spot.get("at", Vector3.ZERO)
	var lined := v.guide_count() > 0
	for g: Array in v.spot.get("guides", []):
		var axis := 0 if is_equal_approx(g[0].x, g[1].x) else 1
		var c: float = at.x if axis == 0 else at.z
		var half := float(spec.w if axis == 0 else spec.d) * 0.5
		var line: float = g[0].x if axis == 0 else g[0].y
		lined = lined and [c - half, c, c + half].any(func(e: float) -> bool: return is_equal_approx(e, line))
	check(lined, "beside the sofa, the new one lines up on guides: %s on %s" % [at, v.spot.get("guides")])
	check(v._guides != null and v._guides.mesh != null and v._guides.mesh.get_surface_count() > 0, "and the guides are drawn")
	v._drop_holding()
	await _settle()
	check(v._guides.mesh == null, "no guides with nothing in your hands")

	# E edits what you aim at; X removes it.
	v.body.position = Vector3(2.0, 0.95, 3.0)
	_face(v, Vector3(2.0, 1.5, 0.0))
	await _physics(2)
	check(v.edit_aimed() and v.is_palette_open() and v.edit_id == back, "E opens the wall's rows")
	var kind0 := str(model.parts[back].kind)
	check(v._palette.find_child("Dim_length", true, false) != null and v._palette.find_child("Dim_height", true, false) != null,
			"with its length and height to change")
	var wh0 := model.part_height(back)
	(v._palette.find_child("Dim_height", true, false).find_child("Up", true, false) as Button).pressed.emit()
	await frames(1)
	check(model.part_height(back) > wh0, "+ makes it taller: %.2f -> %.2f" % [wh0, model.part_height(back)])
	(v._palette.find_child("Dim_height", true, false).find_child("Value", true, false) as SpinBox).value = 3.1
	await frames(1)
	check(is_equal_approx(model.part_height(back), 3.1), "a typed height sets it: %.2f" % model.part_height(back))
	b.sync.undo()
	b.sync.undo()
	await frames(1)
	check(is_equal_approx(model.part_height(back), wh0), "undo puts it back")
	var kb: Button = null
	for c: Node in v._palette.find_child("KindScroll", true, false).find_children("Kind_*", "Button", true, false):
		if not (c as Button).disabled:
			kb = c
			break
	check(kb != null and v._palette.find_child("KindFilter", true, false) != null, "a list of kinds to change it to, with a filter")
	kb.pressed.emit()
	await frames(1)
	check(v.edit_pick != "" and v._palette.find_child("ChangeKind", true, false) != null, "picking one shows it, with CHANGE TO")
	var pick := v.edit_pick
	(v._palette.find_child("ChangeKind", true, false) as Button).pressed.emit()
	await frames(1)
	check(str(model.parts[back].kind) == pick and pick != kind0, "the wall is now a %s" % pick)
	b.sync.undo()
	await frames(1)
	var flt := v._palette.find_child("KindFilter", true, false) as LineEdit
	flt.text = "zzzz no such"
	flt.text_changed.emit(flt.text)
	await frames(1)
	check(v._kind_list.get_child_count() == 0 or v._kind_list.get_children().all(func(n: Node) -> bool: return n.is_queued_for_deletion()),
			"the filter narrows the list")
	v.toggle_palette()
	await _physics(2)

	# F puts a door in the wall.
	var openings := model.openings_in(back).size()
	check(v.door_here(), "F asks for a door")
	await frames(2)
	check(model.openings_in(back).size() == openings + 1 and bld.doors.size() == 3, "a door in the back wall, and its leaf")
	b.sync.undo()
	await frames(1)

	# E on the sofa: its width, depth and height.
	v.body.position = Vector3(float(model.parts[sofa].at[0]), 0.95, float(model.parts[sofa].at[2]) + 2.0)
	_face(v, Vector3(float(model.parts[sofa].at[0]), 0.3, float(model.parts[sofa].at[2])))
	await _physics(2)
	check(v.edit_aimed() and v.edit_id == sofa and v._palette.find_child("Dim_w", true, false) != null
			and v._palette.find_child("Dim_d", true, false) != null, "E on the sofa: width, depth and height")
	(v._palette.find_child("Dim_w", true, false).find_child("Value", true, false) as SpinBox).value = 2.4
	await frames(2)
	check(is_equal_approx(float(model.parts[sofa].get("w", 0.0)), 2.4) and bld.node_of(sofa) != null,
			"typed 2.4 m, the sofa is 2.4 m wide: %s" % model.parts[sofa])
	check(v.help_text().begins_with("EDITING"), "the help bar says how: %s" % v.help_text())
	b.sync.undo()
	await frames(1)
	(v._palette.find_child("Dim_rot", true, false).find_child("Value", true, false) as SpinBox).value = 37.5
	await frames(1)
	check(is_equal_approx(float(model.parts[sofa].rot), 37.5), "a typed angle turns it to 37.5°: %s" % model.parts[sofa].rot)
	b.sync.undo()
	await frames(1)
	var sr0 := float(model.parts[sofa].rot)
	v.r_press()
	for i in 6:
		v.r_drag(20.0, false)
	v.r_release()
	await frames(1)
	check(is_equal_approx(float(model.parts[sofa].rot), fposmod(sr0 + 30.0, 360.0)), "hold R + mouse turns the sofa you aim at: %s" % model.parts[sofa].rot)
	b.sync.undo()
	await frames(1)
	check(is_equal_approx(float(model.parts[sofa].rot), sr0), "and one undo turns it back")
	# Ctrl+C / Ctrl+V: a copy in your hands, the same size, angle and material.
	b.sync.edit(WalkInside.WalkEdits.resize(model, sofa, "w", 2.4))
	await frames(1)
	var ctrl := func(key: Key) -> void:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		ev.ctrl_pressed = true
		ev.pressed = true
		v._input(ev)
	ctrl.call(KEY_C)
	check(str(WalkInside.clipboard.get("kind", "")) == "sofa" and is_equal_approx(float(WalkInside.clipboard.fields.w), 2.4),
			"Ctrl+C copies the sofa you're editing: %s" % WalkInside.clipboard)
	var look_was := ArtStyle.realistic()
	ctrl.call(KEY_V)
	check(str(v.holding.get("type", "")) == "sofa" and v.holding.has("copy") and not v.is_palette_open()
			and is_equal_approx(float(v.holding.rot), float(model.parts[sofa].rot)) and ArtStyle.realistic() == look_was,
			"Ctrl+V puts a copy in your hands, turned the same (and V's look toggle stays put)")
	v.body.position = Vector3(2.0, 0.95, 5.0)
	_face(v, Vector3(2.5, 0.0, 2.6))
	await _settle()
	var n0 := model.parts.size()
	check(v.spot.has("at") and v._ghost != null and is_equal_approx(float(v._ghost.get_meta("size").x), 2.4),
			"its ghost is the copy's size: %s" % [v._ghost.get_meta("size") if v._ghost else null])
	var placed := v.put_down()
	await frames(1)
	var copy_id := ""
	for pid: String in model.parts:
		if str(model.parts[pid].kind) == "sofa" and pid != sofa:
			copy_id = pid
	check(placed and model.parts.size() == n0 + 1 and copy_id != "" and is_equal_approx(float(model.parts[copy_id].get("w", 0.0)), 2.4),
			"put down, the copy is 2.4 m wide too: %s" % model.parts.get(copy_id, {}))
	ctrl.call(KEY_V)
	check(str(v.holding.get("type", "")) == "sofa", "Ctrl+V again: another")
	v._drop_holding()
	var clip_bus := Modules.bus("design")
	var shared: Dictionary = clip_bus.get("clipboard")
	check((shared.get("items", []) as Array).size() == 1 and str(shared.items[0].entry.kind) == "sofa"
			and is_equal_approx(float(shared.items[0].entry.w), 2.4), "the copy is on the designer's clipboard too, to paste there")
	# A designer copy of several things is carried as one, on the guides.
	var two: Dictionary = shared.duplicate(true)
	var other: Dictionary = (two.items[0] as Dictionary).duplicate(true)
	other.id = "p_other"
	other.entry.at = [2.6, 0.0, 0.0]
	two.items.append(other)
	two.size = Vector2(5.0, 1.0)
	two.label = "2 things"
	clip_bus.set("clipboard", two)
	ctrl.call(KEY_V)
	check(v.holding.has("clip") and v.holding.label == "2 things", "a designer copy of 2 things in your hands")
	await _settle()
	check(v._ghost != null and is_equal_approx(float(v._ghost.get_meta("size").x), 5.0), "its ghost spans the copy")
	if clip_bus.has_method("paste_ops"):
		var n1 := model.parts.size()
		check(v.put_down(), "put down")
		await frames(1)
		check(model.parts.size() == n1 + 2, "both pasted: %d" % (model.parts.size() - n1))
		b.sync.undo()
	v._drop_holding()
	clip_bus.set("clipboard", {})
	b.sync.undo()
	b.sync.undo()
	await frames(1)
	v.toggle_palette()
	await frames(1)

	# X removes the sofa.
	v.body.position = Vector3(float(model.parts[sofa].at[0]), 0.95, float(model.parts[sofa].at[2]) + 2.0)
	_face(v, Vector3(float(model.parts[sofa].at[0]), 0.3, float(model.parts[sofa].at[2])))
	await _physics(2)
	check(v.aimed_part() == sofa and v.remove_aimed(), "X removes the part you aim at")
	await frames(2)
	check(not model.parts.has(sofa), "the sofa is gone")

	# The ROOMS tab: the room you stand in becomes the type you pick, grouped by category.
	v.body.position = Vector3(2.0, 0.95, 3.0)
	await _physics(2)
	v.toggle_palette()
	(v._palette.find_child("Tab_rooms", true, false) as Button).pressed.emit()
	check(v.palette_tab == "rooms" and v._palette.find_child("Group_domestic", true, false) != null, "rooms are grouped by category")
	v._search.text = "kitchen"
	v._search.text_changed.emit("kitchen")
	(v._palette.find_child("Item_kitchen", true, false) as Button).pressed.emit()
	await frames(1)
	check(str(model.rooms[room].type) == "kitchen", "picking one makes the room you're in that type")
	b.sync.undo()
	await frames(1)

	# Hooks for other modules: a preview before taking, takers for their own items, sections.
	var previewed: Array = []
	walk.set_preview_maker(func(item: Dictionary) -> Control:
		previewed.append(item.id)
		var l := Label.new()
		l.name = "PreviewOf_" + str(item.id)
		return l)
	var taken: Array = []
	walk.register_taker("test", func(_view: Node, item: Dictionary) -> bool:
		if str(item.id).begins_with("module:"):
			taken.append(item.id)
			return true
		return false)
	walk.register_tab_section("test.modules", "Saved modules", func(view: Node) -> Control:
		var bt := Button.new()
		bt.name = "Module_office"
		bt.pressed.connect(func() -> void: view.call("use_item", {"id": "module:office", "label": "Office", "tags": []}))
		return bt)
	(v._palette.find_child("Tab_objects", true, false) as Button).pressed.emit()
	v._search.text = "sofa"
	v._search.text_changed.emit("sofa")
	(v._palette.find_child("Item_sofa", true, false) as Button).pressed.emit()
	check(previewed == ["sofa"] and v._palette.find_child("PreviewOf_sofa", true, false) != null and v.holding.is_empty(),
			"with a preview, a click shows it first")
	(v._palette.find_child("Take", true, false) as Button).pressed.emit()
	check(str(v.holding.get("type", "")) == "sofa", "and TAKE puts it in your hands")
	v._drop_holding()
	v.toggle_palette()
	(v._palette.find_child("Module_office", true, false) as Button).pressed.emit()
	check(taken == ["module:office"], "another module's section and taker get their items")
	v._search.text = ""
	v._search.text_changed.emit("")
	if v.is_palette_open():
		v.toggle_palette()
	walk.set_preview_maker(Callable())
	walk.unregister_taker("test")
	walk.unregister_tab_section("test.modules")

	# The designer's palette is the source: its groups, plus columns, and groups other modules
	# add (saved modules) handed to their own pick.
	var dbus := Modules.bus("design")
	var picks: Array = []
	dbus.call("register_palette_group", "objects", "test.saved", "Saved modules", func() -> Array:
		return [{"id": "m1", "label": "My office module", "tags": PackedStringArray(["module"])}],
		func(id: String) -> void: picks.append(id), 90)
	var gids: Array = v.palette_groups().map(func(g: Dictionary) -> String: return str(g.id))
	check(gids.has("living") and gids.has("columns") and gids.has("test.saved"), "the designer's groups, columns and added groups: %s" % [gids])
	v.toggle_palette()
	v._search.text = "office module"
	v._search.text_changed.emit("office module")
	(v._palette.find_child("Item_m1", true, false) as Button).pressed.emit()
	check(picks == ["m1"], "an added group's item goes to its own pick")
	v._search.text = ""
	v._search.text_changed.emit("")
	if v.is_palette_open():
		v.toggle_palette()
	dbus.call("unregister_palette_group", "objects", "test.saved")

	# Fly: up through the ceiling.
	v.toggle_fly()
	check(v.flying and v.body.collision_mask == 0, "Q flies, through walls")
	await frames(1)
	check(v._aim_text().begins_with("Flying") or v._aim_text().contains("\n"), "the help bar knows you fly: %s" % v._aim_text())
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
	walk.set_preview_maker(kept_preview)
	walk.unregister_module()
	design.queue_free()


## A couple of physics ticks and drawn frames (the ghost follows on drawn frames).
func _settle() -> void:
	await _physics(2)
	for i in 2:
		await get_tree().process_frame


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
