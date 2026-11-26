extends RefCounted
## Layer 1 structural solver: a simplified load-path model on the StructureGraph.
##
## Gravity. Every node's distance to the ground is the cheapest route to a foundation,
## where a metre of post costs 1, of diagonal 2 and of beam 4 (so loads prefer to go
## straight down). A node hands its load to the members leading to nodes nearer the
## ground, shared by 1 / route cost; for a beam split at a point load that gives exactly
## the lever-rule reactions. Posts and diagonals carry what they pass on axially; a beam
## that passes load on is a cantilever from the nearer end. A member neither end relies on
## spans between two supports and carries its own load simply supported. Nodes are worked
## from the top of the route tree down, so each load is passed on exactly once.
##
## Sideways (wind, quake). Nodes tied together by beams form a floor that shares sideways
## load. Each floor hands its storey shear to the posts, braces and walls below it by
## sideways stiffness (a brace or a wall in line with the push is far stiffer than a post),
## and they pass it down to the floor or foundations under them. A post bends (shear times
## half its height), a brace takes it axially, a wall racks in shear.
##
## Utilisation = axial / axial capacity + moment / moment capacity, or shear / shear
## capacity if that is higher. Everything is iterated in sorted id order and uses plain
## float maths, so the same graph gives the same numbers on every machine.

const EPS := 1e-9
## sin of the slope above which a member is a post, and below which it is a beam.
const POST_SIN := 0.7
const BEAM_SIN := 0.3
const COST_POST := 1.0
const COST_DIAGONAL := 2.0
const COST_BEAM := 4.0
## Sideways stiffness weights.
const K_COLUMN := 1.0
const K_BRACE := 20.0
const K_WALL := 15.0  # per metre of wall in line with the push
const K_GROUND := 1000.0

enum Orient { POST, DIAGONAL, BEAM }

var g: StructureGraph
var node_ids: Array = []
var member_ids: Array = []
var geo: Dictionary = {}  # member id -> {L, s, c, lh, orient, cost, k_dir: Vector3 or null}
var adj: Dictionary = {}  # node id -> Array of member ids
var dist: Dictionary = {}  # node id -> float (INF = unsupported)
var down: Dictionary = {}  # node id -> Array of member ids leading nearer the ground
var order: Array = []  # supported node ids, furthest from the ground first
var group_of: Dictionary = {}  # supported node id -> floor group id
var groups: Dictionary = {}  # group id -> {"nodes": Array, "top": float, "members": Array, "anchors": Array}
var group_order: Array = []
var chain_of: Dictionary = {}  # beam member id -> chain id (members of one line, see "chain")
var chain_members: Dictionary = {}  # chain id -> Array of member ids
var chain_nodes: Dictionary = {}  # chain id -> Array of node ids, sorted along it
var chain_x: Dictionary = {}  # chain id -> {node id: distance along the chain}
var chain_order: Array = []


func _init(graph: StructureGraph) -> void:
	g = graph
	node_ids = g.nodes.keys()
	node_ids.sort()
	member_ids = g.members.keys()
	member_ids.sort()
	for n: String in node_ids:
		adj[n] = []
	for id: String in member_ids:
		var m: Dictionary = g.members[id]
		var pa: Vector3 = g.nodes[m.a].pos
		var pb: Vector3 = g.nodes[m.b].pos
		var d := pb - pa
		var length := d.length()
		var s := absf(d.y) / length
		var lh := Vector2(d.x, d.z).length()
		var o := Orient.POST if s >= POST_SIN else (Orient.BEAM if s < BEAM_SIN else Orient.DIAGONAL)
		var cost := length * (COST_POST if o == Orient.POST else (COST_BEAM if o == Orient.BEAM else COST_DIAGONAL))
		geo[id] = {"L": length, "s": s, "c": lh / length, "lh": lh, "orient": o, "cost": cost,
				"hdir": Vector3(d.x, 0.0, d.z).normalized() if lh > EPS else Vector3.ZERO}
		adj[m.a].append(id)
		adj[m.b].append(id)
	_route()
	_chains()
	_floors()


