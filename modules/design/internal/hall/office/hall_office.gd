extends Node3D
## The design hall as a proper office (flag design.office): the front wall is full-height
## glass looking out over a vast vista, with the late sun coming through it; a warm ring of
## light hangs over the holotable, LED strips run along the ceiling, and there are two
## lounges by the glass (a corner sofa round a rug, and a lounge chair by a lamp).
## The vista is the hall's sky: a picture any player can change at the Vista console by the
## window (F there, or drop a picture file onto the game), shared with the whole crew.
## The hall builds this from _build_shell(); it owns everything listed here and nothing else.

const VistaImage := preload("res://modules/design/internal/hall/office/vista_image.gd")
const T := preload("res://modules/ui/api/terminal_kit.gd")

const FLAG := "design.office"
const POINTER := "design.hall.vista"
## The window wall: the hall's front (-Z) wall, its whole width and height.
const WINDOW_Z := -9.0
## Mullions every this many metres across the glass.
const BAY := 3.0
## The sun: degrees round from straight out of the window (+ to the right) and above the
## horizon. The default vista draws its sun there.
const SUN_TURN_DEG := 22.0
const SUN_HIGH_DEG := 12.0
## Where the Vista console stands, and how near it F works, m.
const CONSOLE_AT := Vector3(0.0, 0.0, -7.4)
const CONSOLE_REACH := 2.2
## Furniture: [asset ids to try, best first], where, turn (radians, 0 faces the window).
const PIECES := [
	[["furniture.home.rug"], Vector3(-8.0, 0, -5.0), 0.0, Vector3(2.2, 1, 2.2)],
	[["furniture.statement.curved_sofa", "furniture.seat.corner_sofa"], Vector3(-6.4, 0, -4.0), 0.0, Vector3.ONE],
	[["furniture.statement.coffee_table", "furniture.table.coffee"], Vector3(-8.6, 0, -5.3), 0.0, Vector3.ONE],
	[["furniture.seat.armchair"], Vector3(-10.6, 0, -5.4), -PI / 2.0, Vector3.ONE],
	[["furniture.light.arc_floor_lamp", "furniture.home.floor_lamp"], Vector3(-10.8, 0, -3.5), 0.0, Vector3.ONE],
	[["office.planter.round"], Vector3(-11.3, 0, -8.3), 0.0, Vector3(1.3, 1.3, 1.3)],
	[["office.planter.round"], Vector3(-3.4, 0, -8.3), 0.0, Vector3.ONE],
	[["furniture.home.rug"], Vector3(7.6, 0, -5.8), 0.0, Vector3(1.6, 1, 1.6)],
	[["furniture.statement.lounge_chair", "furniture.seat.armchair"], Vector3(6.6, 0, -5.4), 0.35, Vector3.ONE],
	[["furniture.seat.sofa_2"], Vector3(8.9, 0, -4.4), -0.25, Vector3.ONE],
	[["furniture.table.coffee"], Vector3(7.9, 0, -6.4), 0.0, Vector3(0.8, 1, 0.8)],
	[["furniture.light.arc_floor_lamp", "furniture.home.floor_lamp"], Vector3(5.3, 0, -4.4), 0.0, Vector3.ONE],
	[["office.planter.round"], Vector3(11.3, 0, -8.3), 0.0, Vector3(1.3, 1.3, 1.3)],
	[["office.planter.round"], Vector3(3.4, 0, -8.3), 0.0, Vector3.ONE],
]
## Statement pieces that may be in the asset library later; their "glow" slot lights up.
const GLOW_SLOT := "glow"

var hall: Node3D
var vista: Node
var env: Environment
var sky_mat: PanoramaSkyMaterial
var sun: DirectionalLight3D
var probe: ReflectionProbe
var console_screen: MeshInstance3D
var console_label: Label3D
## The furniture placed: [{id, node}].
var placed: Array[Dictionary] = []
var panel: Control
var _status: Label
var _thumb: TextureRect
var _from: Label
var _dialog: FileDialog
var _probe_frames := 0


## Builds the office into the hall, round the shell the hall has made (floor, ceiling, side
## and back walls), and turns `environment` into the vista's sky.
func setup(owner_hall: Node3D, environment: Environment) -> void:
	name = "Office"
	hall = owner_hall
	env = environment
	vista = _find_vista()
	_build_sky()
	_build_window()
	_build_lights()
	_build_furniture()
	_build_console()
	if vista:
		vista.connect("changed", _on_vista_changed)
		vista.connect("prepared", _on_prepared)


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		get_window().files_dropped.connect(_on_files_dropped)


func _exit_tree() -> void:
	HudSlots.release_pointer(POINTER)
	if get_window() and get_window().files_dropped.is_connected(_on_files_dropped):
		get_window().files_dropped.disconnect(_on_files_dropped)


