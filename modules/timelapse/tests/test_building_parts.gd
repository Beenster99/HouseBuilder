extends ModuleTest
## The building model as timelapse parts: kinds, boxes, what rests on what, and a schedule.
##   tools/run_tests.sh timelapse

const C := preload("res://modules/building/api/building_commands.gd")


func run_tests() -> void:
	var m := _house()
	var parts := BuildingParts.from_model(m)
	var by := {}
	for p: Dictionary in parts:
		by[p.id] = p
	check(parts.size() == 17, "16 parts and a stair core come through: %d" % parts.size())
	var kinds := {}
	for p: Dictionary in parts:
		kinds[p.kind] = true
	for k in ["foundation", "wall", "door", "window", "column", "beam", "slab", "roof", "fitout", "stairs"]:
		check(kinds.has(k), "kind %s present" % k)
	check(by.p9.supported_by.has("p2"), "a door hangs on its wall: %s" % str(by.p9.supported_by))
	check(by.p2.supported_by.has("p1"), "a wall rests on its footing: %s" % str(by.p2.supported_by))
	check(not by.p13.supported_by.has("p15"), "a beam is not carried by the slab it holds up")
	check(by.p13.supported_by.has("p12"), "the beam rests on the column it's connected to: %s" % str(by.p13.supported_by))
	var slab: Dictionary = {}
	for p: Dictionary in parts:
		if p.kind == "slab":
			slab = p
	check(not slab.is_empty() and slab.supported_by.size() >= 2, "the first floor rests on the walls and beam: %s" % str(slab.get("supported_by")))
	check(by.p1.supported_by.is_empty(), "footings rest on the ground")
	var total := 0.0
	for p: Dictionary in parts:
		total += float(p.cost)
	check(total > 1000.0, "costs come from the building's quantities: £%d" % total)

	var s := TimelapseSchedule.build(parts)
	check(s.tasks.size() == parts.size() + 3 and s.days > 10.0, "the house schedules: %.0f days" % s.days)
	var start_of := {}
	for t: Dictionary in s.tasks:
		start_of[t.id] = t
	check(start_of.p2.start >= start_of.p1.end - 0.0001, "walls go up after their footings")

	var bus := Modules.bus("timelapse") as TimelapseBus
	bus.start_from_model(m, "", false)
	check(bus.is_active() and bus.title == "Test house", "start_from_model schedules it under the building's name")
	bus.apply_net_snapshot({})


static func _house() -> BuildingModel:
	var m := BuildingModel.new("house1", "Test house")
	m.apply(C.add_level(2.7, "First floor"))
	for side: Array in [[[0, 0, 0], [8, 0, 0]], [[8, 0, 0], [8, 0, 6]], [[8, 0, 6], [0, 0, 6]], [[0, 0, 6], [0, 0, 0]]]:
		m.apply(C.place_part("strip_footing", 0, {"a": side[0], "b": side[1]}))
		m.apply(C.place_part("wall_loadbearing", 0, {"a": side[0], "b": side[1]}, "masonry"))
	m.apply(C.place_opening("door_external", "p2", 4.0))
	m.apply(C.place_opening("window_medium", "p4", 3.0))
	m.apply(C.place_opening("window_medium", "p6", 0.1 + 2.0 / 3.0))
	m.apply(C.place_part("column", 0, {"at": [4, 0, 3]}, "steel"))
	m.apply(C.place_part("beam", 0, {"a": [0, 3, 3], "b": [8, 3, 3]}, "steel", "ub_254x146x31"))
	m.apply(C.connect_parts("p12", "p13", "pinned"))
	m.apply(C.place_part("slab", 1, {"outline": C.rect(0, 0, 8, 6)}, "timber"))
	m.apply(C.place_part("roof_pitched", 1, {"outline": C.rect(0, 0, 8, 6), "y": 2.7, "pitch": 40.0}))
	m.apply(C.place_room("living_room", 0, C.rect(0, 0, 8, 6), "Lounge"))
	m.apply(C.place_room("stair_core", 0, C.rect(6, 4, 2, 2), "Stairs"))
	m.apply(C.place_part("bed_double", 1, {"at": [2, 0, 1.5], "rot": 90.0}))
	return m
