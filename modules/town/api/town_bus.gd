class_name TownBus
extends Node
## The firm's town (Modules.bus("town")): every contract the crew hands over and passes is
## kept, and stays standing on its real site, so the crew can walk or fly round everything
## the firm has built.
##
##   var town := Modules.bus("town") as TownBus
##   town.records()                 # TownRecord headers, oldest first
##   town.record(id)                # one header ({} for none)
##   town.on_site(site_id)          # the records built on that site
##   town.occupied_sites()          # site ids that already hold a standing building
##   town.near(pack)                # [{record, at: Vector3 in pack coordinates, own}]: what
##                                  # stands on or near that site (neighbouring packs too)
##   town.model_of(id)              # the stored BuildingModel (null until this peer has it)
##   town.make_view(id)             # a static merged mesh of it, no physics, model coords
##   town.make_site_extras(pack)    # everything near a pack, placed in its coordinates
##   town.visit(id) / town.leave()  # the crew goes to see one together ("" = the map)
##   signals: records_changed, visit_changed, here_changed
##
## The host records a passed handover from the contracts module's settled signal (found by
## name): the brief, the settlement, the crew's names and the shared building's saved data.
## Records travel in the join snapshot as headers; the buildings themselves travel with the
## visit that needs them (and the snapshot sends those of the site being visited).
## The sites module draws them on any site it shows when it offers register_view_extra.
##
## Flags: "town" (the module, records and save), "town.map" (the Our work screen, its menu
## entry and the design hall wall-screen page). Save section "town".

signal records_changed
## The crew's visit changed: visiting is a record id, or "" for the map.
signal visit_changed
## Someone came into or left the Our work screen.
signal here_changed

const FLAG := "town.map"
const SCENE := "town.map"
const SCENE_PATH := "res://modules/town/internal/town_screen.tscn"
const MENU_ENTRY := "town.map"
const MENU_ORDER := 22
const CHANNEL_ID := "town.list"
const CHANNEL_ORDER := 30
const LIST_SCRIPT := "res://modules/town/internal/town_list.gd"
const BUILDER_SCRIPT := preload("res://modules/town/internal/town_builder.gd")
const SAMPLES_SCRIPT := "res://modules/town/internal/town_samples.gd"
const SITE_EXTRA := "town.buildings"
const DEBUG_SECTION := "town.samples"
const SAVE_SECTION := "town"
const SAVE_VERSION := 1
const EV_ADD := "town.add"
const EV_VISIT := "town.visit"
const EV_HERE := "town.here"
const EV_DEMOLISHED := "town.demolished"
const EV_CLEAR := "town.clear"
## Movers: each player's walker in the town view, driven by that player.
const BODY_MOVER := "player:%d:town"
## A building on another site pack shows on this one when its origin is this close to the
## pack's terrain edge (m inside the radius).
const NEAR_MARGIN := 20.0

## The record a redevelopment contract taken now will bring down ("" for none).
func being_redeveloped() -> String:
	var a: Variant = _contracts.get("active") if _contracts != null and is_instance_valid(_contracts) else null
	return str((a as Dictionary).get("record_id", "")) if a is Dictionary else ""


## Record id being visited by the crew, "" for none.
var visiting := ""
## peer id -> {name, colour}: who is on the Our work screen.
var here: Dictionary = {}
## Tests and tools: the building to record instead of the building module's shared one.
var source_model: BuildingModel = null
var net: MultiplayerBus
var _records: Array = []
## record id -> BuildingModel.to_data() Dictionary.
var _models: Dictionary = {}
## record id -> BuildingModel, built on first use.
var _built: Dictionary = {}
var _next := 1
var _contracts: Object
## The contract being worked on (settled fires after the contracts bus clears it).
var _brief: Dictionary = {}
var _proxies: Dictionary = {}
var _design: Node
var _sites: Node


