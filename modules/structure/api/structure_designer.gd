class_name StructureDesigner
extends RefCounted
## The structural engineer does the design work: it stress tests the building, then fixes
## what fails, round after round, until everything passes or it runs out of ideas. It only
## adds parts or makes them bigger; it never removes or moves what the players drew.
##
##   var plan := StructureDesigner.design(model)
##   if not plan.op.is_empty():
##       building.sync.edit(plan.op)     # one shared edit, one undo for everyone
##   print("\n".join(plan.notes))
##
## Fixes, cheapest first, one per failing part per round:
## - An overloaded member, wall or footing gets the next stronger section of its material.
## - A beam already at its biggest section gets a column under its middle, carried down to
##   the ground on columns with a pad footing.
## - A floor or flat roof already at its thickest gets a steel beam across its middle (its
##   short way), which halves its span; the beam is then sized, and propped, in later rounds.
## - A part nothing holds up gets columns under its ends (or its middle) down to a pad.
## - Sway and racking it can only fix by upsizing; past that it says where to brace.
##
## Returns {"op": a BuildingCommands.batch of every change ({} when nothing changed),
## "notes": plain-language lines, "before": StructureReport, "after": StructureReport,
## "passed": bool, "upsized": int, "added": int}.

const MAX_ROUNDS := 12
## Columns closer than this (in plan) to a wanted one count as already there.
const NEAR := 0.15
const LEVEL_TOL := 0.05
const COLUMN_MATERIAL := "steel"
const BEAM_MATERIAL := "steel"
## A floor or flat roof over this utilisation gets a beam under it before a thicker section.
const SPAN_FIRST := 1.6


static func design(model: BuildingModel, scenarios: Array[StructureScenario] = [], options: Dictionary = {}) -> Dictionary:
	var work := BuildingModel.from_data(model.to_data(), model.catalog)
	var before := StructureBuilding.stress_test(model, scenarios, options)
	var report := before
	var dos: Array = []
	var notes := PackedStringArray()
	var said := {}
	var upsized := 0
	var added := 0
	var stuck := {}  # part id -> true once nothing more can be done for it
	var was := {}  # part id -> its section before the first upsize
	for round_i in MAX_ROUNDS:
		if report.passed():
			break
		var fixes := 0
		var failing := _failing(report, work)
		for pid: String in BuildingModel.sort_ids(failing.keys()):
			if stuck.has(pid) or not work.parts.has(pid):
				continue
			var row: Dictionary = failing[pid]
			var got := _fix(work, pid, row)
			if got.ops.is_empty():
				stuck[pid] = true
				if got.note != "" and not said.has(got.note):
					said[got.note] = true
					notes.append(got.note)
				continue
			for op: Dictionary in got.ops:
				if str(op.op) == "set" and not was.has(pid):
					was[pid] = str(work.parts[pid].get("section", ""))
				var r := work.apply(op)
				if r.is_empty():
					continue
				dos.append(r.do)
				if str(op.op) == "add":
					added += 1
				else:
					upsized += 1
			fixes += 1
			if got.get("added", false) and got.note != "" and not said.has(got.note):
				said[got.note] = true
				notes.append(got.note)
		if fixes == 0:
			break
		report = StructureBuilding.stress_test(work, scenarios, options)
	var head := ""
	if before.passed():
		head = "Nothing to fix: the structure already passes every test."
	elif report.passed():
		head = "Structure designed: it now passes every test (%d %s added, %d upsized)." % [
				added, "part" if added == 1 else "parts", upsized]
	elif dos.is_empty():
		head = "The engineer could not fix this structure by adding or upsizing parts."
	else:
		head = "Improved, but it still fails: %s" % report.summary
	var out_notes := PackedStringArray([head])
	out_notes.append_array(notes)
	for pid: String in BuildingModel.sort_ids(was.keys()):
		if work.parts.has(pid):
			out_notes.append("%s: %s instead of %s." % [_label(work, pid),
					_section_label(work.catalog, str(work.parts[pid].get("section", ""))), _section_label(work.catalog, str(was[pid]))])
	if not report.passed():
		for n in report.notes:
			if not n in out_notes:
				out_notes.append(n)
	return {"op": BuildingCommands.batch(dos) if not dos.is_empty() else {}, "notes": out_notes,
			"before": before, "after": report, "passed": report.passed(), "upsized": upsized, "added": added}


## Failing building parts and the worst failure of each: part id -> result row, plus
## "anchor": true for foundations.
static func _failing(report: StructureReport, model: BuildingModel) -> Dictionary:
	var out := {}
	for r in report.results:
		for id in r.failures:
			var anchor := r.anchors.has(id)
			var row: Dictionary = (r.anchors[id] if anchor else r.members[id]).duplicate()
			var part := str(row.get("part", id))
			if not model.parts.has(part):
				continue
			row["anchor"] = anchor
			if not out.has(part) or float(row.u) > float(out[part].u):
				out[part] = row
	return out


