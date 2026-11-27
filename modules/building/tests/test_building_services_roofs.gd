extends ModuleTest
## Catalog kinds other threads asked for: service runs (pipes and cables, priced by the
## metre, not structural) and hipped and mono-pitch roofs.
##   tools/run_tests.sh building

const C := preload("res://modules/building/api/building_commands.gd")


func run_tests() -> void:
	var cat := BuildingCatalog.from_data(BuildingCatalog.DATA_SCRIPT.DATA)
	check(cat.problems().is_empty(), "the catalog has no problems: %s" % [cat.problems()])
	var runs := {"cable_power": 14.0, "cable_lighting": 12.0, "pipe_cold": 30.0, "pipe_hot": 34.0, "pipe_heating": 32.0, "pipe_waste": 40.0}
	var m := BuildingModel.new("svc", "Services", cat)
	var all_ok := true
	for k: String in runs:
		var spec := cat.kind(k)
		if str(spec.family) != "service" or str(spec.shape) != "line" or bool(spec.structural):
			all_ok = false
		var r := m.apply(C.place_part(k, 0, {"a": [0.0, 0.5, 0.0], "b": [10.0, 0.5, 0.0]}))
		if r.is_empty():
			all_ok = false
			continue
		var q := BuildingQuantities.part(m, str(r.do.entry.id))
		if not is_equal_approx(float(q.cost), 10.0 * float(runs[k])):
			all_ok = false
	check(all_ok, "every service run is a non-structural line priced by the metre")
	for k: String in ["roof_hip", "roof_mono"]:
		var spec := cat.kind(k)
		check(str(spec.family) == "roof" and str(spec.shape) == "area" and float(spec.pitch) == 35.0, "%s is a pitched roof kind" % k)
		var r := m.apply(C.place_part(k, 0, {"outline": C.rect(0, 0, 6, 4), "y": 3.0, "pitch": 25.0}))
		check(not r.is_empty() and float(m.parts[str(r.do.entry.id)].get("pitch", 0.0)) == 25.0, "and keeps its own pitch")
	var copy := BuildingModel.from_data(m.to_data(), cat)
	check(copy != null and copy.to_data() == m.to_data(), "they save and load")
