class_name BuildingQuantities
extends RefCounted
## Quantities and costs of a BuildingModel, priced from its catalog: what the live cost
## panel and the quantity surveyor's view show. Pure functions, cheap enough to run after
## every edit for a house; cache by model.revision for big buildings.
##
##   var q := BuildingQuantities.part(model, "p4")
##   # {length, area, volume, mass, unit, rate, quantity, cost}
##   var r := BuildingQuantities.room(model, "r2")   # {area, fit_out, capacity, ...}
##   var t := BuildingQuantities.totals(model)
##   # {cost, structure, fit_out, mass, by_family: {beam: cost...}, by_material, by_level}
##
## length m, area m2, volume m3, mass kg, cost in catalog.currency.


## One part. Every key is present (0.0 where it does not apply).
static func part(model: BuildingModel, part_id: String) -> Dictionary:
	var out := {"length": 0.0, "area": 0.0, "volume": 0.0, "mass": 0.0, "unit": "", "rate": 0.0, "quantity": 0.0, "cost": 0.0}
	var e: Dictionary = model.parts.get(part_id, {})
	if e.is_empty():
		return out
	var cat := model.catalog
	var kind := str(e.kind)
	var spec := cat.kind(kind)
	var fam := str(spec.get("family", ""))
	var sec := cat.section(str(e.get("section", "")))
	var mat := cat.material(str(e.material))
	var sec_area := float(sec.get("area", 0.0))
	var thick := float(sec.get("d", 0.0))
	match str(spec.get("shape", "")):
		"point":
			if fam == "column":
				out.length = model.part_height(part_id)
				out.volume = sec_area * out.length
			elif kind == "pile":
				out.length = float(e.get("length", spec.get("length", 10.0)))
				out.volume = sec_area * out.length
			elif str(sec.get("shape", "")) == "pad":
				out.area = float(sec.w) * float(sec.w)
				out.volume = out.area * thick
		"line":
			out.length = BuildingModel._v3(e.a).distance_to(BuildingModel._v3(e.b))
			if fam == "wall":
				var gross: float = float(out.length) * model.part_height(part_id)
				var holes := 0.0
				for oid in model.openings_in(part_id):
					var o: Dictionary = model.parts[oid]
					var os := cat.kind(str(o.kind))
					holes += float(o.get("w", os.get("w", 0.0))) * float(o.get("h", os.get("h", 0.0)))
				out.area = maxf(gross - holes, 0.0)
				out.volume = out.area * thick
			else:
				out.volume = sec_area * out.length
		"area":
			var plan := BuildingModel.outline_area(e.outline)
			var pitch := float(e.get("pitch", spec.get("pitch", 0.0)))
			out.area = plan / cos(deg_to_rad(pitch)) if pitch > 0.0 else plan
			out.volume = plan * thick
	if sec.has("kg_m"):
		out.mass = float(sec.kg_m) * out.length
	else:
		out.mass = out.volume * float(mat.get("density", 0.0))
	var r := cat.rate(kind, str(e.material), str(e.get("section", "")))
	if not r.is_empty():
		out.unit = r.unit
		out.rate = r.rate
		match str(r.unit):
			"m3":
				out.quantity = out.volume
			"m2":
				out.quantity = out.area
			"m":
				out.quantity = out.length
			"t":
				out.quantity = out.mass / 1000.0
			_:
				out.quantity = 1.0
		out.cost = out.quantity * out.rate
	return out


## One room: {area, fit_out (cost), capacity (from fixtures standing in it, else from its
## area), fixtures: [part ids], min_area, short (area below the type's minimum)}.
static func room(model: BuildingModel, room_id: String) -> Dictionary:
	var e: Dictionary = model.rooms.get(room_id, {})
	if e.is_empty():
		return {"area": 0.0, "fit_out": 0.0, "capacity": 0, "fixtures": PackedStringArray(), "min_area": 0.0, "short": false}
	var rt := model.catalog.room_type(str(e.type))
	var area := BuildingModel.outline_area(e.outline)
	var key := str(rt.get("capacity", ""))
	var fixtures := fixtures_in(model, room_id)
	var cap := 0
	if key != "":
		for fid in fixtures:
			cap += int((model.catalog.kind(str(model.parts[fid].kind)).get("capacity", {}) as Dictionary).get(key, 0))
	var per := float(rt.get("area_per_person", 0.0))
	if cap == 0 and per > 0.0:
		cap = floori(area / per)
	var min_area := float(rt.get("min_area", 0.0))
	return {"area": area, "fit_out": area * float(rt.get("fit_out", 0.0)), "capacity": cap,
			"fixtures": fixtures, "min_area": min_area, "short": area + BuildingModel.EPS < min_area}


## Fixture part ids standing inside a room's outline on its level, sorted.
static func fixtures_in(model: BuildingModel, room_id: String) -> PackedStringArray:
	var e: Dictionary = model.rooms.get(room_id, {})
	var out: Array = []
	if e.is_empty():
		return PackedStringArray()
	for pid in model.parts_of_family("fixture"):
		var p: Dictionary = model.parts[pid]
		if int(p.level) == int(e.level) and BuildingModel.outline_has_point(e.outline, float(p.at[0]), float(p.at[2])):
			out.append(pid)
	return BuildingModel.sort_ids(out)


## The whole building. cost = structure (every part) + fit_out (every room).
static func totals(model: BuildingModel) -> Dictionary:
	var out := {"cost": 0.0, "structure": 0.0, "fit_out": 0.0, "mass": 0.0, "floor_area": 0.0,
			"by_family": {}, "by_material": {}, "by_level": {}, "currency": model.catalog.currency}
	for pid in BuildingModel.sort_ids(model.parts.keys()):
		var q := part(model, pid)
		var e: Dictionary = model.parts[pid]
		var fam := model.catalog.family_of(str(e.kind))
		var lv := str(model.level_of(pid))
		out.structure += q.cost
		out.mass += q.mass
		out.by_family[fam] = float(out.by_family.get(fam, 0.0)) + q.cost
		out.by_material[str(e.material)] = float(out.by_material.get(str(e.material), 0.0)) + q.cost
		out.by_level[lv] = float(out.by_level.get(lv, 0.0)) + q.cost
	for rid in BuildingModel.sort_ids(model.rooms.keys()):
		var r := room(model, rid)
		var lv := str(model.rooms[rid].level)
		out.fit_out += r.fit_out
		out.floor_area += r.area
		out.by_level[lv] = float(out.by_level.get(lv, 0.0)) + r.fit_out
	out.cost = out.structure + out.fit_out
	return out
