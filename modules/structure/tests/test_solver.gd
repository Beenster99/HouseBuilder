extends ModuleTest
## The load-path solver: textbook beams, unsupported members, foundations, sideways load,
## the three stress tests on a sensible house, and the failure notes.
##   tools/run_tests.sh structure

const Samples := preload("res://modules/structure/tests/samples.gd")


func run_tests() -> void:
	_unsupported_beam()
	_simple_beam()
	_point_load()
	_cantilever()
	_foundation()
	_sway_and_bracing()
	_quake_base_shear()
	_sensible_house()


func _plain() -> StructureScenario:
	return StructureScenario.make("plain", "Plain", {"dead": 1.0, "live": 1.0})


func _near(a: float, b: float, tol := 1e-6) -> bool:
	return absf(a - b) <= tol * maxf(1.0, absf(b))


## Two posts with a beam across their tops, 6 m apart, 3 m tall.
func _portal(section: String, live_kn_per_m: float) -> StructureGraph:
	var g := StructureGraph.new()
	g.add_anchor("a1", Vector3(0, 0, 0))
	g.add_anchor("a2", Vector3(6, 0, 0))
	g.add_node("t1", Vector3(0, 3, 0))
	g.add_node("t2", Vector3(6, 3, 0))
	g.add_member("c1", "a1", "t1", StructureGraph.COLUMN, "steel.uc_203x203x46")
	g.add_member("c2", "a2", "t2", StructureGraph.COLUMN, "steel.uc_203x203x46")
	g.add_member("b", "t1", "t2", StructureGraph.BEAM, section)
	g.add_member_load("b", "live", live_kn_per_m)
	return g


func _unsupported_beam() -> void:
	# A beam floating on its own, and one beside a standing house: no path to the ground.
	var lone := StructureGraph.new()
	lone.add_node("p", Vector3(0, 3, 0))
	lone.add_node("q", Vector3(5, 3, 0))
	lone.add_member("b", "p", "q", StructureGraph.BEAM, "steel.ub_457x191x67")
	var house := Samples.house()
	house.add_node("p", Vector3(20, 3, 0))
	house.add_node("q", Vector3(25, 3, 0))
	house.add_member("float", "p", "q", StructureGraph.BEAM, "steel.ub_457x191x67", 1.0, Vector3.ZERO, "Loose beam")
	for g: StructureGraph in [lone, house]:
		var id := "b" if g == lone else "float"
		var digests := {}
		for i in 10:
			var rep := StructureSolver.stress_test(g)
			digests[rep.digest()] = true
			check(not rep.passed(), "unsupported beam fails (run %d)" % i)
			for r in rep.results:
				check(r.members[id].mode == "unsupported" and r.utilisation(id) >= StructureResult.UNSUPPORTED,
						"%s: %s unsupported in %s" % [id, r.members[id].mode, r.scenario_id])
				check(r.failures[0] == id, "unsupported beam fails first in %s: %s" % [r.scenario_id, r.failures])
				check(r.status(id) == StructureResult.RED_STATUS, "unsupported beam is red")
				check("p" in r.unsupported_nodes and "q" in r.unsupported_nodes, "its nodes listed unsupported")
			check(rep.first_failure().id == id, "first failure is the beam")
		check(digests.size() == 1, "same result every run")
	var rep := StructureSolver.stress_test(house)
	check(rep.notes.size() == 1 and rep.notes[0].begins_with("Loose beam is not connected to any foundation"),
			"note names the loose beam: %s" % str(rep.notes))
	check(rep.summary.contains("Loose beam"), "summary names it: %s" % rep.summary)
	# The house beside it is unaffected.
	check(rep.result("normal_use").failures.size() == 1, "only the loose beam fails")


func _simple_beam() -> void:
	var g := _portal("steel.ub_305x165x40", 10.0)
	var r := StructureSolver.solve(g, _plain())
	var w := 10.0 + 0.4  # live plus the beam's own weight
	check(_near(r.members.b.moment, w * 36.0 / 8.0), "simply supported moment wL²/8: %f" % r.members.b.moment)
	check(_near(r.members.b.shear, w * 3.0), "end shear wL/2: %f" % r.members.b.shear)
	check(not r.members.b.cantilever, "not a cantilever")
	check(r.members.b.mode == "bending", "beam governed by bending")
	check(_near(r.members.c1.axial, w * 3.0 + 0.46 * 3.0), "column carries its half: %f" % r.members.c1.axial)
	check(_near(r.anchors.a1.load, w * 3.0 + 0.46 * 3.0), "foundation load: %f" % r.anchors.a1.load)
	check(_near(r.utilisation("b"), w * 36.0 / 8.0 / 210.0), "utilisation = moment / capacity")
	check(r.passed(), "passes")
	# Five times the load on a light beam: bends past capacity.
	var heavy := _portal("steel.ub_203x133x25", 50.0)
	var rh := StructureSolver.stress_test(heavy)
	check(not rh.passed() and rh.first_failure().id == "b", "overloaded beam fails")
	check(rh.notes[0].begins_with("Beam b spans 6.0 m and bends at"), "note says it spans: %s" % rh.notes[0])


