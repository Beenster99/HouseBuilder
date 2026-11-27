extends ModuleTest
## BuildingModel: placing, moving, deleting and retagging parts and rooms, with every edit's
## undo putting the model back exactly, and refusals leaving it untouched.
##   tools/run_tests.sh building

const C := preload("res://modules/building/api/building_commands.gd")


func run_tests() -> void:
	_catalog()
	_place_and_undo()
	_openings()
	_move()
	_retag()
	_levels()
	_batch_all_or_nothing()
	_signals()
	_meta()
	_circulation()


func _catalog() -> void:
	var cat := BuildingCatalog.default_catalog()
	var problems := cat.problems()
	check(problems.is_empty(), "the catalog is sound: %s" % ", ".join(problems))
	for fam: String in ["foundation", "column", "beam", "brace", "truss", "slab", "roof", "wall", "opening", "fixture"]:
		check(not cat.kinds_in(fam).is_empty(), "the catalog has %s parts" % fam)
	var ub := cat.section("ub_305x165x40")
	check(is_equal_approx(float(ub.kg_m), 40.3) and float(ub.area) > 0.0, "steel sections carry their mass and area")
	var rc := cat.section("rc_300x300")
	check(is_equal_approx(float(rc.area), 0.09), "rectangular sections work out their area")
	check(cat.rate("beam", "steel", "ub_305x165x40").unit == "t", "steel is priced by the tonne")
	check(cat.rate("wall_loadbearing", "masonry", "wall_cavity_300").rate == 195.0, "a wall build-up has its own rate")
	for k: String in ["consumer_unit", "water_main", "boiler", "soil_stack"]:
		check(cat.family_of(k) == "fixture" and cat.shape_of(k) == "point" and cat.rate(k, cat.materials_for(k)[0]).unit == "each",
				"service source %s is an each-priced fixture" % k)
	check(not cat.room_types_in("domestic").is_empty() and cat.has_room_type("classroom"), "room types cover houses and schools")


func _place_and_undo() -> void:
	var m := BuildingModel.new()
	var empty := m.to_data()
	var r := m.apply(C.place_part("column", 0, {"at": Vector3(0, 0, 0)}, "steel"))
	check(not r.is_empty() and str(r.do.entry.id) == "p1", "a column gets the first id")
	var col: Dictionary = m.parts["p1"]
	check(str(col.section) == "uc_152x152x23" and col.rot == 0.0, "defaults filled in: the first steel section, no rotation")
	check(m.points_of("p1").size() == 2 and is_equal_approx(m.points_of("p1")[1].y, 3.0), "a column runs up its level's height")
	check(m.apply(r.undo).size() == 2 and m.parts.is_empty(), "undo removes it")
	var after := m.to_data()
	after.next = empty.next
	check(after == empty, "undo puts the model back")
	check(m.apply(r.do).size() == 2 and m.has("p1"), "the applied op replays with its id")

	# Refusals
	check(m.apply(C.place_part("column", 0, {"at": [0, 0, 0]}, "masonry")).is_empty(), "a column cannot be masonry")
	check(m.apply(C.place_part("beam", 0, {"a": [0, 3, 0], "b": [0, 3, 0.01]})).is_empty(), "a beam needs length")
	check(m.apply(C.place_part("beam", 5, {"a": [0, 3, 0], "b": [4, 3, 0]})).is_empty(), "no part on a level that is not there")
	check(m.apply(C.place_part("nonsense", 0, {"at": [0, 0, 0]})).is_empty(), "unknown kinds are refused")
	check(m.apply(C.place_part("beam", 0, {"a": [0, 3, 0], "b": [4, 3, 0]}, "steel", "rc_300x300")).is_empty(), "a section must suit the material")
	check(m.apply({"op": "add", "table": "parts", "entry": {"id": "p1", "kind": "column", "at": [1, 0, 1]}}).is_empty(), "ids are unique")
	check(m.apply(C.place_room("dungeon", 0, C.rect(0, 0, 3, 3))).is_empty(), "unknown room types are refused")
	check(m.apply(C.place_room("bedroom", 0, [[0, 0], [1, 1], [2, 2]])).is_empty(), "a room needs area")

	# Set and its undo
	var beam := m.apply(C.place_part("beam", 0, {"a": [0, 3, 0], "b": [5, 3, 0]}, "steel"))
	var bid := str(beam.do.entry.id)
	var before := m.to_data()
	var s := m.apply(C.set_fields(bid, {"section": "ub_406x178x60", "name": "Main beam"}))
	check(str(m.parts[bid].section) == "ub_406x178x60" and str(m.parts[bid].name) == "Main beam", "set changes fields")
	check(m.apply(C.set_fields(bid, {"section": "ub_406x178x60"})).is_empty(), "setting the same value is a no-op")
	m.apply(s.undo)
	check(m.to_data() == before, "set's undo restores the fields (and removes the added name)")

	# Connections go with their parts, and come back on undo
	var c := m.apply(C.connect_parts("p1", bid, "pinned"))
	check(not c.is_empty() and m.connections_of("p1").size() == 1, "two parts connected")
	check(m.apply(C.connect_parts(bid, "p1")).is_empty(), "one connection per pair")
	check(m.apply(C.connect_parts("p1", "p1")).is_empty(), "a part cannot connect to itself")
	var with_conn := m.to_data()
	var del := m.apply(C.delete(["p1"]))
	check(not m.has("p1") and m.connections.is_empty(), "deleting a part takes its connections")
	m.apply(del.undo)
	check(m.to_data() == with_conn, "undo brings the part and its connection back with their ids")

	# Rooms
	var room := m.apply(C.place_room("bedroom", 0, C.rect(0, 0, 3.5, 3), "Bed 1"))
	check(not room.is_empty() and str(room.do.entry.id).begins_with("r"), "a room is painted")
	check(is_equal_approx(BuildingModel.outline_area(m.rooms[room.do.entry.id].outline), 10.5), "its area is 10.5 m2")


