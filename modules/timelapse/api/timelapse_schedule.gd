class_name TimelapseSchedule
extends RefCounted
## Turns a building into a construction schedule: which part is built on which day, by real
## build logic. Pure data and deterministic (same parts in, same schedule out, on every peer).
##
## Input: an Array of part Dictionaries, the shape the building api adapter produces:
##   {"id": "col_3", "kind": "column", "aabb": AABB(...), "supported_by": ["pad_1"],
##    "cost": 1200.0 (optional), "level": 1 (optional, else from the part's base height)}
## Output (build()):
##   {"tasks": [{id, kind, stage, level, start, end, cost, aabb, shape}, ...]  ordered by start,
##    "days": total days, "cost": total cost, "crews": crews used,
##    "stages": {stage: [first start, last end]}, "levels": number of storeys,
##    "start_date": "YYYY-MM-DD"}
## Site work (clearance, excavation, landscaping) is added as tasks with ids "site:*".
##
## Rules: a part starts once everything it rests on is finished; on each storey, cladding,
## services and fit-out wait for that storey's frame and floor; the roof waits for the whole
## frame; fit-out waits for the roof (weather-tight). A fixed number of crews work at once,
## so big jobs take longer. Durations are crew-days from the part's kind and size.

const STAGES: PackedStringArray = ["site", "foundation", "frame", "floor", "envelope", "roof",
		"services", "fitout", "landscape"]
const KIND_STAGE := {
	"foundation": "foundation", "footing": "foundation", "pad": "foundation", "pile": "foundation",
	"strip": "foundation", "raft": "foundation",
	"column": "frame", "beam": "frame", "brace": "frame", "truss": "frame", "frame": "frame",
	"slab": "floor", "floor": "floor",
	"wall": "envelope", "window": "envelope", "door": "envelope", "glazing": "envelope",
	"cladding": "envelope", "opening": "envelope",
	"roof": "roof",
	"stairs": "services", "lift": "services", "services": "services",
	"fitout": "fitout", "furniture": "fitout", "fixture": "fitout", "prop": "fitout",
}
## Crew-days: base + per unit of the kind's measure (m of length, m2 of face, m3 of volume).
const DURATION := {
	"foundation": [4.0, 1.0, "volume"], "frame": [1.2, 0.25, "length"],
	"floor": [3.0, 0.12, "area"], "envelope": [1.5, 0.1, "area"], "roof": [3.0, 0.15, "area"],
	"services": [6.0, 0.0, "none"], "fitout": [4.0, 0.0, "none"],
}
## Default cost, GBP: base + per unit of the same measure, when a part carries no cost.
const RATE := {
	"foundation": [400.0, 220.0], "frame": [150.0, 95.0], "floor": [300.0, 85.0],
	"envelope": [120.0, 110.0], "roof": [500.0, 140.0], "services": [4000.0, 0.0],
	"fitout": [250.0, 0.0],
}
const STOREY_HEIGHT := 3.0
const DEFAULT_CREWS := 3
const DEFAULT_START := "2027-03-01"


