extends ModuleTest
## FrameStats' numbers and verdicts, the overlay's text, and the bus's toggles.
##   tools/run_tests.sh perf


func run_tests() -> void:
	_steady_60()
	_slow_and_hitchy()
	_window_rolls()
	await _bus()


func _steady_60() -> void:
	var fs := FrameStats.new(120)
	for i in 120:
		fs.add(16.0 + (i % 3) * 0.3)
	var s := fs.summary()
	check(int(s.frames) == 120, "120 frames recorded")
	check(absf(float(s.fps) - 61.4) < 1.0, "about 61 fps: %.2f" % s.fps)
	check(float(s.p50_ms) >= 16.0 and float(s.p99_ms) <= 16.61, "percentiles: %s" % s)
	check(fs.meets() == "", "steady 16 ms frames meet the target: %s" % fs.meets())


func _slow_and_hitchy() -> void:
	var slow := FrameStats.new(100)
	for i in 100:
		slow.add(20.0)
	check(slow.meets().begins_with("mean frame"), "50 fps fails on the mean: %s" % slow.meets())
	var hitchy := FrameStats.new(300)
	for i in 300:
		hitchy.add(80.0 if i % 60 == 0 else 14.0)
	var s := hitchy.summary()
	check(int(s.hitches) == 5, "five hitches: %d" % s.hitches)
	check(float(s.worst_ms) == 80.0, "worst frame is the hitch")
	check(hitchy.meets().contains("hitches"), "a good mean with stutters still fails: %s" % hitchy.meets())
	var jittery := FrameStats.new(100)
	for i in 100:
		jittery.add(10.0 if i % 4 else 30.0)
	check(jittery.meets() != "", "a quarter of frames at 30 ms fails: %s" % jittery.meets())
	check(FrameStats.new().meets() == "no frames recorded", "an empty window doesn't pass")


func _window_rolls() -> void:
	var fs := FrameStats.new(10)
	for i in 25:
		fs.add(float(i))
	check(fs.size() == 10, "window keeps its capacity")
	check(fs.values() == PackedFloat32Array([15, 16, 17, 18, 19, 20, 21, 22, 23, 24]), "oldest frames roll out: %s" % fs.values())
	check(fs.percentile(1.0) == 24.0 and fs.percentile(0.1) == 15.0, "percentiles over the window")


func _bus() -> void:
	var perf := Modules.bus("perf") as PerfBus
	check(perf != null, "perf module loads")
	if perf == null:
		return
	await frames(10)
	check(perf.frames.size() >= 8, "the bus records every frame: %d" % perf.frames.size())
	var s := perf.snapshot()
	for k in ["fps", "p95_ms", "draw_calls", "nodes", "players", "desyncs", "verdict", "sent_bps", "movers"]:
		check(s.has(k), "snapshot has %s" % k)
	check(Keys.has(PerfBus.TOGGLE), "F3 toggle registered")
	perf.set_overlay(true)
	await frames(2)
	check(perf.overlay_on(), "overlay opens")
	var text: String = load("res://modules/perf/internal/perf_overlay.gd").text_for(s)
	check(text.contains("fps") and text.contains("draw calls") and text.contains("offline"), "overlay text: %s" % text)
	perf.set_overlay(false)
	check(not perf.overlay_on(), "overlay closes")
