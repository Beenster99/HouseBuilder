extends ModuleTest
## The M&E consultant on sample buildings: every room powered and wet room plumbed, routes
## that use doors and service zones, waste that never runs uphill, the cases it cannot
## serve, and the same report every time.
##   tools/run_tests.sh services

const Samples := preload("res://modules/services/tests/samples.gd")
const C := preload("res://modules/building/api/building_commands.gd")


func run_tests() -> void:
	_empty()
	_house()
	_same_every_time()
	_doors_save_holes()
	_sealed_room()
	_waste_never_uphill()
	_placed_sources()
	_long_wc_branch()
	_lift_shaft()


func _empty() -> void:
	var rep := ServicesConsultant.route(BuildingModel.new())
	check(not rep.passed() and rep.summary.begins_with("Nothing to route"), "empty building: %s" % rep.summary)


func _house() -> void:
	var m := Samples.house()
	var rep := ServicesConsultant.route(m)
	check(rep.passed(), "sample house passes: %s" % rep.summary)
	check(rep.rooms.size() == 8, "every room reported")
	for rid: String in rep.rooms:
		check(bool(rep.rooms[rid].powered), "room %s powered" % rid)
	for t in ["kitchen", "utility", "bathroom"]:
		var r := rep.room(Samples.room_of_type(m, t))
		check(r.wet and r.plumbed == true, "%s plumbed" % t)
	check(rep.room(Samples.room_of_type(m, "bedroom")).plumbed == null, "a bedroom is not a wet room")
	for s in ServicesRates.SYSTEMS:
		var sys := rep.system(s)
		check(not sys.is_empty() and float(sys.length) > 0.0 and float(sys.cost) > float(sys.source_cost),
				"%s routed and priced: %s" % [s, str(sys.get("length"))])
		check(str(sys.source.how) == "auto", "%s source chosen by the consultant" % s)
		check((sys.unserved as Array).is_empty(), "%s reaches everything" % s)
	check(rep.system("power").branches.size() == 9, "power: 8 rooms and the boiler: %d" % rep.system("power").branches.size())
	var utility := Samples.room_of_type(m, "utility")
	check(str(rep.system("power").source.room) == utility, "consumer unit in the utility room")
	check(str(rep.system("hot_water").source.room) == utility, "boiler in the utility room")
	check(int(rep.system("waste").source.level) == 0, "soil stack on the ground floor")
	var ids := []
	for b: Dictionary in rep.system("cold_water").branches:
		ids.append(b.id)
	check("boiler" in ids and utility in ids, "cold feed to the boiler and the bare utility room: %s" % str(ids))
	var sinks := 0
	for b: Dictionary in rep.system("hot_water").branches:
		if b.what == "Sink":
			sinks += 1
	check(sinks == 1, "one sink per kitchen, not one per unit: %d" % sinks)
	var total := 0.0
	for s: String in rep.systems:
		total += float(rep.systems[s].cost)
	check(absf(total - rep.total_cost) < 0.05, "total is the sum of the systems")
	check(rep.routes("power").size() > 0 and rep.routes("power")[0][0] is Vector3, "routes as polylines")
	check(not rep.is_stale(m), "fresh report")
	m.apply(C.place_room("store_room", 1, C.rect(0, 0, 1, 1)))
	check(rep.is_stale(m), "stale once the building changes")
	print(rep.summary)
	for n in rep.notes:
		print("  ", n)


func _same_every_time() -> void:
	var m := Samples.house()
	var want := ServicesConsultant.route(m).digest()
	for i in 3:
		check(ServicesConsultant.route(m).digest() == want, "run %d identical" % i)
	var copy := BuildingModel.from_data(m.to_data())
	check(ServicesConsultant.route(copy).digest() == want, "a saved and loaded copy routes the same")
	var rep := ServicesConsultant.route(m)
	var wire := ServicesReport.from_dict(bytes_to_var(var_to_bytes(rep.to_dict())))
	check(wire.digest() == want, "report through the wire keeps its digest")
	var json := ServicesReport.from_dict(JSON.parse_string(JSON.stringify(rep.to_dict())))
	check(json.digest() == want and json.passed() == rep.passed(), "report through JSON keeps its digest")


## Two rooms with a load-bearing wall between them.
func _two_rooms(door: bool) -> BuildingModel:
	var m := BuildingModel.new()
	Samples.add(m, C.place_part("slab", 0, {"outline": C.rect(0, 0, 8, 4)}, "concrete"))
	var w := Samples.wall(m, 0, Vector2(4, 0), Vector2(4, 4), true)
	if door:
		Samples.add(m, C.place_opening("door_internal", w, 2.0))
	Samples.add(m, C.place_room("utility", 0, C.rect(0, 0, 4, 4)))
	Samples.add(m, C.place_room("bedroom", 0, C.rect(4, 0, 4, 4)))
	return m


