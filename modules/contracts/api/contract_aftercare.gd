class_name ContractAftercare
extends RefCounted
## After the handover (flag contracts.aftercare): some time after a building is handed over,
## the weather, the years or the crowds test it again. Heavy snow, a storm harder than the
## handover test, ten years of ageing, or heavy use; a flat roof can start to leak. The host
## judges it at the handover (it still has the building) and the news lands with the next
## handover: a thank-you bonus and XP when it held, a call-back to repair it, at the firm's
## cost, and a warier client when it did not.
##
##   var ev := ContractAftercare.judge(brief, model)   # host, at handover: {} for none
##   ContractAftercare.text(ev)                         # the news, one or two sentences
##
## An event: {brief_id, title, client, event, label, ok, failed (part labels), leak, bonus,
## repair, xp}.

const FLAG := "contracts.aftercare"
## The share of passed handovers that get a later event.
const CHANCE := 0.7
const EVENTS := [
	{"id": "heavy_snow", "label": "Heavy snow", "scenario": "heavy_snow",
		"held": "The worst snow in years sat on the roof of %s for a week, and it held.",
		"failed": "The worst snow in years came down on %s, and %s gave way."},
	{"id": "storm", "label": "A big storm", "scenario": "storm*1.3",
		"held": "A storm harder than anything in the handover test hit %s, and it rode it out.",
		"failed": "A storm harder than anything in the handover test hit %s, and %s failed."},
	{"id": "ten_years", "label": "Ten years on", "scenario": "ten_years",
		"held": "Ten years on, %s is wearing well: the survey found nothing to put right.",
		"failed": "Ten years on, the survey of %s found %s no longer up to the job."},
	{"id": "heavy_use", "label": "Packed out", "scenario": "heavy_use",
		"held": "%s was packed far fuller than it was designed for, and nothing so much as creaked.",
		"failed": "%s was packed far fuller than it was designed for, and %s failed."},
]
## When it held: this share of the fee as a thank-you, and of the brief's XP.
const BONUS_SHARE := 0.03
const XP_SHARE := 0.1
## A call-back costs this many times the failed parts' build cost (scaffold, making good).
const REPAIR_FACTOR := 2.0
## A flat roof's repair after ten years: this share of the roof's cost.
const LEAK_SHARE := 0.4
## A call-back never costs more than this share of the fee.
const MAX_REPAIR_SHARE := 0.25
const LEAK_CHANCE := 0.5


## Host: the later event for a passed handover of `brief`, judged on `model` now. {} when
## the roll gives none, the flag is off or it is a demolition. force: an event id (tests).
static func judge(brief: Dictionary, model: BuildingModel, force := "") -> Dictionary:
	if force == "" and (not Flags.is_on(FLAG) or ContractDemolition.is_demolition(brief)):
		return {}
	if model == null or model.parts.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(brief.get("seed", 0)), str(brief.get("id", "")), "aftercare"])
	var ev: Dictionary = {}
	if force != "":
		for e: Dictionary in EVENTS:
			if str(e.id) == force:
				ev = e
	elif rng.randf() < CHANCE:
		ev = EVENTS[rng.randi_range(0, EVENTS.size() - 1)]
	if ev.is_empty():
		return {}
	var title := str(brief.get("title", "the building"))
	var out := {"brief_id": str(brief.get("id", "")), "title": title, "client": str(brief.get("client", "")),
			"event": str(ev.id), "label": str(ev.label), "ok": true, "failed": [], "leak": false, "bonus": 0.0, "repair": 0.0, "xp": 0}
	var sc := StructureScenario.by_id(str(ev.scenario))
	var report := StructureBuilding.stress_test(model, [sc] as Array[StructureScenario])
	var failed := report.failed_parts()
	var repair := 0.0
	var names := {}
	for pid in failed:
		if not model.has(pid):
			continue
		repair += float(BuildingQuantities.part(model, pid).get("cost", 0.0))
		names[str(model.catalog.kind(str(model.parts[pid].kind)).get("label", "a part")).to_lower()] = true
	# The years find out a flat roof.
	if str(ev.id) == "ten_years":
		for pid in model.parts_of_family("roof"):
			if str(model.parts[pid].kind) == "roof_flat" and rng.randf() < LEAK_CHANCE:
				out.leak = true
				repair += _area_cost(model, pid) * LEAK_SHARE
				break
	if failed.is_empty() and not out.leak:
		out.bonus = snappedf(float(brief.get("fee", 0.0)) * BONUS_SHARE, 100.0)
		out.xp = roundi(int(brief.get("xp", 0)) * XP_SHARE)
		return out
	out.ok = false
	var labels: Array = names.keys()
	labels.sort()
	out.failed = labels
	if repair <= 0.0 and not failed.is_empty():
		repair = float(brief.get("fee", 0.0)) * 0.05
	out.repair = snappedf(minf(repair * (REPAIR_FACTOR if not failed.is_empty() else 1.0), float(brief.get("fee", 0.0)) * MAX_REPAIR_SHARE), 100.0)
	return out


## The news of an event, as the settlement shows it.
static func text(ev: Dictionary) -> String:
	if ev.is_empty():
		return ""
	var row: Dictionary = {}
	for e: Dictionary in EVENTS:
		if str(e.id) == str(ev.event):
			row = e
	var title := str(ev.title)
	var name := title if title.begins_with("The ") else "the " + title.to_lower()
	if bool(ev.ok):
		var s := (str(row.held) % name) if str(row.held).count("%s") == 1 else str(row.held)
		return "News from %s: %s %s thank you: +%s and +%s." % [_who(ev), s.left(1).to_upper() + s.substr(1),
				_they(ev), ContractValidator.money(float(ev.bonus)), ContractTiers.xp_text(int(ev.xp))]
	var lines := PackedStringArray()
	if not (ev.failed as Array).is_empty():
		var parts := PackedStringArray(ev.failed)
		var what := parts[0] if parts.size() == 1 else ", ".join(parts.slice(0, parts.size() - 1)) + " and " + parts[-1]
		var s := str(row.failed) % [name, "the " + what]
		lines.append(s.left(1).to_upper() + s.substr(1))
	if bool(ev.leak):
		lines.append("The flat roof of %s has started to leak." % name)
	lines.append("%s called the firm back: the repairs cost %s." % [_who(ev).left(1).to_upper() + _who(ev).substr(1), ContractValidator.money(float(ev.repair))])
	if not (ev.failed as Array).is_empty():
		lines.append("Next time, run the stress test before handover and let the engineer fix what fails.")
	elif bool(ev.leak):
		lines.append("A pitched roof sheds water for longer.")
	return "News: " + " ".join(lines)


static func _who(ev: Dictionary) -> String:
	var c := str(ev.get("client", ""))
	return c if c != "" else "the client"


static func _they(ev: Dictionary) -> String:
	return "%s send%s their" % [_who(ev), "" if _who(ev).ends_with("family") or _who(ev).begins_with("Mr and") else "s"]


static func _area_cost(model: BuildingModel, pid: String) -> float:
	return float(BuildingQuantities.part(model, pid).get("cost", 0.0))
