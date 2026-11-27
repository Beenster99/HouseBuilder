class_name ServicesConsultant
extends RefCounted
## The M&E consultant: designs the cheapest routes for wiring and piping through the
## building, from the consumer unit, water main, boiler and soil stack to every room and
## wet fixture, prices them, and checks that every room is powered and every wet room
## plumbed. Deterministic and headless; it only reads the BuildingModel.
##
##   var report := ServicesConsultant.route(model)                    # auto-placed sources
##   var report := ServicesConsultant.route(model, {"power": {"level": 0, "at": [1.0, 0.5]}})
##
## Sources, per system, first found wins:
##   1. a part of the source kind (consumer_unit, water_main, boiler, soil_stack) once the
##      building catalog has those kinds;
##   2. `sources[system]` = {level, at: [x, z]}, placed by the players through the bus;
##   3. auto: the consultant picks a spot (a plant room, utility room, garage or hallway,
##      by the front door for the consumer unit, on the street side for the water main,
##      under the WCs for the soil stack) and says so in the notes.
##
## What needs what (ServicesRates): every room gets a lighting and socket point; WCs,
## basins, baths, showers and each room's first kitchen unit (its sink) get cold water,
## waste and, except WCs, hot water; a wet room with no fixtures yet is routed to its centre;
## the boiler gets power and a cold feed. options: {cell: grid size in m (0.5)}.

const Rates := preload("res://modules/services/api/services_rates.gd")
const RouteGrid := preload("res://modules/services/internal/route_grid.gd")
const RouteSolver := preload("res://modules/services/internal/route_solver.gd")