func _other(id: String, n: String) -> String:
	var m: Dictionary = g.members[id]
	return m.b if m.a == n else m.a


func supported(n: String) -> bool:
	return dist[n] < INF


# --- Routes to the ground ----------------------------------------------------------------

func _route() -> void:
	# Dijkstra from every foundation; the heap holds [distance, node id].
	var heap: Array = []
	for n: String in node_ids:
		dist[n] = INF
		down[n] = []
		if g.nodes[n].anchor:
			dist[n] = 0.0
			_push(heap, [0.0, n])
	while not heap.is_empty():
		var top: Array = _pop(heap)
		var n: String = top[1]
		if top[0] > dist[n]:
			continue
		for id: String in adj[n]:
			var o := _other(id, n)
			var nd: float = dist[n] + geo[id].cost
			if nd < dist[o] - EPS:
				dist[o] = nd
				_push(heap, [nd, o])
	for n: String in node_ids:
		if dist[n] == INF or g.nodes[n].anchor:
			continue
		for id: String in adj[n]:
			if dist[_other(id, n)] < dist[n] - EPS:
				down[n].append(id)
	for n: String in node_ids:
		if dist[n] < INF:
			order.append(n)
	order.sort_custom(func(x: String, y: String) -> bool:
		return dist[x] > dist[y] or (dist[x] == dist[y] and x < y))


static func _less(x: Array, y: Array) -> bool:
	return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1])


static func _push(heap: Array, e: Array) -> void:
	heap.append(e)
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if not _less(heap[i], heap[p]):
			break
		var t: Array = heap[i]
		heap[i] = heap[p]
		heap[p] = t
		i = p


static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	var size := heap.size()
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var best := i
		if l < size and _less(heap[l], heap[best]):
			best = l
		if r < size and _less(heap[r], heap[best]):
			best = r
		if best == i:
			break
		var t: Array = heap[i]
		heap[i] = heap[best]
		heap[best] = t
		i = best
	return top


## True if member id is the only thing node n hands its load on through.
func _relies_only(id: String, n: String) -> bool:
	return down[n].size() == 1 and down[n][0] == id


func _member_supported(id: String) -> bool:
	var m: Dictionary = g.members[id]
	return supported(m.a) and supported(m.b)


# --- Chains: beams split into pieces along one line, bent span by span -------------------

func _chains() -> void:
	for id: String in member_ids:
		if geo[id].orient != Orient.BEAM:
			continue
		var c := str(g.members[id].get("chain", ""))
		if c == "":
			c = id
		chain_of[id] = c
		if not chain_members.has(c):
			chain_members[c] = []
		chain_members[c].append(id)
	chain_order = chain_members.keys()
	chain_order.sort()
	for c: String in chain_order:
		var first: Dictionary = g.members[chain_members[c][0]]
		var origin: Vector3 = g.nodes[first.a].pos
		var axis: Vector3 = ((g.nodes[first.b].pos as Vector3) - origin).normalized()
		var xs := {}
		for id: String in chain_members[c]:
			for n: String in [g.members[id].a, g.members[id].b]:
				xs[n] = ((g.nodes[n].pos as Vector3) - origin).dot(axis)
		var ns: Array = xs.keys()
		ns.sort_custom(func(p: String, q: String) -> bool: return xs[p] < xs[q] or (xs[p] == xs[q] and p < q))
		chain_x[c] = xs
		chain_nodes[c] = ns


# --- Floors (sideways load sharing) -------------------------------------------------------

