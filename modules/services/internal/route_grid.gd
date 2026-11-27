extends RefCounted
## The space services can run through: a grid of cells over every level of the building.
## A cell is inside when its centre is inside a room or a floor slab on its level. Walls
## sit between cells: crossing one costs a hole (none at a door), and curtain walls cannot
## be crossed. Built from the building model's api only; nothing here changes the model.

const Rates := preload("res://modules/services/api/services_rates.gd")

const OUT := 0
const IN := 1
const NO_GO := 2
## Grids grow coarser on big buildings so a route takes well under a second.
const MAX_CELLS := 12000
const BLOCKED := INF

var cell := 0.5
var nx := 0
var nz := 0
var nl := 0
var ox := 0.0
var oz := 0.0
var level_y := PackedFloat64Array()
var level_h := PackedFloat64Array()
## Per cell: OUT, IN or NO_GO.
var state := PackedByteArray()
## Per cell: 1 in a service zone (corridor, plant room...), else 0.
var zone := PackedByteArray()
## Per cell: 1 where a riser may go through the floor cheaply.
var riser := PackedByteArray()
## Per cell: index into room_ids, or -1.
var room_at := PackedInt32Array()
var room_ids := PackedStringArray()
## room index -> PackedInt32Array of its inside cells (ascending)
var room_cells: Array = []
## edge key (cell * 2 + 0 for +x, + 1 for +z) -> {cost, holes: [{kind, wall}]}
var walls := {}
## The same as costs per cell, for the search's inner loop: crossing to the +x / +z
## neighbour (0 when no wall, INF when sealed).
var wall_x := PackedFloat64Array()
var wall_z := PackedFloat64Array()


func size() -> int:
	return nx * nz * nl


func index(level: int, ix: int, iz: int) -> int:
	return (level * nz + iz) * nx + ix


func level_of(i: int) -> int:
	return i / (nx * nz)


func ix_of(i: int) -> int:
	return i % nx


func iz_of(i: int) -> int:
	return (i / nx) % nz


## A cell's centre in world space, on its level's floor.
func centre(i: int) -> Vector3:
	return Vector3(ox + (ix_of(i) + 0.5) * cell, level_y[level_of(i)], oz + (iz_of(i) + 0.5) * cell)


func room_of(i: int) -> String:
	var r := room_at[i]
	return room_ids[r] if r >= 0 else ""


## The inside cell on `level` nearest (x, z), optionally only cells of `room_id`; -1 if none.
func nearest(level: int, x: float, z: float, room_id: String = "") -> int:
	if level < 0 or level >= nl:
		return -1
	var best := -1
	var best_d := INF
	var cells: PackedInt32Array
	if room_id != "":
		var r := room_ids.find(room_id)
		if r < 0:
			return -1
		cells = room_cells[r]
	else:
		var base := level * nx * nz
		cells = PackedInt32Array()
		for k in nx * nz:
			if state[base + k] == IN:
				cells.append(base + k)
	for i in cells:
		if level_of(i) != level:
			continue
		var c := centre(i)
		var d := (c.x - x) * (c.x - x) + (c.z - z) * (c.z - z)
		if d < best_d - 0.000001:
			best_d = d
			best = i
	return best


## Every cell of a room.
func cells_of_room(room_id: String) -> PackedInt32Array:
	var r := room_ids.find(room_id)
	return room_cells[r] if r >= 0 else PackedInt32Array()


## Neighbours of a cell: [j, kind] where kind is "h" (same level) or "up" / "down".
func neighbours(i: int) -> Array:
	var out := []
	var l := level_of(i)
	var x := ix_of(i)
	var z := iz_of(i)
	if x > 0:
		out.append([i - 1, "h"])
	if x < nx - 1:
		out.append([i + 1, "h"])
	if z > 0:
		out.append([i - nx, "h"])
	if z < nz - 1:
		out.append([i + nx, "h"])
	if l > 0:
		out.append([i - nx * nz, "down"])
	if l < nl - 1:
		out.append([i + nx * nz, "up"])
	return out


## The wall crossing between two horizontally adjacent cells, or {} when there is none.
func wall_between(i: int, j: int) -> Dictionary:
	var a := mini(i, j)
	var b := maxi(i, j)
	var key := a * 2 + (0 if b == a + 1 else 1)
	return walls.get(key, {})


