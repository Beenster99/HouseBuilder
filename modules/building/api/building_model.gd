class_name BuildingModel
extends RefCounted
## The building as data: levels, parts, connections and rooms. No nodes, no scenes: the
## design room, the structural solver, the timelapse, the cost panel and the network all
## read this one model, and scenes only draw it.
##
## It changes only through apply(op). An op is a plain Dictionary, so it can be sent over
## the network, logged and replayed. apply() returns {} when the op is refused (or does
## nothing), else {"do": op as applied, "undo": the op that reverses it}. "do" carries every
## id the model chose, so applying it to another copy of the model gives the same result:
## the host applies a request, then broadcasts "do" for clients to apply as is.
## BuildingHistory keeps the undo and redo stacks on top of this; BuildingCommands builds
## the ops.
##
## Space: metres, y up, -Z forward (Godot's convention). Level 0 is the ground floor, its
## floor at y = 0; level n's floor is at the sum of the heights below it. Every y in a part
## is relative to its level's floor.
##
## Entries (every entry has a unique "id"; ids never change and are not reused while the
## entry exists):
##   part:  {id, kind, material, section?, level, name?, ...shape fields}
##     shape "point"   (columns, pads, piles, fixtures, lifts): at = [x, y, z], rot (degrees
##                     about y), height? (columns; default the level's height), length? (piles,
##                     down), w? d? (a lift's shaft footprint), top_level? (a lift: the highest
##                     level it serves, above its own; default the next one up)
##     shape "line"    (beams, braces, trusses, walls, strip footings, stairs): a = [x, y, z],
##                     b = [x, y, z], height? (walls; default the level's height), w? (a
##                     stair's width). A stair runs from a (foot) to b (head, in plan: its y
##                     is set to a's) and always rises to the next level up.
##     shape "area"    (slabs, rafts, roofs): outline = [[x, z], ...] (3 or more, not
##                     self-checked for crossing), y (default 0), pitch? (pitched roofs, degrees)
##     shape "opening" (doors, windows): host = a wall part's id, t = distance of the
##                     opening's centre from the wall's a end, w? h? sill? (default from the
##                     catalog). No level of its own: it is on its wall's level.
##     section is present only for kinds that have sections in the catalog.
##     locked? true: the part is kept as it is (a frontage to keep, the existing house of an
##     extension). Only a set of "locked" itself changes it: no other set, move, retag or
##     remove, no opening added to a locked wall (unless the opening is locked too: part of
##     the same kept building) and no remove that would take it with it.
##   room:  {id, type, level, outline = [[x, z], ...], name, locked?}
##   connection: {id, a, b, kind, at?}   two part ids, a catalog connection kind and,
##                     optionally, where they meet: at = [x, y, z] in world space
##
## Ops:
##   {op = "add", table = "parts" | "rooms" | "connections", entry = {...}}   id optional
##   {op = "set", id, fields = {...}}   a null value removes an optional field
##   {op = "remove", id}  or  {op = "remove", ids = [...]}
##       a part takes its hosted openings and its connections with it; undo brings all back
##   {op = "move", ids = [...], by = [dx, dy, dz]}   parts and rooms; an opening slides
##       along its wall (unless its wall moves with it); rooms ignore dy
##   {op = "retag", id, type, name?}   a room's type, or a part's kind (same shape; the
##       material and section are kept where the new kind allows them)
##   {op = "add_level", index?, height?, name?}    inserted under index (default: on top)
##   {op = "set_level", index, fields = {height?, name?}}
##   {op = "remove_level", index}                  only an empty level, never the last one
##   {op = "set_meta", fields = {name?, ...}}      design metadata; null removes a key
##   {op = "batch", ops = [...]}   all or nothing, applied in order, undone in reverse
##
## Saved form (to_data / from_data, JSON-safe): {format, id, name, meta, levels, parts,
## rooms, connections, next}, entries sorted by id, so equal models give equal data.

## Emitted after every applied op, with the op as applied ("do"); {"op": "load"} on load_data.
signal changed(op: Dictionary)
## Per entry, after an applied op (one signal per entry it touched, in id order; a batch
## that adds then changes an entry gives just entry_added).
signal entry_added(id: String)
signal entry_changed(id: String)
signal entry_removed(id: String)
## A level was added, removed or changed (entries' level numbers may have shifted).
signal levels_changed
## The whole model was replaced (load_data, a join snapshot): rebuild every view.
signal loaded

const FORMAT := 1
const TABLES: PackedStringArray = ["parts", "rooms", "connections"]
const PREFIX := {"parts": "p", "rooms": "r", "connections": "c"}
const DEFAULT_LEVEL_HEIGHT := 3.0
const DEFAULT_GRID := 0.25
## Shortest line part and smallest area, m and m2.
const MIN_LENGTH := 0.05
const MIN_AREA := 0.01
## Shortest stair flight in plan, m.
const MIN_STAIR_RUN := 1.0
const EPS := 0.0001

