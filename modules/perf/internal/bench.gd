extends Node
## The benchmark: plays fixed scenes with the real renderer and judges every one against
## the 60 fps target (PerfBudget.TARGET), with two more players joined so the host carries
## a full crew's network and sync load.
##
##   godot --path . -- --bench                    every scenario, 3 players
##   godot --path . -- --bench=design_office      one scenario (comma-separate for more)
##   godot --path . -- --bench --solo             no extra players
##   godot --path . -- --bench --look=realistic   in the realistic look (default: clean)
##
## The extra players are headless copies of the game on this PC (--perf-client=<port>) that
## join, make an edit every second like a busy crew, and quit when the host leaves. Each
## scenario warms up, records, and adds a row to the report: frame stats, draw calls,
## nodes, bodies, desyncs. The report is printed, saved to user://perf/ (the path is
## printed) and the process exits 1 if any scenario misses the target or desyncs.

const PORT := 24581
const WARMUP := 2.0
const RECORD := 8.0
const CLIENT_EDIT_EVERY := 1.0
const SCENARIOS := ["design_house", "design_office", "design_terminal", "demolition_office"]

var perf: Node
var net: MultiplayerBus
var building: BuildingBus
var rows: Array[Dictionary] = []
var _clients: Array[int] = []
## Whether the extra players run on cores of their own (else they share the host's).
var clients_pinned := false
var _edits := 0


func start(args: PackedStringArray) -> void:
	perf = get_parent()
	net = Modules.bus("multiplayer") as MultiplayerBus
	building = Modules.bus("building") as BuildingBus
	for a in args:
		if a.begins_with("--perf-client="):
			var opts := a.get_slice("=", 1).split(",")
			_run_client(int(opts[0]), "diverge" in opts)
			return
	_run_host(args)


# --- Host -------------------------------------------------------------------------------

func _run_host(args: PackedStringArray) -> void:
	var wanted: Array = SCENARIOS.duplicate()
	var solo := false
	var look := "clean"
	for a in args:
		if a.begins_with("--bench="):
			wanted = Array(a.get_slice("=", 1).split(",", false))
		elif a == "--solo":
			solo = true
		elif a.begins_with("--look="):
			look = a.get_slice("=", 1)
	_set_look(look)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var players := 1
	if not solo:
		if net.host(PORT) != OK:
			_log("could not host on port %d; running solo" % PORT)
		else:
			perf.set("report_checks", true)
			_spawn_clients(MultiplayerBus.MAX_CREW - 1)
			var t := 0.0
			while net.peers().size() < MultiplayerBus.MAX_CREW and t < 30.0:
				await get_tree().create_timer(0.25).timeout
				t += 0.25
			players = net.peers().size()
			_log("%d players in the session" % players)
	for id: String in wanted:
		if not has_method("_scenario_" + id.get_slice("_", 0)):
			_log("unknown scenario %s" % id)
			continue
		await call("_scenario_" + id.get_slice("_", 0), id.get_slice("_", 1))
		rows[-1]["scenario"] = id
		rows[-1]["players"] = players
		rows[-1]["look"] = look
		_log(_row_text(rows[-1]))
	_finish(players)


func _scenario_design(size_name: String) -> void:
	building.sync.load_design(ScaleBuildings.data(size_name))
	Router.goto(DesignBus.ROOM_SCENE)
	await _record()


func _scenario_demolition(size_name: String) -> void:
	building.sync.load_design(ScaleBuildings.data(size_name))
	# As a crew would: the design was open a while, so its live checks have finished.
	await get_tree().create_timer(1.0).timeout
	var structure := Modules.bus("structure")
	var t0 := Time.get_ticks_msec()
	while structure and structure.has_method("is_checking") and structure.call("is_checking") and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().create_timer(0.1).timeout
	var demo := Modules.bus("demolition") as DemolitionBus
	demo.start_from_model(building.model)
	var t := 0.0
	while Router.current_id != DemolitionBus.VIEW_SCENE and t < 10.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	await get_tree().create_timer(1.0).timeout
	# Charges on every ground-floor column, all at once: the most bodies awake together.
	var n := 0
	for p: Dictionary in demo.parts:
		if str(p.get("family", "")) == "column" and int(p.get("level", 0)) == 0 and n < DemolitionBus.MAX_CHARGES:
			demo.request_charge(str(p.id), 0.0)
			n += 1
	await get_tree().create_timer(0.5).timeout
	demo.request_fire()
	await get_tree().create_timer(DemolitionBus.COUNTDOWN).timeout
	await _record(12.0)


func _record(seconds: float = RECORD) -> void:
	await get_tree().create_timer(WARMUP).timeout
	var fs := FrameStats.new(100000)
	var peak := {"draw_calls": 0, "objects": 0, "primitives": 0, "nodes": 0, "bodies_awake": 0, "movers": 0,
			"sent_bps": 0}
	var next_count := 0.0
	var desyncs_before: int = (perf.get("desyncs") as Array).size()
	var t0 := Time.get_ticks_usec()
	var last := t0
	while (Time.get_ticks_usec() - t0) / 1e6 < seconds:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		fs.add((now - last) / 1000.0)
		last = now
		var s: Dictionary = perf.call("snapshot")
		# Jolt doesn't fill the engine's active-body monitor: count them, twice a second.
		if (now - t0) / 1e6 >= next_count:
			next_count += 0.5
			s["bodies_awake"] = _awake(get_tree().current_scene)
			last = Time.get_ticks_usec()  # the count's own time isn't the game's
		for k: String in peak:
			peak[k] = maxi(int(peak[k]), int(s.get(k, 0)))
	if net.is_online():
		perf.call("send_digest")
		await get_tree().create_timer(1.0).timeout
	var row := fs.summary()
	row["verdict"] = fs.meets()
	row.merge(peak)
	row["desyncs"] = (perf.get("desyncs") as Array).size() - desyncs_before
	row["parts"] = building.model.parts.size()
	rows.append(row)


