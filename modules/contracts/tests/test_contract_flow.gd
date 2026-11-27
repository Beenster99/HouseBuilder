extends ModuleTest
## Generated briefs, payout, the firm's XP, tiers and unlocks, and the bus taking a contract
## from the board to handover, solo and with two players; the big-screen board and the
## debug menu's XP buttons.
##   tools/run_tests.sh contracts

const Kit := preload("res://modules/contracts/tests/building_kit.gd")
const C := preload("res://modules/building/api/building_commands.gd")
const PORT := 24591


func run_tests() -> void:
	_generator()
	_payout()
	_career()
	_tiers()
	_bus_solo()
	_debug_xp()
	await _board_in_window()
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
		var g := ContractGenerator.generate(s, "", 7)
		types[g.type] = true
		var n := ContractBrief.normalize(g)
		if n.is_empty() or float(n.budget) <= 0.0 or float(n.fee) <= float(n.budget) or int(n.deadline_days) <= 0 or (n.requirements as Array).is_empty():
			all_ok = false
		for r: Dictionary in n.requirements:
			if ContractBrief.describe(r) == str(r.kind):
				all_ok = false
	check(all_ok, "every generated brief has a budget, a fee above it, a deadline and readable requirements")
	check(types.size() >= 12, "200 briefs cover at least 12 building types (%d)" % types.size())
	# Every brief states its plot, size limits, room sizes and materials.
	var spelled := true
	for s in 60:
		var g := ContractGenerator.generate_on_site(s, "", 7)
		var lines := ContractBrief.spec_lines(g)
		var kinds := {}
		for r: Dictionary in g.requirements:
			kinds[str(r.kind)] = true
			if str(r.kind) == "rooms" and float(r.get("min_area", 0.0)) <= 0.0:
				spelled = false
		if not (kinds.has("within_plot") and kinds.has("materials") and kinds.has("max_height") and kinds.has("max_storeys")) \
				or (g.site.plot as Array).size() < 3 or float(g.site.w) <= 0.0 or lines.size() < 5 \
				or not str(lines[0]).begins_with("Plot: ") or not "Structure: " in "\n".join(lines):
			spelled = false
	check(spelled, "every brief gives its plot, building limits, room sizes and materials: %s" % ["\n".join(ContractBrief.spec_lines(ContractGenerator.generate(3, "semi_detached", 2)))])
	var plain_plot := ContractGenerator.generate(3, "semi_detached", 2)
	check(str(plain_plot.site.id) == "" and float(plain_plot.site.area) >= float(plain_plot.floor_area),
			"a brief with no real site gets a plain plot big enough for it")
	check(not "steel" in ContractGenerator.structure_materials("bungalow") and "steel" in ContractGenerator.structure_materials("detached_house"),
			"materials follow the tier: no steel for a tier 2 bungalow, steel for a tier 3 house")
	var open := ContractGenerator.types_open(1)
	check("garden_studio" in open and not "bungalow" in open and not "airport_terminal" in open, "a new firm is offered small works only")
	for s in 50:
		var g := ContractGenerator.generate(s, "", 1)
		if not str(g.type) in open or int(g.tier) != 1 or int(g.xp) <= 0:
			all_ok = false
	check(all_ok, "and never rolls a type it has not unlocked")
	var own := 0
	for s in 100:
		if int(ContractGenerator.generate(s, "", 4).tier) == 4:
			own += 1
	check(own >= 55 and own < 100, "a tier 4 firm is mostly offered tier 4 work, some from below (%d of 100)" % own)
	var small := ContractGenerator.generate(5, "garden_studio", 1)
	var big := ContractGenerator.generate(5, "airport_terminal", 7)
	check(int(big.xp) > int(small.xp) * 20, "an airport earns far more XP than a garden studio (%d, %d)" % [int(big.xp), int(small.xp)])
	var school := ContractGenerator.generate(7, "primary_school")
	check(str(school.type) == "primary_school" and "classroom" in str(school.summary), "a type can be asked for: %s" % school.summary)
	# A generated semi-detached house brief can be won by the test house, near enough:
	# its budget is in the same range as a real design's cost.
	var semi := ContractGenerator.generate(3, "semi_detached")
	var cost: float = BuildingQuantities.totals(Kit.house()).cost
	check(float(semi.budget) > cost * 0.6 and float(semi.budget) < cost * 2.0,
			"a semi's budget (%s) is in range of a real house's cost (%s)" % [ContractValidator.money(semi.budget), ContractValidator.money(cost)])
	# Briefs on real plots.
	var onsite := 0
	var site_ok := true
	for s in 40:
		var g := ContractGenerator.generate_on_site(s, "", 7)
		if str(g.site.id) != "":
			onsite += 1
			var plot: Array = g.site.plot
			var has_req := false
			for r: Dictionary in g.requirements:
				if str(r.kind) == "within_plot":
					has_req = true
			if plot.size() < 3 or not has_req or not str(g.site.name) in str(g.summary) or int(g.site.rating) < 1:
				site_ok = false
	check(onsite >= 20, "most briefs find a real plot (%d of 40)" % onsite)
	check(site_ok, "each has the plot's outline, a within_plot requirement and the site in its summary")
	var plain := ContractGenerator.generate(11, "primary_school", 7)
	var sited := ContractGenerator.generate_on_site(11, "primary_school", 7)
	check(str(sited.site.id) != "" and float(sited.budget) >= float(plain.budget), "a hard plot raises the budget (%s on %s)" % [
			ContractValidator.money(sited.budget), str(sited.get("site", {}).get("name", "?"))])
	check(ContractGenerator.generate_on_site(11, "primary_school", 7) == sited, "and the same seed picks the same plot")
	check(ContractGenerator.max_site_rating(1) == 2 and ContractGenerator.max_site_rating(7) == 5, "harder plots open up with the tier")
	var first := ContractGenerator.board(1, 1, 5)
	check(first.size() == 5 and first.all(func(b: Dictionary) -> bool: return int(b.tier) == 1), "a new firm's board is all small works")
	var board := ContractGenerator.board(1, 3, 5)
	check(board.size() == 5 and str(board[0].id) == "house_detached_3bed", "at tier 3 the board leads with the hand-written house")
	var later := ContractGenerator.board(1, 3, 5, ["house_detached_3bed"])
	check(str(later[0].id) != "house_detached_3bed", "and moves on once it is done")


