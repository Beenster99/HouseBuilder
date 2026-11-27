extends ModuleTest
## The harder stress tests contract events use: heavy snow, ten years on (materials lose
## strength), heavy use, and any test made harder by a factor (storm*1.3).
##   tools/run_tests.sh structure

const Samples := preload("res://modules/structure/tests/samples.gd")


func run_tests() -> void:
	_heavy_snow()
	_ten_years()
	_heavy_use()
	_scaled()
	_by_id()
	_house()


## A 5 m timber roof beam on two posts carrying snow and a little roof weight.
func _roof(section: String, snow_kn_per_m: float) -> StructureGraph:
	var g := StructureGraph.new()
	g.add_anchor("a1", Vector3(0, 0, 0))
	g.add_anchor("a2", Vector3(5, 0, 0))
	g.add_node("t1", Vector3(0, 3, 0))
	g.add_node("t2", Vector3(5, 3, 0))
	g.add_member("c1", "a1", "t1", StructureGraph.COLUMN, "steel.uc_203x203x46")
	g.add_member("c2", "a2", "t2", StructureGraph.COLUMN, "steel.uc_203x203x46")
	g.add_member("b", "t1", "t2", StructureGraph.BEAM, section)
	g.add_member_load("b", "dead", 0.5)
	g.add_member_load("b", "snow", snow_kn_per_m)
	g.add_member_load("b", "live", 0.5)
	return g


func _u(g: StructureGraph, sc: StructureScenario, id: String) -> float:
	return StructureSolver.stress_test(g, [sc] as Array[StructureScenario]).envelope(id)


func _heavy_snow() -> void:
	var g := _roof("timber.glulam_115x360", 6.0)
	var normal := _u(g, StructureScenario.normal_use(), "b")
	var snow := _u(g, StructureScenario.heavy_snow(), "b")
	check(snow > normal * 1.3, "heavy snow loads the roof beam harder (%.2f vs %.2f)" % [snow, normal])
	var tuned := _roof("timber.glulam_115x360", 10.0)
	check(_u(tuned, StructureScenario.normal_use(), "b") < 1.0 and _u(tuned, StructureScenario.heavy_snow(), "b") >= 1.0,
			"a roof that passes normal use can fail in heavy snow")


func _ten_years() -> void:
	var g := _roof("timber.glulam_115x360", 4.0)
	var normal := _u(g, StructureScenario.normal_use(), "b")
	var aged := _u(g, StructureScenario.ten_years(), "b")
	check(absf(aged / normal - 1.0 / 0.8) < 0.01, "timber works a quarter harder after ten years (%.3f)" % (aged / normal))
	var steel := _roof("steel.ub_457x191x67", 4.0)
	var sn := _u(steel, StructureScenario.normal_use(), "b")
	var sa := _u(steel, StructureScenario.ten_years(), "b")
	check(absf(sa / sn - 1.0 / 0.9) < 0.01, "and steel a ninth harder (%.3f)" % (sa / sn))
	check(_u(g, StructureScenario.ten_years(), "b") == aged, "the same every time")


func _heavy_use() -> void:
	var house := Samples.house()
	var normal := StructureSolver.stress_test(house, [StructureScenario.normal_use()] as Array[StructureScenario])
	var packed := StructureSolver.stress_test(house, [StructureScenario.heavy_use()] as Array[StructureScenario])
	check(packed.envelope("f0") > normal.envelope("f0"), "packed rooms load the floor beams harder (%.2f vs %.2f)"
			% [packed.envelope("f0"), normal.envelope("f0")])


func _scaled() -> void:
	var storm := StructureScenario.storm()
	var hard := storm.scaled(1.3)
	check(hard.id == "storm*1.3" and hard.title.contains("1.3"), "a scaled test says how much harder (%s, %s)" % [hard.id, hard.title])
	check(is_equal_approx(hard.wind_kpa, storm.wind_kpa * 1.3) and hard.dead == storm.dead, "more wind, same self weight")
	check(storm.scaled(1.0).id == "storm", "scaling by one changes nothing")
	var house := Samples.house()
	var base := StructureSolver.stress_test(house, [storm] as Array[StructureScenario])
	var worse := StructureSolver.stress_test(house, [hard] as Array[StructureScenario])
	check(worse.envelope("bx01") > base.envelope("bx01"), "and the braces work harder")
	check(worse.results[0].scenario_id == "storm*1.3", "the report names the harder test")


func _by_id() -> void:
	for sid: String in ["heavy_snow", "ten_years", "heavy_use"]:
		check(StructureScenario.by_id(sid) != null and StructureScenario.by_id(sid).id == sid, "%s by id" % sid)
	var s := StructureScenario.by_id("quake", 1.5)
	check(s.id == "quake*1.5" and is_equal_approx(s.quake_g, StructureScenario.quake().quake_g * 1.5), "by id with a factor")
	var again := StructureScenario.by_id(s.id)
	check(again != null and again.id == s.id and is_equal_approx(again.quake_g, s.quake_g), "and back from its id")
	check(StructureScenario.by_id("storm*x") == null and StructureScenario.by_id("blizzard") == null, "nonsense is refused")
	var wire := StructureScenario.from_dict(bytes_to_var(var_to_bytes(StructureScenario.ten_years().scaled(1.2).to_dict())))
	check(is_equal_approx(float(wire.capacity.get("timber", 0.0)), 0.8) and is_equal_approx(wire.factor, 1.2),
			"capacity and factor survive the network")


func _house() -> void:
	var h := Samples.model_house()
	var list: Array[StructureScenario] = [StructureScenario.heavy_snow(), StructureScenario.ten_years(), StructureScenario.heavy_use()]
	var rep := StructureBuilding.stress_test(h.model, list)
	check(rep.results.size() == 3 and rep.results[1].scenario_id == "ten_years", "the building check takes a list of events")