func register_module() -> void:
	Saves.register_section(SAVE_SECTION, self)
	if Flags.is_on(FLAG):
		Router.register_scene(SCENE, SCENE_PATH)
		Router.set_loading_title(SCENE, "Our work")
		Menu.register_entry(MENU_ENTRY, "Our work", SCENE, MENU_ORDER)
		Shots.register("town_map", SCENE, func(_scene: Node) -> void: add_samples(), 40)
		Shots.register("town_visit", SCENE, func(_scene: Node) -> void:
			add_samples()
			if not _records.is_empty():
				visit(str(_records[0].id)), 90)
	Menu.register_settings_section(Menu.DEBUG, DEBUG_SECTION, "Town: sample buildings", make_debug_section, 40)
	if Modules.ready_done:
		_hook()
	else:
		Modules.modules_ready.connect(_hook, CONNECT_ONE_SHOT)


func unregister_module() -> void:
	Saves.unregister_section(SAVE_SECTION)
	Menu.unregister_entry(MENU_ENTRY)
	Menu.unregister_settings_section(Menu.DEBUG, DEBUG_SECTION)
	if is_instance_valid(_design) and _design.has_method("unregister_channel"):
		_design.unregister_channel(CHANNEL_ID)
	if is_instance_valid(_sites) and _sites.has_method("unregister_view_extra"):
		_sites.unregister_view_extra(SITE_EXTRA)
	unwatch()
	unbind()


func _hook() -> void:
	var bus := Modules.bus("multiplayer") as MultiplayerBus
	if bus != null:
		bind(bus)
	var contracts := Modules.bus("contracts")
	if contracts != null:
		watch(contracts)
	var sites := Modules.bus("sites")
	if sites != null and sites.has_method("register_view_extra"):
		_sites = sites
		sites.register_view_extra(SITE_EXTRA, make_site_extras)
	var design := Modules.bus("design")
	if design != null and design.has_method("register_channel") and Flags.is_on(FLAG):
		_design = design
		design.register_channel(CHANNEL_ID, "Our work", func(_model: Variant) -> Control: return make_list(), CHANNEL_ORDER)


# --- Session ---------------------------------------------------------------------------

func bind(bus: MultiplayerBus) -> void:
	unbind()
	net = bus
	net.register_event(EV_ADD, _apply_add, _validate_host_only)
	net.register_event(EV_VISIT, _apply_visit, _validate_visit)
	net.register_event(EV_HERE, _apply_here, _validate_here)
	net.register_event(EV_DEMOLISHED, _apply_demolished, _validate_demolished)
	net.register_event(EV_CLEAR, _apply_clear, _validate_clear)
	net.register_snapshot_provider(SAVE_SECTION, self)
	if not net.peer_left.is_connected(_on_peer_left):
		net.peer_left.connect(_on_peer_left)
		net.session_ended.connect(_on_session_ended)


func unbind() -> void:
	if net == null:
		return
	for e: String in [EV_ADD, EV_VISIT, EV_HERE, EV_DEMOLISHED, EV_CLEAR]:
		net.unregister_event(e)
	net.unregister_snapshot_provider(SAVE_SECTION)
	if net.peer_left.is_connected(_on_peer_left):
		net.peer_left.disconnect(_on_peer_left)
		net.session_ended.disconnect(_on_session_ended)
	for peer: int in _proxies.keys():
		_drop_proxy(peer)
	net = null


func is_host() -> bool:
	return net == null or net.is_host()


func local_peer() -> int:
	return net.local_peer_id() if net else 1


## Listens to a contracts bus (the module's, or a test's): a passed handover is recorded.
func watch(contracts: Object) -> void:
	unwatch()
	_contracts = contracts
	contracts.connect("active_changed", _on_active_changed)
	contracts.connect("settled", _on_settled)
	_on_active_changed()


