extends Node3D
## The co-op design room: the shared plot, the building drawn from the model, every player's
## cursor, drag line, selection and locks in their colour, the ghost of this player's tool,
## and the HUD (tools, levels, grid, 2D/3D, undo and redo, save and load, live costs).
## Other players' avatars are put in this scene by the multiplayer module and follow their
## cameras, so in 3D everyone sees where everyone is looking from.
##
## Mouse: left click or drag uses the tool, right drag orbits (3D) or cancels (2D), middle
## drag pans, wheel zooms. Keys: 1-0 tools, Tab 2D/3D, Page Up/Down level, Ctrl+Z undo,
## Ctrl+Y redo, Del delete, R turn, T retag room, Esc cancel, then pause.

const DesignView := preload("res://modules/design/internal/room/design_view.gd")
const DesignCamera := preload("res://modules/design/internal/room/design_camera.gd")
const DesignHud := preload("res://modules/design/internal/room/design_hud.gd")
const DesignMarks := preload("res://modules/design/internal/room/design_marks.gd")
## A middle press that moves less than this before it lets go is a ping, not a pan, px.
const TAP_SLOP := 6.0
## Holding the middle button still this long opens the mark-up wheel, s.
const WHEEL_HOLD := 0.3
const DesignWheel := preload("res://modules/design/internal/room/design_wheel.gd")

## How far out you can build and look: the graph paper never ends, so this is just far.
const PLOT_HALF := 1500.0
const GROUND := Color(0.5, 0.58, 0.45)
const MINE := Color(1.0, 0.85, 0.2)
## Height the 2D plan cuts the walls at, m (doors and windows show below it).
const PLAN_CUT := 1.2

var net: MultiplayerBus
var building: BuildingBus
var design: DesignBus
var session: DesignSession
var view: Node3D
var camera: Camera3D
var hud: Control
var _grid_mesh: InfiniteGrid
var _ghost: MeshInstance3D
## The live size of what is being drawn: width x length and area.
var ghost_dims: Label3D
## The taken contract's plot, a red line.
var plot: DesignPlot
var _crew_marks: Node3D
var _marks: Dictionary = {}  # peer -> {root, line, label}
var _ghost_mats: Dictionary = {}
var _tint_dirty := true
## Entries flashing (DesignBus.pulse): id -> time the flash ends, s.
var _pulses: Dictionary = {}
const PULSE := Color(0.3, 1.0, 0.55)
const PULSE_TIME := 1.2
var _left_down := false
var _sun: DirectionalLight3D
## The view this player looks through: "" (Architect) or a DesignBus overlay id.
var overlay := ""
var marks: Node3D
var _middle_from: Variant = null
var _middle_t := 0.0
var _middle_moved := false
var wheel: Control
## The right-click menu and edit form.
var context: Node
var _right_from: Variant = null
## Opened from the hall's holotable (DesignHall): drawn into the hall's designer screen, and Esc
## goes back to the hall instead of the pause menu.
var embedded := false
## Taking the mouse and keys (false while the hall is shown and the designer is put away).
var active := true
## R held (a tap turns 90°, held with the mouse turns freely), and how far the mouse went.
var _r_held := false
var _r_px := 0.0
## Mouse pixels per degree while turning with R held.
const TURN_PX := 4.0
## True while another camera (walk-inside) has this room's view.
var lent_view := false
## Esc with nothing to cancel, while embedded: back to the hall.
signal leave_requested


