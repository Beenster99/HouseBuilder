class_name ContractCareer
extends RefCounted
## The architecture firm across contracts: money, XP and its tier (ContractTiers), finished
## jobs and what has been unlocked. Completing contracts earns XP; each tier unlocks building
## types (ContractGenerator offers them) and materials and part kinds (the design room's
## palette asks is_kind_unlocked()). A tier, once reached, is never lost.
##
##   var career := ContractCareer.new()
##   var new_unlocks := career.record(settlement)   # after ContractPayout.settle
##   career.tier()                                  # 1..ContractTiers.top()
##   career.progress()                              # ContractTiers.progress(career.xp)
##   career.is_unlocked("type:primary_school")
##   career.is_kind_unlocked("truss", catalog)     # kind and its materials both allowed
##
## Sandbox ignores all of this: everything is open there.

signal changed

const START_MONEY := 250000.0
## Unlocks by tier, beyond the building types (whose tiers are in the generator's building
## type table). id: "material:<id>" or "kind:<id>".
const UNLOCKS := [
	{"tier": 1, "id": "material:timber", "label": "Timber"},
	{"tier": 1, "id": "material:masonry", "label": "Brick and block"},
	{"tier": 1, "id": "material:concrete", "label": "Reinforced concrete"},
	{"tier": 1, "id": "material:glass", "label": "Glazing"},
	{"tier": 1, "id": "material:ceramic", "label": "Sanitaryware"},
	{"tier": 3, "id": "material:steel", "label": "Structural steel"},
	{"tier": 3, "id": "kind:truss", "label": "Trusses"},
	{"tier": 4, "id": "kind:pile", "label": "Bored piles"},
	{"tier": 4, "id": "material:glulam", "label": "Glulam"},
	{"tier": 5, "id": "kind:curtain_wall", "label": "Curtain walling"},
	{"tier": 5, "id": "kind:raft", "label": "Raft foundations"},
]

var money := START_MONEY
var xp := 0
## Finished contracts, oldest first: {brief_id, title, tier, passed, profit, xp, days}.
var history: Array = []
var unlocked: PackedStringArray = []


func _init() -> void:
	_unlock_due()


## Books a settled contract. Returns the ids unlocked by it.
func record(settlement: Dictionary) -> PackedStringArray:
	money += float(settlement.get("profit", 0.0))
	xp += maxi(0, int(settlement.get("xp", 0)))
	history.append({"brief_id": str(settlement.get("brief_id", "")), "title": str(settlement.get("title", "")),
			"tier": int(settlement.get("tier", 1)), "passed": bool(settlement.get("passed", false)),
			"profit": float(settlement.get("profit", 0.0)), "xp": int(settlement.get("xp", 0)), "days": int(settlement.get("days", 0))})
	var fresh := _unlock_due()
	changed.emit()
	return fresh


func tier() -> int:
	return ContractTiers.tier_for(xp)


func progress() -> Dictionary:
	return ContractTiers.progress(xp)


## Sets the XP outright (the debug menu's Max XP). Unlocks what the new tier opens; going down
## re-locks what is above it, so a tester can step back through the tiers. Returns the ids
## newly unlocked.
func set_xp(value: int) -> PackedStringArray:
	xp = clampi(value, 0, ContractTiers.MAX_XP * 10)
	var t := tier()
	var keep := PackedStringArray()
	for u: Dictionary in all_unlocks():
		if int(u.tier) <= t and is_unlocked(str(u.id)):
			keep.append(str(u.id))
	unlocked = keep
	var fresh := _unlock_due()
	changed.emit()
	return fresh


## Takes XP away (abandoning a contract), never below the current tier's floor.
func lose_xp(amount: int) -> void:
	xp = maxi(int(ContractTiers.info(tier()).xp), xp - maxi(0, amount))
	changed.emit()


func is_unlocked(unlock_id: String) -> bool:
	return unlock_id in unlocked


## A part kind can be used: the kind is not locked and at least one of its materials is open.
func is_kind_unlocked(kind: String, catalog: BuildingCatalog) -> bool:
	if _is_lockable("kind:" + kind) and not is_unlocked("kind:" + kind):
		return false
	# Furniture and equipment are never held back by a structural material.
	if catalog.family_of(kind) == "fixture":
		return true
	for m in catalog.materials_for(kind):
		if is_material_unlocked(m):
			return true
	return false


func is_material_unlocked(material: String) -> bool:
	return not _is_lockable("material:" + material) or is_unlocked("material:" + material)


## Contracts passed in a row, newest last.
func streak() -> int:
	var n := 0
	for i in range(history.size() - 1, -1, -1):
		if not history[i].passed:
			break
		n += 1
	return n


## What the next unlock is: {tier, id, label} or {} when everything is open.
func next_unlock() -> Dictionary:
	var best := {}
	for u: Dictionary in all_unlocks():
		if not is_unlocked(str(u.id)) and (best.is_empty() or int(u.tier) < int(best.tier)):
			best = u
	return best


## Everything a tier opens: [{tier, id, label}].
static func unlocks_at(t: int) -> Array:
	return all_unlocks().filter(func(u: Dictionary) -> bool: return int(u.tier) == t)


## Every unlock: materials and kinds above, plus "type:<building type>" for each type.
static func all_unlocks() -> Array:
	var out: Array = UNLOCKS.duplicate(true)
	for t: String in ContractGenerator.TYPES:
		out.append({"tier": int(ContractGenerator.TYPES[t].tier), "id": "type:" + t, "label": str(ContractGenerator.TYPES[t].label)})
	return out


func to_data() -> Dictionary:
	return {"money": money, "xp": xp, "history": history.duplicate(true), "unlocked": Array(unlocked)}


func load_data(data: Dictionary) -> void:
	money = float(data.get("money", START_MONEY))
	xp = maxi(0, int(data.get("xp", 0)))
	history = (data.get("history", []) as Array).duplicate(true) if data.get("history") is Array else []
	unlocked = PackedStringArray(data.get("unlocked", []))
	_unlock_due()
	changed.emit()


func _unlock_due() -> PackedStringArray:
	var fresh := PackedStringArray()
	for u: Dictionary in all_unlocks():
		if int(u.tier) <= tier() and not is_unlocked(str(u.id)):
			unlocked.append(str(u.id))
			fresh.append(str(u.id))
	return fresh


static func _is_lockable(unlock_id: String) -> bool:
	for u: Dictionary in UNLOCKS:
		if str(u.id) == unlock_id:
			return true
	return false
