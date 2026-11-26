extends RefCounted
## Routes one system (power, cold water, hot water or waste) over a RouteGrid: a cheapest
## shared network from the source to every demand point.
##
## The network grows from the source. A cheapest-path search from every cell on the network
## reaches the nearest demand still waiting, adds that path to the network and carries on
## from there (the shortest-path heuristic for Steiner trees, so branches share runs). The cost of
## a step is money: run length times the system's rate per metre (less in service zones),
## plus any hole through a wall or floor. Waste is searched from the soil stack outwards and
## may never step down a level, so every fixture drains downhill to the stack.
##
## Ties break on cell index and demands are taken in id order, so the same building always
## gives the same routes.

const Rates := preload("res://modules/services/api/services_rates.gd")
const MinHeap := preload("res://modules/services/internal/min_heap.gd")

var grid: RefCounted
var system := ""
var spec: Dictionary
## cell -> metres along the network to the source, counting only runs across a floor
## (a riser or stack is not a branch)
var on_tree := {}
## "a-b" (a < b) -> {a, b, length, cost, holes}
var edges := {}
## Each served demand: {id, cell, length, cost, to_source (level runs only), points}
var branches: Array = []
## Each demand with no route: {id, cell}
var unserved: Array = []


func _init(route_grid: RefCounted, system_id: String) -> void:
	grid = route_grid
	system = system_id
	spec = Rates.SYSTEM[system_id]


## demands: Array of {id, cell, wc?}. Demands are served in rounds, in the given groups
## (waste routes every WC first so the shared runs are sized for them).
func solve(source_cell: int, groups: Array) -> void:
	on_tree[source_cell] = 0.0
	for group: Array in groups:
		var waiting := {}
		for d: Dictionary in group:
			if int(d.cell) < 0:
				unserved.append({"id": d.id, "cell": -1})
				continue
			if not waiting.has(int(d.cell)):
				waiting[int(d.cell)] = []
			waiting[int(d.cell)].append(d)
		_search(waiting, bool(group[0].get("wc", false)))
		for c: int in waiting:
			for d: Dictionary in waiting[c]:
				unserved.append({"id": d.id, "cell": c})


## One cheapest-path search per group that keeps going as the network grows: each time it
## reaches a waiting cell it adds that path to the network, seeds the new cells at cost 0
## and carries on (costs only ever fall, so earlier work stays valid).
func _search(waiting: Dictionary, wc: bool) -> void:
	var per_m := float(spec.get("per_m_wc", spec.per_m)) if wc else float(spec.per_m)
	var n: int = grid.size()
	var dist := PackedFloat64Array()
	dist.resize(n)
	dist.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var heap := MinHeap.new()
	for c: int in on_tree:
		dist[c] = 0.0
		heap.push(0.0, c)
	var nx: int = grid.nx
	var nz: int = grid.nz
	var nxz: int = nx * nz
	var nl: int = grid.nl
	var state: PackedByteArray = grid.state
	var waste := system == "waste"
	while not waiting.is_empty() and not heap.is_empty():
		var d := heap.top_cost()
		var i := heap.pop()
		if d > dist[i]:
			continue
		if waiting.has(i):
			var path := PackedInt32Array([i])
			var length := 0.0
			var c := i
			while prev[c] >= 0 and not on_tree.has(c):
				var p := prev[c]
				length += _length(p, c)
				path.append(p)
				c = p
			path.reverse()
			for k in range(path.size() - 1):
				_add_edge(path[k], path[k + 1], per_m)
			_serve(waiting, i, path, length, d)
			for k in path.size():
				dist[path[k]] = 0.0
				prev[path[k]] = -1
				heap.push(0.0, path[k])
			continue
		var x := i % nx
		var z := (i / nx) % nz
		var l := i / nxz
		for dir in 6:
			var j := -1
			match dir:
				0: j = i - 1 if x > 0 else -1
				1: j = i + 1 if x < nx - 1 else -1
				2: j = i - nx if z > 0 else -1
				3: j = i + nx if z < nz - 1 else -1
				4: j = i - nxz if l > 0 and not waste else -1
				5: j = i + nxz if l < nl - 1 else -1
			if j < 0 or state[j] != 1:
				continue
			var step := _step(i, j, "h" if dir < 4 else "v", per_m)
			if step == INF:
				continue
			var nd := d + step
			if nd < dist[j] - 0.0000001:
				dist[j] = nd
				prev[j] = i
				heap.push(nd, j)