func _floors() -> void:
	var parent := {}
	for n: String in order:
		parent[n] = n
	for id: String in member_ids:
		if geo[id].orient != Orient.BEAM or not _member_supported(id):
			continue
		var m: Dictionary = g.members[id]
		var ra := _find(parent, m.a)
		var rb := _find(parent, m.b)
		if ra != rb:
			# Smallest id is the root, so groups are named the same on every machine.
			if ra < rb:
				parent[rb] = ra
			else:
				parent[ra] = rb
	for n: String in node_ids:
		if not supported(n):
			continue
		var root := _find(parent, n)
		group_of[n] = root
		if not groups.has(root):
			groups[root] = {"nodes": [], "top": -INF, "members": [], "anchors": []}
		groups[root].nodes.append(n)
		groups[root].top = maxf(groups[root].top, (g.nodes[n].pos as Vector3).y)
		if g.nodes[n].anchor:
			groups[root].anchors.append(n)
	# Storey members belong to the floor at their upper end.
	for id: String in member_ids:
		if geo[id].orient == Orient.BEAM or not _member_supported(id):
			continue
		var m: Dictionary = g.members[id]
		var upper: String = m.a if (g.nodes[m.a].pos as Vector3).y > (g.nodes[m.b].pos as Vector3).y else m.b
		groups[group_of[upper]].members.append(id)
	group_order = groups.keys()
	group_order.sort_custom(func(x: String, y: String) -> bool:
		return groups[x].top > groups[y].top or (groups[x].top == groups[y].top and x < y))


static func _find(parent: Dictionary, n: String) -> String:
	var r := n
	while parent[r] != r:
		r = parent[r]
	var c := n
	while parent[c] != r:
		var nxt: String = parent[c]
		parent[c] = r
		c = nxt
	return r


# --- Solving -------------------------------------------------------------------------------

func solve(sc: StructureScenario) -> StructureResult:
	var res := StructureResult.new()
	res.scenario_id = sc.id
	res.scenario_title = sc.title
	var grav := _gravity(sc)
	var base_rows: Dictionary = grav.members
	# Without sideways load, the gravity forces are the answer.
	var dirs: Array[Vector3] = []
	if sc.wind_kpa > 0.0 or sc.quake_g > 0.0:
		dirs = sc.directions
	var best := {}
	for id: String in member_ids:
		best[id] = _utilise(id, base_rows[id], {}, -1)
	var mass := _seismic_weight(sc) if sc.quake_g > 0.0 else {}
	for i in dirs.size():
		var lat := _lateral(sc, dirs[i], mass)
		res.base_shear = maxf(res.base_shear, lat.base)
		for id: String in member_ids:
			if not lat.members.has(id):
				continue
			var row := _utilise(id, base_rows[id], lat.members[id], i)
			if row.u > best[id].u:
				best[id] = row
	for id: String in _sorted_keys(g.plates):
		best[id] = _plate(id, sc)
	res.members = best
	for n: String in node_ids:
		if not supported(n):
			res.unsupported_nodes.append(n)
	# A foundation part (a strip or raft under several nodes) spreads its load: each of its
	# nodes reports the whole foundation's load over its whole capacity.
	var part_load := {}
	var part_bearing := {}
	for n: String in g.anchor_ids():
		var part := str(g.nodes[n].get("part", ""))
		if part != "" and part != "ground":
			part_load[part] = float(part_load.get(part, 0.0)) + float(grav.anchors.get(n, 0.0))
			part_bearing[part] = float(part_bearing.get(part, 0.0)) + float(g.nodes[n].bearing)
	for n: String in g.anchor_ids():
		var load: float = grav.anchors.get(n, 0.0)
		var bearing: float = g.nodes[n].bearing
		var part := str(g.nodes[n].get("part", ""))
		var u := load / bearing if bearing > 0.0 else 0.0
		if part_load.has(part) and float(part_bearing[part]) > 0.0:
			u = float(part_load[part]) / float(part_bearing[part])
		res.anchors[n] = {"u": u, "mode": "bearing", "load": load, "bearing": bearing,
				"part": part if part != "" else n}
	res.sort_failures()
	return res


