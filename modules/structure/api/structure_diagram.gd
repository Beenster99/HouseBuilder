class_name StructureDiagram
extends RefCounted
## The stress test drawn like a finite-element plot: every wall, floor, beam, column and
## foundation shaded across its surface by how hard it is working, blue (idle) through green
## and amber to red (failed), with the worst spots picked out. build() works it out from the
## graph and a full report (on the host, off the main thread); the result is plain packed
## arrays, small enough to send with each live report.
##
## How the stress varies along a member comes from what governs it: bending peaks mid-span
## (at the root of a cantilever), shear at the supports, and a column or wall carries the most
## at its foot. A floor peaks furthest from what holds it up. These are the shapes an FE plot
## would show; the peak value is the solver's own.
##
## Result: {
##   "bars": PackedVector3Array (a, b per bar), "bar_d": PackedFloat32Array (box size, m),
##   "bar_u": PackedByteArray (SAMPLES per bar, a to b),
##   "pan_o", "pan_x", "pan_y", "pan_n": PackedVector3Array (corner, full length, full height
##       and half-thickness offset of each panel), "pan_cr": PackedInt32Array (cols, rows),
##   "pan_u": PackedByteArray (cols * rows per panel, row by row), "pan_m": PackedByteArray
##       ((cols - 1) * (rows - 1) per panel: 1 = draw the cell),
##   "hot_p": PackedVector3Array, "hot_u": PackedFloat32Array, "hot_t": PackedStringArray
##       (the worst spots, worst first) }
## Utilisation bytes are u * 100, so 255 means 2.55 or more.

## Points along each bar.
const SAMPLES := 5
## Worst spots marked.
const HOT_COUNT := 6
## Grid spacing over walls and floors, m (coarser on big ones).
const CELL := 0.4
const MAX_CELLS := 48
const BAR_SIZE := 0.15


## Utilisation to the stored byte and back.
static func to_byte(u: float) -> int:
	return clampi(roundi(u * 100.0), 0, 255)


static func from_byte(b: int) -> float:
	return float(b) / 100.0


## The FE colour scale: 0 blue, 0.35 green, 0.7 amber, 1 red, towards 2 deep crimson.
static func colour(u: float) -> Color:
	const STOPS := [[0.0, Color(0.16, 0.32, 0.95)], [0.2, Color(0.1, 0.7, 0.9)],
			[0.4, Color(0.15, 0.82, 0.35)], [0.7, Color(1.0, 0.78, 0.12)],
			[1.0, Color(0.95, 0.18, 0.1)], [2.0, Color(0.6, 0.0, 0.3)]]
	if u <= 0.0:
		return STOPS[0][1]
	for i in range(1, STOPS.size()):
		if u <= float(STOPS[i][0]):
			var lo: Array = STOPS[i - 1]
			var hi: Array = STOPS[i]
			return (lo[1] as Color).lerp(hi[1], (u - float(lo[0])) / (float(hi[0]) - float(lo[0])))
	return STOPS[STOPS.size() - 1][1]


## How much of the peak shows at t (0..1 along the member) for a row's mode. root: the
## supported end of a cantilever (0 or 1), low: the lower end of an upright (0 or 1).
static func profile(mode: String, t: float, cantilever: bool, root: float, low: float) -> float:
	match mode:
		"unsupported":
			return 1.0
		"shear":
			return 0.45 + 0.55 * absf(2.0 * t - 1.0)
		"bending":
			if cantilever:
				return 1.0 - 0.85 * absf(t - root)
			return 0.3 + 0.7 * 4.0 * t * (1.0 - t)
		"bearing":
			return 1.0
	# axial: heaviest at the foot
	return 0.82 + 0.18 * (1.0 - absf(t - low))


