extends Node3D
## The demolition site. The building stands as frozen Jolt chunks (DemolitionRules.chunks,
## sized so the building has at most DemolitionRules.MAX_CHUNKS). When the host's bus
## releases a part, its chunks are welded into one falling body; when that hits something
## hard it breaks back into its chunks (bus.host_fracture, while fewer than AWAKE_CAP bodies
## are moving). Debris that comes to rest is frozen where it lies. On the host the bodies
## are dynamic, on everyone else frozen copies following the host's packed mover group
## (GROUP: the chunk's index, or past the last chunk a part's whole). Falling bodies that hit
## standing parts hard enough knock them loose too (host only), so a collapse spreads.
##
## Plan: hover a part and left click to place a charge at the current delay (click again to
## remove it, [ and ] change the delay), P previews what will come down, F fires (3 s
## countdown), R resets the building. Tab takes the wrecking-ball crane: A/D slew, W/S reach,
## Q/E cable. Right drag orbits, middle drag pans, wheel zooms, Esc pauses.

const DemoOffice := preload("res://modules/demolition/internal/demo_office.gd")
const DebrisScript := preload("res://modules/demolition/internal/debris.gd")

const COLOURS := {
	"foundation": Color(0.55, 0.55, 0.53), "column": Color(0.78, 0.77, 0.74),
	"beam": Color(0.7, 0.7, 0.68), "brace": Color(0.4, 0.42, 0.46), "truss": Color(0.4, 0.42, 0.46),
	"slab": Color(0.86, 0.85, 0.82), "roof": Color(0.6, 0.38, 0.32), "wall": Color(0.93, 0.91, 0.86),
	"opening": Color(0.55, 0.75, 0.9), "fixture": Color(0.6, 0.72, 0.6), "room": Color(0.8, 0.7, 0.5),
}
const CHARGE_COLOUR := Color(0.95, 0.15, 0.1)
const PREVIEW_COLOUR := Color(1.0, 0.5, 0.1)
const NEIGHBOUR_COLOUR := Color(0.55, 0.62, 0.72)
## The packed mover group the debris streams in.
const GROUP := "demolition"
## A falling part breaks up when it hits something at this speed, m/s...
const FRACTURE_SPEED := 3.0
## ...while fewer bodies than this are moving, at most FRACTURES_PER_FRAME parts a frame.
const AWAKE_CAP := 900
const FRACTURES_PER_FRAME := 24
## Debris slower than this (m/s, rad/s) for STILL_TIME s is frozen where it lies.
const STILL_SPEED := 0.25
const STILL_SPIN := 0.5
const STILL_TIME := 0.75
const BLAST_RADIUS := 5.0
const BLAST_IMPULSE := 900.0
## Parts within this many metres of a charge have their faces spalled when it goes off, in a
## cube this many metres each way round it.
const SPALL_REACH := 3.0
const SPALL_SIZE := 1.2
## A part breaking up this close to a charge crumbles finer and throws off more.
const CRUMBLE_REACH := 8.0
const SETTLE_SPEED := 0.4
const SETTLE_TIME := 1.5
const SETTLE_MAX := 25.0
const CRANE_ID := "crane:tip"
const CABLE_ID := "crane:cable"
const BALL_ID := "crane:ball"
## The wrecking-ball crane (Tab to drive it). Off for now: the person asked for it to go
## for the time being.
const WRECKING_BALL_FLAG := "demolition.wrecking_ball"
const BALL_MASS := 3000.0
const BALL_RADIUS := 0.7
const ORBIT_SPEED := 0.006
const PAN_SPEED := 0.0025
const ZOOM_STEP := 1.12

var bus: DemolitionBus
var net: MultiplayerBus
var camera: Camera3D
var _chunks: Dictionary = {}  # part id -> Array[RigidBody3D] (one welded whole while falling)
var _chunk_size := DemolitionRules.CHUNK
var _first_index: Dictionary = {}  # part id -> group index of its first chunk
var _whole_index: Dictionary = {}  # part id -> group index of its welded whole
var _fracture_queue: PackedStringArray = []
var _still_tick := 0
var _materials: Dictionary = {}
var _ground: MeshInstance3D
var _damage: Dictionary = {}  # part id -> J taken
var _pending: PackedStringArray = []
var _neighbour_hits: Dictionary = {}
var _charge_marks: Dictionary = {}  # part id -> Node3D
var _preview := false
var _delay := 0.0
## The size new charges go on at (DemolitionBus.SIZES).
var _size := 1
## Where on the hovered part the pointer is (world), for placing a charge there.
var _hover_point: Variant = null
var _panel: PanelContainer
var _panel_box: VBoxContainer
var _delay_label: Label
var _size_buttons: Array[Button] = []
var _preview_button: Button
var _walk_button: Button
var _sequence: OptionButton
## Debris zones shown with the fall preview once the firm has a blast consultant.
var _debris_zones: Array[Dictionary] = []
var _debris_root: Node3D
var _hover := ""
var _building_root: Node3D
var _fx_root: Node3D
## Fine fragments thrown off by charges and hard hits (debris.gd).
var debris: Node3D
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
## The help line along the bottom (ui's HelpBar, the same on every screen).
var help: HelpBar
var _status: Label
var _plan: Label
var _result: Label
## A demolition contract's checklist and hand-over button, under the result.
var _job: VBoxContainer
var _job_items: VBoxContainer
var _hand_over: Button


