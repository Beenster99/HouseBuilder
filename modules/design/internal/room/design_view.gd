extends Node3D
## Draws a BuildingModel: one node per part or room, rebuilt per entry when it changes, and
## everything again when the model is loaded. Levels above the one being worked on are
## hidden so plans read clearly. tint(id, colour) highlights selections and locks.

const ROOM_ALPHA := 0.38
const DEFAULT_COLOUR := Color(0.85, 0.85, 0.85)
const GLASS := Color(0.55, 0.78, 0.92, 0.45)
const DOOR := Color(0.5, 0.34, 0.2)

var model: BuildingModel
var level := 0
var show_rooms := true
## The plan's cut: in the 2D plan, walls on the working level are drawn only up to this
## height, as an architect's plan cuts them, so doors and windows show. INF in 3D.
var cut := INF
var _nodes: Dictionary = {}  # entry id -> Node3D
var _tints: Dictionary = {}  # entry id -> Color
var _mats: Dictionary = {}


func bind(m: BuildingModel) -> void:
	model = m
	model.entry_added.connect(refresh)
	model.entry_changed.connect(refresh)
	model.entry_removed.connect(refresh)
	model.loaded.connect(rebuild)
	model.levels_changed.connect(rebuild)
	model.changed.connect(_on_changed)
	Graphics.changed.connect(rebuild)
	rebuild()


## Stairs and lifts cut holes in the floors they pass through: redraw those slabs.
func _on_changed(op: Dictionary) -> void:
	var touches := false
	for pid in model.parts_of_family("circulation"):
		touches = true
		break
	if not touches and str(op.get("op", "")) != "remove":
		return
	for pid in model.parts_of_family("slab"):
		_drop(pid)
		_build(pid)


func rebuild() -> void:
	for id: String in _nodes:
		(_nodes[id] as Node).queue_free()
	_nodes.clear()
	for id: String in model.parts:
		_build(id)
	for id: String in model.rooms:
		_build(id)


## Redraws one entry (and, for a wall or opening, the wall with its openings).
func refresh(id: String) -> void:
	_drop(id)
	if model.parts.has(id) or model.rooms.has(id):
		_build(id)
	var e := model.entry(id)
	var host := str(e.get("host", ""))
	if host != "" and model.parts.has(host):
		_drop(host)
		_build(host)
	elif not e.is_empty() and model.catalog.family_of(str(e.get("kind", ""))) == "wall":
		for o in model.openings_in(id):
			_drop(o)
			_build(o)
	if e.is_empty():
		# A removed wall's openings went with it; a removed opening leaves a hole to fill.
		for wid: String in model.parts_of_family("wall"):
			if _nodes.has(wid) and (_nodes[wid] as Node).get_meta("holes", 0) != model.openings_in(wid).size():
				_drop(wid)
				_build(wid)


func _drop(id: String) -> void:
	if _nodes.has(id):
		(_nodes[id] as Node).queue_free()
		_nodes.erase(id)


func show_level(l: int) -> void:
	var was := level
	level = l
	if cut < INF and was != l:
		rebuild()
		return
	for id: String in _nodes:
		_apply_visibility(id)


func set_cut(height: float) -> void:
	if height != cut:
		cut = height
		rebuild()


func set_show_rooms(on: bool) -> void:
	show_rooms = on
	for id: String in model.rooms:
		_apply_visibility(id)


func node_count() -> int:
	return _nodes.size()


func has_node_for(id: String) -> bool:
	return _nodes.has(id)


func tint(id: String, colour: Variant) -> void:
	var had: Variant = _tints.get(id)
	if colour == null:
		_tints.erase(id)
	else:
		_tints[id] = colour
	if had != colour and _nodes.has(id):
		_drop(id)
		_build(id)


func tints() -> Dictionary:
	return _tints.duplicate()


