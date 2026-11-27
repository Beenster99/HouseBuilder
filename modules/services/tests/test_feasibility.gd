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
