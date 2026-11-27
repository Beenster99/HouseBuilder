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
## The engineer finished designing the structure: what it did and what is left (plain words).
signal design_done(notes: PackedStringArray)

const EVENT_RUN := "structure.run"
## The "Stress test" button and the Engineer view in the design room.
const STRESS_TEST_FLAG := "structure.stress_test"
const OVERLAY := "structure.stress"
const ACTION := "structure.stress"
const DESIGN_ACTION := "structure.design"
const PANEL_SCRIPT := "res://modules/structure/internal/stress_panel.gd"

## Overlay colours: green under StructureResult.AMBER, amber up to RED, red past it.
const GREEN := Color(0.3, 0.78, 0.42)
const AMBER := Color(0.98, 0.7, 0.2)
const RED := Color(0.93, 0.25, 0.22)

var _net: Object
var _provider := Callable()
var _report: StructureReport
var _design: Node
var _model_provider := Callable()
var _editor := Callable()
var _plan: Dictionary = {}
## part id -> highest utilisation in the last report (built on demand).
var _part_u: Dictionary = {}


func register_module() -> void:
	attach(Modules.bus("multiplayer"))
	# By default the host tests the shared building.
	var building := Modules.bus("building") as BuildingBus
	if building:
		set_graph_provider(func() -> StructureGraph: return StructureBuilding.graph(building.model))
		set_model_provider(func() -> BuildingModel: return building.model)
		set_edit_handler(func(op: Dictionary) -> void: building.sync.edit(op))
	_hook_design.call_deferred()


func unregister_module() -> void:
	if is_instance_valid(_design):
		_design.unregister_action(ACTION)
		_design.unregister_action(DESIGN_ACTION)
		_design.unregister_overlay(OVERLAY)
	_design = null
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


## The building the engineer designs: a Callable returning a BuildingModel (or null).
## Set at start to the building module's shared model.
func set_model_provider(provider: Callable) -> void:
	_model_provider = provider


## Where design_structure() sends its edit: a Callable(op). Set at start to the building
## module's shared sync, so the change is validated, sent to everyone and one undo step.
func set_edit_handler(handler: Callable) -> void:
	_editor = handler


## The engineer designs the structure: works out what to add and upsize until the
## building passes (StructureDesigner), sends it as one shared edit, then asks for a
## fresh stress test. Returns the plan; its notes also go out through design_done.
func design_structure() -> Dictionary:
	var model: BuildingModel = _model_provider.call() if _model_provider.is_valid() else null
	if model == null or model.parts.is_empty():
		_plan = {"op": {}, "notes": PackedStringArray(["Nothing to design yet: draw some walls and floors first."]), "passed": false}
		design_done.emit(_plan.notes)
		return _plan
	_plan = StructureDesigner.design(model)
	if not (_plan.op as Dictionary).is_empty() and _editor.is_valid():
		_editor.call(_plan.op)
	if _net:
		run_stress_test()
	design_done.emit(_plan.notes)
	return _plan


## The last design_structure() plan ({} before the first).
func last_plan() -> Dictionary:
	return _plan


## The last stress test, or null before the first one.
func last_report() -> StructureReport:
	return _report


## "Stress test" on the design room's top bar and the Engineer view, when the design
## module is loaded (optional, found by name so structure does not depend on it).
func _hook_design() -> void:
	if not Flags.is_on(STRESS_TEST_FLAG):
		return
	var design := Modules.bus("design")
	if design == null or not design.has_method("register_overlay"):
		return
	hook_design(design)


## Registers the action and the overlay with a design bus (or a stand-in in tests).
func hook_design(design: Node) -> void:
	_design = design
	design.register_action(ACTION, "Stress test", func(_model: BuildingModel) -> void: run_stress_test(), 40)
	design.register_action(DESIGN_ACTION, "Design structure", func(_model: BuildingModel) -> void: design_structure(), 54)
	design.register_overlay(OVERLAY, "Engineer", overlay_tints, make_panel, 40)
	report_changed.connect(func(_r: StructureReport) -> void: design.refresh_overlay(OVERLAY))


## The Engineer view's colours: each building part by the worst utilisation of any of its
## members or foundations over every scenario. Parts the test did not reach stay untinted.
func overlay_tints(_model: BuildingModel = null) -> Dictionary:
	var out := {}
	for id: String in part_utilisation():
		out[id] = colour_for(float(_part_u[id]))
	return out


## part id -> highest utilisation in the last report ({} before the first test).
func part_utilisation() -> Dictionary:
	if _report == null:
		return {}
	if _part_u.is_empty():
		for r in _report.results:
			for dict: Dictionary in [r.members, r.anchors]:
				for id: String in dict:
					var part := str(dict[id].get("part", ""))
					if part != "":
						_part_u[part] = maxf(float(_part_u.get(part, 0.0)), float(dict[id].u))
	return _part_u


static func colour_for(u: float) -> Color:
	match StructureResult.status_for(u):
		StructureResult.RED_STATUS:
			return RED
		StructureResult.AMBER_STATUS:
			return AMBER
	return GREEN


## The Engineer view's side panel: the verdict, each scenario, the notes and the button.
func make_panel() -> Control:
	var panel: Control = load(PANEL_SCRIPT).new()
	panel.call("bind", self)
	return panel


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
	_set_report(report)


func get_net_snapshot() -> Dictionary:
	return {"report": _report.to_dict()} if _report else {}


func apply_net_snapshot(data: Dictionary) -> void:
	if data.has("report"):
		_set_report(StructureReport.from_dict(data.report))


func _set_report(report: StructureReport) -> void:
	_report = report
	_part_u = {}
	report_changed.emit(report)