func _ready() -> void:
	net = Modules.bus("multiplayer") as MultiplayerBus
	building = Modules.bus("building") as BuildingBus
	design = Modules.bus("design") as DesignBus
	session = DesignSession.new()
	session.name = "Session"
	add_child(session)
	session.setup(net, building.model, building.sync)
	session.grid = float(Settings.get_value(DesignBus.SETTINGS, "grid"))
	session.auto_walls = bool(Settings.get_value(DesignBus.SETTINGS, "auto_walls"))
	_build_world()
	view = DesignView.new()
	view.name = "Building"
	add_child(view)
	add_child(DesignLayers.new(building.model, view))
	view.bind(building.model)
	marks = DesignMarks.new()
	marks.name = "Marks"
	add_child(marks)
	marks.call("bind", building.model, net)
	session.measure_changed.connect(func(a: Variant, b: Variant) -> void: marks.call("set_measure", a, b))
	_crew_marks = Node3D.new()
	_crew_marks.name = "CrewMarks"
	add_child(_crew_marks)
	_ghost = MeshInstance3D.new()
	_ghost.name = "Ghost"
	_ghost.mesh = ImmediateMesh.new()
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)
	plot = DesignPlot.new()
	add_child(plot)
	# Live size while a room or slab is dragged out or reshaped.
	ghost_dims = Label3D.new()
	ghost_dims.name = "GhostDims"
	ghost_dims.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	ghost_dims.no_depth_test = true
	ghost_dims.fixed_size = true
	ghost_dims.pixel_size = 0.0013
	ghost_dims.font_size = 30
	ghost_dims.outline_size = 10
	ghost_dims.outline_modulate = Color(1, 1, 1, 0.9)
	ghost_dims.modulate = Color(0.1, 0.2, 0.45)
	ghost_dims.visible = false
	add_child(ghost_dims)
	hud = DesignHud.new()
	hud.room = self
	var layer := CanvasLayer.new()
	layer.name = "Hud"
	add_child(layer)
	layer.add_child(hud)
	context = preload("res://modules/design/internal/room/design_context.gd").new()
	add_child(context)
	context.call("setup", session, hud)
	wheel = DesignWheel.new()
	wheel.name = "Wheel"
	layer.add_child(wheel)
	session.preview_changed.connect(_draw_ghost)
	session.level_changed.connect(_on_level)
	session.note_requested.connect(func(at: Vector3, target: String) -> void: hud.call("ask_note", at, target))
	session.presence.selection_changed.connect(func(_p: int, _ids: PackedStringArray) -> void:
		_tint_dirty = true
		_draw_ghost())
	session.presence.locks_changed.connect(func() -> void: _tint_dirty = true)
	session.presence.pulsed.connect(_on_pulsed)
	design.pulse_requested.connect(_on_pulse_requested)
	# Only an overlay's colours depend on the building itself.
	building.model.changed.connect(func(_op: Dictionary) -> void: _tint_dirty = _tint_dirty or overlay != "")
	building.model.loaded.connect(func() -> void: _tint_dirty = true)
	design.overlay_changed.connect(func(id: String) -> void:
		if id == overlay:
			_tint_dirty = true)
	design.overlays_changed.connect(func() -> void:
		if overlay != "" and not design.overlays.has(overlay):
			set_overlay(""))
	_on_level(0)
	session.set_tool("room")
	session.tool_changed.connect(func(_t: String) -> void: end_stamp())
	design.open_room = self


# --- Stamp (placing a saved module, or anything another module hands over) -------------------

var _stamp: Dictionary = {}  # {label, ghost: Node3D, ops_at: Callable, rot}


## A ghost under the pointer that a click places (DesignBus.begin_stamp).
func begin_stamp(label: String, ghost: Node3D, ops_at: Callable) -> void:
	session.set_tool("select")  # ends any stamp before
	end_stamp()
	if ghost:
		add_child(ghost)
	_stamp = {"label": label, "ghost": ghost, "ops_at": ops_at, "rot": 0.0}
	session.status.emit("%s: click to place it, R turns it, Esc stops" % label, false)


## Ctrl+V: the copy (DesignBus.clipboard) in hand at the pointer, lined up by the guides;
## each click puts one down (R or Shift+wheel turns it, Esc stops).
func paste() -> bool:
	var clip: Dictionary = design.clipboard if design else {}
	if clip.is_empty():
		session.status.emit("Nothing copied yet: select something and Ctrl+C", true)
		return false
	begin_stamp("Paste %s" % str(clip.get("label", "")), _paste_ghost(clip), func(_level: int, at: Vector3, rot: float) -> Array:
		return session.paste_here(clip, at, rot))
	_stamp["size"] = clip.get("size", Vector2.ZERO)
	return true