## One fix for one failing part: {"ops": [...], "note": what was done or what to try}.
static func _fix(model: BuildingModel, pid: String, row: Dictionary) -> Dictionary:
	var cat := model.catalog
	var e: Dictionary = model.parts[pid]
	var fam := cat.family_of(str(e.kind))
	var who := _label(model, pid)
	if str(row.get("mode", "")) == "unsupported":
		var ops := _prop_part(model, pid)
		if ops.is_empty():
			return {"ops": [], "note": "%s has nothing under it and the engineer found nowhere to put a column. Add a wall or beam under it." % who}
		return {"ops": ops, "added": true, "note": "Added columns and a pad footing under %s, which had nothing holding it up." % who}
	# A floor far over capacity wants a beam under it before a thicker slab.
	if fam in ["slab", "roof"] and float(row.u) > SPAN_FIRST and not bool(row.get("lateral", false)):
		var first := _beam_across(model, pid)
		if not first.is_empty() and not _is_pitched(model, pid):
			return {"ops": [first], "added": true, "note": "Added a steel beam across the middle of %s to halve its span." % who}
	var bigger := next_section(cat, str(e.kind), str(e.material), str(e.get("section", "")))
	if bigger != "":
		return {"ops": [BuildingCommands.set_fields(pid, {"section": bigger})],
				"note": "%s: %s instead of %s." % [who, _section_label(cat, bigger), _section_label(cat, str(e.get("section", "")))]}
	if bool(row.get("anchor", false)) or fam == "foundation":
		return {"ops": [], "note": "%s is the biggest footing of its kind and the ground still cannot take it. Use a raft or piles." % who}
	if bool(row.get("lateral", false)) or str(row.get("mode", "")) == "shear" and fam == "wall":
		return {"ops": [], "note": "%s is at its strongest and still sways or racks. Add bracing or another shear wall in that direction." % who}
	match fam:
		"beam":
			var pts := model.points_of(pid)
			var mid := (pts[0] + pts[1]) * 0.5
			var ops := support_stack(model, mid.x, mid.z, minf(pts[0].y, pts[1].y))
			if not ops.is_empty():
				return {"ops": ops, "added": true, "note": "Added a column under the middle of %s to halve its span." % who}
		"slab", "roof":
			if _is_pitched(model, pid):
				return {"ops": [], "note": "%s is the strongest roof of its kind. Add a wall or beam under its ridge." % who}
			var op := _beam_across(model, pid)
			if not op.is_empty():
				return {"ops": [op], "added": true, "note": "Added a steel beam across the middle of %s to halve its span." % who}
	return {"ops": [], "note": "%s is at its strongest section and still fails. Add a column or wall under it." % who}


## The next stronger section for a kind and material, or "" at the top of the range.
static func next_section(cat: BuildingCatalog, kind: String, material: String, current: String) -> String:
	var secs := cat.sections_for(kind, material)
	if secs.is_empty():
		return ""
	var fam := cat.family_of(kind)
	var now := _strength(cat, fam, current) if current != "" else -1.0
	var best := ""
	var best_s := INF
	for s in secs:
		var v := _strength(cat, fam, s)
		if v > now + 1e-9 and v < best_s:
			best_s = v
			best = s
	return best


## What a section is ranked by: footings by plan size, members by bending strength (or
## area), walls and plates by thickness.
static func _strength(cat: BuildingCatalog, family: String, sid: String) -> float:
	var s := cat.section(sid)
	if family == "foundation":
		return float(s.get("w", s.get("dia", 0.0))) * 1000.0 + float(s.get("d", 0.0))
	if s.has("wy"):
		return float(s.wy) * 1e6 + float(s.get("area", 0.0))
	return float(s.get("d", 0.0)) * 1000.0 + float(s.get("w", 0.0))


## Columns from world height top_y down to the ground at (x, z), one per storey, and a pad
## footing under them. Storeys that already have a column there are skipped. Returns ops.
static func support_stack(model: BuildingModel, x: float, z: float, top_y: float) -> Array:
	var ops: Array = []
	if top_y <= LEVEL_TOL:
		return ops
	var cat := model.catalog
	var col_sec := ""
	var secs := cat.sections_for("column", COLUMN_MATERIAL)
	if not secs.is_empty():
		col_sec = secs[0]
	for lv in range(model.level_count() - 1, -1, -1):
		var floor_y := model.level_elevation(lv)
		var top := floor_y + model.level_height(lv)
		if floor_y >= top_y - LEVEL_TOL:
			continue
		if _column_at(model, lv, x, z):
			continue
		var geo := {"at": [x, 0.0, z]}
		if absf(top - top_y) > LEVEL_TOL:
			geo["height"] = minf(top, top_y) - floor_y
		ops.append(BuildingCommands.place_part("column", lv, geo, COLUMN_MATERIAL, col_sec))
	if not _pad_at(model, x, z):
		var pads := cat.sections_for("pad_footing", "concrete")
		ops.append(BuildingCommands.place_part("pad_footing", 0, {"at": [x, 0.0, z]}, "concrete", pads[0] if not pads.is_empty() else ""))
	return ops


