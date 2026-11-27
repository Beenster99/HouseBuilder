extends Node3D
## The room's mark-up layers, each shown or hidden from the HUD's Layers menu:
##   notes       comments pinned to a spot or a part, kept in the design (shared, saved,
##               undoable: each is a "note:<id>" key in the building's design metadata);
##   pings       "look here" markers from a middle-click tap, gone after a few seconds;
##   dimensions  every wall's length on the working level;
##   measure     this player's tape measure (the Measure tool), not shared.

const NOTE_PREFIX := "note:"
const PIN := Color(1.0, 0.78, 0.2)

var model: BuildingModel
var net: MultiplayerBus
var level := 0
var layers := {"notes": true, "pings": true, "dimensions": true}
var _notes: Node3D
var _pings: Node3D
var _dims: Node3D
var _measure: Node3D
var _ping_nodes: Dictionary = {}  # ping id -> {node, born}
var _dim_nodes: Dictionary = {}  # wall id -> Label3D


func bind(m: BuildingModel, bus: MultiplayerBus) -> void:
	model = m
	net = bus
	for n: String in ["Notes", "Pings", "Dimensions", "Measure"]:
		var node := Node3D.new()
		node.name = n
		add_child(node)
	_notes = $Notes
	_pings = $Pings
	_dims = $Dimensions
	_measure = $Measure
	model.changed.connect(_on_changed)
	model.entry_added.connect(_dim_entry)
	model.entry_changed.connect(_dim_entry)
	model.entry_removed.connect(_dim_entry)
	model.loaded.connect(redraw)
	model.levels_changed.connect(redraw)
	net.ping_received.connect(_on_ping)
	net.ping_removed.connect(_drop_ping)
	for p: Dictionary in net.pings():
		_on_ping(p)
	redraw()


func _on_changed(op: Dictionary) -> void:
	if str(op.get("op", "")) == "set_meta" or str(op.get("op", "")) == "batch":
		_draw_notes()


func set_level(l: int) -> void:
	level = l
	redraw()


func set_layer(id: String, on: bool) -> void:
	layers[id] = on
	_notes.visible = layers.notes
	_pings.visible = layers.pings
	_dims.visible = layers.dimensions


func redraw() -> void:
	_draw_notes()
	_draw_dimensions()


# --- Notes --------------------------------------------------------------------------------

## The notes in the design: [{key, at: Vector3 (world), level, target, text, author, peer}].
static func notes_of(m: BuildingModel) -> Array:
	var out: Array = []
	for k: String in m.meta:
		if k.begins_with(NOTE_PREFIX) and m.meta[k] is Dictionary:
			var n: Dictionary = (m.meta[k] as Dictionary).duplicate()
			n["key"] = k
			out.append(n)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.key) < str(b.key))
	return out


func _draw_notes() -> void:
	for c in _notes.get_children():
		c.queue_free()
	for n: Dictionary in notes_of(model):
		if int(n.get("level", 0)) != level:
			continue
		var at := Vector3(float(n.at[0]), float(n.at[1]), float(n.at[2]))
		var colour := Color.html(str(n.get("colour", PIN.to_html())))
		var pin := Node3D.new()
		pin.name = str(n.key).replace(":", "_")
		pin.set_meta("note_key", n.key)
		pin.position = at
		var post := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.12
		cyl.bottom_radius = 0.0
		cyl.height = 0.5
		post.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colour
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		post.material_override = mat
		post.position.y = 0.25
		pin.add_child(post)
		var label := Label3D.new()
		label.text = "%s: %s" % [str(n.get("author", "")), str(n.get("text", ""))]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 34
		label.pixel_size = 0.01
		label.width = 700
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.modulate = Color(0.08, 0.08, 0.1)
		label.outline_modulate = colour.lightened(0.6)
		label.outline_size = 14
		label.position.y = 0.95
		pin.add_child(label)
		_notes.add_child(pin)


# --- Pings --------------------------------------------------------------------------------

