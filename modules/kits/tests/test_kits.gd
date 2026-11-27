extends ModuleTest
## Room modules: capture a room and its contents, place copies turned and side by side, share
## the library with the crew (and a late joiner), the designer and walk-inside hooks, and the
## object preview's figures and floating window.
##   tools/run_tests.sh kits

const C := preload("res://modules/building/api/building_commands.gd")


class Wire:
	var peers: Array = []
	var rejected: Array[String] = []


class FakeNet:
	var wire: Wire
	var peer_id := 1
	var events := {}
	var snapshots := {}

	func register_event(event_name: String, apply: Callable, validate := Callable()) -> void:
		events[event_name] = {"apply": apply, "validate": validate}

	func unregister_event(event_name: String) -> void:
		events.erase(event_name)

	func register_snapshot_provider(section: String, provider: Object) -> void:
		snapshots[section] = provider

	func unregister_snapshot_provider(section: String) -> void:
		snapshots.erase(section)

	func player_name(peer: int) -> String:
		return "Player %d" % peer

	func request(event_name: String, payload: Dictionary = {}) -> void:
		var host: FakeNet = wire.peers[0]
		var sent: Dictionary = bytes_to_var(var_to_bytes(payload))
		var entry: Dictionary = host.events[event_name]
		var out: Variant = sent
		if entry.validate.is_valid():
			out = entry.validate.call(peer_id, sent)
		if out is String:
			wire.rejected.append(out)
			return
		var bytes := var_to_bytes(out)
		for p: FakeNet in wire.peers:
			p.events[event_name].apply.call(bytes_to_var(bytes))

	func join(host: FakeNet) -> void:
		for section: String in host.snapshots:
			var data: Dictionary = bytes_to_var(var_to_bytes(host.snapshots[section].get_net_snapshot()))
			snapshots[section].apply_net_snapshot(data)


## A stand-in design bus with the palette hooks.
class FakeDesign:
	extends Node
	signal palette_previewed(kind: String, id: String, source: String)
	var groups := {}
	var refreshed := 0
	var stamp: Dictionary = {}

	func register_palette_group(kind: String, id: String, title: String, items: Callable, pick: Callable, order: int = 50) -> void:
		groups[id] = {"kind": kind, "title": title, "items": items, "pick": pick, "order": order}

	func unregister_palette_group(_kind: String, id: String) -> void:
		groups.erase(id)

	func refresh_palette() -> void:
		refreshed += 1

	func begin_stamp(label: String, ghost: Node3D, ops_at: Callable) -> void:
		stamp = {"label": label, "ghost": ghost, "ops_at": ops_at}


class FakeWalk:
	extends Node
	var preview := Callable()
	var takers := {}

	func set_preview_maker(make: Callable) -> void:
		preview = make

	func register_taker(id: String, take: Callable) -> void:
		takers[id] = take

	func unregister_taker(id: String) -> void:
		takers.erase(id)


func run_tests() -> void:
	_starters()
	_capture()
	_place_turned()
	_side_by_side()
	_library_sync()
	await _bus_and_hooks()
	await _preview()


## A bedroom: four walls, a door and a window, a bed and a desk; outside it a sofa and a stair.
func _bedroom() -> Array:
	var m := BuildingModel.new()
	m.apply(C.add_level())
	var r := m.apply(C.place_room("bedroom", 0, C.rect(2, 1, 4, 3), "Main"))
	var corners := [Vector3(2, 0, 1), Vector3(6, 0, 1), Vector3(6, 0, 4), Vector3(2, 0, 4)]
	var walls: Array = []
	for i in 4:
		walls.append(str(m.apply(C.place_part("wall_loadbearing", 0, {"a": corners[i], "b": corners[(i + 1) % 4]}, "masonry")).do.entry.id))
	m.apply(C.place_opening("door_internal", walls[0], 0.8))
	m.apply(C.place_opening("window_medium", walls[1], 1.5))
	m.apply(C.place_part("bed_double", 0, {"at": Vector3(4, 0, 3), "rot": 0.0}))
	m.apply(C.place_part("desk_office", 0, {"at": Vector3(2.6, 0, 2), "rot": 90.0}))
	m.apply(C.place_part("sofa", 0, {"at": Vector3(9, 0, 9), "rot": 0.0}))
	m.apply(C.place_stair(0, Vector3(3, 0, 2), Vector3(3, 0, 3.5)))
	return [m, str(r.do.entry.id)]


