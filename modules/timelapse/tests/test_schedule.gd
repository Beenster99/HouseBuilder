extends ModuleTest
## The schedule generator: build logic, crews, determinism, loops, money and dates.
##   tools/run_tests.sh timelapse

const DemoHouse := preload("res://modules/timelapse/internal/demo_house.gd")


func run_tests() -> void:
	var parts := DemoHouse.parts()
	var s := TimelapseSchedule.build(parts)
	var tasks: Array = s.tasks
	var by_id := {}
	for t: Dictionary in tasks:
		by_id[t.id] = t
	check(tasks.size() == parts.size() + 3, "every part plus three site tasks scheduled: %d" % tasks.size())
	check(s.days > 20.0 and s.days < 400.0, "a plausible build time: %.1f days" % s.days)
	check(s.levels == 2, "two storeys found: %d" % s.levels)

	var ok := true
	for p: Dictionary in parts:
		for sup: String in p.supported_by:
			if by_id[p.id].start < by_id[sup].end - 0.0001:
				ok = false
				print("  %s starts before its support %s ends" % [p.id, sup])
	check(ok, "nothing starts before what it rests on is finished")

	var frame_end := 0.0
	var roof_end := 0.0
	var first_found := INF
	var last_end := 0.0
	for t: Dictionary in tasks:
		if t.stage == "frame":
			frame_end = maxf(frame_end, t.end)
		if t.stage == "roof":
			roof_end = maxf(roof_end, t.end)
		if t.stage == "foundation":
			first_found = minf(first_found, t.start)
		if t.id != "site:landscape":
			last_end = maxf(last_end, t.end)
	check(by_id.roof.start >= frame_end - 0.0001, "the roof waits for the whole frame")
	check(by_id.fitout_L0_kitchen.start >= roof_end - 0.0001, "fit-out waits until it's weather-tight")
	check(first_found >= by_id["site:dig"].end - 0.0001, "foundations wait for the excavation")
	check(by_id["site:landscape"].start >= last_end - 0.0001, "landscaping comes last")
	check(by_id.wall_L1_z0.start >= by_id.slab_L1.end - 0.0001, "upper walls wait for their floor")

	var again := TimelapseSchedule.build(parts)
	check(str(again) == str(s), "the same design always gives the same schedule")
	var more := TimelapseSchedule.build(parts, {"crews": 8})
	var one := TimelapseSchedule.build(parts, {"crews": 1})
	check(more.days <= s.days and s.days < one.days, "more crews build faster: 1=%.0f 3=%.0f 8=%.0f" % [one.days, s.days, more.days])
	check(is_equal_approx(one.cost, s.cost), "crews change time, not cost")

	check(TimelapseSchedule.progress({"start": 2.0, "end": 4.0}, 3.0) == 0.5, "progress halfway")
	check(TimelapseSchedule.spent(s, 0.0) == 0.0 and is_equal_approx(TimelapseSchedule.spent(s, s.days), s.cost),
			"money spent runs from 0 to the total")
	check(TimelapseSchedule.date_on(s, 0.0) == "2027-03-01" and TimelapseSchedule.date_on(s, 31.5) == "2027-04-01",
			"calendar dates from the start date")
	check(TimelapseSchedule.active_stages(s, 0.5) == PackedStringArray(["site"]), "day 0 is site work")

	var loop := [
		{"id": "a", "kind": "column", "aabb": AABB(Vector3.ZERO, Vector3(0.3, 3, 0.3)), "supported_by": ["b"]},
		{"id": "b", "kind": "column", "aabb": AABB(Vector3(2, 0, 0), Vector3(0.3, 3, 0.3)), "supported_by": ["a"]},
		{"id": "c", "kind": "mystery", "aabb": AABB(Vector3(4, 0, 0), Vector3(1, 1, 1)), "supported_by": ["nowhere"]},
	]
	var ls := TimelapseSchedule.build(loop)
	check(ls.tasks.size() == 6, "a support loop and unknown ids still schedule every part")

	var big: Array[Dictionary] = []
	for i in 2000:
		big.append({"id": "p%d" % i, "kind": "beam" if i % 2 else "column",
				"aabb": AABB(Vector3(i % 40, (i / 400) * 3.0, (i / 40) % 10), Vector3(1, 3, 0.3)),
				"supported_by": ["p%d" % (i - 400)] if i >= 400 else []})
	var t0 := Time.get_ticks_msec()
	var bs := TimelapseSchedule.build(big)
	var ms := Time.get_ticks_msec() - t0
	check(bs.tasks.size() == 2003 and ms < 4000, "2000 parts schedule quickly: %d ms" % ms)