func _apply_visibility(id: String) -> void:
	var n: Node3D = _nodes.get(id)
	if n:
		var on := model.level_of(id) <= level
		if model.rooms.has(id):
			on = on and show_rooms and model.level_of(id) == level
		n.visible = on


func _build(id: String) -> void:
	var root := Node3D.new()
	root.name = id
	root.set_meta("entry_id", id)
	if model.rooms.has(id):
		_room(root, id)
	else:
		_part(root, id)
	add_child(root)
	_nodes[id] = root
	_apply_visibility(id)


func _part(root: Node3D, id: String) -> void:
	var e: Dictionary = model.parts[id]
	var cat := model.catalog
	var kind := str(e.kind)
	var spec := cat.kind(kind)
	var fam := cat.family_of(kind)
	var sec := cat.section(str(e.get("section", "")))
	# The game's look (ArtStyle: clean model or realistic), or the highlight when tinted.
	var colour: Variant = _colour(id, ArtStyle.material(str(e.get("material", "")), fam).albedo_color) \
			if _tints.has(id) else ArtStyle.material(str(e.get("material", "")), fam)
	var floor_y := model.level_elevation(model.level_of(id))
	match cat.shape_of(kind):
		"point":
			var at := _v3(e.at) + Vector3(0, floor_y, 0)
			var rot := Basis(Vector3.UP, deg_to_rad(float(e.get("rot", 0.0))))
			if kind == "lift":
				var shaft := Vector3(float(e.get("w", spec.get("w", 2.0))), model.part_height(id), float(e.get("d", spec.get("d", 2.0))))
				var c: Variant = _colour(id, Color(0.55, 0.6, 0.68, 0.55)) if _tints.has(id) else ArtStyle.material("glass", "opening")
				_box(root, at + Vector3(0, shaft.y / 2.0, 0), shaft, rot, c)
			elif fam == "fixture":
				var size := Vector3(float(spec.get("w", 0.5)), float(spec.get("h", 0.8)), float(spec.get("d", 0.5)))
				_box(root, at + Vector3(0, size.y / 2.0, 0), size, rot, colour)
			elif kind == "pile":
				var length := float(e.get("length", spec.get("length", 10.0)))
				var dia := float(sec.get("dia", 0.45))
				_box(root, at - Vector3(0, length / 2.0, 0), Vector3(dia, length, dia), rot, colour)
			elif str(sec.get("shape", "")) == "pad":
				var w := float(sec.get("w", 1.0))
				var d := float(sec.get("d", 0.5))
				_box(root, at - Vector3(0, d / 2.0, 0), Vector3(w, d, w), rot, colour)
			else:
				var h := model.part_height(id)
				var w := float(sec.get("w", 0.3))
				var d := float(sec.get("d", w))
				_box(root, at + Vector3(0, h / 2.0, 0), Vector3(w, h, d), rot, colour)
		"line":
			var a := _v3(e.a) + Vector3(0, floor_y, 0)
			var b := _v3(e.b) + Vector3(0, floor_y, 0)
			if fam == "wall":
				_wall(root, id, a, b, colour)
			elif kind == "stair":
				_stair(root, id, a, b, colour)
			else:
				var w := float(sec.get("w", 0.2))
				var d := float(sec.get("d", 0.3))
				# Beams hang below their line (their top is at a and b).
				_linear(root, a - Vector3(0, d / 2.0, 0), b - Vector3(0, d / 2.0, 0), w, d, colour)
		"area":
			var t := maxf(float(sec.get("d", 0.2)), 0.05)
			var y := floor_y + float(e.get("y", 0.0))
			var pieces: Array = [_outline(e.outline)]
			if fam == "slab" and absf(float(e.get("y", 0.0))) < 0.01:
				pieces = _cut_voids(pieces[0], model.voids_on(model.level_of(id)))
			for poly: PackedVector2Array in pieces:
				_prism(root, poly, y - t, y, colour)
		"opening":
			var pts := model.points_of(id)
			if pts.size() == 2:
				var h := float(e.get("h", spec.get("h", 2.0)))
				if model.level_of(id) == level:
					h = minf(h, maxf(0.05, cut - float(e.get("sill", spec.get("sill", 0.0)))))
				var glass := str(e.get("material", "")) == "glass" or kind.begins_with("window")
				var c: Variant = _colour(id, GLASS if glass else DOOR) if _tints.has(id) \
						else ArtStyle.material("glass" if glass else "timber", "opening" if glass else "fixture")
				_linear(root, pts[0] + Vector3(0, h / 2.0, 0), pts[1] + Vector3(0, h / 2.0, 0), 0.06, h, c)


