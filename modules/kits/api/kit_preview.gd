class_name KitPreview
extends VBoxContainer
## The object preview: the thing turning slowly in a small window of its own, and its
## figures underneath (size, weight, cost, power, water...). Shows a catalog kind, a saved
## module, or a room type's brief. Drag across the picture to turn it yourself.
##
##   var p := KitPreview.new()
##   add_child(p)
##   p.show_kind(catalog, "bath")
##   p.show_kit(catalog, kit)            # a saved module (KitCapture.capture)

const KitMesh := preload("res://modules/kits/internal/kit_mesh.gd")

## Turns a second while nobody drags it, rad.
const SPIN := 0.6
const PICTURE := Vector2i(300, 210)
const FOV := 30.0
## Modules show as a cutaway, walls this high, m.
const CUT := 1.1

var title_label: Label
var figures: GridContainer
var viewport: SubViewport
var camera: Camera3D
var turntable: Node3D
## What is shown: {type: "object" | "module" | "room", id}.
var showing: Dictionary = {}
var _dragging := false
var _pitch := -0.5
var _fit := 3.0
var _shown: Node3D


func _init() -> void:
	name = "KitPreview"
	add_theme_constant_override("separation", 6)
	custom_minimum_size = Vector2(PICTURE.x, 0)
	title_label = Label.new()
	title_label.name = "Title"
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", BsxTheme.ACCENT)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(title_label)
	var box := SubViewportContainer.new()
	box.name = "Picture"
	box.stretch = true
	box.custom_minimum_size = Vector2(PICTURE)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.gui_input.connect(_on_picture_input)
	add_child(box)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = PICTURE
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	box.add_child(viewport)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.11, 0.13, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.82)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	viewport.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-20), deg_to_rad(-140), 0)
	fill.light_energy = 0.35
	viewport.add_child(fill)
	turntable = Node3D.new()
	turntable.name = "Turntable"
	viewport.add_child(turntable)
	camera = Camera3D.new()
	camera.fov = FOV
	camera.current = true
	viewport.add_child(camera)
	figures = GridContainer.new()
	figures.name = "Figures"
	figures.columns = 2
	figures.add_theme_constant_override("h_separation", 12)
	figures.add_theme_constant_override("v_separation", 2)
	add_child(figures)


func _ready() -> void:
	var g := get_node_or_null("/root/Graphics")
	if g and g.has_signal("changed"):
		g.connect("changed", _on_look_changed)


func _process(delta: float) -> void:
	if not _dragging and turntable:
		turntable.rotation.y += SPIN * delta
	_place_camera()


## A catalog kind (a fitting, door, window, column...).
func show_kind(catalog: BuildingCatalog, kind: String) -> void:
	showing = {"type": "object", "id": kind}
	_pitch = -0.45
	var s := ObjectSpecs.for_kind(catalog, kind)
	_set_model(KitMesh.object(catalog, kind) if not s.is_empty() else null)
	_set_text(str(s.get("label", kind)), ObjectSpecs.lines(s))


## A saved module: its room, walls, doors, windows and fittings.
func show_kit(catalog: BuildingCatalog, kit: Dictionary) -> void:
	showing = {"type": "module", "id": str(kit.get("name", ""))}
	var m := KitCapture.as_model(kit, catalog)
	var size: Array = kit.get("size", [0, 0])
	var centre := Vector3(snappedf(float(size[0]) / 2.0, 0.25), 0, snappedf(float(size[1]) / 2.0, 0.25))
	var node := KitMesh.build(m, centre, CUT)
	# Centre the picture on the room, not on the placing pivot.
	for c in node.get_children():
		(c as Node3D).position -= Vector3(float(size[0]) / 2.0 - centre.x, 0, float(size[1]) / 2.0 - centre.z)
	_set_model(node)
	_pitch = -0.75
	var s := ObjectSpecs.for_kit(catalog, kit)
	var lines := ObjectSpecs.lines(s)
	var rt := catalog.room_type(str(s.get("room_type", "")))
	if not rt.is_empty():
		lines.push_front(["Room", str(rt.get("label", s.room_type))])
	if str(s.get("author", "")) != "":
		lines.append(["Saved by", str(s.author)])
	_set_text("Module: %s" % str(kit.get("name", "")), lines)


