class_name ServicesDesigner
extends RefCounted
## The M&E consultant's design work: what it would add to the building so every room is
## powered and every wet room plumbed, as building ops the crew can apply (one undo step).
##
##   var plan := ServicesDesigner.propose(model)
##   plan.ops          # building ops: fixtures for bare wet rooms, then the source units
##   plan.added        # [{kind, level, at: [x, y, z], room, why}]
##   plan.before       # ServicesReport of the building as it is
##   plan.after        # ServicesReport once the ops are applied
##   plan.notes        # what it did, in words
##
## It furnishes wet rooms that have no fixtures yet (a bathroom gets a WC, basin and bath,
## a WC a WC and basin, a kitchen or utility a sink unit, toilets two of each, a commercial
## kitchen three sink units), lined up along the wall nearest the soil stack. Then it places a
## consumer unit, water main, boiler and soil stack part wherever the routing put each source
## and no such part is in the building yet. It never moves or removes what players drew. The
## ops are worked out on a copy, so `model` is not changed.

const Rates := preload("res://modules/services/api/services_rates.gd")
const C := preload("res://modules/building/api/building_commands.gd")

## Fixtures for a bare wet room, in order along the wall.
const FIT_OUT := {
	"bathroom": ["wc", "basin", "bath"],
	"wc_room": ["wc", "basin"],
	"kitchen": ["kitchen_unit"],
	"utility": ["kitchen_unit"],
	"toilet_block": ["wc", "wc", "basin", "basin"],
	"commercial_kitchen": ["kitchen_unit", "kitchen_unit", "kitchen_unit"],
}
## Gap between fixtures along a wall, and from the wall to a fixture's back edge (m).
const GAP := 0.15
const WALL_GAP := 0.05
## Source part heights above the floor (a wall-mounted consumer unit and boiler).
const MOUNT_Y := {"consumer_unit": 1.5, "boiler": 1.2, "water_main": 0.0, "soil_stack": 0.0}


static func propose(model: BuildingModel, sources: Dictionary = {}) -> Dictionary:
	var before := ServicesConsultant.route(model, sources)
	var work := BuildingModel.from_data(model.to_data(), model.catalog)
	var ops: Array = []
	var added: Array = []
	var notes := PackedStringArray()
	var cat := model.catalog
	if model.rooms.is_empty():
		return {"ops": [], "added": [], "before": before, "after": before,
			"notes": PackedStringArray(["Nothing to design yet: draw some rooms first."])}

	# 1. Fixtures for bare wet rooms, along the wall nearest where waste goes.
	var stack := Vector2.INF
	var waste := before.system("waste")
	if not waste.is_empty():
		stack = Vector2(float(waste.source.at[0]), float(waste.source.at[2]))
	for rid in BuildingModel.sort_ids(model.rooms.keys()):
		var r: Dictionary = model.rooms[rid]
		var t := str(r.type)
		if not FIT_OUT.has(t) or _has_wet_fixture(model, rid):
			continue
		var kinds: Array = FIT_OUT[t].filter(func(k: String) -> bool: return cat.has_kind(k))
		var spots := _line_up(r.outline, kinds, cat, stack)
		var placed := PackedStringArray()
		for k in kinds.size():
			if spots[k] == null:
				continue
			var at: Array = spots[k].at
			var op := C.place_part(kinds[k], int(r.level), {"at": at, "rot": spots[k].rot})
			if work.apply(op).is_empty():
				continue
			ops.append(op)
			added.append({"kind": kinds[k], "level": int(r.level), "at": at, "room": rid, "why": "fit-out"})
			placed.append(str(cat.kind(kinds[k]).get("label", kinds[k])).to_lower())
		if not placed.is_empty():
			notes.append("Fitted out %s with %s." % [ServicesConsultant._room_name(model, rid), ", ".join(placed)])

	# 2. Route the fitted-out copy and put the source units where the routes start.
	var routed := ServicesConsultant.route(work, sources)
	for s in Rates.SYSTEMS:
		var sys := routed.system(s)
		if sys.is_empty() or str(sys.source.how) == "part":
			continue
		var kind := str(Rates.SYSTEM[s].source_kind)
		if not cat.has_kind(kind):
			continue
		var lv := int(sys.source.level)
		var at := [float(sys.source.at[0]), float(MOUNT_Y.get(kind, 0.0)), float(sys.source.at[2])]
		var op := C.place_part(kind, lv, {"at": at})
		if work.apply(op).is_empty():
			continue
		ops.append(op)
		var room := str(sys.source.room)
		added.append({"kind": kind, "level": lv, "at": at, "room": room, "why": s})
		notes.append("Placed the %s %s." % [Rates.SYSTEM[s].source,
			("in " + ServicesConsultant._room_name(model, room)) if room != "" else "on level %d" % lv])
	var after := ServicesConsultant.route(work, sources)
	if ops.is_empty():
		notes.append("Nothing to add: every source unit is placed and every wet room has fixtures.")
	notes.append(after.summary)
	return {"ops": ops, "added": added, "before": before, "after": after, "notes": notes}


