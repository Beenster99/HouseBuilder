class_name BuildingCatalog
extends RefCounted
## What a building can be made of: materials, section sizes, part kinds, room types and
## their costs. Plain data (internal/catalog_data.gd), read once; BuildingModel checks every
## edit against it and BuildingQuantities prices from it.
##
##   var cat := BuildingCatalog.default_catalog()
##   cat.kinds_in("beam")                  # ["beam"]
##   cat.sections_for("beam", "steel")     # ["ub_203x133x25", ...]
##   cat.section("ub_305x165x40")          # {label, shape, w, d, area, iy, wy, kg_m}
##   cat.room_type("classroom")            # {label, live_load, min_area, ...}
##
## A kind: {label, family, shape, structural, materials: [..], sections: {material: [..]},
## rates: {material: [unit, rate]}} plus, per family, w/h/sill (openings), w/d/h and
## capacity (fixtures), pitch (pitched roofs), length (piles).
## Families: FAMILIES below. Shapes: "point", "line", "area", "opening" (BuildingModel).
##
## The 3D library's placeable assets (modules/assets: furniture, equipment, plant, street
## and garden objects) are kinds too, family "fixture", with the asset id as the kind id:
##   cat.library_kinds()                       # every one, in manifest order
##   cat.kind("office.desk.bench_4")           # {..., asset, group, category, tags, loose, outdoor}
##   cat.services_of("furniture.kitchen.sink_1000")  # {power_w, cold, hot, drain, gas, data, heating, heat_w, gen_w}
##   cat.group_of(kind)                        # palette group: "Furniture", "Healthcare"...
## Costs, services and capacities come from internal/library_data.gd. loose: true marks things
## that are not part of the build (vehicles, site plant, luggage): they cost nothing.

const DATA_SCRIPT := preload("res://modules/building/internal/catalog_data.gd")
const LIBRARY_SCRIPT := preload("res://modules/building/internal/library_data.gd")
## Every key services_of() returns.
const SERVICE_KEYS := {"power_w": 0, "cold": false, "hot": false, "drain": false, "gas": false, "data": false,
		"heating": false, "heat_w": 0, "gen_w": 0}
const SHAPES: PackedStringArray = ["point", "line", "area", "opening"]
const RATE_UNITS: PackedStringArray = ["m3", "m2", "m", "t", "each"]

var currency := "GBP"
var rates_note := ""
var families: PackedStringArray = []
var connection_kinds: PackedStringArray = []
## id -> {label, density, strength, e, colour}
var materials: Dictionary = {}
## id -> {label, shape, ...} with area (m2), iy (m4) and wy (m3) filled in where they apply
var sections: Dictionary = {}
## id -> kind spec (see above)
var kinds: Dictionary = {}
## id -> {label, category, live_load, min_area, area_per_person, capacity, fit_out, colour}
var room_types: Dictionary = {}

static var _default: BuildingCatalog


## Flag: the default catalog includes the 3D library's placeable assets.
const LIBRARY_FLAG := "building.library"


## The shared default catalog (built once), with the 3D library's placeable assets while the
## building.library flag is on.
static func default_catalog() -> BuildingCatalog:
	if _default == null:
		_default = from_data(DATA_SCRIPT.DATA)
		if Flags.is_on(LIBRARY_FLAG):
			_default.add_library(AssetLibrary.manifest())
	return _default


## Drops the shared catalog so the next default_catalog() builds it again (tests that flip
## building.library). Models already made keep the catalog they were given.
static func reset_default() -> void:
	_default = null


## Adds the placeable assets of an asset manifest (AssetLibrary.manifest()) as fixture kinds.
## Assets that already draw a catalog kind, stretch to length, or are not placeable
## (library_data.gd CATEGORIES and SKIP) are left out. Returns how many were added.
func add_library(manifest: Dictionary) -> int:
	var n := 0
	for id: String in manifest:
		var e: Dictionary = manifest[id]
		var category := str(e.get("category", ""))
		if not category in LIBRARY_SCRIPT.CATEGORIES or str(e.get("kind", "")) != "" or str(e.get("stretch", "")) != "" \
				or kinds.has(id) or _skipped(id):
			continue
		var rule := library_rule(id)
		var loose := bool(rule.get("loose", false))
		var mat := _material_of(e.get("pieces", []))
		var box: Array = e.get("aabb", [[0, 0, 0], [0, 0, 0]])
		var lo: Array = box[0]
		var hi: Array = box[1]
		kinds[id] = {"label": str(e.get("label", id)), "family": "fixture", "shape": "point", "structural": false,
			"w": snappedf(float(hi[0]) - float(lo[0]), 0.01), "d": snappedf(float(hi[2]) - float(lo[2]), 0.01),
			"h": snappedf(float(hi[1]) - float(lo[1]), 0.01),
			"materials": [mat], "sections": {}, "rates": {mat: ["each", 0.0 if loose else float(rule.get("cost", 0.0))]},
			"mass": {mat: float(e.get("mass", 0.0))}, "capacity": (rule.get("cap", {}) as Dictionary).duplicate(),
			"asset": id, "category": category, "group": str(LIBRARY_SCRIPT.GROUPS.get(category, category.capitalize())),
			"tags": PackedStringArray(e.get("tags", [])), "loose": loose, "outdoor": bool(rule.get("outdoor", false)),
			"services": _services(rule)}
		n += 1
	return n