func unwatch() -> void:
	if _contracts != null and is_instance_valid(_contracts):
		if _contracts.is_connected("active_changed", _on_active_changed):
			_contracts.disconnect("active_changed", _on_active_changed)
			_contracts.disconnect("settled", _on_settled)
	_contracts = null


func _on_active_changed() -> void:
	var a: Variant = _contracts.get("active") if _contracts != null else null
	if a is Dictionary and not (a as Dictionary).is_empty():
		_brief = (a as Dictionary).duplicate(true)


func _on_settled(s: Dictionary) -> void:
	if not bool(s.get("passed", false)) or not is_host():
		return
	var brief: Dictionary = s.get("brief", {}) if s.get("brief") is Dictionary else {}
	if brief.is_empty():
		brief = _brief
	if not brief.is_empty() and str(brief.get("id", "")) != str(s.get("brief_id", brief.get("id", ""))):
		brief = {}
	if ContractDemolition.is_demolition(brief):
		# A demolition job knocks a building down; nothing new is left standing.
		return
	var model := source_model
	if model == null:
		var b := Modules.bus("building") as BuildingBus
		model = b.model if b != null else null
	if model == null or model.parts.is_empty():
		return
	add_building(model, brief, s)
	_brief = {}


## Host: records a building as handed over (what a passed handover does; the debug samples
## call it too). Returns the new record's id.
func add_building(model: BuildingModel, brief: Dictionary, settlement: Dictionary, pack: SitePack = null) -> String:
	var site: Dictionary = brief.get("site", {}) if brief.get("site") is Dictionary else {}
	var site_id := str(site.get("id", ""))
	if pack == null and site_id != "":
		var sites := Modules.bus("sites") as SitesBus
		var cur := sites.current() if sites != null else null
		pack = cur if cur != null and cur.id() == site_id else SitePool.open(site_id)
	var rid := "t%d" % _next
	var rec := TownRecord.make(rid, brief, settlement, model, crew_names(), pack)
	var payload := {"record": rec}
	payload.merge(_pack_model(model.to_data()))
	_emit(EV_ADD, payload)
	return rid


## The names of everyone in the session now (the host's name alone when solo).
func crew_names() -> PackedStringArray:
	var out := PackedStringArray()
	if net == null:
		return out
	var peers := net.peers()
	var ids: Array = peers.keys()
	ids.sort()
	for p: int in ids:
		out.append(net.player_name(p))
	return out


# --- Reading ---------------------------------------------------------------------------

func records() -> Array:
	return _records


func record(rid: String) -> Dictionary:
	for r: Dictionary in _records:
		if str(r.id) == rid:
			return r
	return {}


func on_site(site_id: String) -> Array:
	return _records.filter(func(r: Dictionary) -> bool: return str(r.site_id) == site_id and site_id != "")


## Real sites that hold one of the firm's standing buildings (contracts skips these).
func occupied_sites() -> PackedStringArray:
	var out := PackedStringArray()
	for r: Dictionary in _records:
		var s := str(r.site_id)
		if s != "" and not bool(r.get("demolished", false)) and not s in out:
			out.append(s)
	return out


## Standing records on a pack or near enough to show on it: [{record, at, own}], at the
## building origin's place in the pack's coordinates (its own site: the plot's centre at
## mean ground; a neighbouring pack's: where it stands on this terrain).
func near(pack: SitePack) -> Array:
	var out: Array = []
	if pack == null:
		return out
	var loc := pack.location()
	for r: Dictionary in _records:
		if bool(r.get("demolished", false)) or str(r.site_id) == "":
			continue
		if str(r.site_id) == pack.id():
			var p: Array = r.get("plot_origin", [0.0, 0.0])
			out.append({"record": r, "at": Vector3(float(p[0]), 0.0, float(p[1])), "own": true})
			continue
		if not loc.has("lat"):
			continue
		var off: Variant = TownRecord.offset_in(r, float(loc.lat), float(loc.lon))
		if off == null:
			continue
		var v: Vector2 = off
		if v.length() > pack.radius() - NEAR_MARGIN:
			continue
		out.append({"record": r, "at": Vector3(v.x, pack.height_at(v.x, v.y), v.y), "own": false})
	return out


