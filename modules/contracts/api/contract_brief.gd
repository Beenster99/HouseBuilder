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
##    site?: {plot: [[x, z], ...], w, d, area, name, rating}   # the plot to stay inside
##    floor_area?: m2 of rooms to aim for (generated briefs)
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
##   materials        {allowed: [material, ...]}   every structural part in one of these (glass aside)
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
## Requirements every brief has, added by normalize() where a brief leaves them out: a
## building with no roof, open sides or no foundations is never finished.
const BASE_REQUIREMENTS := [
	{"id": "weathertight", "kind": "weathertight"},
	{"id": "foundations", "kind": "foundations"},
]


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
	if b.has("floor_area"):
		out["floor_area"] = float(b.floor_area)
	if str(b.get("mode", "")) != "":
		out["mode"] = str(b.mode)
	for key: String in ["requirements", "goals"]:
		var n := 0
		for r: Variant in b.get(key, []):
			if r is Dictionary and str((r as Dictionary).get("kind", "")) != "":
				n += 1
				var req: Dictionary = (r as Dictionary).duplicate(true)
				if str(req.get("id", "")) == "":
					req["id"] = "%s%d" % [key.left(1), n]
				out[key].append(req)
	# Every building needs these, whatever the brief says.
	var reqs: Array = out.requirements
	var at := reqs.size()
	for i in reqs.size():
		if str(reqs[i].kind) == "budget":
			at = i
			break
	for base: Dictionary in BASE_REQUIREMENTS if str(out.get("mode", "")) == "" else []:
		if not reqs.any(func(r: Dictionary) -> bool: return str(r.kind) == str(base.kind)):
			reqs.insert(at, base.duplicate())
			at += 1
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
			var size := ""
			if req.has("min_area"):
				size = " of at least %s m2%s" % [_num(float(req.min_area)), " each" if n != 1 else ""]
			if cap > 1:
				return ("%d %s for %d each" % [n, label, cap] if n != 1 else "%s %s for %d" % [article(label).capitalize(), label, cap]) + size
			return ("%d %s" % [n, label] if n != 1 else "%s %s" % [article(label).capitalize(), label]) + size
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
			return "No taller than %s m" % _num(v)
		"max_footprint":
			return "A ground floor of no more than %s m2" % _num(v)
		"within_plot":
			return "Keep inside the plot boundary"
		"weathertight":
			return "A roof over every room and walls round it"
		"foundations":
			return "Foundations under every ground-floor wall and column"
		"raised_floor":
			return "Ground floor at least %s m above the ground, no bedrooms on it" % _num(v)
		"boundary_gap":
			return "Nothing within %s m of the boundary" % _num(v)
		"column_free":
			return "No columns inside the ground-floor rooms"
		"keep_existing":
			return "Keep %s as it is" % str(req.get("what", "the existing building"))
		"demolition_collapse":
			return "At least %d%% of the building brought down" % roundi(v * 100.0)
		"debris_within_plot":
			return "No more than %d%% of the debris off the plot" % roundi(v * 100.0)
		"neighbours_safe":
			return "The neighbouring buildings untouched"
		"charge_budget":
			return "No more than %d charges" % int(v)
		"foundation_type":
			var ws := PackedStringArray()
			for k: Variant in req.get("allowed", []):
				ws.append(str(cat.kind(str(k)).get("label", k)).to_lower() + "s")
			return "Foundations of %s only" % " or ".join(ws)
		"materials":
			return "Structure in %s" % material_list(PackedStringArray(req.get("allowed", [])))
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
			return "A secure door on every %s" % room_label(str(req.get("type", "custody_cell")), cat, 1)
		"near":
			return "Every %s within %.0f m of the %s" % [room_label(str(req.a), cat, 1), v, room_label(str(req.b), cat, 1)]
		"exit_distance":
			return "A way out within %.0f m of every room" % v
		"lift_if_storeys":
			return "A lift to every floor (if more than one)"
		"structure":
			return "Passes the structural stress test"
	return str(req.get("kind", ""))


## The brief's dimensions and materials, one line each, for the panel and the wall screen:
## the plot, the building's limits, the floor area to aim for, each room's size and the
## structure's materials.
static func spec_lines(brief: Dictionary, catalog: BuildingCatalog = null) -> PackedStringArray:
	var cat := catalog if catalog != null else BuildingCatalog.default_catalog()
	var out := PackedStringArray()
	var site: Dictionary = brief.get("site", {}) if brief.get("site") is Dictionary else {}
	if site.has("plot"):
		var w := float(site.get("w", 0.0))
		var d := float(site.get("d", 0.0))
		var size := "%s x %s m, " % [_num(w), _num(d)] if w > 0.0 and d > 0.0 else ""
		var line := "Plot: %s%s m2, %s" % [size, _num(roundf(float(site.get("area", w * d)))), str(site.get("name", "the plot"))]
		if int(site.get("rating", 1)) > 1:
			line += " (difficulty %d of 5)" % int(site.rating)
		out.append(line + ".")
	var limits := PackedStringArray()
	var rooms := PackedStringArray()
	var mats := ""
	for r: Dictionary in brief.get("requirements", []):
		var v := float(r.get("value", 0.0))
		match str(r.get("kind", "")):
			"max_storeys":
				limits.append("%d storey%s" % [int(v), "" if int(v) == 1 else "s"])
			"max_height":
				limits.append("%s m tall" % _num(v))
			"max_footprint":
				limits.append("%s m2 of rooms on the ground floor" % _num(v))
			"floor_area":
				limits.append(describe(r, cat).to_lower())
			"rooms":
				var each := float(r.get("min_area", cat.room_type(str(r.type)).get("min_area", 0.0)))
				var n := int(r.get("count", 1))
				var cap := int(r.get("capacity", 0))
				rooms.append("%d %s, %s m2+%s%s" % [n, room_label(str(r.type), cat, n), _num(each), " each" if n != 1 else "",
						" for %d" % cap if cap > 1 else ""])
			"double_bedroom":
				var dn := int(r.get("count", 1))
				rooms.append("%d double bedroom%s, 11.5 m2+" % [dn, "" if dn == 1 else "s"])
			"materials":
				mats = "Structure: %s (glazing is always allowed)." % material_list(PackedStringArray(r.get("allowed", [])))
	if not limits.is_empty():
		out.append("Building: at most %s." % ", ".join(limits))
	if float(brief.get("floor_area", 0.0)) > 0.0:
		out.append("Floor area: about %s m2 of rooms in all." % _num(float(brief.floor_area)))
	if not rooms.is_empty():
		out.append("Rooms: %s." % "; ".join(rooms))
	if mats != "":
		out.append(mats)
	return out


## Plain words for a material ("brick and block" for masonry).
static func material_word(m: String) -> String:
	return str({"masonry": "brick and block", "concrete": "reinforced concrete", "glulam": "glulam timber"}.get(m, m))


## "timber, brick and block or steel".
static func material_list(mats: PackedStringArray) -> String:
	var words := PackedStringArray()
	for m in mats:
		words.append(material_word(m))
	if words.size() <= 1:
		return "".join(words)
	return ", ".join(words.slice(0, words.size() - 1)) + " or " + words[words.size() - 1]


static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


## "a" or "an" for a word.
static func article(word: String) -> String:
	var w := word.to_lower()
	for c: String in ["uni", "uti", "use", "usu", "eu", "one"]:
		if w.begins_with(c):
			return "a"
	return "an" if w.left(1) in ["a", "e", "i", "o", "u"] else "a"


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
