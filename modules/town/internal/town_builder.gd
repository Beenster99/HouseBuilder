extends Node3D
## A finished building drawn as a few merged meshes (one per material and family), in the
## building model's own coordinates, with no physics bodies: a site with several of the
## firm's buildings on it stays cheap. Library objects (furniture, aircraft) are placed as
## their own models with a distance cut-off. add_colliders() gives it trimesh colliders for
## walking about on it. Follows the game's look (Graphics.changed).

const KIND_FAMILY := {"pad": "foundation", "footing": "foundation", "window": "opening",
		"door": "opening", "fitout": "fixture", "stairs": "room", "lift": "room", "frame": "column"}
## Library models vanish beyond this far, or eight times their size.
const MODEL_LOD := 70.0
## Collision layer for walking on the buildings (the site view's terrain uses layer 1 too).
const WALK_LAYER := 1

var record_id := ""
## mesh -> [material name, family], so a change of look swaps materials without rebuilding.
var _looks: Dictionary = {}
var _models: Array[Node3D] = []
var _bounds := AABB()


func build(model: BuildingModel, rid: String = "") -> void:
	record_id = rid
	name = "TownBuilding_" + (rid if rid != "" else "preview")
	var tools: Dictionary = {}  # look key -> SurfaceTool
	var keys: Dictionary = {}  # look key -> [material, family]
	var first := true
	for p: Dictionary in BuildingParts.from_model(model):
		var box: AABB = p.aabb
		_bounds = box if first else _bounds.merge(box)
		first = false
		var look: Dictionary = p.get("model", {})
		if not look.is_empty() and AssetLibrary.has(AssetLibrary.id_for_kind(str(look.kind))):
			_add_model(look)
			continue
		var family := str(p.get("family", p.kind))
		family = str(KIND_FAMILY.get(family, KIND_FAMILY.get(str(p.kind), family)))
		var mat := str(p.get("material", ""))
		var key := mat + "|" + family
		if not tools.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[key] = st
			keys[key] = [mat, family]
		_append(tools[key], p)
	for key: String in tools:
		var st: SurfaceTool = tools[key]
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.name = "Mesh_" + key.replace("|", "_")
		mi.mesh = st.commit()
		add_child(mi)
		_looks[mi] = keys[key]
	_apply_look()
	if not Graphics.changed.is_connected(_apply_look):
		Graphics.changed.connect(_apply_look)


func _exit_tree() -> void:
	if Graphics.changed.is_connected(_apply_look):
		Graphics.changed.disconnect(_apply_look)


## The building's extent in its own coordinates.
func bounds() -> AABB:
	return _bounds


func mesh_count() -> int:
	return _looks.size()


func _apply_look() -> void:
	for mi: MeshInstance3D in _looks:
		var k: Array = _looks[mi]
		mi.material_override = ArtStyle.material(str(k[0]), str(k[1]))
	for m in _models:
		if is_instance_valid(m):
			AssetLibrary.apply_look(m)


## Trimesh colliders on every merged mesh, so a walker can stand on floors and meet walls.
func add_colliders() -> void:
	if has_node("Walkable"):
		return
	var body := StaticBody3D.new()
	body.name = "Walkable"
	body.collision_layer = WALK_LAYER
	body.collision_mask = 0
	for mi: MeshInstance3D in _looks:
		var shape := mi.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	add_child(body)


func _add_model(look: Dictionary) -> void:
	var size: Vector3 = look.get("size", Vector3.ONE)
	var node := AssetLibrary.make_kind(str(look.kind), {"size": size, "fit": look.get("fit", size), "family": "fixture",
			"lod": maxf(MODEL_LOD, size.length() * 8.0)})
	node.position = look.get("at", Vector3.ZERO)
	node.rotation.y = deg_to_rad(float(look.get("rot", 0.0)))
	add_child(node)
	_models.append(node)


func _append(st: SurfaceTool, p: Dictionary) -> void:
	var shape: Dictionary = p.get("shape", {})
	if shape.has("cuts"):
		for xf: Transform3D in shape.cuts:
			_box(st, xf)
	elif shape.has("obb"):
		_box(st, shape.obb)
	elif shape.has("faces"):
		for f: Array in shape.faces:
			var c: Array = f[0]
			for i in range(1, c.size() - 1):
				_face(st, c[0], c[i], c[i + 1], f[1])
	elif shape.has("outline"):
		_slab(st, shape.outline, float(shape.top), float(shape.thick))
	else:
		var box: AABB = p.aabb
		var s := Vector3(maxf(box.size.x, 0.02), maxf(box.size.y, 0.02), maxf(box.size.z, 0.02))
		_box(st, Transform3D(Basis.from_scale(s), box.get_center()))


## A unit box (centred, 1 m) through a transform: six faces.
func _box(st: SurfaceTool, xf: Transform3D) -> void:
	var c: Array[Vector3] = []
	for i in 8:
		c.append(xf * Vector3(0.5 if i & 1 else -0.5, 0.5 if i & 2 else -0.5, 0.5 if i & 4 else -0.5))
	var centre := xf.origin
	for q: Array in [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]:
		var a: Vector3 = c[q[0]]
		var b: Vector3 = c[q[1]]
		var d: Vector3 = c[q[2]]
		var e: Vector3 = c[q[3]]
		var out := (a + b + d + e) * 0.25 - centre
		_face(st, a, b, d, out)
		_face(st, a, d, e, out)


## A polygon outline (x, z) extruded down from top by thick.
func _slab(st: SurfaceTool, outline: PackedVector2Array, top: float, thick: float) -> void:
	var poly := outline
	if poly.size() < 3:
		return
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		for i in range(1, poly.size() - 1):
			tris.append_array([0, i, i + 1])
	var bottom := top - maxf(thick, 0.02)
	for i in range(0, tris.size(), 3):
		var a := poly[tris[i]]
		var b := poly[tris[i + 1]]
		var c := poly[tris[i + 2]]
		_face(st, Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(c.x, top, c.y), Vector3.UP)
		_face(st, Vector3(a.x, bottom, a.y), Vector3(b.x, bottom, b.y), Vector3(c.x, bottom, c.y), Vector3.DOWN)
	var area := 0.0  # twice the signed area in (x, z): > 0 when the interior is left of each edge
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		area += p.x * q.y - q.x * p.y
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var d := q - p
		var out := Vector3(d.y, 0, -d.x) * signf(area)
		_face(st, Vector3(p.x, bottom, p.y), Vector3(q.x, bottom, q.y), Vector3(q.x, top, q.y), out)
		_face(st, Vector3(p.x, bottom, p.y), Vector3(q.x, top, q.y), Vector3(p.x, top, p.y), out)


## One triangle wound to face out (Godot's front faces wind clockwise seen from outside).
static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3) -> void:
	if (c - a).cross(b - a).dot(out) < 0.0:
		var swap := b
		b = c
		c = swap
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
