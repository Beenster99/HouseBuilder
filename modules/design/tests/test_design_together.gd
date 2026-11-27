extends ModuleTest
## Two, then three players in one design room over ENet on localhost, each with their own
## bus, building model and design session: a joiner gets the design so far, edits from
## everyone land the same everywhere, cursors and drag lines stream, selections show, a drag
## locks its parts against the others until drop (or a stalled drag times out), undo is
## per player, a loaded design replaces the building for everyone, and a long burst of
## mixed edits from all three ends with identical copies.
##   tools/run_tests.sh design

const C := preload("res://modules/building/api/building_commands.gd")
const PORT := 24581


func run_tests() -> void:
	var saved := Flags.all()
	Flags.set_flag(MultiplayerBus.ONLINE_FLAG, true)
	var a := _player("Ana")
	var b := _player("Ben")
	var na: MultiplayerBus = a.net
	var nb: MultiplayerBus = b.net
	var sa: DesignSession = a.session
	var sb: DesignSession = b.session
	var ma: BuildingModel = a.model
	var mb: BuildingModel = b.model

	# Ana starts on her own, then hosts; Ben joins and gets the room.
	sa.set_tool("room")
	sa.press(Vector3(0, 0, 0))
	sa.release(Vector3(6, 0, 4))
	check(na.host(PORT) == OK, "Ana hosts")
	nb.join("127.0.0.1", PORT)
	check(await _until(func() -> bool: return nb.peers().size() == 2 and na.peers().size() == 2), "Ben joins")
	check(await _until(func() -> bool: return mb.rooms.size() == 1 and mb.checksum() == ma.checksum()), "Ben gets Ana's room and walls")
	var ana := na.local_peer_id()
	var ben := nb.local_peer_id()

	# Edits from both sides land the same.
	sb.set_tool("wall")
	sb.press(Vector3(0, 0, 8))
	sb.press(Vector3(6, 0, 8))
	sb.cancel()
	sa.set_tool("column")
	sa.press(Vector3(10, 0, 0))
	check(await _until(func() -> bool: return ma.parts.size() == 6 and mb.parts.size() == 6), "a wall from Ben and a column from Ana")
	check(ma.checksum() == mb.checksum(), "the same on both")
	var col: String = ma.parts_of_family("column")[0]

	# Cursors and drag lines stream.
	sa.set_tool("wall")
	sa.press(Vector3(2, 0, 10))
	sa.hover(Vector3(5, 0, 10))
	check(await _until(func() -> bool:
		var o: Dictionary = sb.presence.others().get(ana, {})
		return o.get("cursor") is Vector3 and (o.cursor as Vector3).distance_to(Vector3(5, 0, 10)) < 0.01 \
				and o.get("anchor") is Vector3 and (o.anchor as Vector3).distance_to(Vector3(2, 0, 10)) < 0.01), \
			"Ben sees Ana's cursor and the wall she is drawing")
	sa.cancel()
	check(await _until(func() -> bool: return sb.presence.others()[ana].anchor == null), "her drag line goes when she stops")
	sb.hover(null)
	check(await _until(func() -> bool: return sa.presence.others().get(ben, {}).get("cursor", 0) == null), "a cursor off the plot hides")

	# Selections show for everyone.
	sa.set_tool("select")
	sa.press(Vector3(10, 0, 0))
	check(await _until(func() -> bool: return sb.presence.selection_of(ana) == PackedStringArray([col])), "Ben sees what Ana selected")

	# A drag locks its parts against everyone else.
	sa.hover(Vector3(11, 0, 0))
	check(await _until(func() -> bool: return sb.presence.locked_by(col) == ana), "Ana's drag locks the column for Ben")
	var refused: Array[String] = []
	sb.status.connect(func(t: String, warn: bool) -> void:
		if warn:
			refused.append(t))
	sb.sync.edit(C.move([col], Vector3(0, 0, 3)))
	check(await _until(func() -> bool: return refused.size() >= 1), "the host refuses Ben's edit to it")
	check(refused[0].contains("being edited by"), "and says someone has it: %s" % str(refused))
	sb.set_tool("select")
	sb.press(Vector3(10, 0, 0))
	sb.hover(Vector3(10, 0, 2))
	check(sb.drag.is_empty(), "Ben cannot start dragging it either")
	sb.release(Vector3(10, 0, 2))
	sa.hover(Vector3(13, 0, 1))
	sa.release(Vector3(13, 0, 1))
	check(await _until(func() -> bool: return float(mb.parts[col].at[0]) == 13.0), "Ana drops it; Ben sees it move")
	check(await _until(func() -> bool: return sb.presence.locked_by(col) == 0), "and the lock goes")
	check(ma.checksum() == mb.checksum(), "still the same")

	# A stalled drag lets go by itself.
	sa.press(Vector3(13, 0, 1))
	sa.hover(Vector3(14, 0, 1))
	check(await _until(func() -> bool: return sb.presence.locked_by(col) == ana), "locked again")
	sa.presence.clock_override = Time.get_ticks_msec() / 1000.0 + DesignPresence.LOCK_TIMEOUT + 1.0
	sa.presence.sweep_locks()
	check(await _until(func() -> bool: return sb.presence.locked_by(col) == 0), "a lock not renewed times out")
	sa.presence.clock_override = -1.0
	sa.cancel()

	# Undo is per player.
	var walls_before := mb.parts_of_family("wall").size()
	sb.undo()
	check(await _until(func() -> bool: return ma.parts_of_family("wall").size() == walls_before - 1), "Ben's undo takes his wall")
	check(ma.has(col) and float(ma.parts[col].at[0]) == 13.0, "and leaves Ana's work alone")
	sb.redo()
	check(await _until(func() -> bool: return ma.parts_of_family("wall").size() == walls_before), "redo")

	# A third player joins late.
	var c := _player("Cas")
	var sc: DesignSession = c.session
	var mc: BuildingModel = c.model
	(c.net as MultiplayerBus).join("127.0.0.1", PORT)
	check(await _until(func() -> bool: return mc.checksum() == ma.checksum() and mc.parts.size() > 0), "Cas joins late with the same design")
	check(await _until(func() -> bool: return sc.presence.selection_of(ana) == PackedStringArray([col])), "and sees Ana's selection")

	# A long burst of mixed edits from all three.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var sessions: Array[DesignSession] = [sa, sb, sc]
	for i in 150:
		var s: DesignSession = sessions[i % 3]
		var x := rng.randi_range(-30, 30) * 0.5
		var z := rng.randi_range(-30, 30) * 0.5
		match rng.randi() % 6:
			0:
				s.set_tool("column")
				s.press(Vector3(x, 0, z))
			1:
				s.set_tool("wall")
				s.press(Vector3(x, 0, z))
				s.press(Vector3(x + rng.randi_range(1, 6), 0, z))
				s.cancel()
			2:
				s.set_tool("room")
				s.press(Vector3(x, 0, z))
				s.release(Vector3(x + rng.randi_range(2, 5), 0, z + rng.randi_range(2, 5)))
			3:
				s.undo()
			4:
				s.set_tool("select")
				s.press(Vector3(x, 0, z))
				s.hover(Vector3(x + 1, 0, z))
				s.release(Vector3(x + 1, 0, z + 1))
			5:
				s.set_tool("door")
				s.press(Vector3(x, 0, z))
		if i % 10 == 0:
			await frames(1)
	check(await _until(func() -> bool:
		return ma.checksum() == mb.checksum() and mb.checksum() == mc.checksum() and ma.revision > 20, 10.0),
			"after 150 mixed edits all three copies match (%d parts)" % ma.parts.size())
	var desyncs: Array = [a.desyncs, b.desyncs, c.desyncs]
	check(desyncs == [0, 0, 0], "no desync reported: %s" % str(desyncs))

	# Loading a design replaces it for everyone.
	sb.save_design("Together test")
	sc.new_design()
	check(await _until(func() -> bool: return ma.parts.is_empty() and mb.parts.is_empty()), "New clears it for everyone")
	sa.load_design("Together test")
	check(await _until(func() -> bool: return ma.parts.size() > 5 and ma.checksum() == mb.checksum() and mb.checksum() == mc.checksum()),
			"a saved design loads for all three, identical")

	# A library asset placed by one player (an airliner, as from walk-inside) reaches the
	# others and their views draw its model at true size, not a box.
	var jet := "airport.aircraft.jumbo"
	var jets := func(m: BuildingModel) -> Array:
		return m.parts.keys().filter(func(id: String) -> bool: return str(m.parts[id].kind) == jet)
	if mb.catalog.has_kind(jet):
		(b.sync as BuildingSync).edit(C.place_part(jet, 0, {"at": [30, 0, 30], "rot": 90}))
		check(await _until(func() -> bool: return (jets.call(ma) as Array).size() == 1 and (jets.call(mc) as Array).size() == 1),
				"an airliner Ben places reaches Ana and Cat")
		var view: Node3D = (load("res://modules/design/internal/room/design_view.gd") as GDScript).new()
		add_child(view)
		view.call("bind", ma)
		await frames(4)
		var drawn: Node3D = view.find_child("Asset_" + str((jets.call(ma) as Array)[0]), true, false)
		check(drawn != null and drawn.visible and drawn.find_children("*", "MeshInstance3D", true, false).size() > 1,
				"and Ana's view draws the airliner's own model")
		if drawn:
			check(drawn.position.distance_to(Vector3(30, 0, 30)) < 0.01 and is_equal_approx(drawn.rotation_degrees.y, 90.0),
					"where Ben put it, turned as he turned it")
		view.queue_free()

	for p: Dictionary in [c, b, a]:
		(p.session as DesignSession).teardown()
		(p.sync as BuildingSync).unbind()
		(p.net as MultiplayerBus).leave()
	Flags.use(saved)


func _player(who: String) -> Dictionary:
	var bus := MultiplayerBus.new()
	bus.name = "Net_" + who
	add_child(bus)
	bus.register_module()
	Settings.set_value("multiplayer", "player_name", who)
	bus._refresh_identity()
	var model := BuildingModel.new()
	var sync := BuildingSync.new(model)
	sync.bind(bus, "bld")
	var s := DesignSession.new()
	s.name = "Design_" + who
	add_child(s)
	s.setup(bus, model, sync)
	var out := {"net": bus, "model": model, "sync": sync, "session": s, "desyncs": 0}
	sync.desync.connect(func(_seq: int) -> void: out.desyncs += 1)
	return out


func _until(cond: Callable, timeout := 5.0) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()
