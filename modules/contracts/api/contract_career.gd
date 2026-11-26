class_name ContractCareer
extends RefCounted
## The firm's standing across contracts: money, reputation, finished jobs and what has been
## unlocked. Reputation unlocks building types (ContractGenerator offers them) and
## materials and part kinds (the design room's palette asks is_kind_unlocked()).
##
##   var career := ContractCareer.new()
##   var new_unlocks := career.record(settlement)   # after ContractPayout.settle
##   career.is_unlocked("type:primary_school")
##   career.is_kind_unlocked("truss", catalog)     # kind and its materials both allowed
##
## Sandbox ignores all of this: everything is open there.

signal changed

const START_MONEY := 250000.0
## Unlocks by reputation, beyond the building types (whose thresholds are in the generator's
## building type table). id: "material:<id>" or "kind:<id>".
const UNLOCKS := [
	{"rep": 0, "id": "material:timber", "label": "Timber"},
	{"rep": 0, "id": "material:masonry", "label": "Brick and block"},
	{"rep": 0, "id": "material:concrete", "label": "Reinforced concrete"},
	{"rep": 0, "id": "material:glass", "label": "Glazing"},
	{"rep": 0, "id": "material:ceramic", "label": "Sanitaryware"},
	{"rep": 8, "id": "material:steel", "label": "Structural steel"},
	{"rep": 15, "id": "kind:truss", "label": "Trusses"},
	{"rep": 15, "id": "kind:pile", "label": "Bored piles"},
	{"rep": 20, "id": "material:glulam", "label": "Glulam"},
	{"rep": 30, "id": "kind:curtain_wall", "label": "Curtain walling"},
	{"rep": 30, "id": "kind:raft", "label": "Raft foundations"},
]

var money := START_MONEY
var reputation := 0
## Finished contracts, oldest first: {brief_id, title, passed, profit, reputation, days}.
var history: Array = []
var unlocked: PackedStringArray = []


func _init() -> void:
	_unlock_due()


## Books a settled contract. Returns the ids unlocked by it.
func record(settlement: Dictionary) -> PackedStringArray:
	money += float(settlement.get("profit", 0.0))
	reputation = maxi(0, reputation + int(settlement.get("reputation", 0)))
	history.append({"brief_id": str(settlement.get("brief_id", "")), "title": str(settlement.get("title", "")),
			"passed": bool(settlement.get("passed", false)), "profit": float(settlement.get("profit", 0.0)),
			"reputation": int(settlement.get("reputation", 0)), "days": int(settlement.get("days", 0))})
	var fresh := _unlock_due()
	changed.emit()
	return fresh


func is_unlocked(unlock_id: String) -> bool:
	return unlock_id in unlocked


## A part kind can be used: the kind is not locked and at least one of its materials is open.
func is_kind_unlocked(kind: String, catalog: BuildingCatalog) -> bool:
	if _is_lockable("kind:" + kind) and not is_unlocked("kind:" + kind):
		return false
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


## What the next unlock is: {rep, id, label} or {} when everything is open.
func next_unlock() -> Dictionary:
	var best := {}
	for u: Dictionary in all_unlocks():
		if not is_unlocked(str(u.id)) and (best.is_empty() or int(u.rep) < int(best.rep)):
			best = u
	return best


## Every unlock: materials and kinds above, plus "type:<building type>" for each type.
static func all_unlocks() -> Array:
	var out: Array = UNLOCKS.duplicate(true)
	for t: String in ContractGenerator.TYPES:
		out.append({"rep": int(ContractGenerator.TYPES[t].rep), "id": "type:" + t, "label": str(ContractGenerator.TYPES[t].label)})
	return out


func to_data() -> Dictionary:
	return {"money": money, "reputation": reputation, "history": history.duplicate(true), "unlocked": Array(unlocked)}


func load_data(data: Dictionary) -> void:
	money = float(data.get("money", START_MONEY))
	reputation = int(data.get("reputation", 0))
	history = (data.get("history", []) as Array).duplicate(true) if data.get("history") is Array else []
	unlocked = PackedStringArray(data.get("unlocked", []))
	_unlock_due()
	changed.emit()


func _unlock_due() -> PackedStringArray:
	var fresh := PackedStringArray()
	for u: Dictionary in all_unlocks():
		if int(u.rep) <= reputation and not is_unlocked(str(u.id)):
			unlocked.append(str(u.id))
			fresh.append(str(u.id))
	return fresh


static func _is_lockable(unlock_id: String) -> bool:
	for u: Dictionary in UNLOCKS:
		if str(u.id) == unlock_id:
			return true
	return false
