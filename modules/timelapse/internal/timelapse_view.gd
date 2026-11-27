extends Node3D
## The timelapse: the scheduled building rises part by part on the shared clock, in a clean
## architectural-model look, inside a busy work site (timelapse_site.gd: the library tower
## crane, crew, plant, deliveries). The sun turns at slow speeds, and the HUD shows the date, build day, stages under way and money spent, with play,
## speed and a scrub bar any of the crew can use (the host applies them for everyone).
##
## Router args {"demo": true} schedules the built-in demo house when nothing is running.
## Controls: right drag orbits, middle drag pans, wheel zooms, Space plays or pauses,
## G shows the ghost of the finished building, Esc goes back to the design office.

const DemoHouse := preload("res://modules/timelapse/internal/demo_house.gd")
const SiteScript := preload("res://modules/timelapse/internal/timelapse_site.gd")

const COLOURS := {
	"foundation": Color(0.62, 0.62, 0.6), "frame": Color(0.33, 0.36, 0.4),
	"floor": Color(0.84, 0.84, 0.82), "envelope": Color(0.95, 0.94, 0.9),
	"roof": Color(0.66, 0.34, 0.27), "services": Color(0.86, 0.7, 0.3),
	"fitout": Color(0.56, 0.72, 0.58), "site": Color(0.36, 0.28, 0.2),
	"landscape": Color(0.42, 0.62, 0.32),
}
const KIND_COLOURS := {
	"window": Color(0.55, 0.76, 0.92, 0.75), "glazing": Color(0.55, 0.76, 0.92, 0.75),
	"door": Color(0.5, 0.35, 0.24),
}
const WORKING := Color(1.0, 0.55, 0.15)
const ORBIT_SPEED := 0.006
const PAN_SPEED := 0.0025
const ZOOM_STEP := 1.12

var bus: TimelapseBus
var camera: Camera3D
var _pieces: Dictionary = {}  # task id -> {pivot, mesh, axis, task}
var _ghost_root: Node3D
var _build_root: Node3D
var _sun: DirectionalLight3D
var _materials: Dictionary = {}
var _working_mat: StandardMaterial3D
var _focus := Vector3.ZERO
var _yaw := deg_to_rad(40.0)
var _pitch := deg_to_rad(-28.0)
var _dist := 34.0
var _orbiting := false
var _panning := false
var _scrubbing := false
# HUD
var _title: Label
var _date: Label
var _stage: Label
var _money: Label
var _play: Button
var _speeds: Dictionary = {}  # speed -> Button
var _scrub: HSlider
var _empty: Label
var _hand_over: Button
## The help line along the bottom (ui's HelpBar, the same on every screen).
var help: HelpBar
var _ground: MeshInstance3D
var _settlement: PanelContainer
## The work site around the build: compound, scaffold, crew, plant and deliveries.
var site: Node3D
## The real-world site round the build (terrain, roads, neighbours, trees, the plot) when the
## sites module has one loaded; null on the plain ground.
var context: Node3D


func _ready() -> void:
	bus = Modules.bus("timelapse") as TimelapseBus
	_build_world()
	_build_hud()
	bus.started.connect(func(_t: String) -> void: _rebuild())
	bus.clock_changed.connect(_sync_buttons)
	Graphics.changed.connect(func() -> void:
		_ground.material_override = ArtStyle.ground()
		_rebuild())
	if not bus.is_active() and bool(Router.args.get("demo", false)):
		bus.start_timelapse(DemoHouse.parts(), "Demo house", false)
	_rebuild()


# --- Scene -----------------------------------------------------------------------------

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.4, 0.58, 0.86)
	sky_mat.sky_horizon_color = Color(0.8, 0.85, 0.9)
	sky_mat.ground_horizon_color = Color(0.62, 0.64, 0.6)
	sky_mat.ground_bottom_color = Color(0.45, 0.47, 0.42)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.light_energy = 0.85
	add_child(_sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1200, 1200)
	ground.mesh = plane
	_ground = ground
	ground.material_override = ArtStyle.ground()
	add_child(ground)

	site = SiteScript.new()
	site.name = "WorkSite"
	add_child(site)
	var sites := Modules.bus("sites")
	if sites != null and sites.has_signal("site_changed"):
		sites.connect("site_changed", func(_pack: Variant) -> void: _show_context())
	_show_context()
	_ghost_root = Node3D.new()
	_ghost_root.name = "Ghost"
	_ghost_root.visible = false
	add_child(_ghost_root)
	_build_root = Node3D.new()
	_build_root.name = "Building"
	add_child(_build_root)
	_working_mat = StandardMaterial3D.new()
	_working_mat.albedo_color = WORKING
	_working_mat.emission_enabled = true
	_working_mat.emission = WORKING
	_working_mat.emission_energy_multiplier = 0.4

	camera = Camera3D.new()
	camera.far = 800.0
	add_child(camera)
	camera.make_current()


