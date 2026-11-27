class_name ContractBriefing
extends RefCounted
## The client's briefing document for a contract: who the client is and why they are
## building, what to build (type, storeys, height, floor area, every room and its size),
## the money and the time, the site and what each of its problems means for the design,
## the materials, the bonus goals and how the handover will be judged.
##
##   ContractBriefing.sections(brief)          # [{title, lines: [String]}] in plain words
##   ContractBriefing.bbcode(brief, muted_hex)  # the whole document for a RichTextLabel
##   ContractBriefing.story(brief)              # the client's paragraph
##   ContractBriefing.site_advice(factor_id)    # what a site problem means for the design
##
## Real-site facts (location, slope, access, existing buildings) come from the site pack
## named by brief.site.id; a brief without one describes its plain plot.

## Who the client is and why they want it, by category, with {client}, {type} (the building
## type, lower case) and {site} (the site's name). Picked by the brief's seed.
const STORIES := {
	"domestic": [
		"{client} have outgrown where they live and have saved hard for this. They want a {type} on {site} that is warm, light and easy to live in, with every room a usable size. They are not builders and are trusting you to tell them what will work.",
		"{client} have bought {site} and want a {type} there that will see them through the next twenty years. They care about the money: a design that comes in under budget will be remembered.",
	],
	"education": [
		"{client} need more places for local children and have funding for a {type} on {site}. Pupils and staff must be able to get out quickly and safely, and everyone must be able to get in, whatever their mobility.",
		"{client} are replacing worn-out temporary classrooms with a permanent {type} on {site}. The governors will check the room sizes against the numbers on the roll.",
	],
	"civic": [
		"{client} have won a grant for a {type} on {site} for local groups to use. It must be open to everyone, cheap to run and finished before the grant runs out.",
		"{client} want a {type} on {site} to replace a building that was past saving. The community has been consulted and knows what it wants; the rooms below are what it asked for.",
	],
	"police": [
		"{client} are consolidating two old stations into a new {type} on {site}. Custody has to meet the rules to the letter: secure cells close to the custody desk, and vehicles straight into the building.",
	],
	"office": [
		"{client} want a {type} on {site} to let to growing local firms. Lettable floor space pays the bills, so the plan should be efficient, with lifts and stairs that serve every floor.",
	],
	"health": [
		"{client} need a {type} on {site} to bring care closer to patients. Wide doors, level access and short routes matter more here than anywhere else.",
	],
	"housing": [
		"{client} {are} building homes for local people who cannot find anywhere to live. They want a {type} on {site}: every home a decent size, with its own front door or a safe, short way to it.",
	],
	"retail": [
		"{client} {are} opening a {type} on {site}. Shoppers have to find their way in easily, deliveries have to get to the stockrooms, and the shop floors must be big enough to trade from.",
	],
	"hospitality": [
		"{client} {are} betting on visitors and want a {type} on {site} that guests will come back to. Comfortable rooms, a kitchen that can keep up, and a warm welcome at the door.",
	],
	"leisure": [
		"{client} {are} bringing culture back to town with a {type} on {site}. Hundreds of people will arrive at once and leave at once, so the foyer, the exits and the sight lines all matter.",
	],
	"justice": [
		"{client} need a {type} on {site}. Security comes first: the public, staff and people in custody must never meet where they should not, and every cell needs a secure door.",
	],
	"industrial": [
		"{client} {are} expanding and need a {type} on {site}: a big, clear floor, wide doors for lorries and somewhere sensible for the office staff. Cheap to build counts.",
	],
	"transport": [
		"{client} are expanding with a new {type} on {site}. Passenger numbers are growing every year; the building must move people through quickly and stand up to heavy use.",
	],
}

