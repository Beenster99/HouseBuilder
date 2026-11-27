class_name DesignFitoutWords
extends RefCounted
## Reads a furnishing description into requests, against every fixture kind in the catalog
## (the catalog's own fittings and the 3D library's furniture):
##
##   read("2 single beds either side of the window, a wardrobe and a desk facing the window", cat)
##   -> {"items": [{kind: "bed_single", count: 2, rel: "near", target: "window"},
##                 {kind: "furniture.wardrobe.double", count: 1, rel: "", target: ""},
##                 {kind: "desk_office", count: 1, rel: "facing", target: "window"}],
##       "unknown": ["..."]}   clauses that named nothing it knows
##
## A clause is split off at commas, "and", "plus", "with" and "then". Its words before a
## relation word ("beside", "facing", "around", "against", "in the corner"...) name the item
## and how many; the words after it name the target: "window", "door", "wall", "corner",
## "centre", or another item (its kind id).

const MAX_COUNT := 120
const NUMBERS := {"a": 1, "an": 1, "one": 1, "two": 2, "pair": 2, "couple": 2, "both": 2, "three": 3,
	"four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
	"dozen": 12, "fifteen": 15, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "few": 3, "several": 4}
const SPLITS := [",", "and", "plus", "with", "then", ";", "&", "+", "also"]
## Relation words -> relation. "next to", "in front of", "at the foot of" are joined first.
const RELATIONS := {"beside": "near", "by": "near", "next_to": "near", "near": "near", "under": "near",
	"below": "near", "underneath": "near", "alongside": "near", "close": "near", "nearby": "near",
	"facing": "facing", "faces": "facing", "opposite": "facing", "toward": "facing", "towards": "facing",
	"overlooking": "facing", "looking": "facing", "around": "around", "round": "around", "surrounding": "around",
	"against": "against", "along": "against", "on_the_wall": "against", "in": "in", "into": "in", "at": "in",
	"in_front_of": "front", "front": "front", "either_side": "sides", "each_side": "sides", "both_sides": "sides",
	"either": "sides", "foot_of": "foot", "end_of": "foot", "between": "near", "away": "away", "far": "away"}
## Targets that are places, not items.
const PLACES := {"window": "window", "windows": "window", "door": "door", "doors": "door", "doorway": "door",
	"entrance": "door", "wall": "wall", "walls": "wall", "corner": "corner", "corners": "corner",
	"middle": "centre", "centre": "centre", "center": "centre", "room": "centre"}
## Words that mean the same as a word some kind uses.
const ALIASES := {"couch": "sofa", "settee": "sofa", "telly": "television", "tv": "television", "loo": "wc",
	"toilet": "wc", "nightstand": "bedside", "bookshelf": "bookcase", "shelf": "bookcase", "shelves": "bookcase",
	"shelving": "bookcase", "dresser": "drawer", "drawers": "drawer", "closet": "wardrobe",
	"robe": "wardrobe", "workstation": "desk", "cooker": "cooker", "stove": "cooker", "hob": "hob",
	"computer": "computer", "pc": "computer", "washer": "washing", "dryer": "dryer", "fridge": "fridge",
	"freezer": "fridge", "worktop": "unit", "cabinet": "cabinet", "cupboard": "cupboard", "plant": "plant",
	"tub": "bath", "bathtub": "bath", "seat": "chair", "seating": "chair", "stool": "stool", "lamp": "lamp",
	"light": "lamp", "carpet": "rug", "bunk": "bunk", "bunks": "bunk", "crib": "cot", "monitor": "monitor",
	"screen": "monitor", "bin": "bin", "pot": "pot", "sideboard": "sideboard", "dining": "dining",
	"kitchen": "kitchen", "armchairs": "armchair", "recliner": "armchair", "easy": "armchair"}
## A bare noun names this kind first, if the catalog has it ("bed" -> a double bed).
const DEFAULTS := {"bed": "bed_double", "desk": "desk_office", "table": "dining_table", "chair": "furniture.seat.dining_chair",
	"sofa": "sofa", "wardrobe": "furniture.wardrobe.double", "drawer": "furniture.storage.chest_of_drawers",
	"bookcase": "furniture.storage.bookcase_tall", "lamp": "furniture.home.floor_lamp", "plant": "home.plant.medium",
	"television": "furniture.appliance.tv_55", "bath": "bath", "shower": "shower", "unit": "kitchen_unit",
	"cupboard": "furniture.storage.stationery_cupboard", "bedside": "furniture.storage.bedside_table",
	"rug": "furniture.home.rug", "mirror": "furniture.home.mirror", "bench": "furniture.seat.bench_3",
	"locker": "locker", "cabinet": "furniture.storage.display_cabinet", "computer": "office.it.pc_tower",
	"bin": "office.waste.bin", "fridge": "furniture.appliance.fridge_freezer", "cooker": "furniture.appliance.range_cooker",
	"sink": "basin", "wc": "wc", "basin": "basin", "stool": "furniture.seat.stool", "armchair": "furniture.seat.armchair",
	"monitor": "office.it.monitor_24", "coffee": "furniture.table.coffee"}
