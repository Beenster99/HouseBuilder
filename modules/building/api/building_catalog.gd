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

const DATA_SCRIPT := preload("res://modules/building/internal/catalog_data.gd")
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


## The shared default catalog (built once).
static func default_catalog() -> BuildingCatalog:
	if _default == null:
		_default = from_data(DATA_SCRIPT.DATA)
	return _default


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
