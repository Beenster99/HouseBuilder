class_name ServicesBus
extends Node
## Services module bus (Modules.bus("services")): the M&E consultant. It routes wiring and
## piping through the shared building and checks every room is powered and every wet room
## plumbed. Only the host routes; everyone receives the same report.
##
##   var services := Modules.bus("services") as ServicesBus
##   services.report_changed.connect(_redraw)
##   services.run_consultant()                          # any player; the host routes it
##   services.place_source("power", 0, Vector2(1, 0.5)) # pin the consumer unit; clear_source()
##   services.last_report()                             # ServicesReport, or null
##   services.design_services()                         # the consultant adds what is missing
##
## The host reads the building from its model provider (by default the building bus's
## shared model), routes it with ServicesConsultant and broadcasts the report as the event
## itself, so clients never route and never drift. Late joiners get the placed sources and
## the last report in the join snapshot. Save section "services": the placed sources.

signal report_changed(report: ServicesReport)
signal sources_changed
## The host started routing; report_changed follows when it is done.
signal routing_started
## The consultant's design was sent to the building (or there was nothing to add): its
## notes, in words. Fired on the player who asked.
signal design_done(notes: PackedStringArray)
## A feasibility review finished (FeasibilityReview), on the player who asked.
signal review_done(review: Dictionary)

## A player asks the host to route; the host routes on a worker thread and broadcasts the
## result as EVENT_REPORT, so nobody's frame waits on the routing.
const EVENT_ROUTE := "services.route"
const EVENT_REPORT := "services.report"
const EVENT_SOURCE := "services.source"
const SAVE_SECTION := "services"
const SAVE_VERSION := 1
## "Route services" and "Design services" on the design room's top bar, and the M&E view.
const CONSULTANT_FLAG := "services.consultant"
const OVERLAY := "services.me"
## Live assessment: a moment after the building stops changing, the host routes the
## services again and every player's feasibility verdict updates.
const LIVE_FLAG := "services.live"
const PANEL_SCRIPT := "res://modules/services/internal/services_panel.gd"
const FEASIBILITY_PANEL := "services.feasibility"
const FEASIBILITY_SCRIPT := "res://modules/services/internal/feasibility_panel.gd"

## system -> {level, at: [x, z]}: sources the players placed (see ServicesConsultant).
var sources: Dictionary = {}
var _net: Object
var _provider := Callable()
var _editor := Callable()
## Seconds of quiet after an edit before the live assessment runs.
var live_delay := 1.0
var _live_timer: Timer
var _watched: BuildingModel
var _review: Dictionary = {}
var _design: Node
var _report: ServicesReport


func register_module() -> void:
	Saves.register_section(SAVE_SECTION, self)
	attach(Modules.bus("multiplayer"))
	_hook_design.call_deferred()
	if Flags.is_on(LIVE_FLAG):
		_hook_live.call_deferred()


func _hook_live() -> void:
	var b := Modules.bus("building")
	if b and "model" in b:
		watch(b.model)
	var contracts := Modules.bus("contracts")
	if contracts and contracts.has_signal("active_changed"):
		contracts.active_changed.connect(_schedule)


## Keeps the assessment live for `model`: every change (edit, undo, load) restarts a short
## timer; when it runs out the host routes again (broadcast to all) and this player's
## feasibility verdict is redone (review_done). null stops watching.
func watch(model: BuildingModel) -> void:
	if _watched and _watched.changed.is_connected(_on_changed):
		_watched.changed.disconnect(_on_changed)
	_watched = model
	if model:
		model.changed.connect(_on_changed)
	if _live_timer == null:
		_live_timer = Timer.new()
		_live_timer.one_shot = true
		_live_timer.timeout.connect(_run_live)
		add_child(_live_timer)


func _on_changed(_op: Dictionary) -> void:
	_schedule()


func _schedule() -> void:
	if _live_timer:
		_live_timer.start(live_delay)