static func route(model: BuildingModel, sources: Dictionary = {}, options: Dictionary = {}) -> ServicesReport:
	var rep := ServicesReport.new()
	rep.revision = model.revision
	var grid = RouteGrid.build(model, float(options.get("cell", 0.5)))
	rep.cell = grid.cell
	if grid.size() == 0 or model.rooms.is_empty():
		rep.summary = "Nothing to route yet: draw some rooms first."
		rep.notes.append(rep.summary)
		return rep
	var cat := model.catalog
	var room_ids := BuildingModel.sort_ids(model.rooms.keys())

	# Fixtures and the rooms they stand in.
	var fixtures: Array = []  # {id, kind, room, level, x, z, needs}
	var sink_taken := {}
	for pid in BuildingModel.sort_ids(model.parts.keys()):
		var e: Dictionary = model.parts[pid]
		var kind := str(e.kind)
		if cat.family_of(kind) != "fixture" or not Rates.FIXTURE_NEEDS.has(kind):
			continue
		var lv := int(e.level)
		var x := float(e.at[0])
		var z := float(e.at[2])
		var rid := _room_at(model, room_ids, lv, x, z)
		if kind == "kitchen_unit":
			if sink_taken.has(rid):
				continue
			sink_taken[rid] = true
		fixtures.append({"id": pid, "kind": kind, "room": rid, "level": lv, "x": x, "z": z,
			"needs": Rates.FIXTURE_NEEDS[kind]})

	# What each system must reach.
	var demands := {}  # system -> Array of {id, cell, room, what, wc?}
	for s in Rates.SYSTEMS:
		demands[s] = []
	var placed_fittings := _placed_fittings(model, room_ids)
	for rid in room_ids:
		var r: Dictionary = model.rooms[rid]
		for s: String in ["power", "lighting", "heating"]:
			if s == "heating" and not Rates.is_heated(str(r.type)):
				continue
			var at := fitting_spot(model, rid, s, placed_fittings)
			var c: int = grid.nearest(int(r.level), at.x, at.y, rid)
			if c < 0:
				c = _room_centre(grid, model, rid)
			var what: String = {"power": "Sockets", "lighting": "Lights", "heating": "Radiator"}[s]
			demands[s].append({"id": rid, "cell": c, "room": rid, "what": what, "at": [at.x, at.y],
				"level": int(r.level), "label": what.to_lower() + " in " + _room_name(model, rid)})
	for f: Dictionary in fixtures:
		var c: int = grid.nearest(f.level, f.x, f.z, f.room)
		if c < 0:
			c = grid.nearest(f.level, f.x, f.z)
		var what := str(cat.kind(f.kind).get("label", f.kind))
		if f.kind == "kitchen_unit":
			what = "Sink"
		var where := (" in " + _room_name(model, f.room)) if f.room != "" else " (%s, outside every room)" % f.id
		for s: String in f.needs:
			demands[s].append({"id": f.id, "cell": c, "room": f.room, "what": what, "label": what + where,
				"wc": f.kind == "wc", "level": f.level})
	for rid in room_ids:
		var r: Dictionary = model.rooms[rid]
		if not Rates.is_wet_room(str(r.type)):
			continue
		var need: Array = ["cold_water", "waste"]
		if bool(Rates.WET_ROOMS[str(r.type)].hot):
			need.append("hot_water")
		for s: String in need:
			var has := false
			for d: Dictionary in demands[s]:
				if d.room == rid:
					has = true
					break
			if not has:
				demands[s].append({"id": rid, "cell": _room_centre(grid, model, rid), "room": rid,
					"what": "Room centre", "label": "%s (no fixtures yet, so its centre)" % _room_name(model, rid)})

	# Sources.
	var src := {}
	for s in Rates.SYSTEMS:
		if Rates.shares(s) != s:
			continue
		var wanted: bool = not demands[s].is_empty()
		if s == "power":
			wanted = wanted or not demands.lighting.is_empty()
		if s == "hot_water":
			wanted = wanted or not demands.heating.is_empty()
		if wanted:
			src[s] = _source(model, grid, room_ids, s, sources, demands)
	for s in Rates.SYSTEMS:
		if Rates.shares(s) != s and src.has(Rates.shares(s)):
			src[s] = src[Rates.shares(s)]
	if src.has("hot_water"):
		var boiler_cell := int(src.hot_water.cell)
		var broom: String = grid.room_of(boiler_cell)
		var blabel := "the boiler" + ((" in " + _room_name(model, broom)) if broom != "" else "")
		demands.power.append({"id": "boiler", "cell": boiler_cell, "room": broom, "what": "Boiler", "label": blabel})
		demands.cold_water.append({"id": "boiler", "cell": boiler_cell, "room": broom, "what": "Boiler", "label": blabel})
		if not src.has("cold_water"):
			src["cold_water"] = _source(model, grid, room_ids, "cold_water", sources, demands)

	# Route.
	var holes_total := {}
	for s in Rates.SYSTEMS:
		if not src.has(s) or demands[s].is_empty():
			continue
		var groups: Array = []
		if s == "waste":
			var wcs: Array = demands[s].filter(func(d: Dictionary) -> bool: return bool(d.get("wc", false)))
			var rest: Array = demands[s].filter(func(d: Dictionary) -> bool: return not bool(d.get("wc", false)))
			for g: Array in [wcs, rest]:
				if not g.is_empty():
					groups.append(g)
		else:
			groups.append(demands[s])
		var solver = RouteSolver.new(grid, s)
		solver.solve(int(src[s].cell), groups)
		rep.systems[s] = _system_result(model, grid, s, src[s], demands[s], solver)
		for k: String in rep.systems[s].holes:
			holes_total[k] = int(holes_total.get(k, 0)) + int(rep.systems[s].holes[k])
		rep.total_cost += float(rep.systems[s].cost)
	rep.total_cost = snappedf(rep.total_cost, 0.01)

	# Rooms.
	for rid in room_ids:
		var r: Dictionary = model.rooms[rid]
		var wet := Rates.is_wet_room(str(r.type))
		var missing: Array = []
		var served := {}  # system -> served for this room
		for s: String in rep.systems:
			for d: Dictionary in demands[s]:
				if d.room != rid or (s in ["power", "lighting", "heating"] and d.id != rid):
					continue
				var ok := _is_served(rep.systems[s], str(d.id))
				served[s] = bool(served.get(s, true)) and ok
		for s: String in ["power", "lighting"]:
			if not bool(served.get(s, false)):
				missing.append(s)
		var heated := Rates.is_heated(str(r.type))
		if heated and not bool(served.get("heating", false)):
			missing.append("heating")
		if wet:
			for s: String in ["cold_water", "hot_water", "waste"]:
				if s == "hot_water" and not bool(Rates.WET_ROOMS[str(r.type)].hot) and not served.has(s):
					continue
				if not bool(served.get(s, false)):
					missing.append(s)
		else:
			for s: String in ["cold_water", "hot_water", "waste"]:
				if served.has(s) and not bool(served[s]):
					missing.append(s)
		rep.rooms[rid] = {"name": _room_name(model, rid), "type": str(r.type), "level": int(r.level), "wet": wet,
			"powered": not "power" in missing and not "lighting" in missing,
			"heated": (not "heating" in missing) if heated else null,
			"plumbed": (not "cold_water" in missing and not "hot_water" in missing and not "waste" in missing) if wet else null,
			"missing": missing}

	_write_notes(rep, model, holes_total)
	return rep


