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
## The consultant's design was sent to the building (or there was nothing to add): its
## notes, in words. Fired on the player who asked.
signal design_done(notes: PackedStringArray)

const EVENT_ROUTE := "services.route"
const EVENT_SOURCE := "services.source"
const SAVE_SECTION := "services"
const SAVE_VERSION := 1
## "Route services" and "Design services" on the design room's top bar, and the M&E view.
const CONSULTANT_FLAG := "services.consultant"
const OVERLAY := "services.me"
const PANEL_SCRIPT := "res://modules/services/internal/services_panel.gd"

## system -> {level, at: [x, z]}: sources the players placed (see ServicesConsultant).
var sources: Dictionary = {}
var _net: Object
var _provider := Callable()
var _editor := Callable()
var _design: Node
var _report: ServicesReport


func register_module() -> void:
	Saves.register_section(SAVE_SECTION, self)
	attach(Modules.bus("multiplayer"))
	_hook_design.call_deferred()


func unregister_module() -> void:
	Saves.unregister_section(SAVE_SECTION)
	if is_instance_valid(_design):
		_design.unregister_action("services.route")
		_design.unregister_action("services.design")
		_design.unregister_overlay(OVERLAY)
	_design = null
	if _net:
		_net.unregister_event(EVENT_ROUTE)
		_net.unregister_event(EVENT_SOURCE)
		_net.unregister_snapshot_provider(SAVE_SECTION)
	_net = null


## Hooks the bus to a session (the multiplayer bus, or a stand-in with the same calls).
func attach(net: Object) -> void:
	_net = net
	if _net == null:
		return
	_net.register_event(EVENT_ROUTE, _apply_route, _validate_route)
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
	if design.has_method("register_overlay"):
		design.register_overlay(OVERLAY, "M&E", overlay_tints, make_panel, 60)
		report_changed.connect(func(_r: ServicesReport) -> void: design.refresh_overlay(OVERLAY))


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
## in bare wet rooms, the consumer unit, water main, boiler and soil stack), sends it to the
## building as one edit, then routes everything again. Returns the plan (ServicesDesigner).
func design_services() -> Dictionary:
	var model := _model()
	if model == null:
		var none := {"ops": [], "notes": PackedStringArray(["Nothing to design yet: draw some rooms first."])}
		design_done.emit(none.notes)
		return none
	var plan := ServicesDesigner.propose(model, sources)
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
	return plan


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
	var report := ServicesConsultant.route(model, sources)
	return {"report": report.to_dict(), "digest": report.digest()}


func _apply_route(payload: Dictionary) -> void:
	var report := ServicesReport.from_dict(payload.get("report", {}))
	if payload.has("digest") and report.digest() != str(payload.digest):
		push_warning("services: consultant report changed on the way (%s)" % payload.digest)
	_report = report
	report_changed.emit(report)


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