func _payout() -> void:
	var brief := ContractBrief.authored_brief("house_detached_3bed")
	var a := ContractValidator.assess(brief, Kit.house())
	var on_time := ContractPayout.settle(brief, a, {"days": 120})
	check(on_time.passed and on_time.fee == 202000.0 and on_time.late_days == 0, "a passing house on time is paid in full")
	check(is_equal_approx(on_time.profit, 202000.0 + a.bonus - a.cost), "profit is fee plus bonuses less the build cost")
	check(on_time.xp >= 1000 and int(on_time.tier) == 3, "and earns the brief's XP, more for goals met (%d)" % on_time.xp)
	var late := ContractPayout.settle(brief, a, {"days": 164})
	check(late.late_days == 14 and is_equal_approx(late.late_penalty, 202000.0 * 0.005 * 14), "two weeks late costs 7% of the fee")
	check(late.xp == on_time.xp - 200, "and two weeks late earns a fifth less XP (%d)" % late.xp)
	var failed := a.duplicate(true)
	failed.ok = false
	(failed.items as Array)[0].ok = false
	var f := ContractPayout.settle(brief, failed, {"days": 100})
	check(not f.passed and f.fee == 0.0 and f.profit < 0.0 and f.xp == 0, "a failed handover is not paid, loses money and earns no XP")
	check("Not paid" in str(f.lines[0]) and "3 bedrooms" in str(f.lines[0]), "and says why: %s" % f.lines[0])


