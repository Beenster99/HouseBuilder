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
const CLEAR := "sites.clear"
const FLAG := "sites.real_sites"
const PICKER_SCENE := "sites.picker"
const VIEW_SCENE := "sites.view"
const SiteView := preload("res://modules/sites/internal/site_view.gd")

var _net: Object
var _pack: SitePack
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


func unregister_module() -> void:
	Menu.unregister_entry(PICKER_SCENE)
	if _net:
		_net.unregister_event(LOAD)
		_net.unregister_event(CLEAR)
		_net.unregister_snapshot_provider("sites")
	_net = null


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
	if _pack == null:
		return null
	var view: Node3D = SiteView.new()
	view.build(_pack)
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
	site_changed.emit(pack)


func _apply_clear(_payload: Dictionary) -> void:
	_pack = null
	_payload = {}
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
