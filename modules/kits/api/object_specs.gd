class_name ObjectSpecs
extends RefCounted
## The figures the object preview shows for a catalog kind: size, weight, cost and what it
## needs from the services (power, cold and hot water, waste, heat).
##
##   var s := ObjectSpecs.for_kind(catalog, "bath")
##   # {label, family, size: Vector3 (w, h, d m), mass kg, cost, currency, power_w, cold_lpm,
##   #  hot_lpm, waste, gas_kw, capacity: {}, asset, tags, note}
##
## Size, cost and mass come from the building catalog and its rates (the same numbers the
## cost panel uses); a modelled asset's manifest mass wins for loose furniture. Services
## demands are typical UK design figures (BS EN 806 flow rates, appliance ratings).

const C := preload("res://modules/building/api/building_commands.gd")

## Typical demands per kind: power_w (running), cold_lpm / hot_lpm (design flow, litres a
## minute), waste (the outlet), gas_kw (heat input), note.
const DEMAND := {
	"wc": {"cold_lpm": 7.8, "waste": "100 mm soil", "note": "6/4 litre dual flush"},
	"basin": {"cold_lpm": 9.0, "hot_lpm": 9.0, "waste": "32 mm"},
	"bath": {"cold_lpm": 18.0, "hot_lpm": 18.0, "waste": "40 mm", "note": "About 150 litres to fill"},
	"shower": {"power_w": 9500, "cold_lpm": 12.0, "waste": "40 mm", "note": "Electric shower, 9.5 kW; or 12 l/min mixed from the boiler"},
	"kitchen_unit": {"power_w": 3000, "cold_lpm": 12.0, "hot_lpm": 12.0, "waste": "40 mm", "note": "Sink unit with a 13 A appliance circuit"},
	"sofa": {},
	"dining_table": {},
	"bed_single": {},
	"bed_double": {},
	"hospital_bed": {"power_w": 300, "note": "Powered profiling bed, medical gas at the bedhead"},
	"cell_bench": {},
	"desk_office": {"power_w": 250, "note": "Computer, screen and task light"},
	"desk_pupil": {},
	"desk_teacher": {"power_w": 150, "note": "Laptop and interactive screen feed"},
	"hall_chair": {},
	"reception_desk": {"power_w": 400, "note": "Two workstations and a printer"},
	"locker": {},
	"consumer_unit": {"power_w": 23000, "note": "100 A single-phase supply, the source of every power run"},
	"water_main": {"cold_lpm": 24.0, "note": "25 mm MDPE service pipe, the source of every cold run"},
	"boiler": {"power_w": 100, "gas_kw": 30.0, "cold_lpm": 12.0, "hot_lpm": 12.0, "waste": "22 mm condensate", "note": "30 kW combination boiler"},
	"soil_stack": {"waste": "100 mm stack", "note": "Takes the WCs and wastes above it"},
	"lift": {"power_w": 11000, "note": "8-person traction lift"},
	"door_vehicle": {"power_w": 750, "note": "Motorised roller shutter"},
	"door_secure": {"power_w": 50, "note": "Access-controlled lock"},
	"door_fire": {"note": "FD30S, self-closing"},
}


## Everything the preview shows for one catalog kind ({} for an unknown kind).
static func for_kind(catalog: BuildingCatalog, kind: String) -> Dictionary:
	var spec := catalog.kind(kind)
	if spec.is_empty():
		return {}
	var asset := AssetLibrary.id_for_kind(kind)
	var size := Vector3(float(spec.get("w", 0.0)), float(spec.get("h", 0.0)), float(spec.get("d", 0.0)))
	if asset != "":
		var b := AssetLibrary.bounds(asset)
		if size.x <= 0.0:
			size.x = b.size.x
		if size.y <= 0.0:
			size.y = b.size.y
		if size.z <= 0.0:
			size.z = b.size.z
	if size.x <= 0.0 and str(spec.get("family", "")) == "column":
		size = Vector3(0.3, BuildingModel.DEFAULT_LEVEL_HEIGHT, 0.3)
	var q := _priced(catalog, kind, str(spec.get("shape", "")))
	var mass := float(q.get("mass", 0.0))
	if asset != "" and float(AssetLibrary.info(asset).get("mass", 0.0)) > 0.0 and (mass <= 0.0 or str(spec.get("family", "")) == "fixture"):
		mass = float(AssetLibrary.info(asset).mass)
	var d: Dictionary = DEMAND.get(kind, {})
	return {
		"label": str(spec.get("label", kind)),
		"family": str(spec.get("family", "")),
		"size": size,
		"mass": mass,
		"cost": float(q.get("cost", 0.0)),
		"currency": catalog.currency,
		"power_w": float(d.get("power_w", 0.0)),
		"cold_lpm": float(d.get("cold_lpm", 0.0)),
		"hot_lpm": float(d.get("hot_lpm", 0.0)),
		"waste": str(d.get("waste", "")),
		"gas_kw": float(d.get("gas_kw", 0.0)),
		"capacity": spec.get("capacity", {}),
		"materials": catalog.materials_for(kind),
		"asset": asset,
		"tags": AssetLibrary.info(asset).get("tags", []) if asset != "" else [],
		"note": str(d.get("note", "")),
	}


