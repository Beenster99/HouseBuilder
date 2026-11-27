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
## The live engineer was switched on or off (for everyone).
signal live_engineer_changed(on: bool)
## The host started or finished a live check (only the host sees this).
signal checking_changed(busy: bool)
## The live engineer placed a part; left more are queued (host only).
signal engineer_placed(left: int)

const EVENT_RUN := "structure.run"
## The "Stress test" button and the Engineer view in the design room.
const STRESS_TEST_FLAG := "structure.stress_test"
const OVERLAY := "structure.stress"
const ACTION := "structure.stress"
const DESIGN_ACTION := "structure.design"
const PANEL_SCRIPT := "res://modules/structure/internal/stress_panel.gd"
## The live assessment: the host re-tests the building in the background as the crew edits,
## and shows it in an always-open window in the design room.
const LIVE_FLAG := "structure.live"
const LIVE_PANEL := "structure.live"
const EVENT_ENGINEER := "structure.engineer"
## "Design structure" pressed (to the host), and the engineer's notes (to everyone).
const EVENT_DESIGN := "structure.design"
const EVENT_DESIGNED := "structure.designed"
## Seconds of quiet after an edit before the host re-tests.
const LIVE_DELAY := 0.4
## Seconds between the live engineer's placements, so everyone watches them go in.
const PLACE_EVERY := 0.2
## The undo group of the live engineer's placements (one undo takes back a run of them).
const ENGINEER_GROUP := "structure.engineer"

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

## Shared: the engineer places supports by itself as the crew designs.
var live_engineer := false
var _live := false
var _watched: BuildingModel
var _changes := 0
var _dirty := false
var _wait := 0.0
var _job := -1
var _job_changes := 0
var _job_out: Dictionary = {}
var _queue: Array = []
## The live check's own copy of the building, kept up to date by replaying each edit on the
## worker thread (copying a big building on the main thread every edit costs a frame).
## Only touched by the job, or between jobs.
var _mirror: BuildingModel
var _pending_ops: Array = []
var _need_full := true
var _own_provider := false  # the graph provider is the shared building's (set at start)
var _design_requested := false
var _job_design := false
var _place_wait := 0.0
var _placing := false


func register_module() -> void:
	attach(Modules.bus("multiplayer"))
	# By default the host tests the shared building.
	var building := Modules.bus("building") as BuildingBus
	if building:
		set_graph_provider(func() -> StructureGraph: return StructureBuilding.graph(building.model))
		_own_provider = true
		set_model_provider(func() -> BuildingModel: return building.model)
		set_edit_handler(func(op: Dictionary, group: String) -> void: building.sync.edit(op, group))
		if Flags.is_on(LIVE_FLAG):
			watch(building.model)
	_hook_design.call_deferred()


func unregister_module() -> void:
	if is_instance_valid(_design):
		_design.unregister_action(ACTION)
		_design.unregister_action(DESIGN_ACTION)
		_design.unregister_overlay(OVERLAY)
		if _design.has_method("unregister_panel"):
			_design.unregister_panel(LIVE_PANEL)
	_design = null
	watch(null)
	_stop_job()
	if _net:
		_net.unregister_event(EVENT_RUN)
		_net.unregister_event(EVENT_ENGINEER)
		_net.unregister_event(EVENT_DESIGN)
		_net.unregister_event(EVENT_DESIGNED)
		_net.unregister_snapshot_provider("structure")
	_net = null


## Hooks the bus to a session (the multiplayer bus, or a stand-in with the same calls).
func attach(net: Object) -> void:
	_net = net
	if _net == null:
		return
	_net.register_event(EVENT_RUN, _apply_run, _validate_run)
	_net.register_event(EVENT_ENGINEER, _apply_engineer, _validate_engineer)
	_net.register_event(EVENT_DESIGN, _apply_design, _validate_design)
	_net.register_event(EVENT_DESIGNED, _apply_designed)
	_net.register_snapshot_provider("structure", self)


## Where the host gets the building to test: a Callable returning a StructureGraph (or
## null when there is nothing to test). Clients may set one too; only the host's is used.
## Set at start to the building module's shared model.
func set_graph_provider(provider: Callable) -> void:
	_provider = provider
	_own_provider = false


## Asks the host to stress test the current building. scenario_ids defaults to
## normal use, storm and quake. The report arrives through report_changed; a refusal
## ("Nothing to test yet") through the multiplayer bus's request_rejected.
func run_stress_test(scenario_ids: PackedStringArray = PackedStringArray()) -> void:
	_net.request(EVENT_RUN, {"scenarios": Array(scenario_ids)})


## The building the engineer designs: a Callable returning a BuildingModel (or null).
## Set at start to the building module's shared model.
func set_model_provider(provider: Callable) -> void:
	_model_provider = provider


## Where design_structure() sends its edits: a Callable(op, group). Set at start to the building
## module's shared sync, so the change is validated, sent to everyone and one undo step.
func set_edit_handler(handler: Callable) -> void:
	_editor = handler


