class_name ContractValidator
extends RefCounted
## Checks a building against a brief. The same result drives the live checklist in the
## design room, the pass or fail at handover and the payout, so they always agree.
##
##   var a := ContractValidator.assess(brief, model, structure_report)
##   a.ok                    # every hard requirement passes
##   a.items                 # [{id, kind, label, hard, ok, progress (0..1), detail, tip, bonus}]
##   a.cost, a.budget        # build cost from BuildingQuantities, the brief's budget
##   a.passed, a.total       # hard requirements passed / in all
##   a.bonus                 # bonuses earned by the goals met
##   a.summary               # one or two sentences: what is wrong and what to do first
##
## structure_report is what the structural stress test gives (structure module):
## StructureReport.brief_result(): {ok: bool, failures: [part ids], worst: utilisation,
## scenario: first failing case or ""}; leave it {} when the design has not been tested, or
## pass {"stale": true} when it changed since; a "structure" requirement then fails with a
## tip to run the test.
##
## Everything is worked out from the BuildingModel's data: rooms by type, level and outline,
## parts by kind, doors by where they sit. Distances are in plan, between room centres.

## Bedrooms this big or bigger count as doubles (England's space standard).
const DOUBLE_BEDROOM_M2 := 11.5
## Doors that count as a way out when they are in an outside wall on the ground floor.
const EXIT_DOORS: PackedStringArray = ["door_external", "door_double", "door_fire", "door_accessible", "door_vehicle"]
## Rooms that count as a way out on their own floor.
const EXIT_ROOMS: PackedStringArray = ["fire_exit", "stair_core"]
## Rooms the exit distance rule does not apply to (they are the way out).
const CIRCULATION: PackedStringArray = ["corridor", "hallway", "fire_exit", "stair_core", "lift_shaft"]


static func assess(brief: Dictionary, model: BuildingModel, structure_report: Dictionary = {}) -> Dictionary:
	var b := ContractBrief.normalize(brief)
	var totals := BuildingQuantities.totals(model)
	var ctx := {"brief": b, "model": model, "cat": model.catalog, "totals": totals, "report": structure_report}
	var items: Array = []
	var passed := 0
	var total := 0
	var bonus := 0.0
	for req: Dictionary in b.get("requirements", []):
		var item := check(req, ctx)
		item["hard"] = true
		item["bonus"] = 0.0
		items.append(item)
		total += 1
		if item.ok:
			passed += 1
	for req: Dictionary in b.get("goals", []):
		var item := check(req, ctx)
		item["hard"] = false
		item["bonus"] = float(req.get("bonus", 0.0))
		items.append(item)
		if item.ok:
			bonus += item.bonus
	var out := {"ok": passed == total, "items": items, "passed": passed, "total": total, "bonus": bonus,
			"cost": float(totals.cost), "budget": float(b.get("budget", 0.0)), "totals": totals}
	out["summary"] = _summary(out)
	return out


