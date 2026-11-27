class_name PerfBus
extends Node
## The performance module's bus (Modules.bus("perf")): the in-game profiler and the live
## desync check.
##
## Profiler: every frame's time goes into `frames` (a FrameStats window). F3 (Keys
## "perf.toggle_overlay") shows the overlay: fps, frame percentiles against the 60 fps
## target, CPU script and physics time, draw calls, nodes, the session's players, round
## trip, upload and download, movers streamed, the view delay, sync status, and every
## Performance custom monitor. To show a
## number of your own without depending on this module, add an engine custom monitor:
##   Performance.add_custom_monitor("fred/structure/solve_ms", func() -> float: return _last_ms)
## (they show in the editor's Debugger > Monitors too). The editor's Profiler and Visual
## Profiler tabs give per-function and per-render-pass detail.
##
## Desync check: while online the host sends a fingerprint of the shared state every
## DIGEST_EVERY seconds as an ordinary event, so each peer checks it at the same point in
## the event order as the host made it. A mismatch is logged, shown on the overlay, reported
## to the host and emitted as desync_detected. Built in: the building model and the
## demolition plan. Any module can add a section (duck-typed, no depends_on needed):
##   var perf := Modules.bus("perf")
##   if perf: perf.register_digest("services", func() -> Variant: return report_data)
##
## Benchmark: godot --path . -- --bench  (see internal/bench.gd).

signal desync_detected(section: String, info: Dictionary)
signal overlay_toggled(on: bool)

const OVERLAY_FLAG := "perf.overlay"
const DESYNC_FLAG := "perf.desync_check"
const TOGGLE := "perf.toggle_overlay"
const DIGEST_EVENT := "perf.digest"
const REPORT_EVENT := "perf.desync"
const DIGEST_EVERY := 3.0
const STATS_EVERY := 1.0
const SETTINGS := "perf"
const MONITORS: Array[StringName] = [&"fred/perf/frame_p95_ms", &"fred/perf/desyncs"]
const Overlay := preload("res://modules/perf/internal/perf_overlay.gd")
const Bench := preload("res://modules/perf/internal/bench.gd")

var frames := FrameStats.new(600)
## Every desync seen this session: {section, at, host, mine, peer}.
var desyncs: Array[Dictionary] = []
## Digest checks that matched, and when the last one ran (Time.get_ticks_msec()).
var checks_ok := 0
var last_check_msec := -1
## Peers also report matched checks to the host (the benchmark and tests turn this on).
var report_checks := false
## Host: peer id -> {ok: matched checks reported, worst_lag and lags (the last 100): s from
## the host sending a check to that peer applying it}.
var peer_checks: Dictionary = {}
var net: MultiplayerBus
var _digests: Dictionary = {}  # section -> Callable() -> Variant
var _net_cache: Dictionary = {}
var _net_stats_msec := 0
var _out_of_sync: Dictionary = {}  # section -> true while this peer differs from the host
var _last_usec := -1
var _since_digest := 0.0
var _overlay: CanvasLayer


func register_module() -> void:
	net = Modules.bus("multiplayer") as MultiplayerBus
	Settings.register(SETTINGS, {"overlay": false})
	Keys.register(TOGGLE, "Performance overlay", KEY_F3, "Debug")
	net.register_event(DIGEST_EVENT, _apply_digest, _host_only)
	net.register_event(REPORT_EVENT, _apply_report, _validate_report)
	register_digest("building", _building_digest)
	register_digest("demolition", _demolition_digest)
	Performance.add_custom_monitor(MONITORS[0], func() -> float: return frames.percentile(0.95))
	Performance.add_custom_monitor(MONITORS[1], func() -> int: return desyncs.size())
	net.session_ended.connect(func(_reason: String) -> void:
		_since_digest = 0.0
		_out_of_sync.clear()
		peer_checks.clear())
	if Flags.is_on(OVERLAY_FLAG) and bool(Settings.get_value(SETTINGS, "overlay")):
		set_overlay(true)
	_launch.call_deferred(OS.get_cmdline_user_args())


func unregister_module() -> void:
	set_overlay(false)
	Keys.unregister(TOGGLE)
	_remove_monitors()
	if net:
		net.unregister_event(DIGEST_EVENT)
		net.unregister_event(REPORT_EVENT)


func _exit_tree() -> void:
	_remove_monitors()


