class_name ContractsBus
extends Node
## The contracts module's bus (Modules.bus("contracts")): the job board, the contract the
## crew has taken, the live check of the building against it, and the firm's career.
##
##   var c := Modules.bus("contracts") as ContractsBus
##   c.board                        # briefs on offer (ContractBrief dictionaries)
##   c.accept(brief_id)             # take one (every player sees it)
##   c.active                       # the brief being worked on, {} for none (sandbox)
##   c.assess()                     # ContractValidator.assess of the shared building now
##   c.set_structure_report(rep)    # a stress test result by hand (normally taken from the
##                                  # structure module's report_changed on every peer)
##   c.hand_over(days)              # settle: pays out, books the career, deals a new board
##   c.abandon()                    # drop the contract (costs reputation)
##   c.career                       # ContractCareer: money, reputation, unlocks
##   signals: board_changed, active_changed, settled(settlement), report_taken, career.changed
##
## While a contract is taken, a live "Contract" window sits in the design room's side column
## (DesignBus.register_panel, reached by name so contracts does not depend on design).
##
## Everything that changes shared state is a host-validated event, so all players see the
## same board, contract and payout. Save section "contracts".
## Feature flag "contracts" (the module).

signal board_changed
signal active_changed
## A contract was handed over: ContractPayout.settle's result, plus "unlocked": [ids].
signal settled(settlement: Dictionary)
## A stress test result was taken in (or cleared).
signal report_taken

## The design room's live window for the active contract (shown only while one is taken).
const PANEL_ID := "contracts.brief"
const PANEL_FLAG := "contracts.panel"
const PANEL_ORDER := 20
const PANEL_SCRIPT := preload("res://modules/contracts/internal/contract_panel.gd")

const SAVE_SECTION := "contracts"
const SAVE_VERSION := 1
const BOARD_SIZE := 5
const ABANDON_REPUTATION := 2
const EV_ACCEPT := "contracts.accept"
const EV_HANDOVER := "contracts.handover"
const EV_ABANDON := "contracts.abandon"
const EV_REPORT := "contracts.structure_report"

var career := ContractCareer.new()
var board: Array = []
var active: Dictionary = {}
## The latest stress test result for the active contract ({} until one is run).
var structure_report: Dictionary = {}
## The last handover's settlement ({} before the first).
var last_settlement: Dictionary = {}
var board_seed := 1
var net: MultiplayerBus
var _design: Node
## The building's checksum when structure_report was made: a report for an older design is
## stale and counts as untested.
var _report_sum := 0


func register_module() -> void:
	Saves.register_section(SAVE_SECTION, self)
	_deal_board(board_seed)
	if Modules.ready_done:
		_hook_net()
	else:
		Modules.modules_ready.connect(_hook_net, CONNECT_ONE_SHOT)


func unregister_module() -> void:
	Saves.unregister_section(SAVE_SECTION)
	if is_instance_valid(_design):
		_design.unregister_panel(PANEL_ID)
	unbind()


func _hook_net() -> void:
	var bus := Modules.bus("multiplayer") as MultiplayerBus
	if bus != null:
		bind(bus)
	var design := Modules.bus("design")
	if design != null and design.has_method("register_panel") and Flags.is_on(PANEL_FLAG):
		hook_design(design)
	var st := Modules.bus("structure") as StructureBus
	if st != null and not st.report_changed.is_connected(_on_structure_report):
		st.report_changed.connect(_on_structure_report)


## The structure module's stress test finished (it fires on every peer with the host's report).
func _on_structure_report(report: StructureReport) -> void:
	if report != null:
		_take_report(report.brief_result())


func _take_report(report: Dictionary) -> void:
	structure_report = report.duplicate(true)
	var m := building()
	_report_sum = m.checksum() if m != null else 0
	report_taken.emit()


## Shows the Contract window in a design bus (or a stand-in in tests) while a contract is taken.
func hook_design(design: Node) -> void:
	_design = design
	if not active_changed.is_connected(_sync_panel):
		active_changed.connect(_sync_panel)
	_sync_panel()


func _sync_panel() -> void:
	if not is_instance_valid(_design):
		return
	if active.is_empty():
		_design.unregister_panel(PANEL_ID)
	else:
		_design.register_panel(PANEL_ID, "Contract", make_panel, PANEL_ORDER)


## The live Contract window for a building (the design room calls this as it opens).
func make_panel(model: BuildingModel) -> Control:
	var p: RichTextLabel = PANEL_SCRIPT.new()
	p.name = "ContractPanel"
	p.setup(self, model if model != null else building())
	return p


## Ties the board and contract to a session (tests bind their own buses).
func bind(bus: MultiplayerBus) -> void:
	unbind()
	net = bus
	net.register_event(EV_ACCEPT, _apply_accept, _validate_accept)
	net.register_event(EV_HANDOVER, _apply_handover, _validate_handover)
	net.register_event(EV_ABANDON, _apply_abandon, _validate_abandon)
	net.register_event(EV_REPORT, _apply_report, _validate_report)
	net.register_snapshot_provider(SAVE_SECTION, self)


func unbind() -> void:
	if net == null:
		return
	for e: String in [EV_ACCEPT, EV_HANDOVER, EV_ABANDON, EV_REPORT]:
		net.unregister_event(e)
	net.unregister_snapshot_provider(SAVE_SECTION)
	net = null


## The shared building (the building module's), or null without it.
func building() -> BuildingModel:
	var b := Modules.bus("building") as BuildingBus
	return b.model if b != null else null


