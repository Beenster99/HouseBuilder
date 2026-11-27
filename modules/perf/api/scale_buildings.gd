class_name ScaleBuildings
extends RefCounted
## Generated buildings at the sizes the game must stay fast at, for the performance tests
## and the benchmark (and any module's own scale tests). Each is a steel frame on a bay
## grid: pad footings, columns and beams, a slab per level, a curtain-wall or masonry
## facade with windows, partitions between bays, a room per bay and a few fixtures per room.
##
##   var m := ScaleBuildings.make("office")       # or "house", "terminal"
##   ScaleBuildings.SIZES.terminal                 # the bay grid it was built from
##
## The same name always gives the same building, so numbers compare between runs.

const C := preload("res://modules/building/api/building_commands.gd")

## bays x, bays z, storeys, bay size m, fixtures per room.
const SIZES := {
	"house": {"bx": 2, "bz": 2, "storeys": 2, "bay": 4.0, "fixtures": 2},
	"office": {"bx": 8, "bz": 4, "storeys": 4, "bay": 6.0, "fixtures": 4},
	"terminal": {"bx": 16, "bz": 8, "storeys": 3, "bay": 8.0, "fixtures": 6},
}
const LEVEL_H := 3.0


static func names() -> PackedStringArray:
	return PackedStringArray(SIZES.keys())


static func make(size_name: String) -> BuildingModel:
	var s: Dictionary = SIZES[size_name]
	var m := BuildingModel.new("", "Scale %s" % size_name)
	build(m, int(s.bx), int(s.bz), int(s.storeys), float(s.bay), int(s.fixtures))
	return m


## As make(), as the plain data BuildingModel.load_data() takes (for the shared model).
static func data(size_name: String) -> Dictionary:
	return make(size_name).to_data()


static func build(m: BuildingModel, bx: int, bz: int, storeys: int, bay: float, fixtures: int) -> void:
	var w := bx * bay
	var d := bz * bay
	for i in storeys - 1:
		m.apply(C.add_level(LEVEL_H, "Level %d" % (i + 1)))
	for xi in bx + 1:
		for zi in bz + 1:
			m.apply(C.place_part("pad_footing", 0, {"at": [xi * bay, 0.0, zi * bay]}, "concrete"))
	for lv in storeys:
		for xi in bx + 1:
			for zi in bz + 1:
				m.apply(C.place_part("column", lv, {"at": [xi * bay, 0.0, zi * bay]}, "steel"))
		for xi in bx + 1:
			for zi in bz + 1:
				if xi < bx:
					m.apply(C.place_part("beam", lv, {"a": [xi * bay, LEVEL_H, zi * bay], "b": [(xi + 1) * bay, LEVEL_H, zi * bay]}, "steel"))
				if zi < bz:
					m.apply(C.place_part("beam", lv, {"a": [xi * bay, LEVEL_H, zi * bay], "b": [xi * bay, LEVEL_H, (zi + 1) * bay]}, "steel"))
		m.apply(C.place_part("slab", lv, {"outline": C.rect(0, 0, w, d)}, "concrete"))
		# Facade: a wall per bay edge round the outside, a window in each.
		var edges: Array = []
		for xi in bx:
			edges.append([[xi * bay, 0.0, 0.0], [(xi + 1) * bay, 0.0, 0.0]])
			edges.append([[(xi + 1) * bay, 0.0, d], [xi * bay, 0.0, d]])
		for zi in bz:
			edges.append([[w, 0.0, zi * bay], [w, 0.0, (zi + 1) * bay]])
			edges.append([[0.0, 0.0, (zi + 1) * bay], [0.0, 0.0, zi * bay]])
		for e: Array in edges:
			var r := m.apply(C.place_part("wall_loadbearing", lv, {"a": e[0], "b": e[1]}, "masonry"))
			if r.get("ok", false):
				m.apply(C.place_opening("window_medium", str(r.do.entry.id), bay * 0.5))
		# Partitions between bays along x, each with a door.
		for xi in range(1, bx):
			for zi in bz:
				var r := m.apply(C.place_part("wall_partition", lv, {"a": [xi * bay, 0.0, zi * bay], "b": [xi * bay, 0.0, (zi + 1) * bay]}))
				if r.get("ok", false):
					m.apply(C.place_opening("door_internal", str(r.do.entry.id), bay * 0.5))
		for xi in bx:
			for zi in bz:
				var type := "corridor" if zi == bz / 2 else "office"
				m.apply(C.place_room(type, lv, C.rect(xi * bay, zi * bay, bay, bay)))
				if type == "office":
					for k in fixtures:
						m.apply(C.place_part("desk_office", lv, {"at": [xi * bay + 1.0 + (k % 3) * 1.6, 0.0, zi * bay + 1.0 + (k / 3) * 1.8]}))
	m.apply(C.place_part("roof_flat", storeys - 1, {"outline": C.rect(0, 0, w, d), "y": LEVEL_H}, "concrete"))
