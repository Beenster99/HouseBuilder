extends ModuleTest
## The requirement validator against the plan's three briefs: a sound house, school and
## police station pass, and each kind of shortfall fails with a reason and a tip.
##   tools/run_tests.sh contracts

const Kit := preload("res://modules/contracts/tests/building_kit.gd")
const C := preload("res://modules/building/api/building_commands.gd")


func run_tests() -> void:
	_house()
	_school()
	_police()
	_limits()
	_wording()


func _house() -> void:
	var brief := ContractBrief.authored_brief("house_detached_3bed")
	check(not brief.is_empty(), "the house brief is there")
	var m := Kit.house()
	var a := ContractValidator.assess(brief, m)
	check(a.ok, "the test house meets the house brief: %s" % a.summary)
	check(a.cost < 180000.0 and a.cost > 100000.0, "and comes in under its 180k budget (%s)" % ContractValidator.money(a.cost))
	check(a.passed == a.total and a.total == 12, "all 12 requirements pass, the roof, walls and foundations included")
	var timber_only := brief.duplicate(true)
	for r: Dictionary in timber_only.requirements:
		if str(r.kind) == "materials":
			r["allowed"] = ["timber"]
	var mat := _item(ContractValidator.assess(timber_only, Kit.house()), "materials")
	check(not mat.ok and "brick and block" in str(mat.detail) and "timber" in str(mat.tip), "a structure in the wrong material fails and says which: %s" % mat.detail)
	# Lose a bedroom: the bedrooms requirement fails and says what to do.
	var bed := ""
	for rid: String in m.rooms:
		if str(m.rooms[rid].type) == "bedroom":
			bed = rid
	m.apply(C.retag(bed, "study"))
	a = ContractValidator.assess(brief, m)
	var item := _item(a, "bedrooms")
	check(not a.ok and not item.ok and is_equal_approx(item.progress, 2.0 / 3.0), "two bedrooms of three: two thirds done")
	check("1 more bedroom to paint" in str(item.detail), "it says one more bedroom is needed: %s" % item.detail)
	check(_item(a, "study").ok and _item(a, "study").bonus > 0.0, "and the new study earns its bonus goal")
	check(a.summary.begins_with("11 of 12 requirements met"), "the summary leads with what is left: %s" % a.summary)
	m.apply(C.retag(bed, "bedroom"))
	# Every brief needs a roof, an enclosed envelope and foundations.
	var bare := Kit.house()
	for pid: String in bare.parts.keys():
		if bare.catalog.family_of(str(bare.parts[pid].kind)) == "roof":
			bare.apply(C.delete([pid]))
	var wt := _item(ContractValidator.assess(brief, bare), "weathertight")
	check(not wt.ok and "No roof over" in str(wt.detail) and "roof" in str(wt.tip), "a building with no roof is never finished: %s" % wt.detail)
	var open := Kit.house()
	var side := ""
	for pid: String in open.parts_on(0):
		var e: Dictionary = open.parts[pid]
		if open.catalog.family_of(str(e.kind)) == "wall" and float(e.a[2]) == 8.0 and float(e.b[2]) == 8.0:
			side = pid
	open.apply(C.delete([side]))
	wt = _item(ContractValidator.assess(brief, open), "weathertight")
	check(not wt.ok and "open to the weather" in str(wt.detail), "nor one with a side wall missing: %s" % wt.detail)
	var floating := Kit.house()
	for pid: String in floating.parts.keys():
		if floating.catalog.family_of(str(floating.parts[pid].kind)) == "foundation":
			floating.apply(C.delete([pid]))
	var fd := _item(ContractValidator.assess(brief, floating), "foundations")
	check(not fd.ok and "nothing under them" in str(fd.detail) and "raft" in str(fd.tip), "nor one with no foundations: %s" % fd.detail)
	floating.apply(C.place_part("raft", 0, {"outline": C.rect(0, 0, 10, 8)}, "concrete"))
	check(_item(ContractValidator.assess(brief, floating), "foundations").ok, "a raft under it is enough")
	# A third storey breaks the height rule.
	m.apply(C.add_level(3.0))
	m.apply(C.place_room("bedroom", 2, C.rect(0, 0, 3, 3)))
	a = ContractValidator.assess(brief, m)
	check(not _item(a, "storeys").ok and "3 storeys used" in str(_item(a, "storeys").detail), "three storeys break the two-storey limit")