## A room type: no model, its brief.
func show_room_type(catalog: BuildingCatalog, type: String) -> void:
	showing = {"type": "room", "id": type}
	_pitch = -0.75
	var s := ObjectSpecs.for_room_type(catalog, type)
	var size := 3.0
	if float(s.get("min_area", 0.0)) > 0.0:
		size = sqrt(float(s.min_area))
	var m := BuildingModel.new("", "room", catalog)
	var C := preload("res://modules/building/api/building_commands.gd")
	m.apply(C.place_part("slab", 0, {"outline": C.rect(0, 0, size, size), "y": 0.0}))
	_set_model(KitMesh.build(m, Vector3(size / 2.0, 0, size / 2.0)))
	var lines := ObjectSpecs.lines(s)
	var needs: Variant = s.get("needs", s.get("requires", {}))
	if needs is Dictionary and not (needs as Dictionary).is_empty():
		var bits: Array = []
		for k: String in needs:
			bits.append("%s %s" % [str(needs[k]), k.replace("_", " ")])
		lines.append(["Needs", ", ".join(bits)])
	_set_text(str(s.get("label", type)), lines)


func clear() -> void:
	showing = {}
	_set_model(null)
	_set_text("", [])


## The figures as shown, [[name, value]...] (tests read this).
func figure_rows() -> Array:
	var out: Array = []
	var kids := figures.get_children()
	for i in range(0, kids.size() - 1, 2):
		out.append([(kids[i] as Label).text, (kids[i + 1] as Label).text])
	return out


func shown_node() -> Node3D:
	return _shown


func _set_model(node: Node3D) -> void:
	if _shown and is_instance_valid(_shown):
		_shown.queue_free()
		turntable.remove_child(_shown)
	_shown = node
	if node == null:
		return
	turntable.add_child(node)
	var box := _bounds(turntable)
	# Stand it on the turntable's centre.
	node.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
	_fit = maxf(box.size.length(), 0.3)
	turntable.position = Vector3.ZERO
	camera.set_meta("look_y", box.size.y * 0.45)
	_place_camera()


func _place_camera() -> void:
	if camera == null:
		return
	# The game's field-of-view setting reaches every camera; this one keeps its own.
	camera.fov = FOV
	var dist := (_fit / 2.0) / sin(deg_to_rad(FOV) / 2.0) * 1.02
	var look := Vector3(0, float(camera.get_meta("look_y", 0.5)), 0)
	var dir := Vector3(0, 0, 1).rotated(Vector3.RIGHT, _pitch)
	var pos := look + dir * dist
	camera.transform = Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos)
	camera.near = maxf(dist * 0.02, 0.02)
	camera.far = dist * 6.0 + 10.0


func _set_text(title: String, lines: Array) -> void:
	title_label.text = title
	for c in figures.get_children():
		figures.remove_child(c)
		c.queue_free()
	for row: Array in lines:
		var k := Label.new()
		k.text = str(row[0])
		k.add_theme_font_size_override("font_size", 13)
		k.add_theme_color_override("font_color", BsxTheme.MUTED)
		figures.add_child(k)
		var v := Label.new()
		v.text = str(row[1])
		v.add_theme_font_size_override("font_size", 13)
		v.add_theme_color_override("font_color", BsxTheme.TEXT)
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.custom_minimum_size.x = PICTURE.x - 90
		figures.add_child(v)


func _on_picture_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (ev as InputEventMouseButton).pressed
		accept_event()
	elif ev is InputEventMouseMotion and _dragging:
		var r := (ev as InputEventMouseMotion).relative
		turntable.rotation.y += r.x * 0.01
		_pitch = clampf(_pitch - r.y * 0.01, -1.4, 0.2)
		accept_event()
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		var b := (ev as InputEventMouseButton).button_index
		if b == MOUSE_BUTTON_WHEEL_UP:
			_fit = maxf(_fit * 0.9, 0.2)
			accept_event()
		elif b == MOUSE_BUTTON_WHEEL_DOWN:
			_fit *= 1.1
			accept_event()


func _on_look_changed() -> void:
	if _shown:
		AssetLibrary.apply_look(_shown)


static func _bounds(root: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi: Node in root.find_children("*", "VisualInstance3D", true, false):
		var vi := mi as VisualInstance3D
		var xf := _local_xf(vi, root)
		var b := xf * vi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box if not first else AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)


static func _local_xf(n: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var at: Node = n
	while at != null and at != root:
		if at is Node3D:
			xf = (at as Node3D).transform * xf
		at = at.get_parent()
	return xf
