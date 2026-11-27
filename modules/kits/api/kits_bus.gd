class_name KitsBus
extends Node
## Room modules and the object preview (Modules.bus("kits")).
##
## Modules: draw a room, put things in it, save it with a name, and it is in every player's
## palette to stamp down again, in the designer and in walk-inside. The library is shared
## with the crew through the host (KitLibrary) and kept on each player's disk.
##   var kits := Modules.bus("kits") as KitsBus
##   kits.save_room(model, "r3", "En-suite", "Bathrooms")       # "" or why not
##   var ops := kits.place_ops(model, "En-suite", level, at, 90.0)
##   sync.edit(BuildingCommands.batch(ops))
##   kits.make_ghost("En-suite")                                # Node3D, origin at the module's centre
## Names or palette item ids ("kits:En-suite") both work in place_ops and make_ghost.
##
## Object preview: click an object, a module or a room type in a palette and a small window
## shows it turning, with its size, weight, cost, power, water and so on.
##   kits.show_preview("objects", "bath")      # floating window in the viewport clicked in
##   kits.make_preview_for({id, label, tags})  # an embeddable KitPreview (walk's Tab menu)
##
## It plugs into the designer and walk-inside by name (no depends_on either way):
##   DesignBus: register_palette_group("rooms", GROUP, "Saved modules", ...) with pick ->
##     begin_stamp, refresh_palette() on library changes, palette_previewed -> preview.
##   WalkBus: set_preview_maker(make_preview_for); walk carries modules itself with
##     make_ghost and place_ops.
##
## Features (Flags): "kits" (the module), "kits.modules" (saved modules), "kits.preview"
## (the object preview), "kits.walk_preview" (it in walk-inside's Tab menu).

signal library_changed

const MODULES_FLAG := "kits.modules"
const PREVIEW_FLAG := "kits.preview"
## The preview in walk-inside's Tab menu (walk then shows it before TAKE).
const WALK_PREVIEW_FLAG := "kits.walk_preview"
## The palette group the saved modules show in (in the "rooms" palette).
const GROUP := "kits.modules"
const GROUP_TITLE := "Saved modules"
## Palette item ids for modules: PREFIX + name.
const PREFIX := "kits:"
const TAG := "module"
const KitMesh := preload("res://modules/kits/internal/kit_mesh.gd")
const PreviewWindow := preload("res://modules/kits/internal/preview_window.gd")
const C := preload("res://modules/building/api/building_commands.gd")

var library := KitLibrary.new()
var _design: Node = null
var _walk: Node = null
## viewport -> the floating preview window in it
var _windows: Dictionary = {}


func register_module() -> void:
	library.load_local()
	library.changed.connect(_on_library_changed)
	if Modules.ready_done:
		_hook()
	else:
		Modules.modules_ready.connect(_hook, CONNECT_ONE_SHOT)


func unregister_module() -> void:
	hide_preview()
	library.unbind()
	if _design and is_instance_valid(_design):
		if _design.has_method("unregister_palette_group"):
			_design.call("unregister_palette_group", "rooms", GROUP)
		if _design.has_signal("palette_previewed") and _design.is_connected("palette_previewed", _on_palette_previewed):
			_design.disconnect("palette_previewed", _on_palette_previewed)
	if _walk and is_instance_valid(_walk):
		if _walk.has_method("set_preview_maker"):
			_walk.call("set_preview_maker", Callable())
	_design = null
	_walk = null


func _hook() -> void:
	library.bind(Modules.bus("multiplayer"))
	hook_design(Modules.bus("design"))
	hook_walk(Modules.bus("walk"))


func modules_on() -> bool:
	return Flags.is_on(MODULES_FLAG)


func preview_on() -> bool:
	return Flags.is_on(PREVIEW_FLAG)


# --- Modules -------------------------------------------------------------------------------

