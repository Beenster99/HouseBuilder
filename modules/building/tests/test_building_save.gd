extends ModuleTest
## A design saved as plain data (and as a JSON file) loads back identically; shared undo
## gives each player their own steps; quantities price a small house.
##   tools/run_tests.sh building

const C := preload("res://modules/building/api/building_commands.gd")


func run_tests() -> void:
	var m := _house()
	_round_trip(m)
	_file(m)
	_history()
	_quantities(m)


## A small two-storey house: footings, walls with a door and windows, a slab, a beam on
## columns, a pitched roof, rooms and a bed.
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
	m.apply(C.place_room("bedroom", 1, C.rect(0, 0, 4, 3), "Bed 1"))
	m.apply(C.place_part("bed_double", 1, {"at": [2, 0, 1.5], "rot": 90.0}))
	return m


func _round_trip(m: BuildingModel) -> void:
	var data := m.to_data()
	check((data.parts as Array).size() == 16 and (data.rooms as Array).size() == 2 and (data.connections as Array).size() == 1,
			"the house has 16 parts, 2 rooms and a connection (%d, %d)" % [(data.parts as Array).size(), (data.rooms as Array).size()])
	var copy := BuildingModel.from_data(data)
	check(copy != null and copy.to_data() == data, "plain data loads back identically")
	var text := JSON.stringify(data, "", true, true)
	var parsed: Variant = JSON.parse_string(text)
	var again := BuildingModel.from_data(parsed)
	check(again != null and again.to_data() == data, "and so does its JSON (floats and ints survive)")
	check(again.checksum() == m.checksum(), "the checksums match")
	# A fresh place after loading gets a fresh id, the same on both copies.
	var a := m.apply(C.place_part("column", 0, {"at": [1, 0, 1]}))
	var b := again.apply(C.place_part("column", 0, {"at": [1, 0, 1]}))
	check(str(a.do.entry.id) == str(b.do.entry.id), "ids carry on from the same number after a load")
	m.apply(a.undo)
	check(BuildingModel.from_data({"format": 99}) == null, "data from a newer format is refused")
	var junk := data.duplicate(true)
	(junk.parts as Array).append({"id": "p999", "kind": "nonsense"})
	var j := BuildingModel.new()
	check(j.load_data(junk).dropped == 1 and j.parts.size() == 16, "a bad entry is dropped, the rest load")


func _file(m: BuildingModel) -> void:
	var path := "user://building_test.json"
	check(m.save_file(path) == OK, "the design saves to a file")
	var back := BuildingModel.load_file(path)
	check(back != null and back.to_data() == m.to_data(), "and reloads identically")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(BuildingModel.load_file("user://missing.json") == null, "a missing file loads nothing")


func _history() -> void:
	var m := BuildingModel.new()
	var h := BuildingHistory.new(m)
	var a := h.commit(C.place_part("column", 0, {"at": [0, 0, 0]}), "1")
	var b := h.commit(C.place_part("column", 0, {"at": [4, 0, 0]}), "2")
	check(not a.is_empty() and not b.is_empty() and m.parts.size() == 2, "two players place a column each")
	var u := h.undo("1")
	check(str(u.get("op", "")) == "remove" and not m.has("p1") and m.has("p2"), "player 1's undo takes back only their column")
	check(h.undo("1").is_empty(), "player 1 has nothing more to undo")
	h.redo("1")
	check(m.has("p1"), "redo brings it back with its id")
	h.commit(C.delete(["p1"]), "2")
	check(h.undo("1").is_empty(), "an edit someone else has since removed can no longer be undone")
	check(h.log.size() == 5 and int(h.log[-1].seq) == 5, "the log numbers every edit")
	# One drag, many moves, one undo
	var before := m.to_data()
	for i in 5:
		h.commit(C.move(["p2"], Vector3(0.25, 0, 0)), "2", "drag-1")
	check(is_equal_approx(float(m.parts.p2.at[0]), 5.25), "a drag moves the column five times")
	h.undo("2")
	check(m.to_data() == before, "and one undo takes the whole drag back")
	# Replaying the log on a second copy gives the same building.
	var replay := BuildingModel.new()
	for step: Dictionary in h.log:
		replay.apply(step.op)
	check(replay.checksum() == m.checksum(), "replaying the log gives the same building")


func _quantities(m: BuildingModel) -> void:
	var col := BuildingQuantities.part(m, "p12")
	check(col.unit == "t" and is_equal_approx(col.mass, 23.0 * 3.0) and is_equal_approx(col.cost, 0.069 * 3200.0),
			"a 3 m steel column is priced by weight")
	var footing := BuildingQuantities.part(m, "p1")
	check(is_equal_approx(footing.volume, 8.0 * 0.6 * 0.225) and is_equal_approx(footing.cost, footing.volume * 240.0),
			"a strip footing is priced by volume")
	var door := BuildingQuantities.part(m, "p9")
	check(door.unit == "each" and door.cost == 1400.0, "a door is priced each")
	var roof := BuildingQuantities.part(m, "p16")
	check(is_equal_approx(roof.area, 48.0 / cos(deg_to_rad(40.0))), "a pitched roof is priced on its slope")
	var bed := BuildingQuantities.room(m, "r18")
	check(bed.capacity == 2 and bed.fixtures.size() == 1 and not bed.short, "the double bed makes the bedroom sleep two")
	var t := BuildingQuantities.totals(m)
	check(t.cost > 20000.0 and t.cost < 200000.0 and is_equal_approx(t.cost, t.structure + t.fit_out),
			"the house costs a plausible amount: %.0f" % t.cost)
	check(is_equal_approx(t.floor_area, 60.0) and (t.by_family as Dictionary).has("wall"), "totals split by family and floor area")
	var box := m.aabb_of("p2")
	check(is_equal_approx(box.size.y, 3.0) and box.size.x > 7.9, "a wall's box is its length by its height")
