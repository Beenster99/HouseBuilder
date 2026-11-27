extends RefCounted
## The modules every player starts with: common rooms drawn here with the design room's own
## parts (walls round the room, a door, a window, the usual fittings), captured as kits the
## same way a player's are. Fittings stand with their backs to +z (rot 0) against a wall.

const C := preload("res://modules/building/api/building_commands.gd")

static var _cache: Array = []


static func all(catalog: BuildingCatalog) -> Array:
	if _cache.is_empty():
		for spec: Dictionary in _specs():
			var k := _make(catalog, spec)
			if not k.is_empty():
				_cache.append(k)
	var out: Array = []
	for k: Dictionary in _cache:
		out.append(k.duplicate(true))
	return out


static func _specs() -> Array:
	return [
		{"name": "Double bedroom", "group": "Homes", "type": "bedroom", "w": 4.0, "d": 3.5,
			"door": [0, 0.7], "window": [1, 1.75],
			"fit": [["bed_double", 2.0, 2.5, 0.0]]},
		{"name": "Single bedroom", "group": "Homes", "type": "bedroom", "w": 3.0, "d": 2.75,
			"door": [0, 0.6], "window": [1, 1.4],
			"fit": [["bed_single", 0.55, 1.75, 0.0]]},
		{"name": "Family bathroom", "group": "Homes", "type": "bathroom", "w": 2.5, "d": 2.5,
			"door": [0, 1.75], "window": [1, 1.25], "window_kind": "window_small",
			"fit": [["bath", 0.4, 1.6, 0.0], ["wc", 1.35, 2.15, 0.0], ["basin", 2.05, 2.27, 0.0]]},
		{"name": "En-suite shower room", "group": "Homes", "type": "bathroom", "w": 2.0, "d": 1.8,
			"door": [0, 1.45],
			"fit": [["shower", 0.5, 1.35, 0.0], ["wc", 1.25, 1.45, 0.0], ["basin", 1.65, 0.35, 180.0]]},
		{"name": "Galley kitchen", "group": "Homes", "type": "kitchen", "w": 3.0, "d": 2.4,
			"door": [0, 0.6], "window": [1, 1.2],
			"fit": [["kitchen_unit", 0.3, 2.1, 0.0], ["kitchen_unit", 0.9, 2.1, 0.0], ["kitchen_unit", 1.5, 2.1, 0.0],
				["kitchen_unit", 2.1, 2.1, 0.0], ["kitchen_unit", 2.7, 2.1, 0.0]]},
		{"name": "Living room", "group": "Homes", "type": "living_room", "w": 5.0, "d": 4.0,
			"door": [0, 0.7], "window": [2, 2.5], "window_kind": "window_large",
			"fit": [["sofa", 2.5, 3.5, 0.0], ["dining_table", 2.5, 1.4, 0.0]]},
		{"name": "Two-desk office", "group": "Offices", "type": "office", "w": 3.5, "d": 3.0,
			"door": [0, 0.6], "window": [2, 1.75],
			"fit": [["desk_office", 1.0, 2.55, 0.0], ["desk_office", 2.5, 2.55, 0.0]]},
		{"name": "Reception", "group": "Offices", "type": "reception", "w": 5.0, "d": 4.0,
			"door": [0, 2.5], "door_kind": "door_double", "window": [1, 2.0],
			"fit": [["reception_desk", 2.5, 3.2, 0.0], ["sofa", 1.2, 0.9, 180.0]]},
		{"name": "Classroom (24)", "group": "Schools", "type": "classroom", "w": 8.0, "d": 7.0,
			"door": [0, 0.75], "window": [1, 3.5], "window_kind": "window_large",
			"fit": _rows("desk_pupil", 4, 3, 1.6, 1.4, 1.6, 1.4, 180.0) + [["desk_teacher", 4.0, 6.2, 180.0]]},
		{"name": "Hospital single room", "group": "Hospitals", "type": "single_room", "w": 4.0, "d": 4.0,
			"door": [0, 1.0], "door_kind": "door_accessible", "window": [2, 2.0],
			"fit": [["hospital_bed", 2.0, 3.0, 0.0], ["basin", 3.5, 0.3, 180.0]]},
		{"name": "Custody cell", "group": "Police", "type": "custody_cell", "w": 2.5, "d": 3.0,
			"door": [0, 1.25], "door_kind": "door_secure",
			"fit": [["cell_bench", 1.25, 2.6, 0.0], ["wc", 0.4, 2.6, 0.0]]},
	]


static func _rows(kind: String, cols: int, rows: int, x0: float, dx: float, z0: float, dz: float, rot: float) -> Array:
	var out: Array = []
	for r in rows:
		for c in cols:
			out.append([kind, x0 + c * dx, z0 + r * dz, rot])
	return out


static func _make(catalog: BuildingCatalog, spec: Dictionary) -> Dictionary:
	var m := BuildingModel.new("", str(spec.name), catalog)
	var w := float(spec.w)
	var d := float(spec.d)
	var room := m.apply(C.place_room(str(spec.type), 0, C.rect(0, 0, w, d), ""))
	if room.is_empty():
		return {}
	# Walls 0..3: front (z = 0), right (x = w), back (z = d), left (x = 0).
	var corners := [Vector3(0, 0, 0), Vector3(w, 0, 0), Vector3(w, 0, d), Vector3(0, 0, d)]
	var walls: Array = []
	for i in 4:
		var r := m.apply(C.place_part("wall_loadbearing", 0, {"a": corners[i], "b": corners[(i + 1) % 4]}, "masonry"))
		walls.append(str(r.do.entry.id) if not r.is_empty() else "")
	if spec.has("door"):
		m.apply(C.place_opening(str(spec.get("door_kind", "door_internal")), walls[int(spec.door[0])], float(spec.door[1])))
	if spec.has("window"):
		m.apply(C.place_opening(str(spec.get("window_kind", "window_medium")), walls[int(spec.window[0])], float(spec.window[1])))
	for f: Array in spec.get("fit", []):
		if catalog.has_kind(str(f[0])):
			m.apply(C.place_part(str(f[0]), 0, {"at": Vector3(float(f[1]), 0, float(f[2])), "rot": float(f[3])}))
	var kit := KitCapture.capture(m, str(room.do.entry.id), str(spec.name), str(spec.group))
	kit["author"] = "Starter"
	return kit
