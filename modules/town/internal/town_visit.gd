extends Node3D
## Visiting one of the firm's buildings with the crew: its real site (terrain, neighbours,
## roads, trees) with every building the firm has put up on or near it standing there, each
## with its plaque. Orbit round from above, or walk (F) and fly (Q) about at full size.
## Buildings with no real site stand alone in the firm's yard.
##
## Everyone on the Our work screen comes along (TownBus.visit is a host event); each walker
## streams as a mover (TownBus.BODY_MOVER) and shows to the others as a figure in their colour.

const ORBIT_SPEED := 0.006
const PAN_SPEED := 0.0025
const KEY_PAN := 30.0
const ZOOM_STEP := 1.12
const WALK_SPEED := 4.5
const RUN_SPEED := 9.0
const FLY_SPEED := 14.0
const JUMP := 4.5
const GRAVITY := 9.8
const LOOK_SPEED := 0.0025
const EYE := 1.65

var bus: TownBus
var record: Dictionary = {}
var pack: SitePack
## "orbit", "walk" or "fly".
var mode := "orbit"
var camera: Camera3D
var body: CharacterBody3D
## Where the building being visited stands (its model origin), in this view's coordinates.
var home := Vector3.ZERO
var home_bounds := AABB()
## peer id -> figure.
var crew: Dictionary = {}
var _site: Node3D
var _focus := Vector3.ZERO
var _yaw := deg_to_rad(35.0)
var _pitch := deg_to_rad(-30.0)
var _dist := 60.0
var _look_yaw := 0.0
var _look_pitch := 0.0
var _orbiting := false
var _panning := false
var _me := 1
var _colliders_added := false


func setup(town: TownBus, rid: String) -> void:
	bus = town
	record = bus.record(rid)
	name = "TownVisit"
	_world()
	_place_buildings(rid)
	_add_body()
	_dist = clampf(maxf(home_bounds.size.x, home_bounds.size.z) * 2.6, 25.0, 400.0)
	_focus = home + home_bounds.get_center() * Vector3(1, 0, 1) + Vector3(0, home_bounds.size.y * 0.3, 0)
	_place_camera()
	bus.here_changed.connect(_sync_crew)
	_sync_crew()


func _exit_tree() -> void:
	if bus and bus.here_changed.is_connected(_sync_crew):
		bus.here_changed.disconnect(_sync_crew)
	if bus and bus.net:
		bus.net.unregister_mover(TownBus.BODY_MOVER % _me)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.4, 0.58, 0.86)
	sky_mat.sky_horizon_color = Color(0.8, 0.85, 0.9)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.9
	env.fog_enabled = true
	env.fog_light_color = sky_mat.sky_horizon_color
	env.fog_density = 0.0015
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-35.0), 0.0)
	sun.shadow_enabled = true
	sun.light_energy = 0.9
	sun.directional_shadow_max_distance = 400.0
	add_child(sun)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.far = 3000.0
	camera.near = 0.08
	add_child(camera)
	camera.make_current()
	ArtStyle.apply_to_camera(camera)


## The site with the town's buildings on it (the sites module's view extra puts them there),
## or a plain yard for a building with no real site.
func _place_buildings(rid: String) -> void:
	var site_id := str(record.get("site_id", ""))
	var sites := Modules.bus("sites")
	if site_id != "":
		pack = SitePool.open(site_id)
		if pack != null and not pack.ok():
			pack = null
	if pack != null and sites != null:
		if sites.has_method("make_view_of"):
			_site = sites.make_view_of(pack)
		elif sites.current() != null and sites.current().id() == site_id:
			_site = sites.make_view()
	if _site != null:
		add_child(_site)
		if _site.find_children("TownBuilding_*", "", true, false).is_empty():
			# A sites module without view extras: put the town's buildings on it here.
			var extras := bus.make_site_extras(pack)
			if extras:
				_site.add_child(extras)
		for n: Dictionary in bus.near(pack):
			if str(n.record.id) == rid:
				home = n.at
	else:
		pack = null
		_add_yard()
		var v := bus.make_view(rid)
		if v != null:
			v.add_child(TownBus.make_plaque(record, v.call("bounds")))
			add_child(v)
	var mine := building_node(rid)
	if mine != null:
		home_bounds = mine.call("bounds")


## The town's view of a building in here, or null.
func building_node(rid: String) -> Node3D:
	var found := find_children("TownBuilding_" + rid, "", true, false)
	return found[0] as Node3D if not found.is_empty() else null


