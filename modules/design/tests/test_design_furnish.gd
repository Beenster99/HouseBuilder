extends ModuleTest
## Furnish: reading a description against the whole furniture library, and laying pieces out
## in square, angled and L-shaped rooms with doors and windows: beds backed onto walls with
## room at the side and foot, nothing overlapping, doors and windows kept clear, pieces
## spread out, more than fits reported, one undo.
##   tools/run_tests.sh design
## FURNISH_PNG=<folder> also draws each room's plan there.

const Fitout := preload("res://modules/design/internal/design_fitout.gd")
const Layout := preload("res://modules/design/internal/fitout/fitout_layout.gd")

var _png := ""


func run_tests() -> void:
	_png = OS.get_environment("FURNISH_PNG")
	_words()
	_bedroom_beds()
	_bedroom_full()
	_angled_room()
	_l_shaped_living()
	_classroom()
	_too_much()
	_session_undo()


func _words() -> void:
	var cat := BuildingCatalog.default_catalog()
	var r := Fitout.read("2 single beds, a desk and three chairs", cat)
	var kinds: Array = r.items.map(func(i: Dictionary) -> Array: return [i.kind, i.count])
	check(kinds == [["bed_single", 2], ["desk_office", 1], ["furniture.seat.dining_chair", 3]], "a description reads: %s" % str(kinds))
	r = Fitout.read("a double bed with two bedside tables, a double wardrobe, chest of drawers and a desk by the window", cat)
	kinds = r.items.map(func(i: Dictionary) -> String: return i.kind)
	check(kinds == ["bed_double", "furniture.storage.bedside_table", "furniture.wardrobe.double", "furniture.storage.chest_of_drawers", "desk_office"],
			"library pieces by name: %s" % str(kinds))
	check(r.items[4].rel == "near" and r.items[4].target == "window", "a desk by the window: %s" % str(r.items[4]))
	r = Fitout.read("a sofa facing the tv, a coffee table, 2 armchairs and a rug", cat)
	check(r.items[0].rel == "facing" and str(r.items[0].target).contains("tv"), "facing the TV: %s" % str(r.items[0]))
	check(r.items.size() == 4 and r.items[2].count == 2 and r.items[2].kind == "furniture.seat.armchair", "armchairs: %s" % str(r.items))
	r = Fitout.read("a folding table with 6 chairs", cat)
	check(r.items[1].rel == "around" and r.items[1].target == "furniture.table.folding" and r.items[1].count == 6, "chairs go round the table: %s" % str(r.items))
	r = Fitout.read("dining table with 6 chairs", cat)
	check(r.items.size() == 1 and r.items[0].kind == "dining_table", "a dining table comes with its chairs: %s" % str(r.items))
	r = Fitout.read("4 beds", cat, "ward_bay")
	check(r.items[0].kind == "hospital_bed", "a bed in a ward is a hospital bed: %s" % str(r.items))
	r = Fitout.read("a bunk bed, a kitchen sink, an office chair, a 55 inch telly and a flux capacitor", cat)
	kinds = r.items.map(func(i: Dictionary) -> String: return i.kind)
	check(kinds == ["furniture.home.bunk_bed", "furniture.kitchen.sink_1000", "furniture.seat.task_chair", "furniture.appliance.tv_55"],
			"bunk bed, kitchen sink, office chair, telly: %s" % str(kinds))
	check(r.unknown.size() == 1 and r.unknown[0].contains("flux"), "words it doesn't know are reported: %s" % str(r.unknown))
	r = Fitout.read("a wardrobe in the corner and a plant", cat)
	check(r.items[0].rel == "in" and r.items[0].target == "corner", "in the corner: %s" % str(r.items[0]))


## A large bedroom, door in one wall and a window in another: three single beds.
func _bedroom_beds() -> void:
	var m := BuildingModel.new()
	var rid := _room(m, "bedroom", BuildingCommands.rect(0, 0, 6, 5), [[0, 1.0, "door_internal"]], [[2, 3.0, "window_small"]])
	var r := Fitout.furnish(m, rid, Fitout.read("3 single beds", m.catalog).items)
	check(int(r.placed) == 3, "three beds placed: %d" % int(r.placed))
	var ids := _apply(m, r.ops)
	_no_overlaps(m, ids, "beds")
	_inside(m, rid, ids, "beds")
	_door_clear(m, rid, ids, "beds")
	for id: String in ids:
		check(_back_to_wall(m, rid, id), "bed %s has its headboard on a wall" % id)
	var gap := INF
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			gap = minf(gap, _gap(m, ids[i], ids[j]))
	check(gap >= 0.55, "the beds are spread with room to get between them: %.2f m" % gap)
	_draw(m, rid, "beds")


