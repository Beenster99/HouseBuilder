extends Node3D
## The demolition site. The building stands as frozen Jolt chunks (DemolitionRules.chunks).
## When the host's bus releases a part, its chunks come alive: on the host they are dynamic
## bodies, on everyone else frozen copies that follow the host's stream (movers
## "demo:<part>#<n>"). Falling chunks that hit standing parts hard enough knock them loose
## too (host only), so a collapse spreads on its own.
##
## Plan: hover a part and left click to place a charge at the current delay (click again to
## remove it, [ and ] change the delay), P previews what will come down, F fires (3 s
## countdown), R resets the building. Tab takes the wrecking-ball crane: A/D slew, W/S reach,
## Q/E cable. Right drag orbits, middle drag pans, wheel zooms, Esc pauses.

const DemoOffice := preload("res://modules/demolition/internal/demo_office.gd")

const COLOURS := {
	"foundation": Color(0.55, 0.55, 0.53), "column": Color(0.78, 0.77, 0.74),
	"beam": Color(0.7, 0.7, 0.68), "brace": Color(0.4, 0.42, 0.46), "truss": Color(0.4, 0.42, 0.46),
	"slab": Color(0.86, 0.85, 0.82), "roof": Color(0.6, 0.38, 0.32), "wall": Color(0.93, 0.91, 0.86),
	"opening": Color(0.55, 0.75, 0.9), "fixture": Color(0.6, 0.72, 0.6), "room": Color(0.8, 0.7, 0.5),
}
const CHARGE_COLOUR := Color(0.95, 0.15, 0.1)
const PREVIEW_COLOUR := Color(1.0, 0.5, 0.1)
const NEIGHBOUR_COLOUR := Color(0.55, 0.62, 0.72)
const BLAST_RADIUS := 5.0
const BLAST_IMPULSE := 900.0
const SETTLE_SPEED := 0.4
const SETTLE_TIME := 1.5
const SETTLE_MAX := 25.0
const CRANE_ID := "crane:tip"
const CABLE_ID := "crane:cable"
const BALL_ID := "crane:ball"
const BALL_MASS := 3000.0
const BALL_RADIUS := 0.7
const ORBIT_SPEED := 0.006
const PAN_SPEED := 0.0025
const ZOOM_STEP := 1.12

var bus: DemolitionBus
var net: MultiplayerBus
var camera: Camera3D
var _chunks: Dictionary = {}  # part id -> Array[RigidBody3D]
var _materials: Dictionary = {}
var _damage: Dictionary = {}  # part id -> J taken
var _pending: PackedStringArray = []
var _neighbour_hits: Dictionary = {}
var _charge_marks: Dictionary = {}  # part id -> Node3D
var _preview := false
var _delay := 0.0
var _hover := ""
var _building_root: Node3D
var _fx_root: Node3D
var _settle_since := -1.0
var _active_since := -1.0
var _watching := false
var _focus := Vector3(7.5, 6.0, 5.0)
var _yaw := deg_to_rad(35.0)
var _pitch := deg_to_rad(-22.0)
var _dist := 55.0
var _orbiting := false
var _panning := false
# Crane
var _crane_base := Vector3.ZERO
var _crane_height := 30.0
var _slew := 0.0
var _reach := 20.0
var _cable := 10.0
var _tip: Node3D
var _cable_node: Node3D
var _ball: RigidBody3D
var _jib: Node3D
var _cable_mesh: MeshInstance3D
# HUD
var _status: Label
var _plan: Label
var _result: Label


func _ready() -> void:
	bus = Modules.bus("demolition") as DemolitionBus
	net = bus.net
	_build_world()
	_build_hud()
	bus.started.connect(func(_t: String) -> void: _rebuild())
	bus.reset.connect(_rebuild)
	bus.charges_changed.connect(_refresh_charges)
	bus.blasted.connect(_on_blasted)
	bus.released.connect(_on_released)
	bus.result_changed.connect(func(_r: Dictionary) -> void: _show_result())
	bus.fired.connect(func(_at: float) -> void: _start_watch())
	if not bus.is_active() and bool(Router.args.get("demo", false)):
		bus.start_demolition(DemoOffice.parts(), "Five-storey office",
				{"neighbours": DemoOffice.neighbours(), "open": false})
	_rebuild()


func _exit_tree() -> void:
	_unregister_all()