## Where a room's socket, light or radiator goes, in plan (x, z): a fitting of that kind the
## players placed in the room, else the default spot (sockets near the -Z wall, the light in
## the middle, the radiator near the +Z wall). The same spot the designer puts a fitting on.
static func fitting_spot(model: BuildingModel, rid: String, system: String, placed: Dictionary = {}) -> Vector2:
	var key := "%s/%s" % [rid, system]
	if placed.has(key):
		return placed[key]
	var r: Dictionary = model.rooms[rid]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var sum := Vector2.ZERO
	for p: Array in r.outline:
		var v := Vector2(float(p[0]), float(p[1]))
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
		sum += v
	var mid := sum / float(r.outline.size())
	var inset := minf(0.3, (hi.y - lo.y) * 0.25)
	var spot := mid
	match system:
		"power":
			spot = Vector2(mid.x, lo.y + inset)
		"heating":
			spot = Vector2(mid.x, hi.y - inset)
	if not BuildingModel.outline_has_point(r.outline, spot.x, spot.y):
		spot = mid
	return Vector2(snappedf(spot.x, 0.01), snappedf(spot.y, 0.01))


## Sockets, lights and radiators already in the building: "room/system" -> plan point (the
## first by id in each room).
static func _placed_fittings(model: BuildingModel, room_ids: PackedStringArray) -> Dictionary:
	var out := {}
	var system_of := {}
	for s: String in Rates.FITTINGS:
		system_of[Rates.FITTINGS[s]] = s
	for pid in BuildingModel.sort_ids(model.parts.keys()):
		var e: Dictionary = model.parts[pid]
		if not system_of.has(str(e.kind)) or not e.has("at"):
			continue
		var rid := _room_at(model, room_ids, int(e.level), float(e.at[0]), float(e.at[2]))
		var key := "%s/%s" % [rid, system_of[str(e.kind)]]
		if rid != "" and not out.has(key):
			out[key] = Vector2(float(e.at[0]), float(e.at[2]))
	return out


static func _is_served(sys: Dictionary, id: String) -> bool:
	for b: Dictionary in sys.branches:
		if b.id == id:
			return true
	return false


static func _system_result(model: BuildingModel, grid: RefCounted, s: String, source: Dictionary, wanted: Array, solver: RefCounted) -> Dictionary:
	var spec: Dictionary = Rates.SYSTEM[s]
	var length := 0.0
	var run_cost := 0.0
	var hole_cost := 0.0
	var holes := {}
	for k: String in solver.edges:
		var e: Dictionary = solver.edges[k]
		length += float(e.length)
		run_cost += float(e.run_cost)
		hole_cost += float(e.hole_cost)
		for h: String in e.holes:
			holes[h] = int(holes.get(h, 0)) + 1
	var by_id := {}
	for d: Dictionary in wanted:
		by_id[str(d.id)] = d
	var branches: Array = []
	for b: Dictionary in solver.branches:
		var d: Dictionary = by_id[str(b.id)]
		branches.append({"id": str(b.id), "room": str(d.room), "what": str(d.what), "label": str(d.label), "at": d.get("at", []),
			"wc": bool(d.get("wc", false)), "level": int(d.get("level", -1)),
			"length": b.length, "cost": b.cost, "to_source": b.to_source, "points": b.points})
	var unserved: Array = []
	for u: Dictionary in solver.unserved:
		var d: Dictionary = by_id[str(u.id)]
		unserved.append({"id": str(u.id), "room": str(d.room), "what": str(d.what), "label": str(d.label)})
	var point_cost := float(spec.per_point) * branches.size()
	# A source placed as a building part is priced with the building, not again here.
	var source_cost := 0.0 if str(source.info.how) == "part" else float(spec.source_cost)
	var cost := run_cost + hole_cost + point_cost + source_cost
	return {"label": str(spec.label), "source": source.info, "length": snappedf(length, 0.001),
		"run_cost": snappedf(run_cost, 0.01), "hole_cost": snappedf(hole_cost, 0.01),
		"point_cost": snappedf(point_cost, 0.01), "source_cost": source_cost,
		"cost": snappedf(cost, 0.01), "holes": holes, "branches": branches, "unserved": unserved}


