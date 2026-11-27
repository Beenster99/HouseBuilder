extends Node3D
## The asset library one category at a time, each asset with its name, to look over in
## either look (Graphics > Display > Look). Drag to orbit, wheel to zoom, WASD to move,
## Page Up and Page Down to change category, Esc for the menu.

const GAP := 0.8
const ROW_WIDTH := 28.0

var camera: Camera3D
var _root: Node3D
var _ground: MeshInstance3D
var _focus := Vector3.ZERO
var _yaw := 0.6
var _pitch := 0.5
var _dist := 30.0
var _categories: Array[String] = []
var _page := 0
var _caption: Label


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50, 35, 0)
	add_child(sun)
	_ground = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	_ground.mesh = plane
	_ground.material_override = ArtStyle.ground()
	add_child(_ground)
	_root = Node3D.new()
	add_child(_root)
	camera = Camera3D.new()
	camera.far = 2000.0
	add_child(camera)
	camera.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(16, 12)
	layer.add_child(_caption)
	_lay_out()
	Graphics.changed.connect(func() -> void:
		_ground.material_override = ArtStyle.ground()
		AssetLibrary.apply_look(_root))
	_place_camera()


## One category at a time (the whole library is too big to see at once): rows of assets
## side by side on their own footprints. Page Up and Page Down change category.
func _lay_out() -> void:
	for child in _root.get_children():
		_root.remove_child(child)
		child.queue_free()
	if _categories.is_empty():
		for id in AssetLibrary.ids():
			var c := str(AssetLibrary.info(id).category)
			if not _categories.has(c):
				_categories.append(c)
		_categories.sort()
	if _categories.is_empty():
		return
	_page = posmod(_page, _categories.size())
	var category: String = _categories[_page]
	var x := 0.0
	var z := 0.0
	var row_depth := 0.0
	var count := 0
	var group := ""
	for id in AssetLibrary.ids():
		var e := AssetLibrary.info(id)
		if str(e.category) != category:
			continue
		var b := AssetLibrary.bounds(id)
		var g := str(id).get_slice(".", 1)
		if x > 0.0 and (g != group or x + b.size.x > ROW_WIDTH):
			z += row_depth + (2.5 if g != group else GAP)
			x = 0.0
			row_depth = 0.0
		group = g
		var node := AssetLibrary.make(id)
		node.position = Vector3(x - b.position.x, maxf(0.0, -b.position.y), z - b.position.z)
		_root.add_child(node)
		var label := Label3D.new()
		label.text = str(e.label)
		label.font_size = 28
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(0.1, 0.1, 0.1)
		label.outline_modulate = Color(1, 1, 1)
		label.position = Vector3(x + b.size.x / 2.0, b.size.y + maxf(0.0, -b.position.y) + 0.25, z + b.size.z / 2.0)
		_root.add_child(label)
		x += b.size.x + GAP
		row_depth = maxf(row_depth, b.size.z)
		count += 1
	# Start at the first rows; WASD and the wheel move along them.
	var length := z + row_depth
	_focus = Vector3(ROW_WIDTH / 2.0, 1.0, minf(8.0, length / 2.0))
	_dist = 30.0
	(_ground.mesh as PlaneMesh).size = Vector2(ROW_WIDTH + 400.0, length + 400.0)
	_ground.position = Vector3(ROW_WIDTH / 2.0, 0.0, length / 2.0)
	if _caption != null:
		_caption.text = "%s  (%d of %d categories, %d assets)   Page Up / Page Down: change category" % [category, _page + 1, _categories.size(), count]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)) != 0:
		_yaw -= event.relative.x * 0.006
		_pitch = clampf(_pitch + event.relative.y * 0.006, 0.05, 1.5)
		_place_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(1.5, _dist * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(600.0, _dist * 1.1)
		_place_camera()
	elif event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_PAGEUP or event.physical_keycode == KEY_PAGEDOWN):
		_page += 1 if event.physical_keycode == KEY_PAGEDOWN else -1
		_lay_out()
		_place_camera()
	elif event.is_action_pressed("ui_cancel"):
		Menu.open_pause()


func _process(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		move.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		move.z += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		move.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		move.x += 1.0
	if move != Vector3.ZERO:
		_focus += move.rotated(Vector3.UP, _yaw) * delta * _dist * 0.6
		_place_camera()


func _place_camera() -> void:
	var dir := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	camera.position = _focus + dir * _dist
	camera.look_at(_focus)