## One requirement: {id, kind, label, ok, progress, detail, tip}.
static func check(req: Dictionary, ctx: Dictionary) -> Dictionary:
	var model: BuildingModel = ctx.model
	var cat: BuildingCatalog = ctx.cat
	var out := {"id": str(req.get("id", "")), "kind": str(req.get("kind", "")), "label": ContractBrief.describe(req, cat),
			"ok": false, "progress": 0.0, "detail": "", "tip": ""}
	var v := float(req.get("value", 0.0))
	match out.kind:
		"rooms":
			_rooms(req, model, cat, out)
		"double_bedroom":
			var need := int(req.get("count", 1))
			var have := 0
			var biggest := 0.0
			for rid in _rooms_of(model, "bedroom"):
				var a := BuildingModel.outline_area(model.rooms[rid].outline)
				biggest = maxf(biggest, a)
				if a + BuildingModel.EPS >= DOUBLE_BEDROOM_M2:
					have += 1
			_count(out, have, need, "%d of %d double bedrooms." % [have, need],
					"The biggest bedroom is %.1f m2; a double needs %.1f m2. Make one bedroom bigger." % [biggest, DOUBLE_BEDROOM_M2])
		"capacity":
			var cap := 0
			for t: Variant in req.get("types", []):
				for rid in _rooms_of(model, str(t)):
					cap += int(BuildingQuantities.room(model, rid).capacity)
			_count(out, cap, int(v), "Room for %d of %d people." % [cap, int(v)],
					"Add rooms, make them bigger, or furnish them with seats, desks or beds.")
		"floor_area":
			var area := float(ctx.totals.floor_area)
			var lo := float(req.get("min", 0.0))
			var hi := float(req.get("max", INF))
			out.ok = area + BuildingModel.EPS >= lo and area <= hi + BuildingModel.EPS
			out.progress = 1.0 if out.ok else (clampf(area / lo, 0.0, 1.0) if area < lo else clampf(hi / area, 0.0, 1.0))
			out.detail = "%.0f m2 of rooms." % area
			if not out.ok:
				out.tip = "Add rooms or make them bigger." if area < lo else "Take out or shrink some rooms."
		"max_storeys":
			var used := _storeys_used(model)
			_limit(out, float(used), v, "%d storeys used." % used, "Bring everything down to %d storeys, or spread it out on the ground." % int(v))
		"max_height":
			var top := _top(model)
			_limit(out, top, v, "The highest point is %.1f m up." % top, "Lower the roof pitch, lose a storey, or make the storeys shorter.")
		"max_footprint":
			var foot := 0.0
			for rid in model.rooms_on(0):
				foot += BuildingModel.outline_area(model.rooms[rid].outline)
			_limit(out, foot, v, "The ground floor has %.0f m2 of rooms." % foot, "Move some rooms upstairs.")
		"within_plot":
			_within_plot(ctx, out)
		"materials":
			var allowed := PackedStringArray(req.get("allowed", []))
			var wrong := {}
			var n := 0
			for pid in BuildingModel.sort_ids(model.parts.keys()):
				var e: Dictionary = model.parts[pid]
				if not bool(cat.kind(str(e.kind)).get("structural", false)) or str(e.material) == "glass":
					continue
				n += 1
				if not str(e.material) in allowed:
					wrong[str(e.material)] = int(wrong.get(str(e.material), 0)) + 1
			var bad := 0
			var words := PackedStringArray()
			for m: String in wrong:
				bad += int(wrong[m])
				words.append("%d in %s" % [int(wrong[m]), ContractBrief.material_word(m)])
			_count(out, n - bad, n, "The structure uses only %s." % ContractBrief.material_list(allowed) if bad == 0
					else "Not allowed here: %s." % ", ".join(words),
					"Change those parts to %s." % ContractBrief.material_list(allowed))
		"budget":
			var share := float(req.get("share", 1.0))
			var cap := float(ctx.brief.budget) * share
			var cost := float(ctx.totals.cost)
			_limit(out, cost, cap, "The build costs %s of %s." % [money(cost), money(cap)],
					"Cut %s: %s." % [money(cost - cap), _saving_tip(ctx.totals)])
		"parts":
			var kinds := PackedStringArray(req.get("kinds", []))
			var n := 0
			for pid: String in model.parts:
				if str(model.parts[pid].kind) in kinds and (not req.has("level") or model.level_of(pid) == int(req.level)):
					n += 1
			_count(out, n, int(req.get("count", 1)), "%d placed." % n, "Place more of them.")
		"accessible_entrance":
			var n := _doors(model, ["door_accessible", "door_double"], true).size()
			_count(out, n, 1, "No accessible entrance yet." if n == 0 else "%d accessible entrance%s." % [n, "" if n == 1 else "s"],
					"Put an accessible door (or double doors) in an outside wall on the ground floor.")
		"vehicle_access":
			var n := _doors(model, ["door_vehicle"], true).size()
			_count(out, n, 1, "No vehicle door yet." if n == 0 else "A vehicle door is in place.",
					"Put a vehicle door in an outside wall of the garage or vehicle bay.")
		"secure_cells":
			var cells := _rooms_of(model, "custody_cell").size()
			var doors := 0
			for pid: String in model.parts:
				if str(model.parts[pid].kind) == "door_secure":
					doors += 1
			if cells == 0:
				out.detail = "There are no custody cells yet."
				out.tip = "Paint the custody cells first."
			else:
				_count(out, doors, cells, "%d secure doors for %d cells." % [doors, cells], "Give every cell a secure door.")
		"near":
			_near(req, model, cat, out)
		"exit_distance":
			_exits(req, model, cat, out)
		"lift_if_storeys":
			var floors: Array = []
			for rid: String in model.rooms:
				if not int(model.rooms[rid].level) in floors:
					floors.append(int(model.rooms[rid].level))
			if floors.size() <= 1:
				out.ok = true
				out.progress = 1.0
				out.detail = "Single storey: no lift needed."
			else:
				var missing: Array = []
				for lv: int in floors:
					var has_lift := false
					for rid in model.rooms_on(lv):
						if str(model.rooms[rid].type) == "lift_shaft":
							has_lift = true
					for pid in model.parts_of_family("circulation"):
						var p: Dictionary = model.parts[pid]
						if str(p.kind) == "lift" and int(p.level) <= lv and lv <= int(p.top_level):
							has_lift = true
					if not has_lift:
						missing.append(lv)
				out.ok = missing.is_empty()
				out.progress = 1.0 - float(missing.size()) / float(floors.size())
				out.detail = "A lift reaches every floor." if out.ok else "No lift on %s." % _floor_names(missing)
				if not out.ok:
					out.tip = "Place a lift that runs from the ground floor to the top."
		"structure":
			var rep: Dictionary = ctx.report
			if rep.is_empty():
				out.detail = "The design has not been stress tested."
				out.tip = "Run the stress test."
			elif rep.get("stale", false):
				out.detail = "The design has changed since the last stress test."
				out.tip = "Run the stress test again."
			else:
				out.ok = bool(rep.get("ok", false))
				out.progress = 1.0 if out.ok else 0.0
				var fails: Array = rep.get("failures", [])
				out.detail = "It stands up to every load case." if out.ok else "%d members fail%s." % [fails.size(),
						" in the %s case" % rep.scenario if str(rep.get("scenario", "")) != "" else ""]
				if not out.ok:
					out.tip = "Look at the red members: shorten their spans, add a column, or pick a bigger section."
		_:
			out.detail = "Unknown requirement."
	return out


