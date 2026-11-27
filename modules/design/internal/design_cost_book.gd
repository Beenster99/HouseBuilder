class_name DesignCostBook
extends RefCounted
## The live cost panel's running book: each part's and room's cost kept from the last time it
## changed, so an edit re-costs only what it touched (the part; a wall when its openings
## change; the rooms on a level when its furniture moves) instead of the whole building.
## A load or a level change re-costs everything, a slice at a time (update(budget)).
##
##   var book := DesignCostBook.new(model)
##   book.update(4000)          # up to 4 ms of re-costing; true when the book is up to date
##   var s := book.summary()    # as DesignCosts.summary(model)

var model: BuildingModel
var _parts: Dictionary = {}  # id -> {cost, mass, fam, material, level, at (fixtures), kind}
var _rooms: Dictionary = {}  # id -> {area, fit_out, capacity, min_area, short, level, label, type}
var _stale: Dictionary = {}  # ids to cost again
var _host_of: Dictionary = {}  # opening id -> wall id
# Running sums, kept as records come and go (_add_part / _take_part).
var _structure := 0.0
var _by_family: Dictionary = {}
var _by_level: Dictionary = {}  # level -> structure cost
var _fam_count: Dictionary = {}
var _lv_count: Dictionary = {}  # level -> {parts, walls, slabs}
var _room_rows: Array = []  # the sorted room schedule, or [] to remake
var _rooms_dirty := true
var _queue: Array = []  # this pass's ids still to cost, popped from the back
var _fixtures: Dictionary = {}  # this pass's furniture by level (_index_fixtures)
## Bumped on every change; the panel redraws when it moves.
var revision := 0


func _init(m: BuildingModel) -> void:
	model = m
	model.entry_added.connect(_touch)
	model.entry_changed.connect(_touch)
	model.entry_removed.connect(_touch)
	model.loaded.connect(restart)
	model.levels_changed.connect(restart)
	restart()


func unbind() -> void:
	if model == null:
		return
	model.entry_added.disconnect(_touch)
	model.entry_changed.disconnect(_touch)
	model.entry_removed.disconnect(_touch)
	model.loaded.disconnect(restart)
	model.levels_changed.disconnect(restart)
	model = null


## Everything again (a load, a new level).
func restart() -> void:
	_parts.clear()
	_rooms.clear()
	_structure = 0.0
	_by_family.clear()
	_by_level.clear()
	_fam_count.clear()
	_lv_count.clear()
	_rooms_dirty = true
	_host_of.clear()
	_stale.clear()
	_queue.clear()
	_fixtures.clear()
	for id: String in model.parts:
		_stale[id] = true
		var host := str(model.parts[id].get("host", ""))
		if host != "":
			_host_of[id] = host
	for id: String in model.rooms:
		_stale[id] = true
	revision += 1


func _touch(id: String) -> void:
	_stale[id] = true
	revision += 1
	var e := model.entry(id)
	var old_host := str(_host_of.get(id, ""))
	var host := str(e.get("host", ""))
	if old_host != "":
		_stale[old_host] = true
	if host != "":
		_stale[host] = true
		_host_of[id] = host
	else:
		_host_of.erase(id)
	# Furniture counts towards the capacity of the rooms it stands in.
	var levels := {}
	var was: Dictionary = _parts.get(id, {})
	if str(was.get("fam", "")) == "fixture":
		levels[int(was.level)] = true
	if model.parts.has(id) and model.catalog.family_of(str(e.kind)) == "fixture":
		levels[int(e.level)] = true
	if not levels.is_empty():
		for rid: String in model.rooms:
			if levels.has(int(model.rooms[rid].level)):
				_stale[rid] = true


## True when nothing is waiting to be costed.
func is_current() -> bool:
	return _stale.is_empty()