## Gravity forces per member: {"members": id -> {axial, moment, shear, cantilever},
## "anchors": id -> kN}.
func _gravity(sc: StructureScenario) -> Dictionary:
	var f := {}
	var lump := {}  # node id -> {chain id: kN of that chain's own load lumped here}
	for n: String in node_ids:
		f[n] = 0.0
	var rows := {}
	for id: String in member_ids:
		rows[id] = {"axial": 0.0, "moment": 0.0, "shear": 0.0, "cantilever": false}
	var line_w := {}
	for id: String in member_ids:
		if not _member_supported(id):
			continue
		var m: Dictionary = g.members[id]
		var gm: Dictionary = geo[id]
		var w := _line_load(id, sc.dead, sc.live, sc.snow)
		line_w[id] = w
		var total: float = w * gm.L
		var row: Dictionary = rows[id]
		if gm.orient == Orient.BEAM:
			# Beams lump their load on their ends; the span check below bends them.
			var c: String = chain_of[id]
			for n: String in [m.a, m.b]:
				f[n] += total * 0.5
				if not lump.has(n):
					lump[n] = {}
				lump[n][c] = float(lump[n].get(c, 0.0)) + total * 0.5
			continue
		# A cantilever only when one end has nothing else to stand on.
		var on_a := _relies_only(id, m.a)
		var on_b := _relies_only(id, m.b)
		var post: bool = gm.orient == Orient.POST
		if on_a or on_b:
			# Cantilever: the whole member's load goes to the end nearer the ground.
			f[m.b if on_a else m.a] += total
			if not post:
				row.moment += w * gm.c * gm.L * gm.L * 0.5
				row.shear += total * gm.c
				row.cantilever = true
			row.axial += total * gm.s
		else:
			f[m.a] += total * 0.5
			f[m.b] += total * 0.5
			if not post:
				row.moment += w * gm.c * gm.L * gm.L * 0.125
				row.shear += total * gm.c * 0.5
			row.axial += total * gm.s * 0.5
	for n: String in node_ids:
		var loads: Dictionary = g.nodes[n].loads
		f[n] += float(loads.get("dead", 0.0)) * sc.dead + float(loads.get("live", 0.0)) * sc.live \
				+ float(loads.get("snow", 0.0)) * sc.snow
	var anchors := {}
	var point_loads := {}  # chain id -> Array of [x, kN]
	for n: String in order:
		var p: float = f[n]
		if g.nodes[n].anchor:
			anchors[n] = p
			continue
		if absf(p) < EPS:
			continue
		var c := _single_chain(n)
		if c != "":
			# Along a beam: straight to the supports either side of it (lever rule).
			var sides := _chain_supports(c, n)
			if not sides.is_empty():
				var own: float = lump.get(n, {}).get(c, 0.0)
				if not point_loads.has(c):
					point_loads[c] = []
				point_loads[c].append([chain_x[c][n], p - own])
				var xn: float = chain_x[c][n]
				if sides.size() == 2:
					var xl: float = chain_x[c][sides[0]]
					var xr: float = chain_x[c][sides[1]]
					f[sides[0]] += p * (xr - xn) / (xr - xl)
					f[sides[1]] += p * (xn - xl) / (xr - xl)
				else:
					f[sides[0]] += p
				continue
		var wsum := 0.0
		for id: String in down[n]:
			wsum += 1.0 / geo[id].cost
		for id: String in down[n]:
			var share: float = p * (1.0 / geo[id].cost) / wsum
			var gm: Dictionary = geo[id]
			f[_other(id, n)] += share
			var row: Dictionary = rows[id]
			if gm.orient == Orient.BEAM:
				row.shear += absf(share)
				row.moment += absf(share) * gm.lh
				if down[n].size() == 1:
					row.cantilever = true
			else:
				row.axial += share / gm.s
	for c: String in chain_order:
		_bend_chain(c, point_loads.get(c, []), line_w, rows)
	return {"members": rows, "anchors": anchors}


## The chain every member n hands its load to belongs to, if they are all beams of one
## chain; else "".
func _single_chain(n: String) -> String:
	var c := ""
	for id: String in down[n]:
		if geo[id].orient != Orient.BEAM:
			return ""
		if c == "":
			c = chain_of[id]
		elif chain_of[id] != c:
			return ""
	return c