# Requirement checks

static func _rooms(req: Dictionary, model: BuildingModel, cat: BuildingCatalog, out: Dictionary) -> void:
	var type := str(req.get("type", ""))
	var need := int(req.get("count", 1))
	var cap_each := int(req.get("capacity", 0))
	var rt := cat.room_type(type)
	var min_area := float(req.get("min_area", rt.get("min_area", 0.0)))
	var label := ContractBrief.room_label(type, cat, 2)
	var good := 0
	var small: Array = []
	var short_cap: Array = []
	var rooms := _rooms_of(model, type)
	for rid in rooms:
		var info := BuildingQuantities.room(model, rid)
		if float(info.area) + BuildingModel.EPS < min_area:
			small.append("%s is %.1f m2" % [_room_name(model, rid), float(info.area)])
		elif cap_each > 0 and int(info.capacity) < cap_each:
			short_cap.append("%s takes %d" % [_room_name(model, rid), int(info.capacity)])
		else:
			good += 1
	_count(out, good, need, "%d of %d %s ready." % [mini(good, need), need, label], "")
	if out.ok:
		return
	var why: Array = []
	if rooms.size() < need:
		why.append("%d more %s to paint" % [need - rooms.size(), label if need - rooms.size() != 1 else ContractBrief.room_label(type, cat, 1)])
	if not small.is_empty():
		why.append("too small (under %.1f m2): %s" % [min_area, ", ".join(PackedStringArray(small))])
	if not short_cap.is_empty():
		why.append("too few places for %d: %s" % [cap_each, ", ".join(PackedStringArray(short_cap))])
	var w := "; ".join(PackedStringArray(why))
	out.detail += " " + w.left(1).to_upper() + w.substr(1) + "."
	var per := float(rt.get("area_per_person", 0.0))
	if not short_cap.is_empty() and per > 0.0:
		out.tip = "A room for %d needs %.0f m2 at %.1f m2 a head, or that many desks or seats in it." % [cap_each, cap_each * per, per]
	elif not short_cap.is_empty():
		out.tip = "Furnish each one for %d." % cap_each
	elif not small.is_empty():
		out.tip = "Drag the walls of the small ones out to at least %.1f m2." % min_area
	else:
		out.tip = "Paint more floor as %s." % label


static func _near(req: Dictionary, model: BuildingModel, cat: BuildingCatalog, out: Dictionary) -> void:
	var a_rooms := _rooms_of(model, str(req.a))
	var b_rooms := _rooms_of(model, str(req.b))
	var limit := float(req.get("value", 0.0))
	if a_rooms.is_empty() or b_rooms.is_empty():
		out.detail = "Needs both a %s and a %s." % [ContractBrief.room_label(str(req.a), cat, 1), ContractBrief.room_label(str(req.b), cat, 1)]
		out.tip = "Paint them first, side by side."
		return
	var far: Array = []
	for ra in a_rooms:
		var best := INF
		for rb in b_rooms:
			if int(model.rooms[rb].level) == int(model.rooms[ra].level):
				best = minf(best, _centre(model.rooms[ra].outline).distance_to(_centre(model.rooms[rb].outline)))
		if best > limit:
			far.append("%s (%s)" % [_room_name(model, ra), "%.0f m" % best if best < INF else "another floor"])
	var ok_n := a_rooms.size() - far.size()
	_count(out, ok_n, a_rooms.size(), "%d of %d close enough." % [ok_n, a_rooms.size()],
			"Move these closer to the %s: %s." % [ContractBrief.room_label(str(req.b), cat, 1), ", ".join(PackedStringArray(far))])