func has_model(rid: String) -> bool:
	return _models.has(rid)


## The stored building, or null if this peer has not been sent it yet.
func model_of(rid: String) -> BuildingModel:
	if _built.has(rid):
		return _built[rid]
	var data: Variant = _models.get(rid)
	if not data is Dictionary:
		return null
	var m := BuildingModel.from_data(data)
	if m != null:
		_built[rid] = m
	return m


## A finished building as a static merged mesh (no physics), in its model's coordinates.
## null if this peer does not hold it.
func make_view(rid: String) -> Node3D:
	var m := model_of(rid)
	if m == null:
		return null
	var v: Node3D = BUILDER_SCRIPT.new()
	v.call("build", m, rid)
	return v


## Every standing building on or near a site pack, placed in the pack's coordinates, each
## with its plaque; null when there are none (the sites module's view extra).
func make_site_extras(pack: SitePack) -> Node3D:
	var list := near(pack)
	if list.is_empty():
		return null
	var root := Node3D.new()
	root.name = "TownBuildings"
	for n: Dictionary in list:
		var rec: Dictionary = n.record
		var view := make_view(str(rec.id))
		if view == null:
			continue
		view.position = n.at
		view.set_meta("town_record", str(rec.id))
		view.add_child(make_plaque(rec, view.call("bounds")))
		root.add_child(view)
	return root if root.get_child_count() > 0 else null


## A plaque on a post at the building's south side: the brief title, client, date and crew.
static func make_plaque(rec: Dictionary, box: AABB) -> Node3D:
	var post := Node3D.new()
	post.name = "Plaque"
	post.position = Vector3(box.get_center().x, 0.0, box.end.z + 1.6)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.04
	pm.bottom_radius = 0.04
	pm.height = 1.4
	pole.mesh = pm
	pole.position.y = 0.7
	pole.material_override = ArtStyle.material("steel", "column")
	post.add_child(pole)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.7, 1.0, 0.05)
	board.mesh = bm
	board.position.y = 1.8
	board.material_override = ArtStyle.material("timber", "fixture")
	post.add_child(board)
	var label := Label3D.new()
	label.name = "Text"
	label.text = TownRecord.plaque_text(rec)
	label.font_size = 28
	label.pixel_size = 0.004
	label.width = 390.0
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = Color(0.1, 0.1, 0.1)
	label.outline_size = 0
	label.position = Vector3(0, 1.8, 0.03)
	label.double_sided = false
	post.add_child(label)
	var back := label.duplicate() as Label3D
	back.position.z = -0.03
	back.rotation.y = PI
	post.add_child(back)
	return post


## The big-screen / screen list of the firm's buildings (kept up to date).
func make_list() -> Control:
	var l: Control = load(LIST_SCRIPT).new()
	l.call("bind", self)
	return l


## Settings > Debug: add a few sample buildings on real neighbouring sites, or clear them.
func make_debug_section() -> Control:
	var row := HBoxContainer.new()
	row.add_child(BsxTheme.button("Add sample buildings", add_samples))
	row.add_child(BsxTheme.button("Clear the town", clear))
	return row


## Testing: three finished buildings on real sites (two next door to each other).
func add_samples() -> void:
	if not is_host():
		return
	for s: Dictionary in load(SAMPLES_SCRIPT).call("samples"):
		if not on_site(str(s.brief.site.id)).is_empty():
			continue
		add_building(s.model, s.brief, s.settlement)


# --- Requests ---------------------------------------------------------------------------

## The crew goes to see a building together ("" goes back to the map).
func visit(rid: String) -> void:
	_request(EV_VISIT, {"id": rid})


func leave() -> void:
	visit("")


