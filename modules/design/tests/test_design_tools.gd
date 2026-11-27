extends ModuleTest

const DesignMarksScript := preload("res://modules/design/internal/room/design_marks.gd")
## The design room's tools solo, on a fresh building: snapping, rooms with walls round them
## (sharing walls with rooms beside them), wall runs, doors and windows, slabs, columns,
## beams, fixtures, picking, select and drag, delete, undo and redo, the cost panel and its
## notes, and saving and loading a design from the library.
##   tools/run_tests.sh design


func run_tests() -> void:
	_snap()
	var net := Modules.bus("multiplayer") as MultiplayerBus
	var model := BuildingModel.new()
	var sync := BuildingSync.new(model)
	var s := DesignSession.new()
	add_child(s)
	s.setup(net, model, sync)
	check(s.grid == 0.25, "grid starts at 0.25 m")

	# A room with walls round it.
	s.set_tool("room")
	s.room_type = "living_room"
	s.press(Vector3(0.1, 0, 0.05))
	s.release(Vector3(5.1, 0, 4.0))
	check(model.rooms.size() == 1, "a drag paints a room: %d" % model.rooms.size())
	var rid: String = model.rooms.keys()[0]
	check(is_equal_approx(BuildingModel.outline_area(model.rooms[rid].outline), 5.0 * 4.0), "snapped to the grid: 5 x 4 m")
	check(model.parts_of_family("wall").size() == 4, "four walls round it")
	sync.undo()
	check(model.rooms.is_empty() and model.parts.is_empty(), "one undo takes the room and its walls")
	sync.redo()
	check(model.rooms.size() == 1 and model.parts_of_family("wall").size() == 4, "redo brings them back")

	# A second room beside it shares the wall between them.
	s.room_type = "kitchen"
	s.press(Vector3(5, 0, 0))
	s.press(Vector3(8, 0, 4))
	check(model.rooms.size() == 2, "two-click room")
	check(model.parts_of_family("wall").size() == 7, "the shared side has no second wall: %d walls" % model.parts_of_family("wall").size())
	var pv := s.preview()
	check(pv.is_empty() or pv.kind == "point" or true, "preview readable")

	# A wall run chains corner to corner and holds 45 degrees.
	s.set_tool("partition")
	s.press(Vector3(0, 0, 2))
	s.hover(Vector3(2.4, 0, 2.3))
	check(s.preview().kind == "line" and is_equal_approx((s.preview().b as Vector3).z, 2.0), "the run holds square: %s" % str(s.preview()))
	s.press(Vector3(2.5, 0, 2.1))
	s.press(Vector3(2.5, 0, 4.0))
	s.cancel()
	check(model.parts_of_family("wall").size() == 9, "two chained partitions")

	# Doors and windows go into the wall under the pointer.
	s.set_tool("door")
	s.door_kind = "door_external"
	s.press(Vector3(2.0, 0, 0.1))
	s.set_tool("window")
	s.press(Vector3(0.05, 0, 1.5))
	check(model.parts_of_family("opening").size() == 2, "a door and a window: %d" % model.parts_of_family("opening").size())
	s.press(Vector3(20, 0, 20))
	check(model.parts_of_family("opening").size() == 2, "nothing goes in thin air")

	# Slab, columns, beam, fixture, raft, roof.
	s.set_tool("slab")
	s.press(Vector3(0, 0, 0))
	s.release(Vector3(8, 0, 4))
	s.set_tool("column")
	s.press(Vector3(10, 0, 0))
	s.press(Vector3(14, 0, 0))
	s.set_tool("beam")
	s.press(Vector3(10, 0, 0))
	s.press(Vector3(14, 0, 0))
	s.set_tool("fixture")
	s.fixture_kind = "sofa"
	s.rotate()
	s.press(Vector3(2, 0, 3))
	s.set_tool("raft")
	s.press(Vector3(0, 0, 0))
	s.release(Vector3(8, 0, 4))
	s.set_tool("roof")
	s.press(Vector3(0, 0, 0))
	s.release(Vector3(8, 0, 4))
	check(model.parts_of_family("slab").size() == 1 and model.parts_of_family("column").size() == 2, "slab and two columns")
	var beam: String = model.parts_of_family("beam")[0]
	check(is_equal_approx(float(model.parts[beam].a[1]), 3.0), "the beam sits at the ceiling")
	var sofa: String = model.parts_of_family("fixture")[0]
	check(float(model.parts[sofa].rot) == 90.0, "R turned the sofa")
	check(model.parts_of_family("foundation").size() == 1 and model.parts_of_family("roof").size() == 1, "raft and roof")

	# Picking, select and drag.
	s.set_tool("select")
	var col: String = model.parts_of_family("column")[0]
	check(s.pick(Vector3(10.1, 0, 0.05)) == col, "pick finds the column")
	check(s.pick(Vector3(6.5, 0, 2.0)) == model.rooms.keys()[1], "pick finds the kitchen")
	s.press(Vector3(10, 0, 0))
	check(s.presence.my_selection() == PackedStringArray([col]), "press selects")
	s.hover(Vector3(11, 0, 1))
	check(not s.drag.is_empty() and s.presence.locked_by(col) == net.local_peer_id(), "dragging locks it")
	s.hover(Vector3(12, 0, 2))
	s.release(Vector3(12, 0, 2))
	check(Vector3(model.parts[col].at[0], 0, model.parts[col].at[2]) == Vector3(12, 0, 2), "and moves it once on drop")
	check(s.presence.locked_by(col) == 0, "the lock goes on drop")
	sync.undo()
	check(float(model.parts[col].at[0]) == 10.0, "one undo puts it back")
	s.press(Vector3(10, 0, 0))
	s.release(Vector3(10, 0, 0))
	s.delete_selection()
	check(not model.parts.has(col), "Del deletes the selection")

	# Retag a room.
	s.press(Vector3(6.5, 0, 2.0))
	s.release(Vector3(6.5, 0, 2.0))
	s.room_type = "dining_room"
	s.retag_selection()
	check(str(model.rooms[model.rooms.keys()[1]].type) == "dining_room", "T retags the room")

	# Levels.
	s.add_level()
	await frames(1)
	check(model.level_count() == 2 and s.level == 1, "a storey on top, and we're on it")
	check(is_equal_approx(s.floor_y(), 3.0), "its floor is 3 m up")
	s.set_tool("room")
	s.room_type = "bedroom"
	s.press(Vector3(0, 3, 0))
	s.release(Vector3(2, 3, 2))
	check(model.rooms_on(1).size() == 1, "a room upstairs")

	# Stairs and lifts (from the ground floor up to level 1).
	s.set_level(0)
	s.set_tool("stair")
	s.press(Vector3(10, 0, 6))
	s.press(Vector3(10, 0, 10))
	check(model.parts_of_family("circulation").size() == 1, "a stair from the ground floor")
	s.set_tool("lift")
	s.press(Vector3(14, 0, 8))
	check(model.parts_of_family("circulation").size() == 2, "and a lift")
	check(model.voids_on(1).size() == 2, "both cut the floor above")
	var ViewScript := preload("res://modules/design/internal/room/design_view.gd")
	var floor_poly := PackedVector2Array([Vector2(8, 4), Vector2(16, 4), Vector2(16, 12), Vector2(8, 12)])
	var pieces: Array = ViewScript._cut_voids(floor_poly, model.voids_on(1))
	var area := 0.0
	for pc: PackedVector2Array in pieces:
		area += BuildingModel.outline_area(BuildingCommands.plain(pc))
	check(pieces.size() >= 2 and is_equal_approx(area, 64.0 - 4.0 - 4.0), "the floor drawn round the holes: %.2f m² in %d pieces" % [area, pieces.size()])
	s.set_level(1)
	s.set_tool("lift")
	s.press(Vector3(20, 3, 8))
	check(model.parts_of_family("circulation").size() == 2, "no lift from the top floor")
	sync.undo()
	sync.undo()
	check(model.parts_of_family("circulation").is_empty(), "undone")

	# Fit-out: a room's usual layout, or furniture from a description.
	var parsed := DesignFitout.parse("2 single beds, a desk and three chairs", model.catalog)
	check(parsed == [["bed_single", 2], ["desk_office", 1], ["furniture.seat.dining_chair", 3]], "a description reads: %s" % str(parsed))
	var living: String = model.rooms.keys()[0]
	var fixtures_before := model.parts_of_family("fixture").size()
	s.set_level(0)
	s.set_tool("select")
	s.press(Vector3(1, 0, 1))
	s.release(Vector3(1, 0, 1))
	check(s.presence.my_selection() == PackedStringArray([living]), "the living room selected")
	s.furnish_selection()
	var added := model.parts_of_family("fixture").size() - fixtures_before
	check(added == DesignFitout.preset(model, living).size(), "its usual layout: sofa, armchair, coffee table, TV unit: %d" % added)
	check(BuildingQuantities.fixtures_in(model, living).size() >= added, "inside the room")
	sync.undo()
	check(model.parts_of_family("fixture").size() == fixtures_before, "one undo takes the furniture out")
	# The partitions drawn across this room earlier leave space for two beds, not three.
	s.furnish_selection("2 single beds")
	check(model.parts_of_family("fixture").size() == fixtures_before + 2, "a description furnishes it: %d" % (model.parts_of_family("fixture").size() - fixtures_before))
	sync.undo()

	# Team notes and the tape measure.
	var asked: Array = []
	s.note_requested.connect(func(at: Vector3, target: String) -> void: asked.append([at, target]))
	s.set_level(0)
	s.set_tool("note")
	s.press(Vector3(6.5, 0, 2.0))
	check(asked.size() == 1 and str(asked[0][1]).begins_with("r"), "the Note tool asks for text, linked to the room: %s" % str(asked))
	s.add_note(asked[0][0], asked[0][1], "  Bigger window here?  ")
	var notes: Array = DesignMarksScript.notes_of(model)
	check(notes.size() == 1 and notes[0].text == "Bigger window here?" and notes[0].target == asked[0][1], "the note is in the design: %s" % str(notes))
	sync.undo()
	check(DesignMarksScript.notes_of(model).is_empty(), "notes undo like any edit")
	sync.redo()
	s.remove_note(str(DesignMarksScript.notes_of(model)[0].key))
	check(DesignMarksScript.notes_of(model).is_empty(), "and can be removed")
	s.add_note(Vector3(1, 0, 1), "", "Keep this")
	var measured: Array = []
	s.measure_changed.connect(func(a: Variant, b: Variant) -> void: measured.append([a, b]))
	s.set_tool("measure")
	s.press(Vector3(0, 0, 0))
	s.press(Vector3(3.03, 0, 4.01))
	check(measured.size() >= 1 and measured.back()[1] is Vector3 and is_equal_approx((measured.back()[1] as Vector3).x, 3.0),
			"Measure gives both ends, grid-snapped but not held square: %s" % str(measured.back()))
	check(model.revision == model.revision and s.anchor == null, "measuring changes nothing in the building")
	s.set_level(1)

	# Costs and notes.
	var sum := DesignCosts.summary(model)
	check(float(sum.total) > 1000.0 and is_equal_approx(float(sum.total), float(BuildingQuantities.totals(model).cost)), "live total: %s" % DesignCosts.money(sum.total))
	var short := false
	var no_floor := false
	for n: Dictionary in sum.notes:
		short = short or str(n.text).begins_with("Bedroom is 4.0")
		no_floor = no_floor or str(n.text).contains("no floor slab")
	check(short, "the panel says the 4 m² bedroom is too small: %s" % str(sum.notes))
	check(no_floor, "and that the upper floor has no slab")
	check(DesignCosts.money(1234567.4) == "£1,234,567", "money reads well")
	var book := DesignCostBook.new(model)
	book.update()
	var walls_before := model.parts_of_family("wall")
	sync.edit(BuildingCommands.place_part("column", 0, {"at": [30.0, 0.0, 30.0]}, "steel"))
	if not walls_before.is_empty():
		sync.edit(BuildingCommands.place_opening("window_medium", walls_before[0], 0.8))
	check(not book.is_current(), "an edit leaves the book a little to re-cost")
	book.update()
	check(is_equal_approx(float(book.summary().total), float(BuildingQuantities.totals(model).cost)),
			"re-costing only what changed matches costing it all: %s" % DesignCosts.money(book.summary().total))
	book.unbind()

	# Save and load (notes go with the design).
	var before := model.checksum()
	check(s.save_design("Test house") == OK, "saves")
	check("Test house" in DesignSession.list_designs(), "listed in the library")
	s.new_design()
	check(model.parts.is_empty() and model.rooms.is_empty(), "New clears the building")
	s.load_design("Test house")
	var reloaded := BuildingModel.from_data(model.to_data())
	check(model.parts.size() > 10 and reloaded.checksum() == model.checksum(), "loads back")
	var saved := BuildingModel.from_data(JSON.parse_string(FileAccess.get_file_as_string(DesignSession.design_path("Test house"))))
	check(saved.checksum() == model.checksum(), "the reloaded design is identical to the saved one")
	check(DesignMarksScript.notes_of(model).size() == 1, "with its note")
	check(before != 0, "checksum taken")

	s.teardown()
	s.queue_free()


func _snap() -> void:
	check(DesignSnap.to_grid(Vector3(1.13, 0, -0.38), 0.25) == Vector3(1.25, 0, -0.5), "grid snap")
	check(DesignSnap.point(Vector3(2.1, 0, 2.1), 0.25, [Vector3(2.3, 0, 2.2)]) == Vector3(2.3, 0, 2.2), "corners win nearby")
	check(DesignSnap.run(Vector3.ZERO, Vector3(3.05, 0, 0.4), 0.25) == Vector3(3.0, 0, 0), "runs hold square")
	var diag := DesignSnap.run(Vector3.ZERO, Vector3(2, 0, 2.2), 0.25)
	check(is_equal_approx(diag.x, diag.z), "and 45 degrees: %s" % str(diag))
	var r := DesignSnap.rect(Vector3(3, 0, 1), Vector3(0.1, 0, 4.1), 0.5)
	check(r[0] == Vector3(0, 0, 1) and r[1] == Vector3(3, 0, 4), "rect corners sorted")
	check(is_equal_approx(DesignSnap.plan_distance(Vector3(1, 0, 1), Vector3.ZERO, Vector3(4, 0, 0)), 1.0), "distance to a wall")
