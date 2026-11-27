extends ModuleTest
## The 60 fps budgets, measured headless on generated buildings at house, office and airport
## terminal size (ScaleBuildings): edits, costing, the structural stress test, M&E routing,
## the design room (opening it, idling, an edit), the demolition collapse (physics time,
## bodies awake) and the network a collapse streams. Budgets are in PerfBudget.
##
## A ratchet: what is over budget today is listed in KNOWN with its owner and the time it
## took when listed. Those print as OVER BUDGET and don't fail, unless they get more than
## twice as slow; anything else over budget fails. When an owner speeds something up,
## lower or delete its KNOWN entry so it can't slip back. Known items slower than
## SKIP_OVER_MS aren't measured on every run (they'd make everyone's tests crawl):
##   PERF_FULL=1 tools/run_tests.sh perf        measures everything
##   tools/run_tests.sh perf                     the usual run
## Headless numbers come from this machine's CPU with no rendering; the benchmark
## (godot --path . -- --bench) measures real frames on the player's PC.

const SKIP_OVER_MS := 3000.0
## The debris stream's cost (MultiplayerBus.register_mover_group): bytes per body, per second.
const GROUP_BYTES := 12.0
const GROUP_RATE := 12.0
## measure id -> [ms (or bytes/s) when listed, owner module, what is slow]. 2026-11-27.
const KNOWN := {
	"quantities.terminal": [60.0, "building", "the first full costing (about 50 ms); after it an edit recosts only what it touched (about 19 ms)"],
	"stress.office": [450.0, "structure", "a cold stress test sits near the 500 ms button budget (the live check is off the main thread and reuses unchanged floors)"],
	"stress.terminal": [900.0, "structure", "a cold stress test of 4,900 members (off the main thread in game; edits re-check in ~0.6 s)"],
	"route.office": [700.0, "services", "routing six systems (lighting and heating added 2026-11-27) on a worker thread, so no frame waits on it"],
	"route.terminal": [1350.0, "services", "routing 384 rooms, six systems, on a worker thread, so no frame waits on it"],
	"demolition_physics.office": [40.0, "demolition", "about 800 parts fall at once, each one body until it breaks up (was 110 ms; 22-40 ms alone, 60 with the suite running)"],
	"demolition_hitch.office": [60.0, "demolition", "the worst physics frame of the collapse (40 ms alone, 60 with the suite running)"],
}

var full := OS.get_environment("PERF_FULL") == "1"
var building: BuildingBus
var results: Array[String] = []


func run_tests() -> void:
	building = Modules.bus("building") as BuildingBus
	# The live structure and services checks run on worker threads after every edit; on these
	# buildings a check outlives the test, and quitting mid-check crashes the engine. Their
	# costs are measured directly below (stress.*, route.*), so they're paused here.
	var live := _pause_live_checks()
	for size in ["house", "office", "terminal"]:
		_model_budgets(size)
	for size in ["house", "office", "terminal"]:
		await _design_room(size)
	await _demolition("office")
	print("\n".join(results))
	building.reset_data()
	_resume_live_checks(live)


func _model_budgets(size: String) -> void:
	var m := ScaleBuildings.make(size)
	_timed("edit.%s" % size, 3, func() -> void:
		var r := m.apply(BuildingCommands.place_part("column", 0, {"at": [1.0, 0.0, 1.0]}, "steel"))
		m.apply(BuildingCommands.delete([str(r.do.entry.id)])), PerfBudget.CLICK_MS / 10.0)
	_timed("save.%s" % size, 2, func() -> void: var _d := m.to_data(), PerfBudget.CLICK_MS * 2.0)
	_timed("quantities.%s" % size, 1, func() -> void: BuildingQuantities.totals(m), PerfBudget.CLICK_MS)
	# The per-edit path: costs are kept on the model, so after an edit only what it touched is
	# recosted (the design room's cost panel does this on every edit).
	BuildingQuantities.totals(m)
	_timed("quantities_edit.%s" % size, 1, func() -> void:
		m.apply(BuildingCommands.place_part("column", 0, {"at": [2.0, 0.0, 2.0]}, "steel"))
		BuildingQuantities.totals(m), PerfBudget.CLICK_MS)
	if _should_measure("stress.%s" % size):
		_timed("stress.%s" % size, 1, func() -> void: StructureBuilding.stress_test(m), PerfBudget.HEAVY_MS)
	if _should_measure("route.%s" % size):
		_timed("route.%s" % size, 1, func() -> void: ServicesConsultant.route(m), PerfBudget.HEAVY_MS)
	var chunks := 0
	var parts := BuildingParts.from_model(m)
	var size_m := DemolitionRules.chunk_size(parts)  # as the demolition view picks it
	for p: Dictionary in parts:
		chunks += DemolitionRules.chunks(p, size_m).size()
	_judge("demolition_chunks.%s" % size, chunks, PerfBudget.MAX_BODIES, "bodies")


func _design_room(size: String) -> void:
	if not _should_measure("design_open.%s" % size):
		return
	building.model.load_data(ScaleBuildings.data(size))
	var t0 := Time.get_ticks_usec()
	var room: Node = (load(Router.scene_path(DesignBus.ROOM_SCENE)) as PackedScene).instantiate()
	add_child(room)
	await frames(2)
	_judge("design_open.%s" % size, _ms(t0), PerfBudget.OPEN_MS)
	# Idle: the 95th percentile of real frame intervals once the room has settled. (The
	# engine's TIME_PROCESS monitor lags and lumps in background work, so it isn't used.)
	# Tests share the CPU with other test processes: take the best of a few windows.
	await get_tree().create_timer(1.0).timeout
	var idle := INF
	for attempt in 3:
		var samples: Array[float] = []
		var t1 := Time.get_ticks_usec()
		var last := t1
		while _ms(t1) < 1200.0:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			samples.append((now - last) / 1000.0)
			last = now
		idle = minf(idle, _pct(samples, 0.95))
		if idle <= PerfBudget.FRAME_MS:
			break
	_judge("design_idle.%s" % size, idle, PerfBudget.FRAME_MS)
	if _should_measure("design_edit.%s" % size):
		t0 = Time.get_ticks_usec()
		building.sync.edit(BuildingCommands.place_part("column", 0, {"at": [1.0, 0.0, 1.0]}, "steel"))
		await frames(2)
		_judge("design_edit.%s" % size, _ms(t0), PerfBudget.CLICK_MS)
	room.queue_free()
	await frames(2)