static func _has_wet_fixture(model: BuildingModel, rid: String) -> bool:
	var r: Dictionary = model.rooms[rid]
	for pid: String in model.parts_on(int(r.level)):
		var e: Dictionary = model.parts[pid]
		if Rates.FIXTURE_NEEDS.has(str(e.kind)) and e.has("at") \
				and BuildingModel.outline_has_point(r.outline, float(e.at[0]), float(e.at[2])):
			return true
	return false


## Spots for `kinds` in a row along one side of the room's box: the side nearest `toward`
## (the first side when there is no target). Each spot is {at, rot} or null if it does not fit.
static func _line_up(outline: Array, kinds: Array, cat: BuildingCatalog, toward: Vector2) -> Array:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Array in outline:
		lo = Vector2(minf(lo.x, p[0]), minf(lo.y, p[1]))
		hi = Vector2(maxf(hi.x, p[0]), maxf(hi.y, p[1]))
	# Sides: [start, along direction, inward normal, rot]
	var sides := [
		[Vector2(lo.x, lo.y), Vector2(1, 0), Vector2(0, 1), 0.0],     # -Z side
		[Vector2(hi.x, lo.y), Vector2(0, 1), Vector2(-1, 0), 90.0],   # +X side
		[Vector2(hi.x, hi.y), Vector2(-1, 0), Vector2(0, -1), 180.0], # +Z side
		[Vector2(lo.x, hi.y), Vector2(0, -1), Vector2(1, 0), 270.0],  # -X side
	]
	var best := 0
	if toward != Vector2.INF:
		var best_d := INF
		for k in 4:
			var side: Array = sides[k]
			var length := (hi.x - lo.x) if k % 2 == 0 else (hi.y - lo.y)
			var centre: Vector2 = side[0] + side[1] * length * 0.5
			var d := centre.distance_to(toward)
			if d < best_d - 0.001:
				best_d = d
				best = k
	var side: Array = sides[best]
	var length := (hi.x - lo.x) if best % 2 == 0 else (hi.y - lo.y)
	var out: Array = []
	var along := GAP
	for kind: String in kinds:
		var spec := cat.kind(kind)
		var w := float(spec.get("w", 0.5))
		var d := float(spec.get("d", 0.5))
		if along + w > length - GAP * 0.5:
			out.append(null)
			continue
		var p: Vector2 = side[0] + side[1] * (along + w * 0.5) + side[2] * (WALL_GAP + d * 0.5)
		p = Vector2(snappedf(p.x, 0.01), snappedf(p.y, 0.01))
		if not BuildingModel.outline_has_point(outline, p.x, p.y):
			out.append(null)
		else:
			out.append({"at": [p.x, 0.0, p.y], "rot": side[3]})
		along += w + GAP
	return out
