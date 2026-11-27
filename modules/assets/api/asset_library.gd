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
## or "" when there is none yet.
static func id_for_kind(kind: String) -> String:
	manifest()
	return str(_by_kind.get(kind, ""))


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


## A new node for the asset, in the current look. opts: "length" (m, for stretch assets),
## "size" (Vector3, the box to draw when the id has no model), "family" (for that box's
## colour).
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
	if opts.has("length") and str(e.get("stretch", "")) != "":
		var length := float(opts.length)
		node.scale = Vector3(1, length, 1) if e.stretch == "y" else Vector3(1, 1, length)
	apply_look(node)
	return node


## make() for a building catalog kind or section; a plain box of `size` if nothing draws it.
static func make_kind(kind: String, opts: Dictionary = {}) -> Node3D:
	var id := id_for_kind(kind)
	return make(id if id != "" else "missing." + kind, opts)


## Sets every mesh under `root` to the current look: the model's own PBR materials when
## realistic, ArtStyle's sketch material otherwise. Call again on Graphics.changed.
static func apply_look(root: Node) -> void:
	var real := ArtStyle.realistic()
	for mi: MeshInstance3D in _meshes(root):
		if mi.has_meta("asset_box"):
			mi.material_override = ArtStyle.material("", str(mi.get_meta("asset_box")))
		elif real:
			mi.material_override = null
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
