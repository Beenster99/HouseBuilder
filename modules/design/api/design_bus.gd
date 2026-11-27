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
## 3D layers (register_layer) came or went.
signal layers_changed
## A wall-screen channel came or went (register_channel).
signal channels_changed
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
## The hall as an office: a window wall onto a vista any player can change (shared).
const OFFICE_FLAG := "design.office"
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
## Big-screen channels for the design hall's wall panels only: id -> {title, make, order}.
var channels: Dictionary = {}
## The design room open on this machine (it sets and clears this), or null.
var open_room: Node
## What this player last copied (Ctrl+C in the designer), for pasting (Ctrl+V) here or in
## walk-inside: {label, size: Vector2 (plan, m), items: [{table: "rooms"|"parts", id (as it
## was, so doors find their walls), entry}]} with every entry's plan points relative to the
## copy's middle, or {}. Local to this player; a paste goes through the building's sync.
var clipboard: Dictionary = {}


func register_module() -> void:
	Settings.register(SETTINGS, {"grid": 0.25, "auto_walls": true, "snap_grid": true, "snap_guides": true})
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
			if Flags.is_on(OFFICE_FLAG) and get_node_or_null("Vista") == null:
				add_child(preload("res://modules/design/internal/hall/office/vista_sync.gd").new())
		else:
			Menu.set_start(ROOM_SCENE, START_PRIORITY)
			Menu.register_entry(ROOM_SCENE, "Design Room", ROOM_SCENE, 2)


func unregister_module() -> void:
	if get_node_or_null("Vista"):
		get_node("Vista").free()
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


## 3D layers drawn over the design (the structural engineer's stress diagram): id -> {label,
## make, toggle, is_on, order}.
var layers: Dictionary = {}


## Adds a 3D layer over the design wherever it is shown (the designer's 3D world, its small
## views, the holotable). make(model) -> Node3D in building coordinates, made once per place;
## it shows and hides itself. toggle() flips it (share it yourself if it should be shared);
## is_on() says whether it is on, for the toggles (designer's Layers menu, T at the table).
func register_layer(id: String, label: String, make: Callable, toggle: Callable, is_on: Callable, order: int = 50) -> void:
	layers[id] = {"label": label, "make": make, "toggle": toggle, "is_on": is_on, "order": order}
	layers_changed.emit()


func unregister_layer(id: String) -> void:
	if layers.erase(id):
		layers_changed.emit()


## 3D layers, lowest order first: [{id, label, make, toggle, is_on, order}].
func layer_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in layers:
		var o: Dictionary = layers[id].duplicate()
		o["id"] = id
		out.append(o)
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.order) < int(y.order))
	return out


## Flashes entries for a moment in every player's room (the engineer's supports as they land).
## Call it anywhere, on the host or a client; nothing happens with no room open.
func pulse(ids: PackedStringArray) -> void:
	pulse_requested.emit(ids)


## Short texts drawn on parts in every view of the design (plan, 3D, small views, holotable),
## by source: source -> {part id -> text}. Another module's findings ("p145  140%") show on
## the parts they are about.
signal part_tags_changed
var part_tags: Dictionary = {}

## Sets one source's tags ({} clears them).
func set_part_tags(source: String, tags: Dictionary) -> void:
	if tags.is_empty():
		if not part_tags.has(source):
			return
		part_tags.erase(source)
	else:
		if part_tags.get(source, {}) == tags:
			return
		part_tags[source] = tags.duplicate()
	part_tags_changed.emit()


## Every tag now: part id -> text (several sources' texts joined).
func all_part_tags() -> Dictionary:
	var out := {}
	for src: String in part_tags:
		for id: String in part_tags[src]:
			out[id] = (str(out[id]) + "\n" if out.has(id) else "") + str(part_tags[src][id])
	return out


## The add ops that put a copy of `clip` (see clipboard) on `level` with its middle at plan
## point `at`, turned `rot` degrees; new ids from `fresh` (unused ids, one per item). One
## sync.edit(BuildingCommands.batch(ops)) places it as one undo step.
func paste_ops(clip: Dictionary, level: int, at: Vector3, rot: float, fresh: Array) -> Array:
	return (load("res://modules/design/internal/design_session.gd") as GDScript).call("paste_ops", clip, level, at, rot, fresh)