## The merged library rule for an asset id: every RULES prefix of it, shortest first.
static func library_rule(asset_id: String) -> Dictionary:
	var hits: Array = []
	for prefix: String in LIBRARY_SCRIPT.RULES:
		if asset_id.begins_with(prefix):
			hits.append(prefix)
	hits.sort_custom(func(a: String, b: String) -> bool: return a.length() < b.length())
	var out := {}
	for prefix: String in hits:
		out.merge(LIBRARY_SCRIPT.RULES[prefix], true)
	return out


static func _skipped(asset_id: String) -> bool:
	for prefix: String in LIBRARY_SCRIPT.SKIP:
		if asset_id.begins_with(prefix):
			return true
	return false


static func _services(rule: Dictionary) -> Dictionary:
	var out := SERVICE_KEYS.duplicate()
	out.power_w = int(rule.get("power", 0))
	out.heat_w = int(rule.get("heat", 0))
	out.gen_w = int(rule.get("gen", 0))
	for k: String in ["cold", "hot", "drain", "gas", "data", "heating"]:
		out[k] = bool(rule.get(k, false))
	return out


## The catalog material for an asset: the one most of its mass is made of.
static func _material_of(pieces: Array) -> String:
	var by := {}
	for p: Variant in pieces:
		if p is Dictionary:
			var m := _slot_material(str(p.get("slot", "")))
			by[m] = float(by.get(m, 0.0)) + float(p.get("mass", 0.0))
	var best := "steel"
	var most := -1.0
	for m: String in by:
		if float(by[m]) > most:
			most = float(by[m])
			best = m
	return best


static func _slot_material(slot: String) -> String:
	for pair: Array in [[["wood", "timber", "oak", "pine", "ply", "softwood", "hardwood", "glulam", "laminate", "worktop", "fabric", "leather", "carpet", "bark", "foliage", "soil", "denim"], "timber"],
			[["glass", "mirror", "screen"], "glass"], [["ceramic", "enamel", "clay"], "ceramic"],
			[["concrete", "render", "paving", "asphalt"], "concrete"], [["brick", "block", "stone", "slate"], "masonry"]]:
		for word: String in pair[0]:
			if word in slot:
				return str(pair[1])
	return "steel"


## Every library kind id (the placeable 3D assets), in manifest order.
func library_kinds() -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in kinds:
		if (kinds[k] as Dictionary).has("asset"):
			out.append(k)
	return out


## What a kind needs from the building's services: SERVICE_KEYS, all present. Library kinds
## carry their own; the catalog's fixtures have theirs in library_data.gd KIND_SERVICES.
func services_of(kind_id: String) -> Dictionary:
	var spec := kind(kind_id)
	if spec.get("services") is Dictionary:
		return (spec.services as Dictionary).duplicate()
	return _services(LIBRARY_SCRIPT.KIND_SERVICES.get(kind_id, {}))


## The palette group of a fixture kind ("Furniture", "Healthcare"...): library kinds name
## theirs; the catalog's own fixtures are "Fittings".
func group_of(kind_id: String) -> String:
	return str(kind(kind_id).get("group", "Fittings" if family_of(kind_id) == "fixture" else family_of(kind_id).capitalize()))


## A catalog from plain data shaped like internal/catalog_data.gd (a deep copy is kept).
static func from_data(data: Dictionary) -> BuildingCatalog:
	var c := BuildingCatalog.new()
	var d: Dictionary = data.duplicate(true)
	c.currency = str(d.get("currency", "GBP"))
	c.rates_note = str(d.get("rates_note", ""))
	c.families = PackedStringArray(d.get("families", []))
	c.connection_kinds = PackedStringArray(d.get("connection_kinds", []))
	c.materials = d.get("materials", {})
	c.kinds = d.get("kinds", {})
	c.room_types = d.get("room_types", {})
	for sid: String in d.get("sections", {}):
		c.sections[sid] = _derive(d.sections[sid])
	return c


