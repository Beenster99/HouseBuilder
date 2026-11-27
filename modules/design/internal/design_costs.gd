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


## The cost panel's text (BBCode) from a summary: the total, by element, by level, the rooms
## (the first max_rooms) and the notes. The designer's cost column and the hall's cost screen.
static func bbcode(s: Dictionary, max_rooms := 30, big := 30) -> String:
	var cur := str(s.currency)
	var dim := BsxTheme.MUTED.to_html(false)
	var t := "[font_size=%d][color=#%s]COST · LIVE%s[/color][/font_size]\n" % [maxi(10, big / 2), BsxTheme.HUD_DIM.to_html(false),
			"" if bool(s.get("current", true)) else " · costing %d%%" % int(float(s.get("progress", 1.0)) * 100.0)]
	t += "[font_size=%d][b]%s[/b][/font_size]\n" % [big, money(s.total, cur)]
	t += "[color=#%s]structure %s · fit-out %s · floor %.0f m²[/color]\n" % [dim,
			money(s.structure, cur), money(s.fit_out, cur), s.floor_area]
	if float(s.floor_area) > 0.0:
		t += "[color=#%s]%s per m²[/color]\n" % [dim, money(float(s.total) / float(s.floor_area), cur)]
	t += "\n[b]By element[/b]\n"
	t += rows_bbcode(s.families, cur)
	if (s.families as Array).is_empty():
		t += "[color=#%s]Nothing placed yet.[/color]\n" % dim
	t += "\n[b]By level[/b]\n"
	t += rows_bbcode(s.levels, cur)
	t += "\n[b]Rooms[/b]\n"
	var listed := 0
	for r: Dictionary in s.rooms:
		listed += 1
		if listed > max_rooms:
			t += "[color=#%s]and %d more in the Rooms tab[/color]\n" % [dim, (s.rooms as Array).size() - max_rooms]
			break
		var c := BsxTheme.WARN.to_html(false) if r.short else BsxTheme.TEXT.to_html(false)
		t += "[color=#%s]%s · L%d · %.1f m²%s[/color]\n" % [c, r.label, int(r.level), r.area,
				" (min %.0f)" % r.min_area if r.short else ""]
	if (s.rooms as Array).is_empty():
		t += "[color=#%s]No rooms yet: paint one with the Room tool.[/color]\n" % dim
	var notes: Array = s.notes
	if not notes.is_empty():
		t += "\n[b]Notes[/b]\n"
		for n: Dictionary in notes:
			var c := BsxTheme.WARN.to_html(false) if n.warn else BsxTheme.LIVE.to_html(false)
			t += "[color=#%s]• %s[/color]\n  [color=#%s]%s[/color]\n" % [c, n.text, dim, n.tip]
	return t


## Label and money in two columns, the money right-aligned.
static func rows_bbcode(rows: Array, cur: String) -> String:
	if rows.is_empty():
		return ""
	var t := "[table=2]"
	for r: Dictionary in rows:
		t += "[cell expand=3]%s[/cell][cell expand=1][right]%s[/right][/cell]" % [r.label, money(r.cost, cur)]
	return t + "[/table]\n"