var id := ""
var name := "New building"
## Free design metadata (grid, notes, brief id, site id...). JSON-safe values only.
var meta: Dictionary = {"grid": DEFAULT_GRID}
## [{height, name}], ground floor first.
var levels: Array = [{"height": DEFAULT_LEVEL_HEIGHT, "name": "Ground floor"}]
## id -> entry. Read them freely; never change them except through apply().
var parts: Dictionary = {}
var rooms: Dictionary = {}
var connections: Dictionary = {}
var catalog: BuildingCatalog
## Goes up by one on every applied op and every load: a cheap "has it changed" check.
var revision := 0
var _next := 1
## id -> whether it existed before the op being applied (for the entry signals).
var _touched: Dictionary = {}
var _levels_touched := false
## Indexes kept in step with the tables by _store, so lookups do not scan every part:
## wall id -> {opening id: true}; part id -> {connection id: true}; "a|b" -> connection id.
var _hosted: Dictionary = {}
var _conns: Dictionary = {}
var _pairs: Dictionary = {}
## Goes up on every change to an entry (including level shifts); the query caches below
## are good while it holds.
var _mut := 0
var _cache: Dictionary = {}
var _cache_mut := -1
## Results other classes work out per entry (BuildingQuantities' costs), by entry id, so an
## edit only redoes what it touched. An entry's result is dropped when it changes, a wall's
## when its openings change, and all of them on a level change or a load. Read it only
## through those classes.
var derived: Dictionary = {}
## level -> a count that goes up whenever a fixture on that level changes (a room's
## capacity depends on the fixtures standing in it).
var fixture_rev: Dictionary = {}


func _init(building_id: String = "", building_name: String = "New building", cat: BuildingCatalog = null) -> void:
	id = building_id
	name = building_name
	catalog = cat if cat != null else BuildingCatalog.default_catalog()


# Applying edits

## Applies an op. Returns {} if refused or a no-op, else {"do": op, "undo": op}.
func apply(op: Dictionary) -> Dictionary:
	_touched = {}
	_levels_touched = false
	var r := _apply(op)
	var touched := _touched
	_touched = {}
	if r.is_empty():
		return r
	revision += 1
	changed.emit(r.do)
	if _levels_touched:
		levels_changed.emit()
	for eid in sort_ids(touched.keys()):
		var was: bool = touched[eid]
		var now := has(eid)
		if was and now:
			entry_changed.emit(eid)
		elif now:
			entry_added.emit(eid)
		elif was:
			entry_removed.emit(eid)
	return r


func _touch(eid: String) -> void:
	if not _touched.has(eid):
		_touched[eid] = has(eid)


func _apply(op: Dictionary) -> Dictionary:
	match str(op.get("op", "")):
		"add":
			return _add(str(op.get("table", "")), op.get("entry", {}))
		"set":
			var f: Variant = op.get("fields", {})
			return _set_entry(str(op.get("id", "")), f if f is Dictionary else {})
		"remove":
			var ids: Array = op.get("ids", []) if op.has("ids") else [op.get("id", "")]
			return _remove(ids)
		"move":
			return _move(op.get("ids", []), op.get("by", []))
		"retag":
			return _retag(op)
		"add_level":
			return _add_level(op)
		"set_level":
			return _set_level(int(op.get("index", -1)), op.get("fields", {}))
		"remove_level":
			return _remove_level(int(op.get("index", -1)))
		"set_meta":
			return _set_meta(op.get("fields", {}))
		"batch":
			return _batch(op.get("ops", []))
	return {}


func _batch(ops: Variant) -> Dictionary:
	if not ops is Array:
		return {}
	var saved_next := _next
	var dos: Array = []
	var undos: Array = []
	for o: Variant in ops:
		var r := _apply(o) if o is Dictionary else {}
		if r.is_empty():
			for i in range(undos.size() - 1, -1, -1):
				_apply(undos[i])
			_next = saved_next
			return {}
		dos.append(r.do)
		undos.append(r.undo)
	if dos.is_empty():
		return {}
	undos.reverse()
	return {"do": {"op": "batch", "ops": dos}, "undo": {"op": "batch", "ops": undos}}


func _add(table_name: String, entry: Variant) -> Dictionary:
	if not table_name in TABLES or not entry is Dictionary:
		return {}
	var e: Dictionary = (entry as Dictionary).duplicate(true)
	var eid := str(e.get("id", ""))
	if eid == "":
		eid = "%s%d" % [PREFIX[table_name], _next]
		while has(eid):
			_next += 1
			eid = "%s%d" % [PREFIX[table_name], _next]
	elif has(eid):
		return {}
	e["id"] = eid
	var norm := _normalize(table_name, e)
	if norm.is_empty():
		return {}
	if norm.has("host") and is_locked(str(norm.host)) and not bool(norm.get("locked", false)):
		return {}
	if table_name == "connections" and _connection_between(str(norm.a), str(norm.b)) != "":
		return {}
	_touch(eid)
	_store(table_name, eid, norm)
	var n := eid.substr(1).to_int() if eid.length() > 1 and eid.substr(1).is_valid_int() else 0
	_next = maxi(_next, n + 1)
	return {"do": {"op": "add", "table": table_name, "entry": norm.duplicate(true)},
			"undo": {"op": "remove", "id": eid}}


func _set_entry(eid: String, fields: Dictionary) -> Dictionary:
	var table_name := table_of(eid)
	if table_name == "" or fields.is_empty():
		return {}
	var old: Dictionary = _table(table_name)[eid]
	if bool(old.get("locked", false)) and not (fields.size() == 1 and fields.has("locked")):
		return {}
	var merged := old.duplicate(true)
	for k: String in fields:
		if k == "id":
			continue
		if fields[k] == null:
			merged.erase(k)
		else:
			merged[k] = fields[k]
	var norm := _normalize(table_name, merged)
	if norm.is_empty() or norm == old:
		return {}
	if table_name == "connections" and _connection_between(str(norm.a), str(norm.b)) not in ["", eid]:
		return {}
	_touch(eid)
	_store(table_name, eid, norm)
	if table_name == "parts" and not _hosted_fit(eid):
		_store(table_name, eid, old)
		return {}
	var dfields := {}
	var ufields := {}
	for k: String in norm:
		if not old.has(k) or old[k] != norm[k]:
			dfields[k] = _copy(norm[k])
			ufields[k] = _copy(old.get(k))
	for k: String in old:
		if not norm.has(k):
			dfields[k] = null
			ufields[k] = _copy(old[k])
	return {"do": {"op": "set", "id": eid, "fields": dfields}, "undo": {"op": "set", "id": eid, "fields": ufields}}


