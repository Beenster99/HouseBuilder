extends Node3D
## Looks around a real site: the terrain, neighbours, roads and trees with the plot
## outlined, and the plot's problems on a panel. Opened from the Real sites picker
## (Router.args {"id": site id} loads that site for the whole crew first).
##
## Controls: right drag orbits, middle drag or W A S D pans, wheel zooms, Esc pauses.

const ORBIT_SPEED := 0.006
const PAN_SPEED := 0.0025
const KEY_PAN := 30.0
const ZOOM_STEP := 1.12

var bus: SitesBus
var camera: Camera3D
var _view: Node3D
var _focus := Vector3.ZERO
var _yaw := deg_to_rad(35.0)
var _pitch := deg_to_rad(-40.0)
var _dist := 110.0
var _orbiting := false
var _panning := false
var _title: Label
var _notes: Label
var _credits: Label


func _ready() -> void:
	bus = Modules.bus("sites") as SitesBus
	_world()
	_hud()
	bus.site_changed.connect(_show)
	var wanted := str(Router.args.get("id", ""))
	if wanted != "" and (bus.current() == null or bus.current().id() != wanted):
		bus.load_site(wanted)
	else:
		_show(bus.current())


func _world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.4, 0.58, 0.85)
	sky_mat.sky_horizon_color = Color(0.8, 0.85, 0.9)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(-35.0), 0.0)
	sun.shadow_enabled = true
	sun.light_energy = 0.8
	add_child(sun)
	camera = Camera3D.new()
	camera.far = 2000.0
	add_child(camera)
	camera.make_current()
	_place_camera()


func _hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", BsxTheme.panel_style(16))
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(420, 0)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_title = BsxTheme.hud_label("", 24)
	box.add_child(_title)
	_notes = BsxTheme.hud_label("", 15)
	_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notes.custom_minimum_size = Vector2(400, 0)
	box.add_child(_notes)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	buttons.add_child(BsxTheme.button("Back to sites", func() -> void: Router.goto(SitesBus.PICKER_SCENE)))
	var start := Menu.start()
	if not start.is_empty():
		buttons.add_child(BsxTheme.button("Design here", func() -> void:
			Router.goto(str(start.scene), start.get("args", {}))))
	_credits = BsxTheme.hud_label("", 13)
	_credits.anchor_top = 1.0
	_credits.anchor_bottom = 1.0
	_credits.offset_left = 16
	_credits.offset_top = -40
	layer.add_child(_credits)


func _show(pack: SitePack) -> void:
	if _view:
		_view.queue_free()
		_view = null
	if pack == null:
		_title.text = "Loading site..."
		_notes.text = ""
		_credits.text = ""
		return
	_view = bus.make_view()
	add_child(_view)
	var c := pack.plot_centre()
	_focus = Vector3(c.x, pack.height_at(c.x, c.y), c.y)
	_title.text = pack.title()
	_notes.text = pack.notes_text()
	_credits.text = "  ".join(pack.attribution())
	_place_camera()


func _place_camera() -> void:
	if camera == null:
		return
	var dir := Vector3(cos(_pitch) * sin(_yaw), -sin(_pitch), cos(_pitch) * cos(_yaw))
	camera.position = _focus + dir * _dist
	camera.look_at(_focus)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				_dist = clampf(_dist / ZOOM_STEP, 10.0, 600.0)
				_place_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_dist = clampf(_dist * ZOOM_STEP, 10.0, 600.0)
				_place_camera()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			_yaw -= mm.relative.x * ORBIT_SPEED
			_pitch = clampf(_pitch - mm.relative.y * ORBIT_SPEED, deg_to_rad(-85.0), deg_to_rad(-5.0))
			_place_camera()
		elif _panning:
			_pan(Vector2(-mm.relative.x, -mm.relative.y) * PAN_SPEED * _dist)
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		Menu.open_pause()


func _process(delta: float) -> void:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		v.y -= 1
	if Input.is_key_pressed(KEY_S):
		v.y += 1
	if Input.is_key_pressed(KEY_A):
		v.x -= 1
	if Input.is_key_pressed(KEY_D):
		v.x += 1
	if v != Vector2.ZERO:
		_pan(v.normalized() * KEY_PAN * delta * maxf(_dist / 60.0, 1.0))


func _pan(d: Vector2) -> void:
	var right := Vector3(cos(_yaw), 0, -sin(_yaw))
	var fwd := Vector3(sin(_yaw), 0, cos(_yaw))
	_focus += right * d.x + fwd * d.y
	if bus.current():
		_focus.y = bus.current().height_at(_focus.x, _focus.z)
	_place_camera()
