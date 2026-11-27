class_name ContractBrief
extends RefCounted
## A contract brief is plain data (a Dictionary), so the host can send it, a save can hold
## it and a generator can roll it. This class holds the format, the hand-written briefs and
## the wording of each requirement.
##
##   {id, title, type (building type), client, summary,
##    budget (GBP the client will let the build cost), fee (GBP paid on handover),
##    deadline_days, tier (the firm tier that is offered it, ContractTiers), xp (earned on
##    a passed handover),
##    site?: {plot: [[x, z], ...]}           # the plot the building must stay inside
##    requirements: [requirement, ...],      # hard: all must pass to be paid
##    goals: [requirement + {bonus}, ...]}   # soft: each one met pays its bonus
##
## Requirements (every one has an id and a kind; ContractValidator checks them):
##   rooms            {type, count, capacity? (each room), min_area? (else the type's)}
##   double_bedroom   {count}                      bedrooms of 11.5 m2 or more
##   capacity         {types: [...], value}        total occupants across those rooms
##   floor_area       {min?, max?}                 m2 of rooms
##   max_storeys      {value}
##   max_height       {value}                      m above ground to the highest part
##   max_footprint    {value}                      m2 of rooms on the ground floor
##   within_plot      {}                           every part and room inside site.plot
##   budget           {share? (1.0)}               build cost <= budget * share
##   parts            {kinds: [...], count, level?}
##   accessible_entrance {}                        an accessible or double door on the ground floor
##   vehicle_access   {}                           a vehicle door on the ground floor
##   secure_cells     {}                           a secure door for every custody cell
##   near             {a, b, value}                every room of type a within value m of a b
##   exit_distance    {value}                      every room within value m of a way out
##   lift_if_storeys  {}                           a lift on every floor, if more than one
##   structure        {}                           passed the structural stress test

const BRIEFS_SCRIPT := preload("res://modules/contracts/internal/briefs.gd")


## The hand-written briefs (house, school, police station), as copies.
static func authored() -> Array:
	return (BRIEFS_SCRIPT.BRIEFS as Array).duplicate(true)


static func authored_brief(brief_id: String) -> Dictionary:
	for b: Dictionary in BRIEFS_SCRIPT.BRIEFS:
		if str(b.id) == brief_id:
			return b.duplicate(true)
	return {}


## A brief with every field present and numbers as numbers ({} if it is not a brief).
static func normalize(brief: Variant) -> Dictionary:
	if not brief is Dictionary or str((brief as Dictionary).get("id", "")) == "":
		return {}
	var b: Dictionary = (brief as Dictionary).duplicate(true)
	var out := {
		"id": str(b.id), "title": str(b.get("title", b.id)), "type": str(b.get("type", "")),
		"client": str(b.get("client", "")), "summary": str(b.get("summary", "")),
		"budget": float(b.get("budget", 0.0)), "fee": float(b.get("fee", 0.0)),
		"deadline_days": int(b.get("deadline_days", 0)),
		"tier": clampi(int(b.get("tier", 1)), 1, ContractTiers.top()),
		"xp": maxi(0, int(b.get("xp", 0))),
		"requirements": [], "goals": [],
	}
	if b.get("site") is Dictionary:
		out["site"] = b.site
	for key: String in ["requirements", "goals"]:
		var n := 0
		for r: Variant in b.get(key, []):
			if r is Dictionary and str((r as Dictionary).get("kind", "")) != "":
				n += 1
				var req: Dictionary = (r as Dictionary).duplicate(true)
				if str(req.get("id", "")) == "":
					req["id"] = "%s%d" % [key.left(1), n]
				out[key].append(req)
	return out


## One line saying what a requirement asks for, in the player's words.
static func describe(req: Dictionary, catalog: BuildingCatalog = null) -> String:
	var cat := catalog if catalog != null else BuildingCatalog.default_catalog()
	var v := float(req.get("value", 0.0))
	match str(req.get("kind", "")):
		"rooms":
			var n := int(req.get("count", 1))
			var label := room_label(str(req.get("type", "")), cat, n)
			var cap := int(req.get("capacity", 0))
			if cap > 1:
				return "%d %s for %d each" % [n, label, cap] if n != 1 else "%s %s for %d" % [article(label).capitalize(), label, cap]
			return "%d %s" % [n, label] if n != 1 else "%s %s" % [article(label).capitalize(), label]
		"double_bedroom":
			return "At least %d double bedroom (11.5 m2 or more)" % int(req.get("count", 1))
		"capacity":
			return "Room for %d people" % int(v)
		"floor_area":
			if req.has("min") and req.has("max"):
				return "Between %d and %d m2 of rooms" % [int(req.min), int(req.max)]
			return "At least %d m2 of rooms" % int(req.get("min", 0)) if req.has("min") else "No more than %d m2 of rooms" % int(req.get("max", 0))
		"max_storeys":
			return "No more than %d storeys" % int(v) if int(v) != 1 else "A single storey"
		"max_height":
			return "No taller than %.0f m" % v
		"max_footprint":
			return "A ground floor of no more than %.0f m2" % v
		"within_plot":
			return "Keep inside the plot boundary"
		"budget":
			var share := float(req.get("share", 1.0))
			return "Build cost within budget" if share >= 1.0 else "Come in %d%% under budget" % roundi((1.0 - share) * 100.0)
		"parts":
			return "%d x %s" % [int(req.get("count", 1)), ", ".join(PackedStringArray(req.get("kinds", [])))]
		"accessible_entrance":
			return "An accessible entrance"
		"vehicle_access":
			return "A vehicle door into the building"
		"secure_cells":
			return "A secure door on every custody cell"
		"near":
			return "Every %s within %.0f m of the %s" % [room_label(str(req.a), cat, 1), v, room_label(str(req.b), cat, 1)]
		"exit_distance":
			return "A way out within %.0f m of every room" % v
		"lift_if_storeys":
			return "A lift to every floor (if more than one)"
		"structure":
			return "Passes the structural stress test"
	return str(req.get("kind", ""))


## "a" or "an" for a word.
static func article(word: String) -> String:
	return "an" if word.left(1).to_lower() in ["a", "e", "i", "o", "u"] else "a"


## A room type's name, lower case, made plural for n other than 1.
static func room_label(type: String, catalog: BuildingCatalog, n: int) -> String:
	var label := str(catalog.room_type(type).get("label", type)).to_lower()
	if n == 1:
		return label
	if label.ends_with("ss") or label.ends_with("ch") or label.ends_with("sh"):
		return label + "es"
	if label.ends_with("s"):
		return label
	if label.ends_with("y") and not label.ends_with("ay"):
		return label.left(-1) + "ies"
	return label + "s"
