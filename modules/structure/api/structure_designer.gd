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
## With complete (the Design structure button), it first finishes the structure: footings
## under ground-floor walls and columns (a raft on soft ground), a ground slab, floors on
## upper levels and a roof over the top, wherever the crew has not drawn them.
##
## Fixes, cheapest first, one per failing part per round, round after round:
## - An overloaded member, wall or footing gets the next stronger section of its material;
##   a masonry or timber wall at its strongest becomes reinforced concrete.
## - A beam at its biggest section gets a column under the middle of the span that fails,
##   carried down to the ground on columns with a pad footing (then quarter points, ...).
## - A floor or flat roof gets steel beams across it (its short way) at its middle, then its
##   quarter points, and so on; the beams are then sized and propped in later rounds.
## - A crushed wall gets steel columns inside it where it is crushed; a wall nothing holds up
##   gets columns under it (or a strip footing on the ground).
## - A part nothing holds up gets columns under its ends (or its middle) down to a pad.
## Only what it truly cannot fix is reported, one short line per part.
##
## Returns {"op": a BuildingCommands.batch of every change ({} when nothing changed),
## "notes": plain-language lines (the first sums it up), "before": StructureReport,
## "after": StructureReport, "passed": bool, "upsized": int, "added": int,
## "stuck": {part id: why}}.

const MAX_ROUNDS := 24
## Columns closer than this (in plan) to a wanted one count as already there.
const NEAR := 0.15
const LEVEL_TOL := 0.05
const COLUMN_MATERIAL := "steel"
const BEAM_MATERIAL := "steel"
## A floor or flat roof over this utilisation gets a beam under it before a thicker section.
const SPAN_FIRST := 1.6
## No column closer than this to another support along a beam, m.
const MIN_BAY := 1.2
## At most this many floor beams across one floor (2^n - 1 for n subdivisions).
const BEAM_DEPTH := 4
## Lines of "could not fix" at most.
const MAX_STUCK_NOTES := 6


static func design(model: BuildingModel, scenarios: Array[StructureScenario] = [], options: Dictionary = {},
		complete: bool = false) -> Dictionary:
	var work := BuildingModel.from_data(model.to_data(), model.catalog)
	var dos: Array = []
	var upsized := 0
	var added := 0
	var count := {}  # kind -> parts added
	if complete:
		for op: Dictionary in complete_ops(work):
			var r := work.apply(op)
			if r.is_empty():
				continue
			dos.append(r.do)
			added += 1
			count[str(op.entry.kind)] = int(count.get(str(op.entry.kind), 0)) + 1
	var g := StructureBuilding.graph(work, PackedStringArray(), options)
	var before := StructureSolver.stress_test(g, scenarios)
	var report := before
	var stuck := {}  # part id -> why nothing more can be done
	for round_i in MAX_ROUNDS:
		if report.passed():
			break
		var fixes := 0
		var failing := _failing(report, work)
		for pid: String in BuildingModel.sort_ids(failing.keys()):
			if stuck.has(pid) or not work.parts.has(pid):
				continue
			var got := _fix(work, g, pid, failing[pid])
			var done := 0
			for op: Dictionary in got.ops:
				var r := work.apply(op)
				if r.is_empty():
					continue
				dos.append(r.do)
				done += 1
				if str(op.op) == "add":
					added += 1
					var k := str(op.entry.kind)
					count[k] = int(count.get(k, 0)) + 1
				else:
					upsized += 1
			if done == 0:
				stuck[pid] = str(got.get("why", "it is already as strong as the engineer can make it"))
				continue
			fixes += 1
		if fixes == 0:
			break
		g = StructureBuilding.graph(work, PackedStringArray(), options)
		report = StructureSolver.stress_test(g, scenarios)
	var did := _did(count, upsized)
	var head := ""
	if before.passed() and dos.is_empty():
		head = "Nothing to fix: the structure already passes every test."
	elif report.passed():
		head = "Structure designed: it now passes every test. %s" % did if not before.passed() \
				else "Structure completed: it passes every test. %s" % did
	elif dos.is_empty():
		head = "The engineer could not fix this structure."
	else:
		head = "Improved, but %s still %s. %s" % [_count_parts(report), "fails" if report.failed_parts().size() == 1 else "fail", did]
	var out_notes := PackedStringArray([head])
	if not report.passed():
		var left := _failing(report, work)
		var shown := 0
		for pid: String in BuildingModel.sort_ids(left.keys()):
			if shown >= MAX_STUCK_NOTES:
				out_notes.append("...and %d more." % (left.size() - shown))
				break
			var why := str(stuck.get(pid, "it needs more than the engineer's rounds allow"))
			out_notes.append("%s at %d%%: %s." % [describe(work, pid), roundi(float(left[pid].u) * 100.0), why])
			shown += 1
	return {"op": BuildingCommands.batch(dos) if not dos.is_empty() else {}, "notes": out_notes,
			"before": before, "after": report, "passed": report.passed(), "upsized": upsized, "added": added,
			"stuck": stuck}