## Nodes of a chain that pass load off it (to a post, another beam, the ground).
func _is_chain_support(c: String, n: String) -> bool:
	if g.nodes[n].anchor:
		return true
	for id: String in down[n]:
		if not chain_of.has(id) or chain_of[id] != c:
			return true
	return false


## The nearest supports of chain c either side of node n that are nearer the ground than n:
## [left, right], or one of them, or [].
func _chain_supports(c: String, n: String) -> Array:
	var xn: float = chain_x[c][n]
	var left := ""
	var right := ""
	for o: String in chain_nodes[c]:
		if o == n or dist[o] >= dist[n] - EPS or not _is_chain_support(c, o):
			continue
		var xo: float = chain_x[c][o]
		if xo < xn and (left == "" or xo > chain_x[c][left]):
			left = o
		elif xo > xn and (right == "" or xo < chain_x[c][right]):
			right = o
	var out: Array = []
	if left != "":
		out.append(left)
	if right != "":
		out.append(right)
	return out


## Bends a chain of beams span by span: simply supported between its supports, and a
## cantilever past the last one. Every member in a span gets the span's moment and shear.
func _bend_chain(c: String, loads: Array, line_w: Dictionary, rows: Dictionary) -> void:
	var xs: Array = []
	for n: String in chain_nodes[c]:
		if supported(n) and _is_chain_support(c, n):
			xs.append(chain_x[c][n])
	if xs.is_empty():
		return
	xs.sort()
	var lo: float = chain_x[c][chain_nodes[c][0]]
	var hi: float = chain_x[c][chain_nodes[c][chain_nodes[c].size() - 1]]
	var regions: Array = []  # [x0, x1, kind]: "span", or "left" / "right" overhang
	if lo < float(xs[0]) - EPS:
		regions.append([lo, xs[0], "left"])
	for i in xs.size() - 1:
		regions.append([xs[i], xs[i + 1], "span"])
	if hi > float(xs.back()) + EPS:
		regions.append([xs.back(), hi, "right"])
	for reg: Array in regions:
		var x0: float = reg[0]
		var x1: float = reg[1]
		if x1 - x0 < EPS:
			continue
		var pieces: Array = []  # [start, end, w, id]
		for id: String in chain_members[c]:
			if not line_w.has(id):
				continue
			var xa: float = chain_x[c][g.members[id].a]
			var xb: float = chain_x[c][g.members[id].b]
			var s0 := minf(xa, xb)
			var s1 := maxf(xa, xb)
			var mid := (s0 + s1) * 0.5
			if mid > x0 and mid < x1:
				pieces.append([s0, s1, float(line_w[id]) * float(geo[id].c), id])
		var pts: Array = []
		for pl: Array in loads:
			if float(pl[0]) > x0 + EPS and float(pl[0]) < x1 - EPS:
				pts.append(pl)
		var moment := 0.0
		var shear := 0.0
		if reg[2] == "span":
			var length := x1 - x0
			var total := 0.0
			var about_x1 := 0.0
			for pl: Array in pts:
				total += float(pl[1])
				about_x1 += float(pl[1]) * (x1 - float(pl[0]))
			for pc: Array in pieces:
				var wl: float = pc[2] * (pc[1] - pc[0])
				total += wl
				about_x1 += wl * (x1 - (pc[0] + pc[1]) * 0.5)
			var r0 := about_x1 / length
			shear = maxf(absf(r0), absf(total - r0))
			var probes: Array = []
			for pl: Array in pts:
				probes.append(pl[0])
			for pc: Array in pieces:
				probes.append(pc[0])
				probes.append((pc[0] + pc[1]) * 0.5)
				probes.append(pc[1])
			for x: float in probes:
				var mx := r0 * (x - x0)
				for pl: Array in pts:
					if float(pl[0]) < x:
						mx -= float(pl[1]) * (x - float(pl[0]))
				for pc: Array in pieces:
					if pc[1] <= x:
						mx -= pc[2] * (pc[1] - pc[0]) * (x - (pc[0] + pc[1]) * 0.5)
					elif pc[0] < x:
						mx -= pc[2] * (x - pc[0]) * (x - pc[0]) * 0.5
				moment = maxf(moment, absf(mx))
		else:
			var xs_: float = x1 if reg[2] == "left" else x0
			for pl: Array in pts:
				shear += float(pl[1])
				moment += float(pl[1]) * absf(float(pl[0]) - xs_)
			for pc: Array in pieces:
				var wl: float = pc[2] * (pc[1] - pc[0])
				shear += wl
				moment += wl * absf((pc[0] + pc[1]) * 0.5 - xs_)
			# The free end itself.
			for pl: Array in loads:
				if absf(float(pl[0]) - (x0 if reg[2] == "left" else x1)) <= EPS:
					shear += float(pl[1])
					moment += float(pl[1]) * (x1 - x0)
		for pc: Array in pieces:
			var row: Dictionary = rows[pc[3]]
			row.moment += moment
			row.shear += absf(shear)
			if reg[2] != "span":
				row.cantilever = true