func _demolition(size: String) -> void:
	building.model.load_data(ScaleBuildings.data(size))
	var demo := Modules.bus("demolition") as DemolitionBus
	demo.start_from_model(building.model, {"open": false})
	await frames(2)
	var view: Node = (load(Router.scene_path(DemolitionBus.VIEW_SCENE)) as PackedScene).instantiate()
	add_child(view)
	await frames(5)
	var n := 0
	for p: Dictionary in demo.parts:
		if str(p.get("family", "")) == "column" and int(p.get("level", 0)) == 0 and n < DemolitionBus.MAX_CHARGES:
			demo.request_charge(str(p.id), 0.0)
			n += 1
	demo.request_fire()
	await get_tree().create_timer(DemolitionBus.COUNTDOWN + 0.2).timeout
	var physics: Array[float] = []
	var awake := 0
	var t0 := Time.get_ticks_usec()
	while _ms(t0) < 5000.0:
		await get_tree().physics_frame
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		awake = maxi(awake, _awake(view))
	# Physics frame times swing 3x with the rest of the suite sharing the CPU, so they only
	# fail with PERF_FULL=1 (run alone); bodies awake below is the steady stand-in for them.
	_judge("demolition_physics.%s" % size, _pct(physics, 0.95), PerfBudget.SCRIPT_FRAME_MS, "ms", full)
	_judge("demolition_hitch.%s" % size, _pct(physics, 1.0), PerfBudget.HITCH_MS, "ms", full)
	_judge("demolition_awake.%s" % size, awake, PerfBudget.MAX_AWAKE, "bodies")
	# Debris streams as a mover group: GROUP_BYTES per body that moved, GROUP_RATE times a
	# second (MultiplayerBus.register_mover_group). Every awake body is counted as moving.
	_judge("demolition_bytes.%s" % size, awake * GROUP_BYTES * GROUP_RATE, PerfBudget.MOVER_BYTES_PER_PEER, "B/s")
	view.queue_free()
	demo.request_reset()
	await frames(2)


## Bodies falling now (dynamic and not asleep) under the view.
static func _awake(root: Node) -> int:
	var n := 0
	for b: Node in root.find_children("*", "RigidBody3D", true, false):
		var body := b as RigidBody3D
		if not body.freeze and not body.sleeping:
			n += 1
	return n


static func _pct(v: Array[float], q: float) -> float:
	if v.is_empty():
		return 0.0
	var s := v.duplicate()
	s.sort()
	return s[clampi(ceili(q * s.size()) - 1, 0, s.size() - 1)]


## Stops the structure and services modules watching the shared building; returns what to
## hand back to _resume_live_checks().
func _pause_live_checks() -> Array:
	var paused: Array = []
	for id in ["structure", "services"]:
		var bus := Modules.bus(id)
		if bus and bus.has_method("watch"):
			bus.call("watch", null)
			paused.append(bus)
	return paused


func _resume_live_checks(paused: Array) -> void:
	for bus: Node in paused:
		bus.call("watch", building.model)


func _should_measure(id: String) -> bool:
	if full or not KNOWN.has(id) or float(KNOWN[id][0]) <= SKIP_OVER_MS:
		return true
	results.append("  %-28s KNOWN SLOW (%s ms when listed; %s owns it), not measured; PERF_FULL=1 to measure" % [id, KNOWN[id][0], KNOWN[id][1]])
	return false


## strict false: report only (for timings too noisy to fail on while other tests run).
func _judge(id: String, value: float, budget: float, unit: String = "ms", strict := true) -> void:
	var line := "  %-28s %10.1f %s  (budget %.0f)" % [id, value, unit, budget]
	if value <= budget:
		results.append(line + "  ok")
		check(true, id)
		return
	if not strict:
		results.append(line + "  OVER BUDGET (reported only; PERF_FULL=1 fails on it)")
		return
	if KNOWN.has(id):
		var was := float(KNOWN[id][0])
		results.append(line + "  OVER BUDGET, known: %s (%s)" % [KNOWN[id][2], KNOWN[id][1]])
		check(value <= was * 2.0, "%s got more than twice as slow: %.0f %s, listed at %.0f" % [id, value, unit, was])
		return
	results.append(line + "  OVER BUDGET")
	check(false, "%s is over budget: %.1f %s, budget %.0f" % [id, value, unit, budget])


## Times f (best of runs) and judges it. Tests share the CPU with other test processes, so
## something over budget that isn't KNOWN gets two more tries before it fails.
func _timed(id: String, runs: int, f: Callable, budget: float) -> void:
	var ms := _best_of(runs, f)
	if ms > budget and not KNOWN.has(id):
		ms = minf(ms, _best_of(2, f))
	_judge(id, ms, budget)


func _best_of(n: int, f: Callable) -> float:
	var best := INF
	for i in n:
		var t0 := Time.get_ticks_usec()
		f.call()
		best = minf(best, _ms(t0))
	return best


static func _ms(t0: int) -> float:
	return (Time.get_ticks_usec() - t0) / 1000.0
