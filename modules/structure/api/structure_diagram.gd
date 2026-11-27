class_name StructureDiagram
extends RefCounted
## The stress test drawn the way finite-element software plots it: every wall, floor, beam,
## column and foundation meshed into small elements and contoured by how hard it is working,
## in banded rainbow colours from blue (least) through cyan, green and yellow to red (most),
## with a legend and the maximum and minimum tagged. build() works it out from the graph and
## a full report (on the host, off the main thread); the result is plain packed arrays, small
## enough to send with each live report.
##
## The value is utilisation (load over capacity). How it varies across a part follows what
## governs it: bending peaks mid-span (at the root of a cantilever, and over inner supports of
## a floor), shear at the supports, and a wall or column carries the most at its foot. The
## lintels' and sills' stress gathers at the corners of doors and windows. The peaks are the
## solver's own values.
##
## Result: {
##   "bars": PackedVector3Array (a, b per bar), "bar_d": PackedFloat32Array (box size, m),
##   "bar_u": PackedByteArray (SAMPLES per bar, a to b),
##   "pan_o", "pan_x", "pan_y", "pan_n": PackedVector3Array (corner, full length, full height
##       and half-thickness of each panel), "pan_cr": PackedInt32Array (cols, rows),
##   "pan_u": PackedByteArray (cols * rows per panel, row by row), "pan_m": PackedByteArray
##       ((cols - 1) * (rows - 1) per panel: 1 = an element there),
##   "hot_p", "hot_u", "hot_t": the worst spots, worst first (point, utilisation, what),
##   "min_p": Vector3, "min_u": float (the least loaded point),
##   "top": the legend's top value (utilisation), "box_lo", "box_hi": Vector3 extent,
##   "cut_y": when the worst spot is a floor inside the building, a height to cut the plot
##       at so it shows (a section view), else a height over everything }
## Utilisation bytes are u * 100, so 255 means 2.55 or more.

## Points along each bar.
const SAMPLES := 9
## Worst spots tagged.
const HOT_COUNT := 3
## Element size over walls and floors, m (coarser on big ones).
const CELL := 0.25
const MAX_CELLS := 64
const BAR_SIZE := 0.15
## Contour bands on the plot and its legend.
const BANDS := 12
## A section cut this far over a failing floor shows it from above, m.
const CUT_OVER := 1.1
const NO_CUT := 10000.0
## How far the stress round a door or window corner reaches, m.
const CORNER_REACH := 0.45


## Utilisation to the stored byte and back.
static func to_byte(u: float) -> int:
	return clampi(roundi(u * 100.0), 0, 255)


static func from_byte(b: int) -> float:
	return float(b) / 100.0