func _ready() -> void:
	bus = Modules.bus("demolition") as DemolitionBus
	net = bus.net
	_build_world()
	_build_hud()
	bus.started.connect(func(_t: String) -> void: _rebuild())
	bus.reset.connect(_rebuild)
	bus.fractured.connect(_on_fractured)
	Graphics.changed.connect(func() -> void:
		_ground.material_override = ArtStyle.ground()
		_refresh_preview())
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
	gm.material_override = ArtStyle.ground()
	_ground = gm
	ground.add_child(gm)
	add_child(ground)

	_building_root = Node3D.new()
	_building_root.name = "Building"
	add_child(_building_root)
	_fx_root = Node3D.new()
	add_child(_fx_root)
	debris = DebrisScript.new()
	debris.name = "Debris"
	add_child(debris)
	camera = Camera3D.new()
	camera.far = 900.0
	add_child(camera)
	camera.make_current()


func _rebuild() -> void:
	_unregister_all()
	debris.clear()
	for n in _building_root.get_children() + _fx_root.get_children():
		n.free()
	_ball = null
	_tip = null
	_chunks.clear()
	_damage.clear()
	_pending.clear()
	_neighbour_hits.clear()
	_charge_marks.clear()
	_first_index.clear()
	_whole_index.clear()
	_fracture_queue.clear()
	_watching = false
	if not bus.is_active():
		return
	var bounds := AABB()
	var first := true
	_chunk_size = DemolitionRules.chunk_size(bus.parts)
	var next := 0
	for p: Dictionary in bus.parts:
		bounds = p.aabb if first else bounds.merge(p.aabb)
		first = false
		var list: Array[RigidBody3D] = []
		var parts_chunks := DemolitionRules.chunks(p, _chunk_size)
		_first_index[p.id] = next
		for i in parts_chunks.size():
			list.append(_make_chunk(p, i, parts_chunks[i]))
		next += parts_chunks.size()
		_chunks[p.id] = list
	for p: Dictionary in bus.parts:
		_whole_index[p.id] = next
		next += 1
	net.register_mover_group(GROUP, bounds.get_center())
	_build_zone()
	for n: Variant in bus.neighbours:
		_build_neighbour(n as AABB)
	_focus = bounds.get_center()
	_dist = clampf(maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)) * 2.6, 20.0, 400.0)
	for mid in [CRANE_ID, CABLE_ID, BALL_ID]:
		net.unregister_mover(mid)
	if Flags.is_on(WRECKING_BALL_FLAG):
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


func _part_material(p: Dictionary) -> BaseMaterial3D:
	return ArtStyle.material(str(p.get("material", "")), str(p.get("family", "")))


func _material(family: String) -> StandardMaterial3D:
	if _materials.has(family):
		return _materials[family]
	var m := StandardMaterial3D.new()
	m.albedo_color = COLOURS.get(family, Color(0.8, 0.8, 0.8))
	m.roughness = 0.9
	_materials[family] = m
	return m


## Placed models swap to a plain box beyond this many metres (or eight times their size).
const MODEL_LOD := 60.0


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
	var look: Dictionary = p.get("model", {})
	if not look.is_empty() and DemolitionRules.chunks(p, _chunk_size).size() == 1:
		# Fit-out, doors and windows that come down whole: their library model on the body,
		# the box kept as its collision shape.
		var node := AssetLibrary.make_kind(str(look.kind), {"size": look.size, "fit": look.get("fit", look.size),
				"family": "fixture", "lod": maxf(MODEL_LOD, (look.size as Vector3).length() * 8.0)})
		node.name = "Model"
		node.position = (look.at as Vector3) - box.get_center()
		node.rotation.y = deg_to_rad(float(look.get("rot", 0.0)))
		body.add_child(node)
	else:
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size * 0.995
		mesh.mesh = bm
		mesh.material_override = _part_material(p)
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
	for id in ids:
		var list: Array = _chunks.get(id, [])
		if bus.fractured_ids.has(id) or list.size() <= 1:
			# One chunk (or a joiner arriving after it broke up): its chunks fall as they are.
			for body: RigidBody3D in list:
				if is_instance_valid(body):
					_activate(body, int(_first_index[id]) + int(body.get_meta("index")))
		else:
			_weld(id)
		var mark: Node3D = _charge_marks.get(id)
		if mark:
			mark.queue_free()
			_charge_marks.erase(id)
	_start_watch()


## A body joins the falling debris: dynamic on the host, following the stream elsewhere.
func _activate(body: RigidBody3D, index: int) -> void:
	body.set_meta("group_index", index)
	if net.is_host():
		body.freeze = false
		# Contact reports cost: only welded wholes (and single-chunk parts) report hits; the
		# chunks a whole breaks into just tumble.
		var reports := body.has_meta("whole") or not bus.fractured_ids.has(str(body.get_meta("part")))
		body.contact_monitor = reports
		body.max_contacts_reported = 2 if reports else 0
		body.can_sleep = true
		if not body.body_entered.is_connected(_on_chunk_hit):
			body.body_entered.connect(_on_chunk_hit.bind(body))
	else:
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	net.set_group_node(GROUP, index, body)