## A wall drawn in pieces around its openings: solid runs, and the pieces under and over each.
func _wall(root: Node3D, id: String, a: Vector3, b: Vector3, colour: Variant) -> void:
	var e: Dictionary = model.parts[id]
	var h := model.part_height(id)
	if model.level_of(id) == level:
		h = minf(h, cut)
	var t := float(model.catalog.section(str(e.get("section", ""))).get("d", 0.2))
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	if length < 0.01:
		return
	var holes: Array = []
	var openings := model.openings_in(id)
	root.set_meta("holes", openings.size())
	for oid in openings:
		var o: Dictionary = model.parts[oid]
		var spec := model.catalog.kind(str(o.kind))
		var w := float(o.get("w", spec.get("w", 0.9)))
		var sill := float(o.get("sill", spec.get("sill", 0.0)))
		var oh := float(o.get("h", spec.get("h", 2.0)))
		holes.append([clampf(float(o.t) - w / 2.0, 0.0, length), clampf(float(o.t) + w / 2.0, 0.0, length), sill, sill + oh])
	holes.sort_custom(func(x: Array, z: Array) -> bool: return x[0] < z[0])
	var dir := (b - a) / length
	var up := Vector3.UP
	var cursor := 0.0
	for hole: Array in holes:
		if hole[0] > cursor:
			_linear(root, a + dir * cursor + up * h / 2.0, a + dir * hole[0] + up * h / 2.0, t, h, colour)
		var bottom: float = hole[2]
		var top: float = minf(hole[3], h)
		if bottom > 0.01:
			_linear(root, a + dir * hole[0] + up * bottom / 2.0, a + dir * hole[1] + up * bottom / 2.0, t, bottom, colour)
		if top < h - 0.01:
			_linear(root, a + dir * hole[0] + up * (top + h) / 2.0, a + dir * hole[1] + up * (top + h) / 2.0, t, h - top, colour)
		cursor = maxf(cursor, hole[1])
	if cursor < length:
		_linear(root, a + dir * cursor + up * h / 2.0, b + up * h / 2.0, t, h, colour)


## A flight of steps from a (foot) to b (head), rising to the next level's floor.
func _stair(root: Node3D, id: String, a: Vector3, b: Vector3, colour: Variant) -> void:
	var rise := model.level_height(model.level_of(id))
	var w := model.stair_width(id)
	var steps := maxi(2, int(round(rise / 0.18)))
	for i in steps:
		var f0 := float(i) / steps
		var f1 := float(i + 1) / steps
		var h := rise * f1
		_linear(root, a.lerp(b, f0) + Vector3(0, h / 2.0, 0), a.lerp(b, f1) + Vector3(0, h / 2.0, 0), w, h, colour)


## A floor outline with stair and lift holes taken out, as pieces with no holes in them (each
## hole splits the floor in two through its middle first, so no piece wraps round a hole).
static func _cut_voids(poly: PackedVector2Array, voids: Array) -> Array:
	var pieces: Array = [poly]
	for v: Dictionary in voids:
		var hole := _outline(v.outline)
		if hole.size() < 3:
			continue
		var cx := 0.0
		for p in hole:
			cx += p.x
		cx /= hole.size()
		var big := 10000.0
		var left := PackedVector2Array([Vector2(-big, -big), Vector2(cx, -big), Vector2(cx, big), Vector2(-big, big)])
		var right := PackedVector2Array([Vector2(cx, -big), Vector2(big, -big), Vector2(big, big), Vector2(cx, big)])
		var next: Array = []
		for piece: PackedVector2Array in pieces:
			for half: PackedVector2Array in [left, right]:
				for part: PackedVector2Array in Geometry2D.intersect_polygons(piece, half):
					for rest: PackedVector2Array in Geometry2D.clip_polygons(part, hole):
						next.append(rest)
		pieces = next
	return pieces


