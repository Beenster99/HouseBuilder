class_name ContractTwists
extends RefCounted
## Awkward briefs (flag contracts.twists): none, one or two twists from internal/twists.gd
## added to a generated brief, each changing how the building has to be designed and paying
## more for the trouble. The chance rises with the firm's tier; twists that clash are never
## paired; site twists are chosen only for a plot that has that problem.
##
##   ContractTwists.apply(brief, firm_tier)   # the brief with its twists (same seed, same twists)
##   ContractTwists.table()                   # the twist rows
##   brief.twists                             # ids added, [] for none

const FLAG := "contracts.twists"
const DATA := preload("res://modules/contracts/internal/twists.gd")


static func table() -> Array:
	return DATA.TWISTS


static func row(twist_id: String) -> Dictionary:
	for t: Dictionary in DATA.TWISTS:
		if str(t.id) == twist_id:
			return t
	return {}


## Adds twists to a brief rolled for a firm of `tier`. Off (the brief unchanged) while the
## flag is off; force skips the flag and the chance (tests).
static func apply(brief: Dictionary, tier: int, force: Array = []) -> Dictionary:
	if force.is_empty() and not Flags.is_on(FLAG):
		return brief
	var b := brief.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(b.get("seed", 0)), str(b.get("id", "")), "twists"])
	var picks: Array = []
	if not force.is_empty():
		for id: Variant in force:
			if not row(str(id)).is_empty() and _fits(b, row(str(id))):
				picks.append(row(str(id)))
	else:
		var chance: float = DATA.CHANCE[clampi(tier, 1, DATA.CHANCE.size() - 1)]
		var n := 0
		if rng.randf() < chance:
			n = 2 if rng.randf() < chance * DATA.SECOND_SHARE else 1
		var pool: Array = DATA.TWISTS.filter(func(t: Dictionary) -> bool: return int(t.tier) <= tier and _fits(b, t))
		while picks.size() < n and not pool.is_empty():
			var t: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
			picks.append(t)
			pool = pool.filter(func(o: Dictionary) -> bool:
				return str(o.id) != str(t.id) and not str(o.id) in t.clashes and not str(t.id) in o.clashes)
	var ids: Array = b.get("twists", [])
	for t: Dictionary in picks:
		if _apply_one(b, t):
			ids.append(str(t.id))
	b["twists"] = ids
	return b


static func _fits(b: Dictionary, t: Dictionary) -> bool:
	var spec: Dictionary = ContractGenerator.TYPES.get(str(b.get("type", "")), {})
	if t.has("max_storeys"):
		for r: Dictionary in b.get("requirements", []):
			if str(r.kind) == "max_storeys" and int(r.value) > int(t.max_storeys):
				return false
	if t.has("only"):
		var allowed := _materials(b)
		if not allowed.has("timber") or spec.is_empty():
			return false
	if t.has("ban") and _ban_target(b, t).is_empty():
		return false
	var needs := str(t.get("needs", ""))
	if needs == "":
		return true
	var site: Dictionary = b.get("site", {}) if b.get("site") is Dictionary else {}
	var sid := str(site.get("id", ""))
	if sid == "":
		return false
	if needs == "site":
		return true
	var pack := SitePool.open(sid)
	return pack != null and pack.ok() and pack.has_factor(needs)


static func _apply_one(b: Dictionary, t: Dictionary) -> bool:
	var sentence := str(t.sentence)
	if t.has("budget"):
		b["budget"] = snappedf(float(b.budget) * float(t.budget), 1000.0)
	if t.has("deadline"):
		b["deadline_days"] = maxi(20, int(snappedf(float(b.deadline_days) * float(t.deadline), 5.0)))
	if t.has("ban"):
		var gone := _ban_target(b, t)
		if gone.is_empty():
			return false
		for r: Dictionary in b.requirements:
			if str(r.kind) == "materials":
				r["allowed"] = Array(r.allowed).filter(func(m: Variant) -> bool: return str(m) != gone)
		sentence = sentence % ContractBrief.material_word(gone)
	if t.has("only"):
		var keep: Array = Array(t.only).filter(func(m: Variant) -> bool:
			return str(m) == "timber" or str(m) in ContractGenerator.structure_materials(str(b.type)))
		for r: Dictionary in b.requirements:
			if str(r.kind) == "materials":
				r["allowed"] = keep
	if t.has("require"):
		var req: Dictionary = (t.require as Dictionary).duplicate(true)
		req["id"] = str(t.id)
		req["twist"] = str(t.id)
		var reqs: Array = b.requirements
		var at := reqs.size()
		for i in reqs.size():
			if str(reqs[i].kind) == "budget":
				at = i
		reqs.insert(at, req)
	b["fee"] = snappedf(float(b.fee) * (1.0 + float(t.uplift)), 1000.0)
	b["summary"] = str(b.get("summary", "")) + " " + sentence
	var notes: Array = b.get("twist_notes", [])
	notes.append({"id": str(t.id), "label": str(t.label), "sentence": sentence, "uplift": float(t.uplift)})
	b["twist_notes"] = notes
	return true


static func _materials(b: Dictionary) -> PackedStringArray:
	for r: Dictionary in b.get("requirements", []):
		if str(r.kind) == "materials":
			return PackedStringArray(r.get("allowed", []))
	return PackedStringArray()


static func _ban_target(b: Dictionary, t: Dictionary) -> String:
	var allowed := _materials(b)
	if allowed.size() < 2:
		return ""
	for m: Variant in t.ban:
		if str(m) in allowed:
			return str(m)
	return ""