## The contour colour at t (0 bottom of the legend, 1 top): blue, cyan, green, yellow, red.
static func jet(t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	return Color(clampf(1.5 - absf(4.0 * t - 3.0), 0.0, 1.0), clampf(1.5 - absf(4.0 * t - 2.0), 0.0, 1.0),
			clampf(1.5 - absf(4.0 * t - 1.0), 0.0, 1.0))


## The banded colour for utilisation u on a legend topping out at top.
static func colour(u: float, top: float = 1.0) -> Color:
	var t := clampf(u / maxf(top, 0.001), 0.0, 1.0)
	return jet((minf(floorf(t * BANDS), BANDS - 1.0) + 0.5) / BANDS)


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
			return 0.15 + 0.85 * sin(PI * clampf(t, 0.0, 1.0))
		"bearing":
			return 1.0
	# axial: heaviest at the foot
	return 0.75 + 0.25 * (1.0 - absf(t - low))


static func build(g: StructureGraph, report: StructureReport) -> Dictionary:
	var out := {"bars": PackedVector3Array(), "bar_d": PackedFloat32Array(), "bar_u": PackedByteArray(),
			"pan_o": PackedVector3Array(), "pan_x": PackedVector3Array(), "pan_y": PackedVector3Array(),
			"pan_n": PackedVector3Array(), "pan_cr": PackedInt32Array(), "pan_u": PackedByteArray(),
			"pan_m": PackedByteArray(), "hot_p": PackedVector3Array(), "hot_u": PackedFloat32Array(),
			"hot_t": PackedStringArray(), "min_p": Vector3.ZERO, "min_u": 0.0, "top": 1.0,
			"box_lo": Vector3.ZERO, "box_hi": Vector3.ZERO, "cut_y": NO_CUT}
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
	var st := {"hot": [], "min_u": INF, "min_p": Vector3.ZERO, "lo": Vector3(INF, INF, INF), "hi": -Vector3(INF, INF, INF)}
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
	var chain_ids := chains.keys()
	chain_ids.sort()
	for c: String in chain_ids:
		_bars(g, chains[c], env, degree, out, st)
	var parts := by_part.keys()
	parts.sort()
	for part: String in parts:
		_wall(g, part, by_part[part], env, out, st)
	var plate_ids := g.plates.keys()
	plate_ids.sort()
	for pid: String in plate_ids:
		_plate(g, pid, env, out, st)
	for n: String in g.anchor_ids():
		if not env.has(n):
			continue
		var p: Vector3 = g.nodes[n].pos
		var u := float(env[n].u)
		_bar(out, st, p + Vector3(0, -0.35, 0), p, 0.55, func(_f: float) -> float: return u)
		st.hot.append([u, p, "Foundation", str(env[n].get("part", n))])
	# The worst spots, one per part.
	var hot: Array = st.hot
	hot.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) > float(y[0]))
	var seen := {}
	for h: Array in hot:
		if out.hot_p.size() >= HOT_COUNT:
			break
		# The worst always; others only when over capacity.
		if seen.has(h[3]) or float(h[0]) <= 0.0 or (not out.hot_p.is_empty() and float(h[0]) < 1.0):
			continue
		if out.hot_p.is_empty() and h.size() > 4 and bool(h[4]) and st.hi.y > (h[1] as Vector3).y + CUT_OVER + 0.3:
			out.cut_y = (h[1] as Vector3).y + CUT_OVER
		seen[h[3]] = true
		out.hot_p.append(h[1])
		out.hot_u.append(float(h[0]))
		out.hot_t.append(str(h[2]))
	# The legend tops out at the worst value (a part with no support counts as 2.5), rounded
	# up to 5 %.
	var peak := 0.0
	for b in out.pan_u:
		peak = maxf(peak, from_byte(b))
	for b in out.bar_u:
		peak = maxf(peak, from_byte(b))
	out.top = clampf(ceilf(peak * 20.0 - 0.001) / 20.0, 0.1, 2.55)
	if st.min_u < INF:
		out.min_u = st.min_u
		out.min_p = st.min_p
	if st.lo.x < INF:
		out.box_lo = st.lo
		out.box_hi = st.hi
	return out


static func _seen(st: Dictionary, p: Vector3, v: float) -> void:
	st.lo = (st.lo as Vector3).min(p)
	st.hi = (st.hi as Vector3).max(p)
	if v < float(st.min_u):
		st.min_u = v
		st.min_p = p


## One bar, a to b, with value(f) at each of SAMPLES points.
static func _bar(out: Dictionary, st: Dictionary, a: Vector3, b: Vector3, size: float, value: Callable) -> Array:
	var best := [-1.0, a]
	for k in SAMPLES:
		var f := float(k) / float(SAMPLES - 1)
		var v: float = value.call(f)
		var p := a.lerp(b, f)
		out.bar_u.append(to_byte(v))
		_seen(st, p, v)
		if v > float(best[0]):
			best = [v, p]
	out.bars.append(a)
	out.bars.append(b)
	out.bar_d.append(size)
	return best