## Options: {"crews": int, "start_date": "YYYY-MM-DD"}.
static func build(parts: Array, options: Dictionary = {}) -> Dictionary:
	var crews := maxi(1, int(options.get("crews", DEFAULT_CREWS)))
	var tasks: Dictionary = {}  # id -> task
	var order: Array[String] = []
	var ground := 0.0
	var first := true
	for p: Dictionary in parts:
		var box: AABB = p.get("aabb", AABB())
		if first or box.position.y < ground:
			ground = box.position.y
		first = false
	var footprint := AABB()
	first = true
	for p: Dictionary in parts:
		var id := str(p.get("id", ""))
		if id == "" or tasks.has(id):
			continue
		var kind := str(p.get("kind", "frame")).to_lower()
		var stage: String = KIND_STAGE.get(kind, "frame")
		var box: AABB = p.get("aabb", AABB())
		footprint = box if first else footprint.merge(box)
		first = false
		# Storeys count from ground level (y = 0); a roof belongs to the storey it caps.
		var base := maxf(box.position.y, 0.0) - (STOREY_HEIGHT * 0.5 if stage == "roof" else 0.0)
		var level := int(p.get("level", maxi(0, floori((base + 0.05) / STOREY_HEIGHT))))
		var cost := float(p.get("cost", -1.0))
		if cost < 0.0:
			cost = _rate(stage, box)
		var preds: Array[String] = []
		for s: Variant in p.get("supported_by", []):
			preds.append(str(s))
		tasks[id] = {"id": id, "kind": kind, "stage": stage, "level": level, "aabb": box,
				"material": str(p.get("material", "")), "family": str(p.get("family", kind)),
				"shape": p.get("shape", {}), "cost": cost, "duration": _duration(stage, box), "preds": preds}
		order.append(id)

	# Site work around the building.
	var area := footprint.size.x * footprint.size.z
	var site_box := AABB(Vector3(footprint.position.x, ground, footprint.position.z),
			Vector3(footprint.size.x, 0.0, footprint.size.z))
	_add_site(tasks, order, "site:clear", "site", 2.0 + area / 200.0, 800.0 + area * 6.0, [], site_box)
	_add_site(tasks, order, "site:dig", "site", 1.0 + area / 150.0, 600.0 + area * 18.0,
			["site:clear"], site_box)

	# Implicit build-logic dependencies.
	var by_stage_level: Dictionary = {}  # "stage:level" -> ids
	var frame_ids: Array[String] = []
	var roof_ids: Array[String] = []
	var max_level := 0
	for id in order:
		var t: Dictionary = tasks[id]
		var key := "%s:%d" % [t.stage, t.level]
		if not by_stage_level.has(key):
			by_stage_level[key] = []
		by_stage_level[key].append(id)
		if t.stage == "frame":
			frame_ids.append(id)
		elif t.stage == "roof":
			roof_ids.append(id)
		max_level = maxi(max_level, int(t.level))
	var all_ids: Array[String] = order.duplicate()
	for id in all_ids:
		var t: Dictionary = tasks[id]
		var preds: Array[String] = t.preds
		match t.stage:
			"foundation":
				preds.append("site:dig")
			"envelope", "services":
				preds.append_array(by_stage_level.get("frame:%d" % t.level, []))
				preds.append_array(by_stage_level.get("floor:%d" % t.level, []))
			"roof":
				preds.append_array(frame_ids)
			"fitout":
				preds.append_array(by_stage_level.get("envelope:%d" % t.level, []))
				preds.append_array(roof_ids)
		if t.stage in ["frame", "floor"] and preds.is_empty():
			preds.append("site:dig")
	_add_site(tasks, order, "site:landscape", "landscape", 3.0 + area / 300.0, 1500.0 + area * 10.0,
			order.duplicate(), site_box)

	# Clean predecessor lists: known ids only, no self, no repeats.
	var succs: Dictionary = {}
	var waiting: Dictionary = {}
	for id in order:
		var t: Dictionary = tasks[id]
		var clean: Array[String] = []
		for pid: String in t.preds:
			if pid != id and tasks.has(pid) and not clean.has(pid):
				clean.append(pid)
		t.preds = clean
		waiting[id] = clean.size()
		for pid in clean:
			if not succs.has(pid):
				succs[pid] = []
			succs[pid].append(id)

	# Serial schedule: take the ready task with the lowest priority, start it when its
	# predecessors are done and a crew is free.
	var ready: Array = []
	for id in order:
		if waiting[id] == 0:
			_insert_ready(ready, tasks[id])
	var crew_free: Array[float] = []
	crew_free.resize(crews)
	crew_free.fill(0.0)
	var done: Dictionary = {}
	var out: Array[Dictionary] = []
	while out.size() < order.size():
		var t: Dictionary
		if ready.is_empty():
			# A support loop: take the first unscheduled part anyway so nothing is lost.
			for id in order:
				if not done.has(id):
					t = tasks[id]
					break
			push_warning("TimelapseSchedule: support loop at %s" % t.id)
		else:
			t = ready.pop_front()
		if done.has(t.id):
			continue
		var earliest := 0.0
		for pid: String in t.preds:
			if done.has(pid):
				earliest = maxf(earliest, float(tasks[pid].end))
		var crew := 0
		for c in crews:
			if crew_free[c] < crew_free[crew]:
				crew = c
		var start := maxf(earliest, crew_free[crew])
		t.start = start
		t.end = start + float(t.duration)
		crew_free[crew] = t.end
		done[t.id] = true
		out.append(t)
		for sid: String in succs.get(t.id, []):
			waiting[sid] -= 1
			if waiting[sid] == 0 and not done.has(sid):
				_insert_ready(ready, tasks[sid])

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.start < b.start or (a.start == b.start and a.id < b.id))
	var stages: Dictionary = {}
	var days := 0.0
	var cost := 0.0
	var result_tasks: Array[Dictionary] = []
	for t in out:
		days = maxf(days, t.end)
		cost += t.cost
		var span: Array = stages.get(t.stage, [t.start, t.end])
		stages[t.stage] = [minf(span[0], t.start), maxf(span[1], t.end)]
		result_tasks.append({"id": t.id, "kind": t.kind, "stage": t.stage, "level": t.level,
				"start": t.start, "end": t.end, "cost": t.cost, "aabb": t.aabb,
				"material": str(t.get("material", "")), "family": str(t.get("family", t.kind)),
				"shape": t.get("shape", {})})
	return {"tasks": result_tasks, "days": days, "cost": cost, "crews": crews, "stages": stages,
			"levels": max_level + 1, "start_date": str(options.get("start_date", DEFAULT_START))}


