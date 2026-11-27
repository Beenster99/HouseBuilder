class_name ArtStyle
extends RefCounted
## The game's two looks, picked in Graphics > Display > "Look":
##   Architectural model: SketchUp style. Plain white matte surfaces, sun shadows, and ink
##     edge lines on every silhouette and crease, drawn by a screen pass the Graphics
##     autoload puts on every camera (internal/art/outline.gdshader), so no mesh needs line
##     geometry. Glass is a pale see-through grey.
##   Realistic: each material with its own colour, grain and bumps (PBR).
## Presentation only, so players may pick differently.
##
##   mesh.material_override = ArtStyle.material("masonry", "wall")
##   ArtStyle.register_material("oak_floor", preload("...tres"))   # an asset library's PBR
##   ArtStyle.material("oak_floor", "")   # that material, or white in the model look
##   ArtStyle.ground()                    # the site's ground
##   Graphics.changed.connect(...)        # rebuild materials when the look changes
##
## Materials are cached per look; the built-in realistic ones map world-space triplanar
## textures, so plain BoxMeshes of any size look right without UVs.

const MODEL := 0
const REALISTIC := 1

## Architectural model: everything white, glass a pale see-through grey.
const MODEL_WHITE := Color(0.96, 0.96, 0.95)
const MODEL_GLASS := Color(0.78, 0.82, 0.85, 0.45)
const MODEL_GROUND := Color(0.4, 0.41, 0.4)
const OUTLINE_SHADER := "res://modules/core/internal/art/outline.gdshader"
const OUTLINE_NODE := "ArtOutline"
## Realistic: [albedo, roughness, metallic, texture scale m, bump strength] per material.
const REAL := {
	"concrete": [Color(0.6, 0.59, 0.56), 0.92, 0.0, 1.2, 0.6],
	"masonry": [Color(0.56, 0.3, 0.22), 0.9, 0.0, 0.4, 1.2],
	"timber": [Color(0.62, 0.45, 0.28), 0.75, 0.0, 0.6, 0.5],
	"steel": [Color(0.42, 0.45, 0.5), 0.42, 0.85, 2.0, 0.2],
	"glass": [Color(0.55, 0.7, 0.78, 0.35), 0.05, 0.3, 4.0, 0.0],
	"tiles": [Color(0.38, 0.2, 0.16), 0.85, 0.0, 0.5, 1.0],
	"plaster": [Color(0.88, 0.86, 0.8), 0.95, 0.0, 1.5, 0.3],
	"ground": [Color(0.32, 0.38, 0.22), 1.0, 0.0, 3.0, 0.8],
}
## Realistic material for a family when the part names none.
const FAMILY_MATERIAL := {
	"foundation": "concrete", "column": "concrete", "beam": "steel", "brace": "steel",
	"truss": "timber", "slab": "concrete", "wall": "masonry", "roof": "tiles",
	"opening": "glass", "fixture": "timber", "room": "plaster",
}

static var _cache: Dictionary = {}
static var _registered: Dictionary = {}  # name -> realistic BaseMaterial3D
static var _outline: ShaderMaterial
static var _textures: Dictionary = {}


static func style() -> int:
	return clampi(int(GraphicsOptions.get_value("art_style")), MODEL, REALISTIC)


static func realistic() -> bool:
	return style() == REALISTIC


## The look's material for a part. `material` is the building model's material name (may be
## empty); `family` the catalog family. Glass and openings come back transparent.
## A registered (asset library) material wins over the built-in ones for its name.
static func material(material_name: String, family: String) -> BaseMaterial3D:
	return material_in(style(), material_name, family)


## The same for a given look (the splash warms both looks' shaders).
static func material_in(s: int, material_name: String, family: String) -> BaseMaterial3D:
	var key := "%d|%s|%s" % [s, material_name, family]
	if _cache.has(key):
		return _cache[key]
	if _registered.has(material_name):
		var reg: BaseMaterial3D = _registered[material_name]
		var out: BaseMaterial3D = reg if s == REALISTIC else _white(_transparent(reg))
		_cache[key] = out
		return out
	var m: StandardMaterial3D
	if s == REALISTIC:
		var name := material_name if REAL.has(material_name) else str(FAMILY_MATERIAL.get(family, "concrete"))
		if family == "opening":
			name = "glass"
		elif family == "roof" and not REAL.has(material_name):
			name = "tiles"
		m = _real(name)
	else:
		m = _white(family == "opening" or material_name == "glass")
	if m.albedo_color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cache[key] = m
	return m


