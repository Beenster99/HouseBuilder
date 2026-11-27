class_name BuildingQuantities
extends RefCounted
## Quantities and costs of a BuildingModel, priced from its catalog: what the live cost
## panel and the quantity surveyor's view show. totals() keeps each part's and room's
## result on the model (model.derived) and redoes only what an edit touched, so it can run
## after every edit even on an airport terminal (about 50 ms the first time, a few ms after).
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
	var e: Dictionary = model.parts.get(part_id, {})
	if e.is_empty():
		return {"length": 0.0, "area": 0.0, "volume": 0.0, "mass": 0.0, "unit": "", "rate": 0.0, "quantity": 0.0, "cost": 0.0}
	return _part(model, part_id, e, model.catalog.kind(str(e.kind)))


static func _part(model: BuildingModel, part_id: String, e: Dictionary, spec: Dictionary) -> Dictionary:
	var cat := model.catalog
	var kind: String = e.kind
	var fam: String = spec.get("family", "")
	var shape: String = spec.get("shape", "")
	var sec_id: String = e.get("section", "")
	var sec := cat.section(sec_id) if sec_id != "" else {}
	var material: String = e.material
	var sec_area := float(sec.get("area", 0.0))
	var thick := float(sec.get("d", 0.0))
	var length := 0.0
	var area := 0.0
	var volume := 0.0
	match shape:
		"point":
			if fam == "column":
				length = model.part_height(part_id)
				volume = sec_area * length
			elif kind == "pile":
				length = float(e.get("length", spec.get("length", 10.0)))
				volume = sec_area * length
			elif sec.get("shape", "") == "pad":
				area = float(sec.w) * float(sec.w)
				volume = area * thick
		"line":
			length = BuildingModel._v3(e.a).distance_to(BuildingModel._v3(e.b))
			if kind == "stair":
				volume = sec_area * length
				length = Vector2(float(e.a[0]) - float(e.b[0]), float(e.a[2]) - float(e.b[2])).length()
				area = BuildingModel.outline_area(model.footprint(part_id))
			elif fam == "wall":
				var gross := length * model.part_height(part_id)
				var holes := 0.0
				for oid in model.openings_in(part_id):
					var o: Dictionary = model.parts[oid]
					var os := cat.kind(str(o.kind))
					holes += float(o.get("w", os.get("w", 0.0))) * float(o.get("h", os.get("h", 0.0)))
				area = maxf(gross - holes, 0.0)
				volume = area * thick
			else:
				volume = sec_area * length
		"area":
			var plan := BuildingModel.outline_area(e.outline)
			var pitch := float(e.get("pitch", spec.get("pitch", 0.0)))
			area = plan / cos(deg_to_rad(pitch)) if pitch > 0.0 else plan
			volume = plan * thick
	var mass := 0.0
	var m: Variant = spec.get("mass")
	if m is Dictionary:
		mass = float((m as Dictionary).get(material, 0.0))
	elif sec.has("kg_m"):
		mass = float(sec.kg_m) * length
	elif volume != 0.0:
		mass = volume * float(cat.material(material).get("density", 0.0))
	var unit := ""
	var rate := 0.0
	var quantity := 0.0
	var cost := 0.0
	var r: Variant = sec.get("rate")
	if not r is Array:
		r = (spec.get("rates", {}) as Dictionary).get(material)
	if r is Array and (r as Array).size() >= 2:
		unit = str(r[0])
		rate = float(r[1])
		match unit:
			"m3":
				quantity = volume
			"m2":
				quantity = area
			"m":
				quantity = length
			"t":
				quantity = mass / 1000.0
			_:
				quantity = 1.0
		cost = quantity * rate
	var out := {"length": length, "area": area, "volume": volume, "mass": mass, "unit": unit, "rate": rate, "quantity": quantity, "cost": cost}
	if kind == "lift" and unit != "":
		out["stops"] = int(e.top_level) - int(e.level) + 1
		out.cost = cost + float(spec.get("per_stop", 0.0)) * int(out.stops)
	return out


## One room: {area, fit_out (cost), capacity (from fixtures standing in it, else from its
## area), fixtures: [part ids], min_area, short (area below the type's minimum)}.
static func room(model: BuildingModel, room_id: String) -> Dictionary:
	return _room(model, room_id, {})


static func _room(model: BuildingModel, room_id: String, buckets: Dictionary) -> Dictionary:
	var e: Dictionary = model.rooms.get(room_id, {})
	if e.is_empty():
		return {"area": 0.0, "fit_out": 0.0, "capacity": 0, "fixtures": PackedStringArray(), "min_area": 0.0, "short": false}
	var rt := model.catalog.room_type(str(e.type))
	var area := BuildingModel.outline_area(e.outline)
	var key := str(rt.get("capacity", ""))
	var found := _fixtures_at(model, e, buckets)
	var fixtures := PackedStringArray()
	var cap := 0
	for f: Array in found:
		fixtures.append(f[0])
		if key != "":
			cap += int((f[3] as Dictionary).get(key, 0))
	var per := float(rt.get("area_per_person", 0.0))
	if cap == 0 and per > 0.0:
		cap = floori(area / per)
	var min_area := float(rt.get("min_area", 0.0))
	return {"area": area, "fit_out": area * float(rt.get("fit_out", 0.0)), "capacity": cap,
			"fixtures": fixtures, "min_area": min_area, "short": area + BuildingModel.EPS < min_area}


