extends RefCounted
## Turns a BuildingModel (read through the building api) into a StructureGraph.
##
## - Columns, beams, braces and trusses become members, split wherever another part's end
##   or a connection point lies on them, so a beam resting on another beam or a wall, or
##   framing into a column, shares a node with it. Nodes are keyed by position (to 1 cm).
## - A load-bearing wall becomes upright WALL members at each such point (and at the edges
##   of its doors and windows), each as wide as the solid wall it stands for, tied along its
##   top and bottom by the wall acting as a deep beam. Over an opening that beam is only as
##   deep as the wall above the opening, so a wide opening needs a stronger wall or beam.
## - Slabs and roofs become plates. Their area is shared among the beams and wall tops under
##   them (each patch to the nearest one), with dead, room live and snow loads, and the
##   plate is checked over its longest span between opposite supports (or as a cantilever).
##   A ground-floor slab with nothing under it bears on the ground.
## - Foundations make the nodes standing on them anchors with the ground's bearing
##   capacity (soil from the model's meta "soil", default clay). Nodes at ground level with
##   no foundation are anchored without a bearing check unless options
##   "ground_needs_foundations" is true.
## Non-structural parts (partitions, curtain walls, openings, fixtures) only count through
## the floor finishes and live loads.

const Props := preload("res://modules/structure/internal/section_props.gd")

const TOL := 0.02
## How far above a foundation's top a node may be and still stand on it.
const ANCHOR_DY := 0.6
const GROUND_Y := 0.05
## How far below or above a slab a beam may be and still hold it up, and how far outside
## its outline.
const SUPPORT_DY := 0.4
const SUPPORT_REACH := 0.3
## Longest stretch of wall between two uprights (m).
const WALL_STEP := 1.0

var model: BuildingModel
var cat: BuildingCatalog
var g := StructureGraph.new()
var options: Dictionary
var skip := {}
var soil := "clay"
var lines: Array = []  # {part, kind, a, b, section_id, label} for columns, beams, braces, trusses
var walls: Array = []  # {part, a, b, h, sec, mat, label, openings: [[t0, t1, sill, top]]}
var plates: Array = []  # part ids of slabs and roofs
var foundations: Array = []  # part ids
var points: Array = []  # Vector3 station candidates


static func build(m: BuildingModel, removed: PackedStringArray = PackedStringArray(), opts: Dictionary = {}) -> StructureGraph:
	var ad = new()
	ad.model = m
	ad.cat = m.catalog
	ad.options = opts
	for id in removed:
		ad.skip[id] = true
	ad.soil = str(m.meta.get("soil", "clay"))
	ad._collect()
	ad._frame()
	ad._walls()
	ad._anchors()
	ad._plates()
	ad.g.auto_wind_areas(3.0)
	ad.g.revision = m.revision
	return ad.g


func _label(id: String) -> String:
	var e: Dictionary = model.parts[id]
	var kind_label := str(cat.kind(str(e.kind)).get("label", str(e.kind).capitalize()))
	var n := str(e.get("name", ""))
	return "%s %s" % [kind_label, n if n != "" else id]


func _collect() -> void:
	for id in BuildingModel.sort_ids(model.parts.keys()):
		if skip.has(id):
			continue
		var e: Dictionary = model.parts[id]
		var spec := cat.kind(str(e.kind))
		if not bool(spec.get("structural", false)):
			continue
		var fam := str(spec.get("family", ""))
		var pts := model.points_of(id)
		match fam:
			"column", "beam", "brace", "truss":
				if pts.size() < 2:
					continue
				var kind: String = {"column": StructureGraph.COLUMN, "brace": StructureGraph.BRACE}.get(fam, StructureGraph.BEAM)
				lines.append({"part": id, "kind": kind, "fam": fam, "a": pts[0], "b": pts[1], "label": _label(id)})
				points.append(pts[0])
				points.append(pts[1])
			"wall":
				var h := model.part_height(id)
				var w := {"part": id, "a": pts[0], "b": pts[1], "h": h, "label": _label(id), "openings": []}
				var length := pts[0].distance_to(pts[1])
				for oid in model.openings_in(id):
					if skip.has(oid):
						continue
					var o: Dictionary = model.parts[oid]
					var os := cat.kind(str(o.kind))
					var ow := float(o.get("w", os.get("w", 1.0)))
					var oh := float(o.get("h", os.get("h", 2.0)))
					var sill := float(o.get("sill", os.get("sill", 0.0)))
					var t := float(o.t)
					w.openings.append([clampf((t - ow * 0.5) / length, 0.0, 1.0), clampf((t + ow * 0.5) / length, 0.0, 1.0), sill, sill + oh])
				walls.append(w)
				for p in [pts[0], pts[1]]:
					points.append(p)
					points.append(p + Vector3(0, h, 0))
			"slab", "roof":
				plates.append(id)
			"foundation":
				foundations.append(id)
				if pts.size() > 0:
					points.append(pts[0])
	for cid in BuildingModel.sort_ids(model.connections.keys()):
		var c: Dictionary = model.connections[cid]
		if c.has("at") and not skip.has(str(c.a)) and not skip.has(str(c.b)):
			var at: Array = c.at
			points.append(Vector3(float(at[0]), float(at[1]), float(at[2])))


