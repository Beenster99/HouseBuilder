extends Node3D
## The holotable in the middle of the design hall (ported from BSX's HoloTable): a big table
## with a scale model of the design on it, built live as anyone edits (the same drawing the
## designer uses, every level showing, in the plain model look). Near the table the arrow keys
## turn and zoom it and the I J K L keys pan it, the same for everyone in the room. Each
## player's pointer (from the designer or a wall screen) and anyone walking inside the design
## stands on the model as a little figure in their colour.
##
## Node space: y = 0 is the floor, the table top is at TABLE_HEIGHT.

const DesignView := preload("res://modules/design/internal/room/design_view.gd")

## The table top, m: length along x, width along z.
const TABLE_SIZE := Vector2(7.0, 3.5)
const TABLE_HEIGHT := 0.95
## The footprint the model is fitted into at zoom 1, m.
const FIT := Vector2(6.3, 2.9)
## Highest the model reaches over the floor at zoom 1, m.
const MODEL_TOP := 3.4
const ZOOM_MIN := 0.3
const ZOOM_MAX := 6.0
## Turn, zoom and pan are sent at most this often while they change, s.
const SEND_EVERY := 0.15

var hall: Node
var model_root: Node3D
var view: Node3D
var turn := 0.0
var zoom := 1.0
## Pan across the table, model metres.
var pan := Vector2.ZERO
var scale_fit := 1.0
var _centre := Vector3.ZERO
var _figures: Dictionary = {}  # key -> Node3D
var _moved := false
var _send_wait := 0.0
var _fit_age := 10.0


func setup(p_hall: Node, model: BuildingModel) -> void:
	hall = p_hall
	name = "HoloTable"
	_build_table()
	model_root = Node3D.new()
	model_root.name = "Model"
	model_root.position.y = TABLE_HEIGHT + 0.01
	add_child(model_root)
	view = DesignView.new()
	view.name = "Building"
	model_root.add_child(view)
	view.call("bind", model)
	view.call("show_level", 1000)
	var screens: Node = hall.get("screens")
	screens.connect("changed", _on_screen)
	for k: String in ["holo.turn", "holo.zoom", "holo.pan"]:
		var v: Variant = screens.call("get_value", k)
		if v != null:
			_on_screen(k, v)


func _on_screen(key: String, value: Variant) -> void:
	match key:
		"holo.turn":
			turn = float(value)
		"holo.zoom":
			zoom = float(value)
		"holo.pan":
			pan = value as Vector2 if value is Vector2 else Vector2.ZERO


## Turns, zooms or pans the model for everyone (keys at the table, or tests).
func nudge(d_turn: float, zoom_by: float, d_pan: Vector2) -> void:
	turn += d_turn
	zoom = clampf(zoom * zoom_by, ZOOM_MIN, ZOOM_MAX)
	pan += d_pan.rotated(-turn) / maxf(scale_fit * zoom, 0.001)
	_moved = true


func _process(delta: float) -> void:
	_fit_age += delta
	if _fit_age > 0.5:
		_fit_age = 0.0
		_fit()
	model_root.rotation.y = turn
	model_root.scale = Vector3.ONE * scale_fit * zoom
	view.position = -_centre - Vector3(pan.x, 0, pan.y)
	view.position.y = -_centre.y
	_send(delta)
	_place_figures()


func _send(delta: float) -> void:
	_send_wait -= delta
	if not _moved or _send_wait > 0.0:
		return
	_moved = false
	_send_wait = SEND_EVERY
	var screens: Node = hall.get("screens")
	screens.call("set_value", "holo.turn", turn)
	screens.call("set_value", "holo.zoom", zoom)
	screens.call("set_value", "holo.pan", pan)


## Fits the model to the table: its footprint inside FIT, its height under MODEL_TOP.
func _fit() -> void:
	var box: AABB = hall.call("bounds")
	_centre = Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var long_side := maxf(box.size.x, box.size.z)
	var short_side := minf(box.size.x, box.size.z)
	scale_fit = minf(minf(FIT.x / maxf(long_side, 4.0), FIT.y / maxf(short_side, 4.0)),
			(MODEL_TOP - TABLE_HEIGHT) / maxf(box.size.y, 3.0))


## Where a point of the design (world metres) is over the table, in this node's space.
func to_table(p: Vector3) -> Vector3:
	return model_root.transform * (view.position + p)


## A little figure on the model for each player's pointer and each walker (WalkBus).
func _place_figures() -> void:
	var want := {}
	var pointers: Dictionary = hall.call("pointers")  # peer -> {at: Vector3, colour, name}
	for peer: int in pointers:
		want["p%d" % peer] = pointers[peer]
	for key: String in _figures.keys():
		if not want.has(key):
			(_figures[key] as Node).queue_free()
			_figures.erase(key)
	for key: String in want:
		var w: Dictionary = want[key]
		if not _figures.has(key):
			_figures[key] = _figure(w.colour as Color, str(w.name))
		var f: Node3D = _figures[key]
		f.position = to_table(w.at as Vector3)


func figure_count() -> int:
	return _figures.size()


func _figure(colour: Color, label_text: String) -> Node3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = 0.6
	var root := Node3D.new()
	root.name = "Figure"
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.035
	cap.height = 0.16
	body.mesh = cap
	body.material_override = mat
	body.position.y = 0.08
	root.add_child(body)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.035
	sph.height = 0.07
	head.mesh = sph
	head.material_override = mat
	head.position.y = 0.2
	root.add_child(head)
	var label := Label3D.new()
	label.text = label_text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = colour
	label.outline_size = 6
	label.font_size = 28
	label.pixel_size = 0.004
	label.position.y = 0.32
	root.add_child(label)
	add_child(root)
	return root


func _build_table() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.2, 0.22, 0.25)
	steel.metallic = 0.7
	steel.roughness = 0.4
	# A plinth under the middle, set back from the edges so people can stand close.
	_solid("Base", Vector3(TABLE_SIZE.x - 1.2, TABLE_HEIGHT - 0.1, TABLE_SIZE.y - 1.0),
			Vector3(0, (TABLE_HEIGHT - 0.1) * 0.5, 0), steel)
	var top := StandardMaterial3D.new()
	top.albedo_color = Color(0.86, 0.88, 0.9)
	top.roughness = 0.6
	_solid("Top", Vector3(TABLE_SIZE.x, 0.1, TABLE_SIZE.y), Vector3(0, TABLE_HEIGHT - 0.05, 0), top)
	# A glowing rim round the top's edge.
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(0.45, 0.9, 1.0)
	var half := TABLE_SIZE * 0.5
	for sz: float in [-1.0, 1.0]:
		_solid("Long", Vector3(TABLE_SIZE.x, 0.04, 0.06), Vector3(0, TABLE_HEIGHT + 0.022, sz * (half.y - 0.03)), glow)
		_solid("Short", Vector3(0.06, 0.036, TABLE_SIZE.y - 0.13), Vector3(sz * (half.x - 0.03), TABLE_HEIGHT + 0.02, 0), glow)
	var body := StaticBody3D.new()
	body.name = "TableBody"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(TABLE_SIZE.x, TABLE_HEIGHT, TABLE_SIZE.y)
	shape.shape = box
	shape.position.y = TABLE_HEIGHT * 0.5
	body.add_child(shape)
	add_child(body)


func _solid(id: String, sz: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = at
	mi.material_override = mat
	mi.name = id
	add_child(mi, true)
	return mi