## The bare noun in some kinds of room.
const ROOM_DEFAULTS := {
	"ward_bay": {"bed": "hospital_bed", "chair": "furniture.seat.armchair"},
	"single_room": {"bed": "hospital_bed", "chair": "furniture.seat.armchair"},
	"office": {"chair": "furniture.seat.task_chair", "table": "furniture.table.meeting_4", "cupboard": "furniture.storage.stationery_cupboard"},
	"meeting_room": {"table": "furniture.table.meeting_8", "chair": "furniture.seat.task_chair"},
	"classroom": {"desk": "desk_pupil", "chair": "hall_chair", "table": "furniture.table.folding"},
	"library": {"desk": "desk_pupil", "chair": "hall_chair"},
	"school_hall": {"chair": "hall_chair", "table": "furniture.table.folding"},
	"kitchen": {"unit": "kitchen_unit", "sink": "furniture.kitchen.sink_1000", "table": "dining_table"},
	"bathroom": {"sink": "basin", "cabinet": "furniture.home.mirror_cabinet"},
	"custody_cell": {"bed": "cell_bench", "bench": "cell_bench"},
	"interview_room": {"table": "furniture.table.interview"},
	"waiting_area": {"chair": "furniture.seat.beam_3"}, "gate_lounge": {"chair": "furniture.seat.beam_4"},
	"departure_lounge": {"chair": "furniture.seat.beam_4"}}
## Small words that never name anything.
const STOP := {"the": 1, "of": 1, "to": 1, "for": 1, "my": 1, "our": 1, "some": 1, "it": 1, "them": 1, "each": 1,
	"is": 1, "are": 1, "please": 1, "put": 1, "place": 1, "add": 1, "i": 1, "want": 1, "need": 1, "like": 1,
	"would": 1, "room": 1, "its": 1, "their": 1, "this": 1, "that": 1, "there": 1, "x": 1}

static var SIZE := RegEx.create_from_string("\\b(\\d+)\\s*(inch|mm|seats?|seater|person|people|drawer|door|lanes?)\\b")
static var SIZE_WORD := RegEx.create_from_string("^\\d+(inch|mm|seats?|seater|person|people|drawer|door|lanes?)$")

## Per catalog: {kind: {"words": {word: true}, "head": word, "n": word count}}, word -> true.
static var _index_of: Dictionary = {}


## Reads a description. room_type picks the bare nouns' meaning ("bed" in a ward bay).
static func read(text: String, catalog: BuildingCatalog, room_type: String = "") -> Dictionary:
	var words := _tokens(text)
	var clauses: Array = [[]]
	for w: String in words:
		if w in SPLITS:
			if not (clauses[-1] as Array).is_empty():
				clauses.append([])
		else:
			(clauses[-1] as Array).append(w)
	var items: Array = []
	var unknown: PackedStringArray = []
	for c: Array in clauses:
		if c.is_empty():
			continue
		var r := c.size()
		for i in c.size():
			if RELATIONS.has(c[i]) and not (c[i] == "in" and i + 1 < c.size() and c[i + 1] == "front_of"):
				r = i
				break
		var item := _item(c.slice(0, r), catalog, room_type)
		if item.is_empty():
			# "and one by the door" after a named item: another of the same.
			if r < c.size() and not items.is_empty() and _count(c.slice(0, r)) > 0:
				item = {"kind": items[-1].kind, "count": _count(c.slice(0, r))}
			else:
				var known := false
				for w: String in c:
					known = known or RELATIONS.has(w) or PLACES.has(w)
				if not known or r == 0:
					unknown.append(" ".join(c).replace("_", " "))
				# A clause that is only a relation ("by the window") belongs to the item before.
				if r == 0 and not items.is_empty() and str(items[-1].rel) == "":
					_relate(items[-1], c, 0, catalog, room_type, items)
				continue
		item["rel"] = ""
		item["target"] = ""
		if r < c.size():
			_relate(item, c, r, catalog, room_type, items)
		items.append(item)
	# Chairs with a table and no say of their own go round it.
	var table := ""
	for it: Dictionary in items:
		if DesignFitoutRules.is_table(catalog, str(it.kind)):
			table = str(it.kind)
	var out: Array = []
	for it: Dictionary in items:
		if table != "" and it.rel == "" and DesignFitoutRules.is_chair(catalog, str(it.kind)):
			it.rel = "around"
			it.target = table
		# "A dining table with 4 chairs" when the table comes with its chairs.
		if it.rel == "around" and DesignFitoutRules.is_chair(catalog, str(it.kind)) \
				and "chair" in str(catalog.kind(str(it.target)).get("label", "")).to_lower():
			continue
		out.append(it)
	return {"items": out, "unknown": unknown}


