class_name ServicesReport
extends RefCounted
## What the M&E consultant designed: the routes of every system, their length and cost,
## which rooms are powered and plumbed, and a plain-language account of what is wrong.
## Plain data, so the host can send it as an event and every peer holds the same report.
##
##   report.passed()                    # every room powered, every wet room plumbed
##   report.summary                     # one line for the panel
##   report.notes                       # "Bathroom (r4) has no hot water: ..."
##   report.system("power")             # {label, source, length, cost, holes, branches, unserved}
##   report.room("r4")                  # {name, type, wet, powered, plumbed, missing: [...]}
##   report.total_cost                  # GBP, every system
##   report.routes("waste")             # [[[x, y, z], ...], ...] polylines for an overlay
##
## A system: {label, source: {at: [x, y, z], level, room, how: "part" | "placed" | "auto",
## part?}, length (m), run_cost, hole_cost, point_cost, source_cost, cost, holes: {kind: n},
## branches: [{id, room, what, label, wc, level, length, cost, to_source, points}],
## unserved: [{id, room, what, label}]}. to_source counts runs across floors only.
## `id` in a branch is a fixture part id, a room id (a room's lighting and sockets, or a wet
## room with no fixtures yet) or "boiler".

var revision := -1
var cell := 0.5
var systems: Dictionary = {}
var rooms: Dictionary = {}
var notes: PackedStringArray = []
var warnings: PackedStringArray = []
var summary := ""
var total_cost := 0.0


func passed() -> bool:
	if rooms.is_empty():
		return false
	for rid: String in rooms:
		if not (rooms[rid].missing as Array).is_empty():
			return false
	return true


func system(id: String) -> Dictionary:
	return systems.get(id, {})


func room(id: String) -> Dictionary:
	return rooms.get(id, {})


## Rooms still missing a service: {room id: [system, ...]}.
func failures() -> Dictionary:
	var out := {}
	for rid: String in BuildingModel.sort_ids(rooms.keys()):
		if not (rooms[rid].missing as Array).is_empty():
			out[rid] = rooms[rid].missing.duplicate()
	return out


## Every branch of a system as a world-space polyline.
func routes(system_id: String) -> Array:
	var out: Array = []
	for b: Dictionary in system(system_id).get("branches", []):
		var line: Array = []
		for p: Array in b.points:
			line.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
		if line.size() > 1:
			out.append(line)
	return out


## True when the building has changed since this report was made.
func is_stale(model: BuildingModel) -> bool:
	return model == null or model.revision != revision


func to_dict() -> Dictionary:
	return {"revision": revision, "cell": cell, "systems": systems.duplicate(true), "rooms": rooms.duplicate(true),
		"notes": Array(notes), "warnings": Array(warnings), "summary": summary, "total_cost": total_cost}


static func from_dict(d: Dictionary) -> ServicesReport:
	var r := ServicesReport.new()
	r.revision = int(d.get("revision", -1))
	r.cell = float(d.get("cell", 0.5))
	r.systems = (d.get("systems", {}) as Dictionary).duplicate(true)
	r.rooms = (d.get("rooms", {}) as Dictionary).duplicate(true)
	r.notes = PackedStringArray(d.get("notes", []))
	r.warnings = PackedStringArray(d.get("warnings", []))
	r.summary = str(d.get("summary", ""))
	r.total_cost = float(d.get("total_cost", 0.0))
	return r


## Equal on every peer that holds the same report (JSON with sorted keys, hashed).
## The building revision is left out, so a saved and loaded copy of a building matches.
func digest() -> String:
	var d := to_dict()
	d.erase("revision")
	return JSON.stringify(_plain(d), "", true).sha256_text().substr(0, 16)


static func _plain(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k: Variant in v:
			out[str(k)] = _plain(v[k])
		return out
	if v is Array:
		var out: Array = []
		for x: Variant in v:
			out.append(_plain(x))
		return out
	if v is int:
		return float(v)
	return v
