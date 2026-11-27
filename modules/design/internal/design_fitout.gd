class_name DesignFitout
extends RefCounted
## Furnishing a room in one go, two ways (the plan's fit-out options besides placing pieces
## by hand): the room type's usual layout, or a plain description such as "2 single beds,
## a desk and a wardrobe". Either gives a list of fixture kinds, which are packed in rows
## inside the room clear of its walls and returned as one batch of place ops.

## The usual contents of each room type: [kind, count] (count -1: one per area_each m²).
const PRESETS := {
	"bedroom": [["bed_double", 1]],
	"bathroom": [["wc", 1], ["basin", 1], ["bath", 1]],
	"wc_room": [["wc", 1], ["basin", 1]],
	"kitchen": [["kitchen_unit", 6], ["dining_table", 1]],
	"living_room": [["sofa", 2]],
	"dining_room": [["dining_table", 1]],
	"study": [["desk_office", 1]],
	"office": [["desk_office", -1]],
	"meeting_room": [["dining_table", 1]],
	"reception": [["reception_desk", 1], ["sofa", 1]],
	"classroom": [["desk_teacher", 1], ["desk_pupil", -1]],
	"school_hall": [["hall_chair", -1]],
	"staff_room": [["sofa", 2], ["dining_table", 1]],
	"library": [["desk_pupil", -1]],
	"toilet_block": [["wc", 4], ["basin", 4]],
	"custody_cell": [["cell_bench", 1], ["wc", 1]],
	"custody_desk": [["reception_desk", 1]],
	"interview_room": [["desk_office", 1]],
	"locker_room": [["locker", 4]],
	"ward_bay": [["hospital_bed", -1]],
	"single_room": [["hospital_bed", 1], ["wc", 1], ["basin", 1]],
	"waiting_area": [["hall_chair", -1]],
	"departure_lounge": [["hall_chair", -1]],
	"gate_lounge": [["hall_chair", -1]],
}
## Area per piece where the count is -1, m².
const AREA_EACH := {"desk_office": 10.0, "desk_pupil": 2.0, "hall_chair": 1.2, "hospital_bed": 9.0}
## Clearance from the walls and between pieces, m.
const MARGIN := 0.35
const GAP := 0.5
const MAX_PIECES := 120
## Words for fixture kinds beyond their catalog labels.
const WORDS := {
	"bed": "bed_double", "beds": "bed_double", "double": "bed_double", "single": "bed_single", "toilet": "wc",
	"loo": "wc", "sink": "basin", "basin": "basin", "bath": "bath", "shower": "shower", "unit": "kitchen_unit",
	"units": "kitchen_unit", "cupboard": "kitchen_unit", "sofa": "sofa", "couch": "sofa", "table": "dining_table",
	"desk": "desk_office", "desks": "desk_office", "pupil": "desk_pupil", "pupils": "desk_pupil", "teacher": "desk_teacher",
	"chair": "hall_chair", "chairs": "hall_chair", "seat": "hall_chair", "seats": "hall_chair", "reception": "reception_desk",
	"counter": "reception_desk", "locker": "locker", "lockers": "locker", "bench": "cell_bench",
	"hospital": "hospital_bed", "wardrobe": "locker",
}
const NUMBERS := {"a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
		"seven": 7, "eight": 8, "nine": 9, "ten": 10, "twelve": 12, "twenty": 20, "thirty": 30}


## The preset contents for a room: [[kind, count], ...].
static func preset(model: BuildingModel, room_id: String) -> Array:
	var r: Dictionary = model.rooms.get(room_id, {})
	if r.is_empty():
		return []
	var area := BuildingModel.outline_area(r.outline)
	var out: Array = []
	for item: Array in PRESETS.get(str(r.type), []):
		var n := int(item[1])
		if n < 0:
			n = maxi(1, floori(area / float(AREA_EACH.get(item[0], 4.0))))
		out.append([item[0], n])
	return out


## Reads a description into [[kind, count], ...]: "3 single beds and a wardrobe".
static func parse(text: String, catalog: BuildingCatalog) -> Array:
	var words := text.to_lower().replace(",", " ").replace(".", " ").replace(" and ", " ").split(" ", false)
	var counts := {}
	var order: Array = []
	var n := 1
	var i := 0
	while i < words.size():
		var w := words[i]
		if w.is_valid_int():
			n = clampi(w.to_int(), 1, MAX_PIECES)
		elif NUMBERS.has(w):
			n = int(NUMBERS[w])
		else:
			var kind := ""
			# Two-word names first ("single bed", "hospital bed", "pupil desk").
			if i + 1 < words.size():
				kind = _kind_for(w + " " + words[i + 1], catalog)
				if kind != "":
					i += 1
			if kind == "":
				kind = _kind_for(w, catalog)
			if kind != "":
				if not counts.has(kind):
					order.append(kind)
				counts[kind] = int(counts.get(kind, 0)) + n
				n = 1
		i += 1
	var out: Array = []
	for k: String in order:
		out.append([k, counts[k]])
	return out


static func _kind_for(word: String, catalog: BuildingCatalog) -> String:
	for kind: String in catalog.kinds_in("fixture"):
		var label := str(catalog.kind(kind).get("label", "")).to_lower()
		if label == word or label.trim_suffix("s") == word.trim_suffix("s") or kind.replace("_", " ") == word:
			return kind
	var pair := {"single bed": "bed_single", "double bed": "bed_double", "hospital bed": "hospital_bed",
			"pupil desk": "desk_pupil", "teacher desk": "desk_teacher", "kitchen unit": "kitchen_unit",
			"office desk": "desk_office", "reception desk": "reception_desk", "dining table": "dining_table"}
	if pair.has(word):
		return pair[word]
	if pair.has(word.trim_suffix("s")):
		return pair[word.trim_suffix("s")]
	return str(WORDS.get(word, ""))


## Place ops for the pieces packed in rows inside the room (largest first), as many as fit.
## Returns {"ops": [...], "placed": int, "wanted": int}.
static func furnish(model: BuildingModel, room_id: String, items: Array) -> Dictionary:
	var r: Dictionary = model.rooms.get(room_id, {})
	var wanted := 0
	for it: Array in items:
		wanted += int(it[1])
	if r.is_empty() or items.is_empty():
		return {"ops": [], "placed": 0, "wanted": wanted}
	var cat := model.catalog
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Array in r.outline:
		lo = lo.min(Vector2(float(p[0]), float(p[1])))
		hi = hi.max(Vector2(float(p[0]), float(p[1])))
	var pieces: Array = []
	for it: Array in items:
		for k in mini(int(it[1]), MAX_PIECES):
			pieces.append(str(it[0]))
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
	return {"ops": ops, "placed": ops.size(), "wanted": wanted}


static func _footprint(cat: BuildingCatalog, kind: String) -> Vector2:
	var k := cat.kind(kind)
	return Vector2(float(k.get("w", 0.6)), float(k.get("d", 0.6)))