## Saves room `room_id` of `model` and what is in it as a module, shared with the crew.
## Returns "" or why not (no such room, no name, a starter module's name...).
func save_room(model: BuildingModel, room_id: String, kit_name: String, group: String = "") -> String:
	if not modules_on():
		return "Modules are switched off"
	if model == null or not model.rooms.has(room_id):
		return "Select a room to save as a module"
	if kit_name.strip_edges() == "":
		return "Give the module a name"
	var kit := KitCapture.capture(model, room_id, kit_name, group)
	return library.save(kit)


func delete_module(kit_name: String) -> String:
	return library.remove(kit_name)


## A module by name or palette item id ("kits:<name>").
func has_module(kit_name: String) -> bool:
	return library.has_kit(_bare(kit_name))


func get_module(kit_name: String) -> Dictionary:
	return library.get_kit(_bare(kit_name))


## [{name, group, room_type, room_label, area, parts, author, builtin}], by group then name.
func module_list(filter: String = "", group: String = "") -> Array[Dictionary]:
	return library.list(filter, group)


func module_groups() -> PackedStringArray:
	return library.groups()


## The ops that put module `kit_name` on `level` centred on plan point `at`, turned rot_deg.
## Send them as one edit: sync.edit(BuildingCommands.batch(ops)). [] for an unknown module.
func place_ops(model: BuildingModel, kit_name: String, level: int, at: Vector3, rot_deg: float = 0.0) -> Array:
	var kit := library.get_kit(_bare(kit_name))
	if kit.is_empty() or model == null:
		return []
	return KitCapture.place_ops(model, kit, level, at, rot_deg)


## The module as a small model in the current look, its origin at the module's centre on
## the floor (where place_ops puts `at`). null for an unknown module.
func make_ghost(kit_name: String) -> Node3D:
	var kit := library.get_kit(_bare(kit_name))
	if kit.is_empty():
		return null
	var size: Array = kit.get("size", [0, 0])
	var centre := Vector3(snappedf(float(size[0]) / 2.0, 0.25), 0, snappedf(float(size[1]) / 2.0, 0.25))
	var node := KitMesh.build(KitCapture.as_model(kit, library.catalog), centre)
	node.name = "KitGhost"
	node.set_meta("kit", str(kit.name))
	return node


## A module name from a name or a palette item id.
static func _bare(kit_name: String) -> String:
	return module_name(kit_name) if kit_name.begins_with(PREFIX) else kit_name


## A palette item's module name ("" if it isn't one).
static func module_name(item_id: String) -> String:
	return item_id.substr(PREFIX.length()) if item_id.begins_with(PREFIX) else ""


## Items for the designer's palette group: [{id, label, tags}].
func palette_items() -> Array:
	var out: Array = []
	if not modules_on():
		return out
	for row: Dictionary in library.list():
		out.append({"id": PREFIX + str(row.name), "label": str(row.name),
				"tags": [TAG, str(row.group).to_lower(), str(row.room_type), str(row.room_label).to_lower()]})
	return out


func _on_library_changed() -> void:
	if _design and is_instance_valid(_design) and _design.has_method("refresh_palette"):
		_design.call("refresh_palette")
	library_changed.emit()


# --- Hooks into the designer and walk-inside ----------------------------------------------

## The designer's palette (a design bus, or a stand-in in tests).
func hook_design(design: Node) -> void:
	if design == null:
		return
	_design = design
	if modules_on() and design.has_method("register_palette_group"):
		design.call("register_palette_group", "rooms", GROUP, GROUP_TITLE, palette_items, _pick_in_designer, 5)
	if design.has_signal("palette_previewed") and not design.is_connected("palette_previewed", _on_palette_previewed):
		design.connect("palette_previewed", _on_palette_previewed)


## Walk-inside's Tab menu (a walk bus, or a stand-in in tests).
func hook_walk(walk: Node) -> void:
	if walk == null:
		return
	_walk = walk
	if preview_on() and Flags.is_on(WALK_PREVIEW_FLAG) and walk.has_method("set_preview_maker"):
		walk.call("set_preview_maker", make_preview_for)