static func _key(p: Vector3) -> String:
	return "n%d_%d_%d" % [roundi(p.x * 100.0), roundi(p.y * 100.0), roundi(p.z * 100.0)]


func _node(p: Vector3) -> String:
	var id := _key(p)
	if not g.nodes.has(id):
		g.add_node(id, Vector3(roundf(p.x * 100.0), roundf(p.y * 100.0), roundf(p.z * 100.0)) / 100.0)
	return id


## Sorted station parameters (0..1) along a to b: its ends plus every candidate point on it.
func _stations(a: Vector3, b: Vector3, extra: Array = []) -> Array:
	var d := b - a
	var len2 := d.length_squared()
	var ts: Array = [0.0, 1.0]
	for p: Vector3 in points:
		var t := clampf((p - a).dot(d) / len2, 0.0, 1.0)
		if (a + d * t).distance_to(p) <= TOL:
			ts.append(t)
	ts.append_array(extra)
	ts.sort()
	var out: Array = []
	var length := sqrt(len2)
	for t: float in ts:
		if out.is_empty() or (t - float(out.back())) * length > TOL:
			out.append(t)
	if float(out.back()) < 1.0:
		out[out.size() - 1] = 1.0
	return out


func _section(sid: String, props: Dictionary) -> String:
	if not g.sections.has(sid):
		g.add_section(sid, props)
	return sid


func _frame() -> void:
	for l: Dictionary in lines:
		var e: Dictionary = model.parts[l.part]
		var mat_id := str(e.material)
		var sec_id := str(e.get("section", ""))
		var ts := _stations(l.a, l.b)
		var segs := ts.size() - 1
		for k in segs:
			var pa: Vector3 = l.a.lerp(l.b, ts[k])
			var pb: Vector3 = l.a.lerp(l.b, ts[k + 1])
			var length := pa.distance_to(pb)
			var sid := "f:%s:%s:%s" % [sec_id, mat_id, l.fam]
			if l.fam == "column":
				sid += ":%d" % roundi(length * 100.0)
			var props: Dictionary = Props.frame(cat.section(sec_id), mat_id, cat.material(mat_id), l.fam, length)
			var mid: String = l.part if segs == 1 else "%s#%d" % [l.part, k]
			var why := g.add_member(mid, _node(pa), _node(pb), l.kind, _section(sid, props), 1.0, Vector3.ZERO, l.label, l.part, l.part)
			if why != "":
				push_warning("structure: " + why)


