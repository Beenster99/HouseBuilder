extends ModuleTest
## Through the bus the host routes and every client (and a late joiner) ends up with the
## host's report; placed sources are shared, checked, saved and loaded.
##   tools/run_tests.sh services

const Samples := preload("res://modules/services/tests/samples.gd")


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

	func host_emit(event_name: String, payload: Dictionary = {}) -> void:
		var bytes := var_to_bytes(payload)
		for p: FakeNet in wire.peers:
			p.events[event_name].apply.call(bytes_to_var(bytes))

	func is_host() -> bool:
		return wire.peers[0] == self

	func join(host: FakeNet) -> void:
		for section: String in host.snapshots:
			var data: Dictionary = bytes_to_var(var_to_bytes(host.snapshots[section].get_net_snapshot()))
			snapshots[section].apply_net_snapshot(data)


func run_tests() -> void:
	await _solo_bus()
	await _host_and_clients()
	_save_and_load()


func _solo_bus() -> void:
	var bus := Modules.bus("services") as ServicesBus
	check(bus != null, "services bus loaded")
	if bus == null:
		return
	var net := Modules.bus("multiplayer") as MultiplayerBus
	var rejected: Array[String] = []
	net.request_rejected.connect(func(_n: String, why: String) -> void: rejected.append(why))
	var reports: Array[ServicesReport] = []
	bus.report_changed.connect(func(r: ServicesReport) -> void: reports.append(r))
	bus.run_consultant()
	check(rejected.size() == 1 and rejected[0].begins_with("Nothing to route"), "the shared building is empty: %s" % str(rejected))
	var house := Samples.house()
	bus.set_model_provider(func() -> BuildingModel: return house)
	bus.run_consultant()
	check(reports.is_empty() and bus.is_routing(), "routing runs in the background, not in this frame")
	await _until(func() -> bool: return reports.size() == 1)
	check(reports.size() == 1 and bus.last_report() == reports[0], "solo run reports when done")
	check(bus.last_report().revision == house.revision, "report carries the building revision")
	check(bus.last_report().digest() == ServicesConsultant.route(house).digest(), "same as routing directly")
	bus.place_source("gas", 0, Vector2.ZERO)
	check(rejected.size() == 2 and rejected[1].contains("gas"), "unknown service refused: %s" % str(rejected))
	bus.place_source("power", 5, Vector2.ZERO)
	check(rejected.size() == 3 and rejected[2].contains("level"), "missing level refused: %s" % str(rejected))
	bus.place_source("power", 0, Vector2(1, 0.5))
	check(bus.sources.has("power"), "source placed")
	bus.clear_source("power")
	check(bus.sources.is_empty(), "source cleared")
	# The consultant designs: its ops go to the building as one edit, then it routes again.
	var bare := Samples.house(false)
	bus.set_model_provider(func() -> BuildingModel: return bare)
	var edits: Array = []
	bus.set_edit_handler(func(op: Dictionary) -> void:
		edits.append(op)
		bare.apply(op))
	var said: Array = []
	bus.design_done.connect(func(notes: PackedStringArray) -> void: said.append(notes))
	var before := reports.size()
	bus.design_services()
	check(edits.is_empty(), "the design is worked out off the main thread")
	await _until(func() -> bool: return said.size() == 1 and reports.size() > before and not bus.is_routing())
	check(edits.size() == 1 and edits[0].op == "batch", "one batch edit, one undo step")
	check(bus.last_report().passed(), "after the design every room is served: %s" % bus.last_report().summary)
	check(said.size() == 1 and "\n".join(said[0]).contains("soil stack"), "it says what it did")
	bus.design_services()
	await _until(func() -> bool: return said.size() == 2)
	check(edits.size() == 1, "nothing more to add, no edit")
	var reviews: Array = []
	bus.review_done.connect(func(r: Dictionary) -> void: reviews.append(r))
	bus.review_feasibility()
	await _until(func() -> bool: return reviews.size() == 1)
	check(reviews.size() == 1 and reviews[0].areas.services.ok, "feasibility arrives from the worker")
	bus.set_edit_handler(Callable())
	# Design room hooks: tints and the panel.
	var tints := bus.overlay_tints(bare)
	check(tints.get(Samples.room_of_type(bare, "bathroom")) == Color(0.3, 0.8, 0.45), "served rooms tinted green")
	var panel: Control = bus.make_panel()
	add_child(panel)
	check(panel.get_child_count() > 3, "panel builds")
	panel.queue_free()
	bus.set_model_provider(Callable())


func _host_and_clients() -> void:
	var wire := Wire.new()
	var buses: Array[ServicesBus] = []
	for i in 3:
		var net := FakeNet.new()
		net.wire = wire
		net.peer_id = i + 1
		wire.peers.append(net)
		var bus := ServicesBus.new()
		add_child(bus)
		bus.attach(net)
		buses.append(bus)
	var house := Samples.house()
	buses[0].set_model_provider(func() -> BuildingModel: return house)
	# A client's own building is never used: only the host routes.
	buses[1].set_model_provider(func() -> BuildingModel: return Samples.house(false))
	buses[2].run_consultant()
	await _until(func() -> bool: return buses[2].last_report() != null)
	var want := ServicesConsultant.route(house).digest()
	for i in 3:
		check(buses[i].last_report() != null and buses[i].last_report().digest() == want,
				"peer %d has the host's report" % (i + 1))
	check(buses[1].last_report().to_dict() == buses[0].last_report().to_dict(), "client and host reports equal")
	# A client pins the consumer unit; everyone sees it and the next report uses it.
	buses[1].place_source("power", 0, Vector2(1, 0.5))
	for i in 3:
		check(buses[i].sources.get("power", {}).get("level", -1) == 0, "peer %d has the placed source" % (i + 1))
	var first := buses[2].last_report()
	buses[2].run_consultant()
	await _until(func() -> bool: return buses[2].last_report() != first)
	for i in 3:
		check(str(buses[i].last_report().system("power").source.how) == "placed", "peer %d: report uses it" % (i + 1))
	# A late joiner gets the sources and the last report in the join snapshot.
	var late_net := FakeNet.new()
	late_net.wire = wire
	late_net.peer_id = 4
	var late := ServicesBus.new()
	add_child(late)
	late.attach(late_net)
	late_net.join(wire.peers[0])
	check(late.last_report() != null and late.last_report().digest() == buses[0].last_report().digest(), "late joiner has the report")
	check(late.sources == buses[0].sources, "late joiner has the sources")
	for b in buses:
		b.queue_free()
	late.queue_free()
	wire.peers.clear()


func _save_and_load() -> void:
	var bus := ServicesBus.new()
	bus.sources = {"waste": {"level": 0, "at": [3.0, 7.0]}}
	var data: Dictionary = JSON.parse_string(JSON.stringify(bus.save_data()))
	var other := ServicesBus.new()
	other.load_data(data, ServicesBus.SAVE_VERSION)
	check(other.sources == bus.sources, "placed sources survive a save: %s" % str(other.sources))
	other.load_data({"sources": {"gas": {"at": [0, 0]}}}, ServicesBus.SAVE_VERSION)
	check(other.sources.is_empty(), "unknown services dropped on load")
	other.reset_data()
	check(other.sources.is_empty() and other.last_report() == null, "reset clears")
	bus.free()
	other.free()


func _until(cond: Callable, seconds := 10.0) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < seconds * 1000.0:
		await get_tree().process_frame