func _bedroom_full() -> void:
	var m := BuildingModel.new()
	var rid := _room(m, "bedroom", BuildingCommands.rect(0, 0, 4.2, 3.6), [[3, 0.9, "door_internal"]], [[1, 1.8, "window_small"]])
	var said := Fitout.read("a double bed, 2 bedside tables, a wardrobe, a chest of drawers and a desk by the window", m.catalog, "bedroom")
	var r := Fitout.furnish(m, rid, said.items)
	check(int(r.placed) == 6, "the whole bedroom fits: %d of %d, missing %s" % [int(r.placed), int(r.wanted), str(r.missing)])
	var ids := _apply(m, r.ops)
	_no_overlaps(m, ids, "bedroom")
	_inside(m, rid, ids, "bedroom")
	_door_clear(m, rid, ids, "bedroom")
	var bed := ""
	for id: String in ids:
		if m.parts[id].kind == "bed_double":
			bed = id
	for id: String in ids:
		if m.parts[id].kind == "furniture.storage.bedside_table":
			check(_gap(m, id, bed) < 0.15, "bedside table %s is by the bed: %.2f m" % [id, _gap(m, id, bed)])
	check(bed != "" and _back_to_wall(m, rid, bed), "the double bed is headboard to the wall")
	_draw(m, rid, "bedroom")
	# The usual layout for a bedroom, in the same room emptied.
	var m2 := BuildingModel.new()
	var rid2 := _room(m2, "bedroom", BuildingCommands.rect(0, 0, 4.2, 3.6), [[3, 0.9, "door_internal"]], [[1, 1.8, "window_small"]])
	var r2 := Fitout.furnish(m2, rid2, Fitout.preset(m2, rid2))
	check(int(r2.placed) == int(r2.wanted) and int(r2.wanted) >= 4, "the usual bedroom: %d of %d" % [int(r2.placed), int(r2.wanted)])
	_no_overlaps(m2, _apply(m2, r2.ops), "usual bedroom")


## A room with a 45 degree wall.
func _angled_room() -> void:
	var m := BuildingModel.new()
	var outline := [[0.0, 0.0], [5.0, 0.0], [5.0, 2.5], [2.5, 5.0], [0.0, 5.0]]
	var rid := _room(m, "bedroom", outline, [[0, 4.0, "door_internal"]], [[3, 1.7, "window_small"]])
	var r := Fitout.furnish(m, rid, Fitout.read("2 single beds, a wardrobe and a bookcase", m.catalog).items)
	check(int(r.placed) == 4, "all four in the angled room: %d, missing %s" % [int(r.placed), str(r.missing)])
	var ids := _apply(m, r.ops)
	_no_overlaps(m, ids, "angled")
	_inside(m, rid, ids, "angled")
	_door_clear(m, rid, ids, "angled")
	_draw(m, rid, "angled")


func _l_shaped_living() -> void:
	var m := BuildingModel.new()
	var outline := [[0.0, 0.0], [7.0, 0.0], [7.0, 3.0], [3.5, 3.0], [3.5, 6.0], [0.0, 6.0]]
	var rid := _room(m, "living_room", outline, [[5, 2.0, "door_internal"]], [[1, 1.5, "window_small"], [4, 1.7, "window_small"]])
	var said := Fitout.read("a sofa facing the tv, a tv unit, 2 armchairs, a coffee table, a folding table with 4 chairs and a plant in the corner", m.catalog, "living_room")
	var r := Fitout.furnish(m, rid, said.items)
	check(int(r.placed) >= int(r.wanted) - 1, "most of the living room fits: %d of %d, missing %s" % [int(r.placed), int(r.wanted), str(r.missing)])
	var ids := _apply(m, r.ops)
	_no_overlaps(m, ids, "L room")
	_inside(m, rid, ids, "L room")
	_door_clear(m, rid, ids, "L room")
	var sofa := ""
	var tv := ""
	for id: String in ids:
		if m.parts[id].kind == "sofa":
			sofa = id
		elif str(m.parts[id].kind).contains("tv_unit"):
			tv = id
	if sofa != "" and tv != "":
		var th := deg_to_rad(float(m.parts[sofa].rot))
		var to := (_centre(m, tv) - _centre(m, sofa)).normalized()
		check(Vector2(-sin(th), -cos(th)).dot(to) > 0.7, "the sofa faces the TV unit: %.2f" % Vector2(-sin(th), -cos(th)).dot(to))
	_draw(m, rid, "living")


