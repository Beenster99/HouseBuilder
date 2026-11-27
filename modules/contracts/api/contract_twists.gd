class_name ContractTwists
extends RefCounted
## Awkward briefs (flag contracts.twists): none, one or two twists from internal/twists.gd
## added to a generated brief, each changing how the building has to be designed and paying
## more for the trouble. The chance rises with the firm's tier; twists that clash are never
## paired; site twists are chosen only for a plot that has that problem.
##
##   ContractTwists.apply(brief, firm_tier)   # the brief with its twists (same seed, same twists)
##   ContractTwists.table()                   # the twist rows
##   brief.twists                             # ids added, [] for none
##   brief.existing                           # ops for a building already there (locked parts)
##   ContractTwists.starting_design(brief)    # BuildingModel data to start the design from

const FLAG := "contracts.twists"
const DATA := preload("res://modules/contracts/internal/twists.gd")


static func table() -> Array:
	return DATA.TWISTS


static func row(twist_id: String) -> Dictionary:
	for t: Dictionary in DATA.TWISTS:
		if str(t.id) == twist_id:
			return t
	return {}


## Adds twists to a brief rolled for a firm of `tier`. Off (the brief unchanged) while the
## flag is off; force skips the flag and the chance (tests).
static func apply(brief: Dictionary, tier: int, force: Array = []) -> Dictionary:
	if force.is_empty() and not Flags.is_on(FLAG):
		return brief
	var b := brief.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(b.get("seed", 0)), str(b.get("id", "")), "twists"])
	var picks: Array = []
	if not force.is_empty():
		for id: Variant in force:
			if not row(str(id)).is_empty() and _fits(b, row(str(id))):
				picks.append(row(str(id)))
	else:
		var chance: float = DATA.CHANCE[clampi(tier, 1, DATA.CHANCE.size() - 1)]
		var n := 0
		if rng.randf() < chance:
			n = 2 if rng.randf() < chance * DATA.SECOND_SHARE else 1
		var pool: Array = DATA.TWISTS.filter(func(t: Dictionary) -> bool: return int(t.tier) <= tier and _fits(b, t))
		while picks.size() < n and not pool.is_empty():
			var t: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
			picks.append(t)
			pool = pool.filter(func(o: Dictionary) -> bool:
				return str(o.id) != str(t.id) and not str(o.id) in t.clashes and not str(t.id) in o.clashes)
	var ids: Array = b.get("twists", [])
	for t: Dictionary in picks:
		if _apply_one(b, t):
			ids.append(str(t.id))
	b["twists"] = ids
	return b


static func _fits(b: Dictionary, t: Dictionary) -> bool:
	var spec: Dictionary = ContractGenerator.TYPES.get(str(b.get("type", "")), {})
	if t.has("categories") and not str(spec.get("category", "")) in t.categories:
		return false
	if t.has("existing") and (b.has("existing") or existing_ops(b, str(t.existing)).is_empty()):
		return false
	if t.has("max_storeys"):
		for r: Dictionary in b.get("requirements", []):
			if str(r.kind) == "max_storeys" and int(r.value) > int(t.max_storeys):
				return false
	if t.has("only"):
		var allowed := _materials(b)
		if not allowed.has("timber") or spec.is_empty():
			return false
	if t.has("ban") and _ban_target(b, t).is_empty():
		return false
	var needs := str(t.get("needs", ""))
	if needs == "":
		return true
	var site: Dictionary = b.get("site", {}) if b.get("site") is Dictionary else {}
	var sid := str(site.get("id", ""))
	if sid == "":
		return false
	if needs == "site":
		return true
	var pack := SitePool.open(sid)
	return pack != null and pack.ok() and pack.has_factor(needs)


static func _apply_one(b: Dictionary, t: Dictionary) -> bool:
	var sentence := str(t.sentence)
	if t.has("budget"):
		b["budget"] = snappedf(float(b.budget) * float(t.budget), 1000.0)
	if t.has("deadline"):
		b["deadline_days"] = maxi(20, int(snappedf(float(b.deadline_days) * float(t.deadline), 5.0)))
	if t.has("ban"):
		var gone := _ban_target(b, t)
		if gone.is_empty():
			return false
		for r: Dictionary in b.requirements:
			if str(r.kind) == "materials":
				r["allowed"] = Array(r.allowed).filter(func(m: Variant) -> bool: return str(m) != gone)
		sentence = sentence % ContractBrief.material_word(gone)
	if t.has("only"):
		var keep: Array = Array(t.only).filter(func(m: Variant) -> bool:
			return str(m) == "timber" or str(m) in ContractGenerator.structure_materials(str(b.type)))
		for r: Dictionary in b.requirements:
			if str(r.kind) == "materials":
				r["allowed"] = keep
	if t.has("existing"):
		var ops := existing_ops(b, str(t.existing))
		if ops.is_empty():
			return false
		b["existing"] = ops
	if t.has("require"):
		var req: Dictionary = (t.require as Dictionary).duplicate(true)
		req["id"] = str(t.id)
		req["twist"] = str(t.id)
		if str(req.kind) == "keep_existing":
			req["entries"] = existing_entries(b.existing)
			req["what"] = "the existing house" if str(t.existing) == "house" else "the old frontage"
		var reqs: Array = b.requirements
		var at := reqs.size()
		for i in reqs.size():
			if str(reqs[i].kind) == "budget":
				at = i
		reqs.insert(at, req)
	b["fee"] = snappedf(float(b.fee) * (1.0 + float(t.uplift)), 1000.0)
	b["summary"] = str(b.get("summary", "")) + " " + sentence
	var notes: Array = b.get("twist_notes", [])
	notes.append({"id": str(t.id), "label": str(t.label), "sentence": sentence, "uplift": float(t.uplift)})
	b["twist_notes"] = notes
	return true