## The design bus's vista keeper (null in odd test setups without the module running).
static func _find_vista() -> Node:
	var bus := Modules.bus("design")
	return bus.get_node_or_null("Vista") if bus else null


func vista_texture() -> Texture2D:
	return vista.call("texture") as Texture2D if vista else load("res://modules/design/internal/hall/office/default_vista.webp") as Texture2D


# --- Sky and sun ------------------------------------------------------------------------

func _build_sky() -> void:
	sky_mat = PanoramaSkyMaterial.new()
	sky_mat.panorama = vista_texture()
	sky_mat.filter = true
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.background_energy_multiplier = 1.0
	# Inside, light comes from the lamps and the sun through the glass, not the whole sky.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.6, 0.66)
	env.ambient_light_energy = 0.65
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.86, 0.7)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.basis = Basis.looking_at(-sun_direction(), Vector3.UP)
	add_child(sun)
	# The floor and the glass reflect the room and the view.
	probe = ReflectionProbe.new()
	probe.name = "Reflections"
	probe.size = Vector3(24.4, 6.4, 18.4)
	probe.position = Vector3(0, 3.0, 0)
	probe.origin_offset = Vector3(0, -1.2, 0)
	probe.box_projection = true
	probe.interior = false
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.intensity = 0.8
	add_child(probe)


## Toward the sun from the room (unit).
static func sun_direction() -> Vector3:
	var turn := deg_to_rad(SUN_TURN_DEG)
	var high := deg_to_rad(SUN_HIGH_DEG)
	return Vector3(sin(turn) * cos(high), sin(high), -cos(turn) * cos(high)).normalized()


func _on_vista_changed() -> void:
	sky_mat.panorama = vista_texture()
	if console_screen:
		(console_screen.material_override as StandardMaterial3D).albedo_texture = vista_texture()
		(console_screen.material_override as StandardMaterial3D).emission_texture = vista_texture()
	_refresh_panel()
	# Catch the new view in the reflections over the next few frames.
	_probe_frames = 3
	probe.update_mode = ReflectionProbe.UPDATE_ALWAYS


func _process(_delta: float) -> void:
	if _probe_frames > 0:
		_probe_frames -= 1
		if _probe_frames == 0:
			probe.update_mode = ReflectionProbe.UPDATE_ONCE
	if console_label:
		var near := near_console()
		console_label.modulate = Color(1, 0.75, 0.35) if near else Color(0.85, 0.9, 1.0, 0.7)


# --- The window wall --------------------------------------------------------------------

func _build_window() -> void:
	var size: Vector3 = hall.get("ROOM_SIZE")
	var half_w := size.x * 0.5
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.09, 0.095, 0.1)
	frame.metallic = 0.8
	frame.roughness = 0.35
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.82, 0.9, 0.95, 0.05)
	glass.metallic = 0.0
	glass.roughness = 0.03
	glass.metallic_specular = 0.9
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pane := MeshInstance3D.new()
	pane.name = "Glass"
	var quad := QuadMesh.new()
	quad.size = Vector2(size.x, size.y)
	pane.mesh = quad
	pane.material_override = glass
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pane.position = Vector3(0, size.y * 0.5, WINDOW_Z - 0.05)
	add_child(pane)
	# Mullions, a head and a sill, and a slim transom at door height.
	var x := -half_w
	while x <= half_w + 0.01:
		_box("Mullion", Vector3(0.09, size.y, 0.22), Vector3(x, size.y * 0.5, WINDOW_Z - 0.05), frame)
		x += BAY
	_box("Head", Vector3(size.x, 0.18, 0.3), Vector3(0, size.y - 0.09, WINDOW_Z - 0.05), frame)
	_box("Sill", Vector3(size.x, 0.06, 0.34), Vector3(0, 0.03, WINDOW_Z - 0.05), frame)
	_box("Transom", Vector3(size.x, 0.05, 0.16), Vector3(0, 2.5, WINDOW_Z - 0.05), frame)
	# A ledge outside, so the view starts beyond something solid.
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.55, 0.54, 0.52)
	stone.roughness = 0.8
	_box("Ledge", Vector3(size.x + 0.6, 0.25, 1.6), Vector3(0, -0.15, WINDOW_Z - 0.95), stone)
	# Nobody walks out through the glass.
	var body := StaticBody3D.new()
	body.name = "WindowWall"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, 0.3)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, size.y * 0.5, WINDOW_Z - 0.15)
	add_child(body)