## The kind a phrase names ("double wardrobe", "bedside tables"), or "".
static func kind_for(phrase: String, catalog: BuildingCatalog, room_type: String = "") -> String:
	var item := _item(_tokens(phrase), catalog, room_type)
	return str(item.get("kind", ""))


static func _relate(item: Dictionary, c: Array, r: int, catalog: BuildingCatalog, room_type: String, items: Array) -> void:
	item.rel = str(RELATIONS[c[r]]) if RELATIONS.has(c[r]) else "near"
	var rest: Array = c.slice(r + 1)
	for w: String in rest:
		if PLACES.has(w):
			item.target = str(PLACES[w])
			if item.rel == "in" and item.target == "wall":
				item.rel = "against"
			return
	var named := _item(rest, catalog, room_type)
	if not named.is_empty():
		item.target = str(named.kind)
		# "a lamp by the bed": prefer the kind actually asked for ("bed" -> single beds).
		var idx := _index(catalog)
		var head := str((idx.kinds.get(str(named.kind), {}) as Dictionary).get("head", ""))
		var exact := false
		for other: Dictionary in items:
			if _same_noun(catalog, str(other.kind), str(named.kind)):
				item.target = str(other.kind)
				exact = true
		# "facing the TV" with a TV unit asked for: face that.
		if not exact:
			for other: Dictionary in items:
				if ((idx.kinds.get(str(other.kind), {}) as Dictionary).get("words", {}) as Dictionary).has(head):
					item.target = str(other.kind)
	elif item.rel == "in":
		item.rel = ""
	if item.rel == "against" and item.target == "":
		item.target = "wall"


## {kind, count} from an item's words, or {}.
static func _item(words: Array, catalog: BuildingCatalog, room_type: String) -> Dictionary:
	var n := _count(words)
	var query: Array = []
	var idx := _index(catalog)
	var vocab: Dictionary = idx.vocab
	for w: String in words:
		if w.is_valid_int() or NUMBERS.has(w) or STOP.has(w):
			continue
		var s := _canon(w)
		if vocab.has(s):
			query.append(s)
	if query.is_empty():
		return {}
	var noun: String = query[-1]
	var kinds: Dictionary = idx.kinds
	# A bare noun ("2 beds", "a desk"): the usual kind for this room.
	if query.size() == 1:
		var d := str((ROOM_DEFAULTS.get(room_type, {}) as Dictionary).get(noun, DEFAULTS.get(noun, "")))
		if d != "" and catalog.has_kind(d):
			return {"kind": d, "count": n}
	var best := ""
	var best_score := -INF
	for k: String in kinds:
		var e: Dictionary = kinds[k]
		var kw: Dictionary = e.words
		if not kw.has(noun):
			continue
		var score := 0.0
		for q: String in query:
			if (e.heads as Dictionary).has(q):
				score += 5.0 if q == noun else 3.0
			elif kw.has(q):
				score += 1.5
			else:
				score -= 1.0
		score -= 0.15 * float(e.n)
		if bool(e.outdoor):
			score -= 0.8
		if bool(e.loose):
			score -= 0.8
		if not bool(e.library):
			score += 0.4
		if score > best_score:
			best_score = score
			best = k
	if best == "":
		return {}
	return {"kind": best, "count": n}


static func _count(words: Array) -> int:
	var n := 0
	for w: String in words:
		if w.is_valid_int():
			n = clampi(w.to_int(), 1, MAX_COUNT)
		elif NUMBERS.has(w) and n == 0:
			n = int(NUMBERS[w])
	return maxi(n, 1)


static func _same_noun(catalog: BuildingCatalog, a: String, b: String) -> bool:
	var idx := _index(catalog)
	return str((idx.kinds.get(a, {}) as Dictionary).get("head", "a")) == str((idx.kinds.get(b, {}) as Dictionary).get("head", "b"))