func _school() -> void:
	var brief := ContractBrief.authored_brief("school_primary_8")
	var m := Kit.school()
	var a := ContractValidator.assess(brief, m)
	check(a.ok, "the test school meets the school brief: %s" % a.summary)
	check(_item(a, "lift").ok and "no lift needed" in str(_item(a, "lift").detail), "one storey needs no lift")
	# Shrink a classroom below 30 places.
	var first := ""
	for rid in BuildingModel.sort_ids(m.rooms.keys()):
		if str(m.rooms[rid].type) == "classroom":
			first = rid
			break
	m.apply(C.set_fields(first, {"outline": C.rect(0, 0, 8, 7)}))
	a = ContractValidator.assess(brief, m)
	var cls := _item(a, "classrooms")
	check(not cls.ok and "takes 28" in str(cls.detail), "a 56 m2 classroom takes only 28: %s" % cls.detail)
	check("60 m2" in str(cls.tip), "and the tip says how big it must be: %s" % cls.tip)
	# Desks count too: 30 pupil desks make it a class of 30 again.
	Kit.furnish(m, "classroom", "desk_pupil", 30)
	a = ContractValidator.assess(brief, m)
	check(_item(a, "classrooms").ok, "furnished with 30 desks, every classroom takes 30")
	# Take away the fire doors: the far end is too far from a way out.
	for pid in m.parts_of_family("opening"):
		if str(m.parts[pid].kind) == "door_fire":
			m.apply(C.delete([pid]))
	for rid: String in m.rooms.keys():
		if str(m.rooms[rid].type) == "fire_exit":
			m.apply(C.delete([rid]))
	# Only the main entrance is left, mid-way along the front: the far corners are over 20 m.
	for r: Dictionary in brief.requirements:
		if str(r.id) == "exits":
			r["value"] = 20.0
	a = ContractValidator.assess(brief, m)
	var ex := _item(a, "exits")
	check(not ex.ok and "too far from a way out" in str(ex.detail), "with only the main door, some rooms are over 20 m out: %s" % ex.detail)
	check(not str(ex.tip).is_empty(), "with a tip to add one")


func _police() -> void:
	var brief := ContractBrief.authored_brief("police_station_town")
	var m := Kit.police()
	var a := ContractValidator.assess(brief, m)
	check(a.ok, "the test police station meets its brief: %s" % a.summary)
	m.apply(C.place_room("custody_cell", 0, C.rect(26, 3, 3, 3)))
	a = ContractValidator.assess(brief, m)
	check(not _item(a, "secure").ok and "4 secure doors for 5 cells" in str(_item(a, "secure").detail), "a fifth cell needs a fifth secure door")
	var far := C.place_room("custody_cell", 0, C.rect(27, 12, 3, 3))
	m.apply(far)
	a = ContractValidator.assess(brief, m)
	check(not _item(a, "near_desk").ok, "a cell at the far end is too far from the custody desk: %s" % _item(a, "near_desk").tip)
	var no_vehicle := Kit.police()
	for pid in no_vehicle.parts_of_family("opening"):
		if str(no_vehicle.parts[pid].kind) == "door_vehicle":
			no_vehicle.apply(C.delete([pid]))
	check(not _item(ContractValidator.assess(brief, no_vehicle), "vehicle_door").ok, "no vehicle door, no pass")


func _limits() -> void:
	var m := Kit.house()
	var brief := {"id": "t", "budget": 100000.0, "fee": 110000.0, "requirements": [
		{"id": "budget", "kind": "budget"},
		{"id": "height", "kind": "max_height", "value": 6.0},
		{"id": "foot", "kind": "max_footprint", "value": 50.0},
		{"id": "plot", "kind": "within_plot"},
		{"id": "struct", "kind": "structure"},
		{"id": "cap", "kind": "capacity", "types": ["bedroom"], "value": 2},
		{"id": "area", "kind": "floor_area", "min": 100.0},
	], "site": {"plot": [[-1, -1], [9, -1], [9, 9], [-1, 9]]}}
	var a := ContractValidator.assess(brief, m)
	var bud := _item(a, "budget")
	check(not bud.ok and "Cut £" in str(bud.tip), "over budget says how much to cut: %s" % bud.tip)
	check(not _item(a, "height").ok, "a two-storey pitched house is taller than 6 m")
	check(not _item(a, "foot").ok, "its 80 m2 ground floor is over a 50 m2 footprint")
	check(not _item(a, "plot").ok, "a 10 m house does not fit a 10 m plot from -1 to 9")
	check(not _item(a, "struct").ok and "Run the stress test" in str(_item(a, "struct").tip), "untested structure asks for a stress test")
	a = ContractValidator.assess(brief, m, {"ok": true, "failures": []})
	check(_item(a, "struct").ok, "a passed stress test passes it")
	a = ContractValidator.assess(brief, m, {"ok": false, "failures": ["p3", "p4"], "scenario": "storm"})
	check("2 members fail in the storm case" in str(_item(a, "struct").detail), "a failed one says how many and when")
	check(_item(a, "cap").ok, "the double bed sleeps two")
	check(_item(a, "area").ok, "over 100 m2 of rooms")


func _wording() -> void:
	var cat := BuildingCatalog.default_catalog()
	check(ContractBrief.describe({"kind": "rooms", "type": "classroom", "count": 8, "capacity": 30}, cat) == "8 classrooms for 30 each", "rooms read naturally")
	check(ContractBrief.describe({"kind": "rooms", "type": "toilet_block", "count": 2}, cat) == "2 toilets", "plural names stay plural")
	check(ContractBrief.describe({"kind": "rooms", "type": "library", "count": 2}, cat) == "2 libraries", "y becomes ies")
	check(ContractValidator.money(1234567.4) == "£1,234,567" and ContractValidator.money(-950.0) == "-£950", "money reads as pounds")


func _item(a: Dictionary, item_id: String) -> Dictionary:
	for it: Dictionary in a.items:
		if str(it.id) == item_id:
			return it
	return {"ok": false, "progress": 0.0, "detail": "missing", "tip": "", "bonus": 0.0}