## A released part's chunks become one falling body: their meshes move into it, and it
## collides as one box (the chunks' boxes wait aside until it breaks: many small shapes in
## one body cost the physics far more than one).
func _weld(id: String) -> void:
	var list: Array = _chunks.get(id, [])
	var whole := RigidBody3D.new()
	whole.name = "whole_%s" % id.replace(":", "_")
	whole.set_meta("part", id)
	whole.set_meta("whole", true)
	var centre := Vector3.ZERO
	var mass := 0.0
	for body: RigidBody3D in list:
		centre += body.global_position * body.mass
		mass += body.mass
	centre /= maxf(mass, 0.001)
	whole.mass = maxf(mass, 5.0)
	whole.position = centre
	var masses: Array[float] = []
	var shapes: Array[Node] = []
	var meshes: Array[Node] = []
	var box := AABB()
	for body: RigidBody3D in list:
		masses.append(body.mass)
		for child in body.get_children():
			var local: Transform3D = Transform3D(Basis(), body.global_position - centre) * (child as Node3D).transform
			body.remove_child(child)
			child.transform = local
			if child is CollisionShape3D:
				var half: Vector3 = ((child as CollisionShape3D).shape as BoxShape3D).size * 0.5
				var b := AABB(local.origin - half, half * 2.0)
				box = b if shapes.is_empty() else box.merge(b)
				shapes.append(child)
			else:
				meshes.append(child)
				whole.add_child(child)
		body.free()
	var one := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box.size
	one.shape = bs
	one.position = box.get_center()
	one.name = "Whole"
	whole.add_child(one)
	whole.move_child(one, 0)
	whole.set_meta("masses", masses)
	whole.set_meta("shapes", shapes)
	whole.set_meta("meshes", meshes)
	whole.tree_exiting.connect(func() -> void:
		for sh: Node in shapes:
			if is_instance_valid(sh) and sh.get_parent() == null:
				sh.queue_free())
	_building_root.add_child(whole)
	_chunks[id] = [whole]
	_activate(whole, int(_whole_index[id]))


func _on_fractured(ids: PackedStringArray) -> void:
	for id in ids:
		_fracture(id)


## A welded part breaks back into its chunks where it is, each moving as it was.
func _fracture(id: String) -> void:
	var list: Array = _chunks.get(id, [])
	if list.size() != 1 or not is_instance_valid(list[0]) or not (list[0] as Node).has_meta("whole"):
		return
	var whole: RigidBody3D = list[0]
	var xf := whole.global_transform
	var v := whole.linear_velocity
	var w := whole.angular_velocity
	var masses: Array = whole.get_meta("masses", [])
	var shapes: Array = whole.get_meta("shapes", [])
	var meshes: Array = whole.get_meta("meshes", [])
	var out: Array[RigidBody3D] = []
	for i in mini(shapes.size(), meshes.size()):
		var shape := shapes[i] as Node3D
		var mesh := meshes[i] as Node3D
		var body := RigidBody3D.new()
		body.name = "%s_%d" % [id.replace(":", "_"), i]
		body.set_meta("part", id)
		body.set_meta("index", i)
		body.mass = float(masses[i]) if i < masses.size() else 5.0
		var at := xf * Transform3D(Basis(), shape.position)
		whole.remove_child(mesh)
		shape.transform = Transform3D()
		mesh.transform = Transform3D()
		body.add_child(shape)
		body.add_child(mesh)
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = true
		_building_root.add_child(body)
		body.global_transform = at
		_activate(body, int(_first_index[id]) + i)
		if net.is_host():
			body.linear_velocity = v + w.cross(at.origin - xf.origin)
			body.angular_velocity = w
		out.append(body)
	net.erase_group_node(GROUP, int(_whole_index[id]))
	_crumble(id, xf, whole)
	whole.queue_free()
	_chunks[id] = out


## A falling part breaking up throws off fragments where it broke: more and finer the
## closer it is to a charge.
func _crumble(id: String, xf: Transform3D, whole: RigidBody3D) -> void:
	var p: Dictionary = bus.by_id.get(id, {})
	var one := whole.get_node_or_null("Whole") as CollisionShape3D
	if p.is_empty() or one == null:
		return
	var half := (one.shape as BoxShape3D).size * 0.5
	var box := AABB(xf * (one.position - half), Vector3.ZERO)
	for c in 8:
		box = box.expand(xf * (one.position + Vector3(half.x * (1 if c & 1 else -1), half.y * (1 if c & 2 else -1), half.z * (1 if c & 4 else -1))))
	var centre := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var close := INF
	for cid: String in bus.charges:
		var cp := bus.charge_point(cid)
		var d := cp.distance_to(cp.clamp(box.position, box.end))
		if d < close:
			close = d
			if d < CRUMBLE_REACH:
				centre = cp.clamp(box.position, box.end)
	var power := 0.25 + 0.5 * clampf(1.0 - close / CRUMBLE_REACH, 0.0, 1.0)
	debris.burst(box, centre, _break_material(p), _part_material(p), power, id + "~")


## Host: falling bodies moving now (not frozen, not asleep).
func awake_count() -> int:
	var n := 0
	for id: String in bus.released_ids:
		for body: RigidBody3D in _chunks.get(id, []):
			if is_instance_valid(body) and not body.freeze and not body.sleeping:
				n += 1
	return n


