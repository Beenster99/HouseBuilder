extends RefCounted
## Sample buildings for the services tests.

const C := preload("res://modules/building/api/building_commands.gd")


static func add(m: BuildingModel, op: Dictionary) -> String:
	var r := m.apply(op)
	assert(not r.is_empty(), "sample op refused: %s" % str(op))
	return str(r.do.entry.id) if r.do.has("entry") else ""


static func wall(m: BuildingModel, level: int, a: Vector2, b: Vector2, structural: bool) -> String:
	var kind := "wall_loadbearing" if structural else "wall_partition"
	return add(m, C.place_part(kind, level, {"a": [a.x, 0, a.y], "b": [b.x, 0, b.y]}, "masonry" if structural else "timber"))


## A two-storey house, 10 by 8 m, front door on the -Z side.
##   ground: hallway (r) x 0-2, living room x 2-10 z 0-4, kitchen x 2-7 z 4-8, utility x 7-10 z 4-8
##   first:  landing x 0-2, bedroom x 2-10 z 0-4, bathroom x 2-6 z 4-8, bedroom x 6-10 z 4-8
## Every internal wall has a door. `fixtures` adds the kitchen sink, bathroom WC, basin and bath.
static func house(fixtures := true) -> BuildingModel:
	var m := BuildingModel.new("house", "Sample house")
	add(m, C.add_level(2.7, "First floor"))
	for lv in 2:
		add(m, C.place_part("slab", lv, {"outline": C.rect(0, 0, 10, 8)}, "concrete"))
		var corners := [Vector2(0, 0), Vector2(10, 0), Vector2(10, 8), Vector2(0, 8)]
		for k in 4:
			var w := wall(m, lv, corners[k], corners[(k + 1) % 4], true)
			if lv == 0 and k == 0:
				add(m, C.place_opening("door_external", w, 1.0))
		# Hall / landing to the rest.
		var hall := wall(m, lv, Vector2(2, 0), Vector2(2, 8), true)
		add(m, C.place_opening("door_internal", hall, 2.0))
		add(m, C.place_opening("door_internal", hall, 6.0))
		var mid := wall(m, lv, Vector2(2, 4), Vector2(10, 4), false)
		var split_x := 7.0 if lv == 0 else 6.0
		var split := wall(m, lv, Vector2(split_x, 4), Vector2(split_x, 8), false)
		if lv == 0:
			add(m, C.place_opening("door_internal", split, 2.0))
		else:
			add(m, C.place_opening("door_internal", mid, 1.0))  # main bedroom to bathroom
	add(m, C.place_room("hallway", 0, C.rect(0, 0, 2, 8), "Hall"))
	add(m, C.place_room("living_room", 0, C.rect(2, 0, 8, 4), "Lounge"))
	add(m, C.place_room("kitchen", 0, C.rect(2, 4, 5, 4), "Kitchen"))
	add(m, C.place_room("utility", 0, C.rect(7, 4, 3, 4), "Utility"))
	add(m, C.place_room("hallway", 1, C.rect(0, 0, 2, 8), "Landing"))
	add(m, C.place_room("bedroom", 1, C.rect(2, 0, 8, 4), "Main bedroom"))
	add(m, C.place_room("bathroom", 1, C.rect(2, 4, 4, 4), "Bathroom"))
	add(m, C.place_room("bedroom", 1, C.rect(6, 4, 4, 4), "Bedroom 2"))
	if fixtures:
		add(m, C.place_part("kitchen_unit", 0, {"at": [3, 0, 7.6]}))
		add(m, C.place_part("kitchen_unit", 0, {"at": [3.6, 0, 7.6]}))
		add(m, C.place_part("wc", 1, {"at": [3, 0, 7.5]}))
		add(m, C.place_part("basin", 1, {"at": [4, 0, 7.7]}))
		add(m, C.place_part("bath", 1, {"at": [5.5, 0, 6]}))
	return m


## The id of the first room of a type.
static func room_of_type(m: BuildingModel, type: String) -> String:
	for rid in BuildingModel.sort_ids(m.rooms.keys()):
		if str(m.rooms[rid].type) == type:
			return rid
	return ""
