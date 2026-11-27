extends ModuleTest
## Editing in the designer: the Add rooms / Add objects palette (groups, filter, arming the
## tool), reshaping a room by its corners and edges (walls follow), adding a corner, left-drag
## panning on empty floor, the right-click menu and edit form, stamps, the mode banner,
## rolling and moving docks, and room labels that stay sharp and fade with zoom.
##   tools/run_tests.sh design

const RoomScene := preload("res://modules/design/internal/room/design_room.tscn")


func run_tests() -> void:
	var building := Modules.bus("building") as BuildingBus
	var design := Modules.bus("design") as DesignBus
	building.reset_data()
	var room: Node3D = RoomScene.instantiate()
	add_child(room)
	await frames(3)
	var s: DesignSession = room.get("session")
	var model := building.model
	check(design.open_room == room, "the bus knows the open room")

	# Palettes: grouped, filtered, and picking arms the tool.
	var rooms := design.palette_groups("rooms")
	var objects := design.palette_groups("objects")
	check(rooms.size() >= 2 and objects.size() >= 2, "rooms and objects come in groups: %d, %d" % [rooms.size(), objects.size()])
	var hud: Node = room.get("hud")
	var pal: Node = hud.get("palette")
	await frames(2)
	var all_rows := int(pal.call("row_count", "rooms"))
	pal.call("set_filter", "rooms", "bed")
	var few := int(pal.call("row_count", "rooms"))
	check(few >= 1 and few < all_rows, "the filter narrows the rooms: %d of %d" % [few, all_rows])
	var seen := []
	design.palette_previewed.connect(func(k: String, id: String, _src: String) -> void: seen.append([k, id]))
	check(bool(pal.call("pick", "rooms", "bedroom")) and s.tool == "room" and s.room_type == "bedroom", "picking a room type arms the Room tool")
	check(seen.size() == 1, "and tells the preview")
	var fixture: String = (objects[0].items as Array)[0].id
	check(design.use_kind(fixture) and s.tool in ["fixture", "door", "window"], "use_kind arms the placing tool for %s" % fixture)
	var extra_picked := []
	design.register_palette_group("rooms", "test.modules", "Saved modules", func() -> Array: return [{"id": "flat", "label": "Studio flat", "tags": PackedStringArray(["module"])}],
			func(id: String) -> void: extra_picked.append(id))
	check(str(design.palette_groups("rooms").back().title) == "Saved modules", "other modules add groups")
	await frames(2)
	pal.call("set_filter", "rooms", "studio")
	check(bool(pal.call("pick", "rooms", "flat")) and extra_picked == ["flat"], "and get their picks")
	design.unregister_palette_group("rooms", "test.modules")

	# Draw a room, then reshape it.
	s.use_room_type("bedroom")
	s.press(Vector3(0, 0, 0))
	s.release(Vector3(4, 0, 3))
	var rid: String = model.rooms.keys()[0]
	s.set_tool("select")
	s.presence.select(PackedStringArray([rid]))
	check(not s.shape_handles().is_empty(), "a selected room shows handles")
	s.press(Vector3(4, 0, 3))   # its corner
	s.hover(Vector3(5, 0, 4))
	s.release(Vector3(5, 0, 4))
	var o: Array = model.rooms[rid].outline
	var has_corner := false
	for p: Variant in o:
		has_corner = has_corner or (is_equal_approx(float(p[0]), 5.0) and is_equal_approx(float(p[1]), 4.0))
	check(has_corner, "dragging a corner moves it: %s" % str(o))
	var follows := false
	for pid: String in model.parts:
		var e: Dictionary = model.parts[pid]
		if model.catalog.family_of(str(e.kind)) == "wall":
			follows = follows or (is_equal_approx(float(e.a[0]), 5.0) and is_equal_approx(float(e.a[2]), 4.0)) \
					or (is_equal_approx(float(e.b[0]), 5.0) and is_equal_approx(float(e.b[2]), 4.0))
	check(follows, "and the walls ending there follow")
	var n := (model.rooms[rid].outline as Array).size()
	var h := s.shape_handles()
	var mid: Vector2 = (h.mids as Array)[0]
	s.press(Vector3(mid.x, 0, mid.y))
	s.hover(Vector3(mid.x, 0, mid.y - 1.0))
	s.release(Vector3(mid.x, 0, mid.y - 1.0))
	check((model.rooms[rid].outline as Array).size() == n + 1, "dragging an edge's middle adds a corner")
	var at_new := Vector2(mid.x, mid.y - 1.0)
	var ends := 0
	var walls := 0
	for pid: String in model.parts:
		var e: Dictionary = model.parts[pid]
		if model.catalog.family_of(str(e.kind)) == "wall":
			walls += 1
			for k: String in ["a", "b"]:
				if Vector2(float(e[k][0]), float(e[k][2])).distance_to(at_new) < 0.01:
					ends += 1
	check(ends == 2, "the wall along that edge bends at the new corner (split in two): %d ends there, %d walls" % [ends, walls])
	check(s.remove_corner(1), "and a corner can be taken away")
	check((model.rooms[rid].outline as Array).size() == n, "back to %d corners" % n)

	# Left-drag on empty floor pans when nothing is selected.
	s.presence.select(PackedStringArray())
	s.press(Vector3(30, 0, 30))
	check(s.pan_drag, "left-drag on empty floor pans")
	s.release(Vector3(31, 0, 31))
	check(not s.pan_drag, "until the button comes up")
	s.presence.select(PackedStringArray([rid]))
	s.press(Vector3(30, 0, 30))
	check(s.pan_drag, "and pans with something selected too")
	s.pan_moved = true
	s.release(Vector3(31, 0, 31))
	check(s.presence.my_selection().size() == 1, "a pan keeps the selection")
	s.press(Vector3(30, 0, 30))
	s.release(Vector3(30, 0, 30))
	check(s.presence.my_selection().is_empty(), "a click on empty floor clears it")
	# A right-click goes back to Select from any tool.
	s.set_tool("wall")
	var rc := InputEventMouseButton.new()
	rc.button_index = MOUSE_BUTTON_RIGHT
	rc.pressed = true
	rc.position = Vector2(700, 500)
	room.call("_unhandled_input", rc)
	rc = rc.duplicate() as InputEventMouseButton
	rc.pressed = false
	room.call("_unhandled_input", rc)
	check(s.tool == "select", "a right-click goes back to Select")
	# Dragging out a room shows its size live.
	s.use_room_type("bedroom")
	s.press(Vector3(40, 0, 40))
	s.hover(Vector3(43, 0, 42))
	room.call("_draw_ghost")
	var dims: Label3D = room.get("ghost_dims")
	check(dims.visible and dims.text.contains("3.00 × 2.00") and dims.text.contains("6.0 m²"), "dragging a room shows its size live: %s" % dims.text.replace("\n", " "))
	s.cancel()
	s.set_tool("select")
	room.call("_draw_ghost")
	check(not dims.visible, "and hides it after")
	# The taken contract's plot shows as a red line when no real site is loaded.
	var contracts := Modules.bus("contracts")
	if contracts != null and "active" in contracts:
		var was: Dictionary = contracts.get("active")
		contracts.set("active", {"site": {"id": "", "plot": [[-10, -8], [10, -8], [10, 8], [-10, 8]]}})
		var pl: DesignPlot = room.get("plot")
		await get_tree().create_timer(0.6).timeout
		check(pl.visible and pl.label.text.contains("20.0 × 16.0"), "the contract's plot shows: %s" % pl.label.text)
		contracts.set("active", was)
		await get_tree().create_timer(0.6).timeout
		check(not pl.visible or not was.is_empty(), "and goes when there's no contract")
	# The top bar is the workflow: 1 Get contract, 2 Design, 3 Build it, 4 Hand over.
	var hud2: Node = room.get("hud")
	var flow := hud2.find_child("Workflow", true, false) as Control
	check(flow != null and flow.find_child("Step_contract", true, false) != null and flow.find_child("Step_handover", true, false) != null,
			"the top bar shows the workflow steps")
	var cbus := Modules.bus("contracts")
	if cbus != null and "active" in cbus:
		var was2: Dictionary = cbus.get("active")
		cbus.set("active", {})
		hud2.call("refresh_steps")
		check(str(hud2.get("step_now")) == "contract", "with no contract the step is Get contract")
		cbus.set("active", {"id": "t", "site": {"id": "", "plot": []}})
		hud2.call("refresh_steps")
		check(str(hud2.get("step_now")) == "design" and str(hud2.get("step_next")) == "build", "with one, Design, then Build it")
		cbus.set("active", was2)
		hud2.call("refresh_steps")
	# Alignment guides while placing: lines up with nearby parts, and shows the line.
	s.sync.edit(BuildingCommands.place_part("column", s.level, {"at": [61.2, 0, 60.0]}, "steel"))
	await frames(2)
	s.set_tool("column")
	s.hover(Vector3(61.2, 0, 64.0))
	check(absf((s.cursor as Vector3).x - 61.25) > 0.001 and not s.guides.is_empty(),
			"placing lines up with a part nearby and shows a guide: x %.2f, %d guides" % [(s.cursor as Vector3).x, s.guides.size()])
	room.call("_draw_ghost")
	s.set_tool("select")
	s.hover(Vector3(61.2, 0, 64.0))
	check(s.guides.is_empty(), "no guides when just pointing")
	# Moving a room along one axis only: it moves, its walls and contents go with it (but a
	# wall it shares with a room that stays), and its own walls don't snap it back.
	s.set_tool("room")
	s.room_type = "bedroom"
	s.press(Vector3(-60, 0, -60))
	s.press(Vector3(-56, 0, -57))
	s.press(Vector3(-56, 0, -60))
	s.press(Vector3(-52, 0, -57))
	s.sync.edit(BuildingCommands.place_part("column", s.level, {"at": [-58.0, 0, -58.5]}, "steel"))
	await frames(2)
	var mv_a := ""
	for r_id in model.rooms_on(s.level):
		if DesignGuides.room_box(model, r_id).has_point(Vector2(-58, -58.5)):
			mv_a = r_id
	var walls_at := func(x: float) -> int:
		var count := 0
		for wid in model.parts_on(s.level):
			var we: Dictionary = model.parts[wid]
			if we.has("a") and absf(float(we.a[0]) - x) < 0.01 and absf(float(we.b[0]) - x) < 0.01:
				count += 1
		return count
	var shared_before: int = walls_at.call(-56.0)
	check(mv_a != "" and int(walls_at.call(-60.0)) >= 1 and shared_before >= 1, "two rooms side by side, with walls")
	s.set_tool("select")
	s.press(Vector3(-59, 0, -59.25))
	for k in 6:
		s.hover(Vector3(-59.0 - 0.25 * (k + 1), 0, -59.25))
	check(s.drag.size() > 0 and (s.drag.ids as Array).size() >= 5, "the drag takes the room, its walls and what stands in it: %s" % [s.drag.get("ids")])
	s.release(Vector3(-60.5, 0, -59.25))
	await frames(2)
	var box_a := DesignGuides.room_box(model, mv_a) if mv_a != "" else Rect2()
	check(box_a.position.is_equal_approx(Vector2(-61.5, -60)) and box_a.size.is_equal_approx(Vector2(4, 3)),
			"a room slid along x alone moves 1.5 m along x: %s" % box_a)
	check(int(walls_at.call(-61.5)) >= 1 and int(walls_at.call(-60.0)) == 0, "its wall went with it")
	check(int(walls_at.call(-56.0)) == shared_before, "the wall it shares with the room that stays, stays")
	var col_moved := false
	for cid in model.parts_on(s.level):
		var ce: Dictionary = model.parts[cid]
		if ce.has("at") and Vector2(float(ce.at[0]), float(ce.at[2])).is_equal_approx(Vector2(-59.5, -58.5)):
			col_moved = true
	check(col_moved, "and so did the column inside it")
	s.undo()
	await frames(2)
	check(DesignGuides.room_box(model, mv_a).position.is_equal_approx(Vector2(-60, -60)) and int(walls_at.call(-60.0)) >= 1,
			"one undo puts the room and its walls back")
	s.press(Vector3(-59, 0, -59.25))
	for k in 4:
		s.hover(Vector3(-59, 0, -59.25 + 0.25 * (k + 1)))
	s.release(Vector3(-59, 0, -58.25))
	await frames(2)
	check(DesignGuides.room_box(model, mv_a).position.is_equal_approx(Vector2(-60, -59)), "and along z alone too: %s" % DesignGuides.room_box(model, mv_a))
	s.undo()
	await frames(2)
	# Mirroring for symmetrical designs: a mirrored copy beside the selection, walls, a turned
	# column and a door with it (the wall on the mirror line isn't doubled), and a flip in place.
	var mv_b := ""
	for r_id in model.rooms_on(s.level):
		if DesignGuides.room_box(model, r_id).has_point(Vector2(-54, -58.5)):
			mv_b = r_id
	s.sync.edit(BuildingCommands.place_part("column", s.level, {"at": [-54.0, 0, -58.0], "rot": 30.0}, "steel"))
	var top_wall := ""
	for wid in model.parts_on(s.level):
		var we: Dictionary = model.parts[wid]
		if we.has("a") and absf(float(we.a[2]) + 60.0) < 0.01 and absf(float(we.b[2]) + 60.0) < 0.01 \
				and minf(float(we.a[0]), float(we.b[0])) > -56.1 and maxf(float(we.a[0]), float(we.b[0])) < -51.9:
			top_wall = wid
	check(mv_b != "" and top_wall != "", "a second room with its own top wall")
	s.sync.edit(BuildingCommands.place_opening(s.door_kind, top_wall, 1.0))
	await frames(2)
	var rooms_n := model.rooms.size()
	var parts_n := model.parts.size()
	s.presence.select(PackedStringArray([mv_b]))
	check(s.mirror_selection(0, true) > 0, "Shift+M mirrors a copy")
	await frames(2)
	var copy_room := ""
	for r_id in model.rooms_on(s.level):
		if DesignGuides.room_box(model, r_id).is_equal_approx(Rect2(-52, -60, 4, 3)):
			copy_room = r_id
	check(model.rooms.size() == rooms_n + 1 and copy_room != "", "the copy of the room sits beside it, mirrored about its right edge")
	check(int(walls_at.call(-52.0)) == 1 and int(walls_at.call(-48.0)) == 1, "with its walls, the one on the mirror line not doubled: %d, %d" % [walls_at.call(-52.0), walls_at.call(-48.0)])
	var mirrored_col := false
	var copied_door := false
	for cid in model.parts_on(s.level):
		var ce: Dictionary = model.parts[cid]
		if ce.has("at") and Vector2(float(ce.at[0]), float(ce.at[2])).is_equal_approx(Vector2(-50, -58)):
			mirrored_col = is_equal_approx(float(ce.rot), 330.0)
	for oid in model.parts:
		var oe: Dictionary = model.parts[oid]
		if oe.has("host") and oid != "" and str(oe.host) != top_wall and model.parts.has(str(oe.host)):
			var hw: Dictionary = model.parts[str(oe.host)]
			copied_door = copied_door or minf(float(hw.a[0]), float(hw.b[0])) > -52.1
	check(mirrored_col, "the column mirrored and turned the other way")
	check(copied_door, "the door copied onto the copied wall")
	check(copy_room in s.presence.my_selection(), "the copy is selected")
	s.undo()
	await frames(2)
	check(model.rooms.size() == rooms_n and model.parts.size() == parts_n, "one undo takes the whole copy away")
	s.presence.select(PackedStringArray([mv_b]))
	var flip_n := s.mirror_selection(1, false)
	await frames(2)
	var flipped := false
	for cid in model.parts_on(s.level):
		var ce: Dictionary = model.parts[cid]
		if ce.has("at") and Vector2(float(ce.at[0]), float(ce.at[2])).is_equal_approx(Vector2(-54, -59)):
			flipped = is_equal_approx(float(ce.rot), 150.0)
	check(flipped and model.rooms.size() == rooms_n, "Flip top to bottom turns it over in place")
	s.undo()
	await frames(2)
	var ctx_m: Node = room.get("context")
	ctx_m.call("open_at", Vector3(-54, 0, -59), Vector2(400, 300))
	var mlabels := []
	for i in (ctx_m.get("menu") as PopupMenu).item_count:
		mlabels.append((ctx_m.get("menu") as PopupMenu).get_item_text(i))
	(ctx_m.get("menu") as PopupMenu).hide()
	check(mlabels.any(func(t: String) -> bool: return t.begins_with("Mirror copy")) and "Flip top to bottom" in mlabels,
			"the right-click menu has Mirror and Flip: %s" % str(mlabels))
	# The docks' cards stretch up and down (a grip between them), and keep their sizes.
	var lsplit := hud2.find_child("Split_left", true, false) as VSplitContainer
	check(lsplit != null and lsplit.get_child_count() == 3, "the left dock's cards sit in a splitter")
	if lsplit:
		var want := PackedInt32Array([40, -30])
		lsplit.split_offsets = want
		hud2.call("_save_split", lsplit)
		lsplit.split_offsets = PackedInt32Array([0, 0])
		hud2.call("_load_split", lsplit)
		check(lsplit.split_offsets == want, "and the sizes are remembered: %s" % str(lsplit.split_offsets))
		lsplit.split_offsets = PackedInt32Array([0, 0])
		hud2.call("_save_split", lsplit)
	# Shift+drag on empty floor draws a box that selects all inside it.
	var whole := (room.get("hud") as Node).get("mini") as DesignMiniWorld
	var bb := whole.bounds()
	var lo := bb.position - Vector3(1, 0, 1)
	var hi := bb.end + Vector3(1, 0, 1)
	s.hover(Vector3(lo.x, 0, lo.z))
	s.press(Vector3(lo.x, 0, lo.z), true)
	check(str(s.preview().get("kind", "")) == "box", "Shift+drag on empty floor draws a box")
	s.hover(Vector3(hi.x, 0, hi.z))
	s.release(Vector3(hi.x, 0, hi.z))
	var boxed := s.presence.my_selection()
	check(boxed.size() > 1 and rid in boxed, "and selects everything inside it: %d" % boxed.size())
	s.delete_selection()
	await frames(2)
	check(model.rooms_on(s.level).is_empty() and model.parts_on(s.level).is_empty(), "then Del deletes them all")
	s.undo()
	await frames(2)
	check(model.rooms.has(rid), "and undo brings them back")

	# The right-click menu and edit form.
	var ctx: Node = room.get("context")
	check(bool(ctx.call("open_at", Vector3(1, 0, 1), Vector2(400, 300))), "right-click on a room opens its menu")
	check(s.presence.my_selection() == PackedStringArray([rid]), "and selects it")
	var menu: PopupMenu = ctx.get("menu")
	var labels := []
	for i in menu.item_count:
		labels.append(menu.get_item_text(i))
	check("Edit…" in labels and "Delete  (Del)" in labels, "with Edit and Delete: %s" % str(labels))
	(ctx.get("menu") as PopupMenu).hide()
	ctx.call("open_edit", rid)
	await frames(1)
	check((ctx.get("_edit") as PopupPanel).visible, "Edit opens the form")
	(ctx.get("_edit") as PopupPanel).hide()
	check("Walk inside from here" in labels or not bool(ctx.call("can_walk")), "and Walk inside from here")
	# Bare floor: only Walk inside from here, which starts walk-inside standing on that spot.
	var walk := Modules.bus("walk")
	if bool(ctx.call("can_walk")):
		check(bool(ctx.call("open_at", Vector3(40, 0, 40), Vector2(10, 10))) and menu.item_count == 1 \
				and menu.get_item_text(0) == "Walk inside from here", "on bare floor the menu is just Walk inside from here")
		menu.hide()
		ctx.call("_on_item", menu.get_item_id(0))
		await frames(3)
		var wv: Node = walk.get("view")
		check(bool(walk.call("is_open")) and wv != null, "it opens walk-inside")
		if wv and wv.has_method("feet"):
			var f: Vector3 = wv.call("feet")
			check(Vector2(f.x, f.z).distance_to(Vector2(40, 40)) < 0.5, "standing where I clicked: %s" % f)
		walk.call("close")
		await frames(3)
	else:
		check(not bool(ctx.call("open_at", Vector3(40, 0, 40), Vector2(10, 10))), "nothing there and no walk-inside, no menu")

	# Stamps.
	var ghost := Node3D.new()
	var ops_at := func(level: int, at: Vector3, _rot: float) -> Array:
		return [BuildingCommands.place_part("column", level, {"at": [at.x, 0.0, at.z]}, "steel")]
	check(design.begin_stamp("Test", ghost, ops_at) and bool(room.call("stamping")), "begin_stamp arms a stamp")
	var parts := model.parts.size()
	room.call("stamp_at", Vector3(10, 0, 10))
	check(model.parts.size() == parts + 1, "a click places it")
	s.set_tool("select")
	check(not bool(room.call("stamping")), "another tool ends it")

	# The mode banner and docks.
	s.set_tool("select")
	await frames(1)
	var banner: RichTextLabel = hud.get("_banner_text")
	check(banner.get_parsed_text().contains("SELECT MODE"), "the banner says Select mode: %s" % banner.get_parsed_text().left(40))
	s.set_tool("wall")
	check(banner.get_parsed_text().contains("WALL"), "and the tool otherwise")
	var help: HelpBar = hud.get("help")
	check(help != null and help.visible and help.shown()[0].contains("Esc") and help.shown()[0].contains("WALL"),
			"the help bar along the bottom says the mode and what the keys do: %s" % help.shown()[0].left(50))
	help.say("hello", false)
	check(help.shown()[1].contains("hello"), "and shows messages in the same place")
	var summary: RichTextLabel = (hud.get("_summary") as RichTextLabel)
	hud.call("_refresh_summary")
	check(summary.get_parsed_text().contains("Rooms") and summary.get_parsed_text().contains("Checks"),
			"a design summary card: %s" % summary.get_parsed_text().left(60).replace("\n", " "))
	check(summary.get_parent().get_parent() is PanelContainer, "each block of information is its own card")
	hud.call("fold_card", "summary", true)
	check(not summary.visible, "a card folds to its title")
	hud.call("fold_card", "summary", false)
	check(int(hud.get("theme").default_font_size) <= 12, "the designer's text is small")
	var left := hud.get("left_dock") as PanelContainer
	var dock := left.get_child(0) as VBoxContainer
	hud.call("roll_dock", left, dock, "left", true)
	check(not dock.get_child(1).visible and left.offset_bottom - left.offset_top <= 40, "a dock rolls up to its bar")
	hud.call("roll_dock", left, dock, "left", false)
	check(dock.get_child(1).visible, "and down again")

	# Room labels are drawn at their size on screen, and fade as the room gets small.
	var view: Node = room.get("view")
	var lab: Label3D = null
	for c in view.find_children("*", "Label3D", true, false):
		lab = c
	check(lab != null and lab.fixed_size, "room labels keep their size on screen (sharp)")
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2000.0
	check(view.call("fade_alpha", cam, 1000.0, Vector3.ZERO, 4.0) == 0.0, "zoomed far out, a room's label is gone")
	cam.size = 20.0
	check(float(view.call("fade_alpha", cam, 1000.0, Vector3.ZERO, 4.0)) == 1.0, "close in, it shows")
	cam.free()

	room.queue_free()
	await frames(2)
	check(design.open_room == null, "the bus forgets the room when it closes")
	building.reset_data()
