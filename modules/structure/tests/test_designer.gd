extends ModuleTest
## The engineer designs the structure: it fixes what fails by adding and upsizing only,
## the fix is one edit that applies (and undoes) on the real building, the same building
## always gets the same design, and the bus sends the edit and reports back.
##   tools/run_tests.sh structure

const Samples := preload("res://modules/structure/tests/samples.gd")


func run_tests() -> void:
	_ranking()
	_already_fine()
	_long_spans()
	_floating_beam()
	_bus()
	_school_hall()
	_completes()


## A two-storey 14 x 10 m office on perimeter walls only: far too far for its slabs.
static func open_plan() -> BuildingModel:
	var C := BuildingCommands
	var m := BuildingModel.new("open", "Open plan", BuildingCatalog.default_catalog())
	m.apply(C.add_level())
	var corners := [[0, 0, 0], [14, 0, 0], [14, 0, 10], [0, 0, 10]]
	for i in 4:
		var a: Array = corners[i]
		var b: Array = corners[(i + 1) % 4]
		m.apply(C.place_part("strip_footing", 0, {"a": a, "b": b}, "concrete", "strip_600x225"))
		for lv in 2:
			m.apply(C.place_part("wall_loadbearing", lv, {"a": a, "b": b}, "masonry", "wall_block_140"))
	m.apply(C.place_part("slab", 0, {"outline": C.rect(0, 0, 14, 10), "y": 0.0}, "concrete", "slab_150"))
	m.apply(C.place_part("slab", 1, {"outline": C.rect(0, 0, 14, 10), "y": 0.0}, "concrete", "slab_150"))
	m.apply(C.place_part("roof_flat", 1, {"outline": C.rect(0, 0, 14, 10), "y": 3.0}, "timber"))
	m.apply(C.place_room("office", 1, C.rect(0, 0, 14, 10), "Office"))
	return m


func _ranking() -> void:
	var cat := BuildingCatalog.default_catalog()
	check(StructureDesigner.next_section(cat, "wall_loadbearing", "masonry", "wall_block_140") == "wall_brick_215", "blockwork goes up to solid brick")
	check(StructureDesigner.next_section(cat, "wall_loadbearing", "masonry", "wall_brick_215") == "wall_cavity_300", "then to cavity")
	check(StructureDesigner.next_section(cat, "wall_loadbearing", "masonry", "wall_cavity_300") == "", "cavity is the top")
	check(StructureDesigner.next_section(cat, "beam", "steel", "ub_203x133x25") == "ub_254x146x31", "next steel beam")
	check(StructureDesigner.next_section(cat, "pad_footing", "concrete", "pad_1000") == "pad_1500", "next pad")
	check(StructureDesigner.next_section(cat, "roof_pitched", "timber", "") == "", "no sections, nothing to upsize")


func _already_fine() -> void:
	var m: BuildingModel = Samples.model_house().model
	var plan := StructureDesigner.design(m)
	check(plan.passed and (plan.op as Dictionary).is_empty(), "a sound house is left alone")
	check(str(plan.notes[0]).begins_with("Nothing to fix"), "and says so: %s" % plan.notes[0])


func _long_spans() -> void:
	var m := open_plan()
	var start := m.checksum()
	var before_ids := m.parts.keys()
	var plan := StructureDesigner.design(m)
	check(not plan.before.passed(), "the open plan fails as drawn")
	check(plan.passed, "the engineer makes it pass: %s" % "\n".join(plan.notes))
	check(int(plan.added) > 0 and int(plan.upsized) > 0, "by adding and upsizing (%d, %d)" % [plan.added, plan.upsized])
	check(m.checksum() == start, "designing changes nothing until the edit is sent")
	var only_safe := true
	for op: Dictionary in plan.op.ops:
		if str(op.op) == "set":
			only_safe = only_safe and (op.fields as Dictionary).keys().all(func(k: String) -> bool: return k in ["section", "material", "kind"])
		elif str(op.op) != "add":
			only_safe = false
	check(only_safe, "only adds parts or strengthens them")
	check(str(plan.op.op) == "batch", "one edit, so one undo")
	var r := m.apply(plan.op)
	check(not r.is_empty(), "the edit applies to the real building")
	for id in before_ids:
		check(m.parts.has(id), "kept %s" % id)
	check(StructureBuilding.stress_test(m).passed(), "and the real building now passes")
	var parts_before: Dictionary = open_plan().parts
	m.apply(r.undo)
	check(m.parts == parts_before, "one undo takes it all back")
	var again := StructureDesigner.design(open_plan())
	check(again.op == plan.op, "the same building always gets the same design")
	var beams := 0
	for op: Dictionary in plan.op.ops:
		if str(op.op) == "add" and str(op.entry.kind) == "beam":
			beams += 1
	check(beams >= 1, "long floors get a beam across: %d" % beams)


