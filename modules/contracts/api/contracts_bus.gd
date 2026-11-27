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
##   c.abandon()                    # drop the contract (costs some XP, never a tier)
##   c.career                       # ContractCareer: money, XP and tier, unlocks
##   c.set_xp(ContractTiers.MAX_XP) # testing: jump the firm's XP (Settings > Debug)
##   c.site_offer()                 # the brief written for the real site the crew is on
##   c.locked_tier("roof:hip")      # the tier that opens an unlock id, 0 if open (unlock tree)
##   c.buy("second_crew")           # a firm upgrade (contracts.buy); c.effect("schedule_factor")
##   ContractBriefing.bbcode(brief) # any brief as the client's full briefing document
##   signals: board_changed, active_changed, settled(settlement), report_taken, career.changed
##
## While a contract is taken, a live "Contract" window sits in the design room's side column
## (DesignBus.register_panel). The "Contracts" wall-screen channel (DesignBus.register_channel,
## id "contracts.board") shows the firm's tier and XP, the board, the active brief and the
## next tier, with the full briefing document of the contract taken or the offer being read.
## Picking a real site with no contract taken deals a brief written for that site to the top
## of the board (site_offer), and the Contract window offers it. Both are reached by name, so contracts does not depend on design. Settings >
## Debug gets "Contracts: firm XP" (Max XP, next tier, reset).
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
## The design hall's big-screen channel.
const CHANNEL_ID := "contracts.board"
const CHANNEL_FLAG := "contracts.board"
const CHANNEL_ORDER := 20
const BOARD_SCRIPT := preload("res://modules/contracts/internal/contract_board.gd")
const DEBUG_SECTION := "contracts.xp"

const SAVE_SECTION := "contracts"
const SAVE_VERSION := 1
const BOARD_SIZE := 5
## Abandoning a contract costs this share of its XP (never below the tier's floor).
const ABANDON_XP_SHARE := 0.5
const EV_ACCEPT := "contracts.accept"
const EV_HANDOVER := "contracts.handover"
const EV_ABANDON := "contracts.abandon"
const EV_REPORT := "contracts.structure_report"
const EV_SET_XP := "contracts.set_xp"
const EV_SITE_BRIEF := "contracts.site_brief"
const EV_BUY := "contracts.buy"
## Tier unlocks for roof shapes, library groups and gear, and firm upgrades bought with money.
const UNLOCK_FLAG := "contracts.unlock_tree"

var career := ContractCareer.new()
var board: Array = []
var active: Dictionary = {}
## The latest stress test result for the active contract ({} until one is run).
var structure_report: Dictionary = {}
## The last handover's settlement ({} before the first).
var last_settlement: Dictionary = {}
var board_seed := 1
## The contract whose briefing document the design room should open next ("" for none): set
## when a contract is taken, cleared by the window that shows it.
var briefing_pending := ""
var net: MultiplayerBus
var _design: Node
## The building's checksum when structure_report was made: a report for an older design is
## stale and counts as untested.
var _report_sum := 0
## The model and revision report_for last checked, and what it found, so the live panel
## does not hash the whole building on every refresh.
var _checked_model: BuildingModel
var _checked_rev := -1
var _checked_fresh := false


func register_module() -> void:
	Saves.register_section(SAVE_SECTION, self)
	Menu.register_settings_section(Menu.DEBUG, DEBUG_SECTION, "Contracts: firm XP", make_debug_section, 30)
	active_changed.connect(_refresh_palette)
	career.changed.connect(_refresh_palette)
	_deal_board(board_seed)
	if Modules.ready_done:
		_hook_net()
	else:
		Modules.modules_ready.connect(_hook_net, CONNECT_ONE_SHOT)


func unregister_module() -> void:
	Saves.unregister_section(SAVE_SECTION)
	Menu.unregister_settings_section(Menu.DEBUG, DEBUG_SECTION)
	if is_instance_valid(_design):
		_design.unregister_panel(PANEL_ID)
		if _design.has_method("unregister_channel"):
			_design.unregister_channel(CHANNEL_ID)
	unbind()


func _hook_net() -> void:
	var bus := Modules.bus("multiplayer") as MultiplayerBus
	if bus != null:
		bind(bus)
	var design := Modules.bus("design")
	if design != null and design.has_method("register_panel"):
		hook_design(design)
	var st := Modules.bus("structure") as StructureBus
	if st != null and not st.report_changed.is_connected(_on_structure_report):
		st.report_changed.connect(_on_structure_report)
	var sites := Modules.bus("sites") as SitesBus
	if sites != null and not sites.site_changed.is_connected(_on_site_changed):
		sites.site_changed.connect(_on_site_changed)


