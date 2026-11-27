class_name DesignFitout
extends RefCounted
## Furnishing a room in one go, two ways (the plan's fit-out options besides placing pieces
## by hand): the room type's usual layout, or a plain description such as "2 single beds
## either side of the window, a wardrobe and a desk facing the window". The words are read
## against every fixture kind (fitout/fitout_words.gd) and laid out like a person would
## (fitout/fitout_layout.gd), returned as one batch of place ops: one undo, synced like any
## other edit.
##
## Flag design.furnish_layout off: the old packing in rows from one corner.

const FLAG := "design.furnish_layout"

## The usual contents of each room type: [what, count]. what is a kind id or words for one
## (the first that the catalog has wins: "a|b"); count -1: one per AREA_EACH m².
const PRESETS := {
	"bedroom": [["bed_double", 1], ["bedside table", 2], ["furniture.wardrobe.double", 1], ["chest of drawers", 1]],
	"bathroom": [["bath", 1], ["wc", 1], ["basin", 1]],
	"wc_room": [["wc", 1], ["basin", 1]],
	"kitchen": [["furniture.kitchen.sink_1000|kitchen_unit", 1], ["furniture.kitchen.hob_600|kitchen_unit", 1],
		["furniture.kitchen.base_600|kitchen_unit", 3], ["furniture.appliance.fridge_freezer|kitchen_unit", 1], ["dining_table", 1]],
	"living_room": [["sofa", 1], ["furniture.seat.armchair|sofa", 1], ["furniture.table.coffee", 1], ["furniture.storage.tv_unit", 1]],
	"dining_room": [["dining_table", 1], ["furniture.storage.sideboard", 1]],
	"study": [["desk_office", 1], ["furniture.storage.bookcase_tall", 1]],
	"office": [["desk_office", -1]],
	"meeting_room": [["furniture.table.meeting_8|dining_table", 1]],
	"reception": [["reception_desk", 1], ["sofa", 1]],
	"classroom": [["desk_teacher", 1], ["desk_pupil", -1]],
	"school_hall": [["hall_chair", -1]],
	"staff_room": [["sofa", 2], ["dining_table", 1]],
	"library": [["furniture.storage.bookcase_tall", 4], ["desk_pupil", -1]],
	"toilet_block": [["wc", 4], ["basin", 4]],
	"custody_cell": [["cell_bench", 1], ["wc", 1]],
	"custody_desk": [["reception_desk", 1]],
	"interview_room": [["furniture.table.interview|desk_office", 1]],
	"locker_room": [["locker", 4]],
	"ward_bay": [["hospital_bed", -1]],
	"single_room": [["hospital_bed", 1], ["wc", 1], ["basin", 1]],
	"waiting_area": [["hall_chair", -1]],
	"departure_lounge": [["hall_chair", -1]],
	"gate_lounge": [["hall_chair", -1]],
}
## Area per piece where the count is -1, m².
const AREA_EACH := {"desk_office": 10.0, "desk_pupil": 2.6, "hall_chair": 1.2, "hospital_bed": 9.0}
const MAX_PIECES := 120
## Layouts tried at most before settling for the fullest.
const TRIES := 8
# The old row packing (flag off).
const MARGIN := 0.35
const GAP := 0.5


## The preset contents for a room: [{kind, count, rel, target}, ...].
static func preset(model: BuildingModel, room_id: String) -> Array:
	var r: Dictionary = model.rooms.get(room_id, {})
	if r.is_empty():
		return []
	var area := BuildingModel.outline_area(r.outline)
	var out: Array = []
	for item: Array in PRESETS.get(str(r.type), []):
		var kind := ""
		for what: String in str(item[0]).split("|"):
			if kind == "":
				kind = what if model.catalog.has_kind(what) else DesignFitoutWords.kind_for(what, model.catalog, str(r.type))
		if kind == "":
			continue
		var n := int(item[1])
		if n < 0:
			n = clampi(floori(area / float(AREA_EACH.get(kind, 4.0))), 1, MAX_PIECES)
		out.append({"kind": kind, "count": n, "rel": "", "target": ""})
	return out