## The copy drawn see-through, as it will land, for carrying at the pointer.
func _paste_ghost(clip: Dictionary) -> Node3D:
	var m := BuildingModel.new()
	var fresh: Array = []
	for i in (clip.get("items", []) as Array).size():
		fresh.append("p%d" % (i + 1))
	for op: Dictionary in DesignSession.paste_ops(clip, 0, Vector3.ZERO, 0.0, fresh):
		m.apply(op)
	var v: Node3D = DesignView.new()
	v.name = "PasteGhost"
	v.set_meta("model", m)  # keeps it alive with the ghost
	v.call("bind", m)
	v.call("set_ghost", true)
	return v


func end_stamp() -> void:
	if _stamp.is_empty():
		return
	if is_instance_valid(_stamp.ghost):
		(_stamp.ghost as Node).queue_free()
	_stamp = {}


func stamping() -> bool:
	return not _stamp.is_empty()


## Places the stamp at `at` (world, snapped).
func stamp_at(at: Vector3) -> void:
	if _stamp.is_empty():
		return
	var ops: Variant = (_stamp.ops_at as Callable).call(session.level, at, float(_stamp.rot))
	if ops is Array and not (ops as Array).is_empty():
		session.sync.edit(BuildingCommands.batch(ops as Array))


func _place_stamp_ghost() -> void:
	if _stamp.is_empty() or not is_instance_valid(_stamp.ghost):
		return
	var g := _stamp.ghost as Node3D
	g.visible = session.cursor != null
	if session.cursor != null:
		g.position = session.cursor as Vector3
		g.rotation.y = deg_to_rad(float(_stamp.rot))


func _exit_tree() -> void:
	if design and design.open_room == self:
		design.open_room = null
	end_stamp()
	if session:
		session.teardown()


# --- World ------------------------------------------------------------------------------

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.85)
	sky_mat.sky_horizon_color = Color(0.78, 0.84, 0.9)
	sky_mat.ground_horizon_color = Color(0.6, 0.62, 0.6)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	_sun = DirectionalLight3D.new()
	var sun := _sun
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(-30.0), 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(PLOT_HALF + 1000.0, PLOT_HALF + 1000.0) * 2.0
	ground.mesh = plane
	ground.material_override = ArtStyle.ground()
	Graphics.changed.connect(func() -> void: ground.material_override = ArtStyle.ground())
	ground.position.y = -0.01
	add_child(ground)
	# A real site (the sites module), when one is loaded, in place of the plain ground.
	add_child(DesignSite.new(ground))
	_grid_mesh = InfiniteGrid.new()
	add_child(_grid_mesh)
	camera = DesignCamera.new()
	camera.name = "Camera"
	camera.limit = PLOT_HALF
	add_child(camera)
	camera.make_current()


## The working level's graph paper: 1 m lines, every 5 m darker, without end, and the snap
## grid near the focus.
func _draw_grid() -> void:
	_grid_mesh.height = session.floor_y() + 0.015
	_grid_mesh.set_snap(session.grid, (camera as DesignCamera).focus)


func _on_level(l: int) -> void:
	view.show_level(l)
	marks.call("set_level", l)
	_draw_grid()
	var cam := camera as DesignCamera
	cam.focus.y = session.floor_y()


# --- Frame ------------------------------------------------------------------------------

var _last_focus := Vector3.INF


