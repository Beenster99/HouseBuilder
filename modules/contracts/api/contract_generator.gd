class_name ContractGenerator
extends RefCounted
## Rolls contract briefs, so there is always new work across the whole range of buildings:
## houses, schools, civic buildings, police and fire stations, offices, clinics, care
## homes, hospital wings and airport terminals. Deterministic: the same seed gives the same
## brief on every machine, so the host only needs to send the seed.
##
##   var brief := ContractGenerator.generate(seed)                       # any type open at rep 0
##   var brief := ContractGenerator.generate(seed, "primary_school")
##   var board := ContractGenerator.board(seed, career.reputation, 5)    # a job board
##   var brief := ContractGenerator.generate_on_site(seed, "", reputation)  # on a real plot
##
## Each brief takes its rooms from the building type's program (internal/building_types.gd),
## sized by a roll, prices its budget from the rooms' floor area at the type's rate with
## some slack (less slack as reputation grows), and sometimes adds a site twist (a height
## limit, a small footprint) or asks for a stress test.

const TYPES_SCRIPT := preload("res://modules/contracts/internal/building_types.gd")
const TYPES: Dictionary = TYPES_SCRIPT.TYPES
## The client pays this much over the budget: building at budget earns this margin.
const FEE_MARGIN := 0.12
## Budgets also cover routed services (wiring, plumbing, heating: the services module),
## which the type rates leave out: about this share of the build on a house.
const SERVICES_SHARE := 0.08


## Building type ids open at a reputation, in table order.
static func types_open(reputation: int) -> PackedStringArray:
	var out := PackedStringArray()
	for t: String in TYPES:
		if int(TYPES[t].rep) <= reputation:
			out.append(t)
	return out


## One brief. type "" picks among the types open at `reputation`.
static func generate(seed: int, type: String = "", reputation: int = 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var open := types_open(reputation)
	if type == "" or not TYPES.has(type):
		type = open[rng.randi_range(0, open.size() - 1)]
	var spec: Dictionary = TYPES[type]
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
		reqs.append(req)
		program_words.append(ContractBrief.describe(req, cat).to_lower())
	area *= 1.0 + float(spec.circulation)
	var storeys: Array = spec.storeys
	var max_storeys := int(storeys[1])
	reqs.append({"id": "storeys", "kind": "max_storeys", "value": max_storeys})
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
	if roll > 0.8 and not _has_kind(reqs, "structure"):
		reqs.append({"id": "structure", "kind": "structure"})
		twist = "The client's engineer wants to see a passed stress test."
	reqs.append({"id": "budget", "kind": "budget"})
	# Money and time.
	var slack := rng.randf_range(1.15, 1.45) - minf(reputation, 60) * 0.002
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
		"reputation": {"min": int(spec.rep), "reward": clampi(2 + int(area / 120.0), 2, 25)},
		"requirements": reqs, "goals": goals,
	}


## The hardest site (1 to 5) offered at a reputation.
static func max_site_rating(reputation: int) -> int:
	return clampi(2 + reputation / 15, 2, 5)


## A brief on a real plot from the sites pool (Phase 6): the plot's outline becomes a
## within_plot requirement (BuildingModel coordinates, the plot centre at 0, 0), the budget
## and fee rise by the plot's cost multiplier, the reward by its difficulty, and its problems
## go in the summary. Falls back to an ordinary brief when no plot suits the type.
static func generate_on_site(seed: int, type: String = "", reputation: int = 0) -> Dictionary:
	var b := generate(seed, type, reputation)
	var kind := str(TYPES_SCRIPT.SITE_KIND.get(str(b.type), ""))
	var site_id := SitePool.pick(kind, seed, max_site_rating(reputation)) if kind != "" else ""
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
	b["site"] = {"id": site_id, "name": pack.title(), "plot": pack.plot_outline_local(), "rating": pack.rating(),
			"soil": pack.soil(), "area": pack.plot_area(), "factors": Array(labels)}
	(b.requirements as Array).insert((b.requirements as Array).size() - 1, {"id": "plot", "kind": "within_plot"})
	b["budget"] = snappedf(float(b.budget) * mult, 1000.0)
	b["fee"] = snappedf(float(b.fee) * mult, 1000.0)
	b["deadline_days"] = int(snappedf(float(b.deadline_days) * (1.0 + 0.05 * (pack.rating() - 1)), 5.0))
	b.reputation["reward"] = int(b.reputation.reward) + pack.rating() - 1
	b["title"] = "%s at %s" % [b.title, pack.title()]
	var site_line := "The site is %s (%d m2), difficulty %d of 5" % [pack.title(), roundi(pack.plot_area()), pack.rating()]
	site_line += ": " + _and_list(labels) + "." if not labels.is_empty() else "."
	b["summary"] = str(b.summary) + " " + site_line
	return b


## n briefs for a job board, each from its own seed; one of the hand-written briefs leads
## while it has not been done, and every other generated one is on a real site.
static func board(seed: int, reputation: int, n: int = 5, done: Array = []) -> Array:
	var out: Array = []
	for b: Dictionary in ContractBrief.authored():
		if not str(b.id) in done and int(b.reputation.min) <= reputation and out.size() < 1:
			out.append(b)
	var i := 0
	while out.size() < n:
		out.append(generate_on_site(seed * 31 + i, "", reputation) if i % 2 == 1 else generate(seed * 31 + i, "", reputation))
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
