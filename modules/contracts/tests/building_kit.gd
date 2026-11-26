extends RefCounted
## Builds simple but complete test buildings for the contract tests: a rectangular shell
## (strip footings, cavity walls, slabs, a roof, an entrance) with rooms laid out on each
## level. Not a test itself (no test_ prefix).

const C := preload("res://modules/building/api/building_commands.gd")


## A w x d shell of `storeys` levels. rooms: [[level, type, x, z, rw, rd], ...].
## Options: roof ("pitched" | "flat"), door (kind of the main entrance), exits (extra
## external doors as [[wall side 0..3, t], ...] on level 0), windows (per side per level).
static func shell(m: BuildingModel, w: float, d: float, storeys: int, rooms: Array, options: Dictionary = {}) -> void:
	for i in storeys - 1:
		m.apply(C.add_level(3.0, "Level %d" % (i + 1)))
	var corners := [[0.0, 0.0, 0.0], [w, 0.0, 0.0], [w, 0.0, d], [0.0, 0.0, d]]
	var walls: Array = []  # [level][side] -> id
	for lv in storeys:
		var row: Array = []
		for side in 4:
			var a: Array = corners[side]
			var b: Array = corners[(side + 1) % 4]
			if lv == 0:
				m.apply(C.place_part("strip_footing", 0, {"a": a, "b": b}))
			var r := m.apply(C.place_part("wall_loadbearing", lv, {"a": a, "b": b}, "masonry"))
			row.append(str(r.do.entry.id))
		walls.append(row)
		m.apply(C.place_part("slab", lv, {"outline": C.rect(0, 0, w, d)}, "concrete" if lv == 0 else "timber"))
	var roof := str(options.get("roof", "pitched"))
	if roof == "pitched":
		m.apply(C.place_part("roof_pitched", storeys - 1, {"outline": C.rect(0, 0, w, d), "y": 3.0, "pitch": 35.0}))
	else:
		m.apply(C.place_part("roof_flat", storeys - 1, {"outline": C.rect(0, 0, w, d), "y": 3.0}, "concrete"))
	m.apply(C.place_opening(str(options.get("door", "door_external")), walls[0][0], w * 0.5))
	for e: Array in options.get("exits", []):
		var side := int(e[0])
		m.apply(C.place_opening("door_fire", walls[0][side], float(e[1])))
	var per_side := int(options.get("windows", 2))
	for lv in storeys:
		for side in 4:
			var length := w if side % 2 == 0 else d
			for k in per_side:
				var t := length * float(k + 1) / float(per_side + 1)
				if lv == 0 and side == 0 and absf(t - w * 0.5) < 1.6:
					continue
				m.apply(C.place_opening("window_medium", walls[lv][side], t))
	for r: Array in rooms:
		m.apply(C.place_room(str(r[1]), int(r[0]), C.rect(float(r[2]), float(r[3]), float(r[4]), float(r[5]))))


## A fixture of `kind` in every room of `type`, `n` per room, in a row from the room's corner.
static func furnish(m: BuildingModel, type: String, kind: String, n: int) -> void:
	for rid in BuildingModel.sort_ids(m.rooms.keys()):
		var room: Dictionary = m.rooms[rid]
		if str(room.type) != type:
			continue
		var o: Array = room.outline[0]
		var far: Array = room.outline[2]
		var cols := maxi(1, int((float(far[0]) - float(o[0])) / 1.0))
		for i in n:
			var x := float(o[0]) + 0.5 + float(i % cols) * 1.0
			var z := float(o[1]) + 0.5 + float(i / cols) * 1.0
			m.apply(C.place_part(kind, int(room.level), {"at": [x, 0.0, z]}))


## The plan's detached house: 3 bedrooms, 2 bathrooms, kitchen, garage, 2 storeys.
static func house() -> BuildingModel:
	var m := BuildingModel.new("", "Test house")
	shell(m, 10.0, 8.0, 2, [
		[0, "living_room", 0, 0, 5, 5], [0, "kitchen", 5, 0, 5, 4], [0, "hallway", 5, 4, 2, 4],
		[0, "garage", 0, 5, 5, 3.5], [0, "wc_room", 7, 4, 1.5, 1.5], [0, "utility", 7, 5.5, 3, 2.5],
		[1, "bedroom", 0, 0, 4, 4], [1, "bedroom", 4, 0, 3.5, 3.5], [1, "bedroom", 0, 4, 3.5, 3],
		[1, "bathroom", 7.5, 0, 2.5, 2.5], [1, "bathroom", 4, 4, 2.5, 2], [1, "hallway", 6.5, 3.5, 3.5, 2],
	], {"windows": 2})
	m.apply(C.place_part("bed_double", 1, {"at": [2.0, 0.0, 2.0]}))
	return m


## The plan's primary school: 8 classrooms of 30, a hall, an accessible entrance, fire exits.
static func school() -> BuildingModel:
	var m := BuildingModel.new("", "Test school")
	var rooms: Array = []
	for i in 4:
		rooms.append([0, "classroom", 8.0 * i, 0, 8, 7.5])
		rooms.append([0, "classroom", 8.0 * i, 12.5, 8, 7.5])
	rooms.append([0, "corridor", 0, 7.5, 32, 2.5])
	rooms.append([0, "school_hall", 32, 0, 12, 12])
	rooms.append([0, "toilet_block", 32, 12, 6, 4])
	rooms.append([0, "staff_room", 38, 12, 6, 4])
	rooms.append([0, "fire_exit", 0, 10, 3, 2.5])
	rooms.append([0, "store_room", 32, 16, 12, 4])
	shell(m, 44.0, 20.0, 1, rooms, {"roof": "flat", "door": "door_accessible", "windows": 6,
			"exits": [[2, 8.0], [2, 30.0], [1, 10.0], [3, 10.0]]})
	return m


## The plan's police station: custody cells with secure doors, front desk, vehicle bay.
static func police() -> BuildingModel:
	var m := BuildingModel.new("", "Test police station")
	var rooms: Array = [
		[0, "reception", 0, 0, 8, 6], [0, "custody_desk", 8, 0, 6, 6], [0, "corridor", 0, 6, 30, 2],
		[0, "custody_cell", 14, 0, 3, 3], [0, "custody_cell", 17, 0, 3, 3], [0, "custody_cell", 20, 0, 3, 3],
		[0, "custody_cell", 23, 0, 3, 3], [0, "interview_room", 26, 0, 4, 3], [0, "vehicle_bay", 0, 8, 12, 8],
		[0, "locker_room", 12, 8, 6, 4], [0, "office", 18, 8, 12, 8], [0, "fire_exit", 12, 12, 3, 4],
	]
	shell(m, 30.0, 16.0, 1, rooms, {"roof": "flat", "door": "door_accessible", "windows": 3,
			"exits": [[2, 6.0], [2, 24.0], [1, 8.0], [3, 4.0]]})
	var corridor_wall := m.apply(C.place_part("wall_partition", 0, {"a": [14, 0, 3], "b": [26, 0, 3]}, "masonry"))
	for t: float in [1.5, 4.5, 7.5, 10.5]:
		m.apply(C.place_opening("door_secure", str(corridor_wall.do.entry.id), t))
	m.apply(C.place_opening("door_vehicle", _wall_at(m, 3), 4.0))
	furnish(m, "custody_cell", "cell_bench", 1)
	return m


static func _wall_at(m: BuildingModel, side: int) -> String:
	var walls := m.parts_of_family("wall")
	return walls[side]