func _serve(waiting: Dictionary, cell: int, path: PackedInt32Array, length: float, cost: float) -> void:
	var start: int = path[0]
	var run := float(on_tree[start])
	for k in range(1, path.size()):
		if grid.level_of(path[k - 1]) == grid.level_of(path[k]):
			run += _length(path[k - 1], path[k])
		if not on_tree.has(path[k]):
			on_tree[path[k]] = run
	var pts: Array = []
	for k in path.size():
		var c: int = path[k]
		# Keep only the corners of the path.
		if k > 0 and k < path.size() - 1:
			var a: Vector3 = grid.centre(path[k - 1])
			var b: Vector3 = grid.centre(c)
			var n: Vector3 = grid.centre(path[k + 1])
			if ((b - a).normalized() - (n - b).normalized()).length() < 0.001:
				continue
		var p: Vector3 = grid.centre(c)
		pts.append([snappedf(p.x, 0.001), snappedf(p.y + float(spec.height), 0.001), snappedf(p.z, 0.001)])
	for d: Dictionary in waiting[cell]:
		branches.append({"id": d.id, "cell": cell, "length": snappedf(length, 0.001),
			"cost": snappedf(cost, 0.01), "to_source": snappedf(float(on_tree[cell]), 0.001), "points": pts})
	waiting.erase(cell)


func _length(i: int, j: int) -> float:
	if grid.level_of(i) == grid.level_of(j):
		return grid.cell
	return grid.level_h[mini(grid.level_of(i), grid.level_of(j))]


func _step(i: int, j: int, kind: String, per_m: float) -> float:
	if kind == "h":
		var w: Dictionary = grid.wall_between(i, j)
		var wall_cost := float(w.get("cost", 0.0))
		if wall_cost == INF:
			return INF
		var f := Rates.SERVICE_ZONE_FACTOR if grid.zone[i] == 1 or grid.zone[j] == 1 else 1.0
		return grid.cell * per_m * f + wall_cost
	var hole: float = Rates.PENETRATION.riser_floor if grid.riser[i] == 1 and grid.riser[j] == 1 else Rates.PENETRATION.floor
	return _length(i, j) * per_m + hole


func _key(i: int, j: int) -> String:
	return "%d-%d" % [mini(i, j), maxi(i, j)]


func _add_edge(i: int, j: int, per_m: float) -> void:
	var key := _key(i, j)
	if edges.has(key):
		return
	var length := _length(i, j)
	var holes: Array = []
	var hole_cost := 0.0
	var run := length * per_m
	if grid.level_of(i) == grid.level_of(j):
		for h: Dictionary in grid.wall_between(i, j).get("holes", []):
			if h.kind != "door":
				holes.append(h.kind)
				hole_cost += float(Rates.PENETRATION[h.kind])
		if grid.zone[i] == 1 or grid.zone[j] == 1:
			run *= Rates.SERVICE_ZONE_FACTOR
	else:
		var riser: bool = grid.riser[i] == 1 and grid.riser[j] == 1
		holes.append("riser_floor" if riser else "floor")
		hole_cost += float(Rates.PENETRATION[holes[0]])
	edges[key] = {"a": mini(i, j), "b": maxi(i, j), "length": length, "run_cost": run, "hole_cost": hole_cost, "holes": holes}