func _box(id: String, sz: Vector3, at: Vector3, mat: Material, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = id
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


static func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


# --- Lights -----------------------------------------------------------------------------

func _build_lights() -> void:
	var size: Vector3 = hall.get("ROOM_SIZE")
	var warm := Color(1.0, 0.88, 0.74)
	var cable := StandardMaterial3D.new()
	cable.albedo_color = Color(0.05, 0.05, 0.05)
	# The halo over the holotable: a big glowing ring on three cables, and its light.
	var ring := MeshInstance3D.new()
	ring.name = "HaloRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 2.3
	torus.outer_radius = 2.42
	torus.rings = 96
	torus.ring_segments = 12
	ring.mesh = torus
	ring.material_override = _glow(warm, 4.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0, size.y - 1.25, 0)
	add_child(ring)
	for i in 3:
		var a := TAU * float(i) / 3.0
		var c := _box("HaloCable", Vector3(0.012, 1.2, 0.012), Vector3(cos(a) * 2.36, size.y - 0.62, sin(a) * 2.36), cable, false)
		c.name = "HaloCable%d" % i
	_lamp("HaloLight", Vector3(0, size.y - 1.4, 0), warm, 1.4, 9.0)
	# LED strips along the ceiling, each with a soft wash below it.
	var strip := _glow(Color(0.95, 0.97, 1.0), 3.0)
	for z: float in [-5.5, 5.5]:
		_box("CeilingStrip", Vector3(18.0, 0.04, 0.1), Vector3(0, size.y - 0.04, z), strip, false)
		for x: float in [-7.0, 0.0, 7.0]:
			_lamp("StripWash", Vector3(x, size.y - 0.5, z), Color(0.93, 0.95, 1.0), 0.55, 8.0)
	# A cove of warm light along the back wall, over its screens.
	_box("BackCove", Vector3(size.x - 1.0, 0.05, 0.08), Vector3(0, size.y - 0.3, size.z * 0.5 - 0.3), _glow(warm, 2.5), false)
	_lamp("BackWash", Vector3(0, size.y - 0.6, size.z * 0.5 - 1.5), warm, 0.6, 9.0)


func _lamp(id: String, at: Vector3, color: Color, energy: float, reach: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = id
	l.position = at
	l.light_color = color
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 1.4
	l.set_meta("gfx_no_shadow", true)
	add_child(l)
	return l


# --- Furniture --------------------------------------------------------------------------

func _build_furniture() -> void:
	for p: Array in PIECES:
		var id := ""
		for want: String in p[0]:
			if AssetLibrary.has(want):
				id = want
				break
		if id == "":
			continue
		var node := AssetLibrary.make(id)
		node.position = p[1]
		node.rotation.y = float(p[2])
		node.scale = p[3]
		_realistic(node)
		add_child(node)
		placed.append({"id": id, "node": node})
		if id.contains("lamp"):
			var top := AssetLibrary.bounds(id).end.y
			_lamp("LoungeLamp", (p[1] as Vector3) + Vector3(0, top - 0.25, 0), Color(1.0, 0.78, 0.52), 0.9, 4.5)
		if id.contains("rug"):
			continue
		# Something to bump into (rugs aside).
		var b := AssetLibrary.bounds(id)
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = b.size * (p[3] as Vector3)
		shape.shape = box
		shape.position = b.get_center() * (p[3] as Vector3)
		body.add_child(shape)
		node.add_child(body)
		body.scale = Vector3.ONE / (p[3] as Vector3)


## The office always looks real, whatever the drawing look: the furniture keeps its own
## materials, and a "glow" slot lights up.
func _realistic(root: Node) -> void:
	for c in root.get_children():
		_realistic(c)
	if root is MeshInstance3D and not root.has_meta("asset_box"):
		var mi := root as MeshInstance3D
		mi.material_override = null
		if str(mi.name).get_slice("__", 1).begins_with(GLOW_SLOT):
			mi.material_override = _glow(Color(1.0, 0.85, 0.65), 3.5)


# --- The Vista console ------------------------------------------------------------------

func _build_console() -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.07, 0.075, 0.085)
	dark.metallic = 0.6
	dark.roughness = 0.3
	_box("ConsoleStand", Vector3(0.12, 1.0, 0.12), CONSOLE_AT + Vector3(0, 0.5, 0), dark)
	_box("ConsoleFoot", Vector3(0.6, 0.03, 0.45), CONSOLE_AT + Vector3(0, 0.015, 0), dark)
	var head := _box("ConsoleHead", Vector3(0.84, 0.48, 0.05), CONSOLE_AT + Vector3(0, 1.18, 0), dark)
	head.rotation.x = deg_to_rad(-35.0)
	console_screen = MeshInstance3D.new()
	console_screen.name = "ConsoleScreen"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.78, 0.39)
	console_screen.mesh = quad
	var m := StandardMaterial3D.new()
	m.albedo_texture = vista_texture()
	m.emission_enabled = true
	m.emission_texture = vista_texture()
	m.emission_energy_multiplier = 0.8
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	console_screen.material_override = m
	console_screen.position = Vector3(0, 0, 0.03)
	head.add_child(console_screen)
	# The screen faces the room (+Z), tilted back.
	console_label = Label3D.new()
	console_label.name = "ConsoleLabel"
	console_label.text = "VISTA\n%s  change the view" % Keys.prompt(Keys.INTERACT)
	console_label.font_size = 40
	console_label.pixel_size = 0.0035
	console_label.outline_size = 8
	console_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	console_label.position = CONSOLE_AT + Vector3(0, 1.75, 0)
	add_child(console_label)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 1.4, 0.45)
	shape.shape = box
	body.add_child(shape)
	body.position = CONSOLE_AT + Vector3(0, 0.7, 0)
	add_child(body)


