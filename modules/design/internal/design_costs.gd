class_name DesignCosts
extends RefCounted
## The live cost and requirement panel's content, worked out from the model after each edit:
## the running total, the split by part family and by level, the room schedule, and plain
## notes on what looks wrong with a tip for each (a room under its minimum size, a door in
## no wall, a storey with nothing to stand on). Pure, so tests read the same numbers.

const FAMILY_LABELS := {"foundation": "Foundations", "column": "Columns", "beam": "Beams",
		"brace": "Bracing", "truss": "Trusses", "slab": "Floors", "roof": "Roof", "wall": "Walls",
		"opening": "Doors and windows", "fixture": "Furniture and fittings"}


## {total, structure, fit_out, floor_area, currency, families: [{label, cost}],
##  levels: [{label, cost}], rooms: [{id, label, area, min_area, short, capacity}],
##  notes: [{text, tip, warn}]}
static func summary(model: BuildingModel) -> Dictionary:
	var t := BuildingQuantities.totals(model)
	var fams: Array = []
	for fam: String in model.catalog.families:
		var cost := float(t.by_family.get(fam, 0.0))
		if cost > 0.0:
			fams.append({"label": FAMILY_LABELS.get(fam, fam.capitalize()), "cost": cost})
	if float(t.fit_out) > 0.0:
		fams.append({"label": "Room fit-out", "cost": float(t.fit_out)})
	var lvls: Array = []
	for i in model.level_count():
		lvls.append({"label": str(model.levels[i].get("name", "Level %d" % i)), "cost": float(t.by_level.get(str(i), 0.0))})
	var rooms: Array = []
	for rid in BuildingModel.sort_ids(model.rooms.keys()):
		var e: Dictionary = model.rooms[rid]
		var q := BuildingQuantities.room(model, rid)
		var rt := model.catalog.room_type(str(e.type))
		rooms.append({"id": rid, "label": str(e.get("name", "")) if str(e.get("name", "")) != "" else str(rt.get("label", e.type)),
				"type": str(e.type), "level": int(e.level), "area": float(q.area), "min_area": float(q.min_area),
				"short": bool(q.short), "capacity": int(q.capacity)})
	return {"total": float(t.cost), "structure": float(t.structure), "fit_out": float(t.fit_out),
			"floor_area": float(t.floor_area), "currency": str(t.currency), "families": fams,
			"levels": lvls, "rooms": rooms, "notes": notes(model, rooms)}


static func notes(model: BuildingModel, rooms: Array) -> Array:
	var out: Array = []
	for r: Dictionary in rooms:
		if r.short:
			out.append({"warn": true, "text": "%s is %.1f m², under the %.0f m² a %s needs." % [r.label, r.area, r.min_area, r.label.to_lower()],
					"tip": "Select it and drag a wall out, or paint a bigger room."})
	var walls := model.parts_of_family("wall")
	for i in model.level_count():
		var on := model.parts_on(i)
		var has_rooms := not model.rooms_on(i).is_empty()
		var has_walls := false
		for pid in on:
			if pid in walls:
				has_walls = true
				break
		if has_rooms and not has_walls:
			out.append({"warn": true, "text": "%s has rooms but no walls." % str(model.levels[i].get("name", "Level %d" % i)),
					"tip": "Turn on Walls in the room tool, or draw walls round the rooms."})
		if i > 0 and not on.is_empty():
			var floor_found := false
			for pid in on:
				if model.catalog.family_of(str(model.parts[pid].kind)) == "slab":
					floor_found = true
					break
			if not floor_found:
				out.append({"warn": true, "text": "%s has no floor slab." % str(model.levels[i].get("name", "Level %d" % i)),
						"tip": "Use Floor slab to lay a floor under the rooms on this level."})
	var top := model.level_count() - 1
	if not model.parts.is_empty() and model.parts_of_family("roof").is_empty():
		out.append({"warn": false, "text": "No roof yet.", "tip": "Go to the top level (%s) and drag a Roof over it." % str(model.levels[top].get("name", ""))})
	if not walls.is_empty() and model.parts_of_family("opening").is_empty():
		out.append({"warn": false, "text": "No doors or windows yet.", "tip": "Pick Door or Window and click on a wall."})
	if not walls.is_empty() and model.parts_of_family("foundation").is_empty():
		out.append({"warn": false, "text": "Nothing carries the walls into the ground yet.",
				"tip": "Add a raft under the ground floor, or strip footings under the walls."})
	return out


static func money(v: float, currency := "GBP") -> String:
	var sign := "£" if currency == "GBP" else currency + " "
	var whole := int(round(v))
	var s := str(absi(whole))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if whole < 0 else "") + sign + s + out