## Says whether this player is on the Our work screen, for everyone.
func set_here(on: bool) -> void:
	_request(EV_HERE, {"on": on})


## A building in the town was brought down (for the redevelopment demolition job).
func mark_demolished(rid: String) -> void:
	_request(EV_DEMOLISHED, {"id": rid})


## Testing: empties the town for everyone.
func clear() -> void:
	_request(EV_CLEAR, {})


func _request(ev: String, payload: Dictionary) -> void:
	if net != null:
		net.request(ev, payload)
		return
	var out: Variant = call("_validate_" + ev.get_slice(".", 1), 1, payload)
	if out is String:
		push_warning("town: %s refused: %s" % [ev, out])
	elif out is Dictionary:
		call("_apply_" + ev.get_slice(".", 1), out)


func _emit(ev: String, payload: Dictionary) -> void:
	if net != null:
		net.host_emit(ev, payload)
	else:
		call("_apply_" + ev.get_slice(".", 1), payload)


static func _pack_model(data: Dictionary) -> Dictionary:
	var raw := var_to_bytes(data)
	return {"zip": raw.compress(FileAccess.COMPRESSION_ZSTD), "size": raw.size()}


static func _unpack_model(p: Dictionary) -> Variant:
	var zip: PackedByteArray = p.get("zip", PackedByteArray())
	if zip.is_empty():
		return null
	var v: Variant = bytes_to_var(zip.decompress(int(p.get("size", 0)), FileAccess.COMPRESSION_ZSTD))
	return v if v is Dictionary else null


# --- Host side --------------------------------------------------------------------------

func _validate_host_only(sender: int, _p: Dictionary) -> Variant:
	return "only the host records buildings" if sender != 1 else _p


## The building asked for, and every building that shows on its site, go with the visit.
func _validate_visit(_sender: int, p: Dictionary) -> Variant:
	var rid := str(p.get("id", ""))
	if rid == "":
		return {"id": ""}
	var rec := record(rid)
	if rec.is_empty():
		return "that building is not in the town"
	return {"id": rid, "models": _models_for(rec)}


func _models_for(rec: Dictionary) -> Dictionary:
	var ids := [str(rec.id)]
	var site := str(rec.get("site_id", ""))
	if site != "":
		var pack := SitePool.open(site)
		for n: Dictionary in near(pack):
			if not str(n.record.id) in ids:
				ids.append(str(n.record.id))
	var out := {}
	for id: String in ids:
		if _models.has(id):
			out[id] = _pack_model(_models[id])
	return out


func _validate_here(sender: int, p: Dictionary) -> Variant:
	return {"peer": sender, "on": bool(p.get("on", false))}


func _validate_demolished(_sender: int, p: Dictionary) -> Variant:
	var rec := record(str(p.get("id", "")))
	if rec.is_empty():
		return "that building is not in the town"
	return {"id": str(rec.id), "at": int(Time.get_unix_time_from_system())}


func _validate_clear(_sender: int, _p: Dictionary) -> Variant:
	if not Flags.is_on("ui.debug_tab"):
		return "testing shortcuts are off"
	return {}


# --- Every peer -------------------------------------------------------------------------

func _apply_add(p: Dictionary) -> void:
	var rec: Dictionary = (p.get("record", {}) as Dictionary).duplicate(true)
	var rid := str(rec.get("id", ""))
	if rid == "" or not record(rid).is_empty():
		return
	_records.append(rec)
	_next = maxi(_next, int(rid.trim_prefix("t")) + 1)
	var data: Variant = _unpack_model(p)
	if data != null:
		_models[rid] = data
	records_changed.emit()


func _apply_visit(p: Dictionary) -> void:
	var models: Dictionary = p.get("models", {})
	for rid: String in models:
		if not _models.has(rid):
			var data: Variant = _unpack_model(models[rid])
			if data != null:
				_models[rid] = data
	var was := visiting
	visiting = str(p.get("id", ""))
	if was != visiting or not models.is_empty():
		visit_changed.emit()