## Reads a description into {items: [{kind, count, rel, target}], unknown: [words]}.
static func read(text: String, catalog: BuildingCatalog, room_type: String = "") -> Dictionary:
	return DesignFitoutWords.read(text, catalog, room_type)


## Just [[kind, count], ...] from a description: "3 single beds and a wardrobe".
static func parse(text: String, catalog: BuildingCatalog, room_type: String = "") -> Array:
	var out: Array = []
	for it: Dictionary in read(text, catalog, room_type).items:
		out.append([it.kind, it.count])
	return out


## Place ops for the pieces laid out in the room, as many as fit.
## items: [{kind, count, rel?, target?}] (or [kind, count] pairs).
## Returns {"ops": [...], "placed": int, "wanted": int, "missing": {kind: count}}.
static func furnish(model: BuildingModel, room_id: String, items: Array) -> Dictionary:
	var list: Array = []
	for it: Variant in items:
		list.append(it if it is Dictionary else {"kind": str(it[0]), "count": int(it[1])})
	if not Flags.is_on(FLAG):
		return _rows(model, room_id, list)
	if not model.rooms.has(room_id) or list.is_empty():
		var wanted := 0
		for it: Dictionary in list:
			wanted += int(it.count)
		return {"ops": [], "placed": 0, "wanted": wanted, "missing": {}}
	# Another try or two with different choices when something is left out; the fullest wins.
	var wanted := 0
	for it: Dictionary in list:
		wanted += int(it.count)
	var tries := TRIES if wanted <= 30 else 2
	var best := {}
	for v in tries:
		var lay := DesignFitoutLayout.new(model, room_id)
		lay.variant = v
		var r := lay.place_all(list)
		if best.is_empty() or int(r.placed) > int(best.placed):
			best = r
		if int(best.placed) >= int(best.wanted):
			break
	return best


## The old packing: in rows from one corner, largest first.
static func _rows(model: BuildingModel, room_id: String, items: Array) -> Dictionary:
	var r: Dictionary = model.rooms.get(room_id, {})
	var wanted := 0
	for it: Dictionary in items:
		wanted += int(it.count)
	if r.is_empty() or items.is_empty():
		return {"ops": [], "placed": 0, "wanted": wanted, "missing": {}}
	var cat := model.catalog
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Array in r.outline:
		lo = lo.min(Vector2(float(p[0]), float(p[1])))
		hi = hi.max(Vector2(float(p[0]), float(p[1])))
	var pieces: Array = []
	for it: Dictionary in items:
		for k in mini(int(it.count), MAX_PIECES):
			pieces.append(str(it.kind))
	pieces.sort_custom(func(a: String, b: String) -> bool:
		return _footprint(cat, a).x * _footprint(cat, a).y > _footprint(cat, b).x * _footprint(cat, b).y)
	var ops: Array = []
	var x := lo.x + MARGIN
	var z := lo.y + MARGIN
	var row_d := 0.0
	for kind: String in pieces:
		var f := _footprint(cat, kind)
		if x + f.x > hi.x - MARGIN:
			x = lo.x + MARGIN
			z += row_d + GAP
			row_d = 0.0
		if z + f.y > hi.y - MARGIN or x + f.x > hi.x - MARGIN:
			break
		var cx := x + f.x / 2.0
		var cz := z + f.y / 2.0
		if BuildingModel.outline_has_point(r.outline, cx, cz):
			ops.append(BuildingCommands.place_part(kind, int(r.level), {"at": Vector3(cx, 0, cz), "rot": 0.0}))
		x += f.x + GAP
		row_d = maxf(row_d, f.y)
	return {"ops": ops, "placed": ops.size(), "wanted": wanted, "missing": {}}


static func _footprint(cat: BuildingCatalog, kind: String) -> Vector2:
	var k := cat.kind(kind)
	return Vector2(float(k.get("w", 0.6)), float(k.get("d", 0.6)))
