extends ModuleTest
## The model's indexes (openings per wall, connections per part, families, levels) and the
## costs BuildingQuantities keeps on the model stay right through every kind of edit, undo
## and load: each step is checked against a model loaded fresh from the same data.
##   tools/run_tests.sh building

const C := preload("res://modules/building/api/building_commands.gd")


func run_tests() -> void:
	var m := BuildingModel.new("idx", "Index test")
	m.apply(C.add_level(2.7, "First floor"))
	var walls: Array = []
	for side: Array in [[[0, 0, 0], [8, 0, 0]], [[8, 0, 0], [8, 0, 6]], [[8, 0, 6], [0, 0, 6]], [[0, 0, 6], [0, 0, 0]]]:
		walls.append(str(m.apply(C.place_part("wall_loadbearing", 0, {"a": side[0], "b": side[1]}, "masonry")).do.entry.id))
	var door := str(m.apply(C.place_opening("door_external", walls[0], 4.0)).do.entry.id)
	var col := str(m.apply(C.place_part("column", 0, {"at": [4, 0, 3]}, "steel")).do.entry.id)
	var beam := str(m.apply(C.place_part("beam", 0, {"a": [0, 3, 3], "b": [8, 3, 3]}, "steel", "ub_254x146x31")).do.entry.id)
	m.apply(C.place_room("living_room", 0, C.rect(0, 0, 8, 6), "Lounge"))
	var bed_room := str(m.apply(C.place_room("bedroom", 1, C.rect(0, 0, 4, 3), "Bed 1")).do.entry.id)
	var bed := str(m.apply(C.place_part("bed_double", 1, {"at": [2, 0, 1.5]})).do.entry.id)
	_same(m, "after building it")
	BuildingQuantities.totals(m)
	var steps: Array = [
		["a connection", C.connect_parts(col, beam, "pinned")],
		["a second door", C.place_opening("door_internal", walls[1], 3.0)],
		["moving the door", C.move([door], Vector3(-1.0, 0, 0))],
		["a taller first floor", C.set_level(1, {"height": 3.0})],
		["a level underneath", C.add_level(3.0, "Basement", 0)],
		["moving the bed out of its room", C.move([bed], Vector3(5.0, 0, 0))],
		["a second bed in the room", C.place_part("bed_single", 2, {"at": [1, 0, 1]})],
		["a wall's openings changing size", C.set_fields(door, {"w": 1.2})],
		["the column removed with its connection", C.delete([col])],
		["a wall removed with its door", C.delete([walls[0]])],
		["removing the basement", C.remove_level(0)],
		["retagging the bedroom", C.retag(bed_room, "study")],
	]
	var undos: Array = []
	for s: Array in steps:
		var r := m.apply(s[1])
		check(not r.is_empty(), "%s applies" % s[0])
		if not r.is_empty():
			undos.append(r.undo)
		_same(m, "after " + str(s[0]))
	for i in range(undos.size() - 1, -1, -1):
		m.apply(undos[i])
	_same(m, "after undoing everything")
	# A refused batch rolls back without leaving index entries behind.
	var bad := C.batch([C.place_opening("window_medium", walls[2], 2.0), C.place_part("column", 0, {"at": [1, 0, 1]}, "no_such_material")])
	check(m.apply(bad).is_empty(), "a batch with a bad op is refused")
	_same(m, "after a refused batch")
	check(m.openings_in(walls[2]).is_empty(), "and its opening is not indexed")
	var copy := BuildingModel.from_data(m.to_data())
	_same(copy, "a loaded copy")
	check(BuildingModel.sort_ids(["p10", "p2", "r1", "c3", "p1"]) == PackedStringArray(["c3", "p1", "p2", "p10", "r1"]), "ids sort by prefix then number")
	check(BuildingModel.sort_ids(["p2", "wall_a", "p10"]) == PackedStringArray(["p2", "p10", "wall_a"]), "and odd ids still sort")


## Every index and cached cost matches a fresh scan of a model loaded from the same data.
func _same(m: BuildingModel, when: String) -> void:
	var fresh := BuildingModel.from_data(m.to_data())
	var ok := true
	for pid: String in m.parts:
		if m.openings_in(pid) != _scan_openings(m, pid) or m.connections_of(pid) != _scan_conns(m, pid):
			ok = false
	for cid: String in m.connections:
		var c: Dictionary = m.connections[cid]
		if m.connection_between(str(c.b), str(c.a)) != cid:
			ok = false
	for fam: String in m.catalog.families:
		if m.parts_of_family(fam) != fresh.parts_of_family(fam):
			ok = false
	for lv in m.level_count():
		if m.parts_on(lv) != fresh.parts_on(lv) or m.rooms_on(lv) != fresh.rooms_on(lv):
			ok = false
	check(ok, "indexes match a scan %s" % when)
	var warm := BuildingQuantities.totals(m)
	var cold := BuildingQuantities.totals(fresh)
	check(warm == cold, "kept costs match a fresh costing %s (%s / %s)" % [when, "%.2f" % warm.cost, "%.2f" % cold.cost])
	var rooms_ok := true
	for rid: String in m.rooms:
		if BuildingQuantities.room(m, rid) != BuildingQuantities.room(fresh, rid):
			rooms_ok = false
	check(rooms_ok, "rooms match %s" % when)


func _scan_openings(m: BuildingModel, wall_id: String) -> PackedStringArray:
	var out: Array = []
	for pid: String in m.parts:
		if str(m.parts[pid].get("host", "")) == wall_id:
			out.append(pid)
	return BuildingModel.sort_ids(out)


func _scan_conns(m: BuildingModel, part_id: String) -> PackedStringArray:
	var out: Array = []
	for cid: String in m.connections:
		if str(m.connections[cid].a) == part_id or str(m.connections[cid].b) == part_id:
			out.append(cid)
	return BuildingModel.sort_ids(out)
