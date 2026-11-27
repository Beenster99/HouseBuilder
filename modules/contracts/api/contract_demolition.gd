class_name ContractDemolition
extends RefCounted
## Demolition jobs (flag contracts.demolition_jobs): a brief to bring an old building down on
## its plot, cleanly, without touching the neighbours and within a charge budget. Accepting one
## loads the old building into the design (locked) and starts the demolition module on it; the
## demolition's result (DemolitionBus.result) is what the job is judged on.
##
##   var b := ContractDemolition.generate(seed, tier)        # brief.mode == "demolish"
##   var b := ContractDemolition.generate(seed, tier, rec)   # the firm's own old building (town)
##   ContractDemolition.target_design(b)                     # BuildingModel data of the old building
##   ContractDemolition.start_options(b)                     # {plot, neighbours} for start_from_model
##   ContractDemolition.assess(b, result)                    # like ContractValidator.assess
##
## Requirement kinds: demolition_collapse (share brought down, value), debris_within_plot
## (most share of debris off the plot, value), neighbours_safe, charge_budget (most charges,
## value) and budget (crew, charges and clearing debris off the plot). Goals: a tighter debris
## share and fewer charges.

const FLAG := "contracts.demolition_jobs"
const MODE := "demolish"
const CHARGE_COST := 1500.0
## Clearing debris that landed off the plot, per m3.
const CLEANUP_PER_M3 := 400.0
## The crew and plant for the job, per m3 of building.
const CREW_PER_M3 := 6.0
const STOREY_M := 3.0
## Building types worth knocking down, by tier (any type of that tier or below works).
const SKIP_CATEGORIES: PackedStringArray = ["transport"]


static func is_demolition(brief: Dictionary) -> bool:
	return str(brief.get("mode", "")) == MODE


## A demolition brief for a firm of `tier`. record (optional): a building the firm put up
## (the town module's record: {id, title, model (BuildingModel data), site?}) to bring down
## for redevelopment.
static func generate(seed: int, tier: int, record: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "demolish"])
	tier = clampi(tier, 1, ContractTiers.top())
	var target: Dictionary
	var type := ""
	var label := ""
	var client := ""
	if record.get("model") is Dictionary:
		target = (record.model as Dictionary).duplicate(true)
		label = str(record.get("title", target.get("name", "building")))
		client = "The town council"
	else:
		var pool: Array = Array(ContractGenerator.types_open(tier)).filter(func(t: String) -> bool:
			return not str(ContractGenerator.TYPES[t].category) in SKIP_CATEGORIES)
		type = str(pool[rng.randi_range(0, pool.size() - 1)])
		var spec: Dictionary = ContractGenerator.TYPES[type]
		label = str(spec.label).to_lower()
		var clients: Array = ContractGenerator.TYPES_SCRIPT.CLIENTS.get(str(spec.category), ["A developer"])
		client = str(clients[rng.randi_range(0, clients.size() - 1)])
		var storeys := rng.randi_range(int(spec.storeys[0]), int(spec.storeys[1]))
		var w := snappedf(rng.randf_range(8.0, 10.0 + tier * 4.0), 1.0)
		var d := snappedf(rng.randf_range(6.0, 8.0 + tier * 3.0), 1.0)
		target = old_building(w, d, storeys, "The old " + label)
	var model := BuildingModel.new()
	model.load_data(target)
	var box := _box(model)
	var volume := box.size.x * box.size.y * box.size.z
	# Plot: the building plus a working margin; neighbours just beyond it on both sides.
	var margin := 4.0 + tier * 0.5
	var lo := Vector2(box.position.x - margin, box.position.z - margin)
	var hi := Vector2(box.end.x + margin, box.end.z + margin)
	var plot := [[lo.x, lo.y], [hi.x, lo.y], [hi.x, hi.y], [lo.x, hi.y]]
	var neighbours: Array = []
	var nh := maxf(6.0, box.size.y * rng.randf_range(0.6, 1.0))
	if tier >= 2 or rng.randf() < 0.5:
		neighbours.append([lo.x - 1.0 - 8.0, 0.0, lo.y + 1.0, 8.0, nh, (hi.y - lo.y) - 2.0])
	if tier >= 3:
		neighbours.append([hi.x + 1.0, 0.0, lo.y + 1.0, 8.0, nh, (hi.y - lo.y) - 2.0])
	var charges := maxi(6, int(ceil(model.parts.size() * (0.35 - tier * 0.02))))
	var outside := clampf(0.2 - tier * 0.02, 0.06, 0.2)
	var budget := snappedf(volume * CREW_PER_M3 + charges * CHARGE_COST * 1.1, 500.0)
	var fee := snappedf(budget * 1.3 + 4000.0 * tier, 1000.0)
	var xp := snappedi(roundi(float(ContractTiers.info(tier).award) * 0.8), 10)
	var title := "Demolish " + (label if record.has("model") else "the old " + label)
	var summary := "%s want%s %s brought down and the plot cleared: everything down, the debris kept on the plot%s, in no more than %d charges." % [
			client, "" if client.ends_with("family") else "s", label if record.has("model") else "the old " + label,
			", with the neighbours untouched" if not neighbours.is_empty() else "", charges]
	if record.has("model"):
		summary += " It is one of your own: it has served its time and the site is wanted for something new."
	var reqs: Array = [
		{"id": "collapse", "kind": "demolition_collapse", "value": 0.95},
		{"id": "debris", "kind": "debris_within_plot", "value": outside},
	]
	if not neighbours.is_empty():
		reqs.append({"id": "neighbours", "kind": "neighbours_safe"})
	reqs.append({"id": "charges", "kind": "charge_budget", "value": charges})
	reqs.append({"id": "budget", "kind": "budget"})
	var goals: Array = [
		{"id": "tidy", "kind": "debris_within_plot", "value": outside * 0.25, "bonus": snappedf(fee * 0.06, 500.0)},
		{"id": "frugal", "kind": "charge_budget", "value": ceili(charges * 0.6), "bonus": snappedf(fee * 0.05, 500.0)},
	]
	var b := {
		"id": "demolish-%s-%d" % [type if type != "" else str(record.get("id", "own")), seed], "mode": MODE,
		"title": title.left(1).to_upper() + title.substr(1), "type": type, "client": client, "summary": summary, "seed": seed,
		"budget": budget, "fee": fee, "deadline_days": 20 + tier * 5, "tier": tier, "xp": xp,
		"requirements": reqs, "goals": goals, "target": target, "neighbours": neighbours, "volume": snappedf(volume, 1.0),
		"site": {"id": str((record.get("site", {}) as Dictionary).get("id", "")) if record.get("site") is Dictionary else "",
				"name": "the old building's plot", "plot": plot, "rating": 1, "soil": "", "area": (hi.x - lo.x) * (hi.y - lo.y),
				"w": hi.x - lo.x, "d": hi.y - lo.y, "factors": []},
	}
	if record.has("id"):
		b["record_id"] = str(record.id)
	return b


