class_name DesignFitoutRules
extends RefCounted
## How each kind of furniture wants to stand in a room: against a wall, free standing, by
## another piece, on a worktop or hung on a wall, and the clear floor it needs to be used.
## Clearances are the usual UK furniture planning figures (Metric Handbook, Lifetime Homes):
## 0.7 m at the foot of a bed, 0.6 m (0.9 m for a hospital bed) at its sides, 0.9 m in front
## of a wardrobe or kitchen run, 0.6 m in front of a WC or basin, 0.6 m round a table with
## its chairs.
##
## rule(catalog, kind) -> {
##   mode: "bed" | "wall" | "free" | "seat" | "bedside" | "top" | "floor" | "mounted" | "ceiling" | "corner",
##   front: m clear in front (-z, the side it is used from),
##   side: m clear at the sides (beds), both_sides: bool (a double or hospital bed),
##   around: m clear on every side (free standing),
##   along: true when its long side goes to the wall (a bath),
##   tall: true when it would block a window, h: its height,
##   order: placing order (smaller first) }

const BEDS := ["bed_single", "bed_double", "hospital_bed", "cell_bench"]


static func rule(catalog: BuildingCatalog, kind: String) -> Dictionary:
	var spec := catalog.kind(kind)
	var label := str(spec.get("label", kind)).to_lower()
	var tags: Array = Array(spec.get("tags", []))
	var w := float(spec.get("w", 0.6))
	var d := float(spec.get("d", 0.6))
	var h := float(spec.get("h", 1.0))
	var r := {"mode": "wall", "front": 0.6, "side": 0.0, "both_sides": false, "around": 0.0, "along": false,
		"tall": h > 1.0, "h": h, "order": 30}
	var id := kind.to_lower()
	if "kitchen.wall_" in id or "extractor" in id:
		r.mode = "mounted"
		r.front = 0.0
		r.order = 35
		r.tall = true
		r["y"] = 1.45 if "wall_" in id else 1.5
	elif "ceiling" in tags or "pendant" in id:
		r.mode = "ceiling"
		r.order = 90
		r.tall = false
	elif "wall" in tags or (d < 0.12 and h > 0.3 and not "rug" in id) or "blind" in id or "curtain" in id:
		r.mode = "mounted"
		r.front = 0.0
		r.order = 80
		r.tall = not ("blind" in id or "curtain" in id or "towel" in id)
	elif is_bed(catalog, kind):
		r.mode = "bed"
		r.front = 0.9 if "hospital" in id else 0.7
		r.side = 0.9 if "hospital" in id else 0.6
		r.both_sides = w > 1.1 or "hospital" in id
		r.order = 10
		r.tall = false
	elif "bedside" in id or "overbed" in id:
		r.mode = "bedside"
		r.order = 12
		r.tall = false
	elif "rug" in id:
		r.mode = "floor"
		r.order = 85
		r.tall = false
	elif _top(id, label, w, d, h):
		r.mode = "top"
		r.order = 70
		r.tall = false
	elif is_chair(catalog, kind):
		r.mode = "seat"
		r.front = 0.5
		r.order = 50
		r.tall = false
		if "armchair" in id or "bean_bag" in id or "lounge" in id:
			r.mode = "free"
			r.around = 0.3
			r.front = 0.6
			r.order = 27
	elif is_table(catalog, kind) or "island" in id or "pod" in id or "bench_" in id and "desk" in id or "piano_grand" in id \
			or "hot_tub" in id or "lift" in id or "walk_in" in id:
		r.mode = "free"
		r.around = 0.4 if "coffee" in id or "side" in id else (0.9 if "island" in id else 0.6)
		r.order = 33 if not "coffee" in id else 26
		r.tall = h > 1.2
	elif "plant" in id or "lamp" in id or "coat_stand" in id or "bin" in id or "speaker" in id or "umbrella" in id \
			or "water_cooler" in id or "planter.round" in id:
		r.mode = "corner"
		r.front = 0.0
		r.order = 75
		r.tall = false
	else:
		# Against a wall, used from the front.
		if "wardrobe" in id or "kitchen" in id or "appliance" in id or "range" in id or "locker" in id \
				or "cupboard" in id or "cabinet" in id or "fridge" in id or "oven" in id:
			r.front = 0.9
		elif "desk" in id or "dressing" in id or "workbench" in id or "piano" in id:
			r.front = 0.8 if not "and chair" in label else 0.5
		elif "sofa" in id:
			r.front = 0.9
			r.order = 20
		elif "bath" in id and not "screen" in id:
			r.along = d > w * 1.5
			r.front = 0.7
		elif id in ["wc", "basin", "bidet"] or "urinal" in id or "vanity" in id or "accessible_wc" in id:
			r.front = 0.6
		elif "bookcase" in id or "drawer" in id or "sideboard" in id or "tv_unit" in id or "shelf" in id:
			r.front = 0.7
		if "wardrobe" in id or "tall" in id or "bookcase_tall" in id:
			r.order = 15
		if "desk" in id:
			r.order = 22
	return r


static func is_bed(catalog: BuildingCatalog, kind: String) -> bool:
	if kind in BEDS:
		return true
	var id := kind.to_lower()
	var label := str(catalog.kind(kind).get("label", "")).to_lower()
	return (" bed" in " " + label.split(",")[0] or "bed" in id.get_slice(".", id.get_slice_count(".") - 1)) \
			and not ("bedside" in id or "overbed" in id or "dog" in id or "flower" in id or "sofa" in id) or "cot" == id.get_slice(".", id.get_slice_count(".") - 1)


static func is_table(catalog: BuildingCatalog, kind: String) -> bool:
	var id := kind.to_lower()
	if "bedside" in id or "overbed" in id or "lamp" in id:
		return false
	return "table" in id or "table" in str(catalog.kind(kind).get("label", "")).to_lower().split(",")[0].split(" and ")[0]


static func is_chair(catalog: BuildingCatalog, kind: String) -> bool:
	var id := kind.to_lower()
	if "desk" in id or "table" in id or "wheelchair" in id or "high" in id:
		return false
	return "chair" in id or "stool" in id or "seat." in id and not ("sofa" in id or "pew" in id or "beam" in id or "bench" in id)


## Small things that stand on a desk, table or worktop.
static func _top(id: String, label: String, w: float, d: float, h: float) -> bool:
	for word: String in ["desk_lamp", "table_lamp", "monitor", "laptop", "kettle", "microwave", "books", "cushion",
			"conference_phone", "printer", "shredder", "pc_tower", "console"]:
		if word in id:
			return w < 1.0 and d < 0.8
	return false


## Words a desk, table, worktop or bedside surface has (things can stand on it).
static func is_surface(kind: String) -> bool:
	var id := kind.to_lower()
	for word: String in ["desk", "table", "kitchen_unit", "kitchen.base", "kitchen.drawers", "sideboard", "bedside",
			"chest_of_drawers", "tv_unit", "dressing", "workbench", "credenza", "tambour", "reception"]:
		if word in id:
			return true
	return false