func _kinds(kit: Dictionary) -> Dictionary:
	var out := {}
	for row: Dictionary in kit.parts:
		var k := str(row.entry.kind)
		out[k] = int(out.get(k, 0)) + 1
	return out


func _starters() -> void:
	var lib := KitLibrary.new()
	lib.persist = false
	lib.load_local()
	var all := lib.list()
	check(all.size() >= 10, "starter modules: %d" % all.size())
	var bad: Array = []
	for row: Dictionary in all:
		var m := BuildingModel.new()
		var ops := KitCapture.place_ops(m, lib.get_kit(row.name), 0, Vector3(10, 0, 10), 0.0)
		var fitted := _kinds(lib.get_kit(row.name))
		if ops.is_empty() or m.apply(C.batch(ops)).is_empty() or m.rooms.size() != 1 or int(fitted.get("wall_loadbearing", 0)) != 4:
			bad.append(row.name)
	check(bad.is_empty(), "every starter module places into an empty building: %s" % str(bad))
	check(lib.groups().has("Homes") and lib.groups().has("Schools"), "starters are grouped: %s" % str(lib.groups()))
	check(lib.list("bath").size() >= 1 and lib.list("", "Offices").size() == 2, "filter by text and by group")
	check(lib.remove("Galley kitchen") != "", "starter modules can't be deleted")


func _capture() -> void:
	var got := _bedroom()
	var m: BuildingModel = got[0]
	var kit := KitCapture.capture(m, got[1], "My bedroom", "Homes")
	var k := _kinds(kit)
	check(int(k.get("wall_loadbearing", 0)) == 4 and int(k.get("door_internal", 0)) == 1 and int(k.get("window_medium", 0)) == 1,
			"the room's walls, door and window are in the module: %s" % str(k))
	check(int(k.get("bed_double", 0)) == 1 and int(k.get("desk_office", 0)) == 1, "and its fittings")
	check(not k.has("sofa") and not k.has("stair"), "not what is outside it, nor stairs")
	check(kit.size == [4.0, 3.0] and kit.room.type == "bedroom" and kit.room.name == "Main", "size and room: %s" % str(kit.size))
	var bed: Dictionary = {}
	for row: Dictionary in kit.parts:
		if row.entry.kind == "bed_double":
			bed = row.entry
	check(bed.at == [2.0, 0.0, 2.0], "coordinates from the room's corner: %s" % str(bed.at))
	check(KitCapture.problem(kit) == "" and KitCapture.problem({"name": ""}) != "", "problem() checks a module")
	var through: Variant = JSON.parse_string(JSON.stringify(kit))
	check(KitCapture.problem(through) == "" and not KitCapture.place_ops(BuildingModel.new(), through, 0, Vector3.ZERO).is_empty(),
			"a module survives JSON (the saved file)")


func _place_turned() -> void:
	var got := _bedroom()
	var kit := KitCapture.capture(got[0], got[1], "Bed", "")
	var m := BuildingModel.new()
	var ops := KitCapture.place_ops(m, kit, 0, Vector3(10, 0, 10), 90.0)
	var r := m.apply(C.batch(ops))
	check(not r.is_empty(), "a turned copy applies as one batch")
	var rid: String = m.rooms.keys()[0]
	check(is_equal_approx(absf(BuildingModel.outline_area(m.rooms[rid].outline)), 12.0), "same floor area")
	var xs: Array = []
	var zs: Array = []
	for p: Array in m.rooms[rid].outline:
		xs.append(p[0])
		zs.append(p[1])
	check(is_equal_approx(xs.max() - xs.min(), 3.0) and is_equal_approx(zs.max() - zs.min(), 4.0), "a quarter turn swaps width and depth")
	var hosted := 0
	var bed_rot := -1.0
	for pid: String in m.parts:
		var e: Dictionary = m.parts[pid]
		if e.has("host"):
			hosted += 1 if m.parts.has(str(e.host)) else 0
		if e.kind == "bed_double":
			bed_rot = float(e.rot)
			check(BuildingModel.outline_has_point(m.rooms[rid].outline, e.at[0], e.at[2]), "the bed is still in the room")
	check(hosted == 2, "door and window are on the copy's new walls")
	check(is_equal_approx(bed_rot, 90.0), "fittings turn with the module: %s" % bed_rot)
	var undo: Dictionary = r.undo
	m.apply(undo)
	check(m.parts.is_empty() and m.rooms.is_empty(), "one undo takes the whole module back")


