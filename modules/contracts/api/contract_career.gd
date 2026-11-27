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
const DATA := preload("res://modules/contracts/internal/unlocks.gd")
## Unlocks by tier, beyond the building types (whose tiers are in the generator's building
## type table). id: "material:<id>" or "kind:<id>"; the wider tree (roof shapes, library
## groups, gear) is in internal/unlocks.gd TREE.
const UNLOCKS: Array = DATA.CORE

var money := START_MONEY
var xp := 0
## Finished contracts, oldest first: {brief_id, title, tier, passed, profit, xp, days}.
var history: Array = []
var unlocked: PackedStringArray = []
## Firm upgrades bought (ids from internal/unlocks.gd UPGRADES), and the bulk deal's material.
var upgrades: PackedStringArray = []
var deal_material := ""
## Clients the firm has built for: {name: record} (ContractClients).
var clients: Dictionary = {}


func _init() -> void:
	_unlock_due()


## Books a settled contract. Returns the ids unlocked by it.
func record(settlement: Dictionary) -> PackedStringArray:
	money += float(settlement.get("profit", 0.0))
	xp += maxi(0, int(settlement.get("xp", 0)))
	history.append({"brief_id": str(settlement.get("brief_id", "")), "title": str(settlement.get("title", "")),
			"tier": int(settlement.get("tier", 1)), "passed": bool(settlement.get("passed", false)),
			"profit": float(settlement.get("profit", 0.0)), "xp": int(settlement.get("xp", 0)), "days": int(settlement.get("days", 0))})
	var client := _client_of(settlement)
	if client != "":
		clients[client] = ContractClients.after(clients.get(client, {}), settlement)
	var fresh := _unlock_due()
	changed.emit()
	return fresh


## Books a walk-out against the client.
func record_abandon(brief: Dictionary) -> void:
	var client := str(brief.get("client", ""))
	if client != "":
		clients[client] = ContractClients.abandoned(clients.get(client, {}))
	changed.emit()


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


## Every unlock: materials and kinds, the wider tree, plus "type:<building type>" for each type.
static func all_unlocks() -> Array:
	var out: Array = UNLOCKS.duplicate(true) + DATA.TREE.duplicate(true)
	for t: String in ContractGenerator.TYPES:
		out.append({"tier": int(ContractGenerator.TYPES[t].tier), "id": "type:" + t, "label": str(ContractGenerator.TYPES[t].label)})
	return out


func to_data() -> Dictionary:
	return {"money": money, "xp": xp, "history": history.duplicate(true), "unlocked": Array(unlocked),
			"upgrades": Array(upgrades), "deal_material": deal_material, "clients": clients.duplicate(true)}


func load_data(data: Dictionary) -> void:
	money = float(data.get("money", START_MONEY))
	xp = maxi(0, int(data.get("xp", 0)))
	history = (data.get("history", []) as Array).duplicate(true) if data.get("history") is Array else []
	unlocked = PackedStringArray(data.get("unlocked", []))
	upgrades = PackedStringArray(data.get("upgrades", []))
	deal_material = str(data.get("deal_material", ""))
	clients = (data.get("clients", {}) as Dictionary).duplicate(true) if data.get("clients") is Dictionary else {}
	_unlock_due()
	changed.emit()


func _unlock_due() -> PackedStringArray:
	var fresh := PackedStringArray()
	for u: Dictionary in all_unlocks():
		if int(u.tier) <= tier() and not is_unlocked(str(u.id)):
			unlocked.append(str(u.id))
			fresh.append(str(u.id))
	return fresh


## The tier that opens an unlock id, 0 if no tier holds it back. "kind:<k>" also answers for
## the kind's roof shape and, unless it is a fixture, its materials (the lowest tier at which
## one of them is open).
static func tier_of(unlock_id: String, catalog: BuildingCatalog = null) -> int:
	var t := 0
	for u: Dictionary in all_unlocks():
		if str(u.id) == unlock_id:
			t = int(u.tier)
	if unlock_id.begins_with("kind:") and catalog != null:
		var kind := unlock_id.substr(5)
		if DATA.KIND_UNLOCK.has(kind):
			t = maxi(t, tier_of(str(DATA.KIND_UNLOCK[kind])))
		if catalog.has_kind(kind) and catalog.family_of(kind) != "fixture":
			var best := 99
			for m in catalog.materials_for(kind):
				best = mini(best, maxi(1, tier_of("material:" + m)))
			if best < 99:
				t = maxi(t, best)
	return t


func has_upgrade(upgrade_id: String) -> bool:
	return upgrade_id in upgrades


static func upgrade_row(upgrade_id: String) -> Dictionary:
	for u: Dictionary in DATA.UPGRADES:
		if str(u.id) == upgrade_id:
			return u
	return {}


## Why an upgrade cannot be bought now ("" when it can).
func cannot_buy(upgrade_id: String, option := "") -> String:
	var row := upgrade_row(upgrade_id)
	if row.is_empty():
		return "no such upgrade"
	if has_upgrade(upgrade_id):
		return "already bought"
	if money < float(row.price):
		return "costs %s" % ContractValidator.money(float(row.price))
	if str(row.get("option", "")) == "material" and option == "":
		return "pick a material"
	return ""


## Buys an upgrade (validated by the caller with cannot_buy).
func buy(upgrade_id: String, option := "") -> void:
	var row := upgrade_row(upgrade_id)
	money -= float(row.price)
	upgrades.append(upgrade_id)
	if str(row.get("option", "")) == "material":
		deal_material = option
	changed.emit()


## An upgrade effect's value: the bought upgrades' value for `name`, else `fallback`.
func effect(name: String, fallback: float = 0.0) -> float:
	for id in upgrades:
		var e: Dictionary = upgrade_row(id).get("effect", {})
		if e.has(name):
			return float(e[name])
	return fallback


static func _client_of(settlement: Dictionary) -> String:
	if settlement.has("client"):
		return str(settlement.client)
	var b: Variant = settlement.get("brief", {})
	return str((b as Dictionary).get("client", "")) if b is Dictionary else ""


static func _is_lockable(unlock_id: String) -> bool:
	for u: Dictionary in UNLOCKS:
		if str(u.id) == unlock_id:
			return true
	return false