func _openings() -> void:
	var m := BuildingModel.new()
	var w := m.apply(C.place_part("wall_loadbearing", 0, {"a": [0, 0, 0], "b": [4, 0, 0]}, "masonry"))
	var wid := str(w.do.entry.id)
	var d := m.apply(C.place_opening("door_internal", wid, 1.0))
	check(not d.is_empty() and m.openings_in(wid).size() == 1, "a door goes in a wall")
	check(m.level_of(str(d.do.entry.id)) == 0 and not (m.parts[d.do.entry.id] as Dictionary).has("level"), "an opening is on its wall's level")
	check(m.apply(C.place_opening("window_large", wid, 0.5)).is_empty(), "an opening must fit inside the wall's length")
	var beam := m.apply(C.place_part("beam", 0, {"a": [0, 3, 0], "b": [4, 3, 0]}))
	check(m.apply(C.place_opening("door_internal", str(beam.do.entry.id), 1.0)).is_empty(), "openings only go in walls")
	check(m.apply(C.set_fields(wid, {"b": [1.2, 0, 0]})).is_empty(), "a wall cannot shrink past its door")
	check(m.apply(C.set_fields(wid, {"height": 1.5})).is_empty(), "nor get lower than it")
	check(m.apply(C.set_level(0, {"height": 1.8})).is_empty(), "nor can its level")
	var q := BuildingQuantities.part(m, wid)
	check(is_equal_approx(q.area, 4.0 * 3.0 - 0.838 * 1.981), "the wall's area leaves out the door")
	var before := m.to_data()
	var del := m.apply(C.delete([wid]))
	check(m.parts.size() == 1, "deleting the wall takes its door")
	m.apply(del.undo)
	check(m.to_data() == before, "undo brings both back")
	check(not m.apply(C.delete([wid, str(d.do.entry.id)])).is_empty(), "deleting a wall and its door together works")