func _classroom() -> void:
	var m := BuildingModel.new()
	var rid := _room(m, "classroom", BuildingCommands.rect(0, 0, 8, 7), [[0, 1.0, "door_internal"]], [[2, 4.0, "window_small"]])
	var t0 := Time.get_ticks_msec()
	var r := Fitout.furnish(m, rid, Fitout.preset(m, rid))
	var ms := Time.get_ticks_msec() - t0
	check(int(r.placed) >= 16, "a classroom of desks: %d of %d" % [int(r.placed), int(r.wanted)])
	check(ms < 4000, "laid out in good time: %d ms" % ms)
	var ids := _apply(m, r.ops)
	_no_overlaps(m, ids, "classroom")
	_inside(m, rid, ids, "classroom")
	_door_clear(m, rid, ids, "classroom")
	_draw(m, rid, "classroom")


func _too_much() -> void:
	var m := BuildingModel.new()
	var rid := _room(m, "bedroom", BuildingCommands.rect(0, 0, 3, 3), [[0, 1.0, "door_internal"]], [])
	var r := Fitout.furnish(m, rid, Fitout.read("6 double beds", m.catalog).items)
	check(int(r.placed) >= 1 and int(r.placed) < 6 and int(r.missing.get("bed_double", 0)) == 6 - int(r.placed),
			"only what fits, the rest reported: %d placed, missing %s" % [int(r.placed), str(r.missing)])
	_no_overlaps(m, _apply(m, r.ops), "too much")


func _session_undo() -> void:
	var net := Modules.bus("multiplayer") as MultiplayerBus
	var model := BuildingModel.new()
	var sync := BuildingSync.new(model)
	var s := DesignSession.new()
	add_child(s)
	s.setup(net, model, sync)
	s.set_tool("room")
	s.room_type = "bedroom"
	s.press(Vector3(0, 0, 0))
	s.release(Vector3(5, 0, 4))
	var rid: String = model.rooms.keys()[0]
	s.set_tool("select")
	s.press(Vector3(1, 0, 1))
	s.release(Vector3(1, 0, 1))
	var before := model.parts_of_family("fixture").size()
	s.furnish_selection("2 single beds and a wardrobe")
	check(model.parts_of_family("fixture").size() == before + 3, "the session furnishes the selected room")
	check(BuildingQuantities.fixtures_in(model, rid).size() == 3, "inside it")
	sync.undo()
	check(model.parts_of_family("fixture").size() == before, "one undo takes it all out")
	s.queue_free()


# --- Helpers -------------------------------------------------------------------------------

## A room with walls round it; doors and windows as [edge index, t, kind].
func _room(m: BuildingModel, type: String, outline: Array, doors: Array, windows: Array) -> String:
	var ops: Array = [BuildingCommands.place_room(type, 0, outline)]
	for i in outline.size():
		var p: Array = outline[i]
		var q: Array = outline[(i + 1) % outline.size()]
		ops.append(BuildingCommands.place_part("wall_loadbearing", 0, {"a": Vector3(p[0], 0, p[1]), "b": Vector3(q[0], 0, q[1])}))
	var done := m.apply(BuildingCommands.batch(ops))
	check(not done.is_empty(), "room built")
	var walls: Array = []
	var rid := ""
	for op: Dictionary in done.do.ops:
		if op.table == "rooms":
			rid = str(op.entry.id)
		else:
			walls.append(str(op.entry.id))
	for o: Array in doors + windows:
		var res := m.apply(BuildingCommands.place_opening(str(o[2]), walls[int(o[0])], float(o[1])))
		check(not res.is_empty(), "opening %s placed" % str(o))
	return rid


func _apply(m: BuildingModel, ops: Array) -> Array:
	if ops.is_empty():
		return []
	var done := m.apply(BuildingCommands.batch(ops))
	check(not done.is_empty(), "the furniture batch applies")
	var ids: Array = []
	if not done.is_empty():
		for op: Dictionary in done.do.ops:
			ids.append(str(op.entry.id))
	return ids