func _side_by_side() -> void:
	var lib := KitLibrary.new()
	lib.persist = false
	lib.load_local()
	var kit := lib.get_kit("Single bedroom")
	var m := BuildingModel.new()
	var w := float(kit.size[0])
	m.apply(C.batch(KitCapture.place_ops(m, kit, 0, Vector3(w / 2.0, 0, 5), 0.0)))
	var walls_before := m.parts_of_family("wall").size()
	# The next one along: its left wall is the first one's right wall.
	var ops := KitCapture.place_ops(m, kit, 0, Vector3(w * 1.5, 0, 5), 0.0)
	check(not m.apply(C.batch(ops)).is_empty(), "a second module next to the first applies")
	check(m.parts_of_family("wall").size() - walls_before == 3, "they share a wall: %d new walls" % (m.parts_of_family("wall").size() - walls_before))
	check(m.rooms.size() == 2, "two rooms")


func _library_sync() -> void:
	var wire := Wire.new()
	var libs: Array = []
	var nets: Array = []
	for i in 3:
		var n := FakeNet.new()
		n.wire = wire
		n.peer_id = 1 if i == 0 else 10 + i
		var lib := KitLibrary.new()
		lib.persist = false
		lib.load_local()
		nets.append(n)
		libs.append(lib)
	wire.peers = [nets[0], nets[1]]
	libs[0].bind(nets[0])
	libs[1].bind(nets[1])
	var got := _bedroom()
	var kit := KitCapture.capture(got[0], got[1], "Guest room", "Homes")
	check(libs[1].save(kit) == "", "a client saves a module")
	check(libs[0].has_kit("Guest room") and libs[1].has_kit("guest room"), "host and client both have it")
	check(str(libs[0].get_kit("Guest room").author) == "Player 11", "stamped with who saved it")
	check(libs[1].save(KitCapture.capture(got[0], got[1], "", "")) != "", "no name, no module")
	var fake := kit.duplicate(true)
	fake["name"] = "Double bedroom"
	check(libs[1].save(fake) != "", "a starter's name is refused")
	# A late joiner with a module of its own: it gets the host's and shares its own.
	var own := kit.duplicate(true)
	own["name"] = "Loft"
	libs[2]._apply_save({"kit": own})
	wire.peers.append(nets[2])
	libs[2].bind(nets[2])
	nets[2].join(nets[0])
	check(libs[2].has_kit("Guest room"), "a late joiner gets the crew's modules")
	check(libs[0].has_kit("Loft") and libs[1].has_kit("Loft"), "and shares its own with them")
	check(libs[0].remove("Guest room") == "" and not libs[2].has_kit("Guest room"), "deleting is for everyone")
	check(wire.rejected.is_empty(), "bad saves are refused before they are sent: %s" % str(wire.rejected))


func _bus_and_hooks() -> void:
	var bus := Modules.bus("kits") as KitsBus
	check(bus != null, "kits bus loaded")
	if bus == null:
		return
	bus.library.persist = false
	var building := Modules.bus("building") as BuildingBus
	var got := _bedroom()
	var src: BuildingModel = got[0]
	check(bus.save_room(src, got[1], "Test bedroom", "Tests") == "", "save_room on the bus")
	check(bus.save_room(src, "r999", "X") != "", "save_room needs a room")
	check(bus.has_module("Test bedroom"), "the bus has it")
	var design := FakeDesign.new()
	add_child(design)
	bus.hook_design(design)
	check(design.groups.has(KitsBus.GROUP) and str(design.groups[KitsBus.GROUP].kind) == "rooms", "a 'Saved modules' palette group")
	var items: Array = (design.groups[KitsBus.GROUP].items as Callable).call()
	var ids: Array = items.map(func(it: Dictionary) -> String: return str(it.id))
	check(ids.has("kits:Test bedroom") and ids.has("kits:Double bedroom"), "it lists saved and starter modules")
	var before := design.refreshed
	bus.save_room(src, got[1], "Test bedroom 2", "Tests")
	check(design.refreshed > before, "the palette refreshes when a module arrives")
	(design.groups[KitsBus.GROUP].pick as Callable).call("kits:Test bedroom")
	check(not design.stamp.is_empty() and design.stamp.ghost is Node3D, "picking stamps it with a ghost")
	if not design.stamp.is_empty():
		var ops: Array = (design.stamp.ops_at as Callable).call(0, Vector3(30, 0, 30), 180.0)
		check(ops.size() > 5, "the stamp's ops: %d" % ops.size())
		var n := building.model.rooms.size()
		building.sync.edit(C.batch(ops))
		await frames(2)
		check(building.model.rooms.size() == n + 1, "stamped into the shared building")
		(design.stamp.ghost as Node).free()
	design.palette_previewed.emit("objects", "bath", "")
	await frames(2)
	var win := bus.preview_window(get_tree().root)
	check(win != null and win.visible, "a palette click pops the floating preview")
	# Walk-inside: preview maker and the module taker.
	var walk := FakeWalk.new()
	add_child(walk)
	var was := Flags.is_on(KitsBus.WALK_PREVIEW_FLAG)
	Flags.set_flag(KitsBus.WALK_PREVIEW_FLAG, true)
	bus.hook_walk(walk)
	Flags.set_flag(KitsBus.WALK_PREVIEW_FLAG, was)
	check(walk.preview.is_valid(), "walk gets a preview maker")
	var pv: Variant = walk.preview.call({"id": "kits:Test bedroom", "label": "Test bedroom", "tags": ["module"]})
	check(pv is KitPreview and (pv as KitPreview).showing.type == "module", "walk's preview shows a module")
	if pv is Node:
		(pv as Node).free()
	var m2 := BuildingModel.new()
	m2.apply(C.batch(bus.place_ops(m2, "kits:Test bedroom", 0, Vector3(20, 0, 4), 90.0)))
	check(m2.rooms.size() == 1, "place_ops takes a palette item id too (walk carries modules)")
	var g2 := bus.make_ghost("kits:Test bedroom")
	check(g2 != null, "and so does make_ghost")
	if g2:
		g2.free()
	check(bus.delete_module("Test bedroom") == "" and bus.delete_module("Test bedroom 2") == "", "delete")
	bus.hide_preview()
	design.queue_free()
	walk.queue_free()


