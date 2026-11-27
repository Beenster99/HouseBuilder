class_name ContractGenerator
extends RefCounted
## Rolls contract briefs, so there is always new work across the whole range of buildings:
## houses, schools, civic buildings, police and fire stations, offices, clinics, care
## homes, hospital wings and airport terminals. Deterministic: the same seed gives the same
## brief on every machine, so the host only needs to send the seed.
##
##   var brief := ContractGenerator.generate(seed)                    # small works (tier 1)
##   var brief := ContractGenerator.generate(seed, "primary_school")
##   var board := ContractGenerator.board(seed, career.tier(), 5)     # a job board
##   var brief := ContractGenerator.generate_on_site(seed, "", tier)  # on a real plot
##
## Each brief takes its rooms from the building type's program (internal/building_types.gd),
## sized by a roll, prices its budget from the rooms' floor area at the type's rate with
## some slack (less slack at higher tiers), and sometimes adds a site twist (a height limit,
## a small footprint) or asks for a stress test. It carries the type's tier and the XP it
## earns ("tier", "xp"). Most briefs are for the firm's own tier, some for the tier below.

const TYPES_SCRIPT := preload("res://modules/contracts/internal/building_types.gd")
const TYPES: Dictionary = TYPES_SCRIPT.TYPES
## The client pays this much over the budget: building at budget earns this margin.
const FEE_MARGIN := 0.12
## Budgets also cover routed services (wiring, plumbing, heating: the services module),
## which the type rates leave out: about this share of the build on a house.
const SERVICES_SHARE := 0.08
## Planning height limit with no other: this much per storey plus a roof allowance, m.
const PLANNING_STOREY_M := 3.5
const PLANNING_ROOF_M := 3.0
## Plot area per m2 of ground floor, by category (gardens, parking, playgrounds).
const PLOT_RATIO := {"domestic": 3.0, "education": 3.0, "civic": 2.5, "police": 2.5, "office": 1.8, "health": 2.5, "transport": 2.0}


## Share of briefs for the firm's own tier (the rest are from the tiers below).
const OWN_TIER_SHARE := 0.7


## Building type ids open at a tier (that tier and below), in table order.
static func types_open(tier: int) -> PackedStringArray:
	var out := PackedStringArray()
	for t: String in TYPES:
		if int(TYPES[t].tier) <= tier:
			out.append(t)
	return out


## Building type ids first offered at exactly this tier.
static func types_of_tier(tier: int) -> PackedStringArray:
	var out := PackedStringArray()
	for t: String in TYPES:
		if int(TYPES[t].tier) == tier:
			out.append(t)
	return out


