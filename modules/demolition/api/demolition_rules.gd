class_name DemolitionRules
extends RefCounted
## Pure demolition rules, the same on every peer: what loses support when parts go, how a
## part breaks into chunks, how strong each family is, and the score.
##
## Parts are BuildingParts Dictionaries ({id, family, kind, aabb, supported_by, material}).
## unsupported() is the support-graph check; a demolition started from a BuildingModel also
## asks the structure module (StructureBuilding.collapse_after) on the host.

## Longest side of a chunk, m. Parts split into pieces this size when they fall.
const CHUNK := 2.6
const MAX_CHUNKS_PER_PART := 24
## Impact energy, J, a standing part takes before it breaks loose. Foundations never do.
const STRENGTH := {
	"column": 90000.0, "wall": 60000.0, "beam": 70000.0, "brace": 30000.0, "truss": 50000.0,
	"slab": 120000.0, "roof": 50000.0, "opening": 4000.0, "fixture": 4000.0, "room": 40000.0,
}
## kg/m3 by material, then by family.
const DENSITY := {"concrete": 2400.0, "steel": 7850.0, "timber": 550.0, "masonry": 1900.0,
		"glass": 2500.0}
const FAMILY_DENSITY := {"foundation": 2400.0, "column": 2400.0, "beam": 2400.0, "slab": 2400.0,
		"wall": 1900.0, "roof": 900.0, "opening": 600.0, "fixture": 400.0}


## How many of its supports a part needs to stay up: columns and walls stand on any one,
## beams need all of theirs, floors and roofs most of theirs.
static func need(part: Dictionary, supports: int) -> int:
	match str(part.get("family", "")):
		"beam", "brace", "truss":
			return supports
		"slab", "roof":
			return ceili(supports * 0.6)
	return mini(1, supports)


## Ids of parts still standing that lose support once `removed` (id -> true) are gone.
## A part with no supports stands on the ground.
static func unsupported(parts: Array, removed: Dictionary) -> PackedStringArray:
	var ids: Dictionary = {}
	for p: Dictionary in parts:
		ids[p.id] = p
	var order := parts.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.aabb as AABB).position.y < (b.aabb as AABB).position.y)
	var up: Dictionary = {}
	var changed := true
	while changed:
		changed = false
		for p: Dictionary in order:
			if up.has(p.id) or removed.has(p.id):
				continue
			var sups: Array = []
			for s: Variant in p.get("supported_by", []):
				if ids.has(str(s)):
					sups.append(str(s))
			var held := 0
			for s: String in sups:
				if up.has(s):
					held += 1
			if sups.is_empty() or held >= need(p, sups.size()):
				up[p.id] = true
				changed = true
	var out := PackedStringArray()
	for p: Dictionary in parts:
		if not up.has(p.id) and not removed.has(p.id):
			out.append(p.id)
	return out


## A part's chunks, local boxes in world space, deterministic.
static func chunks(part: Dictionary) -> Array[AABB]:
	var box: AABB = part.aabb
	var n := Vector3i(maxi(1, ceili(box.size.x / CHUNK)), maxi(1, ceili(box.size.y / CHUNK)),
			maxi(1, ceili(box.size.z / CHUNK)))
	while n.x * n.y * n.z > MAX_CHUNKS_PER_PART:
		if n.x >= n.y and n.x >= n.z:
			n.x -= 1
		elif n.z >= n.y:
			n.z -= 1
		else:
			n.y -= 1
	var step := Vector3(box.size.x / n.x, box.size.y / n.y, box.size.z / n.z)
	var out: Array[AABB] = []
	for i in n.x:
		for j in n.y:
			for k in n.z:
				out.append(AABB(box.position + Vector3(i * step.x, j * step.y, k * step.z), step))
	return out


static func strength(part: Dictionary) -> float:
	if str(part.get("family", "")) == "foundation":
		return INF
	return float(STRENGTH.get(str(part.get("family", "")), 50000.0))


static func density(part: Dictionary) -> float:
	var m := str(part.get("material", ""))
	if DENSITY.has(m):
		return DENSITY[m]
	return float(FAMILY_DENSITY.get(str(part.get("family", "")), 1500.0))


## The drop zone: the building's footprint grown by `margin` m, on the ground plan (x, z).
static func drop_zone(parts: Array, margin: float) -> Rect2:
	var r := Rect2()
	var first := true
	for p: Dictionary in parts:
		var b: AABB = p.aabb
		var plan := Rect2(b.position.x, b.position.z, b.size.x, b.size.z)
		r = plan if first else r.merge(plan)
		first = false
	return r.grow(margin)


## The score out of 100 from what came down where:
##   debris_in / debris_total  volume of fallen material inside / anywhere, m3
##   standing / total          volume still standing / of the whole building, m3
##   neighbour_hits            protected neighbours touched by debris
##   charges                   charges fired
static func score(debris_in: float, debris_total: float, standing: float, total: float,
		neighbour_hits: int, charges: int) -> Dictionary:
	var contained := 1.0 if debris_total <= 0.0 else clampf(debris_in / debris_total, 0.0, 1.0)
	var down := 0.0 if total <= 0.0 else clampf(1.0 - standing / total, 0.0, 1.0)
	var pts := 60.0 * contained * down + 35.0 * down + 5.0 * clampf(1.0 - charges / 40.0, 0.0, 1.0)
	pts -= 25.0 * neighbour_hits
	pts = clampf(roundf(pts), 0.0, 100.0)
	var grade := "Fail"
	if neighbour_hits == 0 and down > 0.9:
		grade = "Textbook" if pts >= 90.0 else ("Clean" if pts >= 75.0 else "Messy")
	elif down >= 0.5:
		grade = "Partial"
	return {"score": pts, "contained": contained, "down": down, "neighbour_hits": neighbour_hits,
			"charges": charges, "grade": grade}