## "Added 4 columns, 2 beams and 4 pad footings; strengthened 8 parts."
static func _did(count: Dictionary, upsized: int) -> String:
	var bits := PackedStringArray()
	var names := {"column": ["column", "columns"], "beam": ["beam", "beams"], "pad_footing": ["pad footing", "pad footings"],
			"strip_footing": ["strip footing", "strip footings"]}
	var kinds := count.keys()
	kinds.sort()
	for k: String in kinds:
		var n := int(count[k])
		var nm: Array = names.get(k, [k.replace("_", " "), k.replace("_", " ") + "s"])
		bits.append("%d %s" % [n, nm[0] if n == 1 else nm[1]])
	var out := ""
	if not bits.is_empty():
		var list := bits[0] if bits.size() == 1 else ", ".join(bits.slice(0, bits.size() - 1)) + " and " + bits[bits.size() - 1]
		out = "Added %s" % list
	if upsized > 0:
		out += ("; s" if out != "" else "S") + "trengthened %d %s" % [upsized, "part" if upsized == 1 else "parts"]
	return out + "." if out != "" else ""


static func _count_parts(report: StructureReport) -> String:
	var n := report.failed_parts().size()
	return "1 part" if n == 1 else "%d parts" % n


## A part as the crew sees it: its kind and number, level and size, e.g. "Load-bearing
## wall p145 (ground floor, 8.0 m long)".
static func describe(model: BuildingModel, pid: String) -> String:
	if not model.parts.has(pid):
		return pid
	var e: Dictionary = model.parts[pid]
	var bits := PackedStringArray()
	if str(e.get("name", "")) != "":
		bits.append(pid)  # the number too, so it can be found
	var lv := model.level_of(pid)
	if lv >= 0:
		var lname := str(model.levels[lv].get("name", "")) if lv < model.levels.size() else ""
		bits.append(lname.to_lower() if lname != "" else ("ground floor" if lv == 0 else "level %d" % lv))
	var pts := model.points_of(pid)
	match model.catalog.shape_of(str(e.kind)):
		"line":
			if pts.size() >= 2:
				bits.append("%.1f m long" % Vector2(pts[0].x, pts[0].z).distance_to(Vector2(pts[1].x, pts[1].z)))
		"area":
			bits.append("%d m²" % roundi(BuildingModel.outline_area(e.outline)))
	return "%s (%s)" % [_label(model, pid), ", ".join(bits)] if not bits.is_empty() else _label(model, pid)


## Failing building parts and the worst failure of each: part id -> result row, plus
## "anchor": true for foundations and "member": the graph id that failed.
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
			row["member"] = id
			if not out.has(part) or float(row.u) > float(out[part].u):
				out[part] = row
	return out