# --- World -----------------------------------------------------------------------------

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.58, 0.82)
	sky_mat.sky_horizon_color = Color(0.82, 0.84, 0.86)
	sky_mat.ground_horizon_color = Color(0.6, 0.6, 0.58)
	sky_mat.ground_bottom_color = Color(0.42, 0.42, 0.4)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(-35.0), 0.0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	add_child(sun)

	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var gs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = Vector3(600, 2, 600)
	gs.shape = gb
	gs.position.y = -1.0
	ground.add_child(gs)
	var gm := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	gm.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.44, 0.45, 0.4)
	gmat.roughness = 1.0
	gmat.metallic_specular = 0.1
	gm.material_override = gmat
	ground.add_child(gm)
	add_child(ground)

	_building_root = Node3D.new()
	_building_root.name = "Building"
	add_child(_building_root)
	_fx_root = Node3D.new()
	add_child(_fx_root)
	camera = Camera3D.new()
	camera.far = 900.0
	add_child(camera)
	camera.make_current()


func _rebuild() -> void:
	_unregister_all()
	for n in _building_root.get_children() + _fx_root.get_children():
		n.free()
	_ball = null
	_tip = null
	_chunks.clear()
	_damage.clear()
	_pending.clear()
	_neighbour_hits.clear()
	_charge_marks.clear()
	_watching = false
	if not bus.is_active():
		return
	var bounds := AABB()
	var first := true
	for p: Dictionary in bus.parts:
		bounds = p.aabb if first else bounds.merge(p.aabb)
		first = false
		var list: Array[RigidBody3D] = []
		var parts_chunks := DemolitionRules.chunks(p)
		for i in parts_chunks.size():
			list.append(_make_chunk(p, i, parts_chunks[i]))
		_chunks[p.id] = list
	_build_zone()
	for n: Variant in bus.neighbours:
		_build_neighbour(n as AABB)
	_focus = bounds.get_center()
	_dist = clampf(maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)) * 2.6, 20.0, 400.0)
	_build_crane(bounds)
	# A joiner arriving mid-collapse: whatever already fell comes alive at once.
	var already := PackedStringArray()
	for id: String in bus.released_ids:
		if bus.blasted_ids.has(id):
			_on_blasted(id)
		else:
			already.append(id)
	if not already.is_empty():
		_on_released(already)
	_refresh_charges()
	_show_result()


func _material(family: String) -> StandardMaterial3D:
	if _materials.has(family):
		return _materials[family]
	var m := StandardMaterial3D.new()
	m.albedo_color = COLOURS.get(family, Color(0.8, 0.8, 0.8))
	m.roughness = 0.9
	_materials[family] = m
	return m


func _make_chunk(p: Dictionary, index: int, box: AABB) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "%s_%d" % [str(p.id).replace(":", "_"), index]
	body.set_meta("part", p.id)
	body.set_meta("index", index)
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.freeze = true
	body.mass = maxf(box.get_volume() * DemolitionRules.density(p), 5.0)
	var size := Vector3(maxf(box.size.x, 0.05), maxf(box.size.y, 0.05), maxf(box.size.z, 0.05))
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size * 0.995
	mesh.mesh = bm
	mesh.material_override = _material(str(p.get("family", "")))
	body.add_child(mesh)
	body.position = box.get_center()
	_building_root.add_child(body)
	return body


func _build_zone() -> void:
	var z := bus.zone
	var lines := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.1)
	lines.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var c := [Vector3(z.position.x, 0.03, z.position.y), Vector3(z.end.x, 0.03, z.position.y),
			Vector3(z.end.x, 0.03, z.end.y), Vector3(z.position.x, 0.03, z.end.y)]
	for i in 4:
		lines.surface_add_vertex(c[i])
		lines.surface_add_vertex(c[(i + 1) % 4])
	lines.surface_end()
	var node := MeshInstance3D.new()
	node.name = "DropZone"
	node.mesh = lines
	_building_root.add_child(node)
	var fill := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = z.size
	fill.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(1.0, 0.85, 0.1, 0.1)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill.material_override = fm
	fill.position = Vector3(z.get_center().x, 0.02, z.get_center().y)
	_building_root.add_child(fill)


func _build_neighbour(box: AABB) -> void:
	var body := StaticBody3D.new()
	body.name = "Neighbour_%d" % _building_root.get_child_count()
	body.set_meta("neighbour", true)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box.size
	shape.shape = bs
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mesh.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = NEIGHBOUR_COLOUR
	mesh.material_override = m
	body.add_child(mesh)
	var tag := Label3D.new()
	tag.text = "PROTECTED"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 64
	tag.pixel_size = 0.02
	tag.position.y = box.size.y / 2.0 + 1.0
	body.add_child(tag)
	body.position = box.get_center()
	_building_root.add_child(body)


