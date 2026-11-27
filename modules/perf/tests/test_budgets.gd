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
## measure id -> [ms (or bytes/s) when listed, owner module, what is slow]. 2026-11-27.
const KNOWN := {
	"quantities.terminal": [60.0, "building", "the first full costing (about 50 ms); after it an edit recosts only what it touched (about 19 ms)"],
	"stress.office": [21000.0, "structure", "the load-path solver is far from linear in members (the live check runs it after every edit)"],
	"stress.terminal": [120000.0, "structure", "the load-path solver"],
	"route.terminal": [800.0, "services", "routing 384 rooms (runs on a worker thread since 2026-11-27, so no frame waits on it)"],
	"design_open.terminal": [25500.0, "design", "one MeshInstance3D and BoxMesh per box; all built in one frame"],
	"design_edit.office": [1050.0, "design", "an edit recosts the whole building and redraws every slab"],
	"design_edit.terminal": [16000.0, "design", "an edit recosts the whole building and redraws every slab"],
	"demolition_chunks.terminal": [10559.0, "demolition", "up to 24 chunks per part, each a RigidBody3D"],
	"demolition_physics.office": [110.0, "demolition", "2,600 chunks awake at once after the ground-floor columns go"],
	"demolition_hitch.office": [110.0, "demolition", "the physics frames of the collapse"],
	"demolition_awake.office": [2650.0, "demolition", "every chunk of every released part wakes together"],
	"demolition_bytes.office": [4000000.0, "demolition", "every awake chunk is a mover streamed 20 times a second"],
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
	if _should_measure("stress.%s" % size):
		_timed("stress.%s" % size, 1, func() -> void: StructureBuilding.stress_test(m), PerfBudget.HEAVY_MS)
	if _should_measure("route.%s" % size):
		_timed("route.%s" % size, 1, func() -> void: ServicesConsultant.route(m), PerfBudget.HEAVY_MS)
	var chunks := 0
	for p: Dictionary in BuildingParts.from_model(m):
		chunks += DemolitionRules.chunks(p).size()
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
	# The engine's time monitors refresh about once a second: let the opening frame age out.
	await get_tree().create_timer(1.2).timeout
	# Tests share the CPU with other test processes: take the best of a few windows.
	var idle := INF
	for attempt in 3:
		var samples: Array[float] = []
		var t1 := Time.get_ticks_usec()
		while _ms(t1) < 1200.0:
			await get_tree().process_frame
			samples.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		idle = minf(idle, _pct(samples, 0.5))
		if idle <= PerfBudget.SCRIPT_FRAME_MS:
			break
	_judge("design_idle.%s" % size, idle, PerfBudget.SCRIPT_FRAME_MS)
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
	_judge("demolition_physics.%s" % size, _pct(physics, 0.95), PerfBudget.SCRIPT_FRAME_MS)
	_judge("demolition_hitch.%s" % size, _pct(physics, 1.0), PerfBudget.HITCH_MS)
	_judge("demolition_awake.%s" % size, awake, PerfBudget.MAX_AWAKE, "bodies")
	_judge("demolition_bytes.%s" % size, awake * _mover_bytes() * 20.0, PerfBudget.MOVER_BYTES_PER_PEER, "B/s")
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


## The size on the wire of one mover sample in a batch, as the session sends them.
static func _mover_bytes() -> float:
	var batch := {}
	for i in 100:
		batch["demo:p%d#%d" % [1000 + i, i % 24]] = Transform3D(Basis.from_euler(Vector3(0.1, i, 0.3)), Vector3(i, 2, 3))
	return var_to_bytes(batch).size() / 100.0


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


func _judge(id: String, value: float, budget: float, unit: String = "ms") -> void:
	var line := "  %-28s %10.1f %s  (budget %.0f)" % [id, value, unit, budget]
	if value <= budget:
		results.append(line + "  ok")
		check(true, id)
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
