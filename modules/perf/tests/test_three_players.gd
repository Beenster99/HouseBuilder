extends ModuleTest
## Three players, three processes: this test hosts, and starts two headless copies of the
## game that join over ENet on localhost (the benchmark's --perf-client mode). On an
## office-sized building everyone edits at once while the host sends sync checks; every
## peer must match the host at every check, and checks must reach them quickly. Then one
## player's copy is changed behind the session's back, and the check must catch it.
##   tools/run_tests.sh perf

const PORT := 24583
const EDIT_FOR := 6.0
const CHECK_EVERY := 1.0

var pids: Array[int] = []


func run_tests() -> void:
	var net := Modules.bus("multiplayer") as MultiplayerBus
	var perf := Modules.bus("perf") as PerfBus
	var building := Modules.bus("building") as BuildingBus
	# The live structure check would still be testing the office when this process quits,
	# which crashes the engine (see test_budgets.gd); the sync check doesn't need it.
	for id in ["structure", "services"]:
		var bus := Modules.bus(id)
		if bus and bus.has_method("watch"):
			bus.call("watch", null)
	check(net.host(PORT) == OK, "host starts")
	perf.report_checks = true
	var steady := _spawn("")
	var diverging := _spawn("diverge")
	check(steady > 0 and diverging > 0, "two player processes start")
	check(await _until(func() -> bool: return net.peers().size() == 3, 40.0), "two players join: %d in the session" % net.peers().size())
	if net.peers().size() < 3:
		await _cleanup(net)
		return

	building.sync.load_design(ScaleBuildings.data("office"))
	var edits := 0
	var t := 0.0
	var next_check := CHECK_EVERY
	while t < EDIT_FOR:
		await get_tree().create_timer(0.2).timeout
		t += 0.2
		edits += 1
		building.sync.edit(BuildingCommands.place_part("desk_office", 0, {"at": [2.0 + (edits % 9), 0.0, 2.0]}))
		if edits % 3 == 0:
			building.sync.undo()
		if t >= next_check:
			next_check += CHECK_EVERY
			perf.send_digest()
	perf.send_digest()
	check(await _until(func() -> bool: return _matched_peers(perf, 3) >= 1 and not perf.desyncs.is_empty(), 15.0),
			"checks come back: %s, desyncs %s" % [perf.peer_checks, perf.desyncs])

	# The steady player matched the host at every check, quickly.
	var by_peer := {}
	for d: Dictionary in perf.desyncs:
		by_peer[int(d.get("peer", 0))] = str(d.get("section", ""))
	var steady_peer := 0
	for peer: int in perf.peer_checks:
		if not by_peer.has(peer):
			steady_peer = peer
	check(steady_peer != 0, "one player stayed in sync throughout: checks %s, desyncs %s" % [perf.peer_checks, by_peer])
	if steady_peer != 0:
		var c: Dictionary = perf.peer_checks[steady_peer]
		check(int(c.ok) >= int(EDIT_FOR / CHECK_EVERY), "it matched every check: %d" % c.ok)
		# Most checks, not every one: the check right after loading a whole office can wait
		# on that load, and with the full suite sharing the CPU one can stall (seen 0.5 s).
		var lags: Array = (c.lags as Array).duplicate()
		lags.sort()
		var p80: float = lags[int(lags.size() * 0.8)] if not lags.is_empty() else INF
		print("sync check lag: 80th percentile %.3f s, worst %.3f s" % [p80, c.worst_lag])
		check(p80 < PerfBudget.MAX_EVENT_LAG, "checks reach it within %.2f s: 80th percentile %.3f s, worst %.3f s" % [PerfBudget.MAX_EVENT_LAG, p80, c.worst_lag])
	# The player whose copy was changed behind the session's back is caught, in the building.
	check(by_peer.size() == 1 and by_peer.values()[0] == "building", "the diverged player is caught, in the building: %s" % by_peer)
	await _cleanup(net)


func _matched_peers(perf: PerfBus, at_least: int) -> int:
	var n := 0
	for peer: int in perf.peer_checks:
		if int(perf.peer_checks[peer].ok) >= at_least:
			n += 1
	return n


func _spawn(option: String) -> int:
	var arg := "--perf-client=%d" % PORT
	if option != "":
		arg += "," + option
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", arg])
	if pid > 0:
		pids.append(pid)
	return pid


func _cleanup(net: MultiplayerBus) -> void:
	net.leave()
	await get_tree().create_timer(1.0).timeout
	for pid in pids:
		if OS.is_process_running(pid):
			OS.kill(pid)


func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while not cond.call():
		if t > timeout:
			return false
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	return true