static func ground() -> StandardMaterial3D:
	return ground_in(style())


static func ground_in(s: int) -> StandardMaterial3D:
	var key := "%d|ground" % s
	if _cache.has(key):
		return _cache[key]
	var m: StandardMaterial3D
	if s == REALISTIC:
		m = _real("ground")
	else:
		m = StandardMaterial3D.new()
		m.albedo_color = MODEL_GROUND
		m.roughness = 1.0
		m.metallic_specular = 0.0
	_cache[key] = m
	return m


## An asset library's realistic material for `name`; the model look shows it white (or pale
## glass when it is see-through).
static func register_material(name: String, realistic: BaseMaterial3D) -> void:
	_registered[name] = realistic
	clear_cache()


static func unregister_material(name: String) -> void:
	if _registered.erase(name):
		clear_cache()


static func has_material(name: String) -> bool:
	return _registered.has(name) or REAL.has(name)


static func _white(glass: bool) -> StandardMaterial3D:
	var key := "white|%s" % glass
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = MODEL_GLASS if glass else MODEL_WHITE
	m.roughness = 1.0
	m.metallic_specular = 0.0
	if glass:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cache[key] = m
	return m


static func _transparent(m: BaseMaterial3D) -> bool:
	return m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or m.albedo_color.a < 1.0


## Puts the edge-line pass on a camera in the model look, and takes it off in realistic.
## The Graphics autoload calls this for every camera, including ones made later.
static func apply_to_camera(cam: Camera3D) -> void:
	var quad := cam.get_node_or_null(OUTLINE_NODE) as MeshInstance3D
	if style() != MODEL:
		if quad:
			quad.queue_free()
		return
	if quad:
		return
	quad = MeshInstance3D.new()
	quad.name = OUTLINE_NODE
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	quad.mesh = mesh
	quad.material_override = outline_material()
	quad.extra_cull_margin = 16384.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	quad.position = Vector3(0.0, 0.0, -1.0)
	cam.add_child(quad)


static func _real(name: String) -> StandardMaterial3D:
	var d: Array = REAL[name]
	var m := StandardMaterial3D.new()
	m.albedo_color = d[0]
	m.roughness = d[1]
	m.metallic = d[2]
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / float(d[3])
	if DisplayServer.get_name() != "headless":
		m.albedo_texture = _texture(name, false)
		if float(d[4]) > 0.0:
			m.normal_enabled = true
			m.normal_texture = _texture(name, true)
			m.normal_scale = d[4]
	return m


## Seamless noise per material: grain for timber, mottling for concrete and so on.
static func _texture(name: String, normal: bool) -> NoiseTexture2D:
	var key := "%s|%s" % [name, normal]
	if _textures.has(key):
		return _textures[key]
	var n := FastNoiseLite.new()
	n.seed = hash(name) & 0xffff
	n.noise_type = FastNoiseLite.TYPE_CELLULAR if name == "masonry" or name == "tiles" else FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.06 if name == "timber" else 0.02
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = n
	if name == "timber":
		n.domain_warp_enabled = true
		t.width = 512
		t.height = 64
	if normal:
		t.as_normal_map = true
		t.bump_strength = 6.0
	else:
		var g := Gradient.new()
		g.set_color(0, Color(0.82, 0.82, 0.82))
		g.set_color(1, Color(1.0, 1.0, 1.0))
		t.color_ramp = g
	_textures[key] = t
	return t


## Forget cached materials (after the look changes, views rebuild from fresh ones).
## Every material both looks can show, and the edge-line pass: what the splash screen draws
## once so their shaders are compiled before play.
static func warm_materials() -> Array[Material]:
	var out: Array[Material] = []
	var seen := {}
	for s in [MODEL, REALISTIC]:
		var names: Array = REAL.keys() + _registered.keys() + [""]
		for n: String in names:
			for fam: String in FAMILY_MATERIAL.keys():
				var m := material_in(s, n, fam)
				if not seen.has(m):
					seen[m] = true
					out.append(m)
		out.append(ground_in(s))
	out.append(outline_material())
	return out


static func outline_material() -> ShaderMaterial:
	if _outline == null:
		_outline = ShaderMaterial.new()
		_outline.shader = load(OUTLINE_SHADER)
	return _outline


static func clear_cache() -> void:
	_cache.clear()
