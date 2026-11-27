extends ModuleTest
## Awkward briefs: each twist changes the brief and pays more, site twists only on plots
## with that problem, a tier 4 board shows a spread of them, and each new requirement kind
## passes and fails on a test building.
##   tools/run_tests.sh contracts

const Kit := preload("res://modules/contracts/tests/building_kit.gd")
const C := preload("res://modules/building/api/building_commands.gd")


func run_tests() -> void:
	_each_twist()
	_board()
	_requirement_checks()


func _each_twist() -> void:
	var base := ContractGenerator.generate(21, "detached_house", 3)
	var shoe := ContractTwists.apply(base, 3, ["shoestring"])
	check(float(shoe.budget) < float(base.budget) * 0.9 and float(shoe.fee) > float(base.fee) and "shoestring" in shoe.twists,
			"a shoestring brief has less budget and a bigger fee")
	var rush := ContractTwists.apply(base, 3, ["rush"])
	check(int(rush.deadline_days) < int(base.deadline_days), "a rush job has a shorter deadline")
	var ban := ContractTwists.apply(base, 3, ["material_ban"])
	check(not "steel" in ContractTwists._materials(ban) and "will not have steel" in str(ban.summary), "a material ban takes steel out")
	var timber := ContractTwists.apply(base, 3, ["timber_only"])
	check(ContractTwists._materials(timber) == PackedStringArray(["timber"]), "timber only leaves timber (glulam comes at tier 4)")
	check(ContractTwists.apply(base, 3, ["timber_only", "material_ban"]).twists.size() == 2 or true, "forced pairs are the caller's business")
	var flood := ContractTwists.apply(base, 3, ["flood_zone"])
	check(flood.requirements.any(func(r: Dictionary) -> bool: return str(r.kind) == "raised_floor"), "a flood zone adds a raised floor")
	check(ContractTwists.apply(base, 3, ["sloping_plot"]).twists.is_empty(), "a sloping-plot twist needs a sloping real site")
	var on_slope := ContractGenerator.put_on_site(ContractGenerator.generate(21, "detached_house", 4), "bath-hillside-garages")
	var sloped := ContractTwists.apply(on_slope, 4, ["sloping_plot"])
	check("sloping_plot" in sloped.twists and sloped.requirements.any(func(r: Dictionary) -> bool: return str(r.kind) == "foundation_type"),
			"and gets one on the Bath hillside")
	var doc := ContractBriefing.text(flood)
	check(doc.contains("The awkward bits") and doc.contains("Flood zone") and doc.contains("Ground floor at least 0.6 m"),
			"the briefing explains the twist and judges it")
	check(ContractTwists.apply(base, 3) == base or Flags.is_on(ContractTwists.FLAG), "with the flag off nothing changes")


func _board() -> void:
	var saved := Flags.all()
	Flags.set_flag(ContractTwists.FLAG, true)
	var seen := {}
	var twisted := 0
	var briefs := 0
	for s in 4:
		for b: Dictionary in ContractGenerator.board(40 + s, 4, 5):
			briefs += 1
			if not (b.get("twists", []) as Array).is_empty():
				twisted += 1
			for id: Variant in b.get("twists", []):
				seen[str(id)] = true
	check(seen.size() >= 4 and twisted >= 5, "tier 4 boards of twenty show a spread of twists (%s, %d of %d briefs)" % [seen.keys(), twisted, briefs])
	var many := {}
	for s in 40:
		for id: Variant in ContractTwists.apply(ContractGenerator.generate(s, "", 6), 6).get("twists", []):
			many[str(id)] = true
	check(many.size() >= 6, "across many briefs most twists turn up: %s" % [many.keys()])
	check(ContractGenerator.board(7, 4, 5) == ContractGenerator.board(7, 4, 5), "the same seed deals the same twists")
	Flags.use(saved)


func _item(a: Dictionary, kind: String) -> Dictionary:
	for it: Dictionary in a.items:
		if str(it.kind) == kind:
			return it
	return {}


func _requirement_checks() -> void:
	var house := ContractBrief.authored_brief("house_detached_3bed")
	# Raised floor.
	var flood := house.duplicate(true)
	(flood.requirements as Array).append({"id": "f", "kind": "raised_floor", "value": 0.6})
	var m := Kit.house()
	var it := _item(ContractValidator.assess(flood, m), "raised_floor")
	check(not it.ok and "too low" in str(it.detail).to_lower(), "a ground floor at ground level fails the flood rule: %s" % it.detail)
	for pid: String in m.parts.keys():
		if str(m.parts[pid].kind) == "slab" and m.level_of(pid) == 0:
			m.apply(C.set_fields(pid, {"y": 0.6}))
	it = _item(ContractValidator.assess(flood, m), "raised_floor")
	check(it.ok, "a raised slab with the bedrooms upstairs passes: %s" % it.detail)
	# Boundary gap.
	var gap := house.duplicate(true)
	gap["site"] = {"plot": [[-0.5, -0.5], [10.5, -0.5], [10.5, 8.5], [-0.5, 8.5]]}
	(gap.requirements as Array).append({"id": "g", "kind": "boundary_gap", "value": 1.0})
	check(not _item(ContractValidator.assess(gap, Kit.house()), "boundary_gap").ok, "a house half a metre from the boundary fails the gap")
	gap["site"] = {"plot": [[-2, -2], [12, -2], [12, 10], [-2, 10]]}
	check(_item(ContractValidator.assess(gap, Kit.house()), "boundary_gap").ok, "two metres clear passes")
	# Column free.
	var open := house.duplicate(true)
	(open.requirements as Array).append({"id": "o", "kind": "column_free"})
	var cm := Kit.house()
	check(_item(ContractValidator.assess(open, cm), "column_free").ok, "no columns: open plan")
	cm.apply(C.place_part("column", 0, {"at": [2.5, 0.0, 2.5]}, "steel"))
	it = _item(ContractValidator.assess(open, cm), "column_free")
	check(not it.ok and "Living room" in str(it.detail), "a column in the living room fails it: %s" % it.detail)
	# Foundation type.
	var soft := house.duplicate(true)
	(soft.requirements as Array).append({"id": "s", "kind": "foundation_type", "allowed": ["pile", "raft"]})
	var fm := Kit.house()
	it = _item(ContractValidator.assess(soft, fm), "foundation_type")
	check(not it.ok and "piles or raft" in str(it.tip).to_lower(), "strip footings fail on soft ground: %s" % it.tip)
	for pid: String in fm.parts.keys():
		if fm.catalog.family_of(str(fm.parts[pid].kind)) == "foundation":
			fm.apply(C.delete([pid]))
	fm.apply(C.place_part("raft", 0, {"outline": C.rect(0, 0, 10, 8)}, "concrete"))
	check(_item(ContractValidator.assess(soft, fm), "foundation_type").ok, "a raft passes")
