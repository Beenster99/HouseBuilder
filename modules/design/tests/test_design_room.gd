extends ModuleTest
## The design room scene: Start on the main menu goes there, it draws the shared building
## and updates as it changes, shows selections in colour, has the HUD with every tool, the
## live cost panel and other modules' actions, and switches between 3D and the 2D plan.
##   tools/run_tests.sh design

const C := preload("res://modules/building/api/building_commands.gd")


func run_tests() -> void:
	var design := Modules.bus("design") as DesignBus
	var building := Modules.bus("building") as BuildingBus
	check(Menu.start().get("scene", "") == DesignBus.ROOM_SCENE, "Start goes to the design room: %s" % str(Menu.start()))
	check(Router.has_scene(DesignBus.ROOM_SCENE), "the room scene is registered")
	var pressed: Array = []
	design.register_action("test.act", "Test it", func(m: BuildingModel) -> void: pressed.append(m), 99)

	building.sync.edit(C.place_part("wall_loadbearing", 0, {"a": [0, 0, 0], "b": [5, 0, 0]}, "masonry"))
	var room: Node3D = (load(Router.scene_path(DesignBus.ROOM_SCENE)) as PackedScene).instantiate()
	add_child(room)
	await frames(5)
	check(room.name == "DesignRoom", "the room opens")
	var view: Node3D = room.get("view")
	check(view.call("node_count") == 1, "it draws the wall already there")
	var session: DesignSession = room.get("session")
	session.set_tool("room")
	session.press(Vector3(0, 0, 0))
	session.release(Vector3(5, 0, 4))
	await frames(2)
	check(building.model.rooms.size() == 1 and view.call("node_count") == 1 + 1 + 3,
			"a room and three more walls appear: %d nodes" % view.call("node_count"))
	var door := ""
	session.set_tool("door")
	session.press(Vector3(2.5, 0, 0))
	await frames(2)
	for id: String in building.model.parts:
		if building.model.catalog.family_of(str(building.model.parts[id].kind)) == "opening":
			door = id
	check(door != "" and view.call("has_node_for", door), "a door is drawn in the wall")
	session.set_tool("select")
	session.press(Vector3(2.5, 0, 0))
	await frames(2)
	check(view.call("tints").has(door), "the selection is highlighted")

	var marks: Node3D = room.get("marks")
	var net := Modules.bus("multiplayer") as MultiplayerBus
	await get_tree().create_timer(0.3).timeout
	net.ping(Vector3(2.5, 0, 0), door, Vector3.UP, session.label_of(door))
	await frames(1)
	check(marks.call("ping_count") >= 1, "a ping shows a marker")
	check(session.label_of(door) == "Internal door", "pings and notes name what they point at")
	session.add_note(Vector3(1, 0, 1), "", "Check this")
	await frames(1)
	check(marks.get_node("Notes").get_child_count() == 1, "a note shows as a pin")
	check(marks.get_node("Dimensions").get_child_count() == 4, "wall lengths show on the working level")
	# The mark-up wheel: hold the middle button, point at a slice, let go.
	var wheel: Control = room.get("wheel")
	var asked: Array = []
	session.note_requested.connect(func(at: Vector3, target: String) -> void: asked.append(target))
	room.call("open_wheel", Vector2(800, 450))
	check(bool(wheel.get("is_open")), "holding the middle button opens the wheel")
	wheel.call("aim", Vector2(0, -60))
	check(wheel.call("selected") == "note", "up points at Note")
	wheel.call("aim", Vector2(60, 0))
	check(wheel.call("selected") == "ping", "right points at Ping")
	wheel.call("aim", Vector2(0, -60))
	room.call("close_wheel")
	check(not bool(wheel.get("is_open")), "letting go closes it")
	room.call("open_wheel", Vector2(800, 450))
	wheel.call("aim", Vector2(3, 3))
	room.call("close_wheel")
	var hud: Control = room.get("hud")
	room.call("open_wheel", Vector2(800, 450))
	wheel.call("aim", Vector2(-60, 0))
	room.call("close_wheel")
	check(not marks.get_node("Notes").visible, "the wheel hides the notes")
	hud.call("toggle_layer", "notes")
	check(marks.get_node("Notes").visible, "and shows them again")
	hud.call("set_layer", "notes", false)
	check(not marks.get_node("Notes").visible, "the Notes layer hides")
	hud.call("set_layer", "notes", true)
	check(hud.find_children("*", "Button", true, false).size() > DesignSession.TOOLS.size(), "the HUD has the tools")
	var labels := hud.find_children("*", "Button", true, false).map(func(b: Node) -> String: return (b as Button).text)
	check("Test it" in labels, "and other modules' actions: %s" % str(labels))
	var cost := hud.find_children("*", "RichTextLabel", true, false)
	await frames(2)
	var cost_text := ""
	for c: RichTextLabel in cost:
		cost_text += c.get_parsed_text()
	check(cost_text.contains("COST") and cost_text.contains("£") and cost_text.contains("Walls"), "the live cost panel shows the walls' cost")
	var engineer_panel := Label.new()
	engineer_panel.text = "Engineer report"
	design.register_overlay("test.eng", "Engineer", func(_m: BuildingModel) -> Dictionary: return {door: Color.RED},
			func() -> Control: return engineer_panel)
	await frames(1)
	room.call("set_overlay", "test.eng")
	await frames(2)
	check(view.call("tints").has(door) and engineer_panel.is_inside_tree(), "an overlay colours parts and shows its panel")
	room.call("set_overlay", "")
	design.unregister_overlay("test.eng")
	await frames(2)
	room.call("toggle_plan")
	check(bool((room.get("camera") as Camera3D).get("plan")), "Tab switches to the 2D plan")
	room.call("toggle_plan")
	session.add_level()
	await frames(2)
	check(session.level == 1 and building.model.level_count() == 2, "a storey added from the room")

	room.queue_free()
	await frames(3)
	check(building.model.parts.size() >= 5, "the building stays when the room closes")
	design.unregister_action("test.act")
	(building as BuildingBus).reset_data()