## Host, each physics frame: break up the parts that hit hard (as many as the budget allows)
## and, every few frames, freeze debris that has come to rest.
func _host_debris() -> void:
	if not _fracture_queue.is_empty():
		var room := mini(FRACTURES_PER_FRAME, AWAKE_CAP - awake_count())
		var go := PackedStringArray()
		while room > 0 and not _fracture_queue.is_empty():
			var id := _fracture_queue[0]
			_fracture_queue.remove_at(0)
			if bus.fractured_ids.has(id):
				continue
			go.append(id)
			room -= maxi(1, DemolitionRules.chunks(bus.by_id[id], _chunk_size).size() - 1)
		if not go.is_empty():
			bus.host_fracture(go)
	_still_tick += 1
	if _still_tick % 10 != 0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	for id: String in bus.released_ids:
		for body: RigidBody3D in _chunks.get(id, []):
			if not is_instance_valid(body) or body.freeze:
				continue
			if body.linear_velocity.length() > STILL_SPEED or body.angular_velocity.length() > STILL_SPIN:
				body.set_meta("still_since", -1.0)
				continue
			var since := float(body.get_meta("still_since", -1.0))
			if since < 0.0:
				body.set_meta("still_since", now)
			elif now - since >= STILL_TIME:
				body.contact_monitor = false
				body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
				body.freeze = true


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
	var power := bus.power_of(id)
	if bus.charges.has(id):
		at = bus.charge_point(id)
	_flash(at)
	_shatter(id)
	if net.is_host():
		for other: String in _chunks:
			if not bus.released_ids.has(other):
				continue
			for body: RigidBody3D in _chunks[other]:
				var d := body.global_position - at
				var reach := BLAST_RADIUS * sqrt(power)
				if d.length() < reach:
					body.apply_central_impulse(d.normalized() * BLAST_IMPULSE * power * (1.0 - d.length() / reach))


## A charge going off breaks its part into fine fragments round the charge, and spalls the
## faces of parts close by.
func _shatter(id: String) -> void:
	var p: Dictionary = bus.by_id.get(id, {})
	if p.is_empty():
		return
	var at := bus.charge_point(id)
	var power := bus.power_of(id)
	debris.burst(p.aabb, at, _break_material(p), _part_material(p), power, id)
	for other: Dictionary in bus.parts:
		if other.id == id or bus.blasted_ids.has(other.id):
			continue
		var box: AABB = other.aabb
		var near := at.clamp(box.position, box.end)
		var d := near.distance_to(at)
		if d > SPALL_REACH * power:
			continue
		var bit := box.intersection(AABB(at - Vector3.ONE * SPALL_SIZE, Vector3.ONE * SPALL_SIZE * 2.0))
		if bit.size == Vector3.ZERO:
			continue
		debris.burst(bit, near, _break_material(other), _part_material(other), (0.35 * (1.0 - d / (SPALL_REACH * power)) + 0.1) * power, str(other.id) + id)


## How a part breaks: its material, glass for windows.
static func _break_material(p: Dictionary) -> String:
	if str(p.get("kind", "")) == "window":
		return "glass"
	return str(p.get("material", ""))


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
	if body.has_meta("whole") and body.linear_velocity.length() >= FRACTURE_SPEED:
		var id := str(body.get_meta("part"))
		if not _fracture_queue.has(id) and not bus.fractured_ids.has(id):
			_fracture_queue.append(id)


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


func _unregister_all() -> void:
	if net == null:
		return
	net.unregister_mover_group(GROUP)
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
		mark.position = bus.charge_point(id)
		mark.scale = Vector3.ONE * (0.7 + 0.3 * bus.size_of(id))
	_refresh_preview()
	_refresh_panel()


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
	_refresh_debris_zones()
	var doomed: Dictionary = {}
	if _preview and not bus.is_fired():
		for id in bus.predicted():
			doomed[id] = true
		for id: String in bus.charges:
			doomed[id] = true
	var hot := _material("__preview")
	hot.albedo_color = PREVIEW_COLOUR
	for id: String in _chunks:
		var mat: BaseMaterial3D = hot if doomed.has(id) else _part_material(bus.by_id[id])
		for body: RigidBody3D in _chunks[id]:
			if not is_instance_valid(body):
				continue
			for c in body.get_children():
				if c is MeshInstance3D:
					(c as MeshInstance3D).material_override = mat
				elif c.name == "Model":
					# A library model: the game's look, or all in the preview colour when doomed.
					AssetLibrary.apply_look(c)
					if doomed.has(id):
						for mi in c.find_children("*", "MeshInstance3D", true, false):
							(mi as MeshInstance3D).material_override = hot


## Whether a demolition contract is on with a result in (the hand-over button shows).
func job_ready() -> bool:
	var contracts := _career()
	if contracts == null or bus.result.is_empty() or not "active" in contracts:
		return false
	var active: Variant = contracts.get("active")
	return active is Dictionary and str((active as Dictionary).get("mode", "")) == "demolish"


## Hands the cleared site over to the client (contracts judges and pays).
func hand_over() -> void:
	var contracts := _career()
	if job_ready() and contracts.has_method("hand_over"):
		contracts.call("hand_over", 0)