func _room(root: Node3D, id: String) -> void:
	var e: Dictionary = model.rooms[id]
	var rt := model.catalog.room_type(str(e.type))
	var c := Color.html(str(rt.get("colour", "dddddd")))
	c.a = ROOM_ALPHA
	c = _colour(id, c)
	var y := model.level_elevation(int(e.level))
	var poly := _outline(e.outline)
	_prism(root, poly, y + 0.01, y + 0.04, c)
	if poly.size() >= 3:
		var centre := Vector2.ZERO
		for v in poly:
			centre += v
		centre /= poly.size()
		var label := Label3D.new()
		var title := str(e.get("name", ""))
		if title == "":
			title = str(rt.get("label", e.type))
		var q := BuildingQuantities.room(model, id)
		label.text = "%s\n%.1f m²%s" % [title, q.area, "  (min %.0f)" % q.min_area if q.short else ""]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 36
		label.pixel_size = 0.01
		label.modulate = Color(1.0, 0.55, 0.35) if q.short else Color(0.08, 0.08, 0.1)
		label.outline_modulate = Color(1, 1, 1, 0.85)
		label.outline_size = 8
		label.position = Vector3(centre.x, y + 0.5, centre.y)
		root.add_child(label)


func _colour(id: String, base: Color) -> Color:
	if _tints.has(id):
		var t: Color = _tints[id]
		var out := base.lerp(t, 0.7)
		out.a = maxf(base.a, 0.6)
		return out
	return base


func _mat(c: Variant) -> Material:
	if c is Material:
		return c
	var key: String = (c as Color).to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	if (c as Color).a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


func _box(root: Node3D, centre: Vector3, size: Vector3, basis: Basis, c: Variant) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.transform = Transform3D(basis, centre)
	root.add_child(mi)


## A bar from a to b (centre line), w wide and h tall.
func _linear(root: Node3D, a: Vector3, b: Vector3, w: float, h: float, c: Variant) -> void:
	var d := b - a
	var plan := Vector2(d.x, d.z)
	if d.length() < 0.01:
		return
	var basis := Basis(Vector3.UP, -plan.angle())
	if absf(d.y) > 0.001:
		basis = basis * Basis(Vector3.BACK, atan2(d.y, plan.length()))
	_box(root, (a + b) / 2.0, Vector3(d.length(), h, w), basis, c)


func _prism(root: Node3D, poly: PackedVector2Array, bottom: float, top: float, c: Variant) -> void:
	if poly.size() < 3:
		return
	if Geometry2D.is_polygon_clockwise(poly):
		poly.reverse()
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, tris.size(), 3):
		for k: int in [0, 2, 1]:
			var v := poly[tris[i + k]]
			st.add_vertex(Vector3(v.x, top, v.y))
		for k: int in [0, 1, 2]:
			var v := poly[tris[i + k]]
			st.add_vertex(Vector3(v.x, bottom, v.y))
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var quad := [Vector3(p.x, bottom, p.y), Vector3(q.x, bottom, q.y), Vector3(q.x, top, q.y), Vector3(p.x, top, p.y)]
		for k: int in [0, 2, 1, 0, 3, 2]:
			st.add_vertex(quad[k])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(c)
	if c is Color and (c as Color).a < 0.99:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


static func _v3(a: Variant) -> Vector3:
	if a is Vector3:
		return a
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


static func _outline(raw: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Variant in raw:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out