## The same figures summed over a module's parts: size (w, h, d), mass, cost, power_w,
## cold_lpm, hot_lpm, gas_kw, area m², parts, fittings {kind: n}.
static func for_kit(catalog: BuildingCatalog, kit: Dictionary) -> Dictionary:
	var m := KitCapture.as_model(kit, catalog)
	var t := BuildingQuantities.totals(m)
	var out := {"label": str(kit.get("name", "Module")), "family": "module", "currency": catalog.currency,
			"cost": float(t.get("cost", 0.0)), "mass": float(t.get("mass", 0.0)),
			"power_w": 0.0, "cold_lpm": 0.0, "hot_lpm": 0.0, "gas_kw": 0.0, "fittings": {}}
	var size: Array = kit.get("size", [0, 0])
	out["size"] = Vector3(float(size[0]), float(kit.get("level_height", 3.0)), float(size[1]))
	var s := KitCapture.summary(kit, catalog)
	out["area"] = s.area
	out["parts"] = s.parts
	out["fittings"] = s.fittings
	for row: Dictionary in kit.get("parts", []):
		var d: Dictionary = DEMAND.get(str(row.entry.get("kind", "")), {})
		for k: String in ["power_w", "cold_lpm", "hot_lpm", "gas_kw"]:
			out[k] = float(out[k]) + float(d.get(k, 0.0))
	var room: Dictionary = kit.get("room", {})
	out["room_type"] = str(room.get("type", ""))
	out["group"] = str(kit.get("group", ""))
	out["author"] = str(kit.get("author", ""))
	return out


## A room type's brief figures: label, category, min_area and what it must have.
static func for_room_type(catalog: BuildingCatalog, type: String) -> Dictionary:
	var rt := catalog.room_type(type)
	if rt.is_empty():
		return {}
	var out := rt.duplicate(true)
	out["label"] = str(rt.get("label", type))
	out["family"] = "room"
	return out


## Text lines for a figures dictionary: [[name, value], ...] in the preview's order.
static func lines(s: Dictionary) -> Array:
	var out: Array = []
	if s.is_empty():
		return out
	var size: Variant = s.get("size")
	if size is Vector3 and (size as Vector3).length() > 0.0:
		var v := size as Vector3
		out.append(["Size", "%s W × %s D × %s H m" % [_m(v.x), _m(v.z), _m(v.y)]])
	if s.has("area"):
		out.append(["Floor area", "%.1f m²" % float(s.area)])
	if s.has("min_area"):
		out.append(["Smallest", "%.1f m²" % float(s.min_area)])
	if float(s.get("mass", 0.0)) > 0.0:
		var kg := float(s.mass)
		out.append(["Weight", "%.1f t" % (kg / 1000.0) if kg >= 1000.0 else "%d kg" % int(round(kg))])
	if float(s.get("cost", 0.0)) > 0.0:
		out.append(["Cost", "%s%s" % ["£" if str(s.get("currency", "GBP")) == "GBP" else str(s.currency) + " ", _money(float(s.cost))]])
	if s.has("power_w"):
		var w := float(s.power_w)
		out.append(["Power", "none" if w <= 0.0 else ("%.1f kW" % (w / 1000.0) if w >= 1000.0 else "%d W" % int(w))])
	if s.has("cold_lpm"):
		var c := float(s.cold_lpm)
		var h := float(s.get("hot_lpm", 0.0))
		out.append(["Water", "none" if c + h <= 0.0 else "cold %.1f l/min%s" % [c, ", hot %.1f l/min" % h if h > 0.0 else ""]])
	if str(s.get("waste", "")) != "":
		out.append(["Waste", str(s.waste)])
	if float(s.get("gas_kw", 0.0)) > 0.0:
		out.append(["Gas", "%.0f kW" % float(s.gas_kw)])
	var cap: Variant = s.get("capacity", {})
	if cap is Dictionary and not (cap as Dictionary).is_empty():
		var bits: Array = []
		for k: String in cap:
			bits.append("%s %s" % [str(cap[k]), k.replace("_", " ")])
		out.append(["Serves", ", ".join(bits)])
	if s.has("parts"):
		out.append(["Parts", str(s.parts)])
	var fit: Variant = s.get("fittings", {})
	if fit is Dictionary and not (fit as Dictionary).is_empty():
		var bits: Array = []
		for k: String in fit:
			bits.append("%d %s" % [int(fit[k]), k.replace("_", " ")])
		out.append(["Fittings", ", ".join(bits)])
	if s.has("materials") and (s.materials as PackedStringArray).size() > 0:
		out.append(["Materials", ", ".join(s.materials)])
	if str(s.get("note", "")) != "":
		out.append(["Note", str(s.note)])
	return out


static func _priced(catalog: BuildingCatalog, kind: String, shape: String) -> Dictionary:
	var m := BuildingModel.new("", "preview", catalog)
	var op := {}
	match shape:
		"point":
			op = C.place_part(kind, 0, {"at": Vector3.ZERO, "rot": 0.0})
		"line":
			op = C.place_part(kind, 0, {"a": Vector3.ZERO, "b": Vector3(1, 0, 0)})
		"opening":
			var w := m.apply(C.place_part("wall_loadbearing", 0, {"a": Vector3.ZERO, "b": Vector3(6, 0, 0)}))
			if w.is_empty():
				return {}
			op = C.place_opening(kind, str(w.do.entry.id), 3.0)
		_:
			return {}
	var r := m.apply(op)
	if r.is_empty():
		return {}
	return BuildingQuantities.part(m, str(r.do.entry.id))


static func _m(m: float) -> String:
	return "%.2f" % m if m < 10.0 else "%.1f" % m


static func _money(v: float) -> String:
	var s := str(int(round(v)))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