static func build(model: BuildingModel, base_cell: float = 0.5) -> RefCounted:
	var g = load("res://modules/services/internal/route_grid.gd").new()
	g._build(model, base_cell)
	return g


func _build(model: BuildingModel, base_cell: float) -> void:
	var cat := model.catalog
	nl = model.level_count()
	for l in nl:
		level_y.append(model.level_elevation(l))
		level_h.append(model.level_height(l))
	# Plan outlines per level: rooms and slabs.
	var outlines: Array = []  # per level: Array of outlines
	for l in nl:
		outlines.append([])
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for rid in BuildingModel.sort_ids(model.rooms.keys()):
		var r: Dictionary = model.rooms[rid]
		outlines[int(r.level)].append(r.outline)
		for p: Array in r.outline:
			lo = Vector2(minf(lo.x, p[0]), minf(lo.y, p[1]))
			hi = Vector2(maxf(hi.x, p[0]), maxf(hi.y, p[1]))
	for pid in BuildingModel.sort_ids(model.parts.keys()):
		var e: Dictionary = model.parts[pid]
		if cat.family_of(str(e.kind)) == "slab" and e.has("outline"):
			outlines[int(e.level)].append(e.outline)
			for p: Array in e.outline:
				lo = Vector2(minf(lo.x, p[0]), minf(lo.y, p[1]))
				hi = Vector2(maxf(hi.x, p[0]), maxf(hi.y, p[1]))
	if lo.x == INF:
		nx = 0
		nz = 0
		return
	var span := hi - lo
	cell = base_cell
	while (span.x / cell + 2.0) * (span.y / cell + 2.0) * nl > MAX_CELLS:
		cell += 0.25
	ox = floorf(lo.x / cell) * cell - cell
	oz = floorf(lo.y / cell) * cell - cell
	nx = int(ceilf((hi.x - ox) / cell)) + 1
	nz = int(ceilf((hi.y - oz) / cell)) + 1
	var n := size()
	state.resize(n)
	zone.resize(n)
	riser.resize(n)
	room_at.resize(n)
	room_at.fill(-1)
	room_ids = BuildingModel.sort_ids(model.rooms.keys())
	for l in nl:
		for ol: Array in outlines[l]:
			for i in _cells_in(l, ol):
				state[i] = IN
	# Rooms in reverse id order, so where two overlap the lower id wins.
	for r in range(room_ids.size() - 1, -1, -1):
		var room: Dictionary = model.rooms[room_ids[r]]
		var t := str(room.type)
		var is_zone := str(cat.room_type(t).get("category", "")) == "services"
		for i in _cells_in(int(room.level), room.outline):
			room_at[i] = r
			state[i] = NO_GO if t in Rates.NO_GO_ROOMS else IN
			zone[i] = 1 if is_zone and not t in Rates.NO_GO_ROOMS else 0
			riser[i] = 1 if t in Rates.RISER_ROOMS else 0
	# Packed arrays are values: gather in Arrays, then pack each once.
	var gather: Array = []
	for r in room_ids.size():
		gather.append([])
	for i in n:
		if room_at[i] >= 0 and state[i] == IN:
			gather[room_at[i]].append(i)
	room_cells.resize(room_ids.size())
	for r in room_ids.size():
		room_cells[r] = PackedInt32Array(gather[r])
	# Doors by the wall they sit in, gathered once (openings_in() scans every part).
	var doors_of := {}
	for pid in BuildingModel.sort_ids(model.parts.keys()):
		var o: Dictionary = model.parts[pid]
		if o.has("host") and str(o.kind).begins_with("door"):
			if not doors_of.has(str(o.host)):
				doors_of[str(o.host)] = []
			doors_of[str(o.host)].append(pid)
	for pid in BuildingModel.sort_ids(model.parts.keys()):
		var e: Dictionary = model.parts[pid]
		if cat.family_of(str(e.kind)) == "wall" and e.has("a"):
			_add_wall(model, pid, doors_of.get(pid, []))
	wall_x.resize(n)
	wall_z.resize(n)
	for key: int in walls:
		if key % 2 == 0:
			wall_x[key / 2] = float(walls[key].cost)
		else:
			wall_z[key / 2] = float(walls[key].cost)


