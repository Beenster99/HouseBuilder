extends ModuleTest
## Contract unlocks in the designer: items, roof shapes and materials a firm has not unlocked
## are greyed with the tier that opens them and cannot be used (DesignBus.locked_tier, asked
## of the contracts module by name); with nothing locked everything is open.
##   tools/run_tests.sh design

const Fake := preload("res://modules/design/tests/fake_locks.gd")


func run_tests() -> void:
	var building := Modules.bus("building") as BuildingBus
	building.reset_data()
	var design := Modules.bus("design") as DesignBus
	var cat := building.model.catalog
	var fix := str(cat.kinds_in("fixture")[0])
	check(DesignBus.locked_tier("roof:hip") == 0 and DesignBus.kind_locked_tier(fix) == 0, "with no unlock tree everything is open")
	# A stand-in contracts module with some things locked.
	var real := Modules.bus("contracts")
	if real != null:
		real.name = "contracts_real"
	var fake: Node = Fake.new()
	fake.name = "contracts"
	fake.locks = {"kind:" + fix: 3, "roof:hip": 2}
	Modules.add_child(fake)
	check(DesignBus.locked_tier("roof:hip") == 2 and DesignBus.kind_locked_tier(fix) == 3, "the designer asks contracts what is locked")
	var found := -1
	for g: Dictionary in design.palette_groups("objects"):
		for it: Dictionary in g.items:
			if str(it.id) == fix:
				found = int(it.get("lock", 0))
	check(found == 3, "the palette marks a locked object with its tier: %d" % found)
	var s := DesignSession.new()
	add_child(s)
	s.setup(Modules.bus("multiplayer") as MultiplayerBus, building.model, building.sync)
	var said: Array = [""]
	s.status.connect(func(text: String, _bad: bool) -> void: said[0] = text)
	check(not s.use_kind(fix) and "tier 3" in str(said[0]), "a locked object cannot be picked: %s" % said[0])
	s.set_tool("roof")
	s.roof_form = "hip"
	s.press(Vector3(0, 0, 0))
	s.press(Vector3(6, 0, 4))
	check(building.model.parts_of_family("roof").is_empty() and "tier 2" in str(said[0]), "nor a locked roof shape placed: %s" % said[0])
	s.roof_form = "gable"
	s.press(Vector3(0, 0, 0))
	s.press(Vector3(6, 0, 4))
	check(building.model.parts_of_family("roof").size() == 1, "an open one can")
	s.teardown()
	s.queue_free()
	fake.queue_free()
	Modules.remove_child(fake)
	if real != null:
		real.name = "contracts"
	check(Modules.bus("contracts") == real, "the real contracts module is back")
	building.reset_data()
	# End to end with the real contracts module: a tier 1 firm on a contract.
	if real != null and real.has_method("locked_tier"):
		var saved := Flags.all()
		Flags.set_flag("contracts.unlock_tree", true)
		real.call("_deal_board", 3)
		real.call("accept", str((real.get("board") as Array)[0].id))
		await frames(2)
		var hc := -1
		for g: Dictionary in design.palette_groups("objects"):
			if str(g.id) == "lib:healthcare" and not (g.items as Array).is_empty():
				hc = int((g.items as Array)[0].get("lock", 0))
		check(DesignBus.locked_tier("roof:hip") > 1 and (hc == -1 or hc > 1),
				"on a contract, a new firm's hipped roofs and medical kit are locked: roof tier %d, healthcare %d" % [DesignBus.locked_tier("roof:hip"), hc])
		real.call("abandon")
		await frames(2)
		check(DesignBus.locked_tier("roof:hip") == 0, "and with no contract taken, open again")
		Flags.use(saved)
		building.reset_data()