static func _exits(req: Dictionary, model: BuildingModel, cat: BuildingCatalog, out: Dictionary) -> void:
	var limit := float(req.get("value", 30.0))
	var exits := {}  # level -> Array of exit points (Vector2)
	for pid in _doors(model, EXIT_DOORS, true):
		var pts := model.points_of(pid)
		var mid := (pts[0] + pts[1]) * 0.5
		if not exits.has(0):
			exits[0] = []
		(exits[0] as Array).append(Vector2(mid.x, mid.z))
	for rid: String in model.rooms:
		var r: Dictionary = model.rooms[rid]
		if str(r.type) in EXIT_ROOMS:
			var lv := int(r.level)
			if not exits.has(lv):
				exits[lv] = []
			(exits[lv] as Array).append(_centre(r.outline))
	# A stair is a way out on the floor it leaves and the floor it reaches.
	for pid in model.parts_of_family("circulation"):
		var st: Dictionary = model.parts[pid]
		if str(st.kind) != "stair":
			continue
		for end: int in 2:
			var lv := int(st.level) + end
			var p: Array = st.a if end == 0 else st.b
			if not exits.has(lv):
				exits[lv] = []
			(exits[lv] as Array).append(Vector2(float(p[0]), float(p[2])))
	var rooms: Array = []
	for rid in BuildingModel.sort_ids(model.rooms.keys()):
		if not str(model.rooms[rid].type) in CIRCULATION:
			rooms.append(rid)
	if rooms.is_empty():
		out.detail = "No rooms yet."
		out.tip = "Paint the rooms first."
		return
	var far: Array = []
	var worst := 0.0
	for rid: String in rooms:
		var c := _centre(model.rooms[rid].outline)
		var best := INF
		for p: Vector2 in exits.get(int(model.rooms[rid].level), []):
			best = minf(best, c.distance_to(p))
		worst = maxf(worst, best)
		if best > limit:
			far.append("%s (%s)" % [_room_name(model, rid), "%.0f m" % best if best < INF else "no way out on its floor"])
	_count(out, rooms.size() - far.size(), rooms.size(),
			"Every room is within %.0f m of a way out." % limit if far.is_empty() else "%d rooms are too far from a way out: %s." % [far.size(), ", ".join(PackedStringArray(far.slice(0, 4)))],
			"Add a fire door in the nearest outside wall, or a fire exit or stair on that floor.")


static func _within_plot(ctx: Dictionary, out: Dictionary) -> void:
	var model: BuildingModel = ctx.model
	var site: Variant = (ctx.brief as Dictionary).get("site")
	var plot: Array = (site as Dictionary).get("plot", []) if site is Dictionary else []
	if plot.size() < 3:
		out.ok = true
		out.progress = 1.0
		out.detail = "This site has no boundary."
		return
	var outside: Array = []
	for pid in BuildingModel.sort_ids(model.parts.keys()):
		for p in model.points_of(pid):
			if not BuildingModel.outline_has_point(plot, p.x, p.z):
				outside.append(pid)
				break
	for rid in BuildingModel.sort_ids(model.rooms.keys()):
		for p: Array in model.rooms[rid].outline:
			if not BuildingModel.outline_has_point(plot, float(p[0]), float(p[1])):
				outside.append(rid)
				break
	var n := model.parts.size() + model.rooms.size()
	_count(out, n - outside.size(), n, "Everything is inside the plot." if outside.is_empty() else "%d things cross the boundary." % outside.size(),
			"Pull the building back inside the red line.")


# Helpers

## ok if have >= need; progress is the share done.
static func _count(out: Dictionary, have: int, need: int, detail: String, tip: String) -> void:
	out.ok = have >= need
	out.progress = 1.0 if need <= 0 else clampf(float(have) / float(need), 0.0, 1.0)
	out.detail = detail
	out.tip = "" if out.ok else tip