func _walls() -> void:
	for w: Dictionary in walls:
		var e: Dictionary = model.parts[w.part]
		var mat_id := str(e.material)
		var sec_id := str(e.get("section", ""))
		var sec := cat.section(sec_id)
		var mat := cat.material(mat_id)
		var a: Vector3 = w.a
		var b: Vector3 = w.b
		var h: float = w.h
		var up := Vector3(0, h, 0)
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var extra: Array = []
		# Uprights at least every WALL_STEP, so a wall carries what sits on it straight down.
		var steps := ceili(length / WALL_STEP)
		for i in range(1, steps):
			extra.append(float(i) / steps)
		for o: Array in w.openings:
			extra.append(o[0])
			extra.append(o[1])
		# Points on the top line count too.
		var ts := _stations(a, b, extra)
		var top_ts := _stations(a + up, b + up)
		for t: float in top_ts:
			if t > 0.0 and t < 1.0:
				ts.append(t)
		ts.sort()
		var clean: Array = []
		for t: float in ts:
			if clean.is_empty() or (t - float(clean.back())) * length > TOL:
				clean.append(t)
		ts = clean
		var upright := _section("w:%s:%s" % [sec_id, mat_id], Props.wall(sec, mat_id, mat))
		# Each interval between stations: solid, a window (wall below the sill) or a door.
		var spans: Array = []
		for k in ts.size() - 1:
			var mid_t := (float(ts[k]) + float(ts[k + 1])) * 0.5
			var span := {"t0": ts[k], "t1": ts[k + 1], "len": (float(ts[k + 1]) - float(ts[k])) * length,
					"solid": true, "above": h, "below": h}
			for o: Array in w.openings:
				if mid_t > float(o[0]) and mid_t < float(o[1]):
					span.solid = false
					span.above = maxf(h - float(o[3]), 0.05)
					span.below = float(o[2])
			spans.append(span)
		for k in ts.size():
			var trib := 0.0
			if k > 0 and spans[k - 1].solid:
				trib += spans[k - 1].len * 0.5
			if k < spans.size() and spans[k].solid:
				trib += spans[k].len * 0.5
			if trib <= 0.0:
				continue
			var base := a.lerp(b, ts[k])
			g.add_member("%s|v%d" % [w.part, k], _node(base), _node(base + up), StructureGraph.WALL,
					upright, trib, dir, w.label, w.part)
		for k in spans.size():
			var s: Dictionary = spans[k]
			var p0 := a.lerp(b, s.t0)
			var p1 := a.lerp(b, s.t1)
			var top_sid := _section("wb:%s:%s:%d" % [sec_id, mat_id, roundi(float(s.above) * 100.0)],
					Props.wall_beam(sec, mat_id, s.above))
			g.add_member("%s|t%d" % [w.part, k], _node(p0 + up), _node(p1 + up), StructureGraph.BEAM,
					top_sid, 1.0, Vector3.ZERO, w.label, w.part, w.part + "|t")
			if float(s.below) > 0.05:
				var bot_sid := _section("wb:%s:%s:%d" % [sec_id, mat_id, roundi(float(s.below) * 100.0)],
						Props.wall_beam(sec, mat_id, s.below))
				g.add_member("%s|b%d" % [w.part, k], _node(p0), _node(p1), StructureGraph.BEAM,
						bot_sid, 1.0, Vector3.ZERO, w.label, w.part, w.part + "|b")


func _anchors() -> void:
	var bearing := {}
	var owner := {}
	var ids := g.nodes.keys()
	ids.sort()
	for fid: String in foundations:
		var e: Dictionary = model.parts[fid]
		var sec := cat.section(str(e.get("section", "")))
		var pts := model.points_of(fid)
		if pts.is_empty():
			continue
		var on: Array = []
		var capacity := 0.0
		match str(e.kind):
			"pile":
				var r := float(sec.get("dia", 0.45)) * 0.5 + 0.3
				capacity = StructureSections.PILE_CAPACITY * pow(float(sec.get("dia", 0.45)) / 0.45, 2.0)
				for n: String in ids:
					var p: Vector3 = g.nodes[n].pos
					if Vector2(p.x - pts[0].x, p.z - pts[0].z).length() <= r and _above(p.y, pts[0].y):
						on.append(n)
			_:
				match cat.shape_of(str(e.kind)):
					"point":
						var half := float(sec.get("w", 1.0)) * 0.5 + TOL
						capacity = StructureSections.foundation_capacity("pad", float(sec.get("w", 1.0)) ** 2, soil)
						for n: String in ids:
							var p: Vector3 = g.nodes[n].pos
							if absf(p.x - pts[0].x) <= half and absf(p.z - pts[0].z) <= half and _above(p.y, pts[0].y):
								on.append(n)
					"line":
						var half := float(sec.get("w", 0.6)) * 0.5 + TOL
						var length := pts[0].distance_to(pts[1])
						capacity = length * float(sec.get("w", 0.6)) * float(StructureSections.SOIL_BEARING.get(soil, 150.0))
						for n: String in ids:
							var p: Vector3 = g.nodes[n].pos
							if _plan_dist(p, pts[0], pts[1]) <= half and _above(p.y, minf(pts[0].y, pts[1].y)):
								on.append(n)
					"area":
						var outline: Array = e.outline
						capacity = StructureSections.foundation_capacity("raft", BuildingModel.outline_area(outline), soil)
						for n: String in ids:
							var p: Vector3 = g.nodes[n].pos
							if BuildingModel.outline_has_point(outline, p.x, p.z) and _above(p.y, pts[0].y):
								on.append(n)
		for n: String in on:
			bearing[n] = float(bearing.get(n, 0.0)) + capacity / on.size()
			if not owner.has(n):
				owner[n] = fid
	for n: String in ids:
		if bearing.has(n):
			g.make_anchor(n, bearing[n], owner[n])
		elif not options.get("ground_needs_foundations", false) and (g.nodes[n].pos as Vector3).y <= GROUND_Y:
			g.make_anchor(n, 0.0, "ground")


