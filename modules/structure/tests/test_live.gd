extends ModuleTest
## The live assessment: the host re-tests the building in the background a moment after
## each edit (never on the frame that made it), drops a check the crew has already moved
## past, and with the live engineer on places its fixes one at a time until it passes.
##   tools/run_tests.sh structure

const Designer := preload("res://modules/structure/tests/test_designer.gd")
const Samples := preload("res://modules/structure/tests/samples.gd")


func run_tests() -> void:
	await _checks_in_background()
	await _engineer_builds()


## Steps the bus as the frame loop would, until done() or a time limit.
func _run(bus: StructureBus, done: Callable, seconds: float = 30.0) -> void:
	var start := Time.get_ticks_msec()
	while not done.call() and Time.get_ticks_msec() - start < seconds * 1000.0:
		bus._process(0.1)
		await get_tree().process_frame


func _checks_in_background() -> void:
	var bus := StructureBus.new()
	var h := Samples.model_house()
	var model: BuildingModel = h.model
	var reports: Array = []
	bus.report_changed.connect(func(r: StructureReport) -> void: reports.append(r))
	bus.set_edit_handler(func(op: Dictionary, _g: String) -> void: model.apply(op))
	bus.watch(model)
	bus._process(0.1)
	check(reports.is_empty() and not bus.is_checking(), "waits for the crew to pause")
	await _run(bus, func() -> bool: return not reports.is_empty())
	check(reports.size() == 1 and reports[0].passed(), "the sound house checks out live")
	check(reports[0].digest() == StructureBuilding.stress_test(model).digest(), "same as a stress test")

	# Take the spine wall away: the live check sees the floor fail.
	model.apply(BuildingCommands.delete([h.ids.spine_0, h.ids.strip_spine]))
	await _run(bus, func() -> bool: return reports.size() >= 2)
	check(reports.size() == 2 and not reports[1].passed(), "an edit that breaks it shows at once")

	# An edit while a check runs: the stale result is dropped, the fresh one lands.
	model.apply(BuildingCommands.place_part("beam", 1, {"a": [4, 0, 0], "b": [4, 0, 6]}, "steel"))
	await _run(bus, func() -> bool: return bus.is_checking())
	model.apply(BuildingCommands.place_part("column", 0, {"at": [4, 0, 3]}, "steel"))
	await _run(bus, func() -> bool: return reports.size() >= 3 and not bus.is_checking())
	check(reports.size() == 3, "one report for the two quick edits: %d" % (reports.size() - 2))
	check(reports[-1].digest() == StructureBuilding.stress_test(model).digest(), "and it is for the latest building")
	check(bus.pending_placements() == 0, "the engineer stays out of it while switched off")
	bus.watch(null)
	bus.free()


func _engineer_builds() -> void:
	var bus := StructureBus.new()
	var model := Designer.open_plan()
	var groups: Array = []
	bus.set_edit_handler(func(op: Dictionary, group: String) -> void:
		groups.append(group)
		model.apply(op))
	var engineer_on: Array = []
	bus.live_engineer_changed.connect(func(on: bool) -> void: engineer_on.append(on))
	bus.set_live_engineer(true)
	check(engineer_on == [true] and bus.live_engineer, "the live engineer switches on")
	var reports: Array = []
	bus.report_changed.connect(func(r: StructureReport) -> void: reports.append(r))
	var seen_left: Array = []
	bus.engineer_placed.connect(func(left: int) -> void: seen_left.append(left))
	bus.watch(model)
	await _run(bus, func() -> bool: return not reports.is_empty() and reports[-1].passed(), 60.0)
	check(not reports[0].passed(), "the open plan fails as drawn")
	check(groups.size() > 3, "the engineer places parts one at a time: %d" % groups.size())
	check(groups.all(func(g: String) -> bool: return g == StructureBus.ENGINEER_GROUP), "as one undo group")
	check(seen_left.has(0) and seen_left[0] > 0, "counting down what is left")
	check(not reports.is_empty() and reports[-1].passed(), "until the live check passes")
	check(StructureBuilding.stress_test(model).passed(), "and the building really does")
	var n := groups.size()
	await _run(bus, func() -> bool: return false, 1.0)
	check(groups.size() == n, "then it stops")
	bus.set_live_engineer(false)
	check(not bus.live_engineer, "and switches off")
	bus.watch(null)
	bus.free()