## kN per metre along the member from its own weight and its loads, factored.
func _line_load(id: String, dead: float, live: float, snow: float) -> float:
	var m: Dictionary = g.members[id]
	var sec := g.section(m.section)
	var own: float = float(sec.weight) * (float(m.width) if sec.get("per_width", false) else 1.0)
	var loads: Dictionary = m.loads
	return (own + float(loads.get("dead", 0.0))) * dead + float(loads.get("live", 0.0)) * live \
			+ float(loads.get("snow", 0.0)) * snow


## Weight (kN) at each node that shaking throws sideways: each member's load split between
## its ends, plus the node's own loads.
func _seismic_weight(sc: StructureScenario) -> Dictionary:
	var out := {}
	for n: String in node_ids:
		var loads: Dictionary = g.nodes[n].loads
		out[n] = float(loads.get("dead", 0.0)) + float(loads.get("live", 0.0)) * sc.quake_live
	for id: String in member_ids:
		if not _member_supported(id):
			continue
		var m: Dictionary = g.members[id]
		var half: float = _line_load(id, 1.0, sc.quake_live, 0.0) * geo[id].L * 0.5
		out[m.a] += half
		out[m.b] += half
	return out


## Sideways forces for one push direction: {"members": id -> {axial, moment, shear},
## "base": kN reaching the ground}.
func _lateral(sc: StructureScenario, d: Vector3, mass: Dictionary) -> Dictionary:
	var shear := {}
	for gid: String in group_order:
		shear[gid] = 0.0
	for n: String in order:
		var h := 0.0
		if sc.wind_kpa > 0.0:
			h += float(g.nodes[n].wind_area) * sc.wind_kpa
		if sc.quake_g > 0.0:
			h += float(mass[n]) * sc.quake_g
		shear[group_of[n]] += h
	var rows := {}
	var base := 0.0
	for gid: String in group_order:
		var v: float = shear[gid]
		if absf(v) < EPS:
			continue
		var grp: Dictionary = groups[gid]
		var ks := {}
		var ktot := 0.0
		for id: String in grp.members:
			var k := _stiffness(id, d)
			if k > 0.0:
				ks[id] = k
				ktot += k
		var k_ground: float = K_GROUND * grp.anchors.size()
		ktot += k_ground
		if ktot <= 0.0:
			continue
		base += v * k_ground / ktot
		for id: String in ks:
			var share: float = v * ks[id] / ktot
			var m: Dictionary = g.members[id]
			var lower: String = m.a if (g.nodes[m.a].pos as Vector3).y < (g.nodes[m.b].pos as Vector3).y else m.b
			shear[group_of[lower]] += share
			var gm: Dictionary = geo[id]
			var row := {"axial": 0.0, "moment": 0.0, "shear": 0.0}
			match m.kind:
				StructureGraph.BRACE:
					row.axial = share / maxf(gm.c * absf((gm.hdir as Vector3).dot(d)), 0.05)
				StructureGraph.WALL:
					row.shear = share
				_:
					var h: float = gm.L * gm.s
					row.shear = share
					row.moment = share * h * 0.5
			rows[id] = row
	return {"members": rows, "base": base}