## Puts the loaded real-world site (sites module) round the build, its plot on the design
## origin as in the design room, in place of the plain ground.
func _show_context() -> void:
	if context:
		context.queue_free()
		context = null
	var sites := Modules.bus("sites")
	if sites != null and sites.has_method("current") and sites.call("current") != null \
			and sites.has_method("make_plot_view"):
		var v: Variant = sites.call("make_plot_view")
		if v is Node3D:
			context = v
			context.name = "RealSite"
			add_child(context)
	_ground.visible = context == null


func _rebuild() -> void:
	for n in _build_root.get_children() + _ghost_root.get_children():
		n.queue_free()
	_pieces.clear()
	_empty.visible = not bus.is_active()
	if not bus.is_active():
		site.visible = false
		return
	_title.text = bus.title.to_upper()
	var bounds := AABB()
	var first := true
	for t: Dictionary in bus.tasks():
		var box: AABB = t.aabb
		bounds = box if first else bounds.merge(box)
		first = false
		_add_piece(t)
	_focus = bounds.get_center()
	_dist = clampf(maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)) * 2.4, 12.0, 300.0)
	site.visible = true
	site.setup(bus.schedule, bounds)
	_scrub.max_value = bus.total_days()
	_scrub.step = 0.01
	_sync_buttons()


## Kinds whose family name differs (for the realistic look's materials).
const KIND_FAMILY := {"pad": "foundation", "footing": "foundation", "window": "opening",
		"door": "opening", "fitout": "fixture", "stairs": "room", "lift": "room", "frame": "column"}


func _material(t: Dictionary, ghost: bool) -> BaseMaterial3D:
	# Building parts take the game's look (white model or realistic); site work keeps its colours.
	if not ghost and t.stage != "site" and t.stage != "landscape":
		var family := str(t.get("family", t.kind))
		return ArtStyle.material(str(t.get("material", "")), str(KIND_FAMILY.get(family, KIND_FAMILY.get(t.kind, family))))
	var colour: Color = KIND_COLOURS.get(t.kind, COLOURS.get(t.stage, Color.WHITE))
	var key := "%s|%s" % [colour.to_html(), ghost]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	if ghost:
		m.albedo_color.a = 0.08
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if m.albedo_color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.85
	_materials[key] = m
	return m


## Whether a task fades in (beams, columns, walls, floors, roofs and the rest of the
## building) rather than spreading across the plot (site clearance and landscaping).
static func fades(t: Dictionary) -> bool:
	return t.stage != "site" and t.stage != "landscape"


func _add_piece(t: Dictionary) -> void:
	var look: Dictionary = t.get("model", {})
	if not look.is_empty() and AssetLibrary.has(AssetLibrary.id_for_kind(str(look.kind))):
		_add_model(t, look)
		return
	var shape: Dictionary = t.get("shape", {})
	if fades(t) and not shape.is_empty():
		_add_shaped(t, shape)
		return
	var box: AABB = t.aabb
	var size := box.size
	if t.stage == "site" or t.stage == "landscape":
		# Clearance and excavation darken the plot; landscaping greens a border around it.
		var grow := 6.0 if t.stage == "landscape" else 2.0
		size = Vector3(box.size.x + grow * 2.0, 0.02, box.size.z + grow * 2.0)
		box = AABB(Vector3(box.position.x - grow, 0.005 if t.kind == "clear" else 0.01, box.position.z - grow), size)
		if t.kind == "landscape":
			box.position.y = 0.0
	size = Vector3(maxf(size.x, 0.02), maxf(size.y, 0.02), maxf(size.z, 0.02))
	# Grow along the part's long axis from one end; walls and columns rise.
	var axis := 1
	if t.stage != "envelope" and t.stage != "site" and t.stage != "landscape":
		if size.x >= size.y and size.x >= size.z:
			axis = 0
		elif size.z >= size.y and size.z >= size.x:
			axis = 2
	if t.stage == "site" or t.stage == "landscape":
		axis = 0
	var pivot := Node3D.new()
	var anchor := box.get_center()
	anchor[axis] = box.position[axis]
	pivot.position = anchor
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	var offset := Vector3.ZERO
	offset[axis] = size[axis] / 2.0
	mesh.position = offset
	mesh.material_override = _material(t, false)
	pivot.add_child(mesh)
	pivot.visible = false
	_build_root.add_child(pivot)
	_pieces[t.id] = {"pivot": pivot, "mesh": mesh, "axis": axis, "task": t}
	if t.stage != "site" and t.stage != "landscape":
		var ghost := MeshInstance3D.new()
		ghost.mesh = bm
		ghost.position = box.get_center()
		ghost.material_override = _material(t, true)
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ghost_root.add_child(ghost)


