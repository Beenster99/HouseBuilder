extends ModuleTest
## The unlock tree and firm upgrades (flag contracts.unlock_tree): which tier opens roof
## shapes, library groups, lifts and gear; locked_tier for the design palette; buying
## upgrades and what they do; the Firm page on the wall screen.
##   tools/run_tests.sh contracts

const Kit := preload("res://modules/contracts/tests/building_kit.gd")


func run_tests() -> void:
	var saved := Flags.all()
	_tiers()
	_locks()
	await _upgrades()
	Flags.use(saved)


func _tiers() -> void:
	var cat := BuildingCatalog.default_catalog()
	check(ContractCareer.tier_of("roof:hip") == 2 and ContractCareer.tier_of("roof:flat") == 1, "hipped roofs open at tier 2, flat at 1")
	check(ContractCareer.tier_of("kind:roof_hip", cat) == 2 and ContractCareer.tier_of("kind:roof_pitched", cat) == 2,
			"a roof kind answers for its shape")
	check(ContractCareer.tier_of("kind:pile", cat) == 4 and ContractCareer.tier_of("kind:lift", cat) == 4, "piles and lifts at tier 4")
	check(ContractCareer.tier_of("kind:wc", cat) == 0, "a fixture is never held back by a material")
	check(ContractCareer.tier_of("lib:healthcare") == 6 and ContractCareer.tier_of("gear:wrecking_ball") == 5, "medical kit at 6, the wrecking ball at 5")
	var opens := ContractCareer.unlocks_at(2).map(func(u: Dictionary) -> String: return str(u.id))
	check("roof:gable" in opens and "type:bungalow" in opens, "tier 2 lists gable roofs and bungalows")


func _locks() -> void:
	var bus := ContractsBus.new()
	add_child(bus)
	bus._deal_board(3)
	Flags.set_flag(ContractsBus.UNLOCK_FLAG, false)
	bus.accept(str(bus.board[0].id))
	check(bus.locked_tier("roof:hip") == 0, "with the unlock tree off nothing is locked")
	Flags.set_flag(ContractsBus.UNLOCK_FLAG, true)
	check(bus.locked_tier("roof:hip") == 2 and bus.locked_tier("roof:flat") == 0 and bus.locked_tier("lib:healthcare") == 6,
			"a tier 1 firm on a contract sees hipped roofs locked until tier 2")
	check(bus.locked_tier("kind:lift") == 4 and bus.locked_tier("kind:roof_mono") == 0, "lifts locked, mono-pitch open")
	bus.abandon()
	check(bus.locked_tier("roof:hip") == 0, "free design (no contract) locks nothing")
	bus.career.set_xp(ContractTiers.MAX_XP)
	bus._deal_board(4)
	bus.accept(str(bus.board[0].id))
	check(bus.locked_tier("lib:airport") == 0, "at the top tier everything is open")
	bus.queue_free()


func _upgrades() -> void:
	Flags.set_flag(ContractsBus.UNLOCK_FLAG, true)
	var bus := ContractsBus.new()
	add_child(bus)
	bus._deal_board(3)
	bus.career.money = 10000.0
	bus.buy("second_crew")
	check(not bus.career.has_upgrade("second_crew"), "an upgrade the firm cannot afford is refused")
	bus.career.money = 200000.0
	bus.buy("second_crew")
	check(bus.career.has_upgrade("second_crew") and is_equal_approx(bus.career.money, 140000.0), "buying the second crew costs 60,000")
	check(is_equal_approx(bus.effect("schedule_factor", 1.0), 0.85), "and makes builds 15% faster")
	bus.buy("second_crew")
	check(is_equal_approx(bus.career.money, 140000.0), "it is bought once")
	bus.buy("bulk_deal")
	check(not bus.career.has_upgrade("bulk_deal"), "a deal needs a material")
	bus.buy("bulk_deal", "masonry")
	check(bus.career.deal_material == "masonry", "a masonry deal")
	var model := Kit.house()
	bus.accept(str(bus.board[0].id))
	var plain := ContractValidator.assess(bus.active, model)
	var dealt := bus.assess(model)
	var mas := float((plain.totals.by_material as Dictionary).get("masonry", 0.0))
	check(mas > 0.0 and is_equal_approx(float(dealt.cost), float(plain.cost) - mas * 0.05), "the deal takes 5%% off the masonry (%s)" % ContractValidator.money(mas * 0.05))
	var data := bus.career.to_data()
	var other := ContractCareer.new()
	other.load_data(data)
	check(other.has_upgrade("second_crew") and other.deal_material == "masonry", "upgrades save and load")
	# The Firm page.
	var board := bus.make_board(null)
	add_child(board)
	await frames(2)
	var firm := board.find_child("FirmPage", true, false) as Button
	check(firm != null and firm.visible, "the wall screen has a Firm page")
	firm.pressed.emit()
	await frames(3)
	var rows := board.find_children("Upgrade_*", "", true, false)
	check(rows.size() == ContractCareer.DATA.UPGRADES.size(), "listing every upgrade")
	var survey := board.find_child("Upgrade_survey_kit", true, false)
	var buy := survey.find_child("Buy", true, false) as Button
	check(buy != null and not buy.disabled, "with a Buy button for one the firm can afford")
	buy.pressed.emit()
	await frames(3)
	check(bus.career.has_upgrade("survey_kit"), "Buy on the Firm page buys it")
	board.queue_free()
	bus.queue_free()
