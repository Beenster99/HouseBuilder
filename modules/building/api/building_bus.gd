class_name BuildingBus
extends Node
## The building module's bus (Modules.bus("building")): the building being designed, as
## data, shared by every player in the session.
##
##   var b := Modules.bus("building") as BuildingBus
##   b.model                      # the open BuildingModel (read it; never change it directly)
##   b.sync.edit(BuildingCommands.place_part("column", 0, {"at": Vector3(2, 0, 2)}))
##   b.sync.undo()  /  b.sync.redo()
##   b.model.changed.connect(...)  # or entry_added / entry_changed / entry_removed / loaded
##   b.catalog                    # BuildingCatalog: kinds, sections, room types, rates
##   BuildingQuantities.totals(b.model)   # live cost
##
## sync is bound to Modules.bus("multiplayer") once every module is ready. Tests that need
## two players in one process make their own BuildingModel + BuildingSync and bind each to
## its own MultiplayerBus.
##
## Save section "building": the open design (BuildingModel.to_data()).

const SAVE_SECTION := "building"
const SAVE_VERSION := 1

var catalog: BuildingCatalog = BuildingCatalog.default_catalog()
var model := BuildingModel.new("", "New building", catalog)
var sync := BuildingSync.new(model)


func register_module() -> void:
	Saves.register_section(SAVE_SECTION, self)
	if Modules.ready_done:
		_hook_net()
	else:
		Modules.modules_ready.connect(_hook_net, CONNECT_ONE_SHOT)


func unregister_module() -> void:
	sync.unbind()
	Saves.unregister_section(SAVE_SECTION)


func _hook_net() -> void:
	var net := Modules.bus("multiplayer") as MultiplayerBus
	if net != null:
		sync.bind(net, SAVE_SECTION)


## A fresh, empty model on the default catalog (not shared; for previews and tests).
func new_model(building_name: String = "New building") -> BuildingModel:
	return BuildingModel.new("", building_name, catalog)


# Saves provider

func save_version() -> int:
	return SAVE_VERSION


func save_data() -> Dictionary:
	return {"current": model.to_data()}


func load_data(data: Dictionary, _from_version: int) -> void:
	var cur: Variant = data.get("current")
	if cur is Dictionary and model.load_data(cur).ok:
		sync.history.clear()
	else:
		reset_data()


func reset_data() -> void:
	model.load_data(BuildingModel.new("", "New building", catalog).to_data())
	sync.history.clear()