## One fix for one failing part: {"ops": [...]} or {"ops": [], "why": what stops it}.
static func _fix(model: BuildingModel, g: StructureGraph, pid: String, row: Dictionary) -> Dictionary:
	var cat := model.catalog
	var e: Dictionary = model.parts[pid]
	var fam := cat.family_of(str(e.kind))
	var mode := str(row.get("mode", ""))
	var lateral := bool(row.get("lateral", false))
	if mode == "unsupported":
		var ops := _prop_part(model, pid)
		return {"ops": ops, "why": "nothing holds it up and there is nowhere to put a column under it"}
	# A floor far over capacity wants a beam under it before a thicker slab.
	if fam in ["slab", "roof"] and float(row.u) > SPAN_FIRST and not lateral and not _is_pitched(model, pid):
		var first := _beams_across(model, pid)
		if not first.is_empty():
			return {"ops": first}
	var bigger := next_section(cat, str(e.kind), str(e.material), str(e.get("section", "")))
	if bigger != "":
		return {"ops": [BuildingCommands.set_fields(pid, {"section": bigger})]}
	# A masonry or timber wall at its strongest: reinforced concrete.
	if fam == "wall" and str(e.material) != "concrete" and "concrete" in cat.materials_for(str(e.kind)):
		var rc := cat.sections_for(str(e.kind), "concrete")
		if not rc.is_empty():
			return {"ops": [BuildingCommands.set_fields(pid, {"material": "concrete", "section": rc[0]})]}
	if bool(row.get("anchor", false)) or fam == "foundation":
		# The biggest pad still sinks: a pile in its place reaches firmer ground.
		if str(e.kind) == "pad_footing" and cat.has_kind("pile"):
			var piles := cat.sections_for("pile", "concrete")
			return {"ops": [BuildingCommands.set_fields(pid, {"kind": "pile", "material": "concrete",
					"section": piles[0] if not piles.is_empty() else null})],
					"why": "the ground cannot take it even on the biggest pile; it needs a raft"}
		return {"ops": [], "why": "the ground cannot take it even on the biggest footing; it needs a raft or piles"}
	if lateral or (mode == "shear" and fam == "wall"):
		return {"ops": [], "why": "it sways or racks; add bracing or another shear wall in that direction"}
	match fam:
		"beam":
			return {"ops": _prop_span(model, g, pid, str(row.get("member", ""))),
					"why": "its spans are as short as columns can make them"}
		"slab", "roof":
			if _is_pitched(model, pid):
				return {"ops": _ridge_beam(model, pid), "why": "it is the strongest roof of its kind even with a ridge beam; add a wall under its ridge"}
			return {"ops": _beams_across(model, pid), "why": "it already has as many beams under it as fit"}
		"wall":
			return _wall_fix(model, g, pid, str(row.get("member", "")), mode)
	return {"ops": [], "why": "it is already as strong as it can be made"}


## A wall at its strongest (reinforced concrete) that still fails, by where it fails:
## crushed (an upright) gets a column inside it there; its bottom spanning over nothing gets
## columns under it (or a strip footing on the ground); its top between supports gets a
## column under the middle of that stretch. Over a door or window there is no room for one.
static func _wall_fix(model: BuildingModel, g: StructureGraph, pid: String, mid: String, mode: String) -> Dictionary:
	if not g.members.has(mid):
		return {"ops": [], "why": "it is already as strong as it can be made"}
	var m: Dictionary = g.members[mid]
	var pa: Vector3 = g.nodes[m.a].pos
	var pb: Vector3 = g.nodes[m.b].pos
	if m.kind == StructureGraph.WALL:
		var ops := support_stack(model, pa.x, pa.z, maxf(pa.y, pb.y))
		if ops.is_empty():
			for off in [0.45, -0.45]:
				var along: Vector3 = _wall_dir(model, pid) * float(off)
				ops = support_stack(model, pa.x + along.x, pa.z + along.z, maxf(pa.y, pb.y))
				if not ops.is_empty():
					break
		return {"ops": ops, "why": "it is crushed even in reinforced concrete with columns in it; it needs a thicker wall or more walls to share the load"}
	var centre := (pa + pb) * 0.5
	if mid.contains("|b"):
		if centre.y <= LEVEL_TOL:
			var pts := model.points_of(pid)
			if not _strip_under(model, pts[0], pts[1]):
				var strips := model.catalog.sections_for("strip_footing", "concrete")
				return {"ops": [BuildingCommands.place_part("strip_footing", 0, {"a": [pts[0].x, 0.0, pts[0].z], "b": [pts[1].x, 0.0, pts[1].z]},
						"concrete", strips[0] if not strips.is_empty() else "")]}
			return {"ops": [], "why": "the ground under it gives way; it needs a wider footing"}
		return {"ops": support_stack(model, centre.x, centre.z, centre.y),
				"why": "nothing under it holds it up and the columns cannot get closer; put a wall under it"}
	if _over_opening(g, pid, centre):
		return {"ops": [], "why": "the lintel over its door or window is overloaded; make the opening narrower or move the load off it"}
	return {"ops": support_stack(model, centre.x, centre.z, maxf(pa.y, pb.y)),
			"why": "it spans too far between supports; add a wall under it"}


