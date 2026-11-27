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

const PLOT_HALF := 40.0
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
var _grid_mesh: MeshInstance3D
var _ghost: MeshInstance3D
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
## Opened from the hall's holotable (DesignHall): drawn into the hall's designer screen, and Esc
## goes back to the hall instead of the pause menu.
var embedded := false
## Taking the mouse and keys (false while the hall is shown and the designer is put away).
var active := true
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
	hud = DesignHud.new()
	hud.room = self
	var layer := CanvasLayer.new()
	layer.name = "Hud"
	add_child(layer)
	layer.add_child(hud)
	wheel = DesignWheel.new()
	wheel.name = "Wheel"
	layer.add_child(wheel)
	session.preview_changed.connect(_draw_ghost)
	session.level_changed.connect(_on_level)
	session.note_requested.connect(func(at: Vector3, target: String) -> void: hud.call("ask_note", at, target))
	session.presence.selection_changed.connect(func(_p: int, _ids: PackedStringArray) -> void: _tint_dirty = true)
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


func _exit_tree() -> void:
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
	plane.size = Vector2(PLOT_HALF * 2.0, PLOT_HALF * 2.0)
	ground.mesh = plane
	ground.material_override = ArtStyle.ground()
	Graphics.changed.connect(func() -> void: ground.material_override = ArtStyle.ground())
	ground.position.y = -0.01
	add_child(ground)
	_grid_mesh = MeshInstance3D.new()
	_grid_mesh.name = "Grid"
	_grid_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_grid_mesh)
	camera = DesignCamera.new()
	camera.name = "Camera"
	camera.limit = PLOT_HALF
	add_child(camera)
	camera.make_current()


## The working level's grid: 1 m lines, every 5 m darker, and the snap grid near the focus.
func _draw_grid() -> void:
	var lines := ImmediateMesh.new()
	var y := session.floor_y() + 0.015
	var half := PLOT_HALF
	for pass_n in 3:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = [Color(0, 0, 0, 0.07), Color(0, 0, 0, 0.16), Color(0, 0, 0, 0.38)][pass_n]
		lines.surface_begin(Mesh.PRIMITIVE_LINES, mat)
		if pass_n == 0:
			# Fine snap grid, 12 m around the middle of the view.
			if session.grid < 1.0:
				var f: Vector3 = (camera as DesignCamera).focus
				var cx := snappedf(f.x, 1.0)
				var cz := snappedf(f.z, 1.0)
				var n := int(12.0 / session.grid)
				for i in range(-n, n + 1):
					var o := i * session.grid
					if is_zero_approx(fmod(absf(o), 1.0)):
						continue
					lines.surface_add_vertex(Vector3(cx + o, y, cz - 12.0))
					lines.surface_add_vertex(Vector3(cx + o, y, cz + 12.0))
					lines.surface_add_vertex(Vector3(cx - 12.0, y, cz + o))
					lines.surface_add_vertex(Vector3(cx + 12.0, y, cz + o))
			else:
				lines.surface_add_vertex(Vector3.ZERO)
				lines.surface_add_vertex(Vector3.ZERO)
		else:
			for i in range(-int(half), int(half) + 1):
				if (i % 5 == 0) != (pass_n == 2):
					continue
				lines.surface_add_vertex(Vector3(i, y, -half))
				lines.surface_add_vertex(Vector3(i, y, half))
				lines.surface_add_vertex(Vector3(-half, y, i))
				lines.surface_add_vertex(Vector3(half, y, i))
		lines.surface_end()
	_grid_mesh.mesh = lines


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
	if not active:
		pass
	elif _pointer_over_hud():
		session.hover(null)
	else:
		session.hover(_floor_point())
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
	match str(pv.get("kind", "")):
		"line":
			_ghost_lines(im, mat, [pv.a, pv.b], y)
		"rect":
			var a: Vector3 = pv.a
			var b: Vector3 = pv.b
			_ghost_lines(im, mat, [a, Vector3(b.x, 0, a.z), b, Vector3(a.x, 0, b.z), a], y)
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
		"move":
			var by: Vector3 = pv.by
			for id: String in pv.ids:
				var box: AABB = building.model.aabb_of(id) if building.model.parts.has(id) else _room_box(id)
				box.position += by
				var lo := box.position
				var hi := box.end
				_ghost_lines(im, mat, [lo, Vector3(hi.x, 0, lo.z), Vector3(hi.x, 0, hi.z), Vector3(lo.x, 0, hi.z), lo], y)


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
	hud.visible = on
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
	if not active:
		return
	var cam := camera as DesignCamera
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var p: Variant = _floor_point()
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
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and (cam.plan or session.anchor != null):
			session.cancel()
			if cam.plan:
				get_viewport().set_input_as_handled()
				return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if wheel.get("is_open"):
			wheel.call("aim", mm.position - (wheel.get("centre") as Vector2))
			get_viewport().set_input_as_handled()
			return
		if _middle_from != null and (mm.position - (_middle_from as Vector2)).length() >= TAP_SLOP:
			_middle_moved = true
	if cam.handle(event):
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
		KEY_R:
			session.rotate()
			return true
		KEY_T:
			session.retag_selection()
			return true
		KEY_V:
			hud.call("set_realistic", not ArtStyle.realistic())
			return true
		KEY_ESCAPE:
			if session.anchor != null or not session.drag.is_empty():
				session.cancel()
			elif not session.presence.my_selection().is_empty():
				session.presence.select(PackedStringArray())
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
	view.call("set_cut", PLAN_CUT if cam.plan else INF)
	hud.call("refresh_bar")