## Fixture part ids standing inside a room's outline on its level, sorted.
static func fixtures_in(model: BuildingModel, room_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f: Array in _fixtures_at(model, model.rooms.get(room_id, {}), {}):
		out.append(f[0])
	return out


## Fixtures are bucketed by level and plan cell, this many metres square.
const CELL := 4.0


## The fixtures in a room entry, in id order: [[id, x, z, capacity dict], ...]. buckets:
## Vector3i(level, cell x, cell z) -> those tuples in id order (filled here if empty).
static func _fixtures_at(model: BuildingModel, e: Dictionary, buckets: Dictionary) -> Array:
	var out: Array = []
	if e.is_empty():
		return out
	if buckets.is_empty():
		_fixture_buckets(model, buckets)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for pt: Variant in e.outline:
		var v := Vector2(float(pt[0]), float(pt[1]))
		lo = lo.min(v)
		hi = hi.max(v)
	var lv := int(e.level)
	var c0 := Vector2i(floori((lo.x - BuildingModel.EPS) / CELL), floori((lo.y - BuildingModel.EPS) / CELL))
	var c1 := Vector2i(floori((hi.x + BuildingModel.EPS) / CELL), floori((hi.y + BuildingModel.EPS) / CELL))
	var cells := 0
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var list: Array = buckets.get(Vector3i(lv, cx, cz), [])
			if list.is_empty():
				continue
			cells += 1
			for f: Array in list:
				var x: float = f[1]
				var z: float = f[2]
				if x >= lo.x and x <= hi.x and z >= lo.y and z <= hi.y and BuildingModel.outline_has_point(e.outline, x, z):
					out.append(f)
	if cells > 1 and out.size() > 1:
		var by_id := {}
		for f: Array in out:
			by_id[f[0]] = f
		out = []
		for fid in BuildingModel.sort_ids(by_id.keys()):
			out.append(by_id[fid])
	return out


static func _fixture_buckets(model: BuildingModel, buckets: Dictionary) -> void:
	buckets["_"] = true
	for pid in model.parts_of_family("fixture"):
		_bucket(buckets, pid, model.parts[pid], model.catalog.kind(str(model.parts[pid].kind)))


static func _bucket(buckets: Dictionary, pid: String, p: Dictionary, spec: Dictionary) -> void:
	var x := float(p.at[0])
	var z := float(p.at[2])
	var key := Vector3i(int(p.level), floori(x / CELL), floori(z / CELL))
	if not buckets.has(key):
		buckets[key] = []
	(buckets[key] as Array).append([pid, x, z, spec.get("capacity", {})])


## The whole building. cost = structure (every part) + fit_out (every room).
static func totals(model: BuildingModel) -> Dictionary:
	var cat := model.catalog
	# Per-part and per-room results are kept on the model between calls (model.derived).
	var derived := model.derived
	if derived.get("_catalog") != cat:
		derived.clear()
		derived["_catalog"] = cat
	var last: Array = derived.get("_totals", [])
	if not last.is_empty() and int(last[0]) == model.revision:
		return (last[1] as Dictionary).duplicate(true)
	var by_family := {}
	var by_material := {}
	var by_level := {}
	var structure := 0.0
	var mass := 0.0
	var buckets := {"_": true}
	# A fixed-size point part (a fixture, a pad) costs the same wherever it stands.
	var same := {}
	for pid in BuildingModel.sort_ids(model.parts.keys()):
		var e: Dictionary = model.parts[pid]
		var kind := str(e.kind)
		var spec := cat.kind(kind)
		var fam := str(spec.get("family", ""))
		var q: Dictionary = derived.get(pid, {})
		if q.is_empty():
			if str(spec.get("shape", "")) == "point" and fam != "column" and kind != "pile" and kind != "lift":
				var key := "%s|%s|%s" % [kind, str(e.material), str(e.get("section", ""))]
				if not same.has(key):
					same[key] = _part(model, pid, e, spec)
				q = same[key]
			else:
				q = _part(model, pid, e, spec)
			derived[pid] = q
		var lv := str(e.level) if e.has("level") else str(model.level_of(pid))
		var mat := str(e.material)
		var cost: float = q.cost
		structure += cost
		mass += float(q.mass)
		by_family[fam] = float(by_family.get(fam, 0.0)) + cost
		by_material[mat] = float(by_material.get(mat, 0.0)) + cost
		by_level[lv] = float(by_level.get(lv, 0.0)) + cost
		if fam == "fixture":
			_bucket(buckets, pid, e, spec)
	var fit_out := 0.0
	var floor_area := 0.0
	for rid in BuildingModel.sort_ids(model.rooms.keys()):
		var room_e: Dictionary = model.rooms[rid]
		var rev := int(model.fixture_rev.get(int(room_e.level), 0))
		var hit: Array = derived.get(rid, [])
		var r: Dictionary
		if not hit.is_empty() and int(hit[0]) == rev:
			r = hit[1]
		else:
			r = _room(model, rid, buckets)
			derived[rid] = [rev, r]
		var lv := str(room_e.level)
		fit_out += float(r.fit_out)
		floor_area += float(r.area)
		by_level[lv] = float(by_level.get(lv, 0.0)) + float(r.fit_out)
	var out := {"cost": structure + fit_out, "structure": structure, "fit_out": fit_out, "mass": mass, "floor_area": floor_area,
			"by_family": by_family, "by_material": by_material, "by_level": by_level, "currency": cat.currency}
	derived["_totals"] = [model.revision, out.duplicate(true)]
	return out