## Columns (down to a pad) under a part nothing holds up: a line's two ends, a point's
## base, an area's centre.
static func _prop_part(model: BuildingModel, pid: String) -> Array:
	var pts := model.points_of(pid)
	if pts.is_empty():
		return []
	var cat := model.catalog
	var at: Array = []
	match cat.shape_of(str(model.parts[pid].kind)):
		"line":
			at = [pts[0], pts[1]]
		"point":
			at = [pts[0]]
		_:
			var c := Vector3.ZERO
			for p in pts:
				c += p
			at = [c / pts.size()]
	var ops: Array = []
	var seen := {}
	for p: Vector3 in at:
		var key := "%.2f,%.2f" % [p.x, p.z]
		if seen.has(key):
			continue
		seen[key] = true
		ops.append_array(support_stack(model, p.x, p.z, p.y))
	return ops


## A steel beam across an area part's middle, the short way, at its height.
static func _beam_across(model: BuildingModel, pid: String) -> Dictionary:
	var e: Dictionary = model.parts[pid]
	var outline: Array = e.outline
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Array in outline:
		lo = Vector2(minf(lo.x, float(p[0])), minf(lo.y, float(p[1])))
		hi = Vector2(maxf(hi.x, float(p[0])), maxf(hi.y, float(p[1])))
	var size := hi - lo
	var y := float(e.get("y", 0.0))
	var a: Array
	var b: Array
	if size.x >= size.y:
		var mx := (lo.x + hi.x) * 0.5
		a = [mx, y, lo.y]
		b = [mx, y, hi.y]
	else:
		var mz := (lo.y + hi.y) * 0.5
		a = [lo.x, y, mz]
		b = [hi.x, y, mz]
	# Not twice: a beam already there means this part needs more than one.
	for id: String in model.parts_on(int(e.level)):
		var q: Dictionary = model.parts[id]
		if str(q.kind) == "beam" and _same_line(q, a, b):
			return {}
	var secs := model.catalog.sections_for("beam", BEAM_MATERIAL)
	return BuildingCommands.place_part("beam", int(e.level), {"a": a, "b": b}, BEAM_MATERIAL, secs[0] if not secs.is_empty() else "")


static func _is_pitched(model: BuildingModel, pid: String) -> bool:
	var e: Dictionary = model.parts[pid]
	return model.catalog.family_of(str(e.kind)) == "roof" \
			and float(e.get("pitch", model.catalog.kind(str(e.kind)).get("pitch", 0.0))) > 0.0


static func _same_line(q: Dictionary, a: Array, b: Array) -> bool:
	var qa := Vector3(q.a[0], q.a[1], q.a[2])
	var qb := Vector3(q.b[0], q.b[1], q.b[2])
	var pa := Vector3(a[0], a[1], a[2])
	var pb := Vector3(b[0], b[1], b[2])
	return (qa.distance_to(pa) < NEAR and qb.distance_to(pb) < NEAR) or (qa.distance_to(pb) < NEAR and qb.distance_to(pa) < NEAR)


static func _column_at(model: BuildingModel, level: int, x: float, z: float) -> bool:
	for id: String in model.parts_on(level):
		var q: Dictionary = model.parts[id]
		if model.catalog.family_of(str(q.kind)) == "column" and Vector2(float(q.at[0]) - x, float(q.at[2]) - z).length() < NEAR:
			return true
	return false


static func _pad_at(model: BuildingModel, x: float, z: float) -> bool:
	for id: String in model.parts_on(0):
		var q: Dictionary = model.parts[id]
		if str(q.kind) in ["pad_footing", "pile"] and Vector2(float(q.at[0]) - x, float(q.at[2]) - z).length() < NEAR:
			return true
	return false


static func _label(model: BuildingModel, id: String) -> String:
	var e: Dictionary = model.parts[id]
	var n := str(e.get("name", ""))
	return "%s %s" % [str(model.catalog.kind(str(e.kind)).get("label", str(e.kind).capitalize())), n if n != "" else id]


static func _section_label(cat: BuildingCatalog, sid: String) -> String:
	return str(cat.section(sid).get("label", sid)) if sid != "" else "no section"