func _doors_save_holes() -> void:
	var solid := ServicesConsultant.route(_two_rooms(false))
	var holes: Dictionary = solid.system("power").holes
	check(int(holes.get("structural_wall", 0)) == 1, "no door: one core-drilled hole: %s" % str(holes))
	var open := ServicesConsultant.route(_two_rooms(true))
	holes = open.system("power").holes
	check(int(holes.get("structural_wall", 0)) == 0, "a door: the cable goes through it: %s" % str(holes))
	check(float(open.system("power").cost) < float(solid.system("power").cost), "cheaper through the door")


func _sealed_room() -> void:
	var m := BuildingModel.new()
	Samples.add(m, C.place_part("slab", 0, {"outline": C.rect(0, 0, 12, 4)}, "concrete"))
	Samples.add(m, C.place_room("utility", 0, C.rect(0, 0, 4, 4)))
	Samples.add(m, C.place_room("office", 0, C.rect(6, 0, 4, 4), "Glass box"))
	var box := [Vector2(6, 0), Vector2(10, 0), Vector2(10, 4), Vector2(6, 4)]
	for k in 4:
		Samples.add(m, C.place_part("curtain_wall", 0, {"a": [box[k].x, 0, box[k].y], "b": [box[(k + 1) % 4].x, 0, box[(k + 1) % 4].y]}, "glass"))
	var rep := ServicesConsultant.route(m)
	var office := Samples.room_of_type(m, "office")
	check(not rep.passed() and rep.room(office).powered == false, "a room sealed by curtain walls gets no power")
	check(rep.failures().keys() == [office], "only that room fails: %s" % str(rep.failures()))
	check(rep.summary.contains("Glass box"), "the summary names it: %s" % rep.summary)
	var said := false
	for n in rep.notes:
		said = said or (n.contains("Glass box") and n.contains("walled off"))
	check(said, "a note says why")


func _waste_never_uphill() -> void:
	var m := Samples.house()
	for b: Dictionary in ServicesConsultant.route(m).system("waste").branches:
		var y := -INF
		var ok := true
		for p: Array in b.points:  # from the network out to the fixture
			ok = ok and float(p[1]) >= y - 0.001
			y = float(p[1])
		check(ok, "waste branch to %s falls all the way" % b.id)
	# A stack upstairs cannot drain the kitchen.
	var rep := ServicesConsultant.route(m, {"waste": {"level": 1, "at": [3.0, 7.0]}})
	var kitchen := Samples.room_of_type(m, "kitchen")
	check("waste" in (rep.room(kitchen).missing as Array), "kitchen below the stack is not drained")
	check(str(rep.system("waste").source.how) == "placed", "placed stack used")
	var said := false
	for n in rep.notes:
		said = said or n.contains("uphill")
	check(said, "a note explains waste cannot run uphill")


func _placed_sources() -> void:
	var m := Samples.house()
	var rep := ServicesConsultant.route(m, {"power": {"level": 0, "at": [1.0, 0.5]}})
	var src: Dictionary = rep.system("power").source
	check(src.how == "placed" and src.room == Samples.room_of_type(m, "hallway"), "consumer unit where the players put it")
	check(absf(float(src.at[0]) - 1.0) <= 0.5 and absf(float(src.at[2]) - 0.5) <= 0.5, "at the placed point: %s" % str(src.at))
	check(rep.passed(), "still passes")


func _long_wc_branch() -> void:
	var m := BuildingModel.new()
	Samples.add(m, C.add_level(3.0, "First floor"))
	for lv in 2:
		Samples.add(m, C.place_part("slab", lv, {"outline": C.rect(0, 0, 20, 3)}, "concrete"))
		Samples.add(m, C.place_room("corridor", lv, C.rect(0, 0, 18, 3)))
	Samples.add(m, C.place_room("store_room", 0, C.rect(18, 0, 2, 3)))
	Samples.add(m, C.place_room("wc_room", 1, C.rect(18, 0, 2, 3)))
	Samples.add(m, C.place_part("wc", 1, {"at": [19.5, 0, 1.5]}))
	var rep := ServicesConsultant.route(m, {"waste": {"level": 0, "at": [0.5, 1.5]}})
	check(rep.passed(), "far WC is still drained: %s" % rep.summary)
	check(rep.warnings.size() == 1 and rep.warnings[0].contains("WC"), "but the long branch is flagged: %s" % str(rep.warnings))
	var near := ServicesConsultant.route(m)
	check(near.warnings.is_empty(), "auto stack sits under the WC: %s" % str(near.warnings))


func _lift_shaft() -> void:
	var m := BuildingModel.new()
	Samples.add(m, C.place_part("slab", 0, {"outline": C.rect(0, 0, 9, 3)}, "concrete"))
	Samples.add(m, C.place_room("plant_room", 0, C.rect(0, 0, 3, 3)))
	Samples.add(m, C.place_room("lift_shaft", 0, C.rect(3, 0, 3, 3)))
	Samples.add(m, C.place_room("office", 0, C.rect(6, 0, 3, 3)))
	var rep := ServicesConsultant.route(m)
	var office := Samples.room_of_type(m, "office")
	check(rep.room(office).powered == false, "no route through a lift shaft")