func _run_live() -> void:
	var m := _model()
	if m == null or m.rooms.is_empty():
		return
	# One snapshot of the building feeds both jobs; turning it back into a model happens on
	# the worker threads, so the main thread only pays for to_data().
	var data := m.to_data()
	if _net and (not _net.has_method("is_host") or _net.is_host()):
		_route_in_background(data, m.revision, m.catalog)
	_review_in_background(data, m.catalog)


## The live review runs on a worker thread on a copy of the building, so a second of
## structural design work never stalls the room. Edits made meanwhile queue one more run.
var _task := -1
var _again := false


func _review_in_background(data: Dictionary, cat: BuildingCatalog, given_brief: Dictionary = {}) -> void:
	if _task >= 0:
		_again = true
		return
	var brief := given_brief if not given_brief.is_empty() else _active_brief()
	var src := sources.duplicate(true)
	_task = WorkerThreadPool.add_task(func() -> void:
		var copy := BuildingModel.from_data(data, cat)
		var r := FeasibilityReview.review(copy, brief, src)
		_finish_review.call_deferred(r))


func _finish_review(r: Dictionary) -> void:
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_review = r
	review_done.emit(r)
	if _again:
		_again = false
		_schedule()


func _active_brief() -> Dictionary:
	var contracts := Modules.bus("contracts")
	if contracts and "active" in contracts:
		return (contracts.active as Dictionary).duplicate(true)
	return {}


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if _route_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_route_task)
		_route_task = -1
	if _design_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_design_task)
		_design_task = -1


## The last feasibility verdict on this player ({} before the first).
func last_review() -> Dictionary:
	return _review


func unregister_module() -> void:
	Saves.unregister_section(SAVE_SECTION)
	if is_instance_valid(_design):
		_design.unregister_action("services.route")
		_design.unregister_action("services.design")
		_design.unregister_action("services.review")
		_design.unregister_overlay(OVERLAY)
		if _design.has_method("unregister_panel"):
			_design.unregister_panel(FEASIBILITY_PANEL)
	_design = null
	if _net:
		_net.unregister_event(EVENT_ROUTE)
		_net.unregister_event(EVENT_REPORT)
		_net.unregister_event(EVENT_SOURCE)
		_net.unregister_snapshot_provider(SAVE_SECTION)
	_net = null


## Hooks the bus to a session (the multiplayer bus, or a stand-in with the same calls).
func attach(net: Object) -> void:
	_net = net
	if _net == null:
		return
	_net.register_event(EVENT_ROUTE, _apply_queued, _validate_route)
	_net.register_event(EVENT_REPORT, _apply_route)
	_net.register_event(EVENT_SOURCE, _apply_source, _validate_source)
	_net.register_snapshot_provider(SAVE_SECTION, self)


## "Route services" in the design room, when the design module is loaded (optional).
func _hook_design() -> void:
	if not Flags.is_on(CONSULTANT_FLAG):
		return
	var design := Modules.bus("design")
	if design == null or not design.has_method("register_action"):
		return
	_design = design
	design.register_action("services.route", "Route services", func(_model: BuildingModel) -> void:
		run_consultant(), 55)
	design.register_action("services.design", "Design services", func(_model: BuildingModel) -> void:
		design_services(), 56)
	design.register_action("services.review", "Check feasibility", func(_model: BuildingModel) -> void:
		review_feasibility(), 57)
	if design.has_method("register_overlay"):
		design.register_overlay(OVERLAY, "M&E", overlay_tints, make_panel, 60)
		report_changed.connect(func(_r: ServicesReport) -> void: design.refresh_overlay(OVERLAY))
	if design.has_method("register_panel") and Flags.is_on(LIVE_FLAG):
		design.register_panel(FEASIBILITY_PANEL, "Feasibility", make_feasibility_panel, 15)


## The M&E view's colours: rooms green when fully served, red when something is missing;
## source units blue; fixtures no route reaches red.
func overlay_tints(_model: BuildingModel) -> Dictionary:
	var out := {}
	if _report == null:
		return out
	for rid: String in _report.rooms:
		out[rid] = Color(0.3, 0.8, 0.45) if (_report.rooms[rid].missing as Array).is_empty() else Color(0.95, 0.3, 0.25)
	for s: String in _report.systems:
		var sys: Dictionary = _report.systems[s]
		if sys.source.has("part"):
			out[str(sys.source.part)] = Color(0.3, 0.6, 1.0)
		for u: Dictionary in sys.unserved:
			out[str(u.id)] = Color(0.95, 0.3, 0.25)
	return out