func _remove(ids: Array) -> Dictionary:
	if ids.is_empty():
		return {}
	var wanted := PackedStringArray()
	for i: Variant in ids:
		var s := str(i)
		if not has(s):
			return {}
		if not s in wanted:
			wanted.append(s)
	# Everything that goes with them: openings in removed walls, then connections.
	var gone := {}
	for s in wanted:
		gone[s] = true
	for s in wanted:
		for oid: String in _hosted.get(s, {}):
			gone[oid] = true
	for gid: String in gone.keys():
		for cid: String in _conns.get(gid, {}):
			gone[cid] = true
	for gid: String in gone:
		if table_of(gid) != "connections" and is_locked(gid):
			return {}
	var restore: Array = []
	var gone_sorted := sort_ids(gone.keys())
	for group: int in 4:
		for gid: String in gone_sorted:
			var t := table_of(gid)
			var opening: bool = t == "parts" and parts[gid].has("host")
			var in_group: bool = (group == 0 and t == "parts" and not opening) or (group == 1 and opening) \
					or (group == 2 and t == "rooms") or (group == 3 and t == "connections")
			if in_group:
				restore.append({"op": "add", "table": t, "entry": _table(t)[gid].duplicate(true)})
	for gid: String in gone:
		_touch(gid)
		_store(table_of(gid), gid, null)
	var do := {"op": "remove", "id": wanted[0]} if wanted.size() == 1 else {"op": "remove", "ids": Array(wanted)}
	return {"do": do, "undo": restore[0] if restore.size() == 1 else {"op": "batch", "ops": restore}}


func _move(ids: Variant, by: Variant) -> Dictionary:
	var d := _vec(by, 3)
	if not ids is Array or (ids as Array).is_empty() or d.is_empty() or (absf(d[0]) < EPS and absf(d[1]) < EPS and absf(d[2]) < EPS):
		return {}
	var list := PackedStringArray()
	for i: Variant in ids:
		var s := str(i)
		if not s in list:
			list.append(s)
	var sets: Array = []
	for eid in list:
		var t := table_of(eid)
		if t == "" or t == "connections":
			return {}
		var e: Dictionary = _table(t)[eid]
		if t == "rooms":
			sets.append({"op": "set", "id": eid, "fields": {"outline": _shift_outline(e.outline, d)}})
			continue
		match catalog.shape_of(str(e.kind)):
			"point":
				sets.append({"op": "set", "id": eid, "fields": {"at": _add3(e.at, d)}})
			"line":
				sets.append({"op": "set", "id": eid, "fields": {"a": _add3(e.a, d), "b": _add3(e.b, d)}})
			"area":
				sets.append({"op": "set", "id": eid, "fields": {"outline": _shift_outline(e.outline, d), "y": float(e.y) + d[1]}})
			"opening":
				if str(e.host) in list:
					continue
				var host: Dictionary = parts[str(e.host)]
				var dir := (_v3(host.b) - _v3(host.a)).normalized()
				sets.append({"op": "set", "id": eid, "fields": {"t": float(e.t) + dir.dot(Vector3(d[0], d[1], d[2]))}})
	var r := _batch(sets)
	if r.is_empty():
		return {}
	return {"do": {"op": "move", "ids": Array(list), "by": d}, "undo": r.undo}


func _retag(op: Dictionary) -> Dictionary:
	var eid := str(op.get("id", ""))
	var type := str(op.get("type", ""))
	var t := table_of(eid)
	var fields := {}
	if op.has("name"):
		fields["name"] = str(op.name)
	if t == "rooms":
		if not catalog.has_room_type(type):
			return {}
		fields["type"] = type
	elif t == "parts":
		var e: Dictionary = parts[eid]
		if not catalog.has_kind(type) or catalog.shape_of(type) != catalog.shape_of(str(e.kind)):
			return {}
		if catalog.family_of(type) != "wall" and not openings_in(eid).is_empty():
			return {}
		fields["kind"] = type
		var mats := catalog.materials_for(type)
		var mat := str(e.material) if str(e.material) in mats else mats[0]
		fields["material"] = mat
		var secs := catalog.sections_for(type, mat)
		fields["section"] = null if secs.is_empty() else (str(e.get("section", "")) if str(e.get("section", "")) in secs else secs[0])
	else:
		return {}
	var r := _set_entry(eid, fields)
	if r.is_empty():
		return {}
	var do := {"op": "retag", "id": eid, "type": type}
	if op.has("name"):
		do["name"] = str(op.name)
	return {"do": do, "undo": r.undo}


func _add_level(op: Dictionary) -> Dictionary:
	var index := int(op.get("index", levels.size()))
	var height := float(op.get("height", DEFAULT_LEVEL_HEIGHT))
	if index < 0 or index > levels.size() or height < 1.0:
		return {}
	var lv := {"height": height, "name": str(op.get("name", ""))}
	levels.insert(index, lv)
	_levels_touched = true
	_drop_all_derived()
	for table: Dictionary in [parts, rooms]:
		for e: Dictionary in table.values():
			if e.has("level") and int(e.level) >= index:
				e["level"] = int(e.level) + 1
			if e.has("top_level") and int(e.top_level) >= index:
				e["top_level"] = int(e.top_level) + 1
	return {"do": {"op": "add_level", "index": index, "height": height, "name": lv.name},
			"undo": {"op": "remove_level", "index": index}}