## 0 before the task starts, 1 once it's done, linear between.
static func progress(task: Dictionary, day: float) -> float:
	var length := maxf(float(task.end) - float(task.start), 0.0001)
	return clampf((day - float(task.start)) / length, 0.0, 1.0)


## Money spent by `day`: finished tasks in full, running ones in part.
static func spent(schedule: Dictionary, day: float) -> float:
	var total := 0.0
	for t: Dictionary in schedule.get("tasks", []):
		if day <= float(t.start):
			break
		total += float(t.cost) * progress(t, day)
	return total


## The stages running on `day`, in build order.
static func active_stages(schedule: Dictionary, day: float) -> PackedStringArray:
	var out: PackedStringArray = []
	var spans: Dictionary = schedule.get("stages", {})
	for s in STAGES:
		if spans.has(s) and day >= float(spans[s][0]) and day < float(spans[s][1]):
			out.append(s)
	return out


## The calendar date `day` days after the start date, "YYYY-MM-DD".
static func date_on(schedule: Dictionary, day: float) -> String:
	var start := Time.get_unix_time_from_datetime_string(str(schedule.get("start_date", DEFAULT_START)))
	return Time.get_date_string_from_unix_time(start + int(floorf(day)) * 86400)


static func _insert_ready(ready: Array, t: Dictionary) -> void:
	var at := ready.bsearch_custom(t, _before)
	ready.insert(at, t)


## Priority: lower storeys first, then build stage, then bottom up, then by id.
static func _before(a: Dictionary, b: Dictionary) -> bool:
	if a.level != b.level and a.stage != "site" and b.stage != "site":
		return a.level < b.level
	var sa := STAGES.find(a.stage)
	var sb := STAGES.find(b.stage)
	if sa != sb:
		return sa < sb
	var ya: float = (a.aabb as AABB).position.y
	var yb: float = (b.aabb as AABB).position.y
	if not is_equal_approx(ya, yb):
		return ya < yb
	return a.id < b.id


static func _add_site(tasks: Dictionary, order: Array[String], id: String, stage: String,
		days: float, cost: float, preds: Array, box: AABB) -> void:
	var p: Array[String] = []
	for x: Variant in preds:
		p.append(str(x))
	tasks[id] = {"id": id, "kind": id.trim_prefix("site:"), "stage": stage, "level": 0,
			"aabb": box, "cost": cost, "duration": days, "preds": p}
	order.append(id)


static func _measure(kind: String, box: AABB) -> float:
	var s := box.size
	match kind:
		"volume":
			return s.x * s.y * s.z
		"length":
			return maxf(s.x, maxf(s.y, s.z))
		"area":
			var dims := [s.x, s.y, s.z]
			dims.sort()
			return float(dims[1]) * float(dims[2])
	return 0.0


static func _duration(stage: String, box: AABB) -> float:
	var d: Array = DURATION.get(stage, [1.0, 0.0, "none"])
	return float(d[0]) + float(d[1]) * _measure(str(d[2]), box)


static func _rate(stage: String, box: AABB) -> float:
	var d: Array = DURATION.get(stage, [1.0, 0.0, "none"])
	var r: Array = RATE.get(stage, [200.0, 0.0])
	return snappedf(float(r[0]) + float(r[1]) * _measure(str(d[2]), box), 1.0)