# --- Releases and blasts ---------------------------------------------------------------

func _on_released(ids: PackedStringArray) -> void:
	var host := net.is_host()
	for id in ids:
		for body: RigidBody3D in _chunks.get(id, []):
			if not is_instance_valid(body):
				continue
			var mid := _mover_id(body)
			if host:
				body.freeze = false
				body.contact_monitor = true
				body.max_contacts_reported = 4
				body.can_sleep = true
				if not body.body_entered.is_connected(_on_chunk_hit):
					body.body_entered.connect(_on_chunk_hit.bind(body))
			else:
				body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			net.register_mover(mid, body)
		var mark: Node3D = _charge_marks.get(id)
		if mark:
			mark.queue_free()
			_charge_marks.erase(id)
	_start_watch()


func _on_blasted(id: String) -> void:
	var at := Vector3.ZERO
	var list: Array = _chunks.get(id, [])
	for body: RigidBody3D in list:
		if is_instance_valid(body):
			at += body.global_position
			body.queue_free()
	if not list.is_empty():
		at /= list.size()
	_chunks.erase(id)
	var mark: Node3D = _charge_marks.get(id)
	if mark:
		mark.queue_free()
		_charge_marks.erase(id)
	_flash(at)
	if net.is_host():
		for other: String in _chunks:
			if not bus.released_ids.has(other):
				continue
			for body: RigidBody3D in _chunks[other]:
				var d := body.global_position - at
				if d.length() < BLAST_RADIUS:
					body.apply_central_impulse(d.normalized() * BLAST_IMPULSE * (1.0 - d.length() / BLAST_RADIUS))


func _flash(at: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.3)
	light.light_energy = 8.0
	light.omni_range = 10.0
	light.position = at
	_fx_root.add_child(light)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.2
	sm.height = 2.4
	ball.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.85, 0.5, 0.9)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.6, 0.2)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball.material_override = m
	ball.position = at
	_fx_root.add_child(ball)
	var tw := create_tween().set_parallel()
	tw.tween_property(light, "light_energy", 0.0, 0.6)
	tw.tween_property(ball, "scale", Vector3.ONE * 3.0, 0.5)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.5)
	tw.chain().tween_callback(func() -> void:
		light.queue_free()
		ball.queue_free())


## Host: a falling chunk hit something. Standing parts take damage; neighbours count.
func _on_chunk_hit(other: Node, body: RigidBody3D) -> void:
	if not is_instance_valid(body):
		return
	_hit(other, 0.5 * body.mass * body.linear_velocity.length_squared())


func _hit(other: Node, energy: float) -> void:
	if other.has_meta("neighbour"):
		if energy > 500.0:
			_neighbour_hits[other.name] = true
		return
	if not other.has_meta("part"):
		return
	var pid := str(other.get_meta("part"))
	if bus.released_ids.has(pid) or not bus.by_id.has(pid):
		return
	_damage[pid] = float(_damage.get(pid, 0.0)) + energy
	if _damage[pid] >= DemolitionRules.strength(bus.by_id[pid]) and not _pending.has(pid):
		_pending.append(pid)


func _mover_id(body: RigidBody3D) -> String:
	return "demo:%s#%d" % [body.get_meta("part"), body.get_meta("index")]


func _unregister_all() -> void:
	if net == null:
		return
	for id: String in _chunks:
		for body: RigidBody3D in _chunks[id]:
			if is_instance_valid(body):
				net.unregister_mover(_mover_id(body))
	for mid in [CRANE_ID, CABLE_ID, BALL_ID]:
		net.unregister_mover(mid)


# --- Charges ---------------------------------------------------------------------------

func _refresh_charges() -> void:
	for id: String in _charge_marks.keys():
		if not bus.charges.has(id):
			(_charge_marks[id] as Node3D).queue_free()
			_charge_marks.erase(id)
	for id: String in bus.charges:
		var mark: Node3D = _charge_marks.get(id)
		if mark == null:
			mark = _make_mark(id)
			if mark == null:
				continue
			_charge_marks[id] = mark
		(mark.get_node("Delay") as Label3D).text = "%.2fs" % float(bus.charges[id])
	_refresh_preview()


