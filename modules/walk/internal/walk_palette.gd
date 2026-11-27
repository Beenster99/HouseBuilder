extends RefCounted
## The Tab menu's groups of rooms and objects, and its filter. The designer and walk-inside
## show the same groups: when the design bus has palette_groups(kind), that is the source
## (found by name; walk doesn't depend on design). Otherwise walk uses this copy: rooms by
## their catalog category, objects by what they are for.
##
##   groups(model.catalog, "rooms" | "objects") -> [{id, title, items: [{id, label, tags}]}]
##   filtered(groups, "bed") -> the same groups, only items whose label or tags match, and
##     no empty groups

## Fittings by what they're for (catalog kind -> group id). Unlisted fittings go to "other".
const FIXTURE_GROUP := {
	"bed_single": "sleeping", "bed_double": "sleeping", "hospital_bed": "care", "cell_bench": "care",
	"wc": "bathroom", "basin": "bathroom", "bath": "bathroom", "shower": "bathroom",
	"kitchen_unit": "kitchen", "dining_table": "kitchen", "sofa": "living",
	"desk_office": "work", "desk_pupil": "work", "desk_teacher": "work", "reception_desk": "work",
	"hall_chair": "work", "locker": "work",
	"consumer_unit": "services", "water_main": "services", "boiler": "services", "soil_stack": "services",
}
const OBJECT_GROUPS: Array = [
	["living", "Living"], ["sleeping", "Sleeping"], ["kitchen", "Kitchen and dining"],
	["bathroom", "Bathroom"], ["work", "Office, school and reception"], ["care", "Care and secure"],
	["services", "Services (power, water, heat)"], ["other", "Other fittings"],
	["doors", "Doors"], ["windows", "Windows"], ["columns", "Columns"],
]


static func groups(catalog: BuildingCatalog, kind: String) -> Array:
	var design := Modules.bus("design") if Engine.get_main_loop() else null
	if design and design.has_method("palette_groups"):
		var got: Variant = design.call("palette_groups", kind)
		if got is Array and not (got as Array).is_empty():
			var out: Array = (got as Array).duplicate()
			# Walk can also stand columns up; the designer draws those with its own tool.
			if kind == "objects" and not out.any(func(g: Dictionary) -> bool: return str(g.id) == "columns"):
				for g: Dictionary in own_groups(catalog, kind):
					if str(g.id) == "columns":
						out.append(g)
			return out
	return own_groups(catalog, kind)


## Walk's own grouping (no design module, or it has none for this kind).
static func own_groups(catalog: BuildingCatalog, kind: String) -> Array:
	var out: Array = []
	var by_id := {}
	if kind == "rooms":
		var cats: Array = []
		for t: String in catalog.room_types:
			var cat := str(catalog.room_type(t).get("category", "other"))
			if not by_id.has(cat):
				by_id[cat] = {"id": cat, "title": cat.capitalize(), "items": []}
				cats.append(cat)
			(by_id[cat].items as Array).append(_item(t, str(catalog.room_type(t).get("label", t)), [cat, "room"]))
		for c: String in cats:
			out.append(by_id[c])
		return out
	for g: Array in OBJECT_GROUPS:
		by_id[g[0]] = {"id": g[0], "title": g[1], "items": []}
	for k in catalog.kinds_in("fixture"):
		var gid := str(FIXTURE_GROUP.get(k, "other"))
		(by_id[gid].items as Array).append(_item(k, str(catalog.kind(k).get("label", k)), ["fixture", gid]))
	for k in catalog.kinds_in("opening"):
		var gid := "windows" if k.begins_with("window") else "doors"
		(by_id[gid].items as Array).append(_item(k, str(catalog.kind(k).get("label", k)), ["opening", gid]))
	for k in catalog.kinds_in("column"):
		(by_id.columns.items as Array).append(_item(k, str(catalog.kind(k).get("label", k)), ["column", "structure"]))
	for g: Array in OBJECT_GROUPS:
		if not (by_id[g[0]].items as Array).is_empty():
			out.append(by_id[g[0]])
	return out


static func _item(id: String, label: String, tags: Array) -> Dictionary:
	return {"id": id, "label": label, "tags": PackedStringArray(tags)}


## Only the items whose label, id or tags contain every word of `text` (any case).
static func filtered(all: Array, text: String) -> Array:
	var words := text.strip_edges().to_lower().split(" ", false)
	if words.is_empty():
		return all
	var out: Array = []
	for g: Dictionary in all:
		var items: Array = []
		for it: Dictionary in g.items:
			var hay := ("%s %s %s %s" % [it.label, it.id, " ".join(PackedStringArray(it.get("tags", []))), g.title]).to_lower()
			var ok := true
			for w: String in words:
				if not hay.contains(w):
					ok = false
					break
			if ok:
				items.append(it)
		if not items.is_empty():
			var g2 := g.duplicate()
			g2["items"] = items
			out.append(g2)
	return out
