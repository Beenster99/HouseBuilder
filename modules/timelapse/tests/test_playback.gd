extends ModuleTest
## The shared clock: start, play, pause, speed, seek, refusals, join snapshots, and the view.
##   tools/run_tests.sh timelapse

const DemoHouse := preload("res://modules/timelapse/internal/demo_house.gd")

var rejected: Array[String] = []


func run_tests() -> void:
	var bus := Modules.bus("timelapse") as TimelapseBus
	check(bus != null, "timelapse bus loaded")
	if bus == null:
		return
	check(not bus.is_active(), "nothing scheduled at first")
	bus.net.request_rejected.connect(func(n, why): rejected.append("%s: %s" % [n, why]))
	bus.start_timelapse([], "Nothing", false)
	check(not bus.is_active() and rejected.size() == 1, "an empty building is refused")

	var started: Array[String] = []
	bus.started.connect(func(t): started.append(t))
	bus.start_timelapse(DemoHouse.parts(), "Demo house", false)
	check(bus.is_active() and started == ["Demo house"], "the host schedules and starts it")
	check(bus.is_playing() and is_equal_approx(bus.speed(), TimelapseBus.DEFAULT_SPEED), "plays at the default speed")
	await _wait(0.5)
	var d := bus.day()
	check(d > 0.6 and d < 1.6, "the clock runs at 2 days a second: %.2f" % d)

	bus.request_play(false)
	var held := bus.day()
	await _wait(0.3)
	check(not bus.is_playing() and is_equal_approx(bus.day(), held), "pause holds the day")
	bus.request_seek(20.0)
	check(is_equal_approx(bus.day(), 20.0), "seek moves the shared day")
	bus.request_seek(99999.0)
	check(is_equal_approx(bus.day(), bus.total_days()), "seek stops at the end")
	bus.request_speed(7.0)
	check(rejected.size() == 2 and is_equal_approx(bus.speed(), TimelapseBus.DEFAULT_SPEED), "an unknown speed is refused")
	bus.request_speed(30.0)
	check(is_equal_approx(bus.speed(), 30.0), "speed changes")
	bus.request_play(true)
	check(bus.is_playing() and bus.day() < 1.0, "play from the end starts again")

	var snap := bus.get_net_snapshot()
	bus.apply_net_snapshot({})
	check(not bus.is_active(), "an empty snapshot clears it")
	bus.apply_net_snapshot(snap)
	check(bus.is_active() and bus.title == "Demo house" and bus.tasks().size() == DemoHouse.parts().size() + 3,
			"a join snapshot brings the schedule and clock")

	# The view: every part has a piece, the HUD reads the shared clock.
	bus.request_seek(bus.total_days() / 2.0)
	bus.request_play(false)
	var view: Node3D = load("res://modules/timelapse/internal/timelapse_view.tscn").instantiate()
	add_child(view)
	await frames(3)
	check(view._pieces.size() == bus.tasks().size(), "a piece for every task")
	var shown := 0
	for id: String in view._pieces:
		if (view._pieces[id].pivot as Node3D).visible:
			shown += 1
	check(shown > 5 and shown < bus.tasks().size(), "halfway, some parts are built: %d" % shown)
	# Building parts fade in at full size; site work spreads across the plot.
	var full_size := true
	for id: String in view._pieces:
		var piece: Dictionary = view._pieces[id]
		if not (piece.pivot as Node3D).visible or not view.fades(piece.task):
			continue
		full_size = full_size and (piece.pivot as Node3D).scale.is_equal_approx(Vector3.ONE)
	check(full_size, "building parts appear at full size")
	var mid := 0.0
	for t: Dictionary in bus.tasks():
		if view.fades(t):
			mid = (float(t.start) + float(t.end)) / 2.0
			break
	bus.request_seek(mid)
	await frames(2)
	var fading := 0
	for id: String in view._pieces:
		var a := (view._pieces[id].mesh as MeshInstance3D).transparency
		if view.fades(view._pieces[id].task) and a > 0.05 and a < 0.95:
			fading += 1
	check(fading >= 1, "a part being built is part way faded in: %d" % fading)
	var date := view.find_child("Date", true, false) as Label
	check(date != null and date.text.contains("day"), "HUD shows the date and day: %s" % (date.text if date else ""))
	var money := view.find_child("Money", true, false) as Label
	check(money != null and money.text.begins_with("£"), "HUD shows money spent")
	bus.request_seek(bus.total_days())
	await frames(2)
	shown = 0
	for id: String in view._pieces:
		if (view._pieces[id].pivot as Node3D).visible:
			shown += 1
	check(shown == bus.tasks().size(), "at the end everything is built")
	var solid := true
	for id: String in view._pieces:
		solid = solid and is_zero_approx((view._pieces[id].mesh as MeshInstance3D).transparency)
	check(solid, "at the end every part is solid")
	# Esc goes back to the design office (the game's start scene) instead of the pause menu.
	# With no start scene it has nowhere to go, so this test stays put and checks the key.
	var start := Menu.start()
	Menu._start = {}
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	view.get_viewport().push_input(esc)
	await frames(1)
	var ui := Modules.bus("ui")
	var paused: bool = ui != null and ui.get("pause") != null and bool(ui.get("pause").get("is_open"))
	check(not paused, "Esc in the timelapse doesn't open the pause menu")
	check(view.find_child("Back", true, false) is Button, "a Back button beside the speeds")
	Menu._start = start
	view.queue_free()
	await frames(1)


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