func _point_load() -> void:
	# A beam split at midspan with a point load there: lever rule, PL/4.
	var g := _portal("steel.ub_305x165x40", 0.0)
	g.members.erase("b")
	g.add_node("m", Vector3(2, 3, 0))
	g.add_member("b1", "t1", "m", StructureGraph.BEAM, "steel.ub_305x165x40")
	g.add_member("b2", "m", "t2", StructureGraph.BEAM, "steel.ub_305x165x40")
	g.add_node_load("m", "live", 30.0)
	var r := StructureSolver.solve(g, _plain())
	# 2 m from t1, 4 m from t2: t1 takes 2/3 of the load, and each support half the beam's
	# own weight (0.4 kN/m over 6 m). The moment under the load is P a b / L = 40 plus the
	# beam's weight: R1 a - w a² / 2 = 41.6 exactly; the model gives within 1%.
	check(_near(r.members.b1.shear, 20.0 + 1.2), "near support reaction: %f" % r.members.b1.shear)
	check(_near(r.members.b2.shear, 10.0 + 1.2), "far support reaction: %f" % r.members.b2.shear)
	check(_near(r.members.b1.moment, 41.6, 0.01), "moment under the load: %f" % r.members.b1.moment)
	check(_near(r.members.b2.moment, 41.6, 0.02), "same moment from the other side: %f" % r.members.b2.moment)
	check(_near(r.anchors.a1.load + r.anchors.a2.load, 30.0 + 2.4 + 2 * 0.46 * 3.0), "all the load reaches the ground")
	check(not r.members.b1.cantilever, "a span, not a cantilever")


func _cantilever() -> void:
	var g := StructureGraph.new()
	g.add_anchor("a", Vector3.ZERO)
	g.add_node("t", Vector3(0, 3, 0))
	g.add_node("tip", Vector3(0, 3, 4))
	g.add_member("c", "a", "t", StructureGraph.COLUMN, "steel.uc_203x203x46")
	g.add_member("arm", "t", "tip", StructureGraph.BEAM, "steel.ub_203x133x25")
	g.add_node_load("tip", "live", 10.0)
	var r := StructureSolver.solve(g, _plain())
	check(r.members.arm.cantilever, "arm is a cantilever")
	check(_near(r.members.arm.moment, 10.0 * 4.0 + 0.25 * 16.0 / 2.0), "moment PL + wL²/2: %f" % r.members.arm.moment)
	check(_near(r.members.c.axial, 10.0 + 1.0 + 0.46 * 3.0), "column takes it all: %f" % r.members.c.axial)
	g.members.erase("arm")
	g.add_member("arm", "t", "tip", StructureGraph.BEAM, "timber.joist_47x200", 1.0, Vector3.ZERO, "Balcony joist")
	var rep := StructureSolver.stress_test(g)
	check(not rep.passed() and rep.first_failure().id == "arm", "timber cantilever fails")
	check(rep.notes[0].begins_with("Balcony joist cantilevers 4.0 m"), "note says cantilever: %s" % rep.notes[0])


func _foundation() -> void:
	var g := StructureGraph.new()
	g.add_anchor("pad", Vector3.ZERO, StructureSections.foundation_capacity("pad", 0.25, "made_ground"))
	g.add_node("t", Vector3(0, 3, 0))
	g.add_member("c", "pad", "t", StructureGraph.COLUMN, "steel.uc_203x203x46")
	g.add_node_load("t", "live", 30.0)
	check(_near(g.nodes.pad.bearing, 12.5), "0.25 m² pad on made ground: 12.5 kN")
	var rep := StructureSolver.stress_test(g)
	var r := rep.result("normal_use")
	check(r.failures.size() == 1 and r.failures[0] == "pad", "pad fails: %s" % r.failures)
	check(r.anchors.pad.mode == "bearing", "bearing mode")
	check(rep.notes[0].begins_with("Foundation pad carries"), "note: %s" % rep.notes[0])
	g.nodes.pad.bearing = StructureSections.foundation_capacity("pile", 1.0)
	check(StructureSolver.stress_test(g).passed(), "a pile holds it")