func _remove_level(index: int) -> Dictionary:
	if index < 0 or index >= levels.size() or levels.size() == 1:
		return {}
	for table: Dictionary in [parts, rooms]:
		for e: Dictionary in table.values():
			if e.has("level") and int(e.level) == index:
				return {}
			# A lift's top floor, or the floor a top-floor stair climbs to, cannot go.
			if e.has("top_level") and int(e.top_level) == index:
				return {}
			if str(e.get("kind", "")) == "stair" and int(e.level) == index - 1 and index == levels.size() - 1:
				return {}
	var lv: Dictionary = levels[index]
	levels.remove_at(index)
	_levels_touched = true
	_drop_all_derived()
	for table: Dictionary in [parts, rooms]:
		for e: Dictionary in table.values():
			if e.has("level") and int(e.level) > index:
				e["level"] = int(e.level) - 1
			if e.has("top_level") and int(e.top_level) > index:
				e["top_level"] = int(e.top_level) - 1
	return {"do": {"op": "remove_level", "index": index},
			"undo": {"op": "add_level", "index": index, "height": float(lv.height), "name": str(lv.name)}}


func _set_level(index: int, fields: Variant) -> Dictionary:
	if index < 0 or index >= levels.size() or not fields is Dictionary:
		return {}
	var f: Dictionary = fields
	var old: Dictionary = levels[index]
	var lv := {"height": float(f.get("height", old.height)), "name": str(f.get("name", old.name))}
	if lv.height < 1.0 or lv == old:
		return {}
	levels[index] = lv
	_levels_touched = true
	_drop_all_derived()
	# Only walls with openings can stop fitting.
	for pid: String in _hosted:
		if int(parts[pid].get("level", -1)) == index and not _hosted_fit(pid):
			levels[index] = old
			return {}
	return {"do": {"op": "set_level", "index": index, "fields": lv.duplicate()},
			"undo": {"op": "set_level", "index": index, "fields": old.duplicate()}}


func _set_meta(fields: Variant) -> Dictionary:
	if not fields is Dictionary or (fields as Dictionary).is_empty():
		return {}
	var dfields := {}
	var ufields := {}
	for k: String in fields:
		var v: Variant = fields[k]
		var was: Variant = name if k == "name" else meta.get(k)
		if k == "name" and v == null:
			continue
		if v == was or not _json_safe(v):
			continue
		dfields[k] = _copy(v)
		ufields[k] = _copy(was)
	if dfields.is_empty():
		return {}
	for k: String in dfields:
		if k == "name":
			name = str(dfields[k])
		elif dfields[k] == null:
			meta.erase(k)
		else:
			meta[k] = _copy(dfields[k])
	return {"do": {"op": "set_meta", "fields": dfields}, "undo": {"op": "set_meta", "fields": ufields}}


# Checking entries

## The entry as stored ({} if it is invalid): numbers made floats, levels ints, unknown
## fields dropped, defaults filled in.
func _normalize(table_name: String, e: Dictionary) -> Dictionary:
	match table_name:
		"parts":
			return _norm_part(e)
		"rooms":
			return _norm_room(e)
		"connections":
			return _norm_connection(e)
	return {}


func _norm_part(e: Dictionary) -> Dictionary:
	var kind := str(e.get("kind", ""))
	var spec := catalog.kind(kind)
	if spec.is_empty():
		return {}
	var mats := catalog.materials_for(kind)
	var mat := str(e.get("material", mats[0]))
	if not mat in mats:
		return {}
	var out := {"id": str(e.id), "kind": kind, "material": mat}
	var secs := catalog.sections_for(kind, mat)
	if not secs.is_empty():
		var sec := str(e.get("section", secs[0]))
		if not sec in secs:
			return {}
		out["section"] = sec
	if str(e.get("name", "")) != "":
		out["name"] = str(e.name)
	if bool(e.get("locked", false)):
		out["locked"] = true
	var shape := str(spec.shape)
	if shape != "opening":
		var lv := _int(e.get("level", 0))
		if lv < 0 or lv >= levels.size():
			return {}
		out["level"] = lv
	match shape:
		"point":
			var at := _vec(e.get("at"), 3)
			if at.is_empty():
				return {}
			out["at"] = at
			out["rot"] = fposmod(float(e.get("rot", 0.0)), 360.0)
			for k: String in ["height", "length", "w", "d"]:
				if e.get(k) != null:
					if float(e[k]) <= EPS:
						return {}
					out[k] = float(e[k])
			if kind == "lift":
				var top := _int(e.get("top_level", int(out.level) + 1))
				if top <= int(out.level) or top >= levels.size():
					return {}
				out["top_level"] = top
		"line":
			var a := _vec(e.get("a"), 3)
			var b := _vec(e.get("b"), 3)
			if kind == "stair" and not b.is_empty() and not a.is_empty():
				b[1] = a[1]
				if int(out.level) + 1 >= levels.size() or Vector2(a[0], a[2]).distance_to(Vector2(b[0], b[2])) < MIN_STAIR_RUN:
					return {}
			if a.is_empty() or b.is_empty() or _v3(a).distance_to(_v3(b)) < MIN_LENGTH:
				return {}
			if e.get("w") != null:
				if float(e.w) <= EPS:
					return {}
				out["w"] = float(e.w)
			out["a"] = a
			out["b"] = b
			if e.get("height") != null:
				if float(e.height) <= EPS:
					return {}
				out["height"] = float(e.height)
		"area":
			var outline := _outline(e.get("outline"))
			if outline.is_empty():
				return {}
			out["outline"] = outline
			out["y"] = float(e.get("y", 0.0))
			if e.get("pitch") != null:
				if float(e.pitch) < 0.0 or float(e.pitch) >= 80.0:
					return {}
				out["pitch"] = float(e.pitch)
		"opening":
			var host := str(e.get("host", ""))
			if not parts.has(host) or catalog.family_of(str(parts[host].kind)) != "wall":
				return {}
			out["host"] = host
			out["t"] = float(e.get("t", 0.0))
			for k: String in ["w", "h", "sill"]:
				if e.get(k) != null:
					out[k] = float(e[k])
			if not _opening_fits(out):
				return {}
		_:
			return {}
	return out