func _move() -> void:
	var m := BuildingModel.new()
	m.apply(C.place_part("wall_loadbearing", 0, {"a": [0, 0, 0], "b": [4, 0, 0]}, "masonry"))
	m.apply(C.place_opening("window_medium", "p1", 2.0))
	m.apply(C.place_room("living_room", 0, C.rect(0, 0, 4, 4)))
	m.apply(C.place_part("slab", 0, {"outline": C.rect(0, 0, 4, 4)}))
	var before := m.to_data()
	var r := m.apply(C.move(["p1", "p2", "r3", "p4"], Vector3(0.25, 0.5, 0.75)))
	check(not r.is_empty(), "a mixed selection moves")
	check(m.parts.p1.a == [0.25, 0.5, 0.75] and float(m.parts.p2.t) == 2.0, "the wall moves and its window stays put in it")
	check(m.rooms.r3.outline[0] == [0.25, 0.75] and float(m.parts.p4.y) == 0.5, "rooms move in plan, slabs in 3D")
	m.apply(r.undo)
	check(m.to_data() == before, "undo puts everything back exactly")
	var slide := m.apply(C.move(["p2"], Vector3(0.5, 0, 0)))
	check(not slide.is_empty() and float(m.parts.p2.t) == 2.5, "a window moved alone slides along its wall")
	check(m.apply(C.move(["p2"], Vector3(5, 0, 0))).is_empty(), "but not out of it")
	check(m.apply(C.move(["p1", "nope"], Vector3(1, 0, 0))).is_empty() and m.parts.p1.a == [0.0, 0.0, 0.0], "an unknown id refuses the whole move")
	check(m.apply(C.move(["p1"], Vector3.ZERO)).is_empty(), "moving by nothing is a no-op")


func _retag() -> void:
	var m := BuildingModel.new()
	m.apply(C.place_room("bedroom", 0, C.rect(0, 0, 3, 3)))
	var r := m.apply(C.retag("r1", "study"))
	check(str(m.rooms.r1.type) == "study" and str(r.do.type) == "study", "a room is retagged")
	m.apply(r.undo)
	check(str(m.rooms.r1.type) == "bedroom", "and back")
	m.apply(C.place_part("wall_loadbearing", 0, {"a": [0, 0, 0], "b": [4, 0, 0]}, "timber"))
	var w := m.apply(C.retag("p2", "wall_partition"))
	check(not w.is_empty() and str(m.parts.p2.material) == "timber" and str(m.parts.p2.section) == "wall_stud_100",
			"a wall turned partition keeps its material and takes a section that suits it")
	m.apply(C.place_opening("door_internal", "p2", 1.0))
	check(m.apply(C.retag("p2", "beam")).is_empty(), "a wall with a door cannot become a beam")
	check(m.apply(C.retag("p2", "column")).is_empty(), "nor change shape")


func _levels() -> void:
	var m := BuildingModel.new()
	m.apply(C.add_level(3.0, "First floor"))
	m.apply(C.place_part("column", 1, {"at": [0, 0, 0]}))
	m.apply(C.place_room("bedroom", 1, C.rect(0, 0, 3, 3)))
	check(is_equal_approx(m.level_elevation(1), 3.0) and is_equal_approx(m.points_of("p1")[0].y, 3.0), "level 1 sits on level 0")
	var before := m.to_data()
	var r := m.apply(C.add_level(2.5, "Basement", 0))
	check(int(m.parts.p1.level) == 2 and int(m.rooms.r2.level) == 2, "inserting a level shifts what is above")
	m.apply(r.undo)
	check(m.to_data() == before, "undo shifts it back")
	check(m.apply(C.remove_level(1)).is_empty(), "a level with parts on it cannot be removed")
	check(m.apply(C.remove_level(5)).is_empty(), "nor one that is not there")
	var s := m.apply(C.set_level(1, {"height": 4.0}))
	check(not s.is_empty() and is_equal_approx(m.part_height("p1"), 4.0), "a column follows its level's height")


func _batch_all_or_nothing() -> void:
	var m := BuildingModel.new()
	var before := m.to_data()
	var bad := C.batch([
		C.place_part("column", 0, {"at": [0, 0, 0]}),
		C.place_part("column", 0, {"at": [4, 0, 0]}),
		C.place_part("column", 9, {"at": [8, 0, 0]}),
	])
	check(m.apply(bad).is_empty() and m.to_data() == before, "a batch with one bad op changes nothing, ids included")
	var good := m.apply(C.batch([
		C.place_part("column", 0, {"at": [0, 0, 0]}),
		C.place_part("column", 0, {"at": [4, 0, 0]}),
		C.connect_parts("p1", "p2", "fixed"),
	]))
	check(not good.is_empty() and m.parts.size() == 2 and m.connections.size() == 1, "a good batch applies")
	m.apply(good.undo)
	var now := m.to_data()
	now.next = before.next
	check(now == before, "and undoes as one")