static func _wall_dir(model: BuildingModel, pid: String) -> Vector3:
	var pts := model.points_of(pid)
	return (pts[1] - pts[0]).normalized() if pts.size() >= 2 else Vector3.RIGHT


static func _over_opening(g: StructureGraph, pid: String, p: Vector3) -> bool:
	var sh: Dictionary = g.shapes.get(pid, {})
	if sh.is_empty():
		return false
	var a: Vector3 = sh.a
	var b: Vector3 = sh.b
	var length := a.distance_to(b)
	if length < 0.01:
		return false
	var t := (p - a).dot((b - a) / length) / length
	for o: Array in sh.get("openings", []):
		if t > float(o[0]) and t < float(o[1]):
			return true
	return false


static func _strip_under(model: BuildingModel, a: Vector3, b: Vector3) -> bool:
	var mid := (a + b) * 0.5
	for id: String in model.parts_on(0):
		var q: Dictionary = model.parts[id]
		if model.catalog.family_of(str(q.kind)) != "foundation" or not q.has("a"):
			continue
		var qa := Vector2(float(q.a[0]), float(q.a[2]))
		var qb := Vector2(float(q.b[0]), float(q.b[2]))
		var p := Vector2(mid.x, mid.z)
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, qa, qb)) < 0.3:
			return true
	return false


## A column under a beam, in the middle of the stretch between its supports where it fails
## (the beam's ends and the columns already under it). Nothing if that stretch is short.
static func _prop_span(model: BuildingModel, g: StructureGraph, pid: String, mid: String) -> Array:
	var pts := model.points_of(pid)
	if pts.size() < 2:
		return []
	var a := pts[0]
	var b := pts[1]
	var length := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	if length < MIN_BAY * 2.0:
		return []
	var dir := (b - a) / maxf(a.distance_to(b), 0.001)
	var at := 0.5
	if g.members.has(mid):
		var m: Dictionary = g.members[mid]
		var c: Vector3 = ((g.nodes[m.a].pos as Vector3) + (g.nodes[m.b].pos as Vector3)) * 0.5
		at = clampf((c - a).dot(dir) / maxf(a.distance_to(b), 0.001), 0.0, 1.0)
	var stops: Array = [0.0, 1.0]
	var y := minf(a.y, b.y)
	for lv in model.level_count():
		for id: String in model.parts_on(lv):
			var q: Dictionary = model.parts[id]
			if model.catalog.family_of(str(q.kind)) != "column":
				continue
			var qp := model.points_of(id)
			if qp.size() < 2 or absf(qp[1].y - y) > 0.3:
				continue
			var p2 := Vector2(qp[0].x, qp[0].z)
			var a2 := Vector2(a.x, a.z)
			var b2 := Vector2(b.x, b.z)
			if p2.distance_to(Geometry2D.get_closest_point_to_segment(p2, a2, b2)) > NEAR + 0.1:
				continue
			stops.append(clampf((p2 - a2).dot(b2 - a2) / maxf((b2 - a2).length_squared(), 1e-6), 0.0, 1.0))
	stops.sort()
	for i in stops.size() - 1:
		var t0: float = stops[i]
		var t1: float = stops[i + 1]
		if at >= t0 - 1e-6 and at <= t1 + 1e-6:
			if (t1 - t0) * length < MIN_BAY * 2.0:
				return []
			var p := a.lerp(b, (t0 + t1) * 0.5)
			return support_stack(model, p.x, p.z, p.y)
	return []


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


