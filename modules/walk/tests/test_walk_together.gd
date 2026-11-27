extends ModuleTest
## Walking inside together, over ENet on localhost: two players walk the same building, each
## sees the other as a figure in their colour following their walk and their pointer where
## they aim; the walkers list (for the design room's holotable and screens) has both, with
## positions and pointers; a wall one pushes moves for the other; a part one holds can't be
## moved by the other; and leaving takes you off the list for everyone.
##   tools/run_tests.sh walk

const C := preload("res://modules/building/api/building_commands.gd")
const WalkInside := preload("res://modules/walk/internal/walk_inside.gd")
const PORT := 24585


func run_tests() -> void:
	var saved := Flags.all()
	Flags.set_flag(MultiplayerBus.ONLINE_FLAG, true)
	var a := _player("Ana")
	var b := _player("Ben")
	var na: MultiplayerBus = a.net
	var nb: MultiplayerBus = b.net
	var ma: BuildingModel = a.model
	var mb: BuildingModel = b.model
	var sa: BuildingSync = a.sync
	sa.edit(C.place_part("slab", 0, {"outline": C.rect(-0.2, -0.2, 8.4, 6.4), "y": 0.0}))
	for w: Array in [[Vector3(0, 0, 0), Vector3(8, 0, 0)], [Vector3(8, 0, 0), Vector3(8, 0, 6)],
			[Vector3(8, 0, 6), Vector3(0, 0, 6)], [Vector3(0, 0, 6), Vector3(0, 0, 0)]]:
		sa.edit(C.place_part("wall_loadbearing", 0, {"a": w[0], "b": w[1]}))
	sa.edit(C.place_room("living_room", 0, C.rect(0, 0, 8, 6), "Lounge"))
	sa.edit(C.place_part("sofa", 0, {"at": Vector3(4, 0, 3)}))
	check(na.host(PORT) == OK, "Ana hosts")
	nb.join("127.0.0.1", PORT)
	check(await _until(func() -> bool: return mb.checksum() == ma.checksum() and mb.parts.size() == 6), "Ben joins with the house")
	var ana := na.local_peer_id()
	var ben := nb.local_peer_id()
	var wa: WalkBus = a.walk
	var wb: WalkBus = b.walk

	# Both walk inside.
	var va: WalkInside = wa.open(ma, self, {"at": Vector3(2, 0, 3), "yaw": 0.0}, a.sync)
	var vb: WalkInside = wb.open(mb, self, {"at": Vector3(6, 0, 3), "yaw": PI}, b.sync)
	check(va != null and vb != null, "both open walk-inside")
	check(await _until(func() -> bool: return wa.walkers.has(ben) and wb.walkers.has(ana) and wa.walkers.size() == 2 and wb.walkers.size() == 2),
			"each has both walkers: %s / %s" % [wa.walkers.keys(), wb.walkers.keys()])
	check(str(wb.walkers[ana].name) == nb.player_name(ana) and wb.walkers[ana].colour is Color, "with their name and colour: %s" % [wb.walkers[ana]])
	check(await _until(func() -> bool: return vb.crew.has(ana) and va.crew.has(ben)), "each sees the other's figure")

	# Ana walks; Ben sees her figure follow, and the walkers list has where she is.
	va.body.position = Vector3(3, 0.95, 2)
	check(await _until(func() -> bool:
		var fig: Node3D = vb.crew[ana].figure
		return fig.position.distance_to(Vector3(3, 0.05, 2)) < 0.1), "Ben sees Ana's figure where she walks to")
	check(await _until(func() -> bool: return (wb.walkers[ana].pos as Vector3).distance_to(Vector3(3, 0.95, 2)) < 0.1),
			"the walkers list has her position (for the holotable)")

	# Ana aims at the back wall: Ben sees her pointer there.
	_face(va, Vector3(3, 1.5, 0))
	await _physics(2)
	var aim: Variant = va.aim_point()
	check(aim is Vector3 and absf((aim as Vector3).z) < 0.2, "Ana aims at the back wall: %s" % [aim])
	check(await _until(func() -> bool:
		var dot: Node3D = vb.crew[ana].dot
		return dot.visible and dot.position.distance_to(aim) < 0.1), "Ben sees her pointer on it")
	check(await _until(func() -> bool: return wb.walkers[ana].aim is Vector3 and (wb.walkers[ana].aim as Vector3).distance_to(aim) < 0.1),
			"and the walkers list has her pointer (for the screens)")

	# Ana pushes the wall away: it moves for Ben too.
	var back := va.aimed_part()
	check(va.push(1), "Ana pushes the back wall")
	check(await _until(func() -> bool: return is_equal_approx(float(mb.parts[back].a[2]), -0.25) and mb.checksum() == ma.checksum()),
			"it moves for Ben, the same on both")

	# Ben picks up the sofa: Ana can't move it while he holds it.
	var sofa := ""
	for id: String in mb.parts:
		if str(mb.parts[id].kind) == "sofa":
			sofa = id
	check(vb.pick_up(sofa), "Ben picks up the sofa")
	check(await _until(func() -> bool: return na.claim_owner(sofa) == ben), "it is his while he holds it")
	check(not va.pick_up(sofa), "Ana can't pick it up")
	var refused := [0]
	sa.rejected.connect(func(_r: String) -> void: refused[0] += 1)
	sa.edit(C.move([sofa], Vector3(1, 0, 0)))
	check(await _until(func() -> bool: return refused[0] > 0), "and the host refuses her moving it")
	_face(vb, Vector3(5, 0, 4.5))
	await _physics(2)
	check(vb.put_down(), "Ben puts it down")
	check(await _until(func() -> bool: return na.claim_owner(sofa) == 0 and float(ma.parts[sofa].at[2]) > 3.5),
			"it moved for Ana and is free again")

	# Ana leaves: she goes off Ben's list and his view.
	wa.close()
	check(await _until(func() -> bool: return not wb.walkers.has(ana) and not vb.crew.has(ana)), "Ana leaves the walk for everyone")
	wb.close()
	check(await _until(func() -> bool: return wa.walkers.is_empty() and wb.walkers.is_empty()), "and then nobody is walking")
	check(int(a.desyncs) == 0 and int(b.desyncs) == 0, "no desyncs")

	nb.leave()
	na.leave()
	await frames(3)
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
	var walk := WalkBus.new()
	walk.name = "Walk_" + who
	add_child(walk)
	walk.bind(bus)
	var out := {"net": bus, "model": model, "sync": sync, "walk": walk, "desyncs": 0}
	sync.desync.connect(func(_seq: int) -> void: out.desyncs += 1)
	return out


func _face(v: WalkInside, at: Vector3) -> void:
	var eye := v.body.position + Vector3(0, 0.7, 0)
	var d := at - eye
	v.body.rotation.y = atan2(-d.x, -d.z)
	v._pitch = atan2(d.y, Vector2(d.x, d.z).length())
	v.camera.rotation.x = v._pitch


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _until(cond: Callable, timeout := 5.0) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()
