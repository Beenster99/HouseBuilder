extends ModuleTest
## Generated briefs, payout, career and unlocks, and the bus taking a contract from the
## board to handover, solo and with two players.
##   tools/run_tests.sh contracts

const Kit := preload("res://modules/contracts/tests/building_kit.gd")
const C := preload("res://modules/building/api/building_commands.gd")
const PORT := 24591


func run_tests() -> void:
	_generator()
	_payout()
	_career()
	_bus_solo()
	await _panel()
	await _bus_two_players()


func _generator() -> void:
	var a := ContractGenerator.generate(42)
	var b := ContractGenerator.generate(42)
	check(a == b, "the same seed gives the same brief")
	check(ContractGenerator.generate(43) != a, "another seed gives another")
	var types := {}
	var all_ok := true
	for s in 200:
		var g := ContractGenerator.generate(s, "", 100)
		types[g.type] = true
		var n := ContractBrief.normalize(g)
		if n.is_empty() or float(n.budget) <= 0.0 or float(n.fee) <= float(n.budget) or int(n.deadline_days) <= 0 or (n.requirements as Array).is_empty():
			all_ok = false
		for r: Dictionary in n.requirements:
			if ContractBrief.describe(r) == str(r.kind):
				all_ok = false
	check(all_ok, "every generated brief has a budget, a fee above it, a deadline and readable requirements")
	check(types.size() >= 12, "200 briefs cover at least 12 building types (%d)" % types.size())
	var open := ContractGenerator.types_open(0)
	check("bungalow" in open and not "airport_terminal" in open, "a new firm is offered houses, not airports")
	for s in 50:
		if not str(ContractGenerator.generate(s, "", 0).type) in open:
			all_ok = false
	check(all_ok, "and never rolls a type it has not unlocked")
	var school := ContractGenerator.generate(7, "primary_school")
	check(str(school.type) == "primary_school" and "classroom" in str(school.summary), "a type can be asked for: %s" % school.summary)
	# A generated semi-detached house brief can be won by the test house, near enough:
	# its budget is in the same range as a real design's cost.
	var semi := ContractGenerator.generate(3, "semi_detached")
	var cost: float = BuildingQuantities.totals(Kit.house()).cost
	check(float(semi.budget) > cost * 0.6 and float(semi.budget) < cost * 2.0,
			"a semi's budget (%s) is in range of a real house's cost (%s)" % [ContractValidator.money(semi.budget), ContractValidator.money(cost)])
	var board := ContractGenerator.board(1, 0, 5)
	check(board.size() == 5 and str(board[0].id) == "house_detached_3bed", "the first board leads with the hand-written house")
	var later := ContractGenerator.board(1, 0, 5, ["house_detached_3bed"])
	check(str(later[0].id) != "house_detached_3bed", "and moves on once it is done")


func _payout() -> void:
	var brief := ContractBrief.authored_brief("house_detached_3bed")
	var a := ContractValidator.assess(brief, Kit.house())
	var on_time := ContractPayout.settle(brief, a, {"days": 120})
	check(on_time.passed and on_time.fee == 202000.0 and on_time.late_days == 0, "a passing house on time is paid in full")
	check(is_equal_approx(on_time.profit, 202000.0 + a.bonus - a.cost), "profit is fee plus bonuses less the build cost")
	check(on_time.reputation == 4, "and earns the brief's reputation")
	var late := ContractPayout.settle(brief, a, {"days": 164})
	check(late.late_days == 14 and is_equal_approx(late.late_penalty, 202000.0 * 0.005 * 14), "two weeks late costs 7% of the fee")
	check(late.reputation == 2, "and two reputation")
	var failed := a.duplicate(true)
	failed.ok = false
	(failed.items as Array)[0].ok = false
	var f := ContractPayout.settle(brief, failed, {"days": 100})
	check(not f.passed and f.fee == 0.0 and f.profit < 0.0 and f.reputation == -2, "a failed handover is not paid, loses money and reputation")
	check("Not paid" in str(f.lines[0]) and "3 bedrooms" in str(f.lines[0]), "and says why: %s" % f.lines[0])


func _career() -> void:
	var c := ContractCareer.new()
	check(c.money == ContractCareer.START_MONEY and c.reputation == 0, "a new firm starts with money and no name")
	var cat := BuildingCatalog.default_catalog()
	check(c.is_kind_unlocked("column", cat) and not c.is_material_unlocked("steel"), "timber and concrete columns are open, steel is not")
	check(not c.is_kind_unlocked("truss", cat) and not c.is_unlocked("type:primary_school"), "trusses and schools are locked")
	var fresh := c.record({"brief_id": "x", "passed": true, "profit": 30000.0, "reputation": 10})
	check(c.reputation == 10 and c.money == ContractCareer.START_MONEY + 30000.0, "a contract books its profit and reputation")
	check("material:steel" in fresh and "type:primary_school" in fresh, "reputation 10 unlocks steel and primary schools")
	check(c.is_kind_unlocked("beam", cat), "beams are open")
	check(not c.next_unlock().is_empty() and int(c.next_unlock().rep) > 10, "the next unlock is further up")
	var copy := ContractCareer.new()
	copy.load_data(c.to_data())
	check(copy.to_data() == c.to_data() and copy.streak() == 1, "the career saves and loads")