func _make_mark(id: String) -> Node3D:
	if not bus.by_id.has(id):
		return null
	var box: AABB = bus.by_id[id].aabb
	var mark := Node3D.new()
	mark.position = box.get_center()
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.35, 0.5)
	mesh.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = CHARGE_COLOUR
	m.emission_enabled = true
	m.emission = CHARGE_COLOUR
	mesh.material_override = m
	mark.add_child(mesh)
	var tag := Label3D.new()
	tag.name = "Delay"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.font_size = 40
	tag.pixel_size = 0.01
	tag.outline_size = 8
	tag.position.y = 0.7
	mark.add_child(tag)
	_fx_root.add_child(mark)
	return mark


func _refresh_preview() -> void:
	var doomed: Dictionary = {}
	if _preview and not bus.is_fired():
		for id in bus.predicted():
			doomed[id] = true
		for id: String in bus.charges:
			doomed[id] = true
	var hot := _material("__preview")
	hot.albedo_color = PREVIEW_COLOUR
	for id: String in _chunks:
		var mat := hot if doomed.has(id) else _material(str(bus.by_id[id].get("family", "")))
		for body: RigidBody3D in _chunks[id]:
			if is_instance_valid(body):
				(body.get_child(1) as MeshInstance3D).material_override = mat


## The part under the mouse, or "".
func part_under_mouse() -> String:
	var mouse := get_viewport().get_mouse_position()
	var q := PhysicsRayQueryParameters3D.create(camera.project_ray_origin(mouse),
			camera.project_ray_origin(mouse) + camera.project_ray_normal(mouse) * 800.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not (hit.collider as Node).has_meta("part"):
		return ""
	return str((hit.collider as Node).get_meta("part"))


# --- Crane -----------------------------------------------------------------------------

func _build_crane(bounds: AABB) -> void:
	for mid in [CRANE_ID, CABLE_ID, BALL_ID]:
		net.unregister_mover(mid)
	_crane_height = bounds.end.y + 10.0
	# Behind the building from the opening camera, its jib reaching over the top.
	_crane_base = Vector3(bounds.get_center().x, 0.0, bus.zone.position.y - 8.0)
	_reach = clampf(absf(bounds.get_center().z - _crane_base.z), 8.0, 58.0)
	_slew = PI
	_cable = _crane_height * 0.5
	var root := Node3D.new()
	root.name = "Crane"
	_building_root.add_child(root)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.95, 0.72, 0.1)
	var mast := MeshInstance3D.new()
	var mb := BoxMesh.new()
	mb.size = Vector3(1.4, _crane_height, 1.4)
	mast.mesh = mb
	mast.material_override = steel
	mast.position = _crane_base + Vector3(0, _crane_height / 2.0, 0)
	root.add_child(mast)
	_jib = Node3D.new()
	_jib.position = _crane_base + Vector3(0, _crane_height, 0)
	root.add_child(_jib)
	var arm := MeshInstance3D.new()
	var ab := BoxMesh.new()
	ab.size = Vector3(1.0, 1.0, 60.0)
	arm.mesh = ab
	arm.material_override = steel
	arm.position = Vector3(0, 0.5, -26.0)
	_jib.add_child(arm)
	_tip = Node3D.new()
	_tip.name = "Tip"
	root.add_child(_tip)
	_cable_node = Node3D.new()
	_cable_node.name = "CableLength"
	root.add_child(_cable_node)
	_ball = RigidBody3D.new()
	_ball.name = "WreckingBall"
	_ball.mass = BALL_MASS
	_ball.contact_monitor = true
	_ball.max_contacts_reported = 4
	_ball.can_sleep = false
	var bs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = BALL_RADIUS
	bs.shape = sphere
	_ball.add_child(bs)
	var bm := MeshInstance3D.new()
	var smesh := SphereMesh.new()
	smesh.radius = BALL_RADIUS
	smesh.height = BALL_RADIUS * 2.0
	bm.mesh = smesh
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.15, 0.15, 0.16)
	dark.metallic = 0.6
	bm.material_override = dark
	_ball.add_child(bm)
	root.add_child(_ball)
	_cable_mesh = MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.06, 1.0, 0.06)
	_cable_mesh.mesh = cm
	_cable_mesh.material_override = dark
	root.add_child(_cable_mesh)
	_place_tip()
	_ball.global_position = _tip.global_position - Vector3(0, _cable, 0)
	if not net.is_host():
		_ball.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		_ball.freeze = true
	else:
		_ball.body_entered.connect(func(other: Node) -> void:
			_hit(other, 0.5 * BALL_MASS * _ball.linear_velocity.length_squared()))
	net.register_mover(CRANE_ID, _tip)
	net.register_mover(CABLE_ID, _cable_node)
	net.register_mover(BALL_ID, _ball)