## Re-costs what changed, for up to budget_usec microseconds (-1: all of it). Parts go before
## rooms, since a room's capacity counts the furniture in it. True when up to date.
func update(budget_usec: int = -1) -> bool:
	if _stale.is_empty():
		_queue.clear()
		_fixtures.clear()
		return true
	var t0 := Time.get_ticks_usec()
	if _queue.is_empty():
		# Rooms at the front, parts at the back: parts are popped (costed) first.
		var rooms: Array = []
		var parts: Array = []
		for id: String in _stale:
			if model.rooms.has(id) or (_rooms.has(id) and not model.parts.has(id)):
				rooms.append(id)
			else:
				parts.append(id)
		_queue = rooms + parts
		_fixtures.clear()
	while not _queue.is_empty():
		var id: String = _queue.pop_back()
		if not _stale.has(id):
			continue
		var is_room := model.rooms.has(id) or (_rooms.has(id) and not model.parts.has(id))
		_stale.erase(id)
		if is_room:
			_rooms.erase(id)
			_rooms_dirty = true
			if model.rooms.has(id):
				if _fixtures.is_empty():
					_fixtures = _index_fixtures()
				_rooms[id] = _cost_room(id, _fixtures)
		else:
			_take_part(id)
			if model.parts.has(id):
				_add_part(id, _cost_part(id))
		if budget_usec >= 0 and Time.get_ticks_usec() - t0 > budget_usec:
			break
	if _queue.is_empty():
		_fixtures.clear()
		# Anything touched meanwhile waits in _stale for the next pass.
	return _stale.is_empty()


## Furniture by level: level -> [[at, kind]] ({"": true} when there is none, so it is built once).
func _index_fixtures() -> Dictionary:
	var out := {"": true}
	for pid: String in _parts:
		var p: Dictionary = _parts[pid]
		if p.fam == "fixture":
			if not out.has(int(p.level)):
				out[int(p.level)] = []
			out[int(p.level)].append([p.at, p.kind])
	return out


## How far through re-costing a load is, 0 to 1.
func progress() -> float:
	var n := model.parts.size() + model.rooms.size()
	return 1.0 if n == 0 else clampf(1.0 - float(_stale.size()) / n, 0.0, 1.0)


func _add_part(id: String, p: Dictionary) -> void:
	_parts[id] = p
	_sum(p, 1.0)


func _take_part(id: String) -> void:
	if _parts.has(id):
		_sum(_parts[id], -1.0)
		_parts.erase(id)


func _sum(p: Dictionary, sgn: float) -> void:
	var c: float = float(p.cost) * sgn
	var fam: String = p.fam
	var l := int(p.level)
	var n := int(sgn)
	_structure += c
	_by_family[fam] = float(_by_family.get(fam, 0.0)) + c
	_by_level[l] = float(_by_level.get(l, 0.0)) + c
	_fam_count[fam] = int(_fam_count.get(fam, 0)) + n
	if not _lv_count.has(l):
		_lv_count[l] = {"parts": 0, "walls": 0, "slabs": 0}
	_lv_count[l].parts += n
	if fam == "wall":
		_lv_count[l].walls += n
	elif fam == "slab":
		_lv_count[l].slabs += n


func _cost_part(id: String) -> Dictionary:
	var e: Dictionary = model.parts[id]
	var q := BuildingQuantities.part(model, id)
	var fam := model.catalog.family_of(str(e.kind))
	var rec := {"cost": float(q.cost), "mass": float(q.mass), "fam": fam, "material": str(e.material),
			"level": model.level_of(id), "kind": str(e.kind), "qty": float(q.quantity), "unit": str(q.unit)}
	if fam == "fixture":
		rec["at"] = Vector2(float(e.at[0]), float(e.at[2]))
	return rec


