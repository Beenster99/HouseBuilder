class_name StructureBuilding
extends RefCounted
## The structure solver on a BuildingModel (read through the building api).
##
##   var report := StructureBuilding.stress_test(model)
##   report.part_envelope("p12")                    # utilisation of a building part
##   report.failed_parts()                          # part ids that fail in any test
##   StructureBuilding.collapse_after(model, ["p7"]) # what else falls if p7 goes
##
## How parts become members, plates and foundations: internal/building_adapter.gd.
## options: {"ground_needs_foundations": bool (default false: nodes at ground level with no
## foundation stand on the ground without a bearing check)}.

const Adapter := preload("res://modules/structure/internal/building_adapter.gd")
const MAX_ROUNDS := 64


## The model as a StructureGraph, leaving out the parts in removed.
static func graph(model: BuildingModel, removed: PackedStringArray = PackedStringArray(),
		options: Dictionary = {}) -> StructureGraph:
	return Adapter.build(model, removed, options)


## Normal use, storm and quake (or the scenarios given) on the model.
static func stress_test(model: BuildingModel, scenarios: Array[StructureScenario] = [],
		options: Dictionary = {}) -> StructureReport:
	return StructureSolver.stress_test(graph(model, PackedStringArray(), options), scenarios)


## Parts that fail once the parts in removed are gone, worked out in rounds: take them out,
## solve under self weight and a few people (StructureScenario.collapse()), take out what
## failed, and repeat until nothing more fails. Overloaded foundations settle rather than
## fall, so they are not counted. Doors and windows in a fallen wall, and partitions and
## fixtures standing on a fallen slab, fall with them. Returns sorted part ids, not
## including removed.
static func collapse_after(model: BuildingModel, removed: PackedStringArray, options: Dictionary = {}) -> PackedStringArray:
	var gone := {}
	for id in removed:
		gone[id] = true
	var fell := {}
	var sc := StructureScenario.collapse()
	for round in MAX_ROUNDS:
		var r := StructureSolver.solve(graph(model, PackedStringArray(gone.keys()), options), sc)
		var more := false
		for id in r.failures:
			if not r.members.has(id):
				continue
			var part := str(r.members[id].get("part", id))
			if not gone.has(part):
				gone[part] = true
				fell[part] = true
				more = true
		if not more:
			break
	_dependents(model, gone, fell)
	var out := PackedStringArray(fell.keys())
	out.sort()
	return out


static func _dependents(model: BuildingModel, gone: Dictionary, fell: Dictionary) -> void:
	var cat := model.catalog
	var slabs := {}
	for id in model.parts_of_family("slab"):
		slabs[id] = true
	for id in BuildingModel.sort_ids(model.parts.keys()):
		if gone.has(id):
			continue
		var e: Dictionary = model.parts[id]
		if e.has("host"):
			if gone.has(str(e.host)):
				fell[id] = true
			continue
		if bool(cat.kind(str(e.kind)).get("structural", false)):
			continue
		var pts := model.points_of(id)
		if pts.is_empty():
			continue
		var p := pts[0].lerp(pts[pts.size() - 1], 0.5)
		var under := 0
		var lost := 0
		for sid: String in slabs:
			var s: Dictionary = model.parts[sid]
			var y := model.level_elevation(model.level_of(sid)) + float(s.get("y", 0.0))
			if absf(y - p.y) <= 0.4 and BuildingModel.outline_has_point(s.outline, p.x, p.z):
				under += 1
				if gone.has(sid):
					lost += 1
		if under > 0 and lost == under:
			fell[id] = true