# Lookups. Each returns {} or [] for an unknown id, never null.

func has_kind(kind_id: String) -> bool:
	return kinds.has(kind_id)


func kind(kind_id: String) -> Dictionary:
	return kinds.get(kind_id, {})


func family_of(kind_id: String) -> String:
	return str(kind(kind_id).get("family", ""))


func shape_of(kind_id: String) -> String:
	return str(kind(kind_id).get("shape", ""))


## Kind ids of one family, in catalog order.
func kinds_in(family: String) -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in kinds:
		if str(kinds[k].family) == family:
			out.append(k)
	return out


func material(material_id: String) -> Dictionary:
	return materials.get(material_id, {})


## Materials a kind may be made of; the first is its default.
func materials_for(kind_id: String) -> PackedStringArray:
	return PackedStringArray(kind(kind_id).get("materials", []))


## Section ids for a kind in a material; the first is its default. [] when the kind has
## no sections (openings, fixtures, pitched roofs).
func sections_for(kind_id: String, material_id: String) -> PackedStringArray:
	return PackedStringArray((kind(kind_id).get("sections", {}) as Dictionary).get(material_id, []))


func section(section_id: String) -> Dictionary:
	return sections.get(section_id, {})


func has_room_type(type_id: String) -> bool:
	return room_types.has(type_id)


func room_type(type_id: String) -> Dictionary:
	return room_types.get(type_id, {})


## Room type ids of one category ("domestic", "education", ...), in catalog order.
func room_types_in(category: String) -> PackedStringArray:
	var out := PackedStringArray()
	for t: String in room_types:
		if str(room_types[t].category) == category:
			out.append(t)
	return out


## The price of one part: {unit, rate}; the section's own rate wins over the kind's.
## {} if the catalog has none.
func rate(kind_id: String, material_id: String, section_id: String = "") -> Dictionary:
	var s := section(section_id)
	var r: Variant = s.get("rate")
	if not r is Array:
		r = (kind(kind_id).get("rates", {}) as Dictionary).get(material_id)
	if not r is Array or (r as Array).size() < 2:
		return {}
	return {"unit": str(r[0]), "rate": float(r[1])}


## Everything wrong with the catalog's own data (unknown references, missing rates), for
## tests and for anyone adding parts. [] when it is sound.
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in kinds:
		var spec: Dictionary = kinds[k]
		if not str(spec.get("family", "")) in families:
			out.append("%s: unknown family %s" % [k, spec.get("family")])
		if not str(spec.get("shape", "")) in SHAPES:
			out.append("%s: unknown shape %s" % [k, spec.get("shape")])
		var mats: Array = spec.get("materials", [])
		if mats.is_empty():
			out.append("%s: no materials" % k)
		for m: String in mats:
			if not materials.has(m):
				out.append("%s: unknown material %s" % [k, m])
			for sid: String in sections_for(k, m):
				if not sections.has(sid):
					out.append("%s: unknown section %s" % [k, sid])
				elif rate(k, m, sid).is_empty():
					out.append("%s: no rate for %s in %s" % [k, sid, m])
			if sections_for(k, m).is_empty() and rate(k, m).is_empty():
				out.append("%s: no rate for %s" % [k, m])
			var r := rate(k, m)
			if not r.is_empty() and not str(r.unit) in RATE_UNITS:
				out.append("%s: unknown rate unit %s" % [k, r.unit])
	for t: String in room_types:
		for key: String in ["label", "category", "live_load", "min_area", "area_per_person", "capacity", "fit_out"]:
			if not (room_types[t] as Dictionary).has(key):
				out.append("room %s: no %s" % [t, key])
	return out


## A section with its area (m2), iy (m4) and wy (m3) worked out from its shape.
static func _derive(s: Dictionary) -> Dictionary:
	var out := s.duplicate(true)
	var w := float(s.get("w", 0.0))
	var d := float(s.get("d", 0.0))
	match str(s.get("shape", "")):
		"rect":
			out["area"] = w * d
			out["iy"] = w * d * d * d / 12.0
			out["wy"] = w * d * d / 6.0
		"pile":
			var r := float(s.get("dia", 0.0)) * 0.5
			out["area"] = PI * r * r
			out["iy"] = PI * r * r * r * r / 4.0
			out["wy"] = PI * r * r * r / 4.0
		"pad":
			out["area"] = w * w
	return out