func _norm_room(e: Dictionary) -> Dictionary:
	var type := str(e.get("type", ""))
	if not catalog.has_room_type(type):
		return {}
	var lv := _int(e.get("level", 0))
	var outline := _outline(e.get("outline"))
	if lv < 0 or lv >= levels.size() or outline.is_empty():
		return {}
	var room := {"id": str(e.id), "type": type, "level": lv, "outline": outline, "name": str(e.get("name", ""))}
	if bool(e.get("locked", false)):
		room["locked"] = true
	return room


func _norm_connection(e: Dictionary) -> Dictionary:
	var a := str(e.get("a", ""))
	var b := str(e.get("b", ""))
	var kind := str(e.get("kind", catalog.connection_kinds[0] if not catalog.connection_kinds.is_empty() else ""))
	if a == b or not parts.has(a) or not parts.has(b) or not kind in catalog.connection_kinds:
		return {}
	var out := {"id": str(e.id), "a": a, "b": b, "kind": kind}
	if e.get("at") != null:
		var at := _vec(e.at, 3)
		if at.is_empty():
			return {}
		out["at"] = at
	return out


## An opening's size and place inside its wall.
func _opening_fits(o: Dictionary) -> bool:
	var host: Dictionary = parts.get(str(o.host), {})
	if host.is_empty():
		return false
	var spec := catalog.kind(str(o.kind))
	var w := float(o.get("w", spec.get("w", 1.0)))
	var h := float(o.get("h", spec.get("h", 2.0)))
	var sill := float(o.get("sill", spec.get("sill", 0.0)))
	var length := _v3(host.a).distance_to(_v3(host.b))
	var t := float(o.t)
	return w > EPS and h > EPS and sill >= 0.0 and t - w * 0.5 >= -EPS and t + w * 0.5 <= length + EPS \
			and sill + h <= part_height(str(host.id)) + EPS


## The openings in a wall still fit it (true for anything that is not a wall).
func _hosted_fit(wall_id: String) -> bool:
	for oid in openings_in(wall_id):
		if not _opening_fits(parts[oid]):
			return false
	return true


func _connection_between(a: String, b: String) -> String:
	return str(_pairs.get(_pair_key(a, b), ""))


static func _pair_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


## Every write to a table goes through here (e null removes), keeping the indexes in step.
func _store(table_name: String, eid: String, e: Variant) -> void:
	var t := _table(table_name)
	var old: Dictionary = t.get(eid, {})
	if not old.is_empty():
		_index(table_name, eid, old, false)
		_drop_derived(table_name, eid, old)
	if e == null:
		t.erase(eid)
	else:
		t[eid] = e
		_index(table_name, eid, e, true)
		_drop_derived(table_name, eid, e)
	_mut += 1


func _drop_derived(table_name: String, eid: String, e: Dictionary) -> void:
	derived.erase(eid)
	if table_name != "parts":
		return
	if e.has("host"):
		derived.erase(str(e.host))
	elif catalog.family_of(str(e.get("kind", ""))) == "fixture":
		var lv := int(e.get("level", 0))
		fixture_rev[lv] = int(fixture_rev.get(lv, 0)) + 1


## Every derived result goes (levels shifted or changed height, or a load).
func _drop_all_derived() -> void:
	derived = {}
	for lv: int in fixture_rev:
		fixture_rev[lv] = int(fixture_rev[lv]) + 1
	_mut += 1


func _index(table_name: String, eid: String, e: Dictionary, on: bool) -> void:
	if table_name == "parts" and e.has("host"):
		_index_in(_hosted, str(e.host), eid, on)
	elif table_name == "connections":
		_index_in(_conns, str(e.a), eid, on)
		_index_in(_conns, str(e.b), eid, on)
		var k := _pair_key(str(e.a), str(e.b))
		if on:
			_pairs[k] = eid
		elif str(_pairs.get(k, "")) == eid:
			_pairs.erase(k)


static func _index_in(index: Dictionary, key: String, eid: String, on: bool) -> void:
	if on:
		if not index.has(key):
			index[key] = {}
		index[key][eid] = true
	elif index.has(key):
		var d: Dictionary = index[key]
		d.erase(eid)
		if d.is_empty():
			index.erase(key)


## A cached query result (key -> sorted ids), dropped on any change.
func _cached(key: String) -> Variant:
	if _cache_mut != _mut:
		_cache = {}
		_cache_mut = _mut
	return _cache.get(key)


# Reading the model

## A locked entry is kept as it is (see "locked?" above).
func is_locked(eid: String) -> bool:
	var t := table_of(eid)
	return t != "" and bool(_table(t)[eid].get("locked", false))


## Ids of every locked part and room, sorted.
func locked_ids() -> PackedStringArray:
	var out: Array = []
	for t: String in ["parts", "rooms"]:
		for eid: String in _table(t):
			if bool(_table(t)[eid].get("locked", false)):
				out.append(eid)
	return sort_ids(out)


func has(eid: String) -> bool:
	return parts.has(eid) or rooms.has(eid) or connections.has(eid)


## "parts", "rooms", "connections" or "" for an unknown id.
func table_of(eid: String) -> String:
	if parts.has(eid):
		return "parts"
	if rooms.has(eid):
		return "rooms"
	if connections.has(eid):
		return "connections"
	return ""


## The stored entry ({} if unknown). Read only: change it through apply().
func entry(eid: String) -> Dictionary:
	var t := table_of(eid)
	return {} if t == "" else _table(t)[eid]


func level_count() -> int:
	return levels.size()