func _on_ping(p: Dictionary) -> void:
	var at: Vector3 = p.at
	var colour: Color = p.colour
	var root := Node3D.new()
	root.position = at
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.45
	torus.outer_radius = 0.6
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	ring.material_override = mat
	ring.position.y = 0.06
	root.add_child(ring)
	var label := Label3D.new()
	label.text = "%s%s" % [str(p.name), (": " + str(p.label)) if str(p.label) != "" else ""]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 44
	label.pixel_size = 0.01
	label.modulate = colour
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.outline_size = 10
	label.position.y = 1.6
	root.add_child(label)
	_pings.add_child(root)
	_ping_nodes[int(p.id)] = {"node": root, "born": Time.get_ticks_msec() / 1000.0}


func _drop_ping(id: int) -> void:
	var p: Dictionary = _ping_nodes.get(id, {})
	if not p.is_empty():
		(p.node as Node).queue_free()
		_ping_nodes.erase(id)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for id: int in _ping_nodes.keys():
		var p: Dictionary = _ping_nodes[id]
		var age := now - float(p.born)
		if age > MultiplayerBus.PING_LIFE:
			_drop_ping(id)
		else:
			var s := 1.0 + 0.25 * sin(age * 6.0)
			(p.node as Node3D).get_child(0).scale = Vector3(s, 1, s)


func ping_count() -> int:
	return _ping_nodes.size()


# --- Dimensions and the tape measure -------------------------------------------------------

func _draw_dimensions() -> void:
	for c in _dims.get_children():
		c.queue_free()
	_dim_nodes.clear()
	for pid in model.parts_on(level):
		_dim_entry(pid)


## Puts a wall's length label up, moves it, or takes it down, as the wall changes.
func _dim_entry(id: String) -> void:
	if _dim_nodes.has(id):
		(_dim_nodes[id] as Node).queue_free()
		_dim_nodes.erase(id)
	if not model.parts.has(id):
		return
	var e: Dictionary = model.parts[id]
	if model.catalog.family_of(str(e.kind)) != "wall" or int(e.get("level", -1)) != level:
		return
	var a := Vector3(float(e.a[0]), 0, float(e.a[2]))
	var b := Vector3(float(e.b[0]), 0, float(e.b[2]))
	var label := _dim_label("%.2f m" % a.distance_to(b))
	label.position = (a + b) / 2.0 + Vector3(0, model.level_elevation(level) + model.part_height(id) + 0.25, 0)
	_dims.add_child(label)
	_dim_nodes[id] = label


## This player's tape: from a to b (world), or clear it with null.
func set_measure(a: Variant, b: Variant) -> void:
	for c in _measure.get_children():
		c.queue_free()
	if a == null or b == null:
		return
	var pa: Vector3 = a
	var pb: Vector3 = b
	var line := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var lift := Vector3(0, 0.08, 0)
	im.surface_add_vertex(pa + lift)
	im.surface_add_vertex(pb + lift)
	var side := (pb - pa).cross(Vector3.UP).normalized() * 0.2
	for p: Vector3 in [pa, pb]:
		im.surface_add_vertex(p + lift - side)
		im.surface_add_vertex(p + lift + side)
	im.surface_end()
	line.mesh = im
	_measure.add_child(line)
	var plan := Vector2(pb.x - pa.x, pb.z - pa.z)
	var label := _dim_label("%.2f m  (%.2f × %.2f)" % [plan.length(), absf(plan.x), absf(plan.y)])
	label.position = (pa + pb) / 2.0 + Vector3(0, 0.5, 0)
	label.modulate = Color(1, 1, 1)
	label.outline_modulate = Color(0, 0, 0, 0.9)
	_measure.add_child(label)


func measure_text() -> String:
	for c in _measure.get_children():
		if c is Label3D:
			return (c as Label3D).text
	return ""


func _dim_label(text: String) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 30
	label.pixel_size = 0.01
	label.modulate = Color(0.1, 0.12, 0.2)
	label.outline_modulate = Color(1, 1, 1, 0.8)
	label.outline_size = 8
	return label