## The engineer designs the structure: works out what to add and upsize until the
## building passes (StructureDesigner), sends it as one shared edit, then asks for a
## fresh stress test. Returns the plan; its notes also go out through design_done.
## While the live check runs (in a game) the work is done on the host in the background:
## this returns {} at once and design_done follows on every player's machine.
func design_structure() -> Dictionary:
	if _live:
		if _net:
			_net.request(EVENT_DESIGN, {})
		else:
			_apply_design({})
		return {}
	var model: BuildingModel = _model_provider.call() if _model_provider.is_valid() else null
	if model == null or model.parts.is_empty():
		_plan = {"op": {}, "notes": PackedStringArray(["Nothing to design yet: draw some walls and floors first."]), "passed": false}
		design_done.emit(_plan.notes)
		return _plan
	_plan = StructureDesigner.design(model)
	if not (_plan.op as Dictionary).is_empty() and _editor.is_valid():
		_editor.call(_plan.op, "")
	if _net:
		run_stress_test()
	design_done.emit(_plan.notes)
	return _plan


## Live assessment: re-test model in the background (on the host) a moment after every
## edit, and, with the live engineer on, place its fixes one by one. null stops watching.
func watch(model: BuildingModel) -> void:
	if _watched and _watched.changed.is_connected(_on_model_changed):
		_watched.changed.disconnect(_on_model_changed)
		_watched.loaded.disconnect(_on_model_loaded)
	_stop_job()
	_watched = model
	_live = model != null
	_queue.clear()
	_mirror = null
	_need_full = true
	_pending_ops.clear()
	if model:
		model.changed.connect(_on_model_changed)
		model.loaded.connect(_on_model_loaded)
		_dirty = not model.parts.is_empty()
		_wait = LIVE_DELAY
	set_process(_live)


## Switches the live engineer on or off for everyone (any player may).
func set_live_engineer(on: bool) -> void:
	if _net:
		_net.request(EVENT_ENGINEER, {"on": on})
	else:
		_apply_engineer({"on": on})


## True while the host is working out a live check.
func is_checking() -> bool:
	return _job >= 0


## Live engineer placements still to come.
func pending_placements() -> int:
	return _queue.size()


## Quitting while a live check runs: let it finish first, or the engine dies tearing down
## the thread pool under it.
func _exit_tree() -> void:
	_stop_job()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_stop_job()


func _stop_job() -> void:
	if _job >= 0:
		WorkerThreadPool.wait_for_task_completion(_job)
		_job = -1
		_job_out = {}


func _is_host() -> bool:
	return _net == null or not _net.has_method("is_host") or _net.is_host()


func _on_model_changed(op: Dictionary) -> void:
	_changes += 1
	if str(op.get("op", "")) == "load" or op.is_empty():
		_need_full = true
		_pending_ops.clear()
	elif not _need_full:
		_pending_ops.append(op.duplicate(true))
	if not _placing:
		_queue.clear()  # the crew changed something: the plan may not fit any more
	_dirty = true
	_wait = LIVE_DELAY


func _on_model_loaded() -> void:
	_on_model_changed({})


func _process(delta: float) -> void:
	if not _live or not _is_host():
		return
	if _job >= 0:
		if WorkerThreadPool.is_task_completed(_job):
			WorkerThreadPool.wait_for_task_completion(_job)
			_job = -1
			checking_changed.emit(false)
			_finish_check()
		return
	if not _queue.is_empty():
		_place_wait -= delta
		if _place_wait <= 0.0:
			_place_next()
		return
	if _dirty:
		_wait -= delta
		if _wait <= 0.0:
			_start_check()


func _start_check() -> void:
	_dirty = false
	if _watched == null or _watched.parts.is_empty():
		if _design_requested:
			_design_requested = false
			var none := ["Nothing to design yet: draw some walls and floors first."]
			if _net and _net.has_method("host_emit"):
				_net.host_emit(EVENT_DESIGNED, {"notes": none})
			else:
				design_done.emit(PackedStringArray(none))
		return
	_job_changes = _changes
	_job_out = {}
	var data := {}
	var ops: Array = []
	if _need_full or _mirror == null:
		data = _watched.to_data()
		_need_full = false
	else:
		ops = _pending_ops
	_pending_ops = []
	var cat := _watched.catalog
	_job_design = _design_requested
	_design_requested = false
	var engineer := (live_engineer or _job_design) and _editor.is_valid()
	_job = WorkerThreadPool.add_task(_check.bind(data, ops, cat, engineer, _watched.revision), false, "structure live check")
	checking_changed.emit(true)


## On a worker thread: works only on its own copy of the building.
func _check(data: Dictionary, ops: Array, cat: BuildingCatalog, engineer: bool, revision: int) -> void:
	if not data.is_empty():
		_mirror = BuildingModel.from_data(data, cat)
	else:
		for op: Dictionary in ops:
			if _mirror.apply(op).is_empty():
				_job_out = {"resync": true}  # lost step: copy the whole building next time
				return
	var m := _mirror
	m.revision = revision  # so the report names the same graph revision as the real one
	var report := StructureBuilding.stress_test(m).compact()
	# Serialising and fingerprinting a big report takes tens of ms: do it here, not on a frame.
	var out := {"report": report, "data": report.to_dict(), "digest": report.digest()}
	if engineer and not report.passed():
		out["plan"] = StructureDesigner.design(m)
	_job_out = out