func _place_tip() -> void:
	var dir := Vector3(-sin(_slew), 0.0, -cos(_slew))
	_tip.global_position = _crane_base + Vector3(0, _crane_height, 0) + dir * _reach
	_cable_node.position = Vector3(_cable, 0, 0)


func driving_crane() -> bool:
	return net.claim_owner(CRANE_ID) == net.local_peer_id()


func _crane_controls(delta: float) -> void:
	if _tip == null:
		return
	if driving_crane():
		var slew := 0.0
		if Input.is_key_pressed(KEY_A):
			slew += 1.0
		if Input.is_key_pressed(KEY_D):
			slew -= 1.0
		_slew += slew * 0.6 * delta
		if Input.is_key_pressed(KEY_W):
			_reach += 6.0 * delta
		if Input.is_key_pressed(KEY_S):
			_reach -= 6.0 * delta
		if Input.is_key_pressed(KEY_E):
			_cable += 5.0 * delta
		if Input.is_key_pressed(KEY_Q):
			_cable -= 5.0 * delta
		_reach = clampf(_reach, 6.0, 58.0)
		_cable = clampf(_cable, 2.0, _crane_height - 1.0)
		_place_tip()
	else:
		# Someone else (or the host) drives: read back what the stream says.
		var local := _tip.global_position - (_crane_base + Vector3(0, _crane_height, 0))
		_slew = atan2(-local.x, -local.z)
		_cable = _cable_node.position.x if _cable_node.position.x > 0.0 else _cable
	_jib.rotation.y = _slew


## Host: the ball hangs on an inextensible cable from the moving tip (a pendulum).
func _physics_process(_delta: float) -> void:
	if _ball == null or not net.is_host():
		return
	var top := _tip.global_position
	var d := _ball.global_position - top
	var length := d.length()
	if length > _cable:
		var n := d / length
		_ball.global_position = top + n * _cable
		var out := _ball.linear_velocity.dot(n)
		if out > 0.0:
			_ball.linear_velocity -= n * out


# --- Every frame -----------------------------------------------------------------------

func _process(delta: float) -> void:
	_place_camera()
	_crane_controls(delta)
	if _ball:
		var top := _tip.global_position
		var bottom := _ball.global_position
		var span := top - bottom
		var turn := Basis(Quaternion(Vector3.UP, span.normalized())) if span.length() > 0.01 else Basis()
		_cable_mesh.global_transform = Transform3D(turn.scaled_local(Vector3(1, maxf(span.length(), 0.1), 1)),
				(top + bottom) / 2.0)
	if net.is_host():
		if not _pending.is_empty():
			bus.host_release(_pending)
			_pending.clear()
		_watch_settle()
	_hover = part_under_mouse() if not driving_crane() else ""
	_update_hud()


func _start_watch() -> void:
	_watching = true
	_settle_since = -1.0
	_active_since = Time.get_ticks_msec() / 1000.0


## Host: once the debris stops moving (or after SETTLE_MAX s), score it.
func _watch_settle() -> void:
	if not _watching or not bus.is_active():
		return
	if bus.is_fired() and bus.countdown() > 0.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var moving := false
	for id: String in bus.released_ids:
		for body: RigidBody3D in _chunks.get(id, []):
			if is_instance_valid(body) and not body.sleeping and body.linear_velocity.length() > SETTLE_SPEED:
				moving = true
				break
		if moving:
			break
	if bus.is_fired():
		for id: String in bus.charges:
			if not bus.blasted_ids.has(id):
				moving = true
	if moving and now - _active_since < SETTLE_MAX:
		_settle_since = -1.0
		return
	if _settle_since < 0.0:
		_settle_since = now
		return
	if now - _settle_since < SETTLE_TIME and now - _active_since < SETTLE_MAX:
		return
	_watching = false
	bus.host_result(assess())


## The score as it stands: debris inside the drop zone, what is still up, neighbours hit.
func assess() -> Dictionary:
	var debris_in := 0.0
	var debris_total := 0.0
	var standing := 0.0
	for p: Dictionary in bus.parts:
		if bus.blasted_ids.has(p.id) or str(p.get("family", "")) == "foundation":
			continue
		for body: RigidBody3D in _chunks.get(p.id, []):
			if not is_instance_valid(body):
				continue
			var v := ((body.get_child(0) as CollisionShape3D).shape as BoxShape3D).size
			var vol := v.x * v.y * v.z
			if bus.released_ids.has(p.id):
				debris_total += vol
				var at := body.global_position
				if bus.zone.has_point(Vector2(at.x, at.z)):
					debris_in += vol
			else:
				standing += vol
	return DemolitionRules.score(debris_in, debris_total, standing, bus.total_volume(),
			_neighbour_hits.size(), bus.charges.size())