static func build(g: StructureGraph, report: StructureReport) -> Dictionary:
	var out := {"bars": PackedVector3Array(), "bar_d": PackedFloat32Array(), "bar_u": PackedByteArray(),
			"pan_o": PackedVector3Array(), "pan_x": PackedVector3Array(), "pan_y": PackedVector3Array(),
			"pan_n": PackedVector3Array(), "pan_cr": PackedInt32Array(), "pan_u": PackedByteArray(),
			"pan_m": PackedByteArray(), "hot_p": PackedVector3Array(), "hot_u": PackedFloat32Array(),
			"hot_t": PackedStringArray()}
	if g == null or report == null:
		return out
	# The worst row of each member and anchor over every scenario.
	var env := {}
	for r in report.results:
		for dict: Dictionary in [r.members, r.anchors]:
			for id: String in dict:
				var row: Dictionary = dict[id]
				if not env.has(id) or float(row.u) > float(env[id].u):
					env[id] = row
	var hot: Array = []  # [u, pos, text]
	var degree := {}
	for id: String in g.members:
		var m: Dictionary = g.members[id]
		degree[m.a] = int(degree.get(m.a, 0)) + 1
		degree[m.b] = int(degree.get(m.b, 0)) + 1
	var by_part := {}  # wall part -> [member ids]
	var chains := {}  # chain id -> [member ids]
	var ids := g.members.keys()
	ids.sort()
	for id: String in ids:
		var m: Dictionary = g.members[id]
		var part := str(m.part)
		if g.shapes.has(part) and str(g.shapes[part].type) == "wall":
			if not by_part.has(part):
				by_part[part] = []
			by_part[part].append(id)
		elif m.kind != StructureGraph.WALL:
			var c := str(m.get("chain", id))
			if not chains.has(c):
				chains[c] = []
			chains[c].append(id)
	for c: String in chains:
		_bars(g, chains[c], env, degree, out, hot)
	var parts := by_part.keys()
	parts.sort()
	for part: String in parts:
		_wall(g, part, by_part[part], env, out, hot)
	var plate_ids := g.plates.keys()
	plate_ids.sort()
	for pid: String in plate_ids:
		_plate(g, pid, env, out, hot)
	var anchor_ids := g.anchor_ids()
	for n: String in anchor_ids:
		if not env.has(n):
			continue
		var p: Vector3 = g.nodes[n].pos
		var u := float(env[n].u)
		out.bars.append(p + Vector3(0, -0.35, 0))
		out.bars.append(p)
		out.bar_d.append(0.55)
		for k in SAMPLES:
			out.bar_u.append(to_byte(u))
		if u >= StructureResult.AMBER:
			hot.append([u, p, "foundation", str(env[n].get("part", n))])
	# The worst spots, one per part.
	hot.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) > float(y[0]))
	var seen := {}
	for h: Array in hot:
		if out.hot_p.size() >= HOT_COUNT:
			break
		if seen.has(h[3]):
			continue
		seen[h[3]] = true
		out.hot_p.append(h[1])
		out.hot_u.append(float(h[0]))
		out.hot_t.append(str(h[2]))
	return out


## A run of bars that bend as one (a chain): t runs along the whole chain.
static func _bars(g: StructureGraph, mids: Array, env: Dictionary, degree: Dictionary,
		out: Dictionary, hot: Array) -> void:
	var first: Dictionary = g.members[mids[0]]
	var a0: Vector3 = g.nodes[first.a].pos
	var dir: Vector3 = (g.nodes[first.b].pos as Vector3) - a0
	dir = dir.normalized() if dir.length_squared() > 1e-9 else Vector3.RIGHT
	var lo := INF
	var hi := -INF
	for id: String in mids:
		var m: Dictionary = g.members[id]
		for n: String in [m.a, m.b]:
			var s := ((g.nodes[n].pos as Vector3) - a0).dot(dir)
			lo = minf(lo, s)
			hi = maxf(hi, s)
	var span := maxf(hi - lo, 0.001)
	for id: String in mids:
		if not env.has(id):
			continue
		var m: Dictionary = g.members[id]
		var pa: Vector3 = g.nodes[m.a].pos
		var pb: Vector3 = g.nodes[m.b].pos
		var row: Dictionary = env[id]
		var u := float(row.u)
		var mode := str(row.get("mode", "axial"))
		var cant := bool(row.get("cantilever", false))
		var ta := (pa - a0).dot(dir)
		var tb := (pb - a0).dot(dir)
		var chained := mids.size() > 1
		# Cantilever root: the end more members meet at.
		var root := 0.0 if int(degree.get(m.a, 0)) >= int(degree.get(m.b, 0)) else 1.0
		var low := 0.0 if pa.y <= pb.y else 1.0
		var best := -1.0
		var best_p := pa
		for k in SAMPLES:
			var f := float(k) / float(SAMPLES - 1)
			var t := f
			if chained and mode in ["bending", "shear"] and not cant:
				t = (lerpf(ta, tb, f) - lo) / span
			var v := u * profile(mode, t, cant, root, low)
			out.bar_u.append(to_byte(v))
			if v > best:
				best = v
				best_p = pa.lerp(pb, f)
		out.bars.append(pa)
		out.bars.append(pb)
		var d := BAR_SIZE
		if g.shapes.has(id):
			d = float(g.shapes[id].get("d", BAR_SIZE))
		elif g.plates.has(str(m.part)):
			d = BAR_SIZE
		out.bar_d.append(clampf(d, 0.08, 0.6) + 0.04)
		if u >= StructureResult.AMBER:
			hot.append([u, best_p, "%s, %s" % [str(m.get("label", id)), mode], str(m.part)])


