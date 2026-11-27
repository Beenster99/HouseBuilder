extends ModuleTest
## The work site around a timelapse: what is on site at each stage, scaffold up with the
## walls and down at the end, crew at work, deliveries through the gate, cleared at the end.
##   tools/run_tests.sh timelapse

const DemoHouse := preload("res://modules/timelapse/internal/demo_house.gd")


func run_tests() -> void:
	var bus := Modules.bus("timelapse") as TimelapseBus
	bus.start_timelapse(DemoHouse.parts(), "Demo house", false)
	bus.request_play(false)
	var view: Node3D = load("res://modules/timelapse/internal/timelapse_view.tscn").instantiate()
	add_child(view)
	await frames(2)
	var site: Node3D = view.site
	check(site != null and site.visible, "the view has a work site")
	var stages: Dictionary = bus.schedule.stages
	var mid := func(s: String) -> float: return (float(stages[s][0]) + float(stages[s][1])) / 2.0

	bus.request_seek(mid.call("site"))
	await frames(3)
	var st: Dictionary = site.state()
	check(st.compound, "the compound is set up from the start")
	check("excavator" in st.plant and "tipper" in st.plant, "a digger and a tipper for the groundworks: %s" % [st.plant])
	check(st.scaffold == 0, "no scaffold before the walls")
	check(st.workers >= 4, "a crew on site: %d" % st.workers)

	bus.request_seek(mid.call("foundation"))
	await frames(3)
	st = site.state()
	check("mixer" in st.plant and "pump" in st.plant, "a concrete mixer and pump for the foundations: %s" % [st.plant])
	check(not ("excavator" in st.plant), "the digger has gone")

	bus.request_seek(mid.call("envelope"))
	await frames(3)
	st = site.state()
	check(st.scaffold > 0, "scaffold up while the walls go up: %d bays" % st.scaffold)
	check("telehandler" in st.plant, "a telehandler moving pallets")
	# The crew walk about in real time.
	var before: Array[Vector3] = []
	for w: Dictionary in site._workers:
		before.append((w.node as Node3D).position)
	await get_tree().create_timer(4.0).timeout
	var moved := 0
	for i in site._workers.size():
		if (site._workers[i].node as Node3D).visible and (site._workers[i].node as Node3D).position.distance_to(before[i]) > 0.5:
			moved += 1
	check(moved >= 2, "the crew move about: %d walked" % moved)

	# A delivery: the lorry comes in through the gate.
	site._next_delivery = bus.day()
	await frames(2)
	check(str(site.state().lorry) == "in", "a lorry comes in with a delivery")

	bus.request_seek(bus.total_days())
	await frames(3)
	st = site.state()
	check(not st.compound and st.workers == 0 and st.scaffold == 0 and (st.plant as PackedStringArray).is_empty(),
			"at handover the site is cleared: %s" % st)
	view.queue_free()
	await frames(1)