## A library object (an airliner, a car, a desk) as its own model, fading in like the rest.
func _add_model(t: Dictionary, look: Dictionary) -> void:
	for ghost: bool in [false, true]:
		var node := AssetLibrary.make_kind(str(look.kind), {"size": look.size, "family": "fixture"})
		node.name = "Model_" + str(t.id)
		node.position = look.at
		node.rotation.y = deg_to_rad(float(look.rot))
		var meshes: Array[MeshInstance3D] = []
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			meshes.append(mi as MeshInstance3D)
		if ghost:
			for mi in meshes:
				mi.material_override = _material(t, true)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_ghost_root.add_child(node)
		else:
			node.visible = false
			_build_root.add_child(node)
			_pieces[t.id] = {"pivot": node, "mesh": meshes[0] if not meshes.is_empty() else null,
					"meshes": meshes, "axis": 1, "task": t}


## A part at its real angle and outline: angled walls, beams and openings as turned boxes,
## slabs, roofs and rooms as their own polygons.
func _add_shaped(t: Dictionary, shape: Dictionary) -> void:
	var pivot := Node3D.new()
	var mesh := MeshInstance3D.new()
	var m: Mesh
	if shape.has("obb"):
		var bm := BoxMesh.new()
		m = bm
		mesh.transform = shape.obb
	elif shape.has("faces"):
		m = faces_mesh(shape.faces)
	else:
		m = slab_mesh(shape.outline, float(shape.top), float(shape.thick))
	mesh.mesh = m
	mesh.material_override = _material(t, false)
	pivot.add_child(mesh)
	pivot.visible = false
	_build_root.add_child(pivot)
	_pieces[t.id] = {"pivot": pivot, "mesh": mesh, "axis": 1, "task": t}
	var ghost := MeshInstance3D.new()
	ghost.mesh = m
	ghost.transform = mesh.transform
	ghost.material_override = _material(t, true)
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost_root.add_child(ghost)


## A polygon outline (x, z) extruded down from `top` by `thick`: top, bottom and sides.
static func slab_mesh(outline: PackedVector2Array, top: float, thick: float) -> ArrayMesh:
	var poly := outline
	if Geometry2D.is_polygon_clockwise(poly):
		poly = poly.duplicate()
		poly.reverse()
	var tris := Geometry2D.triangulate_polygon(poly)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bottom := top - maxf(thick, 0.02)
	if tris.is_empty():
		# Self-crossing outline: fall back to a fan from the first corner.
		for i in range(1, poly.size() - 1):
			tris.append_array([0, i, i + 1])
	var area := 0.0  # twice the signed area in (x, z): > 0 when the interior is left of each edge
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		area += p.x * q.y - q.x * p.y
	for i in range(0, tris.size(), 3):
		var a := poly[tris[i]]
		var b := poly[tris[i + 1]]
		var c := poly[tris[i + 2]]
		_face(st, Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(c.x, top, c.y), Vector3.UP)
		_face(st, Vector3(a.x, bottom, a.y), Vector3(b.x, bottom, b.y), Vector3(c.x, bottom, c.y), Vector3.DOWN)
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var d := q - p
		var out := Vector3(d.y, 0, -d.x) * signf(area)
		var p0 := Vector3(p.x, bottom, p.y)
		var q0 := Vector3(q.x, bottom, q.y)
		var p1 := Vector3(p.x, top, p.y)
		var q1 := Vector3(q.x, top, q.y)
		_face(st, p0, q0, q1, out)
		_face(st, p0, q1, p1, out)
	st.generate_normals()
	return st.commit()


## A mesh of flat faces ([[corners (3 or 4)], outward normal], as RoofShape gives them).
static func faces_mesh(faces: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f: Array in faces:
		var c: Array = f[0]
		var n: Vector3 = f[1]
		for i in range(1, c.size() - 1):
			_face(st, c[0], c[i], c[i + 1], n)
	st.generate_normals()
	return st.commit()


## One triangle wound to face `out` (Godot's front faces wind clockwise seen from outside).
static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3) -> void:
	if (c - a).cross(b - a).dot(out) < 0.0:
		var swap := b
		b = c
		c = swap
	for v: Vector3 in [a, b, c]:
		st.add_vertex(v)