func near_console() -> bool:
	var walker: Node3D = hall.get("walker")
	if walker == null:
		return false
	var d := walker.global_position - (global_transform * CONSOLE_AT)
	return Vector2(d.x, d.z).length() <= CONSOLE_REACH


func _unhandled_input(event: InputEvent) -> void:
	if panel:
		return
	if str(hall.get("mode")) != "room" or HudSlots.pointer_claimed() or Keys.typing():
		return
	if event.is_action_pressed(Keys.INTERACT) and not event.is_echo() and near_console():
		open_panel()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if panel == null or not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	if (event as InputEventKey).physical_keycode == KEY_ESCAPE and (_dialog == null or not _dialog.visible):
		close_panel()
		get_viewport().set_input_as_handled()


## The Vista panel: what's showing, pick a picture, or go back to the default.
func open_panel() -> void:
	if panel:
		return
	var layer := CanvasLayer.new()
	layer.name = "VistaLayer"
	layer.layer = 6
	add_child(layer)
	var page := PanelContainer.new()
	page.name = "VistaPanel"
	page.theme = BsxTheme.get_theme()
	page.add_theme_stylebox_override("panel", T.box(Color(0.02, 0.05, 0.09, 0.96), T.EDGE, 1, 18.0))
	page.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	page.custom_minimum_size = Vector2(620, 0)
	page.grow_horizontal = Control.GROW_DIRECTION_BOTH
	page.grow_vertical = Control.GROW_DIRECTION_BOTH
	layer.add_child(page)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	page.add_child(col)
	col.add_child(T.label("THE VIEW", "display_bold", 20, T.ORANGE))
	_thumb = TextureRect.new()
	_thumb.custom_minimum_size = Vector2(580, 290)
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	col.add_child(_thumb)
	_from = T.label("", "body", 15, T.TEXT)
	col.add_child(_from)
	var tip := T.label("Any picture works. A 2:1 panorama wraps all the way round; any other photo is spread across the window. Everyone in the room sees it. You can also drop a picture file onto the game.", "body", 14, T.DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size.x = 580
	col.add_child(tip)
	_status = T.label("", "body", 14, T.ORANGE)
	col.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var pick := T.button("CHOOSE A PICTURE", true, 16)
	pick.name = "Choose"
	pick.pressed.connect(_choose)
	row.add_child(pick)
	var back := T.button("DEFAULT VIEW", false, 16)
	back.name = "Default"
	back.pressed.connect(func() -> void:
		if vista:
			vista.call("reset"))
	row.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var close := T.button("CLOSE", false, 16)
	close.name = "Close"
	close.pressed.connect(close_panel)
	row.add_child(close)
	panel = page
	_refresh_panel()
	HudSlots.claim_pointer(POINTER)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_panel() -> void:
	if panel == null:
		return
	panel.get_parent().queue_free()
	panel = null
	_dialog = null
	HudSlots.release_pointer(POINTER)
	if DisplayServer.get_name() != "headless" and str(hall.get("mode")) == "room":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh_panel() -> void:
	if panel == null:
		return
	_thumb.texture = vista_texture()
	var by := str(vista.get("shared_by")) if vista else ""
	_from.text = "Showing: the default mountains" if by == "" else "Showing: a picture from %s" % by


func _choose() -> void:
	if _dialog == null:
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.use_native_dialog = true
		_dialog.title = "Pick a picture for the view"
		_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.tga ; Pictures"])
		_dialog.file_selected.connect(share_file)
		panel.get_parent().add_child(_dialog)
	_dialog.popup_centered_ratio(0.7)


## Prepares and shares a picture file (from the panel or dropped onto the game).
func share_file(path: String) -> void:
	if vista == null:
		return
	if _status:
		_status.text = "Preparing the picture..."
	vista.call("share_file", path)


func _on_prepared(error: String) -> void:
	if _status:
		_status.text = error if error != "" else "Sent to the crew."


func _on_files_dropped(files: PackedStringArray) -> void:
	for f in files:
		if VistaImage.is_picture(f):
			share_file(f)
			return
