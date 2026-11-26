extends ModuleTest
## Same result everywhere: the solver ignores the order a building was put together in,
## reports survive saving and the wire unchanged, and through the bus the host solves while
## every client (and a late joiner) ends up with the host's report.
##   tools/run_tests.sh structure

const Samples := preload("res://modules/structure/tests/samples.gd")


## A stand-in session that carries events and snapshots through var_to_bytes, as ENet does.
class Wire:
	var peers: Array = []  # Array of FakeNet; peers[0] is the host
	var rejected: Array[String] = []


class FakeNet:
	var wire: Wire
	var peer_id := 1
	var events := {}
	var snapshots := {}

	func register_event(event_name: String, apply: Callable, validate := Callable()) -> void:
		events[event_name] = {"apply": apply, "validate": validate}

	func unregister_event(event_name: String) -> void:
		events.erase(event_name)

	func register_snapshot_provider(section: String, provider: Object) -> void:
		snapshots[section] = provider

	func unregister_snapshot_provider(section: String) -> void:
		snapshots.erase(section)

	func request(event_name: String, payload: Dictionary = {}) -> void:
		var host: FakeNet = wire.peers[0]
		var sent: Dictionary = bytes_to_var(var_to_bytes(payload))
		var entry: Dictionary = host.events[event_name]
		var out: Variant = sent
		if entry.validate.is_valid():
			out = entry.validate.call(peer_id, sent)
		if out is String:
			wire.rejected.append(out)
			return
		var bytes := var_to_bytes(out)
		for p: FakeNet in wire.peers:
			p.events[event_name].apply.call(bytes_to_var(bytes))

	func join(host: FakeNet) -> void:
		for section: String in host.snapshots:
			var data: Dictionary = bytes_to_var(var_to_bytes(host.snapshots[section].get_net_snapshot()))
			snapshots[section].apply_net_snapshot(data)


func run_tests() -> void:
	_order_and_repeats()
	_saving_and_wire()
	await _solo_bus()
	_host_and_clients()


func _order_and_repeats() -> void:
	var digests := {}
	for seed in [0, 1, 2, 3, 7, 42]:
		var rep := StructureSolver.stress_test(Samples.house(true, seed))
		digests[rep.digest()] = true
		rep = StructureSolver.stress_test(Samples.house(false, seed))
		digests["unbraced " + rep.digest()] = true
	check(digests.size() == 2, "build order never changes the result: %d digests" % digests.size())
	var g := Samples.house()
	var first := StructureSolver.stress_test(g).to_dict()
	for i in 5:
		check(StructureSolver.stress_test(g).to_dict() == first, "run %d identical" % i)


func _saving_and_wire() -> void:
	var g := Samples.house()
	var want := StructureSolver.stress_test(g).digest()
	var copy := StructureGraph.from_dict(g.to_dict())
	check(StructureSolver.stress_test(copy).digest() == want, "graph to_dict / from_dict keeps the result")
	var parsed: Variant = JSON.parse_string(JSON.stringify(g.to_dict(), "", true, true))
	var from_json := StructureGraph.from_dict(parsed)
	check(StructureSolver.stress_test(from_json).digest() == want, "graph through JSON keeps the result")
	var rep := StructureSolver.stress_test(g)
	var back := StructureReport.from_dict(bytes_to_var(var_to_bytes(rep.to_dict())))
	check(back.digest() == want, "report through the wire keeps its digest")
	check(back.summary == rep.summary and back.passed() == rep.passed(), "summary survives")
	check(back.envelope("f0") == rep.envelope("f0"), "utilisation survives exactly")
	var sc := StructureScenario.from_dict(StructureScenario.storm().to_dict())
	check(sc.wind_kpa == 1.5 and sc.directions.size() == 4, "scenario round trip")


func _solo_bus() -> void:
	var bus := Modules.bus("structure") as StructureBus
	check(bus != null, "structure bus loaded")
	if bus == null:
		return
	var net := Modules.bus("multiplayer") as MultiplayerBus
	var rejected: Array[String] = []
	net.request_rejected.connect(func(_n: String, why: String) -> void: rejected.append(why))
	var reports: Array[StructureReport] = []
	bus.report_changed.connect(func(r: StructureReport) -> void: reports.append(r))
	bus.run_stress_test()
	check(rejected == ["Nothing to test yet"], "an empty building, no test: %s" % str(rejected))
	var house := Samples.house()
	bus.set_graph_provider(func() -> StructureGraph: return house)
	bus.run_stress_test()
	check(reports.size() == 1 and bus.last_report() == reports[0], "solo run reports at once")
	check(bus.last_report().digest() == StructureSolver.stress_test(house).digest(), "same as solving directly")
	bus.run_stress_test(PackedStringArray(["storm"]))
	check(bus.last_report().results.size() == 1 and bus.last_report().results[0].scenario_id == "storm", "one scenario on request")
	bus.run_stress_test(PackedStringArray(["volcano"]))
	check(rejected.size() == 2 and rejected[1].contains("volcano"), "unknown scenario refused: %s" % str(rejected))
	bus.set_graph_provider(Callable())
	bus.run_stress_test()
	check(rejected.size() == 3 and rejected[2] == "Nothing to test yet", "no provider, no test")


func _host_and_clients() -> void:
	var wire := Wire.new()
	var buses: Array[StructureBus] = []
	for i in 3:
		var net := FakeNet.new()
		net.wire = wire
		net.peer_id = i + 1
		wire.peers.append(net)
		var bus := StructureBus.new()
		add_child(bus)
		bus.attach(net)
		buses.append(bus)
	var house := Samples.house()
	buses[0].set_graph_provider(func() -> StructureGraph: return house)
	# A client's own provider is never used: only the host solves.
	buses[1].set_graph_provider(func() -> StructureGraph: return Samples.house(false))
	buses[2].run_stress_test()
	var want := StructureSolver.stress_test(house).digest()
	for i in 3:
		check(buses[i].last_report() != null and buses[i].last_report().digest() == want,
				"peer %d has the host's report" % (i + 1))
	check(buses[1].last_report().to_dict() == buses[0].last_report().to_dict(), "client and host reports equal")
	# A late joiner gets the last report in the join snapshot.
	var late_net := FakeNet.new()
	late_net.wire = wire
	late_net.peer_id = 4
	var late := StructureBus.new()
	add_child(late)
	late.attach(late_net)
	late_net.join(wire.peers[0])
	check(late.last_report() != null and late.last_report().digest() == want, "late joiner has the report")
	# The host's building changes: everyone moves to the new result together.
	house.add_node("p", Vector3(20, 3, 0))
	house.add_node("q", Vector3(25, 3, 0))
	house.add_member("float", "p", "q", StructureGraph.BEAM, "steel.ub_203x133x25")
	buses[1].run_stress_test()
	for i in 3:
		check(not buses[i].last_report().passed() and buses[i].last_report().first_failure().id == "float",
				"peer %d sees the loose beam fail" % (i + 1))
	for b in buses:
		b.queue_free()
	late.queue_free()
	wire.peers.clear()  # FakeNet and Wire point at each other
