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

const ROOM_SCENE := "design.room"
const ROOM_FLAG := "design.room"
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


func register_module() -> void:
	Settings.register(SETTINGS, {"grid": 0.25, "auto_walls": true})
	if Flags.is_on(ROOM_FLAG):
		Router.register_scene(ROOM_SCENE, "res://modules/design/internal/room/design_room.tscn")
		Router.set_loading_title(ROOM_SCENE, "Design room")
		Menu.set_start(ROOM_SCENE, START_PRIORITY)
		Menu.register_entry(ROOM_SCENE, "Design Room", ROOM_SCENE, 2)
		Shots.register("design_room", ROOM_SCENE)


func unregister_module() -> void:
	Menu.clear_start(ROOM_SCENE)
	Menu.unregister_entry(ROOM_SCENE)


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