func _floating_beam() -> void:
	var C := BuildingCommands
	var m: BuildingModel = Samples.model_house().model
	m.apply(C.place_part("beam", 0, {"a": [10, 3, 2], "b": [14, 3, 2]}, "steel", "ub_203x133x25"))
	var plan := StructureDesigner.design(m)
	check(plan.passed, "a beam in mid air gets propped: %s" % "\n".join(plan.notes))
	var cols := 0
	var pads := 0
	for op: Dictionary in plan.op.ops:
		if str(op.op) == "add":
			cols += 1 if str(op.entry.kind) == "column" else 0
			pads += 1 if str(op.entry.kind) == "pad_footing" else 0
	check(cols == 2 and pads == 2, "a column and a pad under each end (%d, %d)" % [cols, pads])
	check(plan.notes.size() == 1 and str(plan.notes[0]).contains("2 columns and 2 pad footings"), "and says what it added in one line: %s" % plan.notes[0])


func _bus() -> void:
	var bus := StructureBus.new()
	var model := open_plan()
	var sent: Array = []
	var said: Array = []
	bus.set_model_provider(func() -> BuildingModel: return model)
	bus.set_edit_handler(func(op: Dictionary, _group: String) -> void:
		sent.append(op)
		model.apply(op))
	bus.design_done.connect(func(notes: PackedStringArray) -> void: said.append(notes))
	var plan := bus.design_structure()
	check(sent.size() == 1 and sent[0] == plan.op, "the bus sends the plan as one edit")
	check(said.size() == 1 and (said[0] as PackedStringArray) == plan.notes, "and reports what it did")
	check(StructureBuilding.stress_test(model).passed(), "the shared building passes")
	bus.design_structure()
	check(sent.size() == 1 and str(bus.last_plan().notes[0]).begins_with("Nothing to fix"), "pressing again changes nothing")
	bus.set_model_provider(func() -> BuildingModel: return BuildingModel.new())
	bus.design_structure()
	check(str(said[-1][0]).begins_with("Nothing to design"), "an empty building: nothing to design")
	bus.free()


## A single-storey hall: long masonry walls full of windows under a heavy concrete roof,
## drawn with no footings. Before, the engineer gave up on the walls and listed advice;
## now it finishes the job.
func _school_hall() -> void:
	var C := BuildingCommands
	var m := BuildingModel.new("hall", "Hall", BuildingCatalog.default_catalog())
	var corners := [[0, 0, 0], [30, 0, 0], [30, 0, 18], [0, 0, 18]]
	var walls: Array = []
	for i in 4:
		var r := m.apply(C.place_part("wall_loadbearing", 0, {"a": corners[i], "b": corners[(i + 1) % 4]}, "masonry", "wall_cavity_300"))
		walls.append(str(r.do.entry.id))
	for t in [3.0, 7.0, 11.0, 15.0, 19.0, 23.0, 27.0]:
		m.apply(C.place_opening("window_large", walls[0], t))
	m.apply(C.place_opening("door_double", walls[2], 15.0))
	m.apply(C.place_part("roof_flat", 0, {"outline": C.rect(0, 0, 30, 18), "y": 3.0}, "concrete"))
	var plan := StructureDesigner.design(m)
	check(not plan.before.passed() and plan.passed, "the engineer makes the hall pass: %s" % "\n".join(plan.notes))
	check(plan.notes.size() == 1, "and sums it up in one line: %s" % plan.notes[0])
	check(StructureDesigner.describe(m, walls[0]).contains("ground floor") and StructureDesigner.describe(m, walls[0]).contains("30.0 m long"),
			"parts are described so they can be found: %s" % StructureDesigner.describe(m, walls[0]))


## Walls only: Design structure delivers the rest of the structure: footings (a raft on soft
## ground), a ground slab, the upper floor and a roof.
func _completes() -> void:
	for soil: String in ["clay", "made_ground"]:
		var C := BuildingCommands
		var m := BuildingModel.new("box", "Box", BuildingCatalog.default_catalog())
		m.apply({"op": "set_meta", "fields": {"soil": soil}})
		m.apply(C.add_level(3.0, "First floor"))
		var corners := [[0, 0, 0], [10, 0, 0], [10, 0, 8], [0, 0, 8]]
		for lv in 2:
			for i in 4:
				m.apply(C.place_part("wall_loadbearing", lv, {"a": corners[i], "b": corners[(i + 1) % 4]}, "masonry", "wall_block_140"))
		var plan := StructureDesigner.design(m, [], {}, true)
		var kinds := {}
		for op: Dictionary in plan.op.ops:
			if str(op.op) == "add":
				kinds[str(op.entry.kind)] = int(kinds.get(str(op.entry.kind), 0)) + 1
		if soil == "clay":
			check(int(kinds.get("strip_footing", 0)) >= 4 and not kinds.has("raft"), "strip footings under the walls on firm ground: %s" % [kinds])
		else:
			check(kinds.has("raft") and not kinds.has("strip_footing"), "a raft on made ground: %s" % [kinds])
		check(int(kinds.get("slab", 0)) == 2, "a ground slab and the first floor")
		check(kinds.has("roof_pitched") or kinds.has("roof_flat"), "and a roof")
		check(plan.passed, "a complete structure that passes: %s" % "\n".join(plan.notes))
		m.apply(plan.op)
		var again := StructureDesigner.design(m, [], {}, true)
		check((again.op as Dictionary).is_empty(), "pressing again adds nothing: %s" % again.notes[0])