func _process(_delta: float) -> void:
	var cam := camera as DesignCamera
	if _middle_from != null and not _middle_moved and not wheel.get("is_open") \
			and _now() - _middle_t >= WHEEL_HOLD:
		open_wheel(_middle_from)
	if cam.focus.distance_to(_last_focus) > 2.0:
		_last_focus = cam.focus
		_draw_grid()
	# Another camera has the view (walking inside the design): the designer steps aside,
	# HUD and all, and comes back when it is given back.
	var lent := active and get_viewport().get_camera_3d() != camera
	if lent != lent_view:
		lent_view = lent
		hud.visible = active and not lent
		if lent:
			session.hover(null)
	if active and not lent_view:
		session.placing = stamping()
		var ps: Vector2 = _stamp.get("size", Vector2.ZERO)
		var turned := fmod(absf(float(_stamp.get("rot", 0.0))), 180.0)
		session.placing_size = Vector2(ps.y, ps.x) if absf(turned - 90.0) < 45.0 else ps
	if not active or lent_view:
		pass
	elif _pointer_over_hud():
		# Over one of the small views (3D, section), the pointer is where it points in there.
		var c := get_viewport().gui_get_hovered_control()
		session.hover(c.call("floor_point", c.get_local_mouse_position()) if c.has_method("floor_point") else null)
	else:
		session.hover(_floor_point())
	_place_stamp_ghost()
	# Handles stay about 10 px wherever the zoom is.
	var reach := clampf(cam.metres_per_pixel() * 12.0, 0.08, 3.0)
	if absf(reach - session.handle_reach) > session.handle_reach * 0.1:
		session.handle_reach = reach
		_draw_ghost()
	if not _pulses.is_empty():
		var t := _now()
		for id: String in _pulses.keys():
			if t >= float(_pulses[id]):
				_pulses.erase(id)
				_tint_dirty = true
	if _tint_dirty:
		_tint_dirty = false
		_update_tints()
	_update_crew_marks()


func _on_pulse_requested(ids: PackedStringArray) -> void:
	session.presence.pulse(ids)


func _on_pulsed(ids: PackedStringArray) -> void:
	for id in ids:
		_pulses[id] = _now() + PULSE_TIME
	_tint_dirty = true


## Entries flashing now.
func pulsing() -> PackedStringArray:
	return PackedStringArray(_pulses.keys())


func _floor_point() -> Variant:
	var cam := camera as DesignCamera
	var hit: Variant = cam.ground_point(get_viewport().get_mouse_position(), session.floor_y())
	if hit == null:
		return null
	var p: Vector3 = hit
	if absf(p.x) > PLOT_HALF or absf(p.z) > PLOT_HALF:
		return null
	return p


func _pointer_over_hud() -> bool:
	var c := get_viewport().gui_get_hovered_control()
	return c != null and c.mouse_filter != Control.MOUSE_FILTER_IGNORE


## Selection and lock colours: mine in yellow, other players' in their colour.
func _update_tints() -> void:
	var want := {}
	if overlay != "" and design.overlays.has(overlay):
		var got: Variant = (design.overlays[overlay].tints as Callable).call(building.model)
		if got is Dictionary:
			want.merge(got, true)
	var p := session.presence
	for peer: int in p.selections:
		var colour := MINE if peer == net.local_peer_id() else net.player_colour(peer)
		for id in p.selections[peer]:
			want[id] = colour
	for id: String in p.held:
		var owner := p.locked_by(id)
		if owner != 0 and owner != net.local_peer_id() and building.model.has(id):
			want[id] = net.player_colour(owner).lightened(0.2)
	for id: String in _pulses:
		want[id] = PULSE
	for id: String in view.tints():
		if not want.has(id):
			view.tint(id, null)
	for id: String in want:
		view.tint(id, want[id])


func _update_crew_marks() -> void:
	var others := session.presence.others()
	for peer: int in _marks.keys():
		if not others.has(peer):
			(_marks[peer].root as Node).queue_free()
			_marks.erase(peer)
	for peer: int in others:
		if not _marks.has(peer):
			_marks[peer] = _make_mark(peer)
		var m: Dictionary = _marks[peer]
		var c: Variant = others[peer].cursor
		var a: Variant = others[peer].anchor
		var root: Node3D = m.root
		root.visible = c != null
		if c == null:
			continue
		root.global_position = c
		(m.label as Label3D).text = "%s\n%s" % [net.player_name(peer), net.activity(peer).trim_prefix("Design: ")]
		var im: ImmediateMesh = (m.line as MeshInstance3D).mesh
		im.clear_surfaces()
		if a != null and (a as Vector3).distance_to(c) > 0.01:
			im.surface_begin(Mesh.PRIMITIVE_LINES, m.mat)
			im.surface_add_vertex((a as Vector3) + Vector3(0, 0.05, 0))
			im.surface_add_vertex((c as Vector3) + Vector3(0, 0.05, 0))
			var ac := a as Vector3
			var cc := c as Vector3
			for corner: Vector3 in [Vector3(ac.x, ac.y, cc.z), Vector3(cc.x, ac.y, ac.z)]:
				im.surface_add_vertex(ac + Vector3(0, 0.05, 0))
				im.surface_add_vertex(corner + Vector3(0, 0.05, 0))
				im.surface_add_vertex(corner + Vector3(0, 0.05, 0))
				im.surface_add_vertex(cc + Vector3(0, 0.05, 0))
			im.surface_end()


