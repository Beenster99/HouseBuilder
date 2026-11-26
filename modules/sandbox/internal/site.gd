extends Node3D
## The Phase 0 shared site: a flat 80 m plot, an orbit camera, every player's snapped
## cursor and test crates that fall under Jolt. Crates run on the host (it drives them) and
## everyone else's copy is frozen and follows the streamed transform.
##
## Controls: right drag orbits, middle drag or WASD pans, wheel zooms, left click drops a
## crate at the cursor, C clears the crates, Esc pauses.

const ORBIT_SPEED := 0.006
const PAN_SPEED := 0.0025
const KEY_PAN := 14.0
const ZOOM_STEP := 1.12
const MIN_DIST := 4.0
const MAX_DIST := 140.0
const GROUND := Color(0.55, 0.6, 0.5)
const CRATE := Color(0.78, 0.6, 0.38)

var bus: SandboxBus
var net: MultiplayerBus
var camera: Camera3D
var _focus := Vector3.ZERO
var _yaw := deg_to_rad(35.0)
var _pitch := deg_to_rad(-38.0)
var _dist := 30.0
var _orbiting := false
var _panning := false
var _cursors: Dictionary = {}  # peer id -> Node3D
var _crates: Dictionary = {}  # crate id -> RigidBody3D
var _hud: Label
var _crate_mesh := BoxMesh.new()
var _crate_shape := BoxShape3D.new()


func _ready() -> void:
	bus = Modules.bus("sandbox") as SandboxBus
	net = bus.net
	_build_world()
	_build_hud()
	for peer_id: int in net.peers():
		_add_cursor(peer_id)
	for id: String in bus.crates:
		_add_crate(id, bus.crates[id])
	bus.crate_added.connect(_add_crate)
	bus.cleared.connect(_clear_crates)
	net.peer_joined.connect(func(peer_id: int, _profile: Dictionary) -> void: _add_cursor(peer_id))
	net.peer_left.connect(func(peer_id: int, _reason: String) -> void: _remove_cursor(peer_id))
	net.session_started.connect(func(_as_host: bool) -> void: _refresh_cursors())
	net.session_ended.connect(func(_reason: String) -> void: _refresh_cursors())


func _exit_tree() -> void:
	for peer_id: int in _cursors:
		net.unregister_mover(SandboxBus.cursor_id(peer_id))
	for id: String in _crates:
		net.unregister_mover(id)


# --- World -----------------------------------------------------------------------------

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.85)
	sky_mat.sky_horizon_color = Color(0.75, 0.82, 0.9)
	sky_mat.ground_horizon_color = Color(0.6, 0.62, 0.6)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-30.0), 0.0)
	sun.shadow_enabled = true
	add_child(sun)

	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SandboxBus.PLOT_HALF * 2.0, 1.0, SandboxBus.PLOT_HALF * 2.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(SandboxBus.PLOT_HALF * 2.0, SandboxBus.PLOT_HALF * 2.0)
	mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GROUND
	mesh.material_override = mat
	ground.add_child(mesh)
	add_child(ground)
	_add_grid_lines()

	_crate_shape.size = Vector3.ONE
	var crate_mat := StandardMaterial3D.new()
	crate_mat.albedo_color = CRATE
	_crate_mesh.material = crate_mat

	camera = Camera3D.new()
	camera.far = 600.0
	add_child(camera)
	camera.make_current()
	_place_camera()


## 1 m site grid lines, every 5th darker, drawn as one immediate mesh.
func _add_grid_lines() -> void:
	var lines := ImmediateMesh.new()
	var half := SandboxBus.PLOT_HALF
	for pass_major: bool in [false, true]:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0, 0, 0, 0.35 if pass_major else 0.12)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lines.surface_begin(Mesh.PRIMITIVE_LINES, mat)
		for i in range(-int(half), int(half) + 1):
			if (i % 5 == 0) != pass_major:
				continue
			lines.surface_add_vertex(Vector3(i, 0.01, -half))
			lines.surface_add_vertex(Vector3(i, 0.01, half))
			lines.surface_add_vertex(Vector3(-half, 0.01, i))
			lines.surface_add_vertex(Vector3(half, 0.01, i))
		lines.surface_end()
	var node := MeshInstance3D.new()
	node.name = "Grid"
	node.mesh = lines
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.name = "SiteHud"
	_hud.position = Vector2(24, 20)
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_color", Color.WHITE)
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)


# --- Cursors ---------------------------------------------------------------------------

func _refresh_cursors() -> void:
	for peer_id: int in _cursors.keys():
		_remove_cursor(peer_id)
	for peer_id: int in net.peers():
		_add_cursor(peer_id)


