class_name DesignLayers
extends Node3D
## Holds every registered 3D layer (DesignBus.register_layer) for one place the design is
## shown, in building coordinates: put it beside the DesignView with the same transform. Each
## layer's node is made once (make(model)) and shows and hides itself.

var model: BuildingModel
var nodes: Dictionary = {}  # layer id -> Node3D
## The DesignView beside it: drawn see-through while any layer is on.
var view: Node3D
var _age := 0.0
## DesignBus.part_tags drawn on their parts (red labels), redrawn when they or the model change.
var tags: Node3D
var _tags_key := ""
var _tags_age := 1.0
const TAG_COLOUR := Color(0.85, 0.12, 0.1)


func _init(p_model: BuildingModel = null, p_view: Node3D = null) -> void:
	model = p_model
	view = p_view
	name = "Layers"


func _ready() -> void:
	var design := Modules.bus("design") as DesignBus
	if design == null:
		return
	design.layers_changed.connect(sync)
	design.part_tags_changed.connect(func() -> void: _tags_age = 1.0)
	sync()


func _process(delta: float) -> void:
	_tags_age += delta
	if _tags_age >= 0.25:
		_tags_age = 0.0
		_update_tags()
	_age += delta
	if _age < 0.25 or view == null or not is_instance_valid(view) or (nodes.is_empty() and float(view.get("ghost")) == 0.0):
		return
	_age = 0.0
	view.call("set_ghost", any_on())


func _update_tags() -> void:
	var design := Modules.bus("design") as DesignBus
	if design == null or model == null:
		return
	var all := design.all_part_tags()
	var key := "%d|%s" % [model.revision, str(all)] if not all.is_empty() else ""
	if key == _tags_key:
		return
	_tags_key = key
	if tags == null:
		tags = Node3D.new()
		tags.name = "PartTags"
		add_child(tags)
	for c in tags.get_children():
		tags.remove_child(c)
		c.queue_free()
	for id: String in all:
		if not model.parts.has(id):
			continue
		var bb: AABB = model.aabb_of(id)
		var l := Label3D.new()
		l.name = "Tag_" + id
		l.text = str(all[id])
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0011
		l.font_size = 22
		l.outline_size = 7
		l.outline_modulate = Color(1, 1, 1, 0.9)
		l.modulate = TAG_COLOUR
		l.render_priority = 3
		l.position = Vector3(bb.get_center().x, bb.end.y + 0.15, bb.get_center().z)
		tags.add_child(l)


## True while any registered layer is on.
static func any_on() -> bool:
	var design := Modules.bus("design") as DesignBus
	for l: Dictionary in design.layer_list():
		if (l.is_on as Callable).is_valid() and bool((l.is_on as Callable).call()):
			return true
	return false


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
