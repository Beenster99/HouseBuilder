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

	var hud: Control = room.get("hud")
	check(hud.find_children("*", "Button", true, false).size() > DesignSession.TOOLS.size(), "the HUD has the tools")
	var labels := hud.find_children("*", "Button", true, false).map(func(b: Node) -> String: return (b as Button).text)
	check("Test it" in labels, "and other modules' actions: %s" % str(labels))
	var cost := hud.find_children("*", "RichTextLabel", true, false)
	await frames(2)
	var cost_text := ""
	for c: RichTextLabel in cost:
		cost_text += c.get_parsed_text()
	check(cost_text.contains("COST") and cost_text.contains("£") and cost_text.contains("Walls"), "the live cost panel shows the walls' cost")
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
