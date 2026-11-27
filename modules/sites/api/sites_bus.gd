class_name SitesBus
extends Node
## Sites module bus (Modules.bus("sites")): real-world plots from site packs (tools/osm).
##
##   var sites := Modules.bus("sites") as SitesBus
##   sites.load_site("bath-hillside-garages")      # any player; the host loads and shares it
##   sites.site_changed.connect(_on_site)          # every peer, with the same pack
##   add_child(sites.make_view())                  # terrain, neighbours, roads, trees, plot
##   sites.current().height_at(x, z)
##
## The host reads the pack from the pool (SitePool) and sends the whole file, compressed, as
## the event, so every player builds on the identical site; joiners get it in the snapshot.
## On the host, loading a site also writes the plot's soil into the shared building's
## design meta ("soil", "site"), which the structure module's foundations read.
##
## Flag "sites.real_sites" adds the "Real sites" picker to the main menu and the site
## viewer scene.

## The site changed (null when cleared).
signal site_changed(pack: SitePack)

const LOAD := "sites.load"
const BOARD_CHANNEL := "sites.board"
## The HUD info card naming the site the crew is building on.
## The current site's window in the design room's right-hand column (while one is loaded).
const PANEL_ID := "sites.current"
const BOARD_SCRIPT := "res://modules/sites/internal/sites_board.gd"
const CLEAR := "sites.clear"
const FLAG := "sites.real_sites"
const PICKER_SCENE := "sites.picker"
const VIEW_SCENE := "sites.view"
const SiteView := preload("res://modules/sites/internal/site_view.gd")

var _net: Object
var _pack: SitePack
## Additions drawn into every site view: id -> Callable(pack) -> Node3D (register_view_extra).
var _extras: Dictionary = {}
var _design: Node
var _payload: Dictionary = {}


func register_module() -> void:
	attach(Modules.bus("multiplayer"))
	if Flags.is_on(FLAG):
		Router.register_scene(PICKER_SCENE, "res://modules/sites/internal/picker_screen.tscn")
		Router.register_scene(VIEW_SCENE, "res://modules/sites/internal/site_screen.tscn")
		Router.set_loading_title(VIEW_SCENE, "Real site")
		Menu.register_entry(PICKER_SCENE, "Real sites", PICKER_SCENE, 20)
		Shots.register("sites_picker", PICKER_SCENE)
		Shots.register("sites_bath", VIEW_SCENE, func(_scene: Node) -> void: load_site("bath-hillside-garages"), 60)
		_hook_design.call_deferred()


func unregister_module() -> void:
	Menu.unregister_entry(PICKER_SCENE)
	if is_instance_valid(_design):
		_design.unregister_channel(BOARD_CHANNEL)
		if _design.has_method("unregister_panel"):
			_design.unregister_panel(PANEL_ID)
	_design = null
	if _net:
		_net.unregister_event(LOAD)
		_net.unregister_event(CLEAR)
		_net.unregister_snapshot_provider("sites")
	_net = null


## The "Real-world sites" page on the design hall's wall screens, when the design module is
## loaded (found by name, so sites does not depend on it).
func _hook_design() -> void:
	var design := Modules.bus("design")
	if design == null or not design.has_method("register_channel"):
		return
	_design = design
	design.register_channel(BOARD_CHANNEL, "Real-world sites", func(_model: Variant) -> Control: return make_board(), 40)
	_show_panel()


## The site's window in the design room's side column while a site is loaded; none without.
func _show_panel() -> void:
	if not is_instance_valid(_design) or not _design.has_method("register_panel"):
		return
	if _pack == null:
		_design.unregister_panel(PANEL_ID)
		return
	_design.register_panel(PANEL_ID, "Site: %s" % _pack.title(), func(_model: Variant) -> Control: return make_site_panel(), 25)


## The current site in brief, for the side column: where, how big, the ground, difficulty
## and access.
func make_site_panel() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	if _pack == null:
		return box
	var lines := PackedStringArray([_pack.location_text(),
			"Plot %s. Ground: %s." % [_pack.plot_size_text(), _pack.soil().replace("_", " ")],
			"Difficulty %d of 5, cost × %.2f." % [_pack.rating(), _pack.cost_multiplier_hint()]])
	var roads := _pack.access()
	lines.append("Access: %s." % (", ".join(roads.map(func(r: Dictionary) -> String:
			return str(r.get("name", r.get("road", "road"))))) if not roads.is_empty() else "no road access"))
	lines.append("The plot is centred on the design's origin; the orange outline is its boundary.")
	for t in lines:
		var l := Label.new()
		l.text = t
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(300, 0)
		box.add_child(l)
	return box