func _show_job() -> void:
	if _job == null:
		return
	_job.visible = job_ready()
	for c in _job_items.get_children():
		c.queue_free()
	if not _job.visible:
		return
	var contracts := _career()
	var verdict: Dictionary = contracts.call("assess") if contracts.has_method("assess") else {}
	for it: Dictionary in verdict.get("items", []):
		var line := BsxTheme.hud_label("%s  %s%s" % ["✓" if bool(it.get("ok", false)) else "✗", str(it.get("label", "")),
				"" if bool(it.get("hard", true)) else "  (goal)"], 14)
		line.modulate = Color(0.7, 1.0, 0.7) if bool(it.get("ok", false)) else Color(1.0, 0.7, 0.6)
		line.tooltip_text = str(it.get("detail", "")) + ("" if str(it.get("tip", "")) == "" else "\n" + str(it.tip))
		line.mouse_filter = Control.MOUSE_FILTER_PASS
		_job_items.add_child(line)
	if verdict.has("summary"):
		var sum := BsxTheme.hud_label(str(verdict.summary), 14)
		_job_items.add_child(sum)


## Where the debris preview says fragments will land: [{part, centre (ground), radius,
## outside (share of the ring off the plot, 0..1)}], shown while previewing with a blast
## consultant. Empty otherwise.
func debris_zones() -> Array[Dictionary]:
	return _debris_zones


func _refresh_debris_zones() -> void:
	_debris_zones.clear()
	if _debris_root == null:
		_debris_root = Node3D.new()
		_debris_root.name = "DebrisPreview"
		add_child(_debris_root)
	for c in _debris_root.get_children():
		c.queue_free()
	if not _preview or bus.is_fired() or not debris_preview_on():
		return
	var ground: float = debris.get("ground_y") if debris else 0.0
	var safe := _material("__debris_safe")
	safe.albedo_color = Color(1.0, 0.75, 0.2, 0.22)
	safe.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	safe.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	safe.cull_mode = BaseMaterial3D.CULL_DISABLED
	var over := _material("__debris_over")
	over.albedo_color = Color(0.9, 0.12, 0.1, 0.35)
	over.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	over.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	over.cull_mode = BaseMaterial3D.CULL_DISABLED
	var spill := 0
	for id: String in bus.charges:
		var at := bus.charge_point(id)
		var r := DemolitionRules.throw_reach(bus.power_of(id), at.y - ground)
		var off := 0
		for k in 16:
			var a := TAU * k / 16.0
			if not bus.on_plot(at.x + cos(a) * r, at.z + sin(a) * r):
				off += 1
		var outside := off / 16.0
		_debris_zones.append({"part": id, "centre": Vector3(at.x, ground, at.z), "radius": r, "outside": outside})
		if outside > 0.0:
			spill += 1
		var disc := MeshInstance3D.new()
		var m := CylinderMesh.new()
		m.top_radius = r
		m.bottom_radius = r
		m.height = 0.02
		m.radial_segments = 32
		m.rings = 1
		disc.mesh = m
		disc.material_override = over if outside > 0.0 else safe
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		disc.position = Vector3(at.x, ground + 0.03, at.z)
		_debris_root.add_child(disc)
	if help and not bus.charges.is_empty():
		help.say("Blast consultant: %s" % ("debris stays on the plot" if spill == 0
				else "%d charge%s will throw debris off the plot (red)" % [spill, "" if spill == 1 else "s"]))