# --- Every frame -----------------------------------------------------------------------

func _process(delta: float) -> void:
	_place_camera()
	if not bus.is_active():
		return
	var day := bus.day()
	site.tick(day, delta * SiteScript.pace(bus.speed(), bus.is_playing()))
	for id: String in _pieces:
		var piece: Dictionary = _pieces[id]
		var t: Dictionary = piece.task
		var p := TimelapseSchedule.progress(t, day)
		var pivot: Node3D = piece.pivot
		pivot.visible = p > 0.0
		if p <= 0.0:
			continue
		var mesh := piece.mesh as MeshInstance3D
		if fades(t):
			# Building parts fade in at full size over their build time.
			var fade := 1.0 - smoothstep(0.0, 1.0, p)
			if piece.has("meshes"):
				for mi: MeshInstance3D in piece.meshes:
					mi.transparency = fade
			elif mesh:
				mesh.transparency = fade
			continue
		# Site work spreads across the plot.
		var s := Vector3.ONE
		s[int(piece.axis)] = maxf(p, 0.001)
		pivot.scale = s
		var busy: bool = p < 1.0 and t.stage != "site" and t.stage != "landscape"
		mesh.material_override = _working_mat if busy else _material(t, false)
	_turn_sun(day)
	_update_hud(day)


## The sun turns with the hour at slow speeds; faster than a day a second it stays at noon.
func _turn_sun(day: float) -> void:
	var hour := 12.0
	if bus.speed() <= 1.0 or not bus.is_playing():
		hour = 6.0 + fposmod(day, 1.0) * 12.0  # working daylight, 06:00 to 18:00
	var elevation := sin((hour - 6.0) / 12.0 * PI) * 60.0 + 8.0
	_sun.rotation = Vector3(deg_to_rad(-elevation), deg_to_rad(-30.0 - (hour - 12.0) * 12.0), 0.0)


func _place_camera() -> void:
	var basis := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	camera.global_transform = Transform3D(basis, _focus + basis.z * _dist)