## The wall-screen page: the site pool and the current site (kept up to date).
func make_board() -> Control:
	var board: Control = load(BOARD_SCRIPT).new()
	board.call("bind", self)
	return board


## Hooks the bus to a session (the multiplayer bus, or a stand-in with the same calls).
func attach(net: Object) -> void:
	_net = net
	if _net == null:
		return
	_net.register_event(LOAD, _apply_load, _validate_load)
	_net.register_event(CLEAR, _apply_clear)
	_net.register_snapshot_provider("sites", self)


## Asks the host to load a pool site for everyone. A refusal comes back through the
## multiplayer bus's request_rejected.
func load_site(site_id: String) -> void:
	_net.request(LOAD, {"id": site_id})


func clear_site() -> void:
	_net.request(CLEAR, {})


## The loaded site, or null.
func current() -> SitePack:
	return _pack


## A fresh 3D view of the loaded site (null if none). The caller owns it.
func make_view() -> Node3D:
	return make_view_of(_pack)


## The same as make_view() for any site pack, loaded or not (e.g. looking round an earlier
## site without making it the crew's current site). null for a null pack.
func make_view_of(pack: SitePack) -> Node3D:
	if pack == null:
		return null
	var view: Node3D = SiteView.new()
	view.build(pack)
	for id: String in _extras:
		var make: Callable = _extras[id]
		if not make.is_valid():
			continue
		var extra = make.call(pack)
		if extra is Node3D:
			(extra as Node3D).name = "Extra_%s" % id.validate_node_name()
			view.add_child(extra)
	return view


## Other modules can add to every site view (in the site pack's coordinates), e.g. the
## firm's earlier buildings: make.call(pack: SitePack) returns a Node3D or null. Views made
## after this include it; re-registering an id replaces it.
func register_view_extra(id: String, make: Callable) -> void:
	_extras[id] = make


func unregister_view_extra(id: String) -> void:
	_extras.erase(id)


## The site drawn in the building model's coordinates (the plot frame: the plot's centre at
## the origin, its mean ground at y = 0), for showing it around the building in the design
## room. null when no site is loaded. The terrain, neighbours and orange plot outline.
func make_plot_view() -> Node3D:
	var view := make_view()
	if view:
		var o := _pack.plot_origin()
		view.position = Vector3(-o.x, 0.0, -o.z)
		view.name = "Site"
	return view


func _validate_load(_sender: int, payload: Dictionary) -> Variant:
	var site_id := str(payload.get("id", ""))
	var text := SitePool.text_of(site_id)
	if text == "":
		return "No site called %s" % site_id
	return pack_payload(site_id, text)


## The event payload for a site pack's text: compressed, with its size and digest.
static func pack_payload(site_id: String, text: String) -> Dictionary:
	var raw := text.to_utf8_buffer()
	return {"id": site_id, "zip": raw.compress(FileAccess.COMPRESSION_ZSTD), "size": raw.size(),
			"digest": text.md5_text()}


## The SitePack in a payload made by pack_payload() (with error set if it is damaged).
static func unpack_payload(payload: Dictionary) -> SitePack:
	var zip: PackedByteArray = payload.get("zip", PackedByteArray())
	var text := zip.decompress(int(payload.get("size", 0)), FileAccess.COMPRESSION_ZSTD).get_string_from_utf8()
	var pack := SitePack.from_text(text)
	if pack.ok() and pack.digest != str(payload.get("digest", "")):
		pack.error = "site pack changed on the way"
	return pack


func _apply_load(payload: Dictionary) -> void:
	var pack := unpack_payload(payload)
	if not pack.ok():
		push_warning("sites: %s" % pack.error)
		return
	_pack = pack
	_payload = payload
	if _net and _net.has_method("is_host") and _net.is_host():
		_tell_building(pack)
	_show_panel()
	site_changed.emit(pack)


func _apply_clear(_payload: Dictionary) -> void:
	_pack = null
	_payload = {}
	_show_panel()
	site_changed.emit(null)


func _tell_building(pack: SitePack) -> void:
	var building := Modules.bus("building") as BuildingBus
	if building == null:
		return
	building.sync.edit(BuildingCommands.set_design_meta({"soil": pack.structure_soil(), "site": pack.id()}))


func get_net_snapshot() -> Dictionary:
	return _payload.duplicate()


func apply_net_snapshot(data: Dictionary) -> void:
	if data.has("zip"):
		_apply_load(data)
	elif _pack != null:
		_apply_clear({})