## The part under the mouse, or "".
func part_under_mouse() -> String:
	var mouse := get_viewport().get_mouse_position()
	var q := PhysicsRayQueryParameters3D.create(camera.project_ray_origin(mouse),
			camera.project_ray_origin(mouse) + camera.project_ray_normal(mouse) * 800.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not (hit.collider as Node).has_meta("part"):
		_hover_point = null
		return ""
	_hover_point = hit.position
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
	if not net.is_host():
		return
	if bus.is_active():
		_host_debris()
	if _ball == null:
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
			if is_instance_valid(body) and not body.freeze and not body.sleeping and body.linear_velocity.length() > SETTLE_SPEED:
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
	var outside := 0.0
	var standing := 0.0
	for p: Dictionary in bus.parts:
		if bus.blasted_ids.has(p.id) or str(p.get("family", "")) == "foundation":
			continue
		for body: RigidBody3D in _chunks.get(p.id, []):
			if not is_instance_valid(body):
				continue
			for c in body.get_children():
				if not c is CollisionShape3D:
					continue
				var v := ((c as CollisionShape3D).shape as BoxShape3D).size
				var vol := v.x * v.y * v.z
				if bus.released_ids.has(p.id):
					debris_total += vol
					var at := (c as Node3D).global_position
					if bus.zone.has_point(Vector2(at.x, at.z)):
						debris_in += vol
					if not bus.on_plot(at.x, at.z):
						outside += vol
				else:
					standing += vol
	return DemolitionRules.result(debris_in, debris_total, standing, bus.total_volume(),
			_neighbour_hits.size(), bus.charges.size(), outside)


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
				if mb.pressed and _hover != "" and not bus.is_fired():
					bus.request_charge(_hover, _delay, _hover_point, _size)
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
				_set_delay(_delay - DemolitionBus.DELAY_STEP)
			KEY_BRACKETRIGHT:
				_set_delay(_delay + DemolitionBus.DELAY_STEP)
			KEY_P:
				_set_preview(not _preview)
			KEY_1, KEY_2, KEY_3:
				_set_size((event as InputEventKey).keycode - KEY_1)
			KEY_I:
				walk_inside()
			KEY_F:
				if not driving_crane():
					bus.request_fire()
			KEY_R:
				if not driving_crane():
					bus.request_reset()
			KEY_TAB:
				if _tip == null:
					return
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
	_job = VBoxContainer.new()
	_job.name = "Job"
	_job.visible = false
	col.add_child(_job)
	_job_items = VBoxContainer.new()
	_job.add_child(_job_items)
	_hand_over = Button.new()
	_hand_over.name = "HandOver"
	_hand_over.text = "Hand over the cleared site"
	_hand_over.tooltip_text = "Finish the job: the client judges it on how the building came down"
	_hand_over.pressed.connect(hand_over)
	_job.add_child(_hand_over)
	help = HelpBar.new()
	add_child(help)
	_build_panel(layer)


## The charges panel on the right: charge size, delay, auto-sequence presets, the firing
## timeline in delay groups (pick a group to add to it, move it earlier or later, clear it),
## the fall preview, walking inside, fire and reset.
func _build_panel(layer: CanvasLayer) -> void:
	_panel = PanelContainer.new()
	_panel.name = "ChargesPanel"
	_panel.add_theme_stylebox_override("panel", BsxTheme.panel_style(14))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -330
	_panel.offset_right = -20
	_panel.offset_top = 20
	layer.add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_panel.add_child(col)
	col.add_child(BsxTheme.hud_label("CHARGES", 18))

	var size_row := HBoxContainer.new()
	size_row.add_child(BsxTheme.hud_label("Size", 14))
	for i in DemolitionBus.SIZES.size():
		var b := Button.new()
		b.text = DemolitionBus.SIZES[i]
		b.toggle_mode = true
		b.tooltip_text = "New charges go on %s (key %d): a heavier charge blasts harder and shatters finer" % [DemolitionBus.SIZES[i].to_lower(), i + 1]
		b.pressed.connect(_set_size.bind(i))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_row.add_child(b)
		_size_buttons.append(b)
	col.add_child(size_row)

	var delay_row := HBoxContainer.new()
	delay_row.add_child(BsxTheme.hud_label("Delay", 14))
	var less := Button.new()
	less.text = "-"
	less.tooltip_text = "Earlier: new charges go off sooner after firing ([)"
	less.pressed.connect(func() -> void: _set_delay(_delay - DemolitionBus.DELAY_STEP))
	delay_row.add_child(less)
	_delay_label = BsxTheme.hud_label("0.00 s", 16)
	_delay_label.custom_minimum_size.x = 70
	_delay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	delay_row.add_child(_delay_label)
	var more := Button.new()
	more.text = "+"
	more.tooltip_text = "Later: new charges go off later after firing (])"
	more.pressed.connect(func() -> void: _set_delay(_delay + DemolitionBus.DELAY_STEP))
	delay_row.add_child(more)
	col.add_child(delay_row)

	_sequence = OptionButton.new()
	_sequence.name = "Sequence"
	_sequence.tooltip_text = "Plan it for me: charges on the lowest storey timed to bring the building down that way (replaces the plan)"
	_sequence.add_item("Auto sequence...")
	for key: String in DemolitionRules.SEQUENCES:
		_sequence.add_item(DemolitionRules.SEQUENCES[key])
		_sequence.set_item_metadata(_sequence.item_count - 1, key)
	_sequence.item_selected.connect(func(i: int) -> void:
		if i > 0:
			apply_sequence(str(_sequence.get_item_metadata(i)))
		_sequence.select(0))
	col.add_child(_sequence)

	col.add_child(BsxTheme.hud_label("Timeline", 14))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_panel_box = VBoxContainer.new()
	_panel_box.name = "Groups"
	_panel_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_panel_box)

	var tools := HBoxContainer.new()
	_preview_button = Button.new()
	_preview_button.text = "Preview fall"
	_preview_button.toggle_mode = true
	_preview_button.tooltip_text = "Show in orange what comes down if the charges fire now (P)"
	_preview_button.toggled.connect(_set_preview)
	tools.add_child(_preview_button)
	var clear := Button.new()
	clear.text = "Clear all"
	clear.tooltip_text = "Take every charge off"
	clear.pressed.connect(func() -> void: bus.request_plan({}))
	tools.add_child(clear)
	col.add_child(tools)
	_walk_button = Button.new()
	_walk_button.text = "Walk inside (I)"
	_walk_button.tooltip_text = "Walk round inside the building to put charges on inside walls, columns and floors"
	_walk_button.pressed.connect(walk_inside)
	col.add_child(_walk_button)
	var fire_row := HBoxContainer.new()
	var fire := Button.new()
	fire.text = "FIRE (F)"
	fire.tooltip_text = "Fire: a 3 s countdown, then each charge at its delay"
	fire.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fire.pressed.connect(func() -> void: bus.request_fire())
	fire_row.add_child(fire)
	var reset := Button.new()
	reset.text = "Reset (R)"
	reset.tooltip_text = "Stand the building up again, charges kept"
	reset.pressed.connect(func() -> void: bus.request_reset())
	fire_row.add_child(reset)
	col.add_child(fire_row)
	_set_size(_size)
	_refresh_panel()


## Contracts' unlock ids for each charge size, and for the auto sequences.
const SIZE_GEAR := ["gear:charge_small", "gear:charge_standard", "gear:charge_heavy"]
const PRESET_GEAR := "gear:delay_presets"


## 0 when gear `unlock_id` can be used now, else the career tier that opens it (contracts
## decides; always 0 without a contract or the contracts module).
func locked_tier(unlock_id: String) -> int:
	var contracts := _career()
	if contracts == null or not contracts.has_method("locked_tier"):
		return 0
	return int(contracts.call("locked_tier", unlock_id))