## Steel beams across an area part the short way: at its middle, or if one is there, at its
## quarter points, then eighths... (each halving the span again). [] when all are there.
static func _beams_across(model: BuildingModel, pid: String) -> Array:
	var e: Dictionary = model.parts[pid]
	var outline: Array = e.outline
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Array in outline:
		lo = Vector2(minf(lo.x, float(p[0])), minf(lo.y, float(p[1])))
		hi = Vector2(maxf(hi.x, float(p[0])), maxf(hi.y, float(p[1])))
	var size := hi - lo
	var y := float(e.get("y", 0.0))
	var secs := model.catalog.sections_for("beam", BEAM_MATERIAL)
	var sec: String = secs[0] if not secs.is_empty() else ""
	var long_x := size.x >= size.y
	var long := size.x if long_x else size.y
	var poly := PackedVector2Array()
	for p: Array in outline:
		poly.append(Vector2(float(p[0]), float(p[1])))
	for n in range(1, BEAM_DEPTH + 1):
		var parts := 1 << n
		if long / parts < MIN_BAY:
			break
		var ops: Array = []
		for k in range(1, parts, 2):
			var f := float(k) / parts
			var a: Array
			var b: Array
			if long_x:
				var mx := lerpf(lo.x, hi.x, f)
				a = [mx, y, lo.y]
				b = [mx, y, hi.y]
			else:
				var mz := lerpf(lo.y, hi.y, f)
				a = [lo.x, y, mz]
				b = [hi.x, y, mz]
			var mid := Vector2((float(a[0]) + float(b[0])) * 0.5, (float(a[2]) + float(b[2])) * 0.5)
			if not Geometry2D.is_point_in_polygon(mid, poly):
				continue  # an L or U shaped floor: the line misses it here
			var there := false
			for id: String in model.parts_on(int(e.level)):
				var q: Dictionary = model.parts[id]
				if str(q.kind) == "beam" and _same_line(q, a, b):
					there = true
					break
			if not there:
				ops.append(BuildingCommands.place_part("beam", int(e.level), {"a": a, "b": b}, BEAM_MATERIAL, sec))
		if not ops.is_empty():
			return ops
	return []


## A steel ridge beam under a pitched roof, along its long way at its eaves height (so it
## holds the rafters at mid-span); [] if one is there.
static func _ridge_beam(model: BuildingModel, pid: String) -> Array:
	var e: Dictionary = model.parts[pid]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Array in e.outline:
		lo = lo.min(Vector2(float(p[0]), float(p[1])))
		hi = hi.max(Vector2(float(p[0]), float(p[1])))
	var y := float(e.get("y", 0.0))
	var a: Array
	var b: Array
	if (hi - lo).x >= (hi - lo).y:
		var mz := (lo.y + hi.y) * 0.5
		a = [lo.x, y, mz]
		b = [hi.x, y, mz]
	else:
		var mx := (lo.x + hi.x) * 0.5
		a = [mx, y, lo.y]
		b = [mx, y, hi.y]
	for id: String in model.parts_on(int(e.level)):
		var q: Dictionary = model.parts[id]
		if str(q.kind) == "beam" and _same_line(q, a, b):
			return []
	var secs := model.catalog.sections_for("beam", BEAM_MATERIAL)
	return [BuildingCommands.place_part("beam", int(e.level), {"a": a, "b": b}, BEAM_MATERIAL, secs[0] if not secs.is_empty() else "")]


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


# --- Completing the structure ---------------------------------------------------------

## Soils too weak for strips and pads: the whole building goes on a raft.
const RAFT_SOILS: PackedStringArray = ["soft_clay", "made_ground"]
## A pitched roof only over a plain rectangle this narrow or less, m.
const PITCH_MAX_SPAN := 12.0