## A run of bars that bend as one (a chain): t runs along the whole chain.
static func _bars(g: StructureGraph, mids: Array, env: Dictionary, degree: Dictionary,
		out: Dictionary, st: Dictionary) -> void:
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
		var whole := mids.size() > 1 and mode in ["bending", "shear"] and not cant
		# Cantilever root: the end more members meet at.
		var root := 0.0 if int(degree.get(m.a, 0)) >= int(degree.get(m.b, 0)) else 1.0
		var low := 0.0 if pa.y <= pb.y else 1.0
		var d := BAR_SIZE
		if g.shapes.has(id):
			d = float(g.shapes[id].get("d", BAR_SIZE))
		var best := _bar(out, st, pa, pb, clampf(d, 0.08, 0.6) + 0.04, func(f: float) -> float:
			var t := (lerpf(ta, tb, f) - lo) / span if whole else f
			return u * profile(mode, t, cant, root, low))
		st.hot.append([float(best[0]), best[1], str(m.get("label", id)), str(m.part)])


## One wall: the uprights' stresses blended along it, the lintels and sills over and under
## its openings with their stress gathering at the corners, the openings left out.
static func _wall(g: StructureGraph, part: String, mids: Array, env: Dictionary, out: Dictionary,
		st: Dictionary) -> void:
	var sh: Dictionary = g.shapes[part]
	var a: Vector3 = sh.a
	var b: Vector3 = sh.b
	var h: float = sh.h
	var length := a.distance_to(b)
	if length < 0.01 or h < 0.01:
		return
	var along := (b - a) / length
	var ups: Array = []  # [x, u, mode]
	var beams: Array = []  # [x0, x1, top: bool, u, mode]
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
			beams.append([minf(x0, x1), maxf(x0, x1), pa.y > a.y + h * 0.5, float(row.u), str(row.get("mode", "bending"))])
	ups.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	var openings: Array = sh.get("openings", [])
	# Opening corners and the stress of the lintel or sill there: [x, y, u].
	var corners: Array = []
	for o: Array in openings:
		var x0 := float(o[0]) * length
		var x1 := float(o[1]) * length
		var mid := (x0 + x1) * 0.5
		for bm: Array in beams:
			if mid < float(bm[0]) or mid > float(bm[1]):
				continue
			if bool(bm[2]):
				corners.append([x0, float(o[3]), float(bm[3])])
				corners.append([x1, float(o[3]), float(bm[3])])
			elif float(o[2]) > 0.05:
				corners.append([x0, float(o[2]), float(bm[3])])
				corners.append([x1, float(o[2]), float(bm[3])])
	var cols := clampi(ceili(length / CELL) + 1, 2, MAX_CELLS + 1)
	var rows := clampi(ceili(h / CELL) + 1, 2, MAX_CELLS + 1)
	var grid := PackedFloat32Array()
	grid.resize(cols * rows)
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
					v = maxf(v, float(bm[3]) * profile(str(bm[4]), t, false, 0.0, 0.0))
			for c: Array in corners:
				var r2 := (Vector2(x, y) - Vector2(float(c[0]), float(c[1]))).length_squared()
				v = maxf(v, float(c[2]) * exp(-r2 / (CORNER_REACH * CORNER_REACH)))
			grid[j * cols + i] = v
	grid = _smooth(grid, cols, rows)
	var peak := [-1.0, a]
	for j in rows:
		for i in cols:
			var v := grid[j * cols + i]
			out.pan_u.append(to_byte(v))
			var p := a + along * (float(i) / float(cols - 1) * length) + Vector3(0, float(j) / float(rows - 1) * h, 0)
			_seen(st, p, v)
			if v > float(peak[0]):
				peak = [v, p]
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
	out.pan_n.append(normal * (float(sh.get("d", 0.2)) * 0.5 + 0.015))
	out.pan_cr.append(cols)
	out.pan_cr.append(rows)
	st.hot.append([float(peak[0]), peak[1], str(g.members[mids[0]].get("label", part)), part])


