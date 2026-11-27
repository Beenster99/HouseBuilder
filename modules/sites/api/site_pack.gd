class_name SitePack
extends RefCounted
## A real-world site: one site pack file from tools/osm (format: tools/osm/FORMAT.md) read
## into plain data with helpers. No scenes; SitesBus.make_view() draws it.
##
##   var pack := SitePack.load_file("res://tools/osm/samples/bath-hillside-garages.sitepack.json")
##   if pack.error != "": push_warning(pack.error)
##   pack.height_at(x, z)          # ground y, bilinear on the terrain grid
##   pack.plot_outline()           # [[x, z], ...]
##   pack.difficulty()             # {rating, score, cost_multiplier_hint, factors}
##   pack.neighbours()             # buildings off the plot (obstacles for demolition)
##
## Metres, x east, y up, z south; y = 0 is the plot's mean ground level.

const FORMAT := "housebuilder.sitepack"
const VERSION := 1
## Site pack ground -> the structure module's soil ids (StructureSections.SOIL_BEARING).
const STRUCTURE_SOIL := {"firm": "clay", "made_ground": "made_ground", "soft_wet": "soft_clay"}

## Why the pack could not be read, or "".
var error := ""
## The parsed file. Read-only by convention.
var data: Dictionary = {}
## md5 of the file text, so peers can check they hold the same pack.
var digest := ""

var _heights := PackedFloat32Array()
var _nx := 0
var _nz := 0
var _ox := 0.0
var _oz := 0.0
var _step := 4.0


static func from_text(text: String) -> SitePack:
	var pack := SitePack.new()
	pack.digest = text.md5_text()
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	if not parsed is Dictionary:
		pack.error = "not a site pack (bad JSON)"
		return pack
	pack._read(parsed)
	return pack


static func load_file(path: String) -> SitePack:
	if not FileAccess.file_exists(path):
		var missing := SitePack.new()
		missing.error = "no site pack at %s" % path
		return missing
	return from_text(FileAccess.get_file_as_string(path))


func _read(d: Dictionary) -> void:
	if str(d.get("format", "")) != FORMAT:
		error = "not a site pack (format %s)" % str(d.get("format", ""))
		return
	if int(d.get("version", 0)) > VERSION:
		error = "site pack version %d is newer than this game reads (%d)" % [int(d.version), VERSION]
		return
	if not d.has("plot") or not d.has("terrain"):
		error = "site pack has no plot or terrain"
		return
	data = d
	var t: Dictionary = d.terrain
	var size: Array = t.get("size", [0, 0])
	_nx = int(size[0])
	_nz = int(size[1])
	var origin: Array = t.get("origin", [0, 0])
	_ox = float(origin[0])
	_oz = float(origin[1])
	_step = float(t.get("spacing_m", 4.0))
	_heights = Marshalls.base64_to_raw(str(t.get("heights_b64", ""))).to_float32_array()
	if _heights.size() != _nx * _nz:
		error = "terrain grid holds %d heights, expected %d" % [_heights.size(), _nx * _nz]
		data = {}


func ok() -> bool:
	return error == ""


func id() -> String:
	return str(data.get("id", ""))


func title() -> String:
	return str(data.get("name", id()))


func description() -> String:
	return str(data.get("description", ""))


func suited_to() -> PackedStringArray:
	return PackedStringArray(data.get("suited_to", []))


## Lines that must be shown wherever the site is used (OSM and terrain credits).
func attribution() -> PackedStringArray:
	return PackedStringArray(data.get("attribution", ["© OpenStreetMap contributors"]))


func radius() -> float:
	return float(data.get("radius_m", 300.0))


# --- Terrain ---------------------------------------------------------------------------