## {cell, info: {at, level, room, how, part?}}
static func _source(model: BuildingModel, grid: RefCounted, room_ids: PackedStringArray, s: String, placed: Dictionary, demands: Dictionary) -> Dictionary:
	var kind := str(Rates.SYSTEM[s].source_kind)
	var cat := model.catalog
	if cat.has_kind(kind):
		for pid in BuildingModel.sort_ids(model.parts.keys()):
			var e: Dictionary = model.parts[pid]
			if str(e.kind) == kind:
				var c: int = grid.nearest(int(e.level), float(e.at[0]), float(e.at[2]))
				if c >= 0:
					return _src(grid, c, "part", pid)
	if placed.has(s):
		var p: Dictionary = placed[s]
		var c: int = grid.nearest(int(p.get("level", 0)), float(p.at[0]), float(p.at[1]))
		if c >= 0:
			return _src(grid, c, "placed")
	return _src(grid, _auto_cell(model, grid, room_ids, s, demands), "auto")


static func _src(grid: RefCounted, c: int, how: String, part: String = "") -> Dictionary:
	var p: Vector3 = grid.centre(c)
	var info := {"at": [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)], "level": grid.level_of(c),
		"room": grid.room_of(c), "how": how}
	if part != "":
		info["part"] = part
	return {"cell": c, "info": info}


static func _auto_cell(model: BuildingModel, grid: RefCounted, room_ids: PackedStringArray, s: String, demands: Dictionary) -> int:
	if s == "waste":
		# Under the WCs (or every wet point), on the ground floor, so the stack runs straight down.
		var pts: Array = demands.waste.filter(func(d: Dictionary) -> bool: return bool(d.get("wc", false)))
		if pts.is_empty():
			pts = demands.waste
		var sum := Vector2.ZERO
		var n := 0
		for d: Dictionary in pts:
			if int(d.cell) >= 0:
				var c: Vector3 = grid.centre(int(d.cell))
				sum += Vector2(c.x, c.z)
				n += 1
		var at := sum / maxf(1.0, n)
		return grid.nearest(0, at.x, at.y)
	# A preferred room, lowest level first, then the room type order, then id.
	var best_room := ""
	var best_rank := 1 << 30
	var prefs: Array = Rates.AUTO_ROOMS[s]
	for rid in room_ids:
		var r: Dictionary = model.rooms[rid]
		var k := prefs.find(str(r.type))
		if k < 0 or grid.cells_of_room(rid).is_empty():
			continue
		var rank := int(r.level) * 100 + k
		if rank < best_rank:
			best_rank = rank
			best_room = rid
	var door := _front_door(model)
	if s == "power" and door != Vector3.INF:
		return grid.nearest(int(door.y), door.x, door.z, best_room)
	if s == "cold_water":
		# The street side: the lowest z of the chosen room (or the building).
		var lo := -1
		var cells: PackedInt32Array = grid.cells_of_room(best_room) if best_room != "" else PackedInt32Array()
		if cells.is_empty():
			for i in grid.nx * grid.nz:
				if grid.state[i] == grid.IN:
					cells.append(i)
		for c in cells:
			if lo < 0 or grid.centre(c).z < grid.centre(lo).z - 0.0001:
				lo = c
		return lo
	if best_room != "":
		return _room_centre(grid, model, best_room)
	if s == "hot_water" and not demands.hot_water.is_empty():
		return int(demands.hot_water[0].cell)
	if door != Vector3.INF:
		return grid.nearest(int(door.y), door.x, door.z)
	return grid.nearest(0, grid.ox, grid.oz)


## The first external door on the lowest level: Vector3(x, level, z), or Vector3.INF.
static func _front_door(model: BuildingModel) -> Vector3:
	var best := Vector3.INF
	for pid in BuildingModel.sort_ids(model.parts.keys()):
		var e: Dictionary = model.parts[pid]
		if str(e.kind) != "door_external":
			continue
		var pts := model.points_of(pid)
		if pts.size() < 2:
			continue
		var mid := (pts[0] + pts[1]) * 0.5
		var lv := model.level_of(pid)
		if best == Vector3.INF or lv < int(best.y):
			best = Vector3(mid.x, lv, mid.z)
	return best