## One light pass of smoothing, as a finite-element plot averages at the nodes. Peaks keep
## most of their height.
static func _smooth(grid: PackedFloat32Array, cols: int, rows: int) -> PackedFloat32Array:
	var out := grid.duplicate()
	for j in rows:
		for i in cols:
			var sum := grid[j * cols + i] * 4.0
			var w := 4.0
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ii := i + d.x
				var jj := j + d.y
				if ii >= 0 and ii < cols and jj >= 0 and jj < rows:
					sum += grid[jj * cols + ii]
					w += 1.0
			out[j * cols + i] = maxf(sum / w, grid[j * cols + i] * 0.85)
	return out


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
	f = f * f * (3.0 - 2.0 * f)
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


## A floor or roof: stress growing away from its supports (or towards them for a
## cantilever) and over its inner supports, cut to its outline.
static func _plate(g: StructureGraph, pid: String, env: Dictionary, out: Dictionary, st: Dictionary) -> void:
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
	var segs: Array = []  # [Vector2, Vector2, inner: bool]
	var edges: Array = []
	for i in outline.size():
		edges.append([outline[i], outline[(i + 1) % outline.size()]])
	for mid: String in pl.supports:
		if g.members.has(mid):
			var m: Dictionary = g.members[mid]
			var pa: Vector3 = g.nodes[m.a].pos
			var pb: Vector3 = g.nodes[m.b].pos
			var a2 := Vector2(pa.x, pa.z)
			var b2 := Vector2(pb.x, pb.z)
			var c2 := (a2 + b2) * 0.5
			var edge := INF
			for e: Array in edges:
				edge = minf(edge, c2.distance_to(Geometry2D.get_closest_point_to_segment(c2, e[0], e[1])))
			segs.append([a2, b2, edge > 0.4])
	if segs.is_empty():
		for e: Array in edges:
			segs.append([e[0], e[1], false])
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
	var grid := PackedFloat32Array()
	grid.resize(cols * rows)
	for j in rows:
		for i in cols:
			var p := lo + Vector2(size.x * float(i) / float(cols - 1), size.y * float(j) / float(rows - 1))
			var dist := INF
			var hog := 0.0
			for sg: Array in segs:
				var r := p.distance_to(Geometry2D.get_closest_point_to_segment(p, sg[0], sg[1]))
				dist = minf(dist, r)
				if bool(sg[2]):
					hog = maxf(hog, 0.8 * exp(-pow(r / (0.18 * span), 2.0)))
			var f := 0.0
			if cant:
				f = 1.0 - 0.85 * clampf(dist / span, 0.0, 1.0)
			else:
				f = 0.1 + 0.9 * sin(PI * 0.5 * clampf(dist / (span * 0.5), 0.0, 1.0))
			grid[j * cols + i] = u * maxf(f, hog)
	grid = _smooth(grid, cols, rows)
	var peak := [-1.0, Vector3(lo.x, y, lo.y)]
	for j in rows:
		for i in cols:
			var v := grid[j * cols + i]
			out.pan_u.append(to_byte(v))
			var p2 := lo + Vector2(size.x * float(i) / float(cols - 1), size.y * float(j) / float(rows - 1))
			if Geometry2D.is_point_in_polygon(p2, poly):
				var p := Vector3(p2.x, y, p2.y)
				_seen(st, p, v)
				if v > float(peak[0]):
					peak = [v, p]
	for j in rows - 1:
		for i in cols - 1:
			var c := lo + Vector2(size.x * (float(i) + 0.5) / float(cols - 1), size.y * (float(j) + 0.5) / float(rows - 1))
			out.pan_m.append(1 if Geometry2D.is_point_in_polygon(c, poly) else 0)
	# Its centre plane half its depth under the top.
	out.pan_o.append(Vector3(lo.x, y - d * 0.5, lo.y))
	out.pan_x.append(Vector3(size.x, 0, 0))
	out.pan_y.append(Vector3(0, 0, size.y))
	out.pan_n.append(Vector3(0, d * 0.5 + 0.015, 0))
	out.pan_cr.append(cols)
	out.pan_cr.append(rows)
	st.hot.append([float(peak[0]), peak[1], str(pl.get("label", pid)), str(pl.get("part", pid)), true])