func _career() -> void:
	var c := ContractCareer.new()
	check(c.money == ContractCareer.START_MONEY and c.xp == 0 and c.tier() == 1, "a new firm starts with money, no XP, at tier 1")
	var cat := BuildingCatalog.default_catalog()
	check(c.is_kind_unlocked("column", cat) and not c.is_material_unlocked("steel"), "timber and concrete columns are open, steel is not")
	check(not c.is_kind_unlocked("truss", cat) and not c.is_unlocked("type:bungalow") and c.is_unlocked("type:garden_studio"),
			"trusses and houses are locked, small works are open")
	var fresh := c.record({"brief_id": "x", "passed": true, "profit": 30000.0, "xp": 3000})
	check(c.xp == 3000 and c.money == ContractCareer.START_MONEY + 30000.0, "a contract books its profit and XP")
	check(c.tier() == 3 and "material:steel" in fresh and "type:detached_house" in fresh and "type:bungalow" in fresh,
			"3,000 XP is tier 3: steel, detached houses and everything below")
	check(c.is_kind_unlocked("beam", cat), "beams are open")
	check(not c.next_unlock().is_empty() and int(c.next_unlock().tier) == 4, "the next unlock is at tier 4")
	c.lose_xp(5000)
	check(c.xp == 3000 and c.tier() == 3, "losing XP never drops the firm a tier")
	c.set_xp(ContractTiers.MAX_XP)
	check(c.tier() == ContractTiers.top() and c.is_unlocked("type:airport_terminal") and c.is_kind_unlocked("curtain_wall", cat),
			"Max XP opens the top tier and everything in it")
	c.set_xp(0)
	check(c.tier() == 1 and not c.is_material_unlocked("steel"), "and back to 0 locks it again")
	c.set_xp(3000)
	var copy := ContractCareer.new()
	copy.load_data(c.to_data())
	check(copy.to_data() == c.to_data() and copy.streak() == 1 and copy.tier() == 3, "the career saves and loads")


func _tiers() -> void:
	check(ContractTiers.tier_for(0) == 1 and ContractTiers.tier_for(999) == 1 and ContractTiers.tier_for(1000) == 2, "tier 2 starts at 1,000 XP")
	check(ContractTiers.tier_for(ContractTiers.MAX_XP) == ContractTiers.top(), "MAX_XP is the top tier")
	var p := ContractTiers.progress(2000)
	check(int(p.tier) == 2 and int(p.next) == 3000 and is_equal_approx(float(p.share), 0.5), "progress is halfway from tier 2 to 3")
	check(int(ContractTiers.progress(ContractTiers.MAX_XP).next) == -1, "the top tier has no next")
	check(ContractTiers.xp_text(12500) == "12,500 XP", "XP reads with commas")
	var every := true
	for t in range(1, ContractTiers.top() + 1):
		if ContractGenerator.types_of_tier(t).is_empty():
			every = false
	check(every, "every tier brings new building types")
	# About four contracts at a tier reach the next one.
	var steady := true
	for t in range(1, ContractTiers.top()):
		var need := int(ContractTiers.info(t + 1).xp) - int(ContractTiers.info(t).xp)
		var n := float(need) / float(ContractTiers.info(t).award)
		if n < 2.5 or n > 6.0:
			steady = false
	check(steady, "each tier takes a few contracts, not one or twenty")


func _bus_solo() -> void:
	var bus := ContractsBus.new()
	add_child(bus)
	bus.career.set_xp(3000)
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
	check(settled.size() == 1 and bus.active.is_empty() and bus.career.xp == 3000 + int(s.xp), "handover books its XP and clears the contract")
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
	var channels := {}
	func register_panel(id: String, title: String, make: Callable, order: int = 50) -> void:
		panels[id] = {"title": title, "make": make, "order": order}
	func unregister_panel(id: String) -> void:
		panels.erase(id)
	func register_channel(id: String, title: String, make: Callable, order: int = 50) -> void:
		channels[id] = {"title": title, "make": make, "order": order}
	func unregister_channel(id: String) -> void:
		channels.erase(id)