func level_height(index: int) -> float:
	return float(levels[index].height) if index >= 0 and index < levels.size() else DEFAULT_LEVEL_HEIGHT


## World y of a level's floor.
func level_elevation(index: int) -> float:
	var y := 0.0
	for i in clampi(index, 0, levels.size()):
		y += float(levels[i].height)
	return y


## A part's or room's level (an opening's is its wall's); -1 for anything else.
func level_of(eid: String) -> int:
	var e := entry(eid)
	if e.has("host"):
		return level_of(str(e.host))
	return int(e.get("level", -1))


## Part ids on a level, sorted (openings count on their wall's level).
func parts_on(index: int) -> PackedStringArray:
	var key := "on:%d" % index
	var hit: Variant = _cached(key)
	if hit != null:
		return hit
	var out: Array = []
	for pid: String in parts:
		if level_of(pid) == index:
			out.append(pid)
	var ids := sort_ids(out)
	_cache[key] = ids
	return ids


func rooms_on(index: int) -> PackedStringArray:
	var key := "rooms_on:%d" % index
	var hit: Variant = _cached(key)
	if hit != null:
		return hit
	var out: Array = []
	for rid: String in rooms:
		if int(rooms[rid].level) == index:
			out.append(rid)
	var ids := sort_ids(out)
	_cache[key] = ids
	return ids


## Part ids of one catalog family ("beam", "wall"...), sorted.
func parts_of_family(family: String) -> PackedStringArray:
	var key := "family:" + family
	var hit: Variant = _cached(key)
	if hit != null:
		return hit
	var out: Array = []
	for pid: String in parts:
		if catalog.family_of(str(parts[pid].kind)) == family:
			out.append(pid)
	var ids := sort_ids(out)
	_cache[key] = ids
	return ids


## Opening ids in a wall, sorted.
func openings_in(wall_id: String) -> PackedStringArray:
	var d: Dictionary = _hosted.get(wall_id, {})
	return PackedStringArray() if d.is_empty() else sort_ids(d.keys())


## Connection ids touching a part, sorted.
func connections_of(part_id: String) -> PackedStringArray:
	var d: Dictionary = _conns.get(part_id, {})
	return PackedStringArray() if d.is_empty() else sort_ids(d.keys())


## The connection id between two parts, or "".
func connection_between(a: String, b: String) -> String:
	return _connection_between(a, b)


## A column's or wall's height: its own, else its level's. 0 for other parts.
func part_height(part_id: String) -> float:
	var e: Dictionary = parts.get(part_id, {})
	if e.is_empty():
		return 0.0
	if e.has("height"):
		return float(e.height)
	if str(e.kind) == "lift":
		var top := int(e.top_level)
		return level_elevation(top) + level_height(top) - level_elevation(int(e.level))
	if str(e.kind) == "stair":
		return level_height(int(e.level))
	var fam := catalog.family_of(str(e.kind))
	return level_height(level_of(part_id)) if fam in ["column", "wall"] else 0.0


## A part's key points in world space: a point part's base (and top, for a column; foot,
## for a pile), a line part's two ends, an area's corners, an opening's two bottom corners.
func points_of(part_id: String) -> PackedVector3Array:
	var e: Dictionary = parts.get(part_id, {})
	var out := PackedVector3Array()
	if e.is_empty():
		return out
	var up := Vector3(0, level_elevation(level_of(part_id)), 0)
	match catalog.shape_of(str(e.kind)):
		"point":
			var base := _v3(e.at) + up
			out.append(base)
			if catalog.family_of(str(e.kind)) == "column" or str(e.kind) == "lift":
				out.append(base + Vector3(0, part_height(part_id), 0))
			elif str(e.kind) == "pile":
				out.append(base - Vector3(0, float(e.get("length", catalog.kind("pile").get("length", 10.0))), 0))
		"line":
			out.append(_v3(e.a) + up)
			out.append(_v3(e.b) + up + (Vector3(0, part_height(part_id), 0) if str(e.kind) == "stair" else Vector3.ZERO))
		"area":
			for p: Array in e.outline:
				out.append(Vector3(float(p[0]), float(e.y), float(p[1])) + up)
		"opening":
			var host: Dictionary = parts[str(e.host)]
			var a := _v3(host.a)
			var dir := (_v3(host.b) - a).normalized()
			var w := float(e.get("w", catalog.kind(str(e.kind)).get("w", 1.0)))
			var sill := Vector3(0, float(e.get("sill", catalog.kind(str(e.kind)).get("sill", 0.0))), 0)
			out.append(a + dir * (float(e.t) - w * 0.5) + sill + up)
			out.append(a + dir * (float(e.t) + w * 0.5) + sill + up)
	return out