func _make_mark(peer: int) -> Dictionary:
	var colour := net.player_colour(peer)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	var root := Node3D.new()
	root.name = "Mark_%d" % peer
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.18
	torus.outer_radius = 0.26
	ring.mesh = torus
	ring.material_override = mat
	ring.position.y = 0.04
	root.add_child(ring)
	var post := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.025
	cyl.height = 1.0
	post.mesh = cyl
	post.material_override = mat
	post.position.y = 0.5
	root.add_child(post)
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = colour
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.outline_size = 10
	label.font_size = 40
	label.pixel_size = 0.01
	label.position.y = 1.35
	root.add_child(label)
	_crew_marks.add_child(root)
	var line := MeshInstance3D.new()
	line.mesh = ImmediateMesh.new()
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crew_marks.add_child(line)
	root.tree_exiting.connect(line.queue_free)
	return {"root": root, "line": line, "label": label, "mat": mat}


## The ghost of this player's tool: the wall or beam line, the rectangle, the point, the
## opening on its wall, or the parts being dragged at their new place.
func _draw_ghost() -> void:
	var im: ImmediateMesh = _ghost.mesh
	im.clear_surfaces()
	var pv := session.preview()
	var y := session.floor_y() + 0.06
	var mat := _ghost_mat(MINE)
	_draw_handles(im, y + 0.02)
	ghost_dims.visible = false
	# Alignment guides: what's being placed lines up with this.
	if not session.guides.is_empty():
		var gm := _ghost_mat(DesignGuides.COLOUR)
		for g: Array in session.guides:
			var a2: Vector2 = g[0]
			var b2: Vector2 = g[1]
			_ghost_lines(im, gm, [Vector3(a2.x, 0, a2.y), Vector3(b2.x, 0, b2.y)], y + 0.03)
	match str(pv.get("kind", "")):
		"line":
			_ghost_lines(im, mat, [pv.a, pv.b], y)
		"rect":
			var a: Vector3 = pv.a
			var b: Vector3 = pv.b
			_ghost_lines(im, mat, [a, Vector3(b.x, 0, a.z), b, Vector3(a.x, 0, b.z), a], y)
			var w := absf(b.x - a.x)
			var d := absf(b.z - a.z)
			_show_dims((a + b) * 0.5, y, "%.2f × %.2f m\n%.1f m²" % [w, d, w * d])
		"point":
			var p: Vector3 = pv.at
			_ghost_lines(im, mat, [p + Vector3(-0.3, 0, 0), p + Vector3(0.3, 0, 0)], y)
			_ghost_lines(im, mat, [p + Vector3(0, 0, -0.3), p + Vector3(0, 0, 0.3)], y)
		"opening":
			var wall := str(pv.wall)
			var p: Vector3 = pv.at
			if wall == "":
				_ghost_lines(im, _ghost_mat(Color(1, 0.4, 0.3)), [p + Vector3(-0.2, 0, -0.2), p + Vector3(0.2, 0, 0.2)], y)
			else:
				var e: Dictionary = building.model.parts[wall]
				var a := Vector3(e.a[0], 0, e.a[2])
				var b := Vector3(e.b[0], 0, e.b[2])
				var dir := (b - a).normalized()
				var t := DesignSnap.along(p, a, b)
				var kind := session.door_kind if session.tool == "door" else session.window_kind
				var w := float(building.catalog.kind(kind).get("w", 1.0))
				_ghost_lines(im, mat, [a + dir * (t - w / 2.0), a + dir * (t + w / 2.0)], y + 0.1)
		"box":
			var a: Vector3 = pv.a
			var b: Vector3 = pv.b
			_ghost_lines(im, _ghost_mat(Color(0.3, 0.7, 1.0)), [a, Vector3(b.x, 0, a.z), b, Vector3(a.x, 0, b.z), a], y)
		"shape":
			var pts: Array = []
			for v: Vector2 in pv.outline:
				pts.append(Vector3(v.x, 0, v.y))
			pts.append(pts[0])
			_ghost_lines(im, mat, pts, y)
			var outline: Array = []
			var c := Vector3.ZERO
			for v: Vector2 in pv.outline:
				outline.append([v.x, v.y])
				c += Vector3(v.x, 0, v.y)
			var bb := AABB(pts[0], Vector3.ZERO)
			for q: Vector3 in pts:
				bb = bb.expand(q)
			_show_dims(c / maxf(1.0, float(outline.size())), y, "%.2f × %.2f m\n%.1f m²" % [bb.size.x, bb.size.z,
					BuildingModel.outline_area(outline)])
		"move":
			var by: Vector3 = pv.by
			for id: String in pv.ids:
				var box: AABB = building.model.aabb_of(id) if building.model.parts.has(id) else _room_box(id)
				box.position += by
				var lo := box.position
				var hi := box.end
				_ghost_lines(im, mat, [lo, Vector3(hi.x, 0, lo.z), Vector3(hi.x, 0, hi.z), Vector3(lo.x, 0, hi.z), lo], y)