## Who says what's unlocked: the contracts bus, or `career` when set (tests).
var career: Object = null


func _career() -> Object:
	return career if career != null else Modules.bus("contracts")


## Whether the firm's blast consultant shows where debris will land with the fall preview.
func debris_preview_on() -> bool:
	var contracts := _career()
	return contracts != null and contracts.has_method("effect") and float(contracts.call("effect", "debris_preview", 0.0)) > 0.0


func _set_size(i: int) -> void:
	var want := clampi(i, 0, DemolitionBus.SIZES.size() - 1)
	var tier := locked_tier(SIZE_GEAR[want])
	if tier > 0:
		if help:
			help.say("%s charges open at career tier %d" % [DemolitionBus.SIZES[want], tier])
		if locked_tier(SIZE_GEAR[_size]) == 0:
			want = _size
		else:
			# The biggest size that is open (the small charge is always tier 1).
			want = 0
			for k in SIZE_GEAR.size():
				if locked_tier(SIZE_GEAR[k]) == 0:
					want = k
	_size = want
	_refresh_locks()


## Greys out the charge sizes and auto sequences the career hasn't opened yet.
func _refresh_locks() -> void:
	for k in _size_buttons.size():
		var tier := locked_tier(SIZE_GEAR[k])
		var b := _size_buttons[k]
		b.disabled = tier > 0
		b.set_pressed_no_signal(k == _size)
		b.tooltip_text = ("%s charges open at career tier %d" % [DemolitionBus.SIZES[k], tier]) if tier > 0 \
				else "New charges go on %s (key %d): a heavier charge blasts harder and shatters finer" % [DemolitionBus.SIZES[k].to_lower(), k + 1]
	if _sequence:
		var tier := locked_tier(PRESET_GEAR)
		for i in range(1, _sequence.item_count):
			_sequence.set_item_disabled(i, tier > 0)
		_sequence.set_item_text(0, "Auto sequence (tier %d)..." % tier if tier > 0 else "Auto sequence...")


func _set_delay(d: float) -> void:
	_delay = clampf(snappedf(d, DemolitionBus.DELAY_STEP), 0.0, DemolitionBus.MAX_DELAY)
	_refresh_panel()


func _set_preview(on: bool) -> void:
	_preview = on
	if _preview_button:
		_preview_button.set_pressed_no_signal(on)
	_refresh_preview()


## Replaces the plan with an auto-sequence preset (DemolitionRules.SEQUENCES), every charge
## at the chosen size, and shows the fall.
func apply_sequence(preset: String) -> void:
	var tier := locked_tier(PRESET_GEAR)
	if tier > 0:
		help.say("Auto sequences open at career tier %d" % tier)
		return
	var plan := {}
	var seq := DemolitionRules.sequence(bus.parts, preset, DemolitionBus.MAX_CHARGES)
	for id: String in seq:
		plan[id] = {"delay": seq[id], "size": _size}
	bus.request_plan(plan)
	_set_preview(true)
	help.say("%s: %d charges on the lowest storey" % [DemolitionRules.SEQUENCES.get(preset, preset), plan.size()])


## The firing timeline as delay groups: [[delay, [part ids]], ...], earliest first.
func groups() -> Array:
	var by_delay := {}
	for id: String in bus.charges:
		var d := float(bus.charges[id])
		if not by_delay.has(d):
			by_delay[d] = []
		by_delay[d].append(id)
	var out: Array = []
	for d: float in by_delay:
		out.append([d, by_delay[d]])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return out


## Moves every charge in the group at `delay` by `by` seconds (merging with a group there).
func shift_group(delay: float, by: float) -> void:
	var plan := bus.plan()
	for id: String in plan:
		if is_equal_approx(float(plan[id].delay), delay):
			plan[id].delay = clampf(float(plan[id].delay) + by, 0.0, DemolitionBus.MAX_DELAY)
	bus.request_plan(plan)


func remove_group(delay: float) -> void:
	var plan := bus.plan()
	for id: String in plan.keys():
		if is_equal_approx(float(plan[id].delay), delay):
			plan.erase(id)
	bus.request_plan(plan)