## What a site problem (SitePack factor id) means for the design and the build.
const SITE_ADVICE := {
	"flood": "Raise the ground floor above the flood level and keep plant and sockets high. Expect a heavier, raised slab.",
	"neighbours": "Keep every wall inside the boundary and dig carefully along it: foundations next to a neighbour need care, and demolition must not touch their buildings.",
	"ground_wet": "Raise the ground floor clear of the wet ground on a suspended slab, keep plant and sockets high, and expect piles or a raft rather than shallow footings.",
	"ground": "Expect deeper foundations than usual. The structural engineer sizes them from the soil; poor ground may need piles or a raft once your firm has them.",
	"shape": "Fit the rooms to the plot's outline (the orange line). An L or a stepped plan may use it better than a simple box.",
	"slope": "Step the floors with the ground, or cut a level platform and allow for retaining walls. Put the entrance on the level side.",
	"access": "Deliveries and cranes will be limited, which slows the build and adds cost. Keep the building simple to construct and put the entrance on the side you can reach.",
	"right_of_way": "A road or path crosses the plot and must stay open: do not build across it.",
	"existing_buildings": "The buildings on the plot must be demolished and cleared before work starts, and that is part of the cost.",
	"heritage": "Protected buildings stand nearby. They must not be damaged, and a modest height and careful demolition will keep the planners happy.",
	"trees": "Protected trees must stay: keep the building and its foundations clear of their roots.",
	"railway": "Trains pass close by: expect vibration and noise, keep a gap from the line and put quiet rooms on the far side.",
	"overhead_lines": "Keep the building and cranes well clear of the lines, or the work stops while they are moved.",
}

const _GENERIC_ADVICE := "Allow for it in the design and the cost."

static var _packs := {}


## The client's paragraph for a brief.
static func story(brief: Dictionary) -> String:
	var spec: Dictionary = ContractGenerator.TYPES.get(str(brief.get("type", "")), {})
	if spec.is_empty() and str(brief.get("summary", "")) != "":
		return str(brief.summary)
	var cat := str(spec.get("category", "domestic"))
	var label := str(spec.get("label", brief.get("title", "building"))).to_lower()
	var site := _site(brief)
	var where := str(site.get("name", "the plot"))
	var options: Array = STORIES.get(cat, STORIES.domestic)
	var seed := int(brief.get("seed", 0))
	var tpl := str(options[absi(seed) % options.size()])
	var client := str(brief.get("client", "The client"))
	var plural := client.begins_with("The ") and (client.ends_with("family") or client.ends_with("s")) or client.begins_with("Mr and")
	var text := tpl.format({"client": client, "type": label, "site": where, "are": "are" if plural else "is"})
	var pack := _pack_of(brief)
	if pack != null and pack.description() != "":
		text += " About the site: " + pack.description()
	return text


## What a site problem means for the design.
static func site_advice(factor_id: String) -> String:
	return str(SITE_ADVICE.get(factor_id, _GENERIC_ADVICE))


## The document as titled sections of plain lines.
static func sections(brief: Dictionary, catalog: BuildingCatalog = null) -> Array:
	var cat := catalog if catalog != null else BuildingCatalog.default_catalog()
	var out: Array = []
	var spec: Dictionary = ContractGenerator.TYPES.get(str(brief.get("type", "")), {})
	out.append({"title": "The client", "lines": [story(brief)]})
	out.append({"title": "What to build", "lines": _build_lines(brief, spec, cat)})
	out.append({"title": "Rooms", "lines": _room_lines(brief, cat)})
	out.append({"title": "Money and time", "lines": _money_lines(brief)})
	out.append({"title": "The site", "lines": _site_lines(brief)})
	var cons := _constraint_lines(brief)
	if not cons.is_empty():
		out.append({"title": "Site constraints and what they mean for the design", "lines": cons})
	out.append({"title": "Materials", "lines": _material_lines(brief)})
	var goals := PackedStringArray()
	for g: Dictionary in brief.get("goals", []):
		goals.append("%s: +%s" % [ContractBrief.describe(g, cat), ContractValidator.money(float(g.get("bonus", 0.0)))])
	if not goals.is_empty():
		out.append({"title": "Bonus goals", "lines": goals})
	out.append({"title": "How it will be judged", "lines": _judging_lines(brief, cat)})
	return out


## The whole document as BBCode: muted is the hex colour for secondary text.
static func bbcode(brief: Dictionary, muted: String = "888888", catalog: BuildingCatalog = null, title_size: int = 20) -> String:
	var lines := PackedStringArray()
	lines.append("[font_size=%d][b]%s[/b][/font_size]" % [title_size, _esc(str(brief.get("title", "Contract")))])
	lines.append("[color=#%s]Briefing for the design team · %s · tier %d · %s[/color]" % [muted,
			_esc(str(brief.get("client", ""))), int(brief.get("tier", 1)), ContractTiers.xp_text(int(brief.get("xp", 0)))])
	for s: Dictionary in sections(brief, catalog):
		lines.append("")
		lines.append("[b]%s[/b]" % _esc(str(s.title)))
		var ls: Array = Array(s.lines)
		for i in ls.size():
			var l := str(ls[i])
			var plain := str(s.title) == "The client" or (l.length() > 1 and l.left(1).is_valid_int())
			lines.append(_esc(l) if plain else "• " + _esc(l))
	return "\n".join(lines)