## ok if value <= limit; progress falls as it goes over.
static func _limit(out: Dictionary, value: float, limit: float, detail: String, tip: String) -> void:
	out.ok = value <= limit + 0.001
	out.progress = 1.0 if out.ok else clampf(limit / maxf(value, 0.001), 0.0, 1.0)
	out.detail = detail
	out.tip = "" if out.ok else tip


static func _rooms_of(model: BuildingModel, type: String) -> PackedStringArray:
	var out: Array = []
	for rid: String in model.rooms:
		if str(model.rooms[rid].type) == type:
			out.append(rid)
	return BuildingModel.sort_ids(out)


## Openings of these kinds, in walls that are not partitions; ground floor only if asked.
static func _doors(model: BuildingModel, kinds: Array, ground_only: bool) -> PackedStringArray:
	var out: Array = []
	for pid: String in model.parts:
		var e: Dictionary = model.parts[pid]
		if not str(e.kind) in kinds or not e.has("host"):
			continue
		if str(model.parts[str(e.host)].kind) == "wall_partition":
			continue
		if ground_only and model.level_of(pid) != 0:
			continue
		out.append(pid)
	return BuildingModel.sort_ids(out)


static func _centre(outline: Array) -> Vector2:
	var c := Vector2.ZERO
	for p: Array in outline:
		c += Vector2(float(p[0]), float(p[1]))
	return c / maxf(outline.size(), 1)


static func _room_name(model: BuildingModel, rid: String) -> String:
	var r: Dictionary = model.rooms[rid]
	if str(r.get("name", "")) != "":
		return str(r.name)
	var label := str(model.catalog.room_type(str(r.type)).get("label", r.type))
	# Number rooms of a type in id order, so "Classroom 3" stays the same room.
	var n := _rooms_of(model, str(r.type)).find(rid) + 1
	return "%s %d" % [label, n]


static func _storeys_used(model: BuildingModel) -> int:
	var top := -1
	for pid: String in model.parts:
		if catalog_family(model, pid) != "roof":
			top = maxi(top, model.level_of(pid))
	for rid: String in model.rooms:
		top = maxi(top, int(model.rooms[rid].level))
	return top + 1


static func catalog_family(model: BuildingModel, pid: String) -> String:
	return model.catalog.family_of(str(model.parts[pid].kind))


static func _top(model: BuildingModel) -> float:
	var top := 0.0
	for pid: String in model.parts:
		top = maxf(top, model.aabb_of(pid).end.y)
	return top


static func _floor_names(levels: Array) -> String:
	var names := PackedStringArray()
	for lv: int in levels:
		names.append("the ground floor" if lv == 0 else "floor %d" % lv)
	return ", ".join(names)


## Where the money goes, as a hint for what to cut.
static func _saving_tip(totals: Dictionary) -> String:
	var by: Dictionary = totals.get("by_family", {})
	var biggest := ""
	for fam: String in by:
		if biggest == "" or float(by[fam]) > float(by[biggest]):
			biggest = fam
	var fit := float(totals.get("fit_out", 0.0))
	if biggest == "" or fit > float(by.get(biggest, 0.0)):
		return "fit-out is the biggest spend (%s); smaller rooms or plainer room types cost less" % money(fit)
	return "the %s cost most (%s); try a cheaper material or a lighter section" % [_plural_family(biggest), money(float(by[biggest]))]


static func _plural_family(fam: String) -> String:
	match fam:
		"foundation": return "foundations"
		"column": return "columns"
		"beam": return "beams"
		"brace": return "braces"
		"truss": return "trusses"
		"slab": return "floor slabs"
		"roof": return "roofs"
		"wall": return "walls"
		"opening": return "doors and windows"
		"fixture": return "fixtures"
	return fam


## "£182,400".
static func money(v: float) -> String:
	var neg := v < 0.0
	var s := str(roundi(absf(v)))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(-3)
	return ("-" if neg else "") + "£" + s + out


static func _summary(a: Dictionary) -> String:
	if a.ok:
		var goals_left := 0
		for it: Dictionary in a.items:
			if not it.hard and not it.ok:
				goals_left += 1
		return "Every requirement is met." + (" %d bonus goal%s still open." % [goals_left, "" if goals_left == 1 else "s"] if goals_left > 0 else " Every bonus goal too.")
	var first := {}
	for it: Dictionary in a.items:
		if it.hard and not it.ok:
			first = it
			break
	return "%d of %d requirements met. Next: %s. %s" % [int(a.passed), int(a.total), str(first.label).to_lower(),
			str(first.tip) if str(first.tip) != "" else str(first.detail)]
