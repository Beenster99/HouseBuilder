class_name DesignCosts
extends RefCounted
## The live cost and requirement panel's content (the room keeps a DesignCostBook so edits
## re-cost only what they touch; summary() here works it all out from scratch):
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
	var book := DesignCostBook.new(model)
	book.update()
	var out := book.summary()
	book.unbind()
	return out


## Notes on what looks wrong, from the room schedule and counts the cost book keeps:
## per_level [{parts, walls, slabs, rooms}], fam_count {family: parts}.
static func notes_from(model: BuildingModel, rooms: Array, per_level: Array, fam_count: Dictionary) -> Array:
	var out: Array = []
	var shown := 0
	var short := 0
	for r: Dictionary in rooms:
		if r.short:
			short += 1
			if shown < 8:
				shown += 1
				out.append({"warn": true, "text": "%s is %.1f m², under the %.0f m² a %s needs." % [r.label, r.area, r.min_area, str(r.label).to_lower()],
						"tip": "Select it and drag a wall out, or paint a bigger room."})
	if short > shown:
		out.append({"warn": true, "text": "%d more rooms are under their minimum size." % (short - shown), "tip": "The Rooms tab marks them (small)."})
	for i in per_level.size():
		var lv: Dictionary = per_level[i]
		var name := str(model.levels[i].get("name", "Level %d" % i))
		if int(lv.rooms) > 0 and int(lv.walls) == 0:
			out.append({"warn": true, "text": "%s has rooms but no walls." % name,
					"tip": "Turn on Walls in the room tool, or draw walls round the rooms."})
		if i > 0 and int(lv.parts) > 0 and int(lv.slabs) == 0:
			out.append({"warn": true, "text": "%s has no floor slab." % name,
					"tip": "Use Floor slab to lay a floor under the rooms on this level."})
	var top := model.level_count() - 1
	var walls := int(fam_count.get("wall", 0))
	var any := false
	for f: String in fam_count:
		any = any or int(fam_count[f]) > 0
	if any and int(fam_count.get("roof", 0)) == 0:
		out.append({"warn": false, "text": "No roof yet.", "tip": "Go to the top level (%s) and drag a Roof over it." % str(model.levels[top].get("name", ""))})
	if walls > 0 and int(fam_count.get("opening", 0)) == 0:
		out.append({"warn": false, "text": "No doors or windows yet.", "tip": "Pick Door or Window and click on a wall."})
	if walls > 0 and int(fam_count.get("foundation", 0)) == 0:
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