func _remove_monitors() -> void:
	for m in MONITORS:
		if Performance.has_custom_monitor(m):
			Performance.remove_custom_monitor(m)


func _launch(args: PackedStringArray) -> void:
	var wanted := false
	for arg in args:
		wanted = wanted or arg == "--bench" or arg.begins_with("--bench=") or arg.begins_with("--perf-client=")
	if not wanted:
		return
	# After the splash has loaded everything and warmed the shaders, as a player would.
	if not Modules.boot_done:
		await Modules.booted
	for arg in args:
		if arg == "--bench" or arg.begins_with("--bench=") or arg.begins_with("--perf-client="):
			var b: Node = Bench.new()
			b.name = "Bench"
			add_child(b)
			b.call("start", args)
			return


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_usec >= 0:
		frames.add((now - _last_usec) / 1000.0)
	_last_usec = now
	if Flags.is_on(DESYNC_FLAG) and net.is_online() and net.is_host() and net.peers().size() > 1:
		_since_digest += _delta
		if _since_digest >= DIGEST_EVERY:
			_since_digest = 0.0
			send_digest()


func _unhandled_input(event: InputEvent) -> void:
	if Flags.is_on(OVERLAY_FLAG) and InputMap.has_action(TOGGLE) and event.is_action_pressed(TOGGLE) and not Keys.typing():
		set_overlay(_overlay == null)
		Settings.set_value(SETTINGS, "overlay", _overlay != null)
		get_viewport().set_input_as_handled()


# --- Profiler ---------------------------------------------------------------------------

func set_overlay(on: bool) -> void:
	if on == (_overlay != null):
		return
	if on:
		_overlay = Overlay.new()
		_overlay.call("bind", self)
		add_child(_overlay)
	else:
		_overlay.queue_free()
		_overlay = null
	overlay_toggled.emit(on)


func overlay_on() -> bool:
	return _overlay != null


