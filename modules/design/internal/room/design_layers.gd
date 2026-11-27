class_name DesignLayers
extends Node3D
## Holds every registered 3D layer (DesignBus.register_layer) for one place the design is
## shown, in building coordinates: put it beside the DesignView with the same transform. Each
## layer's node is made once (make(model)) and shows and hides itself.

var model: BuildingModel
var nodes: Dictionary = {}  # layer id -> Node3D


func _init(p_model: BuildingModel = null) -> void:
	model = p_model
	name = "Layers"


func _ready() -> void:
	var design := Modules.bus("design") as DesignBus
	if design == null:
		return
	design.layers_changed.connect(sync)
	sync()


## Adds the layers that are new and drops those that went.
func sync() -> void:
	var design := Modules.bus("design") as DesignBus
	for id: String in nodes.keys():
		if not design.layers.has(id):
			if is_instance_valid(nodes[id]):
				(nodes[id] as Node).queue_free()
			nodes.erase(id)
	for l: Dictionary in design.layer_list():
		var id := str(l.id)
		if nodes.has(id) or not (l.make as Callable).is_valid():
			continue
		var n: Variant = (l.make as Callable).call(model)
		if n is Node3D:
			(n as Node3D).name = id.validate_node_name()
			add_child(n as Node3D)
			nodes[id] = n


## Flips every layer: on if any is off, else all off (T at the holotable).
static func toggle_all() -> bool:
	var design := Modules.bus("design") as DesignBus
	var list := design.layer_list()
	if list.is_empty():
		return false
	var any_off := false
	for l: Dictionary in list:
		any_off = any_off or not bool((l.is_on as Callable).call())
	for l: Dictionary in list:
		if bool((l.is_on as Callable).call()) != any_off:
			(l.toggle as Callable).call()
	return true