## The whole document as plain text (tests, logs).
static func text(brief: Dictionary, catalog: BuildingCatalog = null) -> String:
	var lines := PackedStringArray([str(brief.get("title", "Contract"))])
	for s: Dictionary in sections(brief, catalog):
		lines.append("")
		lines.append(str(s.title))
		for l: Variant in s.lines:
			lines.append(str(l))
	return "\n".join(lines)


static func _build_lines(brief: Dictionary, spec: Dictionary, cat: BuildingCatalog) -> PackedStringArray:
	var out := PackedStringArray()
	var storeys := 0
	var height := 0.0
	var footprint := 0.0
	var musts := PackedStringArray()
	for r: Dictionary in brief.get("requirements", []):
		var v := float(r.get("value", 0.0))
		match str(r.get("kind", "")):
			"max_storeys":
				storeys = int(v)
			"max_height":
				height = v
			"max_footprint":
				footprint = v
			"rooms", "double_bedroom", "materials", "within_plot", "budget":
				pass
			_:
				musts.append(ContractBrief.describe(r, cat))
	var what := str(spec.get("label", brief.get("title", "A building")))
	var line := "Building: %s %s" % [ContractBrief.article(what).capitalize(), what.to_lower()]
	if storeys > 0:
		line += ", %s" % ("a single storey" if storeys == 1 else "up to %d storeys" % storeys)
	if height > 0.0:
		line += ", no taller than %s m" % ContractBrief._num(height)
	out.append(line + ".")
	if float(brief.get("floor_area", 0.0)) > 0.0:
		out.append("Floor area: aim for about %s m2 of rooms in all, corridors included." % ContractBrief._num(float(brief.floor_area)))
	if footprint > 0.0:
		out.append("Ground floor: no more than %s m2 of rooms." % ContractBrief._num(footprint))
	for m in musts:
		out.append("Also: " + m.left(1).to_lower() + m.substr(1) + ".")
	return out


static func _room_lines(brief: Dictionary, cat: BuildingCatalog) -> PackedStringArray:
	var out := PackedStringArray()
	for r: Dictionary in brief.get("requirements", []):
		match str(r.get("kind", "")):
			"rooms":
				var n := int(r.get("count", 1))
				var each := float(r.get("min_area", cat.room_type(str(r.type)).get("min_area", 0.0)))
				var cap := int(r.get("capacity", 0))
				var label := ContractBrief.room_label(str(r.type), cat, n)
				out.append("%d %s, at least %s m2%s%s." % [n, label, ContractBrief._num(each),
						" each" if n != 1 else "", ", for %d people" % cap if cap > 1 else ""])
			"double_bedroom":
				out.append("At least %d of the bedrooms a double (11.5 m2 or more)." % int(r.get("count", 1)))
	if out.is_empty():
		out.append("As you see fit: the client has not fixed the rooms.")
	return out


static func _money_lines(brief: Dictionary) -> PackedStringArray:
	var fee := float(brief.get("fee", 0.0))
	var days := int(brief.get("deadline_days", 0))
	var out := PackedStringArray()
	out.append("Build budget: %s. That is what the construction may cost; you pay it either way." % ContractValidator.money(float(brief.get("budget", 0.0))))
	out.append("Fee: %s, paid at handover if every requirement is met." % ContractValidator.money(fee))
	if days > 0:
		out.append("Deadline: %d days of construction. Each day late costs %s (%s%% of the fee), up to half the fee." % [days,
				ContractValidator.money(fee * ContractPayout.LATE_SHARE), str(ContractPayout.LATE_SHARE * 100.0)])
	out.append("Experience: %s for a pass, %d%% more for each bonus goal met, %d%% less for each week late." % [
			ContractTiers.xp_text(int(brief.get("xp", 0))), roundi(ContractPayout.GOAL_XP * 100.0), roundi(ContractPayout.LATE_XP * 100.0)])
	return out