func _finish_check() -> void:
	if _job_out.get("resync", false):
		if _job_design:
			_design_requested = true
		_mirror = null
		_need_full = true
		_dirty = true
		_wait = 0.0
		return
	if _changes != _job_changes:
		if _job_design:
			_design_requested = true  # design the building as it is now instead
		return  # edited while checking: a fresh check is already due
	var report: StructureReport = _job_out.get("report")
	if report == null:
		return
	if _net and _net.has_method("host_emit"):
		_net.host_emit(EVENT_RUN, {"scenarios": [], "report": _job_out.data, "digest": _job_out.digest, "live": true})
	else:
		_set_report(report)
	var plan: Dictionary = _job_out.get("plan", {})
	if _job_design:
		var notes := PackedStringArray(["Nothing to fix: the structure already passes every test."])
		if not plan.is_empty():
			_plan = plan
			notes = plan.notes
			if not (plan.op as Dictionary).is_empty():
				_editor.call(plan.op, "")  # one edit, one undo
		if _net and _net.has_method("host_emit"):
			_net.host_emit(EVENT_DESIGNED, {"notes": Array(notes)})
		else:
			design_done.emit(notes)
		return
	if live_engineer and not plan.is_empty() and not (plan.op as Dictionary).is_empty():
		_plan = plan
		_queue = (plan.op.ops as Array).duplicate(true)
		_place_wait = 0.0
		design_done.emit(plan.notes)


func _place_next() -> void:
	var op: Dictionary = _queue.pop_front()
	_placing = true
	_editor.call(op, ENGINEER_GROUP)
	_placing = false
	# Flash what the engineer just placed or upsized, for every player.
	var id := str(op.entry.get("id", "")) if op.has("entry") else str(op.get("id", ""))
	if id != "" and is_instance_valid(_design) and _design.has_method("pulse"):
		_design.pulse(PackedStringArray([id]))
	_place_wait = PLACE_EVERY
	engineer_placed.emit(_queue.size())
	if _queue.is_empty():
		_dirty = true
		_wait = 0.0


func _validate_design(_sender: int, _payload: Dictionary) -> Variant:
	if not _live:
		return "The engineer is not on site"
	return {}


func _apply_design(_payload: Dictionary) -> void:
	if _live and _is_host():
		_design_requested = true
		_dirty = true
		_wait = 0.0


func _apply_designed(payload: Dictionary) -> void:
	design_done.emit(PackedStringArray(payload.get("notes", [])))


func _validate_engineer(_sender: int, payload: Dictionary) -> Variant:
	return {"on": bool(payload.get("on", false))}


func _apply_engineer(payload: Dictionary) -> void:
	live_engineer = bool(payload.get("on", false))
	if not live_engineer:
		_queue.clear()
	elif _live:
		_dirty = true
		_wait = 0.0
	live_engineer_changed.emit(live_engineer)


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
	# With the live window always open, the Engineer view only colours the building.
	if _live and design.has_method("register_panel"):
		design.register_panel(LIVE_PANEL, "Structural engineer", func(_model: BuildingModel) -> Control: return make_panel(true), 30)
		design.register_overlay(OVERLAY, "Engineer", overlay_tints, Callable(), 40)
	else:
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
	if _part_u.is_empty() and not _report.parts.is_empty():
		_part_u = _report.parts
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
## live: the always-open window (no title of its own, with the live engineer switch).
func make_panel(live: bool = false) -> Control:
	var panel: Control = load(PANEL_SCRIPT).new()
	panel.call("bind", self, live)
	return panel


func _validate_run(_sender: int, payload: Dictionary) -> Variant:
	# In a game the live check answers in the background instead of solving on this frame.
	if _live and _own_provider and (payload.get("scenarios", []) as Array).is_empty() and not payload.has("report"):
		if _watched == null or _watched.parts.is_empty():
			return "Nothing to test yet"
		_dirty = true
		_wait = 0.0
		return {"queued": true}
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
	if payload.get("queued", false):
		return
	var report := StructureReport.from_dict(payload.get("report", {}))
	# Live checks skip the fingerprint check: it costs a frame's worth of time on every edit.
	if payload.has("digest") and not payload.get("live", false) and report.digest() != str(payload.digest):
		push_warning("structure: stress test report changed on the way (%s)" % payload.digest)
	_set_report(report)


func get_net_snapshot() -> Dictionary:
	var out := {"engineer": live_engineer}
	if _report:
		out["report"] = _report.to_dict()
	return out


func apply_net_snapshot(data: Dictionary) -> void:
	if data.has("engineer"):
		live_engineer = bool(data.engineer)
		live_engineer_changed.emit(live_engineer)
	if data.has("report"):
		_set_report(StructureReport.from_dict(data.report))


func _set_report(report: StructureReport) -> void:
	_report = report
	_part_u = {}
	report_changed.emit(report)
