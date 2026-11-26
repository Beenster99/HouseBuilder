class_name StructureBus
extends Node
## Structure module bus (Modules.bus("structure")): the structural graph solver and stress
## tests. Only the host solves; everyone receives the same report.
##
##   var structure := Modules.bus("structure") as StructureBus
##   structure.set_graph_provider(func() -> StructureGraph: return my_graph)   # on the host
##   structure.report_changed.connect(_recolour)
##   structure.run_stress_test()                     # any player; the host runs it
##
## The request goes to the host, which builds the graph from its provider, runs every
## scenario asked for (all three standard ones by default) and broadcasts the report as the
## event itself, so clients never solve and never drift. Late joiners get the last report
## in the join snapshot. For a quick local answer (previews, tests) call StructureSolver
## directly.

## A stress test finished (or arrived from the host, or came with the join snapshot).
signal report_changed(report: StructureReport)

const EVENT_RUN := "structure.run"
## The stress test button and the utilisation overlay in the design room (not built yet).
const STRESS_TEST_FLAG := "structure.stress_test"

var _net: Object
var _provider := Callable()
var _report: StructureReport


func register_module() -> void:
	attach(Modules.bus("multiplayer"))
	# By default the host tests the shared building.
	var building := Modules.bus("building") as BuildingBus
	if building:
		set_graph_provider(func() -> StructureGraph: return StructureBuilding.graph(building.model))


func unregister_module() -> void:
	if _net:
		_net.unregister_event(EVENT_RUN)
		_net.unregister_snapshot_provider("structure")
	_net = null


## Hooks the bus to a session (the multiplayer bus, or a stand-in with the same calls).
func attach(net: Object) -> void:
	_net = net
	if _net == null:
		return
	_net.register_event(EVENT_RUN, _apply_run, _validate_run)
	_net.register_snapshot_provider("structure", self)


## Where the host gets the building to test: a Callable returning a StructureGraph (or
## null when there is nothing to test). Clients may set one too; only the host's is used.
## Set at start to the building module's shared model.
func set_graph_provider(provider: Callable) -> void:
	_provider = provider


## Asks the host to stress test the current building. scenario_ids defaults to
## normal use, storm and quake. The report arrives through report_changed; a refusal
## ("Nothing to test yet") through the multiplayer bus's request_rejected.
func run_stress_test(scenario_ids: PackedStringArray = PackedStringArray()) -> void:
	_net.request(EVENT_RUN, {"scenarios": Array(scenario_ids)})


## The last stress test, or null before the first one.
func last_report() -> StructureReport:
	return _report


func _validate_run(_sender: int, payload: Dictionary) -> Variant:
	if not _provider.is_valid():
		return "Nothing to test yet"
	var graph = _provider.call()
	if not graph is StructureGraph or (graph.members.is_empty() and graph.plates.is_empty()):
		return "Nothing to test yet"
	var scenarios: Array[StructureScenario] = []
	for sid in payload.get("scenarios", []):
		var sc := StructureScenario.by_id(str(sid))
		if sc == null:
			return "Unknown stress test: %s" % sid
		scenarios.append(sc)
	var report := StructureSolver.stress_test(graph, scenarios)
	var data := report.to_dict()
	return {"scenarios": payload.get("scenarios", []), "report": data, "digest": report.digest()}


func _apply_run(payload: Dictionary) -> void:
	var report := StructureReport.from_dict(payload.get("report", {}))
	if payload.has("digest") and report.digest() != str(payload.digest):
		push_warning("structure: stress test report changed on the way (%s)" % payload.digest)
	_report = report
	report_changed.emit(report)


func get_net_snapshot() -> Dictionary:
	return {"report": _report.to_dict()} if _report else {}


func apply_net_snapshot(data: Dictionary) -> void:
	if data.has("report"):
		_report = StructureReport.from_dict(data.report)
		report_changed.emit(_report)
