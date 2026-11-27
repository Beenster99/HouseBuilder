class_name AssetLibrary
extends RefCounted
## The 3D asset library. Every model is built in Blender by tools/assets/build.py and listed
## in internal/manifest.json; ask for one by id and get a ready node in the current look.
##
##   var window := AssetLibrary.make("opening.window.medium")
##   var beam := AssetLibrary.make("structure.section.ub_305x165x40", {"length": 6.0})
##   var bed := AssetLibrary.make_kind("bed_double")          # by building catalog kind
##   AssetLibrary.apply_look(root)                            # after Graphics.changed
##
## Axes: x right, y up, -z forward, metres. Fixtures sit on the floor at their centre with
## their back to +z; openings sit at the bottom centre of the hole, in the wall's plane;
## sections are 1 m long along z, centred, and stretch with "length".
## An id with no model yet gives a plain box of its size (opts "size": Vector3), so callers
## can switch over before the library is complete. Each mesh child is one build stage and
## material slot ("<stage>__<slot>"): hide and show stages with show_stages().

const ROOT := "res://modules/assets/internal/"
const MANIFEST := ROOT + "manifest.json"

static var _manifest: Dictionary = {}
static var _by_kind: Dictionary = {}
static var _templates: Dictionary = {}


## Every asset's manifest entry by id.
static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var text := FileAccess.get_file_as_string(MANIFEST)
		var parsed: Variant = JSON.parse_string(text) if text != "" else null
		if parsed is Dictionary:
			_manifest = parsed
			for id: String in _manifest:
				var kind := str(_manifest[id].get("kind", ""))
				if kind != "" and not _by_kind.has(kind):
					_by_kind[kind] = id
	return _manifest


static func has(id: String) -> bool:
	return manifest().has(id)


## Ids in id order, optionally only those with a tag ("fixture", "door", "steel"...) or in a
## category ("opening", "plant"...).
static func ids(tag: String = "") -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in manifest():
		var e: Dictionary = _manifest[id]
		if tag == "" or e.category == tag or (e.tags as Array).has(tag):
			out.append(id)
	out.sort()
	return out


## The manifest entry: label, category, family, kind, tags, stretch, aabb, stages, pieces
## ({node, stage, slot, mass kg}), sockets ({name: [x, y, z]}), tris, mass. {} if unknown.
static func info(id: String) -> Dictionary:
	return manifest().get(id, {})


## The asset that draws a building catalog kind or section ("door_fire", "ub_305x165x40"),
## or "" when there is none yet. A kind that is itself an asset id draws that asset.
static func id_for_kind(kind: String) -> String:
	manifest()
	if _by_kind.has(kind):
		return str(_by_kind[kind])
	return kind if has(kind) else ""


## The space the model fills, in its own axes.
static func bounds(id: String) -> AABB:
	var e := info(id)
	if e.is_empty():
		return AABB()
	var lo := _v3(e.aabb[0])
	return AABB(lo, _v3(e.aabb[1]) - lo).abs()


## A socket's position in the asset's own axes (Vector3.ZERO if it has none by that name).
static func socket(id: String, name: String) -> Vector3:
	var s: Dictionary = info(id).get("sockets", {})
	return _v3(s[name]) if s.has(name) else Vector3.ZERO


static func stages(id: String) -> PackedStringArray:
	return PackedStringArray(info(id).get("stages", []))


## A new node for the asset, in the current look. opts: "length", "height", "width" (m, for
## stretch assets, see info(id).stretch), "size" (Vector3, the box to draw when the id has
## no model), "family" (for that box's colour).
## Stretch assets are 1 m models scaled on the axes their stretch names: "z", "x" or "y"
## take "length"; "zy" (walls) takes "length" along z and "height" up; "xz" (floors, roof
## coverings, lawn) takes "width" along x and "length" along z.
## "fit" (Vector3, m) scales a fixed-size model to fill that box, so it matches the footprint
## the building model gives the part (a zero component keeps the model's own size).
## "lod" (m) draws the full model up to that distance from the camera and a plain box of its
## size beyond it: use it wherever many assets stand in one scene (design views, timelapse,
## demolition), so every view shows the real model close up.
static func make(id: String, opts: Dictionary = {}) -> Node3D:
	var e := info(id)
	var node: Node3D = null
	if not e.is_empty():
		var template := _template(id, e)
		if template:
			node = template.duplicate() as Node3D
	if node == null:
		node = _box(opts.get("size", bounds(id).size if not e.is_empty() else Vector3.ONE), str(opts.get("family", e.get("family", ""))))
		node.set_meta("asset_fallback", true)
	node.name = id.replace(".", "_")
	node.set_meta("asset_id", id)
	var stretch := str(e.get("stretch", ""))
	if stretch != "":
		node.scale = _stretch_scale(stretch, opts)
	elif opts.has("fit") and not e.is_empty() and not node.has_meta("asset_fallback"):
		var fit: Vector3 = opts.fit
		var own := bounds(id).size
		for k in 3:
			if fit[k] > 0.0 and own[k] > 0.001:
				node.scale[k] = fit[k] / own[k]
	if float(opts.get("lod", 0.0)) > 0.0 and not e.is_empty() and not node.has_meta("asset_fallback"):
		_add_lod(node, bounds(id), float(opts.lod), str(e.get("family", "")))
	apply_look(node)
	return node


