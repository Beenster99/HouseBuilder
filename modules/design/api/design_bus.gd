class_name DesignBus
extends Node
## The design room module's bus (Modules.bus("design")): the shared drafting room where the
## crew draws the building together on a snap grid. The building itself is the building
## module's model; this module is the tools, cursors, selections, soft locks, the cost panel
## and the design library.
##
## Other modules add buttons to the room's top bar (the timelapse's "Build it"):
##   var design := Modules.bus("design") as DesignBus
##   design.register_action("timelapse.build", "Build it", func(model: BuildingModel) -> void: ..., 50)
## and views over the building that each player can switch to (the engineer's stresses):
##   design.register_overlay("structure.stress", "Engineer", func(model) -> Dictionary: return {"p3": Color.RED}, make_panel)
##   design.refresh_overlay("structure.stress")   # after a new report
##
## Features (Flags): "design" (the module), "design.room" (the room scene, which is where
## Start on the main menu goes).

signal actions_changed
## An overlay was added or removed.
signal overlays_changed
## An overlay's colours or panel changed (refresh_overlay); rooms showing it redraw.
signal overlay_changed(id: String)
## A side panel was added or removed.
signal panels_changed
## pulse() was called; the open room shares it with every player.
signal pulse_requested(ids: PackedStringArray)
## The room and object palettes changed (a group was registered, or refresh_palette()).
signal palette_changed
## A palette row was clicked: kind "rooms" or "objects", id (room type, catalog kind or a
## registered group's item) and source (that group's id, or ""). Kits shows its preview.
signal palette_previewed(kind: String, id: String, source: String)

const ROOM_SCENE := "design.room"
const ROOM_FLAG := "design.room"
## The design hall (BSX's design room): walls of screens, the holotable, and the designer at
## the table. Start goes here while its flag is on, else straight to the designer.
const HALL_SCENE := "design.hall"
const HALL_FLAG := "design.hall"
const START_PRIORITY := 20
const SETTINGS := "design"

## Views other modules lay over the building (the engineer's stresses, the services runs):
## id -> {label, tints: Callable(model) -> {entry id: Color}, panel: Callable() -> Control, order}.
## Each player picks the view they look through on the room's top bar; Architect is none.
var overlays: Dictionary = {}

## Always-on windows in the room's right-hand column, whatever the View (the engineer's live
## assessment): id -> {title, make: Callable(model) -> Control, order}. Each player can fold one.
var panels: Dictionary = {}

## Buttons other modules put on the room's top bar: id -> {label, press: Callable(model), order}.
var actions: Dictionary = {}
## Extra palette groups from other modules: "<kind>:<id>" -> {kind, id, title, items, order}.
var palette_extra: Dictionary = {}
## Fittings by what they're for (catalog kind -> group id), as walk-inside's Tab menu has
## them; unlisted fittings go to "other".
const FIXTURE_GROUP := {
	"bed_single": "sleeping", "bed_double": "sleeping", "hospital_bed": "care", "cell_bench": "care",
	"wc": "bathroom", "basin": "bathroom", "bath": "bathroom", "shower": "bathroom",
	"kitchen_unit": "kitchen", "dining_table": "kitchen", "sofa": "living",
	"desk_office": "work", "desk_pupil": "work", "desk_teacher": "work", "reception_desk": "work",
	"hall_chair": "work", "locker": "work",
	"consumer_unit": "services", "water_main": "services", "boiler": "services", "soil_stack": "services",
}
const OBJECT_GROUPS: Array = [
	["living", "Living"], ["sleeping", "Sleeping"], ["kitchen", "Kitchen and dining"],
	["bathroom", "Bathroom"], ["work", "Office, school and reception"], ["care", "Care and secure"],
	["services", "Services (power, water, heat)"], ["other", "Other fittings"],
	["doors", "Doors"], ["windows", "Windows"],
]
## The design room open on this machine (it sets and clears this), or null.
var open_room: Node