## Lower case words, punctuation as its own word, a few phrases joined with "_".
static func _tokens(text: String) -> Array:
	var t := " " + text.to_lower() + " "
	for p: String in [",", ";", ".", "&", "+", "(", ")", "!", "?", ":", "'s ", "-", "/"]:
		t = t.replace(p, " , " if p in [",", ";", "."] else (" s " if p == "'s " else " "))
	t = t.replace(" , ", " , ")
	for pair: Array in [[" next to ", " next_to "], [" in front of ", " in_front_of "], [" on the wall ", " on_the_wall "],
			[" either side of ", " either_side "], [" each side of ", " each_side "], [" both sides of ", " both_sides "],
			[" either side ", " either_side "], [" at the foot of ", " foot_of "], [" foot of ", " foot_of "],
			[" at the end of ", " end_of "], [" away from ", " away "], [" close to ", " close "], [" a pair of ", " 2 "],
			[" a couple of ", " 2 "], [" lots of ", " 6 "], [" a few ", " 3 "], [" a dozen ", " 12 "], [" sit stand ", " sit_stand "],
			[" chests of drawers ", " drawers "], [" chest of drawers ", " drawers "]]:
		t = t.replace(pair[0], pair[1])
	# Sizes are part of the name, not how many: "55 inch", "4 drawer", "6 seat".
	t = SIZE.sub(t, " $1$2 ", true)
	# Digits glued to words ("2beds").
	var out: Array = []
	for w: String in t.split(" ", false):
		var lead := 0
		while lead < w.length() and w[lead] >= "0" and w[lead] <= "9":
			lead += 1
		if lead > 0 and lead < w.length() and SIZE_WORD.search(w) == null:
			out.append(w.substr(0, lead))
			out.append(w.substr(lead))
		else:
			out.append(w)
	return out


## One word as the index keeps it: alias, then singular.
static func _canon(w: String) -> String:
	var s := w
	if ALIASES.has(s):
		return str(ALIASES[s])
	s = _singular(s)
	return str(ALIASES.get(s, s))


static func _singular(w: String) -> String:
	if w.length() <= 3 or w.ends_with("ss") or w.ends_with("us") or w.ends_with("is"):
		return w
	if w.ends_with("ies"):
		return w.substr(0, w.length() - 3) + "y"
	if w.ends_with("ves") and w != "stoves":
		return w.substr(0, w.length() - 3) + "f"
	for e: String in ["ches", "shes", "xes", "sses"]:
		if w.ends_with(e):
			return w.substr(0, w.length() - 2)
	if w.ends_with("s"):
		return w.substr(0, w.length() - 1)
	return w


## The word index of a catalog's fixture kinds (built once per catalog).
static func _index(catalog: BuildingCatalog) -> Dictionary:
	var key := catalog.get_instance_id()
	if _index_of.has(key) and int(_index_of[key].size) == catalog.kinds.size():
		return _index_of[key]
	var kinds := {}
	var vocab := {}
	for k: String in catalog.kinds_in("fixture"):
		var spec := catalog.kind(k)
		var label := str(spec.get("label", k)).to_lower()
		var main := label.split(",")[0].split(" and ")[0].split(" with ")[0].split("(")[0].strip_edges()
		var main_words := main.replace("-", " ").split(" ", false)
		var heads := {}
		if not main_words.is_empty():
			heads[_canon(main_words[-1])] = true
			# "Kitchen sink unit", "Locker bank": the word before names it too.
			if main_words.size() > 1 and main_words[-1] in ["unit", "units", "set", "bank", "housing", "rack", "and"]:
				heads[_canon(main_words[-2])] = true
		var head := _canon(main_words[-1]) if not main_words.is_empty() else ""
		var kw := {}
		var all_words: Array = []
		label = SIZE.sub(label, "$1$2", true)
		for w: String in label.replace(",", " ").replace("(", " ").replace(")", " ").replace("-", " ").replace("'s", "").split(" ", false):
			all_words.append(w)
		for t: String in spec.get("tags", []):
			all_words.append(t)
		for part: String in k.split("."):
			for w: String in part.split("_", false):
				all_words.append(w)
		for w: String in all_words:
			if w.is_valid_int() or STOP.has(w) or w in ["and", "a", "with", "for", "on"]:
				continue
			kw[_canon(w)] = true
		# Words people use for it that its label lacks.
		for extra: Array in [["basin", "sink"], ["bedside", "table"], ["tv", "television"], ["tv_unit", "stand"],
				["wardrobe", "cupboard"], ["chest_of_drawers", "dresser"], ["fridge", "fridge"], ["range_cooker", "oven"]]:
			if str(extra[0]) in k:
				kw[_canon(str(extra[1]))] = true
		if "bed" in kw and not ("bedside" in k or "overbed" in k or "dog" in k):
			kw["bed"] = true
		for w: String in kw:
			vocab[w] = true
		kinds[k] = {"words": kw, "head": head, "heads": heads, "n": kw.size(), "outdoor": bool(spec.get("outdoor", false)) or "outdoor" in spec.get("tags", []),
			"loose": bool(spec.get("loose", false)), "library": spec.has("asset")}
	for w: String in DEFAULTS:
		vocab[w] = true
	_index_of[key] = {"kinds": kinds, "vocab": vocab, "size": catalog.kinds.size()}
	return _index_of[key]