## Ground y at a plan point: bilinear on the grid, clamped at its edges.
func height_at(x: float, z: float) -> float:
	if _heights.is_empty():
		return 0.0
	var fx := clampf((x - _ox) / _step, 0.0, _nx - 1.0)
	var fz := clampf((z - _oz) / _step, 0.0, _nz - 1.0)
	var i := mini(int(fx), _nx - 2)
	var j := mini(int(fz), _nz - 2)
	var tx := fx - i
	var tz := fz - j
	var h00 := _heights[j * _nx + i]
	var h10 := _heights[j * _nx + i + 1]
	var h01 := _heights[(j + 1) * _nx + i]
	var h11 := _heights[(j + 1) * _nx + i + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## {"origin": Vector2 (x, z of the first sample), "spacing": m, "size": Vector2i,
## "heights": PackedFloat32Array row-major north to south}.
func terrain_grid() -> Dictionary:
	return {"origin": Vector2(_ox, _oz), "spacing": _step, "size": Vector2i(_nx, _nz), "heights": _heights}


func sea_level() -> float:
	return float(data.terrain.get("sea_level_y", -1000.0))


# --- The plot ----------------------------------------------------------------------------

func plot() -> Dictionary:
	return data.get("plot", {})


func plot_outline() -> Array:
	return plot().get("outline", [])


func plot_centre() -> Vector2:
	var o := plot_outline()
	var c := Vector2.ZERO
	for p: Array in o:
		c += Vector2(float(p[0]), float(p[1]))
	return c / maxf(o.size(), 1)


# --- The plot frame: the building model's coordinates on this site ------------------------
# The building model is drawn around (0, 0). On a site, its (0, 0) is the plot's centre and
# its y = 0 is the plot's mean ground (the pack's datum), with the same axes: x east, z south.

## Where the building model's origin sits in pack coordinates.
func plot_origin() -> Vector3:
	var c := plot_centre()
	return Vector3(c.x, 0.0, c.y)


## A pack point in the building model's coordinates.
func to_plot(p: Vector3) -> Vector3:
	return p - plot_origin()


## A building model point in pack coordinates (to draw it on the site).
func from_plot(p: Vector3) -> Vector3:
	return p + plot_origin()


## The plot boundary in building model coordinates: [[x, z], ...], as BuildingModel outlines.
func plot_outline_local() -> Array:
	var o := plot_origin()
	var out: Array = []
	for p: Array in plot_outline():
		out.append([float(p[0]) - o.x, float(p[1]) - o.z])
	return out


## The plot's bounding box in building model coordinates (position = north-west corner).
func plot_bounds_local() -> Rect2:
	var outline := plot_outline_local()
	if outline.is_empty():
		return Rect2()
	var r := Rect2(Vector2(outline[0][0], outline[0][1]), Vector2.ZERO)
	for p: Array in outline:
		r = r.expand(Vector2(p[0], p[1]))
	return r


## True when a building model point (x, z) is inside the plot.
func plot_contains_local(x: float, z: float) -> bool:
	return BuildingModel.outline_has_point(plot_outline_local(), x, z)


## The plot's area in square metres.
func plot_area() -> float:
	return BuildingModel.outline_area(plot_outline())


## Ground height (y) under a building model point.
func ground_at_local(x: float, z: float) -> float:
	var o := plot_origin()
	return height_at(x + o.x, z + o.z)


func ground() -> Dictionary:
	return plot().get("ground", {})


## "firm", "made_ground" or "soft_wet".
func soil() -> String:
	return str(ground().get("soil", "firm"))


## The soil as the structure module's foundations read it (BuildingModel meta "soil").
func structure_soil() -> String:
	return STRUCTURE_SOIL.get(soil(), "clay")


func difficulty() -> Dictionary:
	return plot().get("difficulty", {"rating": 1, "score": 0, "cost_multiplier_hint": 1.0, "factors": []})


func rating() -> int:
	return int(difficulty().get("rating", 1))


## The pack's suggested build cost multiplier (contracts decide the real effect).
func cost_multiplier_hint() -> float:
	return float(difficulty().get("cost_multiplier_hint", 1.0))


## Difficulty factors, most severe first: {id, severity, label, detail, metrics}.
func factors() -> Array:
	return difficulty().get("factors", [])


func has_factor(factor_id: String) -> bool:
	for f: Dictionary in factors():
		if str(f.get("id", "")) == factor_id:
			return true
	return false


## The plot's problems in words for players: one paragraph per factor.
func notes_text() -> String:
	var lines := PackedStringArray()
	var g := ground()
	lines.append("%s. Difficulty %d of 5. Suggested cost x%.2f." % [title(), rating(), cost_multiplier_hint()])
	lines.append("Plot %d m², ground %s, falls %.0f%% to the %s." % [roundi(float(plot().get("area_m2", 0.0))),
			soil().replace("_", " "), float(g.get("slope_pct", 0.0)), str(g.get("downhill", "-"))])
	for f: Dictionary in factors():
		lines.append("%s: %s" % [str(f.get("label", "")), str(f.get("detail", ""))])
	if str(plot().get("notes", "")) != "":
		lines.append(str(plot().notes))
	return "\n\n".join(lines)


# --- Features ----------------------------------------------------------------------------

func buildings() -> Array:
	return data.get("buildings", [])


## Buildings standing on the plot (brownfield: clear them first).
func existing_buildings() -> Array:
	return buildings().filter(func(b: Dictionary) -> bool: return bool(b.get("on_plot", false)))


## Buildings off the plot: real obstacles. Each {id, kind, outline, base_y, height_m,
## protected, ...} as in the pack; top is base_y + height_m.
func neighbours() -> Array:
	return buildings().filter(func(b: Dictionary) -> bool: return not bool(b.get("on_plot", false)))


func protected_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for b: Dictionary in buildings():
		if bool(b.get("protected", false)):
			out.append(str(b.id))
	return out


func features(kind: String) -> Array:
	return data.get(kind, [])
