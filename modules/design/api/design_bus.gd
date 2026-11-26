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
##
## Features (Flags): "design" (the module), "design.room" (the room scene, which is where
## Start on the main menu goes).

signal actions_changed

const ROOM_SCENE := "design.room"
const ROOM_FLAG := "design.room"
const START_PRIORITY := 20
const SETTINGS := "design"

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