func building_count() -> int:
	return find_children("TownBuilding_*", "", true, false).size()


func _add_yard() -> void:
	var g := StaticBody3D.new()
	g.name = "Yard"
	var cs := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	cs.shape = plane
	g.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1200, 1200)
	mi.mesh = pm
	mi.position.y = -0.01
	mi.material_override = ArtStyle.ground()
	g.add_child(mi)
	add_child(g)


func _add_body() -> void:
	body = CharacterBody3D.new()
	body.name = "Walker"
	body.collision_layer = 0
	body.collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	body.add_child(cs)
	add_child(body)
	body.position = spawn_point()
	_me = bus.local_peer()
	if bus.net:
		bus.net.register_mover(TownBus.BODY_MOVER % _me, body)


## Outside the building's south side, by its plaque, on the ground.
func spawn_point() -> Vector3:
	var p := home + Vector3(home_bounds.get_center().x, 0.0, home_bounds.end.z + 7.0)
	p.y = ground_at(p.x, p.z) + 0.05
	return p


func ground_at(x: float, z: float) -> float:
	return pack.height_at(x, z) if pack != null else 0.0


# --- Modes ---------------------------------------------------------------------------------

func set_mode(m: String) -> void:
	if m == mode:
		return
	if m != "orbit" and not _colliders_added:
		# Floors and walls to stand on: only when someone walks, so orbiting stays cheap.
		_colliders_added = true
		for n in find_children("TownBuilding_*", "", true, false):
			n.call("add_colliders")
	if mode == "orbit" and m != "orbit":
		if m == "walk":
			body.position = spawn_point()
		else:
			body.position = camera.global_position - Vector3(0, EYE, 0)
		# Face the building being visited.
		var d := home + home_bounds.get_center() - (body.position + Vector3(0, EYE, 0))
		_look_yaw = atan2(-d.x, -d.z)
		_look_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.2, 0.6) if m == "fly" else 0.1
	if m == "orbit":
		_focus = body.position + Vector3(0, 1.0, 0)
		_dist = 20.0
	mode = m
	body.velocity = Vector3.ZERO
	(body.get_child(0) as CollisionShape3D).disabled = m == "fly"
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if m == "orbit" else Input.MOUSE_MODE_CAPTURED
	_place_camera()


func _place_camera() -> void:
	if camera == null:
		return
	if mode == "orbit":
		var dir := Vector3(cos(_pitch) * sin(_yaw), -sin(_pitch), cos(_pitch) * cos(_yaw))
		camera.position = _focus + dir * _dist
		camera.look_at(_focus)
		if body and mode == "orbit":
			body.position = Vector3(_focus.x, ground_at(_focus.x, _focus.z), _focus.z)
	else:
		camera.position = body.position + Vector3(0, EYE, 0)
		camera.rotation = Vector3(_look_pitch, _look_yaw, 0)


func help_text() -> Array:
	match mode:
		"walk":
			return ["WALKING", HelpBar.keys_text([["W A S D", "walk"], ["Shift", "run"], ["Space", "jump"],
					["Q", "fly"], ["F", "orbit"], ["V", "look"], ["Esc", "orbit"]])]
		"fly":
			return ["FLYING", HelpBar.keys_text([["W A S D", "fly"], ["Space / C", "up / down"], ["Shift", "fast"],
					["Q", "walk"], ["F", "orbit"], ["V", "look"], ["Esc", "orbit"]])]
	return ["VISITING", HelpBar.keys_text([["Right drag", "orbit"], ["Middle drag / W A S D", "pan"], ["Wheel", "zoom"],
			["F", "walk"], ["Q", "fly"], ["V", "look"], ["Esc", "back to the map"]])]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_F:
				set_mode("orbit" if mode != "orbit" else "walk")
				get_viewport().set_input_as_handled()
			KEY_Q:
				set_mode("walk" if mode == "fly" else "fly")
				get_viewport().set_input_as_handled()
			KEY_V:
				GraphicsOptions.set_value("art_style", ArtStyle.MODEL if ArtStyle.realistic() else ArtStyle.REALISTIC)
				ArtStyle.apply_to_camera(camera)
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if mode != "orbit":
					set_mode("orbit")
				else:
					bus.leave()
				get_viewport().set_input_as_handled()
			KEY_SPACE:
				if mode == "walk" and body.is_on_floor():
					body.velocity.y = JUMP
		return
	if mode != "orbit":
		if event is InputEventMouseMotion:
			var mm := event as InputEventMouseMotion
			_look_yaw -= mm.relative.x * LOOK_SPEED
			_look_pitch = clampf(_look_pitch - mm.relative.y * LOOK_SPEED, -1.5, 1.5)
		elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				_dist = clampf(_dist / ZOOM_STEP, 6.0, 800.0)
				_place_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_dist = clampf(_dist * ZOOM_STEP, 6.0, 800.0)
				_place_camera()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			_yaw -= mm.relative.x * ORBIT_SPEED
			_pitch = clampf(_pitch - mm.relative.y * ORBIT_SPEED, deg_to_rad(-85.0), deg_to_rad(-3.0))
			_place_camera()
		elif _panning:
			_pan(Vector2(-mm.relative.x, -mm.relative.y) * PAN_SPEED * _dist)


