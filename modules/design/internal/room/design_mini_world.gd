class_name DesignMiniWorld
extends SubViewport
## A second, whole copy of the design for the designer's small views (the 3D view top right
## and the section): every level shows and nothing is cut, whatever the main view is doing.
## Each player's pointer stands in it as a marker in their colour. It is redrawn only while
## a small view is up, at most every REDRAW s, so it costs nothing in the plan alone.
##
## It is the source the small views' cameras (HallChannels.ModelChannel) ask for the world,
## the building's extent and the floor.

const DesignView := preload("res://modules/design/internal/room/design_view.gd")

## Edits show in the small views at most this often, s.
const REDRAW := 0.3

var session: DesignSession
var view: Node3D
## Small views showing now (each says so while it is visible).
var watchers := 0
var _age := 10.0
var _bounds := AABB(Vector3(-10, 0, -10), Vector3(20, 6, 20))
var _bounds_rev := -1
var _markers: Dictionary = {}  # peer -> Node3D


func setup(p_session: DesignSession) -> void:
	session = p_session
	name = "MiniWorld"
	own_world_3d = true
	size = Vector2i(2, 2)
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(35), 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	# The designer's own sky, so the small views look like the big one.
	e.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.85)
	sky_mat.sky_horizon_color = Color(0.78, 0.84, 0.9)
	sky_mat.ground_horizon_color = Color(0.6, 0.62, 0.6)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	view = DesignView.new()
	view.name = "Building"
	add_child(view)
	view.call("bind", session.model)
	view.call("show_level", 1000)
	view.set_process(false)


func _process(delta: float) -> void:
	_age += delta
	if watchers <= 0:
		return
	if _age >= REDRAW:
		_age = 0.0
		view.call("flush")
	_place_markers()


## The world the small views look into.
func model_world() -> World3D:
	return find_world_3d()


## The building's extent (world m).
func bounds() -> AABB:
	if session.model.revision != _bounds_rev:
		_bounds_rev = session.model.revision
		_bounds = model_bounds(session.model)
	return _bounds


func floor_y() -> float:
	return session.floor_y()


## The designer works out the pointer itself from the view under the mouse.
func set_pointer(_at: Variant) -> void:
	pass


## The building's extent (world m): its parts and room outlines; a default plot when empty.
static func model_bounds(model: BuildingModel) -> AABB:
	var first := true
	var box := AABB()
	for id: String in model.parts:
		var b: AABB = model.aabb_of(id)
		box = b if first else box.merge(b)
		first = false
	for id: String in model.rooms:
		for p: Variant in model.rooms[id].outline:
			var v := Vector3(float(p[0]), model.level_elevation(int(model.rooms[id].level)), float(p[1]))
			box = AABB(v, Vector3.ZERO) if first else box.expand(v)
			first = false
	if first:
		return AABB(Vector3(-10, 0, -10), Vector3(20, 6, 20))
	box.size.y = maxf(box.size.y, 3.0)
	return box


## Every player's pointer now: peer -> {at, colour, name}. This player's own, the others'
## (the designer's presence) and anyone walking inside the design (WalkBus, if there).
static func pointers_of(pres: DesignPresence, net: MultiplayerBus) -> Dictionary:
	var out := {}
	var me := net.local_peer_id()
	if pres.my_cursor.position.y > DesignPresence.HIDDEN_Y + 1.0:
		out[me] = {"at": pres.my_cursor.position, "colour": net.player_colour(me), "name": net.player_name(me)}
	var others := pres.others()
	for peer: int in others:
		if others[peer].cursor != null:
			out[peer] = {"at": others[peer].cursor, "colour": net.player_colour(peer), "name": net.player_name(peer)}
	var walk := Modules.bus("walk")
	if walk and "walkers" in walk:
		var walkers: Dictionary = walk.get("walkers")
		for peer: int in walkers:
			var w: Dictionary = walkers[peer]
			if w.has("pos"):
				out[peer] = {"at": w.pos, "colour": net.player_colour(peer), "name": net.player_name(peer)}
	return out


func marker_count() -> int:
	return _markers.size()


func _place_markers() -> void:
	var want := pointers_of(session.presence, session.net)
	for peer: int in _markers.keys():
		if not want.has(peer):
			(_markers[peer] as Node).queue_free()
			_markers.erase(peer)
	for peer: int in want:
		var w: Dictionary = want[peer]
		if not _markers.has(peer):
			_markers[peer] = _marker(w.colour as Color, str(w.name))
		(_markers[peer] as Node3D).position = w.at as Vector3


func _marker(colour: Color, label_text: String) -> Node3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = colour
	mat.no_depth_test = true
	var root := Node3D.new()
	root.name = "Pointer"
	var ball := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.25
	sph.height = 0.5
	ball.mesh = sph
	ball.material_override = mat
	ball.position.y = 0.25
	root.add_child(ball)
	var label := Label3D.new()
	label.text = label_text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0015
	label.modulate = colour
	label.outline_size = 8
	label.font_size = 32
	label.position.y = 0.8
	root.add_child(label)
	add_child(root)
	return root