## The crew moved to a real site: with no contract taken, the host deals a brief for it.
func _on_site_changed(pack: SitePack) -> void:
	_sync_panel()
	if pack == null or not active.is_empty() or (net != null and not net.is_host()):
		return
	if not site_offer(pack.id()).is_empty():
		return
	_request.call_deferred(EV_SITE_BRIEF, {"site": pack.id()})


## The brief on the board written for a site (the current one by default), {} for none.
func site_offer(site_id: String = "") -> Dictionary:
	if site_id == "":
		var sites := Modules.bus("sites") as SitesBus
		var cur := sites.current() if sites != null else null
		if cur == null:
			return {}
		site_id = cur.id()
	for b: Dictionary in board:
		if bool(b.get("for_site", false)) and str((b.get("site", {}) as Dictionary).get("id", "")) == site_id:
			return b
	return {}


## Deals a brief written for a real site to the top of the board (what picking a site does).
func deal_site_brief(site_id: String) -> void:
	_request(EV_SITE_BRIEF, {"site": site_id})


## The structure module's stress test finished (it fires on every peer with the host's report).
func _on_structure_report(report: StructureReport) -> void:
	if report != null:
		_take_report(report.brief_result())


func _take_report(report: Dictionary) -> void:
	structure_report = report.duplicate(true)
	var m := building()
	_report_sum = m.checksum() if m != null else 0
	_checked_model = null
	report_taken.emit()


## Shows the Contract window in a design bus (or a stand-in in tests) while a contract is taken.
func hook_design(design: Node) -> void:
	_design = design
	if design.has_method("register_channel") and Flags.is_on(CHANNEL_FLAG):
		design.register_channel(CHANNEL_ID, "Contracts", make_board, CHANNEL_ORDER)
	if not active_changed.is_connected(_sync_panel):
		active_changed.connect(_sync_panel)
	_sync_panel()


func _sync_panel() -> void:
	if not is_instance_valid(_design) or not Flags.is_on(PANEL_FLAG):
		return
	if active.is_empty() and site_offer().is_empty():
		_design.unregister_panel(PANEL_ID)
	else:
		_design.register_panel(PANEL_ID, "Contract", make_panel, PANEL_ORDER)


## The live Contract window for a building (the design room calls this as it opens).
func make_panel(model: BuildingModel) -> Control:
	var p: RichTextLabel = PANEL_SCRIPT.new()
	p.name = "ContractPanel"
	p.setup(self, model if model != null else building())
	return p


## The big-screen Contracts page (the design hall's wall screens call this).
func make_board(model: BuildingModel = null) -> Control:
	var b: Control = BOARD_SCRIPT.new()
	b.name = "ContractBoard"
	b.setup(self, model if model != null else building())
	return b


## Settings > Debug: the firm's XP, with Max XP, next tier and reset buttons.
func make_debug_section() -> Control:
	var box := VBoxContainer.new()
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info)
	var row := HBoxContainer.new()
	box.add_child(row)
	var buttons := [["Max XP", func() -> void: set_xp(ContractTiers.MAX_XP)], ["Next tier", _debug_next_tier],
			["+1,000 XP", func() -> void: set_xp(career.xp + 1000)], ["Reset XP", func() -> void: set_xp(0)]]
	for b: Array in buttons:
		var btn := Button.new()
		btn.text = str(b[0])
		btn.name = str(b[0]).replace(" ", "").replace(",", "").replace("+", "Plus")
		btn.pressed.connect(b[1])
		row.add_child(btn)
	var refresh_info := func() -> void:
		if is_instance_valid(info):
			var p := career.progress()
			info.text = "Tier %d, %s: %s.%s" % [int(p.tier), str(p.name), ContractTiers.xp_text(career.xp),
					" Next: tier %d at %s." % [int(p.tier) + 1, ContractTiers.xp_text(int(p.next))] if int(p.next) >= 0 else " Top tier."]
	career.changed.connect(refresh_info)
	box.tree_exiting.connect(func() -> void:
		if career.changed.is_connected(refresh_info):
			career.changed.disconnect(refresh_info))
	refresh_info.call()
	return box


func _debug_next_tier() -> void:
	var p := career.progress()
	set_xp(int(p.next) if int(p.next) >= 0 else career.xp)