static func _awake(root: Node) -> int:
	if root == null:
		return 0
	var n := 0
	for b: Node in root.find_children("*", "RigidBody3D", true, false):
		if not (b as RigidBody3D).freeze and not (b as RigidBody3D).sleeping:
			n += 1
	return n


func _finish(players: int) -> void:
	var failed := 0
	for r in rows:
		if str(r.verdict) != "" or int(r.desyncs) > 0:
			failed += 1
	var report := {
		"when": Time.get_datetime_string_from_system(),
		"godot": Engine.get_version_info().string,
		"gpu": RenderingServer.get_video_adapter_name(),
		"cpu": OS.get_processor_name(),
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"players": players,
		"extra_players_on_own_cores": clients_pinned,
		"target_fps": PerfBudget.TARGET_FPS,
		"rows": rows,
		"passed": failed == 0,
	}
	DirAccess.make_dir_recursive_absolute("user://perf")
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "user://perf/bench_%s.json" % stamp
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	_log("%s on %s, %d players%s" % [report.gpu, report.cpu, players,
			"" if players == 1 or clients_pinned else " (the extra players share this PC's CPU; --solo for the host alone)"])
	_log("%d of %d scenarios meet %d fps. Report: %s" % [rows.size() - failed, rows.size(), PerfBudget.TARGET_FPS,
			ProjectSettings.globalize_path(path)])
	if net.is_online():
		net.leave()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if failed == 0 else 1)


## The host on the first half of the cores, the extra players on the rest (Linux).
func _pin_self(cores: int) -> void:
	OS.execute("taskset", ["-p", "-c", "0-%d" % (cores / 2 - 1), str(OS.get_process_id())])


func _spawn_clients(n: int) -> void:
	var exe := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")
	var args := ["--headless", "--path", project, "--", "--perf-client=%d" % PORT]
	# Real players each have their own PC; here the extra players share the host's CPU and
	# steal its time (20 hitches a collapse on a 4-core PC, none with them on other cores).
	# On Linux they go on the last cores; elsewhere --solo gives the host's own numbers.
	var cores := OS.get_processor_count()
	var pin := OS.get_name() == "Linux" and cores >= 4 and OS.execute("sh", ["-c", "command -v taskset"]) == 0
	for i in n:
		var pid := -1
		if pin:
			pid = OS.create_process("taskset", ["-c", "%d-%d" % [cores / 2, cores - 1], exe] + args)
		else:
			pid = OS.create_process(exe, args)
		if pid > 0:
			_clients.append(pid)
	clients_pinned = pin
	if pin:
		_pin_self(cores)


static func _row_text(r: Dictionary) -> String:
	return "%-18s %3.0f fps  mean %5.1f  p95 %5.1f  p99 %5.1f  worst %6.1f ms  hitches %d  draws %d  nodes %d  bodies %d  up %.0f KB/s  desyncs %d  %s" % [
			r.scenario, r.fps, r.mean_ms, r.p95_ms, r.p99_ms, r.worst_ms, r.hitches, r.draw_calls, r.nodes,
			r.bodies_awake, float(r.sent_bps) / 1024.0, r.desyncs, "PASS" if str(r.verdict) == "" and int(r.desyncs) == 0 else "FAIL: " + str(r.verdict)]


## The look for the run (not saved): "clean" (the white model) or "realistic".
func _set_look(look: String) -> void:
	GraphicsOptions.set_value("art_style", ArtStyle.REALISTIC if look == "realistic" else ArtStyle.MODEL)
	Graphics.apply_all()


func _log(line: String) -> void:
	print("[bench] ", line)


# --- Client -----------------------------------------------------------------------------

## A headless player: joins the bench host on this PC, edits like a busy crew member (not
## during a demolition, where players can't edit),
## reports each matched sync check, and quits when the session ends. With "diverge"
## (--perf-client=<port>,diverge, for the desync test) it changes its own copy of the
## building behind the session's back after the first matched check once a design loads.
func _run_client(port: int, diverge := false) -> void:
	perf.set("report_checks", true)
	net.session_ended.connect(func(_reason: String) -> void: get_tree().quit(0))
	if net.join("127.0.0.1", port) != OK:
		get_tree().quit(1)
		return
	var t := 0.0
	while not net.is_online() and t < 20.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	if not net.is_online():
		get_tree().quit(1)
		return
	var me := net.local_peer_id()
	if diverge:
		await building.model.loaded
		var seen := int(perf.get("checks_ok"))
		while int(perf.get("checks_ok")) <= seen:
			await get_tree().create_timer(0.1).timeout
		# Design metadata that no later edit overwrites (a stray part would be, by id).
		building.model.apply(BuildingCommands.set_design_meta({"perf_diverged": true}))
	var demo := Modules.bus("demolition") as DemolitionBus
	while true:
		await get_tree().create_timer(CLIENT_EDIT_EVERY).timeout
		# Nobody can edit the building from the demolition site, so neither do these players.
		if demo and demo.is_active():
			continue
		_edits += 1
		# A desk somewhere on the ground floor, then away again: edits without growing forever.
		var at := [1.0 + float(me % 7), 0.0, 1.0 + float(_edits % 5)]
		building.sync.edit(BuildingCommands.place_part("desk_office", 0, {"at": at}))
		if _edits % 2 == 0:
			building.sync.undo()