## The always-on Feasibility window: the live verdict, kept up to date by review_done.
func make_feasibility_panel(_model: BuildingModel = null) -> Control:
	var panel: Control = load(FEASIBILITY_SCRIPT).new()
	panel.call("bind", self)
	return panel


## The M&E view's side panel: the summary, the notes and the two buttons.
func make_panel() -> Control:
	var panel: Control = load(PANEL_SCRIPT).new()
	panel.call("bind", self)
	return panel


## Where the host gets the building: a Callable returning a BuildingModel (or null). By
## default the building bus's shared model. Only the host's provider is used.
func set_model_provider(provider: Callable) -> void:
	_provider = provider


## Where design_services() sends its building ops: a Callable(op). By default the building
## bus's shared sync (so the edit is validated, broadcast and one undo step for everyone).
func set_edit_handler(handler: Callable) -> void:
	_editor = handler


## The consultant does the design work: it works out what the building is missing (fixtures
## in bare wet rooms, the consumer unit, water main, boiler and soil stack) on a worker
## thread, sends it to the building as one edit, then routes everything again. design_done
## (with the notes) fires when the edit has been sent; last_plan() is the plan.
func design_services() -> void:
	var model := _model()
	if model == null or model.rooms.is_empty():
		design_done.emit(PackedStringArray(["Nothing to design yet: draw some rooms first."]))
		return
	if _design_task >= 0:
		return
	var data := model.to_data()
	var cat := model.catalog
	var src := sources.duplicate(true)
	_design_task = WorkerThreadPool.add_task(func() -> void:
		var plan := ServicesDesigner.propose(BuildingModel.from_data(data, cat), src)
		_finish_design.call_deferred(plan))


var _design_task := -1
var _plan: Dictionary = {}


func _finish_design(plan: Dictionary) -> void:
	WorkerThreadPool.wait_for_task_completion(_design_task)
	_design_task = -1
	_plan = plan
	if not (plan.ops as Array).is_empty():
		var op := BuildingCommands.batch(plan.ops)
		if _editor.is_valid():
			_editor.call(op)
		else:
			var b := Modules.bus("building")
			if b and "sync" in b:
				b.sync.edit(op)
	design_done.emit(plan.notes)
	run_consultant()


## The last Design services plan (ServicesDesigner.propose), or {}.
func last_plan() -> Dictionary:
	return _plan


## The consultant's verdict on the shared building: does it stand up, is it powered and
## plumbed, and does it meet the active contract's brief and budget (FeasibilityReview).
## Worked out on a worker thread on this player's copy of the building, which every player
## shares, so anyone asking gets the same answer; it arrives through review_done.
func review_feasibility(brief: Dictionary = {}) -> void:
	var m := _model()
	if m == null:
		var r := FeasibilityReview.review(null)
		_review = r
		review_done.emit(r)
		return
	_review_in_background(m.to_data(), m.catalog, brief)


## Asks the host to route every service through the current building. The report arrives
## through report_changed; a refusal through the multiplayer bus's request_rejected.
func run_consultant() -> void:
	_net.request(EVENT_ROUTE, {})


## Asks the host to pin a system's source (consumer unit, water main, boiler or soil stack)
## at plan point `at` on `level`. A source part in the building, once the catalog has one,
## still wins over this.
func place_source(system: String, level: int, at: Vector2) -> void:
	_net.request(EVENT_SOURCE, {"system": system, "level": level, "at": [at.x, at.y]})


## Asks the host to let the consultant choose a system's source again.
func clear_source(system: String) -> void:
	_net.request(EVENT_SOURCE, {"system": system, "clear": true})


## The last report, or null before the first one.
func last_report() -> ServicesReport:
	return _report


