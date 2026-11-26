class_name StructureResult
extends RefCounted
## What one scenario did to every member and foundation. Utilisation is load divided by
## capacity: under AMBER is green, up to RED is amber, over RED has failed.

const AMBER := 0.7
const RED := 1.0
## Utilisation given to members with no path to a foundation.
const UNSUPPORTED := 99.0

const GREEN_STATUS := "green"
const AMBER_STATUS := "amber"
const RED_STATUS := "red"

var scenario_id := ""
var scenario_title := ""
## member id -> {"u": utilisation, "mode": "axial" | "bending" | "shear" | "unsupported",
##   "axial": kN, "moment": kN·m, "shear": kN, "lateral": bool (sideways load governs),
##   "direction": index into the scenario's directions or -1, "cantilever": bool,
##   "kind": String, "length": m, "part": building part id}
var members: Dictionary = {}
## anchor id -> {"u": utilisation, "mode": "bearing", "load": kN, "bearing": kN,
##   "part": foundation part id, or the node id}
var anchors: Dictionary = {}
## Node ids with no path to any foundation.
var unsupported_nodes: PackedStringArray = PackedStringArray()
## Total sideways force reaching the ground in the worst direction (kN).
var base_shear := 0.0
## Ids over RED, the most overloaded first: the order things would give way as the
## load rises.
var failures: PackedStringArray = PackedStringArray()


func passed() -> bool:
	return failures.is_empty()


func utilisation(id: String) -> float:
	if members.has(id):
		return members[id].u
	if anchors.has(id):
		return anchors[id].u
	return 0.0


func status(id: String) -> String:
	return status_for(utilisation(id))


static func status_for(u: float) -> String:
	if u > RED:
		return RED_STATUS
	if u >= AMBER:
		return AMBER_STATUS
	return GREEN_STATUS


## The highest utilisation of any member or foundation, and its id.
func worst() -> Dictionary:
	var best_id := ""
	var best_u := -1.0
	for dict: Dictionary in [members, anchors]:
		var ids := dict.keys()
		ids.sort()
		for id: String in ids:
			if float(dict[id].u) > best_u:
				best_u = dict[id].u
				best_id = id
	return {"id": best_id, "u": maxf(best_u, 0.0)}


## Fills failures from members and anchors (called by the solver).
func sort_failures() -> void:
	var over: Array = []
	for dict: Dictionary in [members, anchors]:
		for id: String in dict:
			if float(dict[id].u) > RED:
				over.append([float(dict[id].u), id])
	over.sort_custom(func(x: Array, y: Array) -> bool:
		return x[0] > y[0] or (x[0] == y[0] and x[1] < y[1]))
	failures = PackedStringArray()
	for e: Array in over:
		failures.append(e[1])


func to_dict() -> Dictionary:
	return {"scenario_id": scenario_id, "scenario_title": scenario_title,
			"members": _sorted_rows(members), "anchors": _sorted_rows(anchors),
			"unsupported_nodes": Array(unsupported_nodes), "base_shear": base_shear,
			"failures": Array(failures)}


static func from_dict(data: Dictionary) -> StructureResult:
	var r := StructureResult.new()
	r.scenario_id = str(data.get("scenario_id", ""))
	r.scenario_title = str(data.get("scenario_title", ""))
	r.members = (data.get("members", {}) as Dictionary).duplicate(true)
	r.anchors = (data.get("anchors", {}) as Dictionary).duplicate(true)
	r.unsupported_nodes = PackedStringArray(data.get("unsupported_nodes", []))
	r.base_shear = float(data.get("base_shear", 0.0))
	r.failures = PackedStringArray(data.get("failures", []))
	return r


## Keys sorted, so the same result always serialises the same.
static func _sorted_rows(d: Dictionary) -> Dictionary:
	var keys := d.keys()
	keys.sort()
	var out := {}
	for k: String in keys:
		var e: Dictionary = d[k]
		var fields := e.keys()
		fields.sort()
		var row := {}
		for f: String in fields:
			row[f] = e[f]
		out[k] = row
	return out
