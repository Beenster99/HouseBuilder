class_name AssetMaterials
extends RefCounted
## The realistic look's textured materials for the library's slots. internal/materials.json
## (written by tools/assets/build.py) gives each slot its colour, roughness, metal and
## surface pattern; internal/textures holds a seamless detail and normal map per pattern
## (tools/assets/textures.py). Mapped triplanar in the model's own space, so nothing needs
## UVs and a piece keeps its texture as it moves or falls. Used by AssetLibrary.apply_look()
## when flag assets.textures is on.

const TABLE := "res://modules/assets/internal/materials.json"
const TEXTURES := "res://modules/assets/internal/textures/"
const FLAG := "assets.textures"

static var _table: Dictionary = {}
static var _cache: Dictionary = {}
static var _textures: Dictionary = {}


static func table() -> Dictionary:
	if _table.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE))
		if parsed is Dictionary:
			_table = parsed
	return _table


static func has(slot: String) -> bool:
	return table().has(slot)


## The slot's surface pattern ("brick", "timber"...), "" when it is a plain colour.
static func pattern(slot: String) -> String:
	return str(table().get(slot, {}).get("pattern", ""))


## The slot's realistic material, or null for a slot the table does not know. `scale` is
## the asset node's scale, so stretched pieces keep their texture at true size.
static func realistic(slot: String, scale: Vector3 = Vector3.ONE) -> StandardMaterial3D:
	var d: Dictionary = table().get(slot, {})
	if d.is_empty():
		return null
	var patterned := str(d.pattern) != ""
	var key := slot if not patterned or scale.is_equal_approx(Vector3.ONE) else "%s|%.3f|%.3f|%.3f" % [slot, scale.x, scale.y, scale.z]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	var rgb: Array = d.rgb
	m.albedo_color = Color(rgb[0], rgb[1], rgb[2], float(d.alpha)).linear_to_srgb()
	m.albedo_color.a = float(d.alpha)
	m.roughness = float(d.rough)
	m.metallic = float(d.metal)
	if float(d.alpha) < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if bool(d.get("glow", false)):
		m.emission_enabled = true
		m.emission = m.albedo_color
		m.emission_energy_multiplier = 1.5
	if patterned:
		var albedo := _texture(str(d.pattern) + "_a")
		var normal := _texture(str(d.pattern) + "_n")
		if albedo:
			m.albedo_texture = albedo
			m.uv1_triplanar = true
			m.uv1_scale = scale / float(d.size)
			if normal:
				m.normal_enabled = true
				m.normal_texture = normal
	_cache[key] = m
	return m


static func _texture(name: String) -> Texture2D:
	if not _textures.has(name):
		var path := TEXTURES + name + ".png"
		_textures[name] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _textures[name]


static func clear_cache() -> void:
	_cache.clear()
	_textures.clear()
	_table.clear()