func _preview() -> void:
	var cat := BuildingCatalog.default_catalog()
	var p := KitPreview.new()
	add_child(p)
	p.show_kind(cat, "bath")
	await frames(3)
	var rows := {}
	for r: Array in p.figure_rows():
		rows[r[0]] = r[1]
	check(rows.has("Size") and "1.70 D" in str(rows.Size), "size from the catalog: %s" % str(rows.get("Size")))
	check(rows.has("Weight") and rows.has("Cost"), "weight and cost: %s" % str(rows))
	check("cold 18.0" in str(rows.get("Water", "")) and "hot 18.0" in str(rows.get("Water", "")), "water: %s" % str(rows.get("Water")))
	check(rows.has("Power") and rows.has("Waste"), "power and waste")
	check(p.shown_node() != null and p.shown_node().is_inside_tree(), "the model is in the picture")
	var spin := p.turntable.rotation.y
	await frames(3)
	check(p.turntable.rotation.y != spin, "it turns")
	p.show_kind(cat, "shower")
	rows = {}
	for r: Array in p.figure_rows():
		rows[r[0]] = r[1]
	check("9.5 kW" in str(rows.get("Power", "")), "an electric shower's power: %s" % str(rows.get("Power")))
	var lib := KitLibrary.new()
	lib.persist = false
	lib.load_local()
	p.show_kit(cat, lib.get_kit("Family bathroom"))
	rows = {}
	for r: Array in p.figure_rows():
		rows[r[0]] = r[1]
	check(rows.has("Floor area") and rows.has("Fittings") and rows.has("Water"), "a module's totals: %s" % str(rows))
	p.show_room_type(cat, "bedroom")
	check(p.showing.type == "room" and p.title_label.text != "", "a room type's brief")
	p.queue_free()
	# Every fitting, door and window has figures and a model.
	var missing: Array = []
	for fam: String in ["fixture", "opening", "column"]:
		for k in cat.kinds_in(fam):
			var s := ObjectSpecs.for_kind(cat, k)
			if s.is_empty() or (s.size as Vector3).x <= 0.0:
				missing.append(k)
	check(missing.is_empty(), "figures for every placeable object: %s" % str(missing))
	# The floating window rolls up and down.
	var bus := Modules.bus("kits") as KitsBus
	var win := bus.show_preview("objects", "sofa", get_tree().root)
	check(win != null, "show_preview in a viewport")
	if win:
		win.call("set_rolled", true)
		check(not (win.get("preview") as Control).visible, "rolled up")
		win.call("set_rolled", false)
		check((win.get("preview") as Control).visible, "rolled down")
	check(bus.show_preview("objects", "no_such_thing", get_tree().root) == null, "nothing to show for an unknown id")
	bus.hide_preview()