func _panel() -> void:
	var bus := ContractsBus.new()
	add_child(bus)
	bus.career.set_xp(3000)
	bus._deal_board(5)
	var design := FakeDesign.new()
	add_child(design)
	bus.hook_design(design)
	check(design.panels.is_empty(), "no Contract window without a contract")
	check(design.channels.has(ContractsBus.CHANNEL_ID) and str(design.channels[ContractsBus.CHANNEL_ID].title) == "Contracts",
			"the Contracts big-screen channel is registered")
	var board: Control = (design.channels[ContractsBus.CHANNEL_ID].make as Callable).call(null)
	add_child(board)
	var accepts := board.find_children("Accept", "Button", true, false)
	check(accepts.size() == ContractsBus.BOARD_SIZE and not (accepts[0] as Button).disabled, "it lists the board with an Accept button each")
	check("Tier 3" in _texts(board) and "7,000 XP" in _texts(board), "and the firm's tier and the XP to the next")
	(accepts[0] as Button).pressed.emit()
	await frames(2)
	check(str(bus.active.get("id", "")) == str(bus.board[0].id), "Accept on the big screen takes the contract")
	check(board.find_children("ContractPanel", "", true, false).size() == 1, "and it shows the live brief")
	bus.abandon()
	await frames(2)
	check(bus.active.is_empty() and bus.career.xp == 3000, "abandoning costs XP, never the tier")
	board.queue_free()
	bus.accept(str(bus.board[0].id))
	check(design.panels.has(ContractsBus.PANEL_ID), "taking a contract puts the Contract window in the design room")
	var model := Kit.house()
	var panel: RichTextLabel = (design.panels[ContractsBus.PANEL_ID].make as Callable).call(model)
	add_child(panel)
	check("Requirements 10 / 10" in panel.text and "Three-bedroom" in panel.text, "it shows the brief and how the design measures up")
	check("Plot: 24 x 20 m" in panel.text and "Structure: timber" in panel.text and "bedrooms, 7.5 m2+" in panel.text, "with the plot, the room sizes and the materials")
	for rid: String in model.rooms.keys():
		if str(model.rooms[rid].type) == "garage":
			model.apply(C.retag(rid, "store_room"))
	await get_tree().create_timer(0.4).timeout
	check("Requirements 9 / 10" in panel.text and "garage" in panel.text.to_lower(), "an edit refreshes it a moment later")
	bus.abandon()
	check(not design.panels.has(ContractsBus.PANEL_ID), "abandoning the contract takes the window away")
	panel.queue_free()
	bus.queue_free()
	design.queue_free()


func _texts(root: Node) -> String:
	var out := ""
	for n in root.find_children("*", "", true, false):
		if n is Label:
			out += (n as Label).text + "\n"
		elif n is RichTextLabel:
			out += (n as RichTextLabel).get_parsed_text() + "\n"
	return out


## The designer's "Contracts..." step shows the page in a scrolling window: the lists must
## still have height there.
func _board_in_window() -> void:
	var bus := Modules.bus("contracts") as ContractsBus
	check(bus != null and bus.board.size() == ContractsBus.BOARD_SIZE, "the running game's contracts bus has a board dealt")
	var scroll := ScrollContainer.new()
	scroll.size = Vector2(980, 620)
	add_child(scroll)
	var page := bus.make_board(null)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)
	await frames(3)
	var offers := page.find_children("Offer_*", "", true, false)
	var lists := page.find_children("ColumnScroll", "ScrollContainer", true, false)
	check(offers.size() == ContractsBus.BOARD_SIZE and lists.all(func(c: Control) -> bool: return c.size.y > 200.0),
			"in a scrolling window the offers have room to show")
	scroll.queue_free()


func _debug_xp() -> void:
	var bus := ContractsBus.new()
	add_child(bus)
	bus._deal_board(5)
	var section := bus.make_debug_section()
	add_child(section)
	check("Tier 1" in _texts(section), "the debug section shows the firm's tier")
	(section.find_child("MaxXP", true, false) as Button).pressed.emit()
	check(bus.career.tier() == ContractTiers.top() and bus.career.xp == ContractTiers.MAX_XP, "Max XP jumps to the top tier")
	check(bus.board.any(func(b: Dictionary) -> bool: return int(b.tier) == ContractTiers.top()), "and deals a board with top-tier work")
	check("Tier 7" in _texts(section), "and the section updates")
	(section.find_child("ResetXP", true, false) as Button).pressed.emit()
	(section.find_child("Nexttier", true, false) as Button).pressed.emit()
	check(bus.career.tier() == 2 and bus.career.xp == 1000, "Next tier steps up one tier")
	check(Menu.settings_sections(Menu.DEBUG).any(func(c: Dictionary) -> bool: return str(c.id) == ContractsBus.DEBUG_SECTION),
			"the contracts module adds it to Settings > Debug")
	section.queue_free()
	bus.queue_free()


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