func _stiffness(id: String, d: Vector3) -> float:
	var m: Dictionary = g.members[id]
	var gm: Dictionary = geo[id]
	match m.kind:
		StructureGraph.BRACE:
			return K_BRACE * gm.c * absf((gm.hdir as Vector3).dot(d))
		StructureGraph.WALL:
			var plane: Vector3 = m.plane if (m.plane as Vector3).length() > 0.0 else Vector3(1, 0, 0)
			return K_WALL * float(m.width) * absf(plane.dot(d))
	if gm.orient == Orient.POST:
		return K_COLUMN
	return K_COLUMN * 0.5


## One member's utilisation from its gravity forces plus (optionally) sideways forces.
func _utilise(id: String, grav: Dictionary, lat: Dictionary, direction: int) -> Dictionary:
	var m: Dictionary = g.members[id]
	var gm: Dictionary = geo[id]
	var row := {"u": 0.0, "mode": "axial", "axial": 0.0, "moment": 0.0, "shear": 0.0,
			"lateral": false, "direction": -1, "cantilever": bool(grav.cantilever),
			"kind": m.kind, "length": gm.L, "part": m.part}
	if not _member_supported(id):
		row.u = StructureResult.UNSUPPORTED
		row.mode = "unsupported"
		return row
	var sec := g.section(m.section)
	var scale: float = float(m.width) if sec.get("per_width", false) else 1.0
	var axial: float = absf(grav.axial) + absf(float(lat.get("axial", 0.0)))
	var moment: float = absf(grav.moment) + absf(float(lat.get("moment", 0.0)))
	var shear: float = absf(grav.shear) + absf(float(lat.get("shear", 0.0)))
	var full := _ratio(sec, scale, axial, moment, shear)
	row.u = full[0]
	row.mode = full[1]
	row.axial = axial
	row.moment = moment
	row.shear = shear
	if not lat.is_empty():
		var still: Array = _ratio(sec, scale, absf(grav.axial), absf(grav.moment), absf(grav.shear))
		# Sideways load governs when it adds more than gravity alone uses.
		row.lateral = full[0] - float(still[0]) > float(still[0])
		row.direction = direction
	return row


## [utilisation, governing mode] for forces on a section.
static func _ratio(sec: Dictionary, scale: float, axial: float, moment: float, shear: float) -> Array:
	var ua := axial / (float(sec.axial) * scale)
	var um := moment / (float(sec.bending) * scale)
	var uv := shear / (float(sec.shear) * scale)
	if uv > ua + um:
		return [uv, "shear"]
	return [ua + um, "axial" if ua >= um else "bending"]


static func _sorted_keys(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k


## A plate as a one-metre strip: simply supported over its span, or a cantilever.
func _plate(id: String, sc: StructureScenario) -> Dictionary:
	var p: Dictionary = g.plates[id]
	var row := {"u": 0.0, "mode": "bending", "axial": 0.0, "moment": 0.0, "shear": 0.0,
			"lateral": false, "direction": -1, "cantilever": bool(p.cantilever),
			"kind": StructureGraph.SLAB, "length": float(p.span), "part": p.part}
	var held := false
	for m: String in p.supports:
		if g.members.has(m) and _member_supported(m):
			held = true
	if not held:
		row.u = StructureResult.UNSUPPORTED
		row.mode = "unsupported"
		return row
	var sec := g.section(p.section)
	var loads: Dictionary = p.loads
	var w: float = (float(sec.weight) + float(loads.get("dead", 0.0))) * sc.dead \
			+ float(loads.get("live", 0.0)) * sc.live + float(loads.get("snow", 0.0)) * sc.snow
	var span: float = p.span
	if p.cantilever:
		row.moment = w * span * span * 0.5
		row.shear = w * span
	else:
		row.moment = w * span * span * 0.125
		row.shear = w * span * 0.5
	var r := _ratio(sec, 1.0, 0.0, row.moment, row.shear)
	row.u = r[0]
	row.mode = r[1]
	return row
