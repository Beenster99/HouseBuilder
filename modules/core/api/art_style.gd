class_name ArtStyle
extends RefCounted
## The game's two looks, picked in Graphics > Display > "Look": a clean architectural model
## (matte, pale, colour coded by what a part is) or realistic (each building material with
## its own colour, grain and bumps). Presentation only, so players may pick differently.
##
##   mesh.material_override = ArtStyle.material("masonry", "wall")
##   ArtStyle.ground()                   # the site's ground
##   Graphics.changed.connect(...)       # rebuild materials when the look changes
##
## Materials are cached per look; realistic ones map world-space triplanar textures, so
## plain BoxMeshes of any size look right without UVs.

const MODEL := 0
const REALISTIC := 1

## Clean model: pale, colour coded by family.
const MODEL_COLOURS := {
	"foundation": Color(0.58, 0.58, 0.6), "column": Color(0.86, 0.86, 0.88),
	"beam": Color(0.8, 0.82, 0.86), "brace": Color(0.78, 0.8, 0.84), "truss": Color(0.78, 0.8, 0.84),
	"slab": Color(0.92, 0.92, 0.92), "wall": Color(0.97, 0.96, 0.93), "roof": Color(0.74, 0.5, 0.42),
	"opening": Color(0.66, 0.8, 0.9, 0.55), "fixture": Color(0.82, 0.78, 0.7), "room": Color(0.9, 0.9, 0.9),
}
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
static var _textures: Dictionary = {}


static func style() -> int:
	return clampi(int(GraphicsOptions.get_value("art_style")), MODEL, REALISTIC)


static func realistic() -> bool:
	return style() == REALISTIC


## The look's material for a part. `material` is the building model's material name (may be
## empty); `family` the catalog family. Glass and openings come back transparent.
static func material(material_name: String, family: String) -> StandardMaterial3D:
	var s := style()
	var key := "%d|%s|%s" % [s, material_name, family]
	if _cache.has(key):
		return _cache[key]
	var m: StandardMaterial3D
	if s == REALISTIC:
		var name := material_name if REAL.has(material_name) else str(FAMILY_MATERIAL.get(family, "concrete"))
		if family == "opening":
			name = "glass"
		elif family == "roof" and not REAL.has(material_name):
			name = "tiles"
		m = _real(name)
	else:
		m = StandardMaterial3D.new()
		m.albedo_color = MODEL_COLOURS.get(family, Color(0.88, 0.88, 0.88))
		m.roughness = 0.9
		m.metallic_specular = 0.25
	if m.albedo_color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cache[key] = m
	return m


static func ground() -> StandardMaterial3D:
	var key := "%d|ground" % style()
	if _cache.has(key):
		return _cache[key]
	var m: StandardMaterial3D
	if style() == REALISTIC:
		m = _real("ground")
	else:
		m = StandardMaterial3D.new()
		m.albedo_color = Color(0.44, 0.45, 0.4)
		m.roughness = 1.0
		m.metallic_specular = 0.1
	_cache[key] = m
	return m


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
static func clear_cache() -> void:
	_cache.clear()