func _signals() -> void:
	var m := BuildingModel.new()
	var seen: Array = []
	m.entry_added.connect(func(id: String) -> void: seen.append("+" + id))
	m.entry_changed.connect(func(id: String) -> void: seen.append("~" + id))
	m.entry_removed.connect(func(id: String) -> void: seen.append("-" + id))
	var rev := m.revision
	m.apply(C.place_part("wall_loadbearing", 0, {"a": [0, 0, 0], "b": [4, 0, 0]}))
	m.apply(C.place_opening("door_internal", "p1", 1.0))
	m.apply(C.move(["p1"], Vector3(1, 0, 0)))
	m.apply(C.delete(["p1"]))
	check(seen == ["+p1", "+p2", "~p1", "-p1", "-p2"], "entry signals name each entry touched: %s" % str(seen))
	check(m.revision == rev + 4, "revision counts applied ops")
	m.apply(C.delete(["p1"]))
	check(m.revision == rev + 4, "a refused op does not")


func _meta() -> void:
	var m := BuildingModel.new()
	var r := m.apply(C.set_design_meta({"name": "Semi", "brief": "house_3bed"}))
	check(m.name == "Semi" and str(m.meta.brief) == "house_3bed", "metadata is set")
	m.apply(r.undo)
	check(m.name == "New building" and not m.meta.has("brief"), "and undone")
	check(m.apply({"op": "set_meta", "fields": {"bad": Vector3.ONE}}).is_empty(), "only plain data goes in metadata")


func _circulation() -> void:
	var m := BuildingModel.new()
	check(m.apply(C.place_stair(0, Vector3(0, 0, 0), Vector3(4, 0, 0))).is_empty(), "a stair needs a level above")
	m.apply(C.add_level(3.0))
	m.apply(C.add_level(3.0))
	var st := m.apply(C.place_stair(0, Vector3(1, 0, 1), Vector3(5, 2, 1), "concrete", 1.2))
	check(not st.is_empty(), "a stair goes up from the ground floor")
	var sid := str(st.do.entry.id)
	check(float(m.parts[sid].b[1]) == 0.0 and is_equal_approx(m.points_of(sid)[1].y, 3.0), "its head is set level with its foot, and it rises one level")
	check(m.apply(C.place_stair(0, Vector3(0, 0, 0), Vector3(0.5, 0, 0))).is_empty(), "a flight needs a run of a metre or more")
	var lift := m.apply(C.place_lift(0, Vector3(8, 0, 8), 2))
	var lid := str(lift.do.entry.id)
	check(not lift.is_empty() and is_equal_approx(m.part_height(lid), 9.0), "a lift runs from the ground floor to the top of level 2")
	check(m.apply(C.place_lift(1, Vector3(8, 0, 8), 1)).is_empty() and m.apply(C.place_lift(0, Vector3(8, 0, 8), 3)).is_empty(),
			"a lift must reach a level above, and one that exists")
	var v1 := m.voids_on(1)
	check(v1.size() == 2 and is_equal_approx(BuildingModel.outline_area(v1[0].outline), 4.8), "level 1's floor has holes for the stair (4 x 1.2) and the lift")
	check(m.voids_on(2).size() == 1 and m.voids_on(0).is_empty(), "level 2 only for the lift, none on the ground")
	var q := BuildingQuantities.part(m, lid)
	check(q.stops == 3 and q.cost == 45000.0 + 3 * 8000.0 and q.mass == 6000.0, "a lift is priced each plus per stop")
	check(BuildingQuantities.part(m, sid).cost == 9000.0, "a concrete stair costs a flight")
	var box := m.aabb_of(lid)
	check(is_equal_approx(box.size.x, 2.0) and is_equal_approx(box.size.y, 9.0), "a lift's box is its shaft, full height")
	var before := m.to_data()
	var ins := m.apply(C.add_level(3.0, "Mezzanine", 1))
	check(int(m.parts[lid].top_level) == 3, "a level inserted in its run makes the lift one stop longer")
	m.apply(ins.undo)
	check(m.to_data() == before, "and undoing that puts it back")
	check(m.apply(C.remove_level(2)).is_empty(), "the lift's top level cannot be removed")
	m.apply(C.set_fields(lid, {"top_level": 1}))
	check(m.apply(C.remove_level(1)).is_empty(), "nor one the lift or stair reaches")