## The live check of a building (the shared one by default) against the active contract.
## {} with no contract taken.
func assess(model: BuildingModel = null) -> Dictionary:
	var m := model if model != null else building()
	if active.is_empty() or m == null:
		return {}
	return ContractValidator.assess(active, m, report_for(m))


## The stress test result if it was made for this design as it is now; {"stale": true} if
## the design has changed since; {} if there has been no test.
func report_for(m: BuildingModel) -> Dictionary:
	if structure_report.is_empty():
		return {}
	if m != null and _report_sum != 0 and m.checksum() != _report_sum:
		return {"stale": true}
	return structure_report


func brief(brief_id: String) -> Dictionary:
	for b: Dictionary in board:
		if str(b.id) == brief_id:
			return b
	return {}


# Requests (any player; the host decides)

func accept(brief_id: String) -> void:
	_request(EV_ACCEPT, {"id": brief_id})


## Hands the building over: days is the construction schedule's length (the timelapse's).
func hand_over(days: int) -> void:
	_request(EV_HANDOVER, {"days": days})


func abandon() -> void:
	_request(EV_ABANDON, {})


func set_structure_report(report: Dictionary) -> void:
	_request(EV_REPORT, {"report": report})


func _request(ev: String, payload: Dictionary) -> void:
	if net != null:
		net.request(ev, payload)
		return
	# No session at all (tools, some tests): validate and apply here.
	var out: Variant = call("_validate_" + ev.get_slice(".", 1), 1, payload)
	if out is Dictionary:
		call("_apply_" + ev.get_slice(".", 1), out)


# Host side

func _validate_accept(_sender: int, p: Dictionary) -> Variant:
	if not active.is_empty():
		return "finish or abandon %s first" % str(active.title)
	var b := brief(str(p.get("id", "")))
	if b.is_empty():
		return "that contract is no longer on the board"
	if int((b.get("reputation", {}) as Dictionary).get("min", 0)) > career.reputation:
		return "needs reputation %d" % int(b.reputation.min)
	return {"brief": b}


func _validate_handover(_sender: int, p: Dictionary) -> Variant:
	if active.is_empty():
		return "no contract taken"
	var m := building()
	if m == null:
		return "no building"
	var a := ContractValidator.assess(active, m, report_for(m))
	var s := ContractPayout.settle(active, a, {"days": int(p.get("days", active.deadline_days))})
	return {"settlement": s, "seed": board_seed + 1}


func _validate_abandon(_sender: int, _p: Dictionary) -> Variant:
	if active.is_empty():
		return "no contract taken"
	return {"title": str(active.title)}


func _validate_report(_sender: int, p: Dictionary) -> Variant:
	return {"report": p.get("report", {}) if p.get("report") is Dictionary else {}}


# Every peer

func _apply_accept(p: Dictionary) -> void:
	active = (p.get("brief", {}) as Dictionary).duplicate(true)
	# A contract on a real plot puts that site in play for the crew (the host asks once).
	var site_id := str((active.get("site", {}) as Dictionary).get("id", "")) if active.get("site") is Dictionary else ""
	var sites := Modules.bus("sites") as SitesBus
	if site_id != "" and sites != null and (net == null or net.is_host()):
		var cur := sites.current()
		if cur == null or cur.id() != site_id:
			sites.load_site(site_id)
	structure_report = {}
	_report_sum = 0
	active_changed.emit()


func _apply_handover(p: Dictionary) -> void:
	var s: Dictionary = (p.get("settlement", {}) as Dictionary).duplicate(true)
	s["unlocked"] = Array(career.record(s))
	last_settlement = s
	active = {}
	structure_report = {}
	_report_sum = 0
	_deal_board(int(p.get("seed", board_seed + 1)))
	active_changed.emit()
	settled.emit(s)


func _apply_abandon(_p: Dictionary) -> void:
	career.reputation = maxi(0, career.reputation - ABANDON_REPUTATION)
	career.changed.emit()
	active = {}
	structure_report = {}
	_report_sum = 0
	active_changed.emit()


func _apply_report(p: Dictionary) -> void:
	_take_report(p.get("report", {}))


func _deal_board(seed: int) -> void:
	board_seed = seed
	var done: Array = []
	for h: Dictionary in career.history:
		if h.passed:
			done.append(str(h.brief_id))
	board = ContractGenerator.board(board_seed, career.reputation, BOARD_SIZE, done)
	board_changed.emit()


# Snapshot (joiners) and save

func get_net_snapshot() -> Dictionary:
	return save_data()


func apply_net_snapshot(data: Dictionary) -> void:
	load_data(data, SAVE_VERSION)


func save_version() -> int:
	return SAVE_VERSION


func save_data() -> Dictionary:
	return {"career": career.to_data(), "board": board.duplicate(true), "board_seed": board_seed,
			"active": active.duplicate(true), "structure_report": structure_report.duplicate(true)}


func load_data(data: Dictionary, _from_version: int) -> void:
	career.load_data(data.get("career", {}) if data.get("career") is Dictionary else {})
	board_seed = int(data.get("board_seed", 1))
	active = (data.get("active", {}) as Dictionary).duplicate(true) if data.get("active") is Dictionary else {}
	structure_report = (data.get("structure_report", {}) as Dictionary).duplicate(true) if data.get("structure_report") is Dictionary else {}
	if data.get("board") is Array and not (data.board as Array).is_empty():
		board = (data.board as Array).duplicate(true)
		board_changed.emit()
	else:
		_deal_board(board_seed)
	active_changed.emit()


func reset_data() -> void:
	career.load_data({})
	active = {}
	structure_report = {}
	_report_sum = 0
	last_settlement = {}
	_deal_board(1)
	active_changed.emit()