## One wall as a panel: the uprights' stresses blended along it, the lintels and sills over
## and under its openings, the openings left out.
static func _wall(g: StructureGraph, part: String, mids: Array, env: Dictionary, out: Dictionary,
		hot: Array) -> void:
	var sh: Dictionary = g.shapes[part]
	var a: Vector3 = sh.a
	var b: Vector3 = sh.b
	var h: float = sh.h
	var length := a.distance_to(b)
	if length < 0.01 or h < 0.01:
		return
	var along := (b - a) / length
	var ups: Array = []  # [x, u, mode]
	var beams: Array = []  # [x0, x1, top: bool, band, u, mode]
	for id: String in mids:
		if not env.has(id):
			continue
		var m: Dictionary = g.members[id]
		var row: Dictionary = env[id]
		var pa: Vector3 = g.nodes[m.a].pos
		var pb: Vector3 = g.nodes[m.b].pos
		if m.kind == StructureGraph.WALL:
			ups.append([(pa - a).dot(along), float(row.u), str(row.get("mode", "axial"))])
		else:
			var x0 := (pa - a).dot(along)
			var x1 := (pb - a).dot(along)
			var top := pa.y > a.y + h * 0.5
			beams.append([minf(x0, x1), maxf(x0, x1), top, 0.0, float(row.u), str(row.get("mode", "bending"))])
	ups.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	var openings: Array = sh.get("openings", [])
	var cols := clampi(ceili(length / CELL) + 1, 2, MAX_CELLS + 1)
	var rows := clampi(ceili(h / CELL) + 1, 2, MAX_CELLS + 1)
	var peak := -1.0
	var peak_p := a
	var peak_mode := ""
	for j in rows:
		var s := float(j) / float(rows - 1)
		var y := s * h
		for i in cols:
			var x := float(i) / float(cols - 1) * length
			var v := _wall_u(ups, x, s)
			for bm: Array in beams:
				if x < float(bm[0]) - 0.001 or x > float(bm[1]) + 0.001:
					continue
				var band := _band(openings, x / length, h, bool(bm[2]))
				var inside: bool = (y >= h - band - 0.001) if bool(bm[2]) else (y <= band + 0.001)
				if inside:
					var t := (x - float(bm[0])) / maxf(float(bm[1]) - float(bm[0]), 0.001)
					v = maxf(v, float(bm[4]) * profile(str(bm[5]), t, false, 0.0, 0.0))
			out.pan_u.append(to_byte(v))
			if v > peak:
				peak = v
				peak_p = a + along * x + Vector3(0, y, 0)
				peak_mode = "wall"
	for j in rows - 1:
		var yc := (float(j) + 0.5) / float(rows - 1) * h
		for i in cols - 1:
			var tc := (float(i) + 0.5) / float(cols - 1)
			var keep := 1
			for o: Array in openings:
				if tc > float(o[0]) and tc < float(o[1]) and yc > float(o[2]) and yc < float(o[3]):
					keep = 0
			out.pan_m.append(keep)
	var normal := along.cross(Vector3.UP).normalized()
	out.pan_o.append(a)
	out.pan_x.append(b - a)
	out.pan_y.append(Vector3(0, h, 0))
	out.pan_n.append(normal * (float(sh.get("d", 0.2)) * 0.5 + 0.02))
	out.pan_cr.append(cols)
	out.pan_cr.append(rows)
	if peak >= StructureResult.AMBER:
		var label := str(g.members[mids[0]].get("label", part))
		hot.append([peak, peak_p, "%s, %s" % [label, peak_mode], part])


## The uprights' stress at x along the wall and s up it, blended between neighbours.
static func _wall_u(ups: Array, x: float, s: float) -> float:
	if ups.is_empty():
		return 0.0
	var lo: Array = ups[0]
	var hi: Array = ups[ups.size() - 1]
	for k in ups.size():
		if float(ups[k][0]) <= x:
			lo = ups[k]
		if float(ups[k][0]) >= x:
			hi = ups[k]
			break
	var span := float(hi[0]) - float(lo[0])
	var f := 0.0 if span < 0.001 else (x - float(lo[0])) / span
	var vl := float(lo[1]) * profile(str(lo[2]), s, false, 0.0, 0.0)
	var vh := float(hi[1]) * profile(str(hi[2]), s, false, 0.0, 0.0)
	return lerpf(vl, vh, clampf(f, 0.0, 1.0))


