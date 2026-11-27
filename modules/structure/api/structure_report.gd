class_name StructureReport
extends RefCounted
## A stress test: one StructureResult per scenario, in the order they were run, plus the
## failure report in plain words. The host makes it and broadcasts to_dict(); every client
## rebuilds it with from_dict() and can compare digest() to know it has the same result.

## The StructureGraph revision this was solved from.
var graph_revision := 0
var results: Array[StructureResult] = []
## Plain-language lines: what failed, why, and what to try. Empty when everything passed.
var notes: PackedStringArray = PackedStringArray()
## One line for a HUD or toast.
var summary := ""
## Building part id -> highest utilisation over every scenario. Filled by compact(); when it
## is, results keep only the rows of what failed and of each scenario's worst member.
var parts: Dictionary = {}


func passed() -> bool:
	for r in results:
		if not r.passed():
			return false
	return true


func result(scenario_id: String) -> StructureResult:
	for r in results:
		if r.scenario_id == scenario_id:
			return r
	return null


## The first thing to give way: the most overloaded member or foundation in the first
## scenario that fails. {} when everything passes; else {"scenario", "id", "u"}.
func first_failure() -> Dictionary:
	for r in results:
		if not r.passed():
			return {"scenario": r.scenario_id, "id": r.failures[0], "u": r.utilisation(r.failures[0])}
	return {}


## Highest utilisation of a member or foundation across every scenario (what the stress
## overlay colours by).
func envelope(id: String) -> float:
	var u := 0.0
	for r in results:
		u = maxf(u, r.utilisation(id))
	return u


func status(id: String) -> String:
	return StructureResult.status_for(envelope(id))


## Every member or foundation that failed in any scenario, sorted.
func failed_ids() -> PackedStringArray:
	var seen := {}
	for r in results:
		for id in r.failures:
			seen[id] = true
	var out := PackedStringArray(seen.keys())
	out.sort()
	return out


## Highest utilisation of any member modelling a building part, across every scenario
## (a wall or a long beam is several members).
func part_envelope(part_id: String) -> float:
	if not parts.is_empty():
		return float(parts.get(part_id, 0.0))
	var u := 0.0
	for r in results:
		for dict: Dictionary in [r.members, r.anchors]:
			for id: String in dict:
				if str(dict[id].get("part", id)) == part_id:
					u = maxf(u, float(dict[id].u))
	return u


## Building parts with a failed member in any scenario, sorted.
func failed_parts() -> PackedStringArray:
	var seen := {}
	for r in results:
		for id in r.failures:
			var row: Dictionary = r.members.get(id, r.anchors.get(id, {}))
			seen[str(row.get("part", id))] = true
	var out := PackedStringArray(seen.keys())
	out.sort()
	return out


## The highest utilisation anywhere in any scenario.
func worst_utilisation() -> float:
	var u := 0.0
	for r in results:
		u = maxf(u, float(r.worst().u))
	return u


## What a contract brief checks: {"ok", "failures": part ids, "worst": utilisation,
## "scenario": id of the first scenario that fails, or ""}.
func brief_result() -> Dictionary:
	var first := first_failure()
	return {"ok": passed(), "failures": Array(failed_parts()), "worst": worst_utilisation(),
			"scenario": str(first.get("scenario", ""))}


func to_dict() -> Dictionary:
	var rs: Array = []
	for r in results:
		rs.append(r.to_dict())
	var out := {"graph_revision": graph_revision, "results": rs, "notes": Array(notes), "summary": summary}
	if not parts.is_empty():
		var keys := parts.keys()
		keys.sort()
		var sorted := {}
		for k: String in keys:
			sorted[k] = parts[k]
		out["parts"] = sorted
	return out


## A small copy for sending to every player after each edit: the verdict, notes, per-part
## utilisation (parts) and, per scenario, only the rows of what failed and of the worst
## member. Everything the overlay, panel and brief_result() read gives the same answer.
func compact() -> StructureReport:
	var out := StructureReport.new()
	out.graph_revision = graph_revision
	out.notes = notes
	out.summary = summary
	for r in results:
		for dict: Dictionary in [r.members, r.anchors]:
			for id: String in dict:
				var part := str(dict[id].get("part", id))
				out.parts[part] = maxf(float(out.parts.get(part, 0.0)), float(dict[id].u))
		var c := StructureResult.new()
		c.scenario_id = r.scenario_id
		c.scenario_title = r.scenario_title
		c.base_shear = r.base_shear
		c.failures = r.failures
		c.unsupported_nodes = r.unsupported_nodes
		var keep := Array(r.failures)
		keep.append(r.worst().id)
		for id: String in keep:
			if r.members.has(id):
				c.members[id] = r.members[id]
			elif r.anchors.has(id):
				c.anchors[id] = r.anchors[id]
		out.results.append(c)
	return out


static func from_dict(data: Dictionary) -> StructureReport:
	var rep := StructureReport.new()
	rep.graph_revision = int(data.get("graph_revision", 0))
	for r: Dictionary in data.get("results", []):
		rep.results.append(StructureResult.from_dict(r))
	rep.notes = PackedStringArray(data.get("notes", []))
	rep.summary = str(data.get("summary", ""))
	rep.parts = (data.get("parts", {}) as Dictionary).duplicate()
	return rep


## A fingerprint of the whole result (numbers to 4 decimal places): equal digests mean
## every client shows the same utilisation everywhere.
func digest() -> String:
	return _canon(to_dict()).md5_text()


static func _canon(v: Variant) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			var keys: Array = (v as Dictionary).keys()
			keys.sort()
			var parts := PackedStringArray()
			for k in keys:
				parts.append("%s:%s" % [str(k), _canon(v[k])])
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var parts := PackedStringArray()
			for e in v:
				parts.append(_canon(e))
			return "[" + ",".join(parts) + "]"
		TYPE_FLOAT:
			return "%.4f" % v
	return str(v)