## The cells on `level` whose centres are inside an outline.
func _cells_in(level: int, outline: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Array in outline:
		lo = Vector2(minf(lo.x, p[0]), minf(lo.y, p[1]))
		hi = Vector2(maxf(hi.x, p[0]), maxf(hi.y, p[1]))
	var x0 := clampi(int(floorf((lo.x - ox) / cell)), 0, nx - 1)
	var x1 := clampi(int(ceilf((hi.x - ox) / cell)), 0, nx - 1)
	var z0 := clampi(int(floorf((lo.y - oz) / cell)), 0, nz - 1)
	var z1 := clampi(int(ceilf((hi.y - oz) / cell)), 0, nz - 1)
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			if BuildingModel.outline_has_point(outline, ox + (ix + 0.5) * cell, oz + (iz + 0.5) * cell):
				out.append(index(level, ix, iz))
	return out


func _add_wall(model: BuildingModel, wall_id: String, door_ids: Array) -> void:
	var e: Dictionary = model.parts[wall_id]
	var spec := model.catalog.kind(str(e.kind))
	var l := int(e.level)
	var a := Vector2(float(e.a[0]), float(e.a[2]))
	var b := Vector2(float(e.b[0]), float(e.b[2]))
	var wlen := a.distance_to(b)
	if wlen < 0.001:
		return
	var sealed := str(e.kind) in Rates.SEALED_WALLS
	var kind := "structural_wall" if bool(spec.get("structural", false)) else "wall"
	var doors: Array = []  # [t0, t1]
	for oid: String in door_ids:
		var o: Dictionary = model.parts[oid]
		var w := float(o.get("w", model.catalog.kind(str(o.kind)).get("w", 0.9)))
		doors.append([float(o.t) - w * 0.5, float(o.t) + w * 0.5])
	var x0 := clampi(int(floorf((minf(a.x, b.x) - ox) / cell)) - 1, 0, nx - 1)
	var x1 := clampi(int(ceilf((maxf(a.x, b.x) - ox) / cell)) + 1, 0, nx - 1)
	var z0 := clampi(int(floorf((minf(a.y, b.y) - oz) / cell)) - 1, 0, nz - 1)
	var z1 := clampi(int(ceilf((maxf(a.y, b.y) - oz) / cell)) + 1, 0, nz - 1)
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var i := index(l, ix, iz)
			var c := Vector2(ox + (ix + 0.5) * cell, oz + (iz + 0.5) * cell)
			for dir in 2:
				if (dir == 0 and ix >= nx - 1) or (dir == 1 and iz >= nz - 1):
					continue
				var d := c + (Vector2(cell, 0) if dir == 0 else Vector2(0, cell))
				var t := _cross(c, d, a, b)
				if t < 0.0:
					continue
				var along := t * wlen
				var through_door := false
				for dr: Array in doors:
					if along >= dr[0] and along <= dr[1]:
						through_door = true
						break
				var key := i * 2 + dir
				var info: Dictionary = walls.get(key, {"cost": 0.0, "holes": []})
				if through_door:
					info.holes.append({"kind": "door", "wall": wall_id})
				elif sealed:
					info.cost = BLOCKED
					info.holes.append({"kind": "sealed", "wall": wall_id})
				else:
					info.cost = float(info.cost) + float(Rates.PENETRATION[kind])
					info.holes.append({"kind": kind, "wall": wall_id})
				walls[key] = info


## Where segment p-q crosses wall a-b, as a fraction along a-b; -1 if it does not. The
## crossing counts at q's end but not p's, so a wall through a cell centre is crossed once.
static func _cross(p: Vector2, q: Vector2, a: Vector2, b: Vector2) -> float:
	var r := q - p
	var s := b - a
	var den := r.cross(s)
	if absf(den) < 0.0000001:
		return -1.0
	var ap := a - p
	var u := ap.cross(s) / den  # along p-q
	var t := ap.cross(r) / den  # along a-b
	if u <= 0.0 or u > 1.0 or t < 0.0 or t > 1.0:
		return -1.0
	return t
