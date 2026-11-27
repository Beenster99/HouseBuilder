extends ModuleTest
## After the handover (flag contracts.aftercare): each later event is judged on the building
## with the structure module's harder tests; a sound building earns a thank-you, a weak one a
## repair bill and a warier client; the news lands with the next handover and saves.
##   tools/run_tests.sh contracts

const Kit := preload("res://modules/contracts/tests/building_kit.gd")
const C := preload("res://modules/building/api/building_commands.gd")


func run_tests() -> void:
	var saved := Flags.all()
	_events()
	_flow()
	Flags.use(saved)


func _events() -> void:
	var brief := ContractBrief.authored_brief("house_detached_3bed")
	var house := Kit.house()
	for id in ["heavy_snow", "storm", "ten_years", "heavy_use"]:
		var ev := ContractAftercare.judge(brief, house, id)
		check(str(ev.event) == id and ContractAftercare.text(ev) != "", "%s is judged: %s" % [id, ContractAftercare.text(ev)])
	var raw := ContractAftercare.judge(brief, house, "heavy_snow")
	check(not bool(raw.ok) and float(raw.repair) <= float(brief.fee) * ContractAftercare.MAX_REPAIR_SHARE + 1.0 and ContractAftercare.text(raw).contains("stress test"),
			"the unengineered test house does not hold heavy snow; the bill is capped and says what to do")
	var plan := StructureDesigner.design(house, [StructureScenario.heavy_snow()] as Array[StructureScenario])
	if not (plan.get("op", {}) as Dictionary).is_empty():
		house.apply(plan.op)
	var snow := ContractAftercare.judge(brief, house, "heavy_snow")
	check(bool(snow.ok) and float(snow.bonus) > 0.0 and int(snow.xp) > 0, "engineered for it, the house holds and earns a thank-you: %s" % ContractAftercare.text(snow))
	# A long beam on thin posts will not take the snow on a roof.
	var weak := BuildingModel.new("", "Weak shed")
	weak.apply(C.place_part("column", 0, {"at": [0, 0, 0]}, "timber"))
	weak.apply(C.place_part("column", 0, {"at": [14, 0, 0]}, "timber"))
	weak.apply(C.place_part("beam", 0, {"a": [0, 3, 0], "b": [14, 3, 0]}, "timber"))
	weak.apply(C.place_part("roof_flat", 0, {"outline": C.rect(0, -2, 14, 4), "y": 3.0}, "timber"))
	var bad := ContractAftercare.judge(brief, weak, "heavy_snow")
	check(not bool(bad.ok) and float(bad.repair) > 0.0 and not (bad.failed as Array).is_empty(), "a weak shed fails: %s" % ContractAftercare.text(bad))
	Flags.set_flag(ContractAftercare.FLAG, false)
	check(ContractAftercare.judge(brief, house).is_empty(), "off: no later events")
	Flags.set_flag(ContractAftercare.FLAG, true)
	var demo := ContractDemolition.generate(1, 2)
	check(ContractAftercare.judge(demo, house).is_empty(), "never for a demolition")


func _flow() -> void:
	var c := ContractCareer.new()
	c.clients["The Okafor family"] = {"jobs": 1, "standing": 3}
	var money := c.money
	c.record_aftercare({"ok": false, "repair": 5000.0, "client": "The Okafor family"})
	check(is_equal_approx(c.money, money - 5000.0) and ContractClients.level(c.clients["The Okafor family"]) == 2, "a call-back costs money and standing")
	c.record_aftercare({"ok": true, "bonus": 1000.0, "xp": 50})
	check(is_equal_approx(c.money, money - 4000.0) and c.xp == 50, "a thank-you pays")
	c.aftercare = {"event": "heavy_snow", "ok": true}
	var other := ContractCareer.new()
	other.load_data(c.to_data())
	check(str(other.aftercare.get("event", "")) == "heavy_snow", "a waiting event saves")
	# The news comes with the next handover.
	var bus := ContractsBus.new()
	add_child(bus)
	bus.career.aftercare = {"brief_id": "x", "title": "The old barn", "client": "", "event": "heavy_snow", "label": "Heavy snow",
			"ok": true, "failed": [], "leak": false, "bonus": 2000.0, "repair": 0.0, "xp": 20}
	bus._apply_handover({"settlement": {"brief_id": "y", "passed": true, "profit": 0.0, "xp": 0, "lines": ["Paid."]}, "seed": 4,
			"aftercare": {"event": "storm", "ok": true}})
	var s: Dictionary = bus.last_settlement
	check(s.has("aftercare") and str((s.lines as PackedStringArray)[-1]).contains("old barn"), "the news is in the settlement: %s" % (s.lines as PackedStringArray)[-1])
	check(str(bus.career.aftercare.get("event", "")) == "storm", "and the new building's event waits for next time")
	bus.queue_free()