func _move_input() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		v.y -= 1
	if Input.is_physical_key_pressed(KEY_S):
		v.y += 1
	if Input.is_physical_key_pressed(KEY_A):
		v.x -= 1
	if Input.is_physical_key_pressed(KEY_D):
		v.x += 1
	return v.normalized() if v != Vector2.ZERO else v


func _physics_process(delta: float) -> void:
	if body == null:
		return
	var v := _move_input()
	var fast := Input.is_physical_key_pressed(KEY_SHIFT)
	match mode:
		"orbit":
			if v != Vector2.ZERO:
				_pan(v * KEY_PAN * delta * maxf(_dist / 60.0, 1.0))
		"walk":
			var basis := Basis(Vector3.UP, _look_yaw)
			var dir := basis * Vector3(v.x, 0, v.y)
			var speed := RUN_SPEED if fast else WALK_SPEED
			body.velocity.x = dir.x * speed
			body.velocity.z = dir.z * speed
			body.velocity.y -= GRAVITY * delta
			body.move_and_slide()
			# Never fall through the world: back onto the ground.
			var g := ground_at(body.position.x, body.position.z)
			if body.position.y < g - 2.0:
				body.position.y = g + 0.1
				body.velocity.y = 0.0
			body.rotation.y = _look_yaw
			_place_camera()
		"fly":
			var b := Basis.from_euler(Vector3(_look_pitch, _look_yaw, 0))
			var up := 0.0
			if Input.is_physical_key_pressed(KEY_SPACE):
				up += 1.0
			if Input.is_physical_key_pressed(KEY_C):
				up -= 1.0
			var move := b * Vector3(v.x, 0, v.y) + Vector3(0, up, 0)
			body.position += move * FLY_SPEED * (3.0 if fast else 1.0) * delta
			body.rotation.y = _look_yaw
			_place_camera()


func _pan(d: Vector2) -> void:
	var right := Vector3(cos(_yaw), 0, -sin(_yaw))
	var fwd := Vector3(sin(_yaw), 0, cos(_yaw))
	_focus += right * d.x + fwd * d.y
	_focus.y = ground_at(_focus.x, _focus.z) + 2.0
	_place_camera()


# --- The crew ------------------------------------------------------------------------------

func _sync_crew() -> void:
	for peer: int in crew.keys():
		if not bus.here.has(peer):
			(crew[peer] as Node).queue_free()
			crew.erase(peer)
	for peer: int in bus.here:
		if peer == _me or crew.has(peer):
			continue
		var w: Dictionary = bus.here[peer]
		var fig := crew_figure(str(w.get("name", "Player")), w.get("colour", Color.WHITE))
		fig.name = "Crew_%d" % peer
		add_child(fig)
		crew[peer] = fig


func _process(_delta: float) -> void:
	for peer: int in crew:
		var src := bus.proxy_body(peer)
		if src != null:
			(crew[peer] as Node3D).position = src.position
			(crew[peer] as Node3D).rotation.y = src.rotation.y


static func crew_figure(player: String, colour: Color) -> Node3D:
	var fig := Node3D.new()
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.8
	mi.mesh = cap
	mi.position.y = 0.9
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	mi.material_override = m
	fig.add_child(mi)
	var tag := Label3D.new()
	tag.text = player
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.font_size = 40
	tag.pixel_size = 0.006
	tag.modulate = colour
	tag.outline_size = 8
	tag.position = Vector3(0, 2.2, 0)
	fig.add_child(tag)
	return fig
