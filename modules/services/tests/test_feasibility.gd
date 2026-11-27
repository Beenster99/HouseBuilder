extends ModuleTest
## The consultant's feasibility verdict: structure, services, requirements and budget,
## in words, worst first.
##   tools/run_tests.sh services

const Samples := preload("res://modules/services/tests/samples.gd")
const C := preload("res://modules/building/api/building_commands.gd")


func run_tests() -> void:
	var empty := FeasibilityReview.review(BuildingModel.new())
	check(not empty.feasible and str(empty.summary).begins_with("Nothing"), "empty design: %s" % empty.summary)

	var m := Samples.house(false)
	for op: Dictionary in ServicesDesigner.propose(m).ops:
		m.apply(op)
	var r := FeasibilityReview.review(m)
	print(r.summary)
	for i: Dictionary in r.issues:
		print("  [%s] %s %s" % [i.area, i.text, i.tip])
	check(r.areas.services.ok, "designed house is serviced")
	var all_ok := true
	for a: String in r.areas:
		all_ok = all_ok and bool(r.areas[a].ok)
	check(bool(r.feasible) == all_ok, "feasible exactly when every area is ok")
	check(absf(float(r.cost.total) - float(r.cost.build) - float(r.cost.services)) < 0.05, "all-in cost is build plus services")
	check(float(r.cost.services) > 0.0, "services priced")
	check(FeasibilityReview.review(m).summary == r.summary, "same verdict every time")

	# A beam with nothing under it.
	var loose := BuildingModel.from_data(m.to_data())
	loose.apply(C.place_part("beam", 1, {"a": [20, 2.5, 0], "b": [26, 2.5, 0]}, "steel", "ub_203x133x25"))
	var lr := FeasibilityReview.review(loose)
	check(not lr.feasible and not lr.areas.structure.ok, "loose beam: not feasible: %s" % lr.summary)
	check(lr.issues.size() > 0 and lr.issues[0].area == "structure", "structure issue first")
	check(str(lr.summary).contains("structure"), "summary names the structure")

	# A room nothing can reach.
	var cut := BuildingModel.from_data(m.to_data())
	cut.apply(C.place_room("office", 0, C.rect(30, 0, 3, 3), "Annexe"))
	var cr := FeasibilityReview.review(cut)
	var said := false
	for i: Dictionary in cr.issues:
		said = said or (i.area == "services" and str(i.text).contains("Annexe"))
	check(not cr.feasible and said, "unreachable room named: %s" % str(cr.issues))

	# Against a contract brief with a tiny budget.
	var brief: Dictionary = ContractBrief.authored()[0].duplicate(true)
	brief["budget"] = 1000.0
	var br := FeasibilityReview.review(m, brief)
	check(br.has("assessment") and br.areas.has("requirements"), "the brief is checked")
	check(not br.feasible and not br.areas.budget.ok, "over budget: not feasible")
	var over := false
	for i: Dictionary in br.issues:
		over = over or (i.area == "budget" and str(i.text).contains("over"))
	check(over, "says how far over budget")
	print(br.summary)
	_fixes()
	await _live()


func _fixes() -> void:
	# The sample house's 8 m slabs fail; the engineer can prop them, the consultant can plumb it.
	var m := Samples.house(false)
	var r := FeasibilityReview.review(m)
	check(not r.feasible and r.fixes.has("structure") and r.fixes.has("services"), "both engineers have work: %s" % str(r.fixes.keys()))
	check(bool(r.fixes.structure.possible) and int(r.fixes.structure.added) + int(r.fixes.structure.upsized) > 0, "Design structure can make it stand")
	check(bool(r.fixes.services.possible), "Design services can serve it")
	check(bool(r.fixable) and str(r.summary).contains("would make it work"), "the verdict says the fixes would work: %s" % r.summary)
	check(float(r.cost.after_fixes) > float(r.cost.total), "fixes cost something")
	var tipped := false
	for i: Dictionary in r.issues:
		tipped = tipped or (i.area == "structure" and str(i.tip).begins_with("Design structure fixes"))
	check(tipped, "structure issues point at Design structure")
	# Applying both for real gives a feasible design at about the forecast cost.
	var sp := StructureDesigner.design(m)
	m.apply(sp.op)
	for op: Dictionary in ServicesDesigner.propose(m).ops:
		m.apply(op)
	var done := FeasibilityReview.review(m)
	check(done.feasible, "after both fixes it is feasible: %s" % done.summary)
	check(absf(float(done.cost.total) - float(r.cost.after_fixes)) < 1.0, "forecast cost matches: %s vs %s" % [done.cost.total, r.cost.after_fixes])


func _live() -> void:
	var bus := ServicesBus.new()
	add_child(bus)
	var m := Samples.house(false)
	bus.set_model_provider(func() -> BuildingModel: return m)
	bus.live_delay = 0.05
	bus.watch(m)
	var got: Array = []
	bus.review_done.connect(func(r: Dictionary) -> void: got.append(r))
	m.apply(C.place_room("store_room", 0, C.rect(0, 0, 1, 1)))
	m.apply(C.place_room("store_room", 0, C.rect(0, 7, 1, 1)))
	check(got.is_empty(), "waits for the edits to stop")
	for k in 100:
		if not got.is_empty():
			break
		await get_tree().create_timer(0.05).timeout
	check(got.size() == 1 and bus.last_review() == got[0], "one live review after a burst of edits: %d" % got.size())
	var panel: Control = bus.make_feasibility_panel()
	add_child(panel)
	check(panel.get_child_count() == 3 and not (panel.get_child(0) as Label).text.is_empty(), "Feasibility window shows the verdict")
	panel.queue_free()
	bus.watch(null)
	m.apply(C.place_room("store_room", 1, C.rect(0, 0, 1, 1)))
	await get_tree().create_timer(0.2).timeout
	check(got.size() == 1, "stops when no longer watching")
	bus.queue_free()
