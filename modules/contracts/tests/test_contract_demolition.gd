extends ModuleTest
## Demolition jobs (flag contracts.demolition_jobs): the brief, the old building it brings
## down, the judging on a demolition result, the board slot, accepting (the old building is
## loaded and the demolition starts) and the handover.
##   tools/run_tests.sh contracts


func run_tests() -> void:
	var saved := Flags.all()
	_brief()
	_judging()
	await _flow()
	Flags.use(saved)


func _brief() -> void:
	var b := ContractDemolition.generate(5, 3)
	check(ContractDemolition.is_demolition(b) and str(b.title).begins_with("Demolish"), "a demolition brief: %s" % b.title)
	var kinds := (b.requirements as Array).map(func(r: Dictionary) -> String: return str(r.kind))
	check("demolition_collapse" in kinds and "debris_within_plot" in kinds and "neighbours_safe" in kinds and "charge_budget" in kinds,
			"judged on collapse, debris, neighbours and charges")
	var norm := ContractBrief.normalize(b)
	check(not (norm.requirements as Array).any(func(r: Dictionary) -> bool: return str(r.kind) == "weathertight"),
			"with no roof or foundation checks")
	var m := BuildingModel.from_data(ContractDemolition.target_design(b))
	check(m.parts.size() > 10 and m.locked_ids().size() == m.parts.size(), "the old building is all there, locked (%d parts)" % m.parts.size())
	check(ContractDemolition.generate(5, 3) == b, "the same seed gives the same job")
	var o := ContractDemolition.start_options(b)
	check((o.plot as PackedVector2Array).size() == 4 and (o.neighbours as Array).size() == 2 and o.neighbours[0] is AABB, "the plot and two neighbours to protect")
	var doc := ContractBriefing.text(b)
	check(doc.contains("What to bring down") and doc.contains("No more than") and doc.contains("neighbouring buildings"), "the briefing explains the job")
	var own := ContractDemolition.generate(6, 4, {"id": "t1", "title": "Riverside surgery", "model": ContractDemolition.old_building(10, 8, 2, "Riverside surgery")})
	check(str(own.record_id) == "t1" and str(own.summary).contains("one of your own"), "the firm's own old building can be the job")


func _judging() -> void:
	var b := ContractDemolition.generate(5, 3)
	var none := ContractDemolition.assess(b, {})
	check(not none.ok and str(none.summary).contains("fire"), "nothing fired: not done")
	var charges := 0
	for r: Dictionary in b.requirements:
		if str(r.kind) == "charge_budget":
			charges = int(r.value)
	var clean := {"collapsed": 1.0, "debris_outside": 0.01, "debris_outside_m3": 1.0, "neighbours_hit": 0, "charges_used": charges - 1}
	var good := ContractDemolition.assess(b, clean)
	check(good.ok and float(good.cost) <= float(good.budget), "a clean job passes within budget: %s" % good.summary)
	check(float(good.bonus) > 0.0, "and the tidy goal pays a bonus")
	var messy := clean.duplicate()
	messy.neighbours_hit = 1
	messy.collapsed = 0.7
	var bad := ContractDemolition.assess(b, messy)
	check(not bad.ok and str(bad.summary).contains("neighbouring"), "hitting a neighbour and leaving it half up fails: %s" % bad.summary)
	var s := ContractPayout.settle(b, good, {"days": int(b.deadline_days)})
	check(bool(s.passed) and float(s.fee) > 0.0 and int(s.xp) > 0, "it settles like any contract")


func _flow() -> void:
	Flags.set_flag(ContractDemolition.FLAG, false)
	var bus := ContractsBus.new()
	bus.open_demolition = false
	add_child(bus)
	bus._deal_board(9)
	check(not bus.board.any(func(o: Dictionary) -> bool: return ContractDemolition.is_demolition(o)), "off: no demolition jobs")
	Flags.set_flag(ContractDemolition.FLAG, true)
	bus._deal_board(9)
	var job: Dictionary = bus.board[-1]
	check(ContractDemolition.is_demolition(job), "on: the board's last slot is a demolition job")
	var bb := Modules.bus("building") as BuildingBus
	var before := bb.model.to_data() if bb != null else {}
	bus.accept(str(job.id))
	check(ContractDemolition.is_demolition(bus.active), "it can be taken")
	if bb != null:
		check(bb.model.locked_ids().size() == bb.model.parts.size() and bb.model.parts.size() == (job.target.parts as Array).size(), "the old building is loaded into the design (%d of %d locked)" % [bb.model.locked_ids().size(), bb.model.parts.size()])
	await frames(2)
	var demo := Modules.bus("demolition")
	if demo != null:
		check(bool(demo.call("is_active")), "and the demolition starts on it")
	bus.hand_over(1)
	check(not bus.active.is_empty(), "no handover before the charges fire")
	bus._on_demolition_result({"collapsed": 1.0, "debris_outside": 0.0, "debris_outside_m3": 0.0, "neighbours_hit": 0, "charges_used": 3})
	check(bool(bus.assess().get("ok", false)), "the result is judged live")
	var xp := bus.career.xp
	bus.hand_over(1)
	check(bus.active.is_empty() and bus.career.xp > xp and bool(bus.last_settlement.passed), "handing over the cleared site pays")
	if demo != null and demo.has_method("_clear"):
		demo.call("_clear")
	if bb != null:
		bb.sync.load_design(before)
	bus.queue_free()