## Beyond `far` metres the model's meshes give way to one box of its bounds.
static func _add_lod(node: Node3D, b: AABB, far: float, family: String) -> void:
	for mi in _meshes(node):
		mi.visibility_range_end = far
		mi.visibility_range_end_margin = far * 0.1
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	var proxy := MeshInstance3D.new()
	proxy.name = "lod_box"
	var bm := BoxMesh.new()
	bm.size = b.size
	proxy.mesh = bm
	proxy.position = b.get_center()
	proxy.visibility_range_begin = far
	proxy.visibility_range_begin_margin = far * 0.1
	proxy.set_meta("asset_box", family)
	node.add_child(proxy)


static func _stretch_scale(stretch: String, opts: Dictionary) -> Vector3:
	var length := float(opts.get("length", 1.0))
	match stretch:
		"x":
			return Vector3(length, 1, 1)
		"y":
			return Vector3(1, length, 1)
		"zy":
			return Vector3(1, float(opts.get("height", 1.0)), length)
		"xz":
			return Vector3(float(opts.get("width", 1.0)), 1, length)
	return Vector3(1, 1, length)


## make() for a building catalog kind or section; a plain box of `size` if nothing draws it.
static func make_kind(kind: String, opts: Dictionary = {}) -> Node3D:
	var id := id_for_kind(kind)
	return make(id if id != "" else "missing." + kind, opts)


## Sets every mesh under `root` to the current look: PBR materials when realistic (textured
## ones per material slot with flag assets.textures, else the model's own flat colours),
## ArtStyle's sketch material otherwise. Call again on Graphics.changed.
static func apply_look(root: Node) -> void:
	var real := ArtStyle.realistic()
	for mi: MeshInstance3D in _meshes(root):
		if mi.has_meta("asset_box"):
			mi.material_override = ArtStyle.material("", str(mi.get_meta("asset_box")))
		elif real:
			# (the textured material for the slot; the model's own flat PBR one without the flag)
			var holder := mi.get_parent() as Node3D
			mi.material_override = AssetMaterials.realistic(str(mi.name).get_slice("__", 1), holder.scale if holder else Vector3.ONE) if Flags.is_on(AssetMaterials.FLAG) else null
		else:
			var slot := str(mi.name).get_slice("__", 1)
			mi.material_override = ArtStyle.material(slot, "opening" if slot.begins_with("glass") else "fixture")


## Shows only the meshes whose build stage is in `shown` (all of them when `shown` is empty).
static func show_stages(root: Node, shown: PackedStringArray = PackedStringArray()) -> void:
	for mi: MeshInstance3D in _meshes(root):
		mi.visible = shown.is_empty() or shown.has(str(mi.name).get_slice("__", 0))


## Frees the cached models (tests, or after rebuilding the library while the game runs).
static func clear_cache() -> void:
	for id: String in _templates:
		if _templates[id] != null:
			(_templates[id] as Node).free()
	_templates.clear()
	_manifest.clear()
	_by_kind.clear()
	AssetMaterials.clear_cache()


static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_meshes(c))
	return out


static func _template(id: String, e: Dictionary) -> Node3D:
	if _templates.has(id):
		return _templates[id]
	var path := ROOT + str(e.file)
	var node: Node3D = null
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene:
			node = scene.instantiate() as Node3D
	if node == null and FileAccess.file_exists(path):
		# Not imported yet (a fresh checkout before the editor has run): read the file itself.
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) == OK:
			node = doc.generate_scene(state) as Node3D
	_templates[id] = node
	return node


static func _box(size: Vector3, family: String) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position.y = size.y / 2.0
	mi.set_meta("asset_box", family)
	root.add_child(mi)
	return root


static func _v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