## Double-click on a module in the designer's palette: a stamp with its ghost.
func _pick_in_designer(item_id: String) -> void:
	var n := module_name(item_id)
	if n == "" or _design == null or not _design.has_method("begin_stamp"):
		return
	var ghost := make_ghost(n)
	if ghost == null:
		return
	_design.call("begin_stamp", "Module: " + n, ghost, func(level: int, at: Vector3, rot_deg: float) -> Array:
		return place_ops(_shared_model(), n, level, at, rot_deg))


func _shared_model() -> BuildingModel:
	var b := Modules.bus("building") as BuildingBus
	return b.model if b else null


# --- Object preview ------------------------------------------------------------------------

## An embeddable preview of a palette item ({id, label, tags}): a catalog kind, a saved
## module (PREFIX + name) or a room type. null when there is nothing to show.
func make_preview_for(item: Dictionary) -> Control:
	if not preview_on():
		return null
	var p := KitPreview.new()
	if not _fill(p, "", str(item.get("id", ""))):
		p.free()
		return null
	return p


## A new, empty preview to put anywhere (show_kind / show_kit / show_room_type on it).
func make_preview() -> KitPreview:
	return KitPreview.new()


## Shows the floating preview for a palette row: kind "objects" or "rooms", id a catalog
## kind, room type or module item id. In `where` (a viewport), else the one the pointer is
## over. Returns the window, or null when there's nothing to show.
func show_preview(kind: String, id: String, where: Viewport = null) -> Control:
	if not preview_on():
		return null
	var vp := where if where else _clicked_viewport()
	if vp == null:
		return null
	var win: Control = _windows.get(vp)
	if win == null or not is_instance_valid(win):
		var layer := CanvasLayer.new()
		layer.name = "KitPreviewLayer"
		layer.layer = 60
		vp.add_child(layer)
		win = PreviewWindow.new()
		win.theme = BsxTheme.get_theme()
		layer.add_child(win)
		var size := vp.get_visible_rect().size
		win.position = Vector2(clampf(vp.get_mouse_position().x + 24.0, 0.0, maxf(size.x - 340.0, 0.0)),
				clampf(vp.get_mouse_position().y - 60.0, 40.0, maxf(size.y - 420.0, 40.0)))
		_windows[vp] = win
	if not _fill(win.get("preview"), kind, id):
		win.hide()
		return null
	win.show()
	return win


func hide_preview() -> void:
	for vp: Variant in _windows:
		var w: Variant = _windows[vp]
		if w is Control and is_instance_valid(w):
			(w as Control).get_parent().queue_free()
	_windows.clear()


## The open floating preview in a viewport, or null.
func preview_window(vp: Viewport) -> Control:
	var w: Variant = _windows.get(vp)
	return w if w is Control and is_instance_valid(w) else null


func _on_palette_previewed(kind: String, id: String, _source: String = "") -> void:
	show_preview(kind, id)


func _fill(p: KitPreview, kind: String, id: String) -> bool:
	var cat := library.catalog
	var n := module_name(id)
	if n != "":
		var kit := library.get_kit(n)
		if kit.is_empty():
			return false
		p.show_kit(cat, kit)
	elif cat.has_kind(id) and kind != "rooms":
		p.show_kind(cat, id)
	elif cat.has_room_type(id):
		p.show_room_type(cat, id)
	elif cat.has_kind(id):
		p.show_kind(cat, id)
	else:
		return false
	return true


## The viewport the pointer is over: the deepest SubViewport with a hovered control (the
## designer drawn inside the hall), else the main window.
func _clicked_viewport() -> Viewport:
	var tree := get_tree()
	if tree == null:
		return null
	for vp: Node in tree.root.find_children("*", "SubViewport", true, false):
		var sv := vp as SubViewport
		if sv.gui_get_hovered_control() != null:
			return sv
	return tree.root
