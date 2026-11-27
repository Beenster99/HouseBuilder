extends ModuleTest
## The design hall: its walls of screens and their channels, the holotable's live model, the
## designer at the table, full-screen panels and everyone's pointer on the screens and table.

const HallScene := preload("res://modules/design/internal/hall/design_hall.tscn")
const HallChannels := preload("res://modules/design/internal/hall/hall_channels.gd")


func run_tests() -> void:
	var building := Modules.bus("building") as BuildingBus
	building.reset_data()
	var hall: Node3D = HallScene.instantiate()
	add_child(hall)
	await frames(3)
	check(bool(hall.get_meta("crew_avatars", false)), "the hall shows the crew's avatars")
	var walls: Dictionary = hall.get("walls")
	check(walls.size() == 4, "four walls of screens")
	var ids := HallChannels.channels(hall).map(func(c: Dictionary) -> String: return str(c.id))
	for want: String in ["plan", "side", "3d", "bom", "cost"]:
		check(want in ids, "a %s channel" % want)
	var design := Modules.bus("design") as DesignBus
	design.register_channel("test.big", "Test board", func(_m: BuildingModel) -> Control:
		var l := Label.new()
		l.text = "BIG BOARD"
		return l)
	ids = HallChannels.channels(hall).map(func(c: Dictionary) -> String: return str(c.id))
	check("channel:test.big" in ids, "other modules add wall-screen channels")
	var ch := HallChannels.make("channel:test.big", hall, 24)
	check(ch.find_children("*", "Label", true, false).size() == 1, "and the screens show them")
	ch.free()
	design.unregister_channel("test.big")
	var boards: Dictionary = hall.get("boards")
	var left: Node = boards["left"]
	check(str((left.get("panels") as Array)[0].view) == "plan", "the left wall starts on the plan")
	left.call("step", 0, 1)
	await frames(1)
	check(str((left.get("panels") as Array)[0].view) == "side", "> flips a panel to the next channel")
	check(str((hall.get("screens") as Node).call("get_value", "wall:left:0")) == "side", "and shares it with the room")
	left.call("set_view", 0, "plan")

	# The table's model grows as the design does.
	var designer: Node3D = hall.get("designer")
	var session: DesignSession = designer.get("session")
	session.set_tool("room")
	session.press(Vector3(0, 0, 0))
	session.release(Vector3(8, 0, 6))
	await frames(2)
	var holo: Node3D = hall.get("holo")
	var view: Node = holo.get("view")
	check(int(view.call("node_count")) >= 5, "the table's model has the room and its walls: %d" % int(view.call("node_count")))
	var box: AABB = hall.call("bounds")
	check(box.size.x >= 7.9 and box.size.z >= 5.9, "the hall knows the building's size: %s" % str(box))
	holo.call("nudge", 0.5, 2.0, Vector2(0.2, 0))
	check(is_equal_approx(float(holo.get("turn")), 0.5) and is_equal_approx(float(holo.get("zoom")), 2.0), "the table turns and zooms")

	# Pointers: one set from a wall screen shows on the table for everyone.
	hall.call("set_pointer", Vector3(4, 0, 3))
	await frames(2)
	check((hall.call("pointers") as Dictionary).size() == 1, "this player's pointer is known")
	check(int(holo.call("figure_count")) == 1, "and stands on the table's model")
	hall.call("set_pointer", null)
	await frames(2)
	check(int(holo.call("figure_count")) == 0, "and goes when it leaves the screen")

	# Pings: on the table's model, on a list on a wall, and on a drawing.
	var pings := hall.call("ping_count") as int
	hall.call("ping_at", Vector3(2, 0, 2))
	await frames(2)
	check(int(hall.call("ping_count")) == pings + 1, "a ping on the design shows on the table")
	await get_tree().create_timer(0.3).timeout  # one ping per player every 0.25 s
	var right: Node = boards["right"]
	var px: Vector2 = ((right.get("_slots") as Array)[0] as Control).get_global_rect().get_center()
	hall.call("_on_wall_middle", px, "right")
	await frames(2)
	check(int(hall.call("ping_count")) == pings + 2, "a ping on a wall's list shows in the hall")
	await get_tree().create_timer(0.3).timeout
	var walker_cam: Camera3D = (hall.get("walker") as Node).get("camera")
	walker_cam.global_transform = Transform3D(Basis.looking_at(Vector3(0, -1, 0.01).normalized()), Vector3(0, 2.5, 0))
	hall.call("ping_look")
	await frames(2)
	check(int(hall.call("ping_count")) == pings + 3, "looking down at the table's model and middle-clicking pings it")

	# The designer at the table, and back.
	hall.call("open_designer")
	await frames(2)
	check(str(hall.get("mode")) == "designer" and bool(designer.get("active")), "F at the table opens the designer")
	check((hall.get("designer_view") as Control).visible, "drawn full screen")
	check(bool(designer.camera.get("plan")), "opening on the plan")
	var hud: Node = designer.get("hud")
	check((hud.get("mini_3d") as Control).is_visible_in_tree(), "with the 3D view top right")
	check(int(hud.get("theme").default_font_size) <= 14, "in small text")
	var mini: DesignMiniWorld = hud.get("mini")
	await frames(25)
	check(int(mini.view.call("node_count")) >= 5, "the small views have the whole design: %d" % int(mini.view.call("node_count")))
	check(not (hud.get("section") as Control).is_visible_in_tree(), "no section until asked")
	hud.call("show_section", true)
	await frames(2)
	check((hud.get("section") as Control).is_visible_in_tree(), "and a section along the bottom when asked")
	hud.call("show_section", false)
	designer.session.presence.set_cursor(Vector3(2, 0, 2))
	await frames(2)
	check(mini.marker_count() == 1, "pointers show in the small views")
	# Walking inside (another camera takes the designer's view): the designer steps aside.
	var walk_cam := Camera3D.new()
	designer.add_child(walk_cam)
	walk_cam.make_current()
	await frames(2)
	check(bool(designer.get("lent_view")) and not (hud as Control).visible, "walk-inside has the view without the designer's panels")
	walk_cam.queue_free()
	designer.camera.make_current()
	await frames(2)
	check(not bool(designer.get("lent_view")) and (hud as Control).visible, "and gives it back")
	designer.emit_signal("leave_requested")
	await frames(1)
	check(str(hall.get("mode")) == "room" and not bool(designer.get("active")), "Esc there comes back to the hall")

	# A wall panel full screen.
	check(bool(hall.call("open_fullscreen", "right", 1)), "F at a wall shows a panel full screen")
	await frames(2)
	var full: Control = hall.get("fullscreen")
	check(full != null and full.is_inside_tree(), "the full-screen page is up")
	var texts := full.find_children("*", "RichTextLabel", true, false)
	await frames(30)
	var got := ""
	for t: RichTextLabel in texts:
		got += t.get_parsed_text()
	check(got.contains("COST"), "showing the cost channel: %s" % got.left(60))
	hall.call("close_fullscreen")
	check(str(hall.get("mode")) == "room", "and F puts it back")

	# The bill of materials lists what's placed.
	var bom := HallChannels.make("bom", hall, 16)
	add_child(bom)
	await frames(40)
	var bom_text := ""
	for t: RichTextLabel in bom.find_children("*", "RichTextLabel", true, false):
		bom_text += t.get_parsed_text()
	check(bom_text.contains("Item") and bom_text.contains("£"), "the bill of materials lists the walls: %s" % bom_text.left(80))
	bom.queue_free()
	hall.queue_free()
	await frames(2)
	building.reset_data()