## Ties the board and contract to a session (tests bind their own buses).
func bind(bus: MultiplayerBus) -> void:
	unbind()
	net = bus
	net.register_event(EV_ACCEPT, _apply_accept, _validate_accept)
	net.register_event(EV_HANDOVER, _apply_handover, _validate_handover)
	net.register_event(EV_ABANDON, _apply_abandon, _validate_abandon)
	net.register_event(EV_REPORT, _apply_report, _validate_report)
	net.register_event(EV_SET_XP, _apply_set_xp, _validate_set_xp)
	net.register_event(EV_SITE_BRIEF, _apply_site_brief, _validate_site_brief)
	net.register_event(EV_BUY, _apply_buy, _validate_buy)
	net.register_snapshot_provider(SAVE_SECTION, self)


func unbind() -> void:
	if net == null:
		return
	for e: String in [EV_ACCEPT, EV_HANDOVER, EV_ABANDON, EV_REPORT, EV_SET_XP, EV_SITE_BRIEF, EV_BUY]:
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
	return ContractValidator.assess(_with_deals(active), m, report_for(m))


## The brief with the firm's supplier deal on it (ContractValidator reads brief.discount).
func _with_deals(b: Dictionary) -> Dictionary:
	var share := effect("material_discount")
	if share <= 0.0 or career.deal_material == "":
		return b
	var out := b.duplicate()
	out["discount"] = {career.deal_material: share}
	return out


## The tier a firm must reach before it may use an unlock id ("kind:<kind>", "material:<id>",
## "roof:<shape>", "lib:<group>", "gear:<id>"), or 0 when it is open. Always 0 with the
## unlock tree off, or with no contract taken (sandbox and free design).
func locked_tier(unlock_id: String) -> int:
	if not Flags.is_on(UNLOCK_FLAG) or active.is_empty():
		return 0
	var m := building()
	var t := ContractCareer.tier_of(unlock_id, m.catalog if m != null else BuildingCatalog.default_catalog())
	return t if t > career.tier() else 0


## A firm upgrade's effect (internal/unlocks.gd UPGRADES), or fallback without it or with the
## unlock tree off.
func effect(name: String, fallback: float = 0.0) -> float:
	if not Flags.is_on(UNLOCK_FLAG):
		return fallback
	return career.effect(name, fallback)


## Buys a firm upgrade for everyone (option: the bulk deal's material).
func buy(upgrade_id: String, option := "") -> void:
	_request(EV_BUY, {"id": upgrade_id, "option": option})


## The stress test result if it was made for this design as it is now; {"stale": true} if
## the design has changed since; {} if there has been no test.
func report_for(m: BuildingModel) -> Dictionary:
	if structure_report.is_empty():
		return {}
	if m == null or _report_sum == 0:
		return structure_report
	if m != _checked_model or m.revision != _checked_rev:
		_checked_model = m
		_checked_rev = m.revision
		_checked_fresh = m.checksum() == _report_sum
	return structure_report if _checked_fresh else {"stale": true}


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


## Testing: sets the firm's XP (and so its tier) for every player, and deals a board for it.
func set_xp(value: int) -> void:
	_request(EV_SET_XP, {"xp": value})


func _request(ev: String, payload: Dictionary) -> void:
	if net != null:
		net.request(ev, payload)
		return
	# No session at all (tools, some tests): validate and apply here.
	var out: Variant = call("_validate_" + ev.get_slice(".", 1), 1, payload)
	if out is String:
		push_warning("contracts: %s refused: %s" % [ev, out])
	if out is Dictionary:
		call("_apply_" + ev.get_slice(".", 1), out)


# Host side

func _validate_accept(_sender: int, p: Dictionary) -> Variant:
	if not active.is_empty():
		return "finish or abandon %s first" % str(active.title)
	var b := brief(str(p.get("id", "")))
	if b.is_empty():
		return "that contract is no longer on the board"
	if int(b.get("tier", 1)) > career.tier() and not bool(b.get("patron", false)):
		return "needs a tier %d firm" % int(b.tier)
	return {"brief": b}


func _validate_handover(_sender: int, p: Dictionary) -> Variant:
	if active.is_empty():
		return "no contract taken"
	var m := building()
	if m == null:
		return "no building"
	var a := ContractValidator.assess(_with_deals(active), m, report_for(m))
	var days := int(p.get("days", active.deadline_days))
	days = ceili(days * effect("schedule_factor", 1.0))
	var s := ContractPayout.settle(active, a, {"days": days})
	return {"settlement": s, "seed": board_seed + 1}


func _validate_abandon(_sender: int, _p: Dictionary) -> Variant:
	if active.is_empty():
		return "no contract taken"
	return {"title": str(active.title), "xp": ceili(int(active.get("xp", 0)) * ABANDON_XP_SHARE)}


