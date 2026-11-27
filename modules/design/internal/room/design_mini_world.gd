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
## Small views showing now; each says so with watch() every frame it is visible.
var watchers := 0
var _watched_frame := -10
## Where a pointer on one of the views goes (the hall's set_pointer); unset, the designer
## works it out from the view under the mouse.
var pointer_sink := Callable()
var _age := 10.0
var _bounds: DesignBounds
var _markers: Dictionary = {}  # peer -> Node3D


## The ground plane, for the look to change.
var _ground: MeshInstance3D

func setup(p_session: DesignSession) -> void:
	session = p_session
	_bounds = DesignBounds.new(session.model)
	name = "MiniWorld"
	own_world_3d = true
	size = Vector2i(2, 2)
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(35), 0)
	# No shadows: the plan, side and section drawings read cleaner without them.
	sun.shadow_enabled = false
	sun.set_meta("gfx_no_shadow", true)
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
	# The site's ground, as in the designer, so the plan reads against it.
	var ground := MeshInstance3D.new()
	_ground = ground
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1000, 1000)
	ground.mesh = plane
	ground.material_override = ArtStyle.ground()
	ground.position.y = -0.02
	add_child(ground)
	Graphics.changed.connect(_on_look_changed)
	add_child(DesignPlot.new())
	add_child(DesignSite.new(ground))
	view = DesignView.new()
	view.name = "Building"
	view.set("labels_fixed", false)
	add_child(view)
	add_child(DesignLayers.new(session.model, view))
	view.call("bind", session.model)
	view.call("show_level", 1000)
	view.set_process(false)


func _process(delta: float) -> void:
	_age += delta
	if watchers <= 0 and Engine.get_process_frames() - _watched_frame > 2:
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
	return _bounds.box()


func floor_y() -> float:
	return session.floor_y()


func set_pointer(at: Variant) -> void:
	if pointer_sink.is_valid():
		pointer_sink.call(at)


## Pings that spot of the design for everyone (a middle-click on one of the views).
func ping_at(at: Variant) -> void:
	if not at is Vector3:
		return
	# Through the open designer when there is one: a click on a ping clears it.
	var room := (Modules.bus("design") as DesignBus).open_room
	if room and room.has_method("ping_here"):
		room.call("ping_here", at)
		return
	var p := session.snap(at as Vector3)
	var id := session.pick(p)
	session.net.ping(p, id, Vector3.UP, session.label_of(id))


## A view showing this world says so each frame (ModelChannel does).
func watch() -> void:
	_watched_frame = Engine.get_process_frames()


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


## The ground takes the new look (a method, not a lambda, so it disconnects when freed).
func _on_look_changed() -> void:
	if is_instance_valid(_ground):
		_ground.material_override = ArtStyle.ground()