## An old w x d building of `storeys`: strip footings and masonry walls round it, concrete
## columns on pads inside when it is wide, concrete floors, a flat roof; every part locked.
static func old_building(w: float, d: float, storeys: int, building_name: String) -> Dictionary:
	var C := BuildingCommands
	var m := BuildingModel.new("", building_name)
	for i in storeys - 1:
		m.apply(C.add_level(STOREY_M))
	var x0 := -w / 2.0
	var z0 := -d / 2.0
	var corners := [[x0, 0.0, z0], [x0 + w, 0.0, z0], [x0 + w, 0.0, z0 + d], [x0, 0.0, z0 + d]]
	var cols: Array = []
	var nx := int(floor(w / 6.0))
	var nz := int(floor(d / 6.0))
	for i in range(1, nx):
		for j in range(1, nz):
			cols.append([x0 + w * float(i) / float(nx), z0 + d * float(j) / float(nz)])
	for lv in storeys:
		for side in 4:
			if lv == 0:
				m.apply(C.place_part("strip_footing", 0, {"a": corners[side], "b": corners[(side + 1) % 4]}))
			var r := m.apply(C.place_part("wall_loadbearing", lv, {"a": corners[side], "b": corners[(side + 1) % 4]}, "masonry"))
			if lv == 0 and side == 0 and not r.is_empty():
				m.apply(C.place_opening("door_external", str(r.do.entry.id), w * 0.5))
		for c: Array in cols:
			if lv == 0:
				m.apply(C.place_part("pad_footing", 0, {"at": [c[0], 0.0, c[1]]}))
			m.apply(C.place_part("column", lv, {"at": [c[0], 0.0, c[1]]}, "concrete"))
		m.apply(C.place_part("slab", lv, {"outline": C.rect(x0, z0, w, d)}, "concrete"))
	m.apply(C.place_part("roof_flat", storeys - 1, {"outline": C.rect(x0, z0, w, d), "y": STOREY_M}, "concrete"))
	var data := m.to_data()
	for e: Dictionary in data.get("parts", []):
		e["locked"] = true
	return data


## The old building as BuildingModel data (for BuildingSync.load_design).
static func target_design(brief: Dictionary) -> Dictionary:
	var t: Variant = brief.get("target")
	return (t as Dictionary).duplicate(true) if t is Dictionary else {}


## Options for DemolitionBus.start_from_model: the plot and the neighbours to protect.
static func start_options(brief: Dictionary) -> Dictionary:
	var plot := PackedVector2Array()
	var site: Dictionary = brief.get("site", {}) if brief.get("site") is Dictionary else {}
	for p: Variant in site.get("plot", []):
		plot.append(Vector2(float(p[0]), float(p[1])))
	var boxes: Array = []
	for n: Variant in brief.get("neighbours", []):
		if n is Array and (n as Array).size() == 6:
			boxes.append(AABB(Vector3(float(n[0]), float(n[1]), float(n[2])), Vector3(float(n[3]), float(n[4]), float(n[5]))))
	return {"plot": plot, "neighbours": boxes}