## The numbers the overlay shows, as data (the benchmark writes these to its report).
func snapshot() -> Dictionary:
	var s := frames.summary()
	s["verdict"] = frames.meets()
	s["script_ms"] = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	s["physics_ms"] = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	s["draw_calls"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	s["objects"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	s["primitives"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	s["nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	s["memory_mb"] = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	s["video_mb"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	s["players"] = net.peers().size() if net.is_online() else 1
	s["host"] = net.is_host()
	s["online"] = net.is_online()
	s["rtt_ms"] = net.round_trip() * 1000.0
	var ns: Dictionary = _net_stats()
	s["sent_bps"] = float(ns.get("sent_bytes_per_s", 0.0))
	s["recv_bps"] = float(ns.get("recv_bytes_per_s", 0.0))
	s["movers"] = int(ns.get("movers", 0))
	s["view_delay_ms"] = float(ns.get("view_delay", 0.0)) * 1000.0
	s["desyncs"] = desyncs.size()
	s["in_sync"] = _out_of_sync.is_empty()
	s["sync_checks"] = checks_ok
	return s


## The session's traffic, cached for STATS_EVERY s (the bus averages its byte rates over
## the time between calls, so calling it every frame would give noisy numbers).
func _net_stats() -> Dictionary:
	var now := Time.get_ticks_msec()
	if net.has_method("net_stats") and (now - _net_stats_msec > STATS_EVERY * 1000.0 or _net_cache.is_empty()):
		_net_stats_msec = now
		_net_cache = net.call("net_stats")
	return _net_cache


## The window's verdict against PerfBudget.TARGET: "" when it meets 60 fps.
func verdict() -> String:
	return frames.meets()


# --- Desync check -----------------------------------------------------------------------

## section's fingerprint is hash_of(provider.call()): plain data that every peer must agree on.
func register_digest(section: String, provider: Callable) -> void:
	_digests[section] = provider


func unregister_digest(section: String) -> void:
	_digests.erase(section)


func digest_sections() -> PackedStringArray:
	var out := PackedStringArray(_digests.keys())
	out.sort()
	return out


## section -> fingerprint of this peer's state now.
func digests() -> Dictionary:
	var out := {}
	for section in digest_sections():
		var c: Callable = _digests[section]
		if c.is_valid():
			out[section] = hash_of(c.call())
	return out


## Host: broadcast the fingerprints now (also every DIGEST_EVERY seconds while online).
func send_digest() -> void:
	if net.is_host():
		net.host_emit(DIGEST_EVENT, {"digests": digests(), "t": net.server_time()})


## A fingerprint of plain data. Dictionary keys are sorted down to CANONICAL_DEPTH (the
## sections and their tables of entries keyed by id), so peers that built the same tables
## in a different order still agree. Below that the engine's hash() is used: fast, and
## order-sensitive, but entries are built from the same ops on every peer.
static func hash_of(v: Variant) -> int:
	return hash(_canonical(v, CANONICAL_DEPTH))


const CANONICAL_DEPTH := 2


static func _canonical(v: Variant, depth: int) -> Variant:
	if depth <= 0:
		return hash(v)
	if v is Dictionary:
		var d: Dictionary = v
		var out := PackedInt64Array()
		var names := PackedStringArray(d.keys())
		names.sort()
		if names.size() == d.size() and (d.is_empty() or d.has(names[0])):
			for k in names:
				out.append(hash(k))
				out.append(_canonical(d[k], depth - 1))
		else:
			var keys: Array = d.keys()
			keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
			for k: Variant in keys:
				out.append(hash(str(k)))
				out.append(_canonical(d[k], depth - 1))
		return hash(out)
	if v is Array:
		var out := PackedInt64Array()
		for x: Variant in v:
			out.append(_canonical(x, depth - 1))
		return hash(out)
	return hash(v)


func _host_only(_sender: int, _payload: Dictionary) -> Variant:
	return "host only"


func _apply_digest(payload: Dictionary) -> void:
	last_check_msec = Time.get_ticks_msec()
	if net.is_host():
		checks_ok += 1
		return
	var lag := net.server_time() - float(payload.get("t", net.server_time()))
	var theirs: Dictionary = payload.get("digests", {})
	var mine := digests()
	var bad := false
	for section: String in theirs:
		if not mine.has(section) or int(mine[section]) == int(theirs[section]):
			_out_of_sync.erase(section)
			continue
		bad = true
		# Report a section once when it goes out of sync, not at every check after.
		if not _out_of_sync.has(section):
			_out_of_sync[section] = true
			var info := {"section": section, "at": net.server_time(), "host": theirs[section], "mine": mine[section],
					"peer": net.local_peer_id()}
			desyncs.append(info)
			push_warning("perf: desync in %s (host %d, here %d)" % [section, theirs[section], mine[section]])
			desync_detected.emit(section, info)
			net.request(REPORT_EVENT, info)
	if not bad:
		checks_ok += 1
		if report_checks:
			net.request(REPORT_EVENT, {"ok": true, "lag": lag})


func _validate_report(sender: int, payload: Dictionary) -> Variant:
	var p := payload.duplicate()
	p["peer"] = sender
	return p


## Everyone hears about a desync anywhere, so the host's overlay and log show it too. The
## host also tallies matched checks from peers that report them (report_checks).
func _apply_report(payload: Dictionary) -> void:
	var peer := int(payload.get("peer", 0))
	if bool(payload.get("ok", false)):
		if net.is_host():
			var c: Dictionary = peer_checks.get(peer, {"ok": 0, "worst_lag": 0.0, "lags": []})
			c.ok = int(c.ok) + 1
			c.worst_lag = maxf(float(c.worst_lag), float(payload.get("lag", 0.0)))
			(c.lags as Array).append(float(payload.get("lag", 0.0)))
			if (c.lags as Array).size() > 100:
				(c.lags as Array).pop_front()
			peer_checks[peer] = c
		return
	if peer == net.local_peer_id():
		return
	desyncs.append(payload)
	push_warning("perf: %s reports a desync in %s" % [net.player_name(int(payload.get("peer", 0))), payload.get("section", "?")])
	desync_detected.emit(str(payload.get("section", "")), payload)


func _building_digest() -> Variant:
	var b := Modules.bus("building") as BuildingBus
	if b == null:
		return null
	var m := b.model
	return {"name": m.name, "meta": m.meta, "levels": m.levels, "parts": m.parts, "rooms": m.rooms,
			"connections": m.connections}


func _demolition_digest() -> Variant:
	var d := Modules.bus("demolition") as DemolitionBus
	if d == null:
		return null
	return {"title": d.title, "parts": d.parts.size(), "charges": d.charges, "fired": d.fire_at,
			"blasted": d.blasted_ids.keys(), "released": d.released_ids.keys()}