func _refresh_panel() -> void:
	if _panel_box == null:
		return
	_delay_label.text = "%.2f s" % _delay
	_refresh_locks()
	_walk_button.visible = _walk_model() != null
	for c in _panel_box.get_children():
		c.queue_free()
	var gs := groups()
	if gs.is_empty():
		_panel_box.add_child(BsxTheme.hud_label("No charges yet: click a column or wall, or pick an auto sequence.", 13))
		(_panel_box.get_child(_panel_box.get_child_count() - 1) as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	for g: Array in gs:
		var d: float = g[0]
		var ids: Array = g[1]
		var row := HBoxContainer.new()
		var pick := Button.new()
		pick.text = "%s%.2f s  ·  %d" % ["> " if is_equal_approx(d, _delay) else "", d, ids.size()]
		pick.flat = true
		pick.tooltip_text = "Add new charges to this group: %s" % ", ".join(ids.map(func(i: String) -> String: return _part_name(i)))
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pick.pressed.connect(_set_delay.bind(d))
		row.add_child(pick)
		for spec: Array in [["<", -DemolitionBus.DELAY_STEP, "Earlier"], [">", DemolitionBus.DELAY_STEP, "Later"]]:
			var b := Button.new()
			b.text = spec[0]
			b.tooltip_text = "%s: move this whole group %.2f s %s" % [spec[2], DemolitionBus.DELAY_STEP, str(spec[2]).to_lower()]
			b.pressed.connect(shift_group.bind(d, float(spec[1])))
			row.add_child(b)
		var x := Button.new()
		x.text = "x"
		x.tooltip_text = "Take this group's charges off"
		x.pressed.connect(remove_group.bind(d))
		row.add_child(x)
		_panel_box.add_child(row)


## "Column, ground floor" for a part id.
func _part_name(id: String) -> String:
	var p: Dictionary = bus.by_id.get(id, {})
	if p.is_empty():
		return id
	var level := int(p.get("level", 0))
	return "%s, %s" % [str(p.get("family", "part")).capitalize(), "ground floor" if level == 0 else "floor %d" % level]


## The building model to walk round: the design this demolition came from, when its parts
## are the model's (and the walk-inside module is loaded with a charges mode).
func _walk_model() -> BuildingModel:
	var walk := Modules.bus("walk")
	if walk == null or not walk.has_method("open") or not bus.is_active() or bus.is_fired():
		return null
	var count := 0
	for m: Dictionary in walk.get_method_list():
		if str(m.name) == "open":
			count = (m.args as Array).size()
	if count < 5:
		return null
	var model := bus.model
	if model == null:
		var building := Modules.bus("building") as BuildingBus
		model = building.model if building else null
	if model == null or bus.parts.is_empty() or not model.parts.has(str(bus.parts[0].id)):
		return null
	return model


## Walks inside the building to place charges (the walk module's charges mode).
func walk_inside() -> void:
	var model := _walk_model()
	if model == null:
		return
	Modules.bus("walk").call("open", model, self, {}, null, {"mode": "charges"})


## The help line: what to do in the mode the player is in (crane, charging, after firing).
func _update_help() -> void:
	var view := [["right drag", "orbit"], ["wheel", "zoom"], ["Esc", "menu"]]
	if driving_crane():
		help.set_help("CRANE", HelpBar.keys_text([["A D", "slew"], ["W S", "reach"], ["Q E", "cable"],
				["Tab", "leave the crane"]] + view), BsxTheme.LIVE)
	elif bus.is_active() and bus.is_fired():
		help.set_help("COLLAPSE", HelpBar.keys_text([["R", "reset and try again"]] + view), BsxTheme.WARN)
	elif bus.is_active():
		help.set_help("PLACE CHARGES", HelpBar.keys_text([["click a part", "charge it (again: take it off)"],
				["[ ]", "delay"], ["1 2 3", "size"], ["P", "preview"], ["F", "fire"], ["R", "reset"]]
				+ ([["I", "walk inside"]] if _walk_button and _walk_button.visible else [])
				+ ([["Tab", "crane"]] if _tip != null else []) + view))
	else:
		help.set_help("DEMOLITION", "Nothing to demolish yet: build something first.")
	if _hover != "":
		help.hover(_hover_text(_hover))


## "Column · ground floor · charged, 0.25 s" for the part under the pointer.
func _hover_text(id: String) -> String:
	var line := id
	for p: Dictionary in bus.parts:
		if str(p.id) == id:
			var level := int(p.get("level", 0))
			line = "%s  ·  %s" % [str(p.get("family", "part")).capitalize(),
					"ground floor" if level == 0 else "floor %d" % level]
			break
	if bus.charges.has(id):
		line += "  ·  %s charge, %.2f s  ·  click again to take it off" % [str(DemolitionBus.SIZES[bus.size_of(id)]).to_lower(), float(bus.charges[id])]
	elif not bus.is_fired():
		line += "  ·  click to put a %s charge on it at %.2f s" % [str(DemolitionBus.SIZES[_size]).to_lower(), _delay]
	return line


func _update_hud() -> void:
	_update_help()
	if not bus.is_active():
		_status.text = "Nothing to demolish yet."
		return
	var line := "%s  ·  delay %.2fs" % [bus.title.to_upper(), _delay]
	if bus.is_fired():
		var c := bus.countdown()
		line += "  ·  FIRING IN %.1f" % c if c > 0.0 else "  ·  FIRED"
	var owner := net.claim_owner(CRANE_ID)
	if owner != 0:
		line += "  ·  crane: %s" % net.player_name(owner)
	_status.text = line
	var gs := groups()
	_plan.text = "Charges %d/%d" % [bus.charges.size(), DemolitionBus.MAX_CHARGES] + \
			("  ·  %d groups, %.2f to %.2f s" % [gs.size(), gs[0][0], gs.back()[0]] if not gs.is_empty() else "  ·  none yet")


func _show_result() -> void:
	var r := bus.result
	# Contracts judges the job from the same result: let it see it first.
	_show_job.call_deferred()
	if r.is_empty():
		_result.text = ""
		return
	_result.text = "%s  ·  %d / 100  ·  down %d%%  ·  in zone %d%%  ·  off the plot %d%%  ·  neighbours hit %d  ·  charges %d" % [
			str(r.get("grade", "")).to_upper(), int(r.get("score", 0)), int(float(r.get("down", 0)) * 100.0),
			int(float(r.get("contained", 0)) * 100.0), int(float(r.get("debris_outside", 0)) * 100.0),
			int(r.get("neighbour_hits", 0)), int(r.get("charges_used", r.get("charges", 0)))]