## What the job costs: the crew, the charges fired, clearing what fell off the plot.
static func cost(brief: Dictionary, result: Dictionary) -> float:
	return float(brief.get("volume", 0.0)) * CREW_PER_M3 + int(result.get("charges_used", 0)) * CHARGE_COST \
			+ float(result.get("debris_outside_m3", 0.0)) * CLEANUP_PER_M3


## The job judged on a demolition result, in ContractValidator.assess's shape. An empty
## result (nothing fired yet) fails every requirement with a tip to fire.
static func assess(brief: Dictionary, result: Dictionary) -> Dictionary:
	var b := ContractBrief.normalize(brief)
	var spent := cost(brief, result) if not result.is_empty() else float(brief.get("volume", 0.0)) * CREW_PER_M3
	var items: Array = []
	var passed := 0
	var total := 0
	var bonus := 0.0
	for key: String in ["requirements", "goals"]:
		for req: Dictionary in b.get(key, []):
			var it := check(req, result, spent, float(b.budget))
			it["hard"] = key == "requirements"
			it["bonus"] = float(req.get("bonus", 0.0)) if key == "goals" else 0.0
			items.append(it)
			if key == "requirements":
				total += 1
				passed += 1 if it.ok else 0
			elif it.ok:
				bonus += float(it.bonus)
	var out := {"ok": passed == total and not result.is_empty(), "items": items, "passed": passed, "total": total, "bonus": bonus,
			"cost": spent, "budget": float(b.budget), "totals": {}}
	out["summary"] = "Plan the charges and fire them: the job is judged on how the building comes down." if result.is_empty() \
			else ("Everything the client asked for." if out.ok else "Not yet: " + ", ".join(PackedStringArray(
				items.filter(func(i: Dictionary) -> bool: return i.hard and not i.ok).map(func(i: Dictionary) -> String: return str(i.label).to_lower()))) + ".")
	return out


static func check(req: Dictionary, result: Dictionary, spent: float, budget: float) -> Dictionary:
	var out := {"id": str(req.get("id", "")), "kind": str(req.get("kind", "")), "label": ContractBrief.describe(req),
			"ok": false, "progress": 0.0, "detail": "", "tip": ""}
	var v := float(req.get("value", 0.0))
	var fired := not result.is_empty()
	match out.kind:
		"demolition_collapse":
			var down := float(result.get("collapsed", 0.0))
			out.ok = fired and down + 0.0005 >= v
			out.progress = clampf(down / maxf(v, 0.01), 0.0, 1.0)
			out.detail = "%d%% brought down." % roundi(down * 100.0) if fired else "Not fired yet."
			out.tip = "" if out.ok else "Charge the columns and walls low down, so what is above loses its support."
		"debris_within_plot":
			var off := float(result.get("debris_outside", 0.0))
			out.ok = fired and off <= v + 0.0005
			out.progress = 0.0 if not fired else (1.0 if out.ok else clampf(v / maxf(off, 0.001), 0.0, 1.0))
			out.detail = "%d%% of the debris landed off the plot (%.0f m3)." % [roundi(off * 100.0), float(result.get("debris_outside_m3", 0.0))] if fired else "Not fired yet."
			out.tip = "" if out.ok else "Fire the middle first so the building falls in on itself (the implode preset)."
		"neighbours_safe":
			var hits := int(result.get("neighbours_hit", 0))
			out.ok = fired and hits == 0
			out.progress = 1.0 if out.ok else 0.0
			out.detail = ("No neighbour touched." if hits == 0 else "%d neighbour%s hit." % [hits, "" if hits == 1 else "s"]) if fired else "Not fired yet."
			out.tip = "" if out.ok else "Fell it away from the neighbours: fire the side next to them last."
		"charge_budget":
			var used := int(result.get("charges_used", 0))
			out.ok = fired and used <= int(v)
			out.progress = 0.0 if not fired else (1.0 if out.ok else clampf(v / maxf(float(used), 1.0), 0.0, 1.0))
			out.detail = "%d of %d charges." % [used, int(v)] if fired else "Not fired yet."
			out.tip = "" if out.ok else "Charge only the parts that carry the rest; what they hold up will follow."
		"budget":
			out.ok = fired and spent <= budget + 0.5
			out.progress = 1.0 if out.ok else clampf(budget / maxf(spent, 1.0), 0.0, 1.0)
			out.detail = "The job costs %s of %s." % [ContractValidator.money(spent), ContractValidator.money(budget)]
			out.tip = "" if out.ok else "Use fewer charges and keep the debris on the plot: clearing it off the street is dear."
	return out


static func _box(m: BuildingModel) -> AABB:
	var box := AABB()
	var first := true
	for pid in BuildingModel.sort_ids(m.parts.keys()):
		var a := m.aabb_of(pid)
		if a.size == Vector3.ZERO:
			continue
		box = a if first else box.merge(a)
		first = false
	return box