func register_module() -> void:
	Settings.register(SETTINGS, {"grid": 0.25, "auto_walls": true})
	if Flags.is_on(ROOM_FLAG):
		Router.register_scene(ROOM_SCENE, "res://modules/design/internal/room/design_room.tscn")
		Router.set_loading_title(ROOM_SCENE, "Design room")
		Shots.register("design_room", ROOM_SCENE)
		if Flags.is_on(HALL_FLAG):
			Router.register_scene(HALL_SCENE, "res://modules/design/internal/hall/design_hall.tscn")
			Router.set_loading_title(HALL_SCENE, "Design hall")
			Menu.set_start(HALL_SCENE, START_PRIORITY)
			Menu.register_entry(HALL_SCENE, "Design Room", HALL_SCENE, 2)
			Shots.register("design_hall", HALL_SCENE)
		else:
			Menu.set_start(ROOM_SCENE, START_PRIORITY)
			Menu.register_entry(ROOM_SCENE, "Design Room", ROOM_SCENE, 2)


func unregister_module() -> void:
	Menu.clear_start(ROOM_SCENE)
	Menu.unregister_entry(ROOM_SCENE)
	Menu.clear_start(HALL_SCENE)
	Menu.unregister_entry(HALL_SCENE)


## Adds a button to the design room's top bar; press gets the open BuildingModel.
func register_action(id: String, label: String, press: Callable, order: int = 50) -> void:
	actions[id] = {"label": label, "press": press, "order": order}
	actions_changed.emit()


func unregister_action(id: String) -> void:
	if actions.erase(id):
		actions_changed.emit()


## Actions, lowest order first: [{id, label, press, order}].
func action_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in actions:
		var a: Dictionary = actions[id].duplicate()
		a["id"] = id
		out.append(a)
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.order) < int(y.order))
	return out


## Adds a view to the room's View picker. tints(model) colours entries ({id: Color}); panel(),
## if given, makes a Control shown in the right-hand column while the view is on.
func register_overlay(id: String, label: String, tints: Callable, panel: Callable = Callable(), order: int = 50) -> void:
	overlays[id] = {"label": label, "tints": tints, "panel": panel, "order": order}
	overlays_changed.emit()


func unregister_overlay(id: String) -> void:
	if overlays.erase(id):
		overlays_changed.emit()


## Call when an overlay's colours or panel should be redrawn (a new stress report).
func refresh_overlay(id: String) -> void:
	overlay_changed.emit(id)


## Overlays, lowest order first: [{id, label, tints, panel, order}].
func overlay_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in overlays:
		var o: Dictionary = overlays[id].duplicate()
		o["id"] = id
		out.append(o)
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.order) < int(y.order))
	return out


## Adds a window to the room's right-hand column, shown whatever View is picked. make(model)
## builds its Control each time a room opens; keep it live yourself (model.changed, timers).
func register_panel(id: String, title: String, make: Callable, order: int = 50) -> void:
	panels[id] = {"title": title, "make": make, "order": order}
	panels_changed.emit()


func unregister_panel(id: String) -> void:
	if panels.erase(id):
		panels_changed.emit()


## Side panels, lowest order first: [{id, title, make, order}].
func panel_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in panels:
		var o: Dictionary = panels[id].duplicate()
		o["id"] = id
		out.append(o)
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.order) < int(y.order))
	return out


## Flashes entries for a moment in every player's room (the engineer's supports as they land).
## Call it anywhere, on the host or a client; nothing happens with no room open.
func pulse(ids: PackedStringArray) -> void:
	pulse_requested.emit(ids)


# --- Palettes -------------------------------------------------------------------------------