## A part's world-space box (rough for sloped parts): its points grown by its section,
## a wall or column by its height, a slab by its thickness (downwards from its y).
func aabb_of(part_id: String) -> AABB:
	var pts := points_of(part_id)
	if pts.is_empty():
		return AABB()
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	var e: Dictionary = parts[part_id]
	var spec := catalog.kind(str(e.kind))
	var sec := catalog.section(str(e.get("section", "")))
	var half := float(sec.get("w", sec.get("dia", sec.get("d", 0.0)))) * 0.5
	var fam := str(spec.get("family", ""))
	match str(spec.get("shape", "")):
		"point":
			if str(e.kind) == "lift":
				var fp := footprint(part_id)
				box = AABB(pts[0], Vector3.ZERO)
				for q: Array in fp:
					box = box.expand(Vector3(float(q[0]), pts[0].y, float(q[1])))
				box.size.y = part_height(part_id)
			elif fam == "fixture":
				# A fitting resized in place keeps its own w, d and height on the part.
				var r := maxf(float(e.get("w", spec.get("w", 0.5))), float(e.get("d", spec.get("d", 0.5)))) * 0.5
				box = box.grow(r)
				box.size.y = float(e.get("height", spec.get("h", 1.0)))
				box.position.y = pts[0].y
			else:
				box = box.grow(half)
				if str(sec.get("shape", "")) == "pad":
					box.position.y = pts[0].y - float(sec.get("d", 0.5))
					box.size.y = float(sec.get("d", 0.5))
		"line":
			if str(e.kind) == "stair":
				box = box.grow(stair_width(part_id) * 0.5)
				box.position.y = pts[0].y
				box.size.y = part_height(part_id)
			elif fam == "wall":
				box = box.grow(float(sec.get("d", 0.1)) * 0.5)
				box.position.y = minf(pts[0].y, pts[1].y)
				box.size.y = absf(pts[0].y - pts[1].y) + part_height(part_id)
			else:
				box = box.grow(maxf(half, float(sec.get("d", 0.0)) * 0.5))
		"area":
			var t := float(sec.get("d", 0.0))
			box.position.y -= t
			box.size.y += t
			var pitch := float(e.get("pitch", spec.get("pitch", 0.0)))
			if pitch > 0.0:
				box.size.y += minf(box.size.x, box.size.z) * 0.5 * tan(deg_to_rad(pitch))
		"opening":
			var h := float(e.get("h", spec.get("h", 2.0)))
			box.size.y += h
			box = box.grow(float(catalog.section(str(parts[str(e.host)].get("section", ""))).get("d", 0.1)) * 0.5)
	return box


## A stair's width, m (its own, else the catalog's).
func stair_width(part_id: String) -> float:
	var e: Dictionary = parts.get(part_id, {})
	return float(e.get("w", catalog.kind(str(e.get("kind", ""))).get("w", 1.0)))


## The plan outline a part stands on: a lift's shaft or a fixture's footprint (rotated
## about its point), a stair's flight. [] for other shapes.
func footprint(part_id: String) -> Array:
	var e: Dictionary = parts.get(part_id, {})
	if e.is_empty():
		return []
	var spec := catalog.kind(str(e.kind))
	match str(spec.get("shape", "")):
		"point":
			var hw := float(e.get("w", spec.get("w", 0.5))) * 0.5
			var hd := float(e.get("d", spec.get("d", 0.5))) * 0.5
			var c := Vector2(float(e.at[0]), float(e.at[2]))
			var out: Array = []
			for corner: Vector2 in [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd)]:
				var p := c + corner.rotated(-deg_to_rad(float(e.get("rot", 0.0))))
				out.append([p.x, p.y])
			return out
		"line":
			if str(e.kind) != "stair":
				return []
			var a := Vector2(float(e.a[0]), float(e.a[2]))
			var b := Vector2(float(e.b[0]), float(e.b[2]))
			var side := (b - a).normalized().orthogonal() * stair_width(part_id) * 0.5
			return [[(a + side).x, (a + side).y], [(b + side).x, (b + side).y], [(b - side).x, (b - side).y], [(a - side).x, (a - side).y]]
	return []


## Holes needed in the floor of a level: lift shafts passing up through it and stairs
## arriving from the level below. [{id (the part), outline: [[x, z], ...]}], sorted by id.
func voids_on(index: int) -> Array:
	var out: Array = []
	for pid in parts_of_family("circulation"):
		var e: Dictionary = parts[pid]
		var lv := int(e.level)
		var hole := (str(e.kind) == "lift" and lv < index and index <= int(e.top_level)) \
				or (str(e.kind) == "stair" and lv + 1 == index)
		if hole:
			out.append({"id": pid, "outline": footprint(pid)})
	return out


## Plan area of an outline [[x, z], ...], m2 (always positive).
static func outline_area(outline: Array) -> float:
	var s := 0.0
	var n := outline.size()
	for i in n:
		var p: Array = outline[i]
		var q: Array = outline[(i + 1) % n]
		s += float(p[0]) * float(q[1]) - float(q[0]) * float(p[1])
	return absf(s) * 0.5


## True if the plan point (x, z) is inside an outline.
static func outline_has_point(outline: Array, x: float, z: float) -> bool:
	var inside := false
	var n := outline.size()
	var j := n - 1
	for i in n:
		var pi_: Array = outline[i]
		var pj: Array = outline[j]
		var zi := float(pi_[1])
		var zj := float(pj[1])
		if (zi > z) != (zj > z):
			var xc := float(pj[0]) + (z - zj) / (zi - zj) * (float(pi_[0]) - float(pj[0]))
			if x < xc:
				inside = not inside
		j = i
	return inside


# Saving and loading

## The whole model as plain JSON-safe data, entries sorted by id.
func to_data() -> Dictionary:
	var out := {"format": FORMAT, "id": id, "name": name, "meta": meta.duplicate(true),
			"levels": levels.duplicate(true), "next": _next}
	for t in TABLES:
		var list: Array = []
		var table := _table(t)
		for eid in sort_ids(table.keys()):
			list.append(table[eid].duplicate(true))
		out[t] = list
	return out