func _bus_solo() -> void:
	var bus := ContractsBus.new()
	add_child(bus)
	bus._deal_board(5)
	check(bus.board.size() == ContractsBus.BOARD_SIZE, "the bus deals a board")
	var model := Kit.house()
	var house_id := str(bus.board[0].id)
	bus.accept(house_id)
	check(str(bus.active.get("id", "")) == house_id, "a contract is taken from the board")
	check(bus.assess(model).ok, "and the live check passes the test house")
	bus.accept(str(bus.board[1].id))
	check(str(bus.active.id) == house_id, "a second contract cannot be taken on top")
	# A stress test result counts only for the design it was made for.
	var shared := (Modules.bus("building") as BuildingBus).model
	shared.load_data(model.to_data())
	var st := StructureBuilding.stress_test(shared).brief_result()
	check(st.has("ok") and st.has("failures") and st.has("scenario"), "the structure module's result has the brief's shape")
	bus._take_report({"ok": true, "failures": [], "worst": 0.5, "scenario": ""})
	check(bus.report_for(shared).get("ok", false), "a fresh stress test result is used")
	shared.apply(C.place_part("column", 0, {"at": [5, 0, 4]}))
	check(bus.report_for(shared).get("stale", false), "after an edit it is stale")
	var stale_check := ContractValidator.check({"kind": "structure"}, {"model": shared, "cat": shared.catalog, "report": bus.report_for(shared)})
	check(not stale_check.ok and "again" in str(stale_check.tip), "and the structure requirement asks for a new test")
	shared.load_data(BuildingModel.new().to_data())
	var settled: Array = []
	bus.settled.connect(func(s: Dictionary) -> void: settled.append(s))
	# Hand over needs the shared building; check the payout path with this model directly.
	var s := ContractPayout.settle(bus.active, bus.assess(model), {"days": 100})
	bus._apply_handover({"settlement": s, "seed": 6})
	check(settled.size() == 1 and bus.active.is_empty() and bus.career.reputation == 4, "handover books it and clears the contract")
	check(bus.board_seed == 6 and str(bus.board[0].id) != house_id, "and deals a new board without the finished house")
	var saved := bus.save_data()
	var other := ContractsBus.new()
	add_child(other)
	other.load_data(saved, ContractsBus.SAVE_VERSION)
	check(other.save_data() == saved, "the contracts section saves and loads")
	bus.queue_free()
	other.queue_free()


## A stand-in for the design bus's panel registry.
class FakeDesign extends Node:
	var panels := {}
	func register_panel(id: String, title: String, make: Callable, order: int = 50) -> void:
		panels[id] = {"title": title, "make": make, "order": order}
	func unregister_panel(id: String) -> void:
		panels.erase(id)


func _panel() -> void:
	var bus := ContractsBus.new()
	add_child(bus)
	bus._deal_board(5)
	var design := FakeDesign.new()
	add_child(design)
	bus.hook_design(design)
	check(design.panels.is_empty(), "no Contract window without a contract")
	bus.accept(str(bus.board[0].id))
	check(design.panels.has(ContractsBus.PANEL_ID), "taking a contract puts the Contract window in the design room")
	var model := Kit.house()
	var panel: RichTextLabel = (design.panels[ContractsBus.PANEL_ID].make as Callable).call(model)
	add_child(panel)
	check("Requirements 7 / 7" in panel.text and "Three-bedroom" in panel.text, "it shows the brief and how the design measures up")
	for rid: String in model.rooms.keys():
		if str(model.rooms[rid].type) == "garage":
			model.apply(C.retag(rid, "store_room"))
	await get_tree().create_timer(0.4).timeout
	check("Requirements 6 / 7" in panel.text and "garage" in panel.text.to_lower(), "an edit refreshes it a moment later")
	bus.abandon()
	check(not design.panels.has(ContractsBus.PANEL_ID), "abandoning the contract takes the window away")
	panel.queue_free()
	bus.queue_free()
	design.queue_free()


func _bus_two_players() -> void:
	var saved := Flags.all()
	Flags.set_flag(MultiplayerBus.ONLINE_FLAG, true)
	var na := _net("ConA", "Ana")
	var nb := _net("ConB", "Ben")
	var ca := ContractsBus.new()
	var cb := ContractsBus.new()
	add_child(ca)
	add_child(cb)
	ca._deal_board(9)
	ca.bind(na)
	cb.bind(nb)
	check(na.host(PORT) == OK, "host starts")
	nb.join("127.0.0.1", PORT)
	check(await _until(func() -> bool: return cb.board_seed == 9 and cb.board.size() == ca.board.size()), "the joiner gets the host's board")
	var pick := str(ca.board[2].id)
	cb.accept(pick)
	check(await _until(func() -> bool: return str(ca.active.get("id", "")) == pick and str(cb.active.get("id", "")) == pick),
			"Ben takes a contract and both see it")
	ca.set_structure_report({"ok": true, "failures": []})
	check(await _until(func() -> bool: return bool(cb.structure_report.get("ok", false))), "the stress test result reaches both")
	cb.abandon()
	check(await _until(func() -> bool: return ca.active.is_empty() and cb.active.is_empty()), "abandoning drops it for both")
	ca.unbind()
	cb.unbind()
	nb.leave()
	na.leave()
	ca.queue_free()
	cb.queue_free()
	Flags.use(saved)


func _net(node_name: String, player: String) -> MultiplayerBus:
	var bus := MultiplayerBus.new()
	bus.name = node_name
	add_child(bus)
	bus.register_module()
	Settings.set_value("multiplayer", "player_name", player)
	bus._refresh_identity()
	return bus


func _until(cond: Callable, timeout := 5.0) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()