func _model() -> BuildingModel:
	if _provider.is_valid():
		var m: Variant = _provider.call()
		return m as BuildingModel if m is BuildingModel else null
	var b := Modules.bus("building")
	if b and "model" in b:
		return b.model as BuildingModel
	return null


func _validate_route(_sender: int, _payload: Dictionary) -> Variant:
	var model := _model()
	if model == null or model.rooms.is_empty():
		return "Nothing to route yet: draw some rooms first"
	_route_in_background(model.to_data(), model.revision, model.catalog)
	return {"revision": model.revision}


## Everyone: the host has started routing (routing_started); the report follows.
func _apply_queued(_payload: Dictionary) -> void:
	routing_started.emit()


var _route_task := -1
var _route_again := false


## Host: route a copy of the building on a worker thread; a request made while one runs
## queues one more run, so the last report is always of the latest building.
func _route_in_background(data: Dictionary, revision: int, cat: BuildingCatalog) -> void:
	if _route_task >= 0:
		_route_again = true
		return
	var src := sources.duplicate(true)
	_route_task = WorkerThreadPool.add_task(func() -> void:
		var copy := BuildingModel.from_data(data, cat)
		var report := ServicesConsultant.route(copy, src)
		report.revision = revision
		var payload := {"report": report.to_dict(), "digest": report.digest()}
		_finish_route.call_deferred(payload))


func _finish_route(payload: Dictionary) -> void:
	WorkerThreadPool.wait_for_task_completion(_route_task)
	_route_task = -1
	if _net:
		_net.host_emit(EVENT_REPORT, payload)
	if _route_again:
		_route_again = false
		var model := _model()
		if model != null and not model.rooms.is_empty():
			_route_in_background(model.to_data(), model.revision, model.catalog)


## True while the host is routing on a worker thread.
func is_routing() -> bool:
	return _route_task >= 0


func _apply_route(payload: Dictionary) -> void:
	_report = ServicesReport.from_dict(payload.get("report", {}))
	report_changed.emit(_report)


func _validate_source(_sender: int, payload: Dictionary) -> Variant:
	var s := str(payload.get("system", ""))
	if not ServicesRates.is_system(s):
		return "Unknown service: %s" % s
	if bool(payload.get("clear", false)):
		return {"system": s, "clear": true}
	var at: Variant = payload.get("at")
	var level: Variant = payload.get("level")
	if not (at is Array and at.size() == 2 and (at[0] is float or at[0] is int) and (at[1] is float or at[1] is int)):
		return "A source needs a plan position"
	if not (level is int and level >= 0):
		return "A source needs a level"
	var model := _model()
	if model != null and level >= model.level_count():
		return "There is no level %d" % level
	return {"system": s, "level": level, "at": [float(at[0]), float(at[1])]}


func _apply_source(payload: Dictionary) -> void:
	var s := str(payload.system)
	if bool(payload.get("clear", false)):
		sources.erase(s)
	else:
		sources[s] = {"level": int(payload.level), "at": [float(payload.at[0]), float(payload.at[1])]}
	sources_changed.emit()


func get_net_snapshot() -> Dictionary:
	var out := {"sources": sources.duplicate(true)}
	if _report:
		out["report"] = _report.to_dict()
	return out


func apply_net_snapshot(data: Dictionary) -> void:
	sources = (data.get("sources", {}) as Dictionary).duplicate(true)
	sources_changed.emit()
	if data.has("report"):
		_report = ServicesReport.from_dict(data.report)
		report_changed.emit(_report)


# Saves provider

func save_version() -> int:
	return SAVE_VERSION


func save_data() -> Dictionary:
	return {"sources": sources.duplicate(true)}


func load_data(data: Dictionary, _from_version: int) -> void:
	sources = {}
	var s: Variant = data.get("sources", {})
	if s is Dictionary:
		for k: String in s:
			if ServicesRates.is_system(k) and s[k] is Dictionary and s[k].has("at"):
				sources[k] = {"level": int(s[k].get("level", 0)), "at": [float(s[k].at[0]), float(s[k].at[1])]}
	_report = null
	sources_changed.emit()


func reset_data() -> void:
	sources = {}
	_report = null
	sources_changed.emit()