static func _materials(b: Dictionary) -> PackedStringArray:
	for r: Dictionary in b.get("requirements", []):
		if str(r.kind) == "materials":
			return PackedStringArray(r.get("allowed", []))
	return PackedStringArray()


static func _ban_target(b: Dictionary, t: Dictionary) -> String:
	var allowed := _materials(b)
	if allowed.size() < 2:
		return ""
	for m: Variant in t.ban:
		if str(m) in allowed:
			return str(m)
	return ""


## The design a brief starts from: empty, or the building already on the plot, locked
## (BuildingModel.to_data(), for BuildingSync.load_design).
static func starting_design(brief: Dictionary, building_name := "") -> Dictionary:
	var m := BuildingModel.new("", building_name if building_name != "" else str(brief.get("title", "New building")))
	for op: Variant in brief.get("existing", []):
		if op is Dictionary:
			m.apply(op)
	m.apply(BuildingCommands.set_design_meta({"brief": str(brief.get("id", ""))}))
	return m.to_data()


## The existing entries as the model stores them ({id: entry}), to check they are kept.
static func existing_entries(ops: Array) -> Dictionary:
	var m := BuildingModel.new()
	var out := {}
	for op: Variant in ops:
		if op is Dictionary:
			var r := m.apply(op)
			if not r.is_empty():
				var id := str(r.do.entry.id)
				out[id] = m.entry(id)
	return out


## Ops that put a locked building on the brief's plot: "house" (a small single-storey house
## at the back) or "frontage" (a street wall along the front, -Z). [] if the plot is too small.
## Ids are x1, x2... so they never meet the design's own.
static func existing_ops(b: Dictionary, mode: String) -> Array:
	var site: Dictionary = b.get("site", {}) if b.get("site") is Dictionary else {}
	var plot: Array = site.get("plot", [])
	if plot.size() < 3:
		return []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Variant in plot:
		lo = Vector2(minf(lo.x, float(p[0])), minf(lo.y, float(p[1])))
		hi = Vector2(maxf(hi.x, float(p[0])), maxf(hi.y, float(p[1])))
	var C := BuildingCommands
	var ops: Array = []
	var n := [0]
	var add := func(op: Dictionary) -> String:
		n[0] += 1
		var id := "x%d" % n[0]
		op.entry["id"] = id
		op.entry["locked"] = true
		ops.append(op)
		return id
	var corners: Array = []
	if mode == "house":
		var w := 6.0
		var d := 4.5
		if hi.x - lo.x < w + 4.0 or hi.y - lo.y < d + 6.0:
			return []
		var x0 := (lo.x + hi.x) / 2.0 - w / 2.0
		var z0 := hi.y - 1.2 - d
		corners = [[x0, 0.0, z0], [x0 + w, 0.0, z0], [x0 + w, 0.0, z0 + d], [x0, 0.0, z0 + d]]
		var walls: Array = []
		for side in 4:
			add.call(C.place_part("strip_footing", 0, {"a": corners[side], "b": corners[(side + 1) % 4]}))
			walls.append(add.call(C.place_part("wall_loadbearing", 0, {"a": corners[side], "b": corners[(side + 1) % 4]}, "masonry")))
		add.call(C.place_part("slab", 0, {"outline": C.rect(x0, z0, w, d)}, "concrete"))
		add.call(C.place_part("roof_pitched", 0, {"outline": C.rect(x0, z0, w, d), "y": 3.0, "pitch": 35.0}))
		add.call(C.place_opening("door_external", walls[0], w * 0.5))
		add.call(C.place_opening("window_medium", walls[0], 1.5))
		add.call(C.place_opening("window_medium", walls[2], w * 0.5))
		add.call(C.place_room("living_room", 0, C.rect(x0, z0, w * 0.6, d), "Existing living room"))
		add.call(C.place_room("kitchen", 0, C.rect(x0 + w * 0.6, z0, w * 0.4, d), "Existing kitchen"))
	elif mode == "frontage":
		var len := minf(hi.x - lo.x - 3.0, 16.0)
		if len < 8.0 or hi.y - lo.y < 12.0:
			return []
		var x0 := (lo.x + hi.x) / 2.0 - len / 2.0
		var z := lo.y + 1.5
		var a := [x0, 0.0, z]
		var bb := [x0 + len, 0.0, z]
		corners = [a, bb]
		add.call(C.place_part("strip_footing", 0, {"a": a, "b": bb}))
		var wall: String = add.call(C.place_part("wall_loadbearing", 0, {"a": a, "b": bb}, "masonry"))
		add.call(C.place_opening("door_external", wall, len * 0.5))
		for k in [0.18, 0.34, 0.66, 0.82]:
			add.call(C.place_opening("window_medium", wall, len * k))
	else:
		return []
	for c: Array in corners:
		if not BuildingModel.outline_has_point(plot, float(c[0]), float(c[2])):
			return []
	return ops
