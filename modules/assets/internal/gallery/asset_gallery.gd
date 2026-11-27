extends Node3D
## Every asset in the library, laid out in rows by category with its name, to look over in
## either look (Graphics > Display > Look). Drag to orbit, wheel to zoom, WASD to move,
## Esc for the menu.

const GAP := 0.8
const ROW_WIDTH := 28.0

var camera: Camera3D
var _root: Node3D
var _ground: MeshInstance3D
var _focus := Vector3.ZERO
var _yaw := 0.6
var _pitch := 0.5
var _dist := 30.0


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
	camera.far = 600.0
	add_child(camera)
	camera.make_current()
	_lay_out()
	Graphics.changed.connect(func() -> void:
		_ground.material_override = ArtStyle.ground()
		AssetLibrary.apply_look(_root))
	_place_camera()


## Rows by category; within a row assets stand side by side on their own footprints.
func _lay_out() -> void:
	var x := 0.0
	var z := 0.0
	var row_depth := 0.0
	var category := ""
	for id in AssetLibrary.ids():
		var e := AssetLibrary.info(id)
		var b := AssetLibrary.bounds(id)
		if b.size.x > 20.0 or b.size.z > 20.0:
			continue  # the tower crane stands on its own, behind
		if e.category != category or x + b.size.x > ROW_WIDTH:
			if category != "":
				z += row_depth + (2.5 if e.category != category else GAP)
			x = 0.0
			row_depth = 0.0
			category = e.category
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
	if AssetLibrary.has("plant.crane.tower"):
		var crane := AssetLibrary.make("plant.crane.tower")
		crane.position = Vector3(ROW_WIDTH + 12.0, 0, z / 2.0)
		_root.add_child(crane)
	_focus = Vector3(ROW_WIDTH / 2.0, 1.0, (z + row_depth) / 2.0)
	_dist = maxf(20.0, z * 0.9)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)) != 0:
		_yaw -= event.relative.x * 0.006
		_pitch = clampf(_pitch + event.relative.y * 0.006, 0.05, 1.5)
		_place_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(1.5, _dist * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(250.0, _dist * 1.1)
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