# --- Camera and input ------------------------------------------------------------------

func _place_camera() -> void:
	var basis := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	camera.global_transform = Transform3D(basis, _focus + basis.z * _dist)


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
					_dist = clampf(_dist / ZOOM_STEP, 5.0, 500.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_dist = clampf(_dist * ZOOM_STEP, 5.0, 500.0)
			MOUSE_BUTTON_LEFT:
				if mb.pressed and _hover != "":
					bus.request_charge(_hover, _delay)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			_yaw -= mm.relative.x * ORBIT_SPEED
			_pitch = clampf(_pitch - mm.relative.y * ORBIT_SPEED, deg_to_rad(-85.0), deg_to_rad(-3.0))
		elif _panning:
			var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
			var back := Vector3(sin(_yaw), 0.0, cos(_yaw))
			_focus -= (right * mm.relative.x + back * mm.relative.y) * PAN_SPEED * _dist
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_BRACKETLEFT:
				_delay = maxf(0.0, _delay - DemolitionBus.DELAY_STEP)
			KEY_BRACKETRIGHT:
				_delay = minf(DemolitionBus.MAX_DELAY, _delay + DemolitionBus.DELAY_STEP)
			KEY_P:
				_preview = not _preview
				_refresh_preview()
			KEY_F:
				if not driving_crane():
					bus.request_fire()
			KEY_R:
				if not driving_crane():
					bus.request_reset()
			KEY_TAB:
				if driving_crane():
					net.release(CRANE_ID)
				else:
					net.claim(CRANE_ID)
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				Menu.open_pause()
				get_viewport().set_input_as_handled()


# --- HUD -------------------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.name = "DemolitionHud"
	panel.add_theme_stylebox_override("panel", BsxTheme.panel_style(16))
	panel.position = Vector2(24, 20)
	layer.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	_status = BsxTheme.hud_label("", 20)
	_status.name = "Status"
	col.add_child(_status)
	_plan = BsxTheme.hud_label("", 15)
	_plan.name = "Timeline"
	col.add_child(_plan)
	_result = BsxTheme.hud_label("", 22)
	_result.name = "Result"
	col.add_child(_result)
	var help := BsxTheme.hud_label("Click part: charge  ·  [ ] delay  ·  P preview  ·  F fire  ·  R reset\n"
			+ "Tab crane (A/D slew, W/S reach, Q/E cable)  ·  right drag orbit  ·  wheel zoom", 14)
	col.add_child(help)


func _update_hud() -> void:
	if not bus.is_active():
		_status.text = "Nothing to demolish yet."
		return
	var line := "%s  ·  delay %.2fs" % [bus.title.to_upper(), _delay]
	if bus.is_fired():
		var c := bus.countdown()
		line += "  ·  FIRING IN %.1f" % c if c > 0.0 else "  ·  FIRED"
	if _hover != "":
		line += "  ·  %s" % _hover
	var owner := net.claim_owner(CRANE_ID)
	if owner != 0:
		line += "  ·  crane: %s" % net.player_name(owner)
	_status.text = line
	var entries: Array = []
	for id: String in bus.charges:
		entries.append([float(bus.charges[id]), id])
	entries.sort()
	var parts_text: PackedStringArray = []
	for e: Array in entries.slice(0, 8):
		parts_text.append("%.2fs %s" % [e[0], e[1]])
	if entries.size() > 8:
		parts_text.append("+%d more" % (entries.size() - 8))
	_plan.text = "Charges %d/%d: %s" % [bus.charges.size(), DemolitionBus.MAX_CHARGES,
			", ".join(parts_text) if not parts_text.is_empty() else "none yet"]


func _show_result() -> void:
	var r := bus.result
	if r.is_empty():
		_result.text = ""
		return
	_result.text = "%s  ·  %d / 100  ·  down %d%%  ·  in zone %d%%  ·  neighbours hit %d" % [
			str(r.get("grade", "")).to_upper(), int(r.get("score", 0)), int(float(r.get("down", 0)) * 100.0),
			int(float(r.get("contained", 0)) * 100.0), int(r.get("neighbour_hits", 0))]