func _show_dims(at: Vector3, y: float, text: String) -> void:
	ghost_dims.text = text
	ghost_dims.position = Vector3(at.x, y + 0.3, at.z)
	ghost_dims.visible = true


## Handles on the selected room: squares on its corners, small crosses on its edges' middles.
func _draw_handles(im: ImmediateMesh, y: float) -> void:
	if session.tool != "select" or not session.shape.is_empty():
		return
	var h := session.shape_handles()
	if h.is_empty():
		return
	var mat := _ghost_mat(Color(1.0, 0.75, 0.1))
	var r := session.handle_reach * 0.7
	for c: Vector2 in h.corners:
		var p := Vector3(c.x, 0, c.y)
		_ghost_lines(im, mat, [p + Vector3(-r, 0, -r), p + Vector3(r, 0, -r), p + Vector3(r, 0, r), p + Vector3(-r, 0, r), p + Vector3(-r, 0, -r)], y)
	for m: Vector2 in h.mids:
		var p := Vector3(m.x, 0, m.y)
		_ghost_lines(im, mat, [p + Vector3(-r, 0, 0), p + Vector3(r, 0, 0)], y)
		_ghost_lines(im, mat, [p + Vector3(0, 0, -r), p + Vector3(0, 0, r)], y)


func _room_box(id: String) -> AABB:
	var e: Dictionary = building.model.rooms.get(id, {})
	if e.is_empty():
		return AABB()
	var box := AABB(Vector3(e.outline[0][0], 0, e.outline[0][1]), Vector3.ZERO)
	for p: Array in e.outline:
		box = box.expand(Vector3(p[0], 0, p[1]))
	return box


func _ghost_lines(im: ImmediateMesh, mat: Material, pts: Array, y: float) -> void:
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	for p: Vector3 in pts:
		im.surface_add_vertex(Vector3(p.x, y, p.z))
	im.surface_end()


func _ghost_mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _ghost_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = true
		_ghost_mats[key] = m
	return _ghost_mats[key]


# --- Input ------------------------------------------------------------------------------

## Puts the designer away (the hall shows) or brings it back. Put away, it takes no input and
## its plan cut comes off, so the hall's screens and table show the whole building.
func set_active(on: bool) -> void:
	active = on
	hud.visible = on and not lent_view
	if not on:
		_left_down = false
		_middle_from = null
		if wheel.get("is_open"):
			wheel.call("close")
		session.hover(null)
		session.cancel()
	var cam := camera as DesignCamera
	view.call("set_cut", PLAN_CUT if on and cam.plan else INF)


