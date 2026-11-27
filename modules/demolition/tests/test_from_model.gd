extends ModuleTest
## "Demolish" from a design: the host takes what falls from the structure solver.
##   tools/run_tests.sh demolition

const C := preload("res://modules/building/api/building_commands.gd")


func run_tests() -> void:
	var bus := Modules.bus("demolition") as DemolitionBus
	var building := Modules.bus("building") as BuildingBus
	check(bus != null and building != null, "demolition and building buses loaded")
	if bus == null or building == null:
		return
	var m := BuildingModel.new("shed1", "Test shed")
	m.apply(C.add_level(2.7, "First floor"))
	for side: Array in [[[0, 0, 0], [6, 0, 0]], [[6, 0, 0], [6, 0, 4]], [[6, 0, 4], [0, 0, 4]], [[0, 0, 4], [0, 0, 0]]]:
		m.apply(C.place_part("strip_footing", 0, {"a": side[0], "b": side[1]}))
		m.apply(C.place_part("wall_loadbearing", 0, {"a": side[0], "b": side[1]}, "masonry"))
	m.apply(C.place_opening("window_medium", "p2", 3.0))
	m.apply(C.place_part("slab", 1, {"outline": C.rect(0, 0, 6, 4)}, "timber"))
	var was := building.model
	building.model = m
	bus.start_from_model(m, {"open": false})
	check(bus.is_active() and bus.title == "Test shed" and bus.model == m, "the host keeps the model it demolishes")
	var walls: Array[String] = []
	var slab := ""
	for p: Dictionary in bus.parts:
		if p.family == "wall":
			walls.append(p.id)
		elif p.family == "slab":
			slab = p.id
	check(walls.size() == 4 and slab != "", "four walls and a floor: %s" % str(walls))
	for w in walls:
		bus.request_charge(w, 0.0)
	var fall := bus.predicted()
	check(slab in fall and "p9" in fall, "without its walls the floor and the window fall: %s" % fall)
	check(not walls.has(fall[0]) if not fall.is_empty() else true, "charged walls are not listed")
	# The window comes down whole: its library model on the body, its box the collision.
	var view: Node3D = load("res://modules/demolition/internal/demolition_view.tscn").instantiate()
	add_child(view)
	await frames(2)
	var bodies: Array = view._chunks.get("p9", [])
	var has_model := false
	for b: RigidBody3D in bodies:
		var n := b.get_node_or_null("Model")
		has_model = has_model or (n != null and n.find_children("*", "MeshInstance3D", true, false).size() > 1)
	check(bodies.size() == 1 and has_model, "the window is drawn as its library model")
	view.queue_free()
	await frames(1)
	bus.apply_net_snapshot({})
	check(bus.model == null, "clearing the site forgets the model")
	building.model = was