## What players pick from to add to the design, grouped, in display order. kind "rooms": room
## types by catalog category (and any registered groups, such as saved modules); "objects":
## furniture and fittings by asset library category, then doors and windows. The designer's
## left column and walk-inside's Tab menu both show these.
##   [{id, title, items: [{id, label, tags: PackedStringArray}]}]
## An item's id is a room type id (rooms) or a catalog kind (objects), unless its group was
## registered by another module (then it is that module's to read).
func palette_groups(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cat := (Modules.bus("building") as BuildingBus).model.catalog
	if kind == "rooms":
		var cats: Array[String] = []
		for t: String in cat.room_types:
			var c := str(cat.room_types[t].get("category", "other"))
			if not cats.has(c):
				cats.append(c)
		for c: String in cats:
			var items: Array[Dictionary] = []
			for t: String in cat.room_types_in(c):
				var rt := cat.room_type(t)
				items.append({"id": t, "label": str(rt.get("label", t)), "tags": PackedStringArray([c, t])})
			items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.label) < str(b.label))
			out.append({"id": c, "title": c.capitalize(), "items": items})
	elif kind == "objects":
		var by_id := {}
		for g: Array in OBJECT_GROUPS:
			by_id[g[0]] = {"id": g[0], "title": g[1], "items": [] as Array[Dictionary]}
		for k: String in cat.kinds_in("fixture"):
			var gid := str(FIXTURE_GROUP.get(k, "other"))
			var tags := PackedStringArray(["fixture", gid, k])
			var asset := AssetLibrary.id_for_kind(k)
			if asset != "":
				for t: Variant in AssetLibrary.info(asset).get("tags", []):
					tags.append(str(t))
			(by_id[gid].items as Array[Dictionary]).append({"id": k, "label": str(cat.kind(k).get("label", k)), "tags": tags})
		for k: String in cat.kinds_in("opening"):
			var gid := "windows" if k.begins_with("window") else "doors"
			(by_id[gid].items as Array[Dictionary]).append({"id": k, "label": str(cat.kind(k).get("label", k)),
					"tags": PackedStringArray(["opening", gid, k])})
		for g: Array in OBJECT_GROUPS:
			var items: Array[Dictionary] = by_id[g[0]].items
			if not items.is_empty():
				items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.label) < str(b.label))
				out.append(by_id[g[0]])
	var extra: Array = palette_extra.values().filter(func(g: Dictionary) -> bool: return str(g.kind) == kind)
	extra.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.order) < int(b.order))
	for g: Dictionary in extra:
		var items: Variant = (g.items as Callable).call() if (g.items as Callable).is_valid() else []
		var list: Array[Dictionary] = []
		for it: Variant in items:
			if it is Dictionary:
				list.append(it as Dictionary)
		out.append({"id": str(g.id), "title": str(g.title), "items": list, "source": str(g.id)})
	return out


## Adds a group to a palette ("rooms" or "objects"), such as saved modules. items() returns
## [{id, label, tags}]; call refresh_palette() when they change. Picking one calls
## pick(item_id) (place it however your module does).
func register_palette_group(kind: String, id: String, title: String, items: Callable, pick: Callable, order: int = 50) -> void:
	palette_extra["%s:%s" % [kind, id]] = {"kind": kind, "id": id, "title": title, "items": items, "pick": pick, "order": order}
	palette_changed.emit()


func unregister_palette_group(kind: String, id: String) -> void:
	if palette_extra.erase("%s:%s" % [kind, id]):
		palette_changed.emit()


func refresh_palette() -> void:
	palette_changed.emit()


## Items whose label or tags contain `text` (any case); groups left empty are dropped.
static func filter_groups(groups: Array[Dictionary], text: String) -> Array[Dictionary]:
	var q := text.strip_edges().to_lower()
	if q == "":
		return groups
	var out: Array[Dictionary] = []
	for g: Dictionary in groups:
		var items: Array[Dictionary] = []
		for it: Dictionary in g.items:
			var hit := str(it.label).to_lower().contains(q)
			if not hit:
				for t: String in it.get("tags", PackedStringArray()):
					if t.to_lower().contains(q):
						hit = true
						break
			if hit:
				items.append(it)
		if not items.is_empty():
			var copy := g.duplicate()
			copy["items"] = items
			out.append(copy)
	return out


# --- The open room ----------------------------------------------------------------------------

## Arms the open room's Furniture, Door or Window tool with a catalog kind. False if no room
## is open or the kind isn't placeable that way.
func use_kind(kind: String) -> bool:
	return open_room != null and bool((open_room.get("session") as Object).call("use_kind", kind))


## A placing tool in the open room: `ghost` follows the pointer (snapped), R turns it 90°, a
## click sends sync.edit(batch(ops_at.call(level, at, rot_deg))), Esc or another tool ends it.
## The room takes ownership of the ghost.
func begin_stamp(label: String, ghost: Node3D, ops_at: Callable) -> bool:
	if open_room == null:
		if ghost:
			ghost.queue_free()
		return false
	open_room.call("begin_stamp", label, ghost, ops_at)
	return true


## Rooms this player has selected in the open room.
func selected_rooms() -> PackedStringArray:
	var out := PackedStringArray()
	if open_room == null:
		return out
	var session: Object = open_room.get("session")
	var model: BuildingModel = session.get("model")
	for id: String in (session.get("presence") as DesignPresence).my_selection():
		if model.rooms.has(id):
			out.append(id)
	return out


## The level the open room is working on (0 with none open).
func current_level() -> int:
	return int((open_room.get("session") as Object).get("level")) if open_room != null else 0