static func _site_lines(brief: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var site := _site(brief)
	var w := float(site.get("w", 0.0))
	var d := float(site.get("d", 0.0))
	var area := roundf(float(site.get("area", w * d)))
	var pack := _pack_of(brief)
	if pack == null:
		var nm := str(site.get("name", "the plot"))
		out.append("%s: about %s x %s m, %s m2." % [nm.left(1).to_upper() + nm.substr(1), ContractBrief._num(w), ContractBrief._num(d), ContractBrief._num(area)])
		out.append("Firm, level ground with road access on one side and nothing in the way.")
		return out
	out.append("%s, %s." % [pack.title(), pack.location_text()] if pack.location_text() != "" else pack.title() + ".")
	out.append("Plot: %s (%s m2 inside the boundary). Difficulty %d of 5." % [pack.plot_size_text(), ContractBrief._num(area), pack.rating()])
	var g := pack.ground()
	out.append("Ground: %s, falling %s%% to the %s." % [pack.soil().replace("_", " "), ContractBrief._num(roundf(float(g.get("slope_pct", 0.0)))), str(g.get("downhill", "-"))])
	var roads := pack.access()
	if roads.is_empty():
		out.append("Access: no road touches the plot; everything comes in on foot or over a neighbour's land.")
	else:
		var names := PackedStringArray()
		for r: Dictionary in roads:
			names.append("%s (%d m of frontage)" % [str(r.get("name", r.get("road", "a road"))), roundi(float(r.get("frontage_m", 0.0)))])
		out.append("Access: from " + ", ".join(names) + ".")
	var existing := pack.existing_buildings().size()
	if existing > 0:
		out.append("%d existing building%s on the plot to demolish first." % [existing, "" if existing == 1 else "s"])
	var near := pack.neighbours().size()
	if near > 0:
		out.append("%d neighbouring building%s around it, %d of them protected." % [near, "" if near == 1 else "s", pack.protected_ids().size()])
	if str(pack.plot().get("notes", "")) != "":
		out.append(str(pack.plot().notes))
	out.append("In the designer the orange outline is the boundary; build around the plot's centre.")
	return out


static func _constraint_lines(brief: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var pack := _pack_of(brief)
	if pack != null:
		for f: Dictionary in pack.factors():
			var fid := str(f.get("id", ""))
			if fid == "ground" and (pack.soil() == "soft_wet" or str(f.get("label", "")).to_lower().contains("wet")):
				fid = "ground_wet"
			out.append("%s. %s What it means for you: %s" % [str(f.get("label", "")), str(f.get("detail", "")), site_advice(fid)])
	else:
		for label: Variant in _site(brief).get("factors", []):
			out.append(str(label).capitalize() + ". " + _GENERIC_ADVICE)
	for r: Dictionary in brief.get("requirements", []):
		if str(r.get("kind", "")) == "max_height" and str(brief.get("summary", "")).contains("conservation area"):
			out.append("Conservation area: nothing taller than %s m. What it means for you: keep the roof low; a pitched roof counts." % ContractBrief._num(float(r.value)))
	return out


static func _material_lines(brief: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for r: Dictionary in brief.get("requirements", []):
		if str(r.get("kind", "")) == "materials":
			out.append("Structure (walls, floors, roof, frame and foundations) in %s only." % ContractBrief.material_list(PackedStringArray(r.get("allowed", []))))
	out.append("Glazing and fittings are always allowed.")
	return out


static func _judging_lines(brief: Dictionary, cat: BuildingCatalog) -> PackedStringArray:
	var out := PackedStringArray()
	out.append("At handover the client checks every one of these. All must pass, or no fee is paid and no XP is earned:")
	var n := 0
	for r: Dictionary in ContractBrief.normalize(brief).get("requirements", []):
		n += 1
		out.append("%d. %s" % [n, ContractBrief.describe(r, cat)])
	out.append("Each bonus goal met adds its bonus to the fee and to the XP.")
	out.append("The Contract window in the designer ticks each one off live as you draw, so you can see where you stand before you hand over.")
	return out


static func _site(brief: Dictionary) -> Dictionary:
	return brief.get("site", {}) if brief.get("site") is Dictionary else {}


static func _pack_of(brief: Dictionary) -> SitePack:
	var sid := str(_site(brief).get("id", ""))
	if sid == "":
		return null
	if not _packs.has(sid):
		var p := SitePool.open(sid)
		_packs[sid] = p if p != null and p.ok() else null
	return _packs[sid]


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")