static func _room_at(model: BuildingModel, room_ids: PackedStringArray, level: int, x: float, z: float) -> String:
	for rid in room_ids:
		var r: Dictionary = model.rooms[rid]
		if int(r.level) == level and BuildingModel.outline_has_point(r.outline, x, z):
			return rid
	return ""


static func _room_centre(grid: RefCounted, model: BuildingModel, rid: String) -> int:
	var r: Dictionary = model.rooms[rid]
	var sum := Vector2.ZERO
	for p: Array in r.outline:
		sum += Vector2(float(p[0]), float(p[1]))
	sum /= float(r.outline.size())
	var c: int = grid.nearest(int(r.level), sum.x, sum.y, rid)
	if c < 0:  # a lift shaft: served from the nearest cell beside it
		c = grid.nearest(int(r.level), sum.x, sum.y)
	return c


static func _room_name(model: BuildingModel, rid: String) -> String:
	var r: Dictionary = model.rooms[rid]
	var n := str(r.get("name", ""))
	if n == "":
		n = str(model.catalog.room_type(str(r.type)).get("label", r.type))
	return "%s (%s)" % [n, rid]


static func _money(v: float) -> String:
	var s := str(int(roundf(v)))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return "£" + s + out


static func _write_notes(rep: ServicesReport, model: BuildingModel, holes_total: Dictionary) -> void:
	for s in Rates.SYSTEMS:
		if not rep.systems.has(s):
			continue
		var sys: Dictionary = rep.systems[s]
		var spec: Dictionary = Rates.SYSTEM[s]
		var where := str(sys.source.room)
		var where_txt := ("in " + _room_name(model, where)) if where != "" else "on level %d" % int(sys.source.level)
		if sys.source.how == "auto" and Rates.shares(s) == s:
			rep.notes.append("No %s placed: the consultant put one %s." % [spec.source, where_txt])
		rep.notes.append("%s: %.1f m of %s from the %s %s to %d points, %s." % [spec.label, float(sys.length),
			spec.run, spec.source, where_txt, (sys.branches as Array).size(), _money(float(sys.cost))])
		for u: Dictionary in sys.unserved:
			var who := str(u.label)
			var why := "no way through: it is walled off (curtain walls or a lift shaft block it) or not connected to the rest of the building"
			if s == "waste":
				why = "the soil stack is not below it, and waste cannot run uphill; put a stack under it or move the room"
			rep.notes.append("%s: no %s reaches %s; %s." % [spec.label, spec.label.to_lower(), who, why])
		if s == "waste":
			# Fixtures upstairs drain to the stack; ground floor ones go straight to the drains.
			for b: Dictionary in sys.branches:
				if int(b.level) < 1:
					continue
				var limit := float(Rates.MAX_BRANCH.wc if bool(b.wc) else Rates.MAX_BRANCH.default)
				if float(b.to_source) > limit:
					var w := "%s runs %.1f m across the floor to the soil stack (more than %.0f m): add a stack nearer it or move it closer." % [
						b.label, float(b.to_source), limit]
					rep.warnings.append(w)
					rep.notes.append(w)
	var holes := PackedStringArray()
	for k: String in ["wall", "structural_wall", "floor", "riser_floor"]:
		if holes_total.has(k):
			holes.append("%d %s" % [holes_total[k], {"wall": "through partitions", "structural_wall": "through load-bearing walls",
				"floor": "through floors", "riser_floor": "through floors in risers"}[k]])
	if not holes.is_empty():
		rep.notes.append("Holes: " + ", ".join(holes) + ".")
	var bad := rep.failures()
	if bad.is_empty():
		rep.summary = "Every room is powered and every wet room plumbed: %s in total." % _money(rep.total_cost)
	else:
		var names := PackedStringArray()
		for rid: String in bad:
			var miss := PackedStringArray()
			for s: String in bad[rid]:
				miss.append(Rates.label(s).to_lower())
			names.append("%s (%s)" % [str(rep.rooms[rid].name), ", ".join(miss)])
		rep.summary = "%d room%s not served: %s." % [bad.size(), "" if bad.size() == 1 else "s", "; ".join(names)]
	rep.notes.insert(0, rep.summary)
