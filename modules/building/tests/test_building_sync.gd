extends ModuleTest
## Two players over ENet on localhost share one building: edits from either side land the
## same on both, each player undoes only their own, a claimed part refuses the other
## player's edits, a late joiner gets the whole building, and loading a design replaces it
## for everyone. Then the same edits with no session at all.
##   tools/run_tests.sh building

const C := preload("res://modules/building/api/building_commands.gd")
const PORT := 24590


func run_tests() -> void:
	_offline()
	await _two_players()


func _offline() -> void:
	var m := BuildingModel.new()
	var s := BuildingSync.new(m)
	s.edit(C.place_part("column", 0, {"at": [0, 0, 0]}))
	check(m.has("p1"), "unbound, an edit applies straight away")
	s.undo()
	check(not m.has("p1"), "and undoes")
	s.redo()
	check(m.has("p1"), "and redoes")


func _two_players() -> void:
	var saved := Flags.all()
	Flags.set_flag(MultiplayerBus.ONLINE_FLAG, true)
	var a := _bus("BuildA", "Ana")
	var b := _bus("BuildB", "Ben")
	var ma := BuildingModel.new()
	var mb := BuildingModel.new()
	# Something on the host's model before anyone joins.
	ma.apply(C.place_part("wall_loadbearing", 0, {"a": [0, 0, 0], "b": [6, 0, 0]}, "masonry"))
	var sa := BuildingSync.new(ma)
	var sb := BuildingSync.new(mb)
	sa.bind(a, "bld")
	sb.bind(b, "bld")
	check(a.host(PORT) == OK, "host starts")
	b.join("127.0.0.1", PORT)
	check(await _until(func() -> bool: return b.peers().size() == 2 and a.peers().size() == 2), "client joins")
	check(await _until(func() -> bool: return mb.has("p1")), "the joiner gets the building as a snapshot")
	check(mb.checksum() == ma.checksum(), "both copies match after joining")

	sb.edit(C.place_opening("door_external", "p1", 2.0))
	sa.edit(C.place_part("column", 0, {"at": [3, 0, 3]}, "steel"))
	check(await _until(func() -> bool: return ma.parts.size() == 3 and mb.parts.size() == 3), "edits from both sides arrive")
	check(mb.checksum() == ma.checksum(), "and land the same on both")
	var door := ""
	for pid: String in ma.parts:
		if str(ma.parts[pid].kind) == "door_external":
			door = pid
	sb.edit(C.move([door], Vector3(0.5, 0, 0)), "drag")
	sb.edit(C.move([door], Vector3(0.5, 0, 0)), "drag")
	check(await _until(func() -> bool: return float(mb.parts[door].t) == 3.0), "a drag slides the door")
	sb.undo()
	check(await _until(func() -> bool: return float(mb.parts[door].t) == 2.0 and float(ma.parts[door].t) == 2.0),
			"Ben's undo takes the whole drag back on both")
	sb.undo()
	check(await _until(func() -> bool: return not ma.has(door) and not mb.has(door)), "his next undo removes his door")
	check(ma.parts.size() == 2, "Ana's column is untouched by Ben's undo")
	sb.redo()
	check(await _until(func() -> bool: return ma.has(door) and mb.has(door)), "redo brings the door back")

	# Soft lock: Ana holds the column, Ben cannot move it.
	var col := ""
	for pid: String in ma.parts:
		if str(ma.parts[pid].kind) == "column":
			col = pid
	a.claim(col)
	check(await _until(func() -> bool: return b.claim_owner(col) == a.local_peer_id()), "Ana claims the column")
	var refused: Array = []
	sb.rejected.connect(func(reason: String) -> void: refused.append(reason))
	sb.edit(C.move([col], Vector3(1, 0, 0)))
	check(await _until(func() -> bool: return not refused.is_empty()), "Ben's move of a held column is refused")
	check(float(ma.parts[col].at[0]) == 3.0, "and the column has not moved")
	sb.edit(C.place_part("column", 9, {"at": [0, 0, 0]}))
	check(await _until(func() -> bool: return refused.size() == 2), "a part on a missing level is refused too")
	a.release(col)

	# A late joiner.
	var c := _bus("BuildC", "Cas")
	var mc := BuildingModel.new()
	var sc := BuildingSync.new(mc)
	sc.bind(c, "bld")
	c.join("127.0.0.1", PORT)
	check(await _until(func() -> bool: return mc.checksum() == ma.checksum()), "a late joiner gets the same building")

	# Load a design for everyone.
	var house := BuildingModel.new("h", "Loaded house")
	house.apply(C.place_room("kitchen", 0, C.rect(0, 0, 3, 3)))
	sb.load_design(house.to_data())
	check(await _until(func() -> bool: return ma.name == "Loaded house" and mb.name == "Loaded house" and mc.name == "Loaded house"),
			"loading a design replaces it for everyone")
	check(ma.parts.is_empty() and mc.rooms.size() == 1 and mb.checksum() == ma.checksum(), "with the loaded contents")
	sc.edit(C.place_part("column", 0, {"at": [1, 0, 1]}))
	check(await _until(func() -> bool: return ma.parts.size() == 1 and mb.parts.size() == 1 and mc.parts.size() == 1), "and editing carries on")
	check(ma.checksum() == mb.checksum() and mb.checksum() == mc.checksum(), "all three copies match")

	sa.unbind()
	sb.unbind()
	sc.unbind()
	c.leave()
	b.leave()
	a.leave()
	Flags.use(saved)


func _bus(node_name: String, player: String) -> MultiplayerBus:
	var bus := MultiplayerBus.new()
	bus.name = node_name
	add_child(bus)
	bus.register_module()
	Settings.set_value("multiplayer", "player_name", player)
	bus._refresh_identity()
	return bus


func _until(cond: Callable, timeout := 5.0) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()
