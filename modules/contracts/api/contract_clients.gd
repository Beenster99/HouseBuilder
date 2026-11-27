class_name ContractClients
extends RefCounted
## Clients with memory (flag contracts.clients): every client the firm has built for keeps a
## standing, from New to Patron, that moves with how the firm treated them. Clients the firm
## knows come back to the board; a happy client pays more, gives more time and, as a Patron,
## offers work a tier above the firm; a wary one wants proof (a passed stress test) and pays less.
##
##   var rec := ContractClients.after(rec, settlement)    # a client's record after a handover
##   ContractClients.apply_board(board, career.clients, seed, tier)   # returning clients, effects
##   ContractClients.level(rec)                           # 0..5
##   ContractClients.label(rec)                           # "New" .. "Patron"
##
## A record: {jobs, passed, failed, late, abandoned, standing}. The standing starts at 0
## (New). A pass on time takes it to at least Satisfied and then up a step; a late pass holds
## it; a fail or a walk-out drops it two steps, but never below Wary once they know the firm.

const FLAG := "contracts.clients"
const LEVELS: PackedStringArray = ["New", "Wary", "Satisfied", "Trusting", "Loyal", "Patron"]
const NEW := 0
const WARY := 1
const SATISFIED := 2
const PATRON := 5
## By standing: fee multiplier, extra share of the deadline.
const FEE := [1.0, 0.95, 1.0, 1.03, 1.06, 1.10]
const TIME := [0.0, 0.0, 0.0, 0.05, 0.10, 0.15]
## Share of board briefs given to a client the firm knows (if one fits the category).
const RETURN_SHARE := 0.5


static func level(rec: Dictionary) -> int:
	return clampi(int(rec.get("standing", NEW)), NEW, PATRON)


static func label(rec: Dictionary) -> String:
	return LEVELS[level(rec)]


## A client's record after a settled contract (passed, late_days from ContractPayout).
static func after(rec: Dictionary, settlement: Dictionary) -> Dictionary:
	var r := _blank() if rec.is_empty() else rec.duplicate(true)
	r.jobs = int(r.jobs) + 1
	var s := level(r)
	if bool(settlement.get("passed", false)):
		r.passed = int(r.passed) + 1
		if int(settlement.get("late_days", 0)) > 0:
			r.late = int(r.late) + 1
			s = SATISFIED if s == NEW else s
		else:
			s = SATISFIED if s < SATISFIED else mini(PATRON, s + 1)
	else:
		r.failed = int(r.failed) + 1
		s = maxi(WARY, s - 2)
	r.standing = s
	return r


## A client's record after the firm walked out on them.
static func abandoned(rec: Dictionary) -> Dictionary:
	var r := _blank() if rec.is_empty() else rec.duplicate(true)
	r.jobs = int(r.jobs) + 1
	r.abandoned = int(r.abandoned) + 1
	r.standing = maxi(WARY, level(r) - 2)
	return r


## The board with returning clients and their standing applied (unchanged while the flag is
## off). clients: {name: record}. Deterministic in seed. A Patron adds one brief from the tier
## above the firm's, if there is one.
static func apply_board(board: Array, clients: Dictionary, seed: int, tier: int, force := false) -> Array:
	if not force and not Flags.is_on(FLAG):
		return board
	var out: Array = []
	for i in board.size():
		var b: Dictionary = board[i]
		out.append(apply(_returning(b, clients, hash([seed, i, "client"])), clients))
	if tier < ContractTiers.top():
		for name: String in clients:
			if level(clients[name]) == PATRON:
				var b := ContractGenerator.generate(hash([seed, name, "patron"]), _type_for(name, tier + 1, seed), tier + 1)
				if not b.is_empty():
					var pb := _rename(b, name)
					pb.patron = true
					out.append(apply(pb, clients))
				break
	return out


## One brief with its client's standing applied: fee, deadline, a stress test for a wary
## client, and the note for the briefing ("client_standing", "client_note").
static func apply(brief: Dictionary, clients: Dictionary) -> Dictionary:
	var name := str(brief.get("client", ""))
	if not clients.has(name):
		return brief
	var rec: Dictionary = clients[name]
	var s := level(rec)
	var b := brief.duplicate(true)
	b.client_standing = s
	b.fee = snappedf(float(b.fee) * float(FEE[s]), 500.0)
	if float(TIME[s]) > 0.0 and int(b.get("deadline_days", 0)) > 0:
		b.deadline_days = int(snappedf(float(b.deadline_days) * (1.0 + float(TIME[s])), 5.0))
	if s == WARY and not _has_kind(b.get("requirements", []), "structure"):
		(b.requirements as Array).insert(maxi(0, (b.requirements as Array).size() - 1), {"id": "client_structure", "kind": "structure"})
	b.client_note = note(rec)
	return b


## The briefing's sentence on the firm's history with a client.
static func note(rec: Dictionary) -> String:
	var jobs := int(rec.get("jobs", 0))
	var past := "You have built for them %s." % ("once before" if jobs == 1 else "%d times before" % jobs)
	match level(rec):
		WARY:
			return past + " They are wary after last time: they pay 5% less and want to see a passed stress test before they sign off."
		SATISFIED:
			return past + " They were happy with the work and are back for more."
		3:
			return past + " They trust the firm: the fee is 3% better and there is 5% more time."
		4:
			return past + " They are loyal clients: the fee is 6% better and there is 10% more time."
		PATRON:
			return past + " They are patrons of the firm: the fee is 10% better, there is 15% more time, and they bring work a tier above the firm's usual."
	return ""


static func _returning(b: Dictionary, clients: Dictionary, seed: int) -> Dictionary:
	if str(b.get("authored", "")) != "" or not ContractGenerator.TYPES.has(str(b.get("type", ""))):
		return b
	var cat := str(ContractGenerator.TYPES[str(b.type)].category)
	var known: Array = []
	for name: String in clients:
		if name in ContractGenerator.TYPES_SCRIPT.CLIENTS.get(cat, []):
			known.append(name)
	if known.is_empty() or str(b.get("client", "")) in known:
		return b
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	if rng.randf() >= RETURN_SHARE:
		return b
	known.sort()
	return _rename(b, str(known[rng.randi_range(0, known.size() - 1)]))


static func _rename(b: Dictionary, name: String) -> Dictionary:
	var out := b.duplicate(true)
	var old := str(out.get("client", ""))
	if old != "" and str(out.get("summary", "")).begins_with(old):
		out.summary = name + str(out.summary).substr(old.length())
	out.client = name
	return out


## A building type of `tier` in the client's category (else any type of that tier).
static func _type_for(name: String, tier: int, seed: int) -> String:
	var all := ContractGenerator.types_of_tier(tier)
	var mine := PackedStringArray()
	for t in all:
		if name in ContractGenerator.TYPES_SCRIPT.CLIENTS.get(str(ContractGenerator.TYPES[t].category), []):
			mine.append(t)
	var pool := mine if not mine.is_empty() else all
	return "" if pool.is_empty() else pool[absi(seed) % pool.size()]


static func _has_kind(reqs: Array, kind: String) -> bool:
	for r: Variant in reqs:
		if r is Dictionary and str(r.get("kind", "")) == kind:
			return true
	return false


static func _blank() -> Dictionary:
	return {"jobs": 0, "passed": 0, "failed": 0, "late": 0, "abandoned": 0, "standing": NEW}