static func _above(y: float, top: float) -> bool:
	return y >= top - TOL and y <= top + ANCHOR_DY


static func _plan_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var p2 := Vector2(p.x, p.z)
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var d := b2 - a2
	var t := 0.0 if d.length_squared() < 1e-12 else clampf((p2 - a2).dot(d) / d.length_squared(), 0.0, 1.0)
	return p2.distance_to(a2 + d * t)


func _plates() -> void:
	var members := g.members.keys()
	members.sort()
	for pid: String in plates:
		var e: Dictionary = model.parts[pid]
		var spec := cat.kind(str(e.kind))
		var fam := str(spec.get("family", ""))
		var outline: Array = e.outline
		var y := model.level_elevation(model.level_of(pid)) + float(e.get("y", 0.0))
		var pitch := float(e.get("pitch", spec.get("pitch", 0.0)))
		var mat_id := str(e.material)
		var sec := cat.section(str(e.get("section", "")))
		var props: Dictionary = Props.plate(sec, mat_id, cat.material(mat_id))
		var sid := _section("p:%s:%s" % [str(e.get("section", "")), mat_id], props)
		# Beams and wall tops holding it up: level with it, under or along its outline.
		var supports: Array = []
		for mid: String in members:
			var m: Dictionary = g.members[mid]
			if m.kind != StructureGraph.BEAM or str(m.part) == pid:
				continue
			var pa: Vector3 = g.nodes[m.a].pos
			var pb: Vector3 = g.nodes[m.b].pos
			if absf(pa.y - y) > SUPPORT_DY or absf(pb.y - y) > SUPPORT_DY:
				continue
			if str(m.part).length() > 0 and model.parts.has(str(m.part)) \
					and cat.family_of(str(model.parts[str(m.part)].kind)) == "wall" and mid.contains("|b"):
				continue  # a wall's bottom holds up the slab under it, not over it
			var mid_p := (pa + pb) * 0.5
			if BuildingModel.outline_has_point(outline, mid_p.x, mid_p.z) or _outline_dist(outline, mid_p) <= SUPPORT_REACH:
				supports.append(mid)
		var area := BuildingModel.outline_area(outline)
		if supports.is_empty() and y <= GROUND_Y + SUPPORT_DY and fam == "slab":
			continue  # a ground-bearing slab
		var roof := fam == "roof"
		var dead := StructureLoads.ROOF_COVERING_KPA if roof else StructureLoads.FLOOR_FINISHES_KPA
		var snow := 0.0
		if roof:
			snow = StructureLoads.SNOW_KPA * clampf((60.0 - pitch) / 30.0, 0.0, 1.0)
		var live_rooms := _rooms_at(y) if not roof else []
		# Share the plate among its supports, cell by cell.
		var cell := maxf(0.25, sqrt(area / 4000.0))
		var bb := _bounds(outline)
		var got := {}  # member id -> {case: kN}
		var span := 0.0
		var cant := 0.0
		var max_live := StructureLoads.live_kpa("roof") if roof else 0.0
		var x := bb.position.x + cell * 0.5
		while x < bb.end.x:
			var z := bb.position.y + cell * 0.5
			while z < bb.end.y:
				if BuildingModel.outline_has_point(outline, x, z):
					var live := StructureLoads.live_kpa("roof") if roof else _live_at(live_rooms, x, z)
					max_live = maxf(max_live, live)
					if not supports.is_empty():
						var near := _nearest(supports, x, z)
						var a2 := cell * cell
						var row: Dictionary = got.get(near.id, {})
						row["dead"] = float(row.get("dead", 0.0)) + (float(props.weight) + dead) * a2
						row["live"] = float(row.get("live", 0.0)) + live * a2
						if snow > 0.0:
							row["snow"] = float(row.get("snow", 0.0)) + snow * a2
						got[near.id] = row
						if near.span >= 0.0:
							span = maxf(span, near.span)
						else:
							cant = maxf(cant, near.d)
				z += cell
			x += cell
		var used := PackedStringArray()
		var keys := got.keys()
		keys.sort()
		for mid: String in keys:
			used.append(mid)
			var length := g.member_length(mid)
			for case: String in got[mid]:
				g.add_member_load(mid, case, float(got[mid][case]) / length)
		var cantilever := 4.0 * cant * cant > span * span
		var check_span := cant if cantilever else span
		if pitch > 0.0 and not cantilever:
			check_span = span * 0.5 / cos(deg_to_rad(pitch))
		g.add_plate(pid, sid, check_span, cantilever, used, _label(pid), pid)
		g.add_plate_load(pid, "dead", dead)
		g.add_plate_load(pid, "live", max_live)
		if snow > 0.0:
			g.add_plate_load(pid, "snow", snow)