func _cost_room(id: String, fixtures: Dictionary) -> Dictionary:
	var e: Dictionary = model.rooms[id]
	var rt := model.catalog.room_type(str(e.type))
	var area := BuildingModel.outline_area(e.outline)
	var key := str(rt.get("capacity", ""))
	var lv := int(e.level)
	var cap := 0
	if key != "":
		for f: Array in fixtures.get(lv, []):
			var at: Vector2 = f[0]
			if BuildingModel.outline_has_point(e.outline, at.x, at.y):
				cap += int((model.catalog.kind(str(f[1])).get("capacity", {}) as Dictionary).get(key, 0))
	var per := float(rt.get("area_per_person", 0.0))
	if cap == 0 and per > 0.0:
		cap = floori(area / per)
	var min_area := float(rt.get("min_area", 0.0))
	var label := str(e.get("name", ""))
	if label == "":
		label = str(rt.get("label", e.type))
	return {"area": area, "fit_out": area * float(rt.get("fit_out", 0.0)), "capacity": cap, "min_area": min_area,
			"short": area + BuildingModel.EPS < min_area, "level": lv, "label": label, "type": str(e.type)}


## The panel's content, from the book as it stands (call update() first), in the shape
## DesignCosts.summary() gives.
func summary() -> Dictionary:
	if _rooms_dirty:
		_rooms_dirty = false
		_room_rows = []
		for rid in BuildingModel.sort_ids(_rooms.keys()):
			var r: Dictionary = _rooms[rid]
			_room_rows.append({"id": rid, "label": r.label, "type": r.type, "level": int(r.level), "area": float(r.area),
					"min_area": float(r.min_area), "short": bool(r.short), "capacity": int(r.capacity),
					"fit_out": float(r.fit_out)})
	var by_level := _by_level.duplicate()
	var fit_out := 0.0
	var floor_area := 0.0
	var per_level: Array = []
	for i in model.level_count():
		var c: Dictionary = _lv_count.get(i, {"parts": 0, "walls": 0, "slabs": 0})
		per_level.append({"parts": int(c.parts), "walls": int(c.walls), "slabs": int(c.slabs), "rooms": 0})
	for r: Dictionary in _room_rows:
		fit_out += float(r.fit_out)
		floor_area += float(r.area)
		by_level[int(r.level)] = float(by_level.get(int(r.level), 0.0)) + float(r.fit_out)
		if int(r.level) >= 0 and int(r.level) < per_level.size():
			per_level[int(r.level)].rooms += 1
	var fams: Array = []
	for fam: String in model.catalog.families:
		var cost := float(_by_family.get(fam, 0.0))
		if cost > 0.005:
			fams.append({"label": DesignCosts.FAMILY_LABELS.get(fam, fam.capitalize()), "cost": cost})
	if fit_out > 0.0:
		fams.append({"label": "Room fit-out", "cost": fit_out})
	var lvls: Array = []
	for i in model.level_count():
		lvls.append({"label": str(model.levels[i].get("name", "Level %d" % i)), "cost": float(by_level.get(i, 0.0))})
	var fam_count := {}
	for f: String in _fam_count:
		if int(_fam_count[f]) > 0:
			fam_count[f] = int(_fam_count[f])
	return {"total": _structure + fit_out, "structure": _structure, "fit_out": fit_out, "floor_area": floor_area,
			"currency": str(model.catalog.currency), "families": fams, "levels": lvls, "rooms": _room_rows,
			"notes": DesignCosts.notes_from(model, _room_rows, per_level, fam_count), "current": is_current(),
			"progress": progress()}


## The bill of materials: one row per kind and material, most expensive first:
## [{kind, material, label, count, qty, unit, cost, fam}].
func bill() -> Array:
	var rows := {}
	for pid: String in _parts:
		var p: Dictionary = _parts[pid]
		var key := "%s|%s" % [p.kind, p.material]
		if not rows.has(key):
			var label := str(model.catalog.kind(str(p.kind)).get("label", p.kind))
			var mat := str(model.catalog.material(str(p.material)).get("label", p.material))
			rows[key] = {"kind": p.kind, "material": p.material, "label": label, "material_label": mat,
					"count": 0, "qty": 0.0, "unit": p.unit, "cost": 0.0, "fam": p.fam}
		var r: Dictionary = rows[key]
		r.count += 1
		r.qty += float(p.get("qty", 0.0))
		r.cost += float(p.cost)
	var out: Array = rows.values()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.cost) > float(b.cost))
	return out