## Takes this player to a part: selects it, goes to its level, frames the designer on it and
## flashes it (a part a note names, say). False if there is no designer open or no such part.
func focus_part(id: String) -> bool:
	pulse(PackedStringArray([id]))
	if open_room == null or not open_room.has_method("focus_part"):
		return false
	return bool(open_room.call("focus_part", id))


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
		var library_groups: Array[String] = []
		for k: String in cat.kinds_in("fixture"):
			var gid := str(FIXTURE_GROUP.get(k, ""))
			if gid == "":
				# Library assets name their own group ("Furniture", "Healthcare"...).
				var title := cat.group_of(k) if cat.has_method("group_of") else "Other fittings"
				gid = "other" if title == "Fittings" or title == "" else "lib:" + title.to_lower().replace(" ", "_")
				if gid != "other" and not by_id.has(gid):
					by_id[gid] = {"id": gid, "title": title, "items": [] as Array[Dictionary]}
					library_groups.append(gid)
			var tags := PackedStringArray(["fixture", gid, k])
			for t: Variant in cat.kind(k).get("tags", []):
				tags.append(str(t))
			var asset := AssetLibrary.id_for_kind(k)
			if asset != "":
				for t: Variant in AssetLibrary.info(asset).get("tags", []):
					tags.append(str(t))
			(by_id[gid].items as Array[Dictionary]).append({"id": k, "label": str(cat.kind(k).get("label", k)), "tags": tags,
					"lock": kind_locked_tier(k, gid)})
		for k: String in cat.kinds_in("opening"):
			var gid := "windows" if k.begins_with("window") else "doors"
			(by_id[gid].items as Array[Dictionary]).append({"id": k, "label": str(cat.kind(k).get("label", k)),
					"tags": PackedStringArray(["opening", gid, k]), "lock": kind_locked_tier(k)})
		library_groups.sort()
		var order: Array[String] = []
		for g: Array in OBJECT_GROUPS:
			if g[0] == "doors":
				order.append_array(library_groups)
			order.append(str(g[0]))
		for gid: String in order:
			var items: Array[Dictionary] = by_id[gid].items
			if not items.is_empty():
				items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.label) < str(b.label))
				out.append(by_id[gid])
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


## The tier a contract firm must reach before it may use `unlock_id` ("kind:<kind>",
## "material:<id>", "roof:<gable|hip|mono>", "lib:<group>"), or 0 when it is open. Asks the
## contracts module by name (ContractsBus.locked_tier), which answers 0 outside contract mode
## or with its unlock tree off; with no contracts module everything is open.
static func locked_tier(unlock_id: String) -> int:
	var contracts := Modules.bus("contracts")
	if contracts == null or not contracts.has_method("locked_tier"):
		return 0
	return int(contracts.call("locked_tier", unlock_id))


## A catalog kind's lock: its own, or its library group's (the higher).
static func kind_locked_tier(kind: String, group := "") -> int:
	var t := locked_tier("kind:" + kind)
	if group.begins_with("lib:"):
		t = maxi(t, locked_tier(group))
	return t


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


# --- Wall-screen channels -------------------------------------------------------------------

## Adds a channel the design hall's big wall screens can flip to (the contracts board, the
## real-world sites...). make(model) -> Control builds it each time a screen shows it; it is
## drawn full size on a wall several metres across, so lay it out for a big page. Keep it
## live yourself. Side panels (register_panel) show on the walls too; a channel is for a
## bigger view than fits the designer's side column.
func register_channel(id: String, title: String, make: Callable, order: int = 50) -> void:
	channels[id] = {"title": title, "make": make, "order": order}
	channels_changed.emit()


func unregister_channel(id: String) -> void:
	if channels.erase(id):
		channels_changed.emit()


## Wall-screen channels, lowest order first: [{id, title, make, order}].
func channel_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in channels:
		var o: Dictionary = channels[id].duplicate()
		o["id"] = id
		out.append(o)
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.order) < int(y.order))
	return out