## Rooms whose floor is at height y: [[outline, live kPa]].
func _rooms_at(y: float) -> Array:
	var out: Array = []
	for rid in BuildingModel.sort_ids(model.rooms.keys()):
		var r: Dictionary = model.rooms[rid]
		if absf(model.level_elevation(int(r.level)) - y) <= SUPPORT_DY:
			var t := cat.room_type(str(r.type))
			out.append([r.outline, float(t.get("live_load", StructureLoads.live_kpa(str(r.type))))])
	return out


static func _live_at(rooms: Array, x: float, z: float) -> float:
	var best := -1.0
	for r: Array in rooms:
		if BuildingModel.outline_has_point(r[0], x, z):
			best = maxf(best, r[1])
	return best if best >= 0.0 else StructureLoads.DEFAULT_LIVE_KPA


## The nearest support to a plan point and its distance, and the shortest span through the
## point between two supports on opposite sides (-1 if there is none, so the point
## overhangs): {"id", "d", "span"}. Supports are grouped by building part.
func _nearest(supports: Array, x: float, z: float) -> Dictionary:
	var p := Vector2(x, z)
	var best_id := ""
	var best_d := INF
	var by_part := {}  # part -> [distance, direction]
	for mid: String in supports:
		var m: Dictionary = g.members[mid]
		var pa: Vector3 = g.nodes[m.a].pos
		var pb: Vector3 = g.nodes[m.b].pos
		var a2 := Vector2(pa.x, pa.z)
		var d2 := Vector2(pb.x, pb.z) - a2
		var t := clampf((p - a2).dot(d2) / maxf(d2.length_squared(), 1e-12), 0.0, 1.0)
		var q := a2 + d2 * t
		var dist := p.distance_to(q)
		if dist < best_d - 1e-9:
			best_d = dist
			best_id = mid
		var part := str(m.part)
		if not by_part.has(part) or dist < float(by_part[part][0]):
			by_part[part] = [dist, (q - p).normalized() if dist > 1e-6 else Vector2.ZERO]
	var span := -1.0
	var hits: Array = by_part.values()
	for i in hits.size():
		if (hits[i][1] as Vector2) == Vector2.ZERO:
			span = 0.0
			break
		for j in range(i + 1, hits.size()):
			if (hits[i][1] as Vector2).dot(hits[j][1]) < -0.5:
				var sp: float = hits[i][0] + hits[j][0]
				if span < 0.0 or sp < span:
					span = sp
	return {"id": best_id, "d": best_d, "span": span}


static func _bounds(outline: Array) -> Rect2:
	var r := Rect2(Vector2(float(outline[0][0]), float(outline[0][1])), Vector2.ZERO)
	for p: Array in outline:
		r = r.expand(Vector2(float(p[0]), float(p[1])))
	return r


static func _outline_dist(outline: Array, p: Vector3) -> float:
	var best := INF
	var n := outline.size()
	for i in n:
		var a: Array = outline[i]
		var b: Array = outline[(i + 1) % n]
		best = minf(best, _plan_dist(p, Vector3(float(a[0]), 0, float(a[1])), Vector3(float(b[0]), 0, float(b[1]))))
	return best