func _add_cursor(peer_id: int) -> void:
	if _cursors.has(peer_id):
		return
	var colour := net.player_colour(peer_id)
	var root := Node3D.new()
	root.name = "Cursor_%d" % peer_id
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.28
	torus.outer_radius = 0.38
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.emission_enabled = true
	mat.emission = colour
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	ring.position.y = 0.03
	root.add_child(ring)
	var post := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.03
	cyl.height = 1.2
	post.mesh = cyl
	post.material_override = mat
	post.position.y = 0.6
	root.add_child(post)
	var tag := Label3D.new()
	tag.text = net.player_name(peer_id)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.modulate = colour
	tag.outline_modulate = Color(0, 0, 0, 0.8)
	tag.font_size = 48
	tag.pixel_size = 0.01
	tag.position.y = 1.5
	root.add_child(tag)
	add_child(root)
	_cursors[peer_id] = root
	print("Site: %s's cursor (peer %d) is on the site" % [net.player_name(peer_id), peer_id])
	net.register_mover(SandboxBus.cursor_id(peer_id), root)


func _remove_cursor(peer_id: int) -> void:
	var node: Node3D = _cursors.get(peer_id)
	if node == null:
		return
	net.unregister_mover(SandboxBus.cursor_id(peer_id))
	node.queue_free()
	_cursors.erase(peer_id)


## Where the mouse meets the ground plane, snapped to the grid; null off the plot or sky.
func cursor_point() -> Variant:
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	if hit == null:
		return null
	var p := SandboxBus.snap(hit as Vector3)
	if absf(p.x) > SandboxBus.PLOT_HALF or absf(p.z) > SandboxBus.PLOT_HALF:
		return null
	return p


# --- Crates ----------------------------------------------------------------------------

func _add_crate(id: String, at: Vector3) -> void:
	if _crates.has(id):
		return
	var body := RigidBody3D.new()
	body.name = id.replace(":", "_")
	body.mass = 40.0
	var shape := CollisionShape3D.new()
	shape.shape = _crate_shape
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _crate_mesh
	body.add_child(mesh)
	body.position = at
	body.rotation = Vector3(0.3, float(id.hash() % 628) / 100.0, 0.2)
	# Only the driving peer (the host) simulates; the others follow the stream.
	if not net.drives(id):
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.freeze = true
	add_child(body)
	_crates[id] = body
	net.register_mover(id, body)


func _clear_crates() -> void:
	for id: String in _crates:
		net.unregister_mover(id)
		_crates[id].queue_free()
	_crates.clear()


func crate_count() -> int:
	return _crates.size()


# --- Camera and input ------------------------------------------------------------------

func _place_camera() -> void:
	var basis := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	camera.global_transform = Transform3D(basis, _focus + basis.z * _dist)


func _process(delta: float) -> void:
	var pan := Vector2(
			Input.get_action_strength(Keys.RIGHT) - Input.get_action_strength(Keys.LEFT),
			Input.get_action_strength(Keys.BACK) - Input.get_action_strength(Keys.FORWARD)) \
			if InputMap.has_action(Keys.RIGHT) else Vector2.ZERO
	if pan != Vector2.ZERO:
		_move_focus(pan * KEY_PAN * delta * (_dist / 30.0))
	_place_camera()
	var own: Node3D = _cursors.get(net.local_peer_id())
	var at: Variant = cursor_point()
	if own and at != null:
		own.global_position = at
	_update_hud(at)


func _move_focus(d: Vector2) -> void:
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var back := Vector3(sin(_yaw), 0.0, cos(_yaw))
	_focus += right * d.x + back * d.y
	_focus.x = clampf(_focus.x, -SandboxBus.PLOT_HALF, SandboxBus.PLOT_HALF)
	_focus.z = clampf(_focus.z, -SandboxBus.PLOT_HALF, SandboxBus.PLOT_HALF)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_dist = clampf(_dist / ZOOM_STEP, MIN_DIST, MAX_DIST)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_dist = clampf(_dist * ZOOM_STEP, MIN_DIST, MAX_DIST)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					var at: Variant = cursor_point()
					if at != null:
						bus.request_drop(at)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			_yaw -= mm.relative.x * ORBIT_SPEED
			_pitch = clampf(_pitch - mm.relative.y * ORBIT_SPEED, deg_to_rad(-85.0), deg_to_rad(-8.0))
		elif _panning:
			_move_focus(-mm.relative * PAN_SPEED * _dist)
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_C:
				bus.request_clear()
			KEY_ESCAPE:
				Menu.open_pause()
				get_viewport().set_input_as_handled()


func _update_hud(at: Variant) -> void:
	var names: PackedStringArray = []
	var peers := net.peers()
	for peer_id: int in peers:
		names.append(net.player_name(peer_id))
	var mode := "solo"
	if net.is_online():
		mode = "hosting" if net.is_host() else "joined"
	var where := "off the plot" if at == null else "%.2f, %.2f m" % [(at as Vector3).x, (at as Vector3).z]
	_hud.text = "SANDBOX SITE  ·  %s  ·  crew %d/%d: %s\ncursor %s  ·  Jolt crates %d/%d\n" \
			% [mode, peers.size(), MultiplayerBus.MAX_CREW, ", ".join(names), where,
			_crates.size(), SandboxBus.MAX_CRATES] \
			+ "left click drop crate  ·  C clear  ·  right drag orbit  ·  middle drag / WASD pan  ·  wheel zoom"