func _apply_here(p: Dictionary) -> void:
	var peer := int(p.get("peer", 0))
	if bool(p.get("on", false)):
		here[peer] = {"name": net.player_name(peer) if net else "You",
				"colour": net.player_colour(peer) if net else Color(0.3, 0.7, 1.0)}
		if peer != local_peer():
			_add_proxy(peer)
	else:
		here.erase(peer)
		_drop_proxy(peer)
	if here.is_empty() and is_host() and visiting != "":
		# Nobody left looking: the next visitor starts at the map.
		visiting = ""
		visit_changed.emit()
	here_changed.emit()


func _apply_demolished(p: Dictionary) -> void:
	for r: Dictionary in _records:
		if str(r.id) == str(p.get("id", "")):
			r["demolished"] = true
			r["demolished_at"] = int(p.get("at", 0))
	records_changed.emit()


func _apply_clear(_p: Dictionary) -> void:
	_records.clear()
	_models.clear()
	_built.clear()
	visiting = ""
	records_changed.emit()
	visit_changed.emit()


# Other players' walkers in the town view: streamed bodies, as walk-inside does.

func _add_proxy(peer: int) -> void:
	if _proxies.has(peer) or net == null:
		return
	var body := Node3D.new()
	body.name = "TownWalker_%d" % peer
	add_child(body)
	net.register_mover(BODY_MOVER % peer, body)
	_proxies[peer] = body


func _drop_proxy(peer: int) -> void:
	var body: Node3D = _proxies.get(peer)
	if body == null:
		return
	_proxies.erase(peer)
	if net:
		net.unregister_mover(BODY_MOVER % peer)
	if is_instance_valid(body):
		body.queue_free()


## Where another player in the town view is (their streamed body), or null.
func proxy_body(peer: int) -> Node3D:
	return _proxies.get(peer)


func _on_peer_left(peer: int, _why: String) -> void:
	if here.erase(peer):
		_drop_proxy(peer)
		here_changed.emit()


func _on_session_ended(_why: String) -> void:
	for peer: int in here.keys():
		if peer != local_peer():
			here.erase(peer)
			_drop_proxy(peer)
	here_changed.emit()


# --- Snapshot (joiners) and save -------------------------------------------------------

func get_net_snapshot() -> Dictionary:
	var models := {}
	var rec := record(visiting)
	if not rec.is_empty():
		models = _models_for(rec)
	var peers: Array = here.keys()
	return {"records": _records.duplicate(true), "next": _next, "visiting": visiting, "models": models, "here": peers}


func apply_net_snapshot(data: Dictionary) -> void:
	_records = (data.get("records", []) as Array).duplicate(true)
	_next = int(data.get("next", 1))
	_models.clear()
	_built.clear()
	records_changed.emit()
	for peer: Variant in data.get("here", []):
		_apply_here({"peer": int(peer), "on": true})
	_apply_visit({"id": str(data.get("visiting", "")), "models": data.get("models", {})})


func save_version() -> int:
	return SAVE_VERSION


func save_data() -> Dictionary:
	return {"records": _records.duplicate(true), "models": _models.duplicate(true), "next": _next}


func load_data(data: Dictionary, _from_version: int) -> void:
	_records.clear()
	for r: Variant in data.get("records", []):
		if r is Dictionary:
			var rec: Dictionary = (r as Dictionary).duplicate(true)
			for k: String in ["tier", "days", "handed_over", "parts", "demolished_at"]:
				rec[k] = int(rec.get(k, 0))
			_records.append(rec)
	_models = (data.get("models", {}) as Dictionary).duplicate(true) if data.get("models") is Dictionary else {}
	_built.clear()
	_next = int(data.get("next", _records.size() + 1))
	visiting = ""
	records_changed.emit()
	visit_changed.emit()


func reset_data() -> void:
	load_data({}, SAVE_VERSION)