## What the structure is missing, as add ops on model: footings (or a raft), a ground slab,
## upper floors and a roof. Nothing the crew drew is changed.
static func complete_ops(model: BuildingModel) -> Array:
	var ops: Array = []
	var cat := model.catalog
	var levels_with_walls: Array[int] = []
	for lv in model.level_count():
		if not _walls_on(model, lv).is_empty():
			levels_with_walls.append(lv)
	if levels_with_walls.is_empty():
		return ops
	var soil := str(model.meta.get("soil", "clay"))
	var has := func(lv: int, fam: String) -> bool:
		for id: String in model.parts_on(lv):
			if cat.family_of(str(model.parts[id].kind)) == fam:
				return true
		return false
	# Foundations.
	var ground := _footprint(model, 0) if levels_with_walls.has(0) else []
	var raft_there := false
	for id: String in model.parts_on(0):
		if str(model.parts[id].kind) == "raft":
			raft_there = true
	if soil in RAFT_SOILS and not ground.is_empty():
		if not raft_there:
			for outline: Array in ground:
				var rafts := cat.sections_for("raft", "concrete")
				ops.append(BuildingCommands.place_part("raft", 0, {"outline": outline, "y": 0.0}, "concrete", rafts[0] if not rafts.is_empty() else ""))
	elif not raft_there:
		var strips := cat.sections_for("strip_footing", "concrete")
		for id: String in _walls_on(model, 0):
			if not bool(cat.kind(str(model.parts[id].kind)).get("structural", false)):
				continue
			var pts := model.points_of(id)
			if not _strip_under(model, pts[0], pts[1]):
				ops.append(BuildingCommands.place_part("strip_footing", 0, {"a": [pts[0].x, 0.0, pts[0].z], "b": [pts[1].x, 0.0, pts[1].z]},
						"concrete", strips[0] if not strips.is_empty() else ""))
		var pads := cat.sections_for("pad_footing", "concrete")
		for id: String in model.parts_on(0):
			if cat.family_of(str(model.parts[id].kind)) != "column":
				continue
			var p := model.points_of(id)[0]
			if not _pad_at(model, p.x, p.z):
				ops.append(BuildingCommands.place_part("pad_footing", 0, {"at": [p.x, 0.0, p.z]}, "concrete", pads[0] if not pads.is_empty() else ""))
	# Floors: a ground slab, and a floor on each upper level the walls reach.
	for lv: int in levels_with_walls:
		if has.call(lv, "slab"):
			continue
		var floors := cat.sections_for("slab", "concrete")
		var sec: String = floors[0 if lv == 0 else mini(1, floors.size() - 1)] if not floors.is_empty() else ""
		for outline: Array in _footprint(model, lv):
			ops.append(BuildingCommands.place_part("slab", lv, {"outline": outline, "y": 0.0}, "concrete", sec))
	# A roof over the top level with walls, unless one is there (or on the level above).
	var top: int = levels_with_walls[levels_with_walls.size() - 1]
	if not has.call(top, "roof") and not (top + 1 < model.level_count() and has.call(top + 1, "roof")):
		var outlines := _footprint(model, top)
		for outline: Array in outlines:
			var h := model.level_height(top)
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for q: Array in outline:
				lo = lo.min(Vector2(float(q[0]), float(q[1])))
				hi = hi.max(Vector2(float(q[0]), float(q[1])))
			var rect := outline.size() == 4 and absf(BuildingModel.outline_area(outline) - (hi - lo).x * (hi - lo).y) < 0.01
			if outlines.size() == 1 and rect and minf((hi - lo).x, (hi - lo).y) <= PITCH_MAX_SPAN:
				ops.append(BuildingCommands.place_part("roof_pitched", top, {"outline": outline, "y": h}, "timber"))
			else:
				ops.append(BuildingCommands.place_part("roof_flat", top, {"outline": outline, "y": h}, "timber",
						str(cat.sections_for("roof_flat", "timber")[0]) if not cat.sections_for("roof_flat", "timber").is_empty() else ""))
	return ops


static func _walls_on(model: BuildingModel, lv: int) -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in model.parts_on(lv):
		if model.catalog.family_of(str(model.parts[id].kind)) == "wall" and model.parts[id].has("a"):
			out.append(id)
	return out


## Outlines to cover on a level: the box round its walls, or, when the rooms drawn there
## fill clearly less of that box (an L or U shaped plan), each room's own outline.
static func _footprint(model: BuildingModel, lv: int) -> Array:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for id: String in _walls_on(model, lv):
		for p in model.points_of(id):
			lo = lo.min(Vector2(p.x, p.z))
			hi = hi.max(Vector2(p.x, p.z))
	if lo.x == INF or (hi - lo).x < 0.5 or (hi - lo).y < 0.5:
		return []
	var box := BuildingCommands.rect(lo.x, lo.y, hi.x - lo.x, hi.y - lo.y)
	var rooms := model.rooms_on(lv)
	if rooms.is_empty():
		return [box]
	var area := 0.0
	for rid: String in rooms:
		area += BuildingModel.outline_area(model.rooms[rid].outline)
	if area >= 0.85 * (hi - lo).x * (hi - lo).y:
		return [box]
	var out: Array = []
	for rid: String in rooms:
		out.append((model.rooms[rid].outline as Array).duplicate(true))
	return out

