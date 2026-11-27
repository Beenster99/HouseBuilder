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

	# The designer at the table, and back.
	hall.call("open_designer")
	await frames(2)
	check(str(hall.get("mode")) == "designer" and bool(designer.get("active")), "F at the table opens the designer")
	check((hall.get("designer_view") as Control).visible, "drawn full screen")
	designer.emit_signal("leave_requested")
	await frames(1)
	check(str(hall.get("mode")) == "room" and not bool(designer.get("active")), "Esc there comes back to the hall")

	# A wall panel full screen.
	check(bool(hall.call("open_fullscreen", "right", 0)), "F at a wall shows a panel full screen")
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