func _fp(m: BuildingModel, id: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q: Array in m.footprint(id):
		out.append(Vector2(q[0], q[1]))
	return out


func _floor(m: BuildingModel, id: String) -> bool:
	var mode := str(DesignFitoutRules.rule(m.catalog, str(m.parts[id].kind)).mode)
	return mode in ["bed", "wall", "free", "seat", "bedside", "corner"]


func _no_overlaps(m: BuildingModel, ids: Array, what: String) -> void:
	var bad: Array = []
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if _floor(m, ids[i]) and _floor(m, ids[j]) and Layout._overlap(_fp(m, ids[i]), _fp(m, ids[j])):
				bad.append([m.parts[ids[i]].kind, m.parts[ids[j]].kind])
	check(bad.is_empty(), "%s: nothing overlaps %s" % [what, str(bad)])


func _inside(m: BuildingModel, rid: String, ids: Array, what: String) -> void:
	var outline := PackedVector2Array()
	for p: Array in m.rooms[rid].outline:
		outline.append(Vector2(p[0], p[1]))
	var out: Array = []
	for id: String in ids:
		if not Geometry2D.clip_polygons(_fp(m, id), outline).is_empty():
			out.append(m.parts[id].kind)
		elif Layout._edge_distance(_centre(m, id), outline) < 0.05:
			out.append(m.parts[id].kind)
	check(out.is_empty(), "%s: everything inside the walls %s" % [what, str(out)])


func _door_clear(m: BuildingModel, rid: String, ids: Array, what: String) -> void:
	var lay := Layout.new(m, rid)
	var bad: Array = []
	for d: Dictionary in lay.doors:
		for id: String in ids:
			if _floor(m, id) and Layout._overlap(d.zone, _fp(m, id)):
				bad.append(m.parts[id].kind)
	check(not lay.doors.is_empty() and bad.is_empty(), "%s: the door swing is clear %s" % [what, str(bad)])


func _centre(m: BuildingModel, id: String) -> Vector2:
	var at: Array = m.parts[id].at
	return Vector2(at[0], at[2])


## The back (+z) of a piece is within 0.3 m of the room's outline.
func _back_to_wall(m: BuildingModel, rid: String, id: String) -> bool:
	var e: Dictionary = m.parts[id]
	var th := deg_to_rad(float(e.rot))
	var back := _centre(m, id) + Vector2(sin(th), cos(th)) * float(m.catalog.kind(str(e.kind)).d) * 0.5
	var outline := PackedVector2Array()
	for p: Array in m.rooms[rid].outline:
		outline.append(Vector2(p[0], p[1]))
	return Layout._edge_distance(back, outline) < 0.3


## Smallest distance between two footprints.
func _gap(m: BuildingModel, a: String, b: String) -> float:
	var pa := _fp(m, a)
	var pb := _fp(m, b)
	if Layout._overlap(pa, pb):
		return 0.0
	var best := INF
	for p in pa:
		best = minf(best, Layout._edge_distance(p, pb))
	for p in pb:
		best = minf(best, Layout._edge_distance(p, pa))
	return best


func _draw(m: BuildingModel, rid: String, name: String) -> void:
	if _png == "":
		return
	var lay := Layout.new(m, rid)
	var sc := 60.0
	var org := lay.bounds.position - Vector2(1, 1)
	var img := Image.create(int((lay.bounds.size.x + 2) * sc), int((lay.bounds.size.y + 2) * sc), false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	var poly := func(p: PackedVector2Array, col: Color) -> void:
		for i in p.size():
			var a: Vector2 = (p[i] - org) * sc
			var b: Vector2 = (p[(i + 1) % p.size()] - org) * sc
			for t in 200:
				var q := a.lerp(b, t / 199.0)
				if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height():
					img.set_pixelv(Vector2i(q), col)
	var outline := PackedVector2Array()
	for p: Array in m.rooms[rid].outline:
		outline.append(Vector2(p[0], p[1]))
	poly.call(outline, Color.BLACK)
	poly.call(lay.inner, Color.GRAY)
	for d: Dictionary in lay.doors:
		poly.call(d.zone, Color.ORANGE)
	for w: Dictionary in lay.windows:
		poly.call(w.zone, Color.SKY_BLUE)
	for id: String in m.parts_of_family("fixture"):
		var fp := _fp(m, id)
		poly.call(fp, Color.DARK_GREEN)
		# The front edge in red.
		var e: Dictionary = m.parts[id]
		var th := deg_to_rad(float(e.rot))
		var c := _centre(m, id)
		var f := -Vector2(sin(th), cos(th)) * float(m.catalog.kind(str(e.kind)).d) * 0.5
		poly.call(PackedVector2Array([c + f * 0.6, c + f]), Color.RED)
	img.save_png(_png.path_join(name + ".png"))
	var data := {"outline": m.rooms[rid].outline, "doors": lay.doors.map(func(d: Dictionary) -> Array: return Array(d.zone).map(func(v: Vector2) -> Array: return [v.x, v.y])),
		"windows": lay.windows.map(func(d: Dictionary) -> Array: return Array(d.zone).map(func(v: Vector2) -> Array: return [v.x, v.y])), "pieces": []}
	for id: String in m.parts_of_family("fixture"):
		var e: Dictionary = m.parts[id]
		data.pieces.append({"label": str(m.catalog.kind(str(e.kind)).label), "fp": m.footprint(id), "at": e.at, "rot": e.rot,
			"d": float(m.catalog.kind(str(e.kind)).d)})
	var f := FileAccess.open(_png.path_join(name + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