## Replaces this model's contents with saved data (as from to_data, or the same after a
## JSON round trip). Entries that fail their checks are dropped and counted in the return
## value's "dropped". Returns {ok: bool, dropped: int}.
func load_data(data: Dictionary) -> Dictionary:
	if int(data.get("format", 0)) < 1 or int(data.get("format", 0)) > FORMAT:
		return {"ok": false, "dropped": 0}
	id = str(data.get("id", ""))
	name = str(data.get("name", "New building"))
	var m: Variant = data.get("meta", {})
	meta = (m as Dictionary).duplicate(true) if m is Dictionary else {}
	levels = []
	for lv: Variant in data.get("levels", []):
		if lv is Dictionary:
			levels.append({"height": maxf(float(lv.get("height", DEFAULT_LEVEL_HEIGHT)), 1.0), "name": str(lv.get("name", ""))})
	if levels.is_empty():
		levels = [{"height": DEFAULT_LEVEL_HEIGHT, "name": "Ground floor"}]
	parts = {}
	rooms = {}
	connections = {}
	_hosted = {}
	_conns = {}
	_pairs = {}
	_drop_all_derived()
	_next = 1
	var dropped := 0
	# Walls before the openings they host; parts before connections.
	var part_list: Array = data.get("parts", [])
	for pass_openings: bool in [false, true]:
		for e: Variant in part_list:
			if not e is Dictionary or (e as Dictionary).has("host") != pass_openings:
				continue
			if _load_entry("parts", e):
				continue
			dropped += 1
	for t: String in ["rooms", "connections"]:
		for e: Variant in data.get(t, []):
			if not (e is Dictionary and _load_entry(t, e)):
				dropped += 1
	_next = maxi(_next, _int(data.get("next", 1)))
	revision += 1
	changed.emit({"op": "load"})
	loaded.emit()
	return {"ok": true, "dropped": dropped}


func _load_entry(table_name: String, e: Dictionary) -> bool:
	var eid := str(e.get("id", ""))
	if eid == "" or has(eid):
		return false
	return not _add(table_name, e).is_empty()


## A new model from saved data (null if the data is not a building).
static func from_data(data: Dictionary, cat: BuildingCatalog = null) -> BuildingModel:
	var m := BuildingModel.new("", "", cat)
	return m if m.load_data(data).ok else null


## Saves as JSON text (full float precision, sorted keys). Returns the file error.
func save_file(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(to_json())
	f.close()
	return OK


## Loads a model saved with save_file (null if the file is missing or not a building).
static func load_file(path: String, cat: BuildingCatalog = null) -> BuildingModel:
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return from_data(parsed, cat) if parsed is Dictionary else null


func to_json() -> String:
	return JSON.stringify(to_data(), "\t", true, true)


## A hash of the whole model: two copies with the same checksum hold the same building.
## The network layer compares it to catch a desync.
func checksum() -> int:
	return JSON.stringify(to_data(), "", true, true).hash()


# Helpers

func _table(table_name: String) -> Dictionary:
	match table_name:
		"parts":
			return parts
		"rooms":
			return rooms
	return connections


## Ids sorted by prefix, then by number ("p2" before "p10").
static func sort_ids(ids: Array) -> PackedStringArray:
	# Fast path: ids that are a letter and a plain number sort natively as one integer each.
	var keys := PackedInt64Array()
	keys.resize(ids.size())
	var i := 0
	for v: Variant in ids:
		var s := str(v)
		var num := s.substr(1)
		if s.length() < 2 or s.length() > 13 or s.unicode_at(0) > 127 or not num.is_valid_int() or num.begins_with("0") or num.begins_with("-") or num.begins_with("+"):
			break
		keys[i] = s.unicode_at(0) * 10000000000000 + num.to_int()
		i += 1
	if i == ids.size():
		keys.sort()
		var out := PackedStringArray()
		out.resize(keys.size())
		for j in keys.size():
			var k := keys[j]
			out[j] = String.chr(k / 10000000000000) + str(k % 10000000000000)
		return out
	var list := ids.duplicate()
	list.sort_custom(func(a: Variant, b: Variant) -> bool:
		var sa := str(a)
		var sb := str(b)
		if sa.left(1) != sb.left(1):
			return sa < sb
		var na := sa.substr(1).to_int()
		var nb := sb.substr(1).to_int()
		return na < nb if na != nb else sa < sb)
	return PackedStringArray(list)


static func _int(v: Variant) -> int:
	return int(v) if (v is int or v is float) else (str(v).to_int() if str(v).is_valid_int() else -1)


## n floats from an array of numbers, or [] if it is not one.
static func _vec(v: Variant, n: int) -> Array:
	if not (v is Array or v is PackedFloat32Array or v is PackedFloat64Array):
		if v is Vector3 and n == 3:
			return [float(v.x), float(v.y), float(v.z)]
		if v is Vector2 and n == 2:
			return [float(v.x), float(v.y)]
		return []
	var a: Array = Array(v)
	if a.size() != n:
		return []
	var out: Array = []
	for x: Variant in a:
		if not (x is int or x is float) or is_nan(float(x)) or is_inf(float(x)):
			return []
		out.append(float(x))
	return out


static func _v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func _add3(a: Array, d: Array) -> Array:
	return [float(a[0]) + d[0], float(a[1]) + d[1], float(a[2]) + d[2]]


static func _shift_outline(outline: Array, d: Array) -> Array:
	var out: Array = []
	for p: Array in outline:
		out.append([float(p[0]) + d[0], float(p[1]) + d[2]])
	return out


## [[x, z], ...] with 3 or more points and some area, or [].
func _outline(v: Variant) -> Array:
	if not v is Array:
		return []
	var out: Array = []
	for p: Variant in v:
		var q := _vec(p, 2)
		if q.is_empty():
			return []
		out.append(q)
	if out.size() < 3 or outline_area(out) < MIN_AREA:
		return []
	return out


static func _copy(v: Variant) -> Variant:
	if v is Dictionary or v is Array:
		return v.duplicate(true)
	return v


static func _json_safe(v: Variant) -> bool:
	if v == null or v is bool or v is int or v is float or v is String:
		return true
	if v is Array:
		for x: Variant in v:
			if not _json_safe(x):
				return false
		return true
	if v is Dictionary:
		for k: Variant in v:
			if not k is String or not _json_safe(v[k]):
				return false
		return true
	return false
