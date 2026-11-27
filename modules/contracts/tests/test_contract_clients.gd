extends ModuleTest
## Clients with memory (flag contracts.clients): standing moves with how the firm treated a
## client, known clients come back to the board, standing changes the fee, the time and the
## checks, a Patron brings work a tier up, and it all saves.
##   tools/run_tests.sh contracts


func run_tests() -> void:
	var saved := Flags.all()
	_standing()
	_effects()
	_board()
	_career()
	Flags.use(saved)


func _standing() -> void:
	var r := ContractClients.after({}, {"passed": true, "late_days": 0})
	check(ContractClients.label(r) == "Satisfied" and int(r.jobs) == 1, "a first job done well leaves a client satisfied")
	r = ContractClients.after(r, {"passed": true, "late_days": 0})
	check(ContractClients.label(r) == "Trusting", "a second makes them trusting")
	r = ContractClients.after(r, {"passed": true, "late_days": 4})
	check(ContractClients.label(r) == "Trusting" and int(r.late) == 1, "a late handover holds the standing")
	r = ContractClients.after(r, {"passed": true})
	r = ContractClients.after(r, {"passed": true})
	r = ContractClients.after(r, {"passed": true})
	check(ContractClients.level(r) == ContractClients.PATRON, "and it tops out at Patron")
	r = ContractClients.after(r, {"passed": false})
	check(ContractClients.label(r) == "Trusting", "a failed building drops two steps")
	var w := ContractClients.abandoned(ContractClients.after({}, {"passed": false}))
	check(ContractClients.label(w) == "Wary" and int(w.abandoned) == 1, "but never below Wary once they know the firm")


func _effects() -> void:
	var b := ContractGenerator.generate(41, "bungalow", 2)
	var name := str(b.client)
	var wary := ContractClients.apply(b, {name: {"jobs": 1, "standing": ContractClients.WARY}})
	check(is_equal_approx(float(wary.fee), snappedf(float(b.fee) * 0.95, 500.0)), "a wary client pays 5% less")
	var structure := (wary.requirements as Array).filter(func(q: Dictionary) -> bool: return str(q.kind) == "structure")
	check(not structure.is_empty() and str(wary.client_note).contains("wary"), "and wants a passed stress test")
	var loyal := ContractClients.apply(b, {name: {"jobs": 4, "standing": 4}})
	check(float(loyal.fee) > float(b.fee) and int(loyal.deadline_days) > int(b.deadline_days), "a loyal client pays more and gives more time")
	check(ContractBriefing.text(loyal).contains("loyal clients"), "the briefing says so")
	check(ContractClients.apply(b, {"Someone else": {"standing": 4}}) == b, "a client the firm has not met is unchanged")


func _board() -> void:
	var board := ContractGenerator.board(7, 3, 5)
	var known := {}
	for cat: String in ContractGenerator.TYPES_SCRIPT.CLIENTS:
		known[str(ContractGenerator.TYPES_SCRIPT.CLIENTS[cat][0])] = {"jobs": 2, "standing": 3}
	Flags.set_flag(ContractClients.FLAG, false)
	check(ContractClients.apply_board(board, known, 7, 3) == board, "off, the board is unchanged")
	Flags.set_flag(ContractClients.FLAG, true)
	var returning := 0
	for seed in [7, 8, 9, 10]:
		for o: Dictionary in ContractClients.apply_board(ContractGenerator.board(seed, 3, 5), known, seed, 3):
			if o.has("client_standing"):
				returning += 1
				check(str(o.summary).begins_with(str(o.client)) or not ContractBrief.authored_brief(str(o.id)).is_empty(), "%s is named in the summary" % o.client)
	check(returning >= 4, "clients the firm knows come back (%d of 20)" % returning)
	check(ContractClients.apply_board(board, known, 7, 3) == ContractClients.apply_board(board, known, 7, 3), "the same seed deals the same board")
	var patron := {"The borough council": {"jobs": 6, "standing": ContractClients.PATRON}}
	var with := ContractClients.apply_board(board, patron, 7, 3)
	var extra: Dictionary = with[-1]
	check(with.size() == board.size() + 1 and bool(extra.get("patron", false)) and int(extra.tier) == 4 and str(extra.client) == "The borough council",
			"a Patron brings a job from the tier above")


func _career() -> void:
	var c := ContractCareer.new()
	c.record({"brief_id": "x", "passed": true, "xp": 100, "brief": {"client": "The Lindqvists"}})
	c.record_abandon({"client": "Hughes Homes"})
	check(ContractClients.label(c.clients["The Lindqvists"]) == "Satisfied" and ContractClients.label(c.clients["Hughes Homes"]) == "Wary",
			"the career books each client")
	var other := ContractCareer.new()
	other.load_data(c.to_data())
	check(other.clients.size() == 2 and int(other.clients["The Lindqvists"].passed) == 1, "client records save and load")
	var bus := ContractsBus.new()
	add_child(bus)
	bus.career.load_data(c.to_data())
	bus._deal_board(5)
	bus.accept(str(bus.board[0].id))
	var who := str(bus.active.client)
	bus.abandon()
	check(bus.career.clients.has(who), "walking out is remembered by %s" % who)
	bus.queue_free()