func _validate_report(_sender: int, p: Dictionary) -> Variant:
	return {"report": p.get("report", {}) if p.get("report") is Dictionary else {}}


func _validate_set_xp(_sender: int, p: Dictionary) -> Variant:
	if not Flags.is_on("ui.debug_tab"):
		return "testing shortcuts are off"
	return {"xp": clampi(int(p.get("xp", 0)), 0, ContractTiers.MAX_XP * 10), "seed": board_seed + 1}


func _validate_buy(_sender: int, p: Dictionary) -> Variant:
	if not Flags.is_on(UNLOCK_FLAG):
		return "firm upgrades are off"
	var why := career.cannot_buy(str(p.get("id", "")), str(p.get("option", "")))
	return why if why != "" else {"id": str(p.id), "option": str(p.get("option", ""))}


func _validate_site_brief(_sender: int, p: Dictionary) -> Variant:
	if not active.is_empty():
		return "a contract is already taken"
	var site_id := str(p.get("site", ""))
	var b := ContractGenerator.for_site(site_id, board_seed * 7919 + site_id.hash() % 100000, career.tier())
	if b.is_empty():
		return "cannot read site %s" % site_id
	return {"brief": ContractClients.apply(b, career.clients) if Flags.is_on(ContractClients.FLAG) else b}


# Every peer

func _apply_accept(p: Dictionary) -> void:
	active = (p.get("brief", {}) as Dictionary).duplicate(true)
	briefing_pending = str(active.get("id", ""))
	# A contract on a real plot puts that site in play for the crew (the host asks once).
	var site_id := str((active.get("site", {}) as Dictionary).get("id", "")) if active.get("site") is Dictionary else ""
	var sites := Modules.bus("sites") as SitesBus
	if site_id != "" and sites != null and (net == null or net.is_host()):
		var cur := sites.current()
		if cur == null or cur.id() != site_id:
			sites.load_site(site_id)
	structure_report = {}
	_report_sum = 0
	_checked_model = null
	active_changed.emit()


func _apply_handover(p: Dictionary) -> void:
	var s: Dictionary = (p.get("settlement", {}) as Dictionary).duplicate(true)
	s["brief"] = active.duplicate(true)
	var before := career.tier()
	s["unlocked"] = Array(career.record(s))
	s["tier_up"] = career.tier() if career.tier() > before else 0
	s["next_unlock"] = career.next_unlock()
	last_settlement = s
	active = {}
	structure_report = {}
	_report_sum = 0
	_checked_model = null
	_deal_board(int(p.get("seed", board_seed + 1)))
	active_changed.emit()
	settled.emit(s)


func _apply_abandon(p: Dictionary) -> void:
	career.lose_xp(int(p.get("xp", 0)))
	if Flags.is_on(ContractClients.FLAG):
		career.record_abandon(active)
	active = {}
	structure_report = {}
	_report_sum = 0
	_checked_model = null
	active_changed.emit()


func _apply_report(p: Dictionary) -> void:
	_take_report(p.get("report", {}))


func _apply_buy(p: Dictionary) -> void:
	career.buy(str(p.id), str(p.get("option", "")))
	_refresh_palette()


## Locks follow the tier: the design palette greys and frees items (asked by name).
func _refresh_palette() -> void:
	var design := Modules.bus("design")
	if design != null and design.has_signal("palette_changed"):
		design.emit_signal("palette_changed")


func _apply_site_brief(p: Dictionary) -> void:
	var b: Dictionary = (p.get("brief", {}) as Dictionary).duplicate(true)
	if b.is_empty():
		return
	board = board.filter(func(o: Dictionary) -> bool: return not bool(o.get("for_site", false)))
	board.insert(0, b)
	board.resize(mini(board.size(), BOARD_SIZE))
	board_changed.emit()
	_sync_panel()


func _apply_set_xp(p: Dictionary) -> void:
	career.set_xp(int(p.get("xp", 0)))
	_deal_board(int(p.get("seed", board_seed + 1)))


func _deal_board(seed: int) -> void:
	board_seed = seed
	var done: Array = []
	for h: Dictionary in career.history:
		if h.passed:
			done.append(str(h.brief_id))
	board = ContractGenerator.board(board_seed, career.tier(), BOARD_SIZE, done)
	board = ContractClients.apply_board(board, career.clients, board_seed, career.tier())
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
	_checked_model = null
	last_settlement = {}
	_deal_board(1)
	active_changed.emit()