## One brief. type "" picks a type for a firm at `tier`: usually one of that tier's own.
static func generate(seed: int, type: String = "", tier: int = 1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	tier = clampi(tier, 1, ContractTiers.top())
	if type == "" or not TYPES.has(type):
		var own := types_of_tier(tier)
		var pool := own if own.size() > 0 and (rng.randf() < OWN_TIER_SHARE or tier == 1) else types_open(tier)
		type = pool[rng.randi_range(0, pool.size() - 1)]
	var spec: Dictionary = TYPES[type]
	var type_tier := int(spec.tier)
	var cat := BuildingCatalog.default_catalog()
	var size := rng.randf()
	var reqs: Array = []
	var area := 0.0
	var program_words := PackedStringArray()
	for p: Array in spec.program:
		var room_type := str(p[0])
		var n := roundi(lerpf(float(p[1]), float(p[2]), size))
		if n <= 0:
			continue
		var cap := int(p[3])
		var rt := cat.room_type(room_type)
		var each := maxf(float(rt.get("min_area", 4.0)), cap * float(rt.get("area_per_person", 0.0)))
		area += n * each * 1.25
		var req := {"id": room_type, "kind": "rooms", "type": room_type, "count": n}
		if cap > 0:
			req["capacity"] = cap
		program_words.append(ContractBrief.describe(req, cat).to_lower())
		req["min_area"] = snappedf(each, 0.5)
		reqs.append(req)
	area *= 1.0 + float(spec.circulation)
	var storeys: Array = spec.storeys
	var max_storeys := int(storeys[1])
	reqs.append({"id": "storeys", "kind": "max_storeys", "value": max_storeys})
	reqs.append({"id": "materials", "kind": "materials", "allowed": Array(structure_materials(type))})
	for e: Dictionary in spec.extras:
		var x := e.duplicate(true)
		x["id"] = str(x.kind)
		reqs.append(x)
	# Site twists.
	var twist := ""
	var roll := rng.randf()
	if roll < 0.15 and max_storeys > 1:
		var h := 3.0 * max_storeys + 2.0
		reqs.append({"id": "height", "kind": "max_height", "value": h})
		twist = "It is in a conservation area: nothing taller than %.0f m." % h
	elif roll < 0.25:
		var foot := ceilf(area / float(max_storeys) * 1.1 / 10.0) * 10.0
		reqs.append({"id": "footprint", "kind": "max_footprint", "value": foot})
		twist = "The plot is tight: the ground floor can take only %.0f m2 of rooms." % foot
	if not _has_kind(reqs, "max_height"):
		reqs.append({"id": "height", "kind": "max_height", "value": PLANNING_STOREY_M * max_storeys + PLANNING_ROOF_M})
	if roll > 0.8 and not _has_kind(reqs, "structure"):
		reqs.append({"id": "structure", "kind": "structure"})
		twist = "The client's engineer wants to see a passed stress test."
	reqs.append({"id": "plot", "kind": "within_plot"})
	reqs.append({"id": "budget", "kind": "budget"})
	# Money and time.
	var slack := rng.randf_range(1.15, 1.45) - (tier - 1) * 0.02
	var budget := snappedf(area * float(spec.rate) * (1.0 + SERVICES_SHARE) * slack, 1000.0)
	var fee := snappedf(budget * (1.0 + FEE_MARGIN), 1000.0)
	var deadline := int(snappedf((60.0 + area * 0.5) * rng.randf_range(1.1, 1.4), 5.0))
	var goals: Array = []
	for g: Array in spec.goals:
		if rng.randf() < 0.7:
			goals.append({"id": str(g[0]), "kind": "rooms", "type": str(g[0]), "count": 1, "bonus": snappedf(fee * float(g[1]), 500.0)})
	goals.append({"id": "thrifty", "kind": "budget", "share": 0.9, "bonus": snappedf(fee * 0.04, 500.0)})
	var clients: Array = TYPES_SCRIPT.CLIENTS.get(str(spec.category), ["A client"])
	var client := str(clients[rng.randi_range(0, clients.size() - 1)])
	var size_word := TYPES_SCRIPT.SIZES[clampi(int(size * TYPES_SCRIPT.SIZES.size()), 0, TYPES_SCRIPT.SIZES.size() - 1)]
	var label := str(spec.label)
	var summary := "%s want%s a %s: %s, on no more than %d storey%s." % [client, "" if (client.begins_with("Mr and") or client.ends_with("family") or client.ends_with("couple")) else "s",
			label.to_lower(), _and_list(program_words), max_storeys, "" if max_storeys == 1 else "s"]
	if twist != "":
		summary += " " + twist
	return {
		"id": "%s-%d" % [type, seed], "title": "%s %s" % [size_word, label.to_lower()], "type": type,
		"client": client, "summary": summary, "seed": seed,
		"budget": budget, "fee": fee, "deadline_days": deadline,
		"tier": type_tier, "xp": snappedi(roundi(float(ContractTiers.info(type_tier).award) * (0.8 + 0.4 * size)), 10),
		"requirements": reqs, "goals": goals, "floor_area": snappedf(area, 5.0),
		"site": default_plot(area / float(max_storeys), str(spec.category)),
	}


## A plain level plot for a brief with no real site: a rectangle centred on (0, 0) in building
## model coordinates, about PLOT_RATIO times the ground floor it needs.
static func default_plot(ground_m2: float, category: String) -> Dictionary:
	var plot_m2 := maxf(ground_m2 * float(PLOT_RATIO.get(category, 2.0)), 150.0)
	var w := maxf(12.0, roundf(sqrt(plot_m2 * 1.4)))
	var d := maxf(12.0, roundf(plot_m2 / w))
	return {"id": "", "name": "a level greenfield plot", "plot": [[-w / 2, -d / 2], [w / 2, -d / 2], [w / 2, d / 2], [-w / 2, d / 2]],
			"rating": 1, "soil": "", "area": w * d, "w": w, "d": d, "factors": []}


## Structural materials a building type allows: its category's list, cut to what a firm has
## unlocked by the type's tier.
static func structure_materials(type: String) -> PackedStringArray:
	var spec: Dictionary = TYPES.get(type, {})
	var want: Array = TYPES_SCRIPT.MATERIALS.get(str(spec.get("category", "")), ["timber", "masonry", "concrete", "steel"])
	var t := int(spec.get("tier", 1))
	var out := PackedStringArray()
	for m: String in want:
		var ok := true
		for u: Dictionary in ContractCareer.UNLOCKS:
			if str(u.id) == "material:" + m and int(u.tier) > t:
				ok = false
		if ok:
			out.append(m)
	return out


## The hardest site (1 to 5) offered at a firm tier.
static func max_site_rating(tier: int) -> int:
	return clampi(1 + (tier + 1) / 2, 2, 5)


## A brief on a real plot from the sites pool (Phase 6): the plot's outline becomes a
## within_plot requirement (BuildingModel coordinates, the plot centre at 0, 0), the budget
## and fee rise by the plot's cost multiplier, the XP by a tenth per difficulty step, and its
## problems go in the summary. Falls back to an ordinary brief when no plot suits the type.
static func generate_on_site(seed: int, type: String = "", tier: int = 1) -> Dictionary:
	var b := generate(seed, type, tier)
	var kind := str(TYPES_SCRIPT.SITE_KIND.get(str(b.type), ""))
	var site_id := SitePool.pick(kind, seed, max_site_rating(tier)) if kind != "" else ""
	if site_id == "":
		return b
	var pack := SitePool.open(site_id)
	if not pack.ok() or pack.plot_outline_local().size() < 3:
		return b
	var mult := maxf(1.0, pack.cost_multiplier_hint())
	var labels := PackedStringArray()
	for f: Dictionary in pack.factors():
		labels.append(str(f.get("label", "")).to_lower())
	b["id"] = "%s@%s" % [b.id, site_id]
	var outline: Array = pack.plot_outline_local()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for pt: Variant in outline:
		var v := Vector2(float(pt[0]), float(pt[1]))
		lo = lo.min(v)
		hi = hi.max(v)
	b["site"] = {"id": site_id, "name": pack.title(), "plot": outline, "rating": pack.rating(),
			"w": roundf(hi.x - lo.x), "d": roundf(hi.y - lo.y),
			"soil": pack.soil(), "area": pack.plot_area(), "factors": Array(labels)}
	if not _has_kind(b.requirements, "within_plot"):
		(b.requirements as Array).insert((b.requirements as Array).size() - 1, {"id": "plot", "kind": "within_plot"})
	b["budget"] = snappedf(float(b.budget) * mult, 1000.0)
	b["fee"] = snappedf(float(b.fee) * mult, 1000.0)
	b["deadline_days"] = int(snappedf(float(b.deadline_days) * (1.0 + 0.05 * (pack.rating() - 1)), 5.0))
	b["xp"] = snappedi(roundi(float(b.xp) * (1.0 + 0.1 * (pack.rating() - 1))), 10)
	b["title"] = "%s at %s" % [b.title, pack.title()]
	var site_line := "The site is %s (%d m2), difficulty %d of 5" % [pack.title(), roundi(pack.plot_area()), pack.rating()]
	site_line += ": " + _and_list(labels) + "." if not labels.is_empty() else "."
	b["summary"] = str(b.summary) + " " + site_line
	return b


## n briefs for a job board, each from its own seed; one of the hand-written briefs leads
## while it has not been done, and every other generated one is on a real site.
## A hand-written brief leads once the firm reaches its tier, until it has been done.
static func board(seed: int, tier: int, n: int = 5, done: Array = []) -> Array:
	var out: Array = []
	for b: Dictionary in ContractBrief.authored():
		if not str(b.id) in done and int(b.tier) <= tier and out.size() < 1:
			out.append(b)
	var i := 0
	while out.size() < n:
		out.append(generate_on_site(seed * 31 + i, "", tier) if i % 2 == 1 else generate(seed * 31 + i, "", tier))
		i += 1
	return out


static func _and_list(words: PackedStringArray) -> String:
	if words.size() <= 1:
		return "".join(words)
	return ", ".join(words.slice(0, words.size() - 1)) + " and " + words[words.size() - 1]


static func _has_kind(reqs: Array, kind: String) -> bool:
	for r: Dictionary in reqs:
		if str(r.kind) == kind:
			return true
	return false
