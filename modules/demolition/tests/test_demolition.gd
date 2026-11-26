extends ModuleTest
## The shared demolition: charges on the timeline, refusals, firing, Jolt bringing the demo
## office down on the host, the score, reset and join snapshots.
##   tools/run_tests.sh demolition

const DemoOffice := preload("res://modules/demolition/internal/demo_office.gd")

var rejected: Array[String] = []


func run_tests() -> void:
	var bus := Modules.bus("demolition") as DemolitionBus
	check(bus != null, "demolition bus loaded")
	if bus == null:
		return
	bus.net.request_rejected.connect(func(n, why): rejected.append("%s: %s" % [n, why]))
	bus.start_demolition(DemoOffice.parts(), "Office", {"neighbours": DemoOffice.neighbours(), "open": false})
	check(bus.is_active() and bus.parts.size() == DemoOffice.parts().size(), "the host sets up the site")
	check(bus.zone.has_point(Vector2(7.5, 5)) and bus.neighbours.size() == 2, "drop zone and neighbours")

	bus.request_charge("col_0_0_0", 0.3)
	check(is_equal_approx(bus.charges.get("col_0_0_0", -1.0), 0.25), "a charge snaps to the 0.25 s timeline")
	bus.request_charge("col_0_0_0", 0.25)
	check(not bus.charges.has("col_0_0_0"), "the same delay again removes it")
	bus.request_charge("pad_0_0", 0.0)
	bus.request_charge("nothing", 0.0)
	check(bus.charges.is_empty() and rejected.size() == 2, "no charges on foundations or unknown parts: %s" % str(rejected))
	bus.request_fire()
	check(not bus.is_fired() and rejected.size() == 3, "no firing without charges")

	# Bring it down: every ground-floor column, the middle ones first.
	var view: Node3D = load("res://modules/demolition/internal/demolition_view.tscn").instantiate()
	add_child(view)
	await frames(3)
	var bodies := 0
	for id: String in view._chunks:
		bodies += (view._chunks[id] as Array).size()
	check(bodies > bus.parts.size() and bodies < 1200, "the building stands as %d frozen chunks" % bodies)
	for i in 4:
		for k in 3:
			bus.request_charge("col_0_%d_%d" % [i, k], 0.0 if (i == 1 or i == 2) else 0.5)
	check(bus.charges.size() == 12, "twelve charges placed")
	check(bus.predicted().size() == bus.parts.size() - 24, "the preview says everything above will fall")
	var snap := bus.get_net_snapshot()
	bus.request_fire()
	check(bus.is_fired() and bus.countdown() > 2.0, "fire starts a countdown")
	bus.request_charge("col_1_0_0", 1.0)
	check(not bus.charges.has("col_1_0_0"), "no new charges once fired")

	var until := Time.get_ticks_msec() + 45000
	while bus.result.is_empty() and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	check(bus.blasted_ids.size() == 12, "every charge went off: %d" % bus.blasted_ids.size())
	check(bus.released_ids.size() == bus.parts.size() - 12, "everything above the pads came loose: %d" % bus.released_ids.size())
	var r := bus.result
	check(not r.is_empty(), "the host scored it once it settled")
	check(float(r.get("down", 0.0)) > 0.95, "the building is down: %s" % str(r))
	check(float(r.get("contained", 0.0)) > 0.6, "most debris landed in the drop zone: %s" % str(r))
	var low := 1e9
	for id: String in bus.released_ids:
		for body: RigidBody3D in view._chunks.get(id, []):
			low = minf(low, body.global_position.y)
	check(low < 3.0, "the debris is on the ground")

	bus.request_reset()
	await frames(2)
	# The wrecking ball hangs on its cable, and a hard knock breaks a standing part loose.
	for i in 90:
		await get_tree().physics_frame
	var hang: float = view._tip.global_position.distance_to(view._ball.global_position)
	check(hang <= view._cable + 0.25 and hang > view._cable - 1.0, "the ball hangs on its cable: %.2f of %.2f m" % [hang, view._cable])
	net_claim_test(bus, view)
	var col: RigidBody3D = view._chunks["col_2_1_1"][0]
	view._hit(col, 1e7)
	await frames(2)
	check(bus.released_ids.has("col_2_1_1") and bus.released_ids.has("bx_2_0_1"),
			"a hard knock breaks a column loose and what it held falls")
	bus.request_reset()
	await frames(2)
	check(not bus.is_fired() and bus.released_ids.is_empty() and bus.charges.size() == 12,
			"reset stands the building up again and keeps the plan")
	bus.apply_net_snapshot({})
	check(not bus.is_active(), "an empty snapshot clears the site")
	bus.apply_net_snapshot(snap)
	check(bus.is_active() and bus.charges.size() == 12 and not bus.is_fired(), "a join snapshot brings the plan")
	view.queue_free()
	await frames(2)
	bus.apply_net_snapshot({})


func net_claim_test(bus: DemolitionBus, view: Node3D) -> void:
	check(not view.driving_crane(), "nobody drives the crane at first")
	bus.net.claim(view.CRANE_ID)
	check(view.driving_crane(), "Tab takes the crane")
	bus.net.release(view.CRANE_ID)
	check(not view.driving_crane(), "and Tab again lets it go")