## Four slender timber posts with beams on top: they sway in a storm until braced.
func _sway_and_bracing() -> void:
	var g := StructureGraph.new()
	var corners := {"a": Vector3(0, 0, 0), "b": Vector3(4, 0, 0), "c": Vector3(4, 0, 4), "d": Vector3(0, 0, 4)}
	for k: String in corners:
		g.add_anchor("g" + k, corners[k])
		g.add_node("t" + k, corners[k] + Vector3(0, 3, 0))
		g.add_member("p" + k, "g" + k, "t" + k, StructureGraph.COLUMN, "timber.post_100x100")
	for pair in [["a", "b"], ["b", "c"], ["c", "d"], ["d", "a"]]:
		g.add_member("e" + pair[0] + pair[1], "t" + pair[0], "t" + pair[1], StructureGraph.BEAM, "timber.beam_75x225")
	g.auto_wind_areas(3.0)
	check(_near(g.nodes.ta.wind_area, 4.5), "wind area half the post height times the bay")
	var rep := StructureSolver.stress_test(g)
	check(rep.result("normal_use").passed(), "stands up in normal use")
	var storm := rep.result("storm")
	check(not storm.passed(), "unbraced posts fail in the storm")
	check(_near(storm.base_shear, 4 * 4.5 * 1.5), "all the wind reaches the ground: %f" % storm.base_shear)
	check(storm.members.pa.lateral and storm.members.pa.mode == "bending", "post fails in sideways bending")
	var note := ""
	for n in rep.notes:
		if n.contains("sways"):
			note = n
	check(note.contains("in the storm test from the") and note.contains("brace"), "note says sway and brace: %s" % str(rep.notes))
	for pair in [["ga", "tb"], ["gd", "tc"], ["ga", "td"], ["gb", "tc"]]:
		g.add_member("x" + pair[0] + pair[1], pair[0], pair[1], StructureGraph.BRACE, "timber.brace_100x50")
	var braced := StructureSolver.stress_test(g)
	check(braced.passed(), "braced frame passes: %s" % braced.summary)
	check(braced.result("storm").utilisation("pa") < storm.utilisation("pa") * 0.5, "bracing takes most of the wind")
	check(braced.result("storm").members.xgatb.axial > 0.0, "braces carry it")


func _quake_base_shear() -> void:
	var g := Samples.house()
	var weight := 0.0
	for id: String in g.members:
		var m: Dictionary = g.members[id]
		var sec := StructureSections.get_section(m.section)
		var own: float = sec.weight * (m.width if sec.get("per_width", false) else 1.0)
		weight += (own + float(m.loads.get("dead", 0.0)) + 0.3 * float(m.loads.get("live", 0.0))) * g.member_length(id)
	var r := StructureSolver.solve(g, StructureScenario.quake())
	check(_near(r.base_shear, 0.25 * weight, 1e-9), "quake base shear is a quarter of the weight: %f / %f" % [r.base_shear, weight])


func _sensible_house() -> void:
	var rep := StructureSolver.stress_test(Samples.house())
	check(rep.passed(), "sensible house passes: %s %s" % [rep.summary, str(rep.notes)])
	check(rep.results.size() == 3 and rep.results[0].scenario_id == "normal_use"
			and rep.results[1].scenario_id == "storm" and rep.results[2].scenario_id == "quake", "three tests in order")
	check(rep.notes.is_empty() and rep.summary.begins_with("Passes every test."), "summary: %s" % rep.summary)
	check(rep.envelope("f0") > 0.2 and rep.status("f0") == StructureResult.GREEN_STATUS, "floor beam loaded, green")
	check(rep.result("storm").utilisation("bx01") > rep.result("normal_use").utilisation("bx01"), "braces work harder in the storm")
	check(rep.result("storm").base_shear > 50.0, "storm pushes the house: %f" % rep.result("storm").base_shear)
	# Take away the middle front column on both floors: the beams above now span 8 m.
	var g := Samples.house()
	g.members.erase("c101")
	g.members.erase("c102")
	var weak := StructureSolver.stress_test(g)
	check(weak.envelope("e001") > rep.envelope("e001") * 5.0, "edge beam picks up the load")