func _unhandled_input(event: InputEvent) -> void:
	if not active or lent_view:
		return
	var cam := camera as DesignCamera
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var p: Variant = _floor_point()
			if mb.pressed and p != null and stamping():
				stamp_at(session.snap(p))
				get_viewport().set_input_as_handled()
				return
			if mb.pressed and p != null:
				_left_down = true
				session.press(p, mb.shift_pressed)
			elif not mb.pressed and _left_down:
				_left_down = false
				session.release(p if p != null else session.cursor if session.cursor != null else Vector3.ZERO)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			# A tap pings the spot for the team, a hold opens the mark-up wheel, a drag pans
			# (the camera handles it).
			if mb.pressed:
				_middle_from = mb.position
				_middle_t = _now()
				_middle_moved = false
			else:
				if wheel.get("is_open"):
					close_wheel()
					get_viewport().set_input_as_handled()
					_middle_from = null
					return
				if _middle_from != null and not _middle_moved:
					ping_here()
				_middle_from = null
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			var busy := session.anchor != null or not session.drag.is_empty() or not session.shape.is_empty() or stamping()
			if mb.pressed:
				_right_from = null if busy or session.tool != "select" else mb.position
				if busy or session.tool != "select":
					# A right-click drops what's half done and goes back to Select.
					session.cancel()
					end_stamp()
					session.set_tool("select")
					get_viewport().set_input_as_handled()
					return
			elif _right_from != null and (mb.position - (_right_from as Vector2)).length() < TAP_SLOP:
				# A right click (not an orbit) on something: its menu.
				_right_from = null
				var at: Variant = _floor_point()
				if at != null and context.open_at(at as Vector3, mb.position):
					get_viewport().set_input_as_handled()
					return
			if cam.plan:
				get_viewport().set_input_as_handled()
				return
	if event is InputEventMouseMotion and _r_held:
		# Holding R: the mouse turns the selection, 1° per 4 px, in 5° steps (Alt: free).
		var mr := event as InputEventMouseMotion
		_r_px += mr.relative.x
		if session.turn.is_empty() and absf(_r_px) >= TURN_PX * 2.0:
			session.begin_turn()
		if not session.turn.is_empty():
			var deg := _r_px / TURN_PX
			session.turn_to(deg if mr.alt_pressed else snappedf(deg, 5.0))
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).shift_pressed and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] \
			and (stamping() or session.tool == "fixture" or not session.presence.my_selection().is_empty()):
		# Shift+wheel turns 15° a notch (Alt: 1°).
		var mw := event as InputEventMouseButton
		var step := (1.0 if mw.alt_pressed else 15.0) * (1.0 if mw.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
		if stamping():
			_stamp.rot = fposmod(float(_stamp.rot) + step, 360.0)
		elif session.tool == "fixture":
			session.fixture_rot = fposmod(session.fixture_rot + step, 360.0)
			session.preview_changed.emit()
		else:
			session.rotate_selection(step)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if session.pan_drag and _left_down:
			cam.pan_pixels(mm.relative)
			if mm.relative.length() > 0.5:
				session.pan_moved = true
			get_viewport().set_input_as_handled()
			return
		if wheel.get("is_open"):
			wheel.call("aim", mm.position - (wheel.get("centre") as Vector2))
			get_viewport().set_input_as_handled()
			return
		if _middle_from != null and (mm.position - (_middle_from as Vector2)).length() >= TAP_SLOP:
			_middle_moved = true
	if cam.handle(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and not event.pressed and (event as InputEventKey).keycode == KEY_R and _r_held:
		_r_held = false
		if session.turn.is_empty():
			session.rotate()
		session.end_turn()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if _key(event as InputEventKey):
			get_viewport().set_input_as_handled()


func _key(k: InputEventKey) -> bool:
	var ctrl := k.ctrl_pressed or k.meta_pressed
	match k.keycode:
		KEY_Z when ctrl:
			if k.shift_pressed:
				session.redo()
			else:
				session.undo()
			return true
		KEY_Y when ctrl:
			session.redo()
			return true
		KEY_S when ctrl:
			hud.call("open_save")
			return true
		KEY_O when ctrl:
			hud.call("open_load")
			return true
		KEY_C when ctrl:
			var clip := session.copy_selection()
			if not clip.is_empty() and design:
				design.clipboard = clip
			return true
		KEY_V when ctrl:
			paste()
			return true
		KEY_TAB:
			toggle_plan()
			return true
		KEY_PAGEUP:
			session.set_level(session.level + 1)
			return true
		KEY_PAGEDOWN:
			session.set_level(session.level - 1)
			return true
		KEY_DELETE, KEY_BACKSPACE:
			session.delete_selection()
			return true
		KEY_R when stamping():
			_stamp.rot = fmod(float(_stamp.rot) + 90.0, 360.0)
			return true
		KEY_R when session.tool == "fixture" or session.presence.my_selection().is_empty():
			session.rotate()
			return true
		KEY_R:
			# A tap turns 90° (on release); held, moving the mouse turns it freely.
			_r_held = true
			_r_px = 0.0
			return true
		KEY_M when k.shift_pressed:
			# Shift+M: a mirrored copy beside the selection (Ctrl too: below it).
			session.mirror_selection(1 if ctrl else 0, true)
			return true
		KEY_T:
			session.retag_selection()
			return true
		KEY_V:
			hud.call("set_realistic", not ArtStyle.realistic())
			return true
		KEY_ESCAPE when stamping():
			end_stamp()
			return true
		KEY_ESCAPE:
			if session.anchor != null or not session.drag.is_empty():
				session.cancel()
			elif not session.presence.my_selection().is_empty():
				session.presence.select(PackedStringArray())
			elif session.tool != "select":
				session.set_tool("select")
			elif embedded:
				leave_requested.emit()
			else:
				Menu.open_pause()
			return true
	if ctrl:
		return false
	for t: Dictionary in DesignSession.TOOLS:
		if int(t.key) != KEY_NONE and k.keycode == int(t.key):
			session.set_tool(str(t.id))
			return true
	return false


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Opens the mark-up wheel at a screen point; what it picks acts on the spot under it.
func open_wheel(at: Vector2) -> void:
	_wheel_spot = _floor_point_at(at)
	(camera as DesignCamera).stop_drag()
	wheel.call("open", at)


## Closes the wheel and does what it points at: a note, a ping or a measure from that spot,
## or shows and hides the notes.
func close_wheel() -> void:
	var pick: String = wheel.call("close")
	var spot: Variant = _wheel_spot
	_wheel_spot = null
	if pick == "notes_layer":
		hud.call("toggle_layer", "notes")
		return
	if pick == "" or spot == null:
		return
	var at := session.snap(spot)
	match pick:
		"note":
			session.note_requested.emit(at, session.pick(at))
		"ping":
			ping_here(spot)
		"measure":
			session.set_tool("measure")
			session.press(at)


var _wheel_spot: Variant = null


func _floor_point_at(screen: Vector2) -> Variant:
	var hit: Variant = (camera as DesignCamera).ground_point(screen, session.floor_y())
	if hit == null:
		return null
	var p: Vector3 = hit
	if absf(p.x) > PLOT_HALF or absf(p.z) > PLOT_HALF:
		return null
	return p


## Pings the spot under the pointer (or `where`), labelled with what is there.
func ping_here(where: Variant = null) -> void:
	var p: Variant = where if where != null else _floor_point()
	if p == null:
		return
	# A middle-click on a ping clears it (for everyone); anywhere else pings.
	var reach := maxf(1.0, (camera as DesignCamera).metres_per_pixel() * 16.0)
	var near := int(marks.call("ping_near", p as Vector3, reach))
	if near >= 0:
		marks.call("unping", near)
		return
	var at := session.snap(p)
	var id := session.pick(at)
	net.ping(at, id, Vector3.UP, session.label_of(id))


func set_overlay(id: String) -> void:
	overlay = id
	_tint_dirty = true
	hud.call("show_overlay_panel", id)


func toggle_plan() -> void:
	var cam := camera as DesignCamera
	cam.set_plan(not cam.plan)
	# Shadows only muddle a plan.
	_sun.shadow_enabled = not cam.plan
	# Graphics re-tunes lights when its settings change; this keeps the plan shadow-free.
	if cam.plan:
		_sun.set_meta("gfx_no_shadow", true)
	else:
		_sun.remove_meta("gfx_no_shadow")
	view.call("set_cut", PLAN_CUT if cam.plan else INF)
	hud.call("refresh_bar")