## How deep the wall's beam band is at t along it: over an opening, from its head up (top)
## or its sill down (bottom); elsewhere a third of the wall.
static func _band(openings: Array, t: float, h: float, top: bool) -> float:
	for o: Array in openings:
		if t > float(o[0]) and t < float(o[1]):
			return maxf(h - float(o[3]), 0.05) if top else float(o[2])
	return h * 0.33


## A floor or roof as a sheet: stress growing away from its supports (or towards them for
## a cantilever), cut to its outline.
static func _plate(g: StructureGraph, pid: String, env: Dictionary, out: Dictionary, hot: Array) -> void:
	if not env.has(pid) or not g.shapes.has(pid):
		return
	var sh: Dictionary = g.shapes[pid]
	if float(sh.get("pitch", 0.0)) > 0.5:
		return  # pitched roofs: their rafters show it
	var outline: Array = sh.outline
	if outline.size() < 3:
		return
	var row: Dictionary = env[pid]
	var u := float(row.u)
	var pl: Dictionary = g.plates[pid]
	var span := maxf(float(pl.span), 0.5)
	var cant := bool(pl.cantilever)
	var segs: Array = []  # [Vector2, Vector2]
	for mid: String in pl.supports:
		if g.members.has(mid):
			var m: Dictionary = g.members[mid]
			var pa: Vector3 = g.nodes[m.a].pos
			var pb: Vector3 = g.nodes[m.b].pos
			segs.append([Vector2(pa.x, pa.z), Vector2(pb.x, pb.z)])
	if segs.is_empty():
		for i in outline.size():
			segs.append([outline[i], outline[(i + 1) % outline.size()]])
	var poly := PackedVector2Array(outline)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector2 in outline:
		lo = lo.min(p)
		hi = hi.max(p)
	var size := hi - lo
	var cell := maxf(CELL, maxf(size.x, size.y) / float(MAX_CELLS))
	var cols := clampi(ceili(size.x / cell) + 1, 2, MAX_CELLS + 1)
	var rows := clampi(ceili(size.y / cell) + 1, 2, MAX_CELLS + 1)
	var y := float(sh.y)
	var d := float(sh.get("d", 0.2))
	var peak := -1.0
	var peak_p := Vector3.ZERO
	for j in rows:
		for i in cols:
			var p := lo + Vector2(size.x * float(i) / float(cols - 1), size.y * float(j) / float(rows - 1))
			var dist := INF
			for sg: Array in segs:
				dist = minf(dist, p.distance_to(Geometry2D.get_closest_point_to_segment(p, sg[0], sg[1])))
			var f := 0.0
			if cant:
				f = 1.0 - 0.85 * clampf(dist / span, 0.0, 1.0)
			else:
				f = 0.2 + 0.8 * sin(PI * 0.5 * clampf(dist / (span * 0.5), 0.0, 1.0))
			var v := u * f
			out.pan_u.append(to_byte(v))
			if v > peak and Geometry2D.is_point_in_polygon(p, poly):
				peak = v
				peak_p = Vector3(p.x, y, p.y)
	for j in rows - 1:
		for i in cols - 1:
			var c := lo + Vector2(size.x * (float(i) + 0.5) / float(cols - 1), size.y * (float(j) + 0.5) / float(rows - 1))
			out.pan_m.append(1 if Geometry2D.is_point_in_polygon(c, poly) else 0)
	# Its centre plane half its depth under the top; drawn on both faces.
	out.pan_o.append(Vector3(lo.x, y - d * 0.5, lo.y))
	out.pan_x.append(Vector3(size.x, 0, 0))
	out.pan_y.append(Vector3(0, 0, size.y))
	out.pan_n.append(Vector3(0, d * 0.5 + 0.02, 0))
	out.pan_cr.append(cols)
	out.pan_cr.append(rows)
	if u >= StructureResult.AMBER:
		hot.append([u, peak_p if peak >= 0.0 else Vector3(lo.x, y, lo.y), "%s, %s" % [str(pl.get("label", pid)), str(row.get("mode", "bending"))], str(pl.get("part", pid))])