## Back to where the building was designed (the game's start scene: the design office).
func go_back() -> void:
	var start := Menu.start()
	if not start.is_empty():
		Router.goto(str(start.scene), start.get("args", {}))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_action_pressed(Keys.CANCEL) and not event.is_echo():
		# Esc goes back to the design office rather than opening the pause menu.
		get_viewport().set_input_as_handled()
		go_back()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_dist = clampf(_dist / ZOOM_STEP, 4.0, 400.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_dist = clampf(_dist * ZOOM_STEP, 4.0, 400.0)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			_yaw -= mm.relative.x * ORBIT_SPEED
			_pitch = clampf(_pitch - mm.relative.y * ORBIT_SPEED, deg_to_rad(-85.0), deg_to_rad(-5.0))
		elif _panning:
			var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
			var back := Vector3(sin(_yaw), 0.0, cos(_yaw))
			_focus -= (right * mm.relative.x + back * mm.relative.y) * PAN_SPEED * _dist
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_SPACE:
				_toggle_play()
			KEY_G:
				_ghost_root.visible = not _ghost_root.visible
				get_viewport().set_input_as_handled()


# --- HUD -------------------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.name = "TimelapseHud"
	panel.add_theme_stylebox_override("panel", BsxTheme.panel_style(16))
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -190
	panel.offset_left = 24
	panel.offset_right = -24
	panel.offset_bottom = -60  # the help bar goes below
	layer.add_child(panel)
	help = HelpBar.new()
	add_child(help)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	col.add_child(top)
	_title = BsxTheme.hud_label("", 22)
	top.add_child(_title)
	_date = BsxTheme.hud_label("", 18)
	_date.name = "Date"
	top.add_child(_date)
	_stage = BsxTheme.hud_label("", 18)
	_stage.name = "Stages"
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_stage)
	_money = BsxTheme.hud_label("", 18)
	_money.name = "Money"
	top.add_child(_money)
	_scrub = HSlider.new()
	_scrub.name = "Scrub"
	_scrub.custom_minimum_size.y = 24
	_scrub.drag_started.connect(func() -> void: _scrubbing = true)
	_scrub.drag_ended.connect(func(_changed: bool) -> void:
		_scrubbing = false
		bus.request_seek(_scrub.value))
	col.add_child(_scrub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	_play = BsxTheme.button("Pause", _toggle_play)
	_play.name = "Play"
	_play.custom_minimum_size.x = 110
	row.add_child(_play)
	row.add_child(BsxTheme.hud_label("  days per second", 16))
	for s in TimelapseBus.SPEEDS:
		var b := BsxTheme.button(("%.2f" % s).trim_suffix("0").trim_suffix("0").trim_suffix("."),
				func() -> void: bus.request_speed(s))
		b.name = "Speed_%s" % str(s).replace(".", "_")
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(64, 42)
		row.add_child(b)
		_speeds[s] = b
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var back := BsxTheme.button("Back to design (Esc)", go_back)
	back.name = "Back"
	back.tooltip_text = "Back to the design office to change the design"
	# With a contract taken (the contracts module, optional): hand the finished building over.
	_hand_over = BsxTheme.button("Hand over", func() -> void:
		var c := _contracts()
		if c:
			c.call("hand_over", ceili(bus.total_days())))
	_hand_over.name = "HandOver"
	_hand_over.custom_minimum_size = Vector2(130, 42)
	_hand_over.visible = false
	row.add_child(_hand_over)
	var contracts := _contracts()
	if contracts and contracts.has_signal("settled"):
		contracts.connect("settled", _show_settlement)
	back.name = "Back"
	back.custom_minimum_size = Vector2(130, 42)
	row.add_child(back)
	_settlement = PanelContainer.new()
	_settlement.name = "Settlement"
	_settlement.add_theme_stylebox_override("panel", BsxTheme.panel_style(20))
	_settlement.set_anchors_preset(Control.PRESET_CENTER)
	_settlement.visible = false
	layer.add_child(_settlement)
	_empty = BsxTheme.hud_label("Nothing is scheduled yet. Finish a design and start its timelapse.", 22)
	_empty.set_anchors_preset(Control.PRESET_CENTER)
	layer.add_child(_empty)


func _toggle_play() -> void:
	if bus.is_active():
		bus.request_play(not bus.is_playing())


func _sync_buttons() -> void:
	if _play == null:
		return
	for s: float in _speeds:
		(_speeds[s] as Button).set_pressed_no_signal(is_equal_approx(s, bus.speed()))


func _update_help(day: float) -> void:
	var how := [["Space", "play / pause"], ["G", "ghost"], ["right drag", "orbit"], ["middle drag", "pan"],
			["wheel", "zoom"], ["Esc", "back to design"]]
	var head := "TIMELAPSE: COMPLETE" if day >= bus.total_days() else "TIMELAPSE"
	help.set_help(head, HelpBar.keys_text(how))


func _update_hud(day: float) -> void:
	var sched := bus.schedule
	_play.text = "Pause" if bus.is_playing() else ("Replay" if day >= bus.total_days() else "Play")
	_date.text = "%s  ·  day %d of %d" % [TimelapseSchedule.date_on(sched, day), int(day) + 1,
			ceili(bus.total_days())]
	var stages := TimelapseSchedule.active_stages(sched, day)
	_stage.text = "Complete" if day >= bus.total_days() else ", ".join(stages).capitalize()
	_money.text = "£%s of £%s" % [_thousands(TimelapseSchedule.spent(sched, day)),
			_thousands(float(sched.get("cost", 0.0)))]
	if not _scrubbing:
		_scrub.set_value_no_signal(day)
	_update_help(day)
	var c := _contracts()
	_hand_over.visible = day >= bus.total_days() and c != null \
			and not (c.get("active") as Dictionary).is_empty()


## The contracts bus when that module is loaded, else null.
func _contracts() -> Node:
	var c := Modules.bus("contracts")
	return c if c and c.has_method("hand_over") else null


func _show_settlement(s: Dictionary) -> void:
	for child in _settlement.get_children():
		child.queue_free()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_settlement.add_child(col)
	col.add_child(BsxTheme.hud_label("%s: %s" % [str(s.get("title", "Contract")),
			"handed over" if bool(s.get("passed", false)) else "not accepted"], 24))
	for line: Variant in s.get("lines", []):
		col.add_child(BsxTheme.hud_label(str(line), 17))
	col.add_child(BsxTheme.button("Close", func() -> void: _settlement.visible = false))
	_settlement.visible = true
	_settlement.reset_size()
	_settlement.position = (get_viewport().get_visible_rect().size - _settlement.size) * 0.5


static func _thousands(v: float) -> String:
	var s := str(int(roundf(v)))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out
