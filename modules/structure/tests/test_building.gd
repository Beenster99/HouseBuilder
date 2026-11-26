extends ModuleTest
## The solver on BuildingModels: a masonry house passes, a loose beam fails, sections and
## loads come from the catalog and rooms, foundations bear on the soil, and collapse_after
## says what falls when parts are taken away.
##   tools/run_tests.sh structure

const Samples := preload("res://modules/structure/tests/samples.gd")
const C := preload("res://modules/building/api/building_commands.gd")


func run_tests() -> void:
	_masonry_house()
	_loose_beam()
	_frame_on_pads()
	_collapse()
	_determinism()


func _masonry_house() -> void:
	var h := Samples.model_house()
	var m: BuildingModel = h.model
	var ids: Dictionary = h.ids
	var g := StructureBuilding.graph(m)
	check(g.plates.has(ids.floor_1) and g.plates.has(ids.roof), "first floor and roof are plates")
	check(not g.plates.has(ids.ground), "the ground slab bears on the ground")
	check(not g.plates[ids.floor_1].supports.is_empty(), "the floor sits on wall tops")
	var uprights := 0
	for mid: String in g.members:
		if g.members[mid].part == ids.front_0 and g.members[mid].kind == StructureGraph.WALL:
			uprights += 1
	check(uprights >= 4, "the front wall stands on several uprights around its door and window: %d" % uprights)
	check(g.anchor_ids().size() > 0, "walls stand on their strip footings")
	var strip_anchor := false
	for n in g.anchor_ids():
		if str(g.nodes[n].get("part", "")) == ids.strip_front:
			strip_anchor = true
	check(strip_anchor, "the front strip footing holds the front wall")
	var rep := StructureBuilding.stress_test(m)
	check(rep.passed(), "a sensible masonry house passes: %s %s" % [rep.summary, str(rep.notes)])
	check(rep.part_envelope(ids.floor_1) > 0.2, "the floor works: %f" % rep.part_envelope(ids.floor_1))
	check(rep.part_envelope(ids.front_0) > 0.0, "the front wall carries load")
	check(rep.brief_result() == {"ok": true, "failures": [], "worst": rep.worst_utilisation(), "scenario": ""}, "brief result: %s" % rep.brief_result())
	# Floor live load follows the rooms: make bedroom 1 a plant room and the floor works harder.
	m.apply(C.retag(ids.bed_1, "plant_room"))
	var heavier := StructureBuilding.stress_test(m)
	check(heavier.part_envelope(ids.floor_1) > rep.part_envelope(ids.floor_1) * 1.5, "a plant room loads the floor more")


func _loose_beam() -> void:
	var h := Samples.model_house()
	var m: BuildingModel = h.model
	var r := m.apply(C.place_part("beam", 1, {"a": [20, 2, 0], "b": [25, 2, 0], "name": "Loose"}, "steel", "ub_305x165x40"))
	var beam := str(r.do.entry.id)
	for i in 5:
		var rep := StructureBuilding.stress_test(m)
		check(not rep.passed() and beam in rep.failed_parts(), "the loose beam fails (run %d)" % i)
		check(rep.first_failure().id == beam, "and fails first")
		check(rep.notes[0].begins_with("Beam Loose is not connected to any foundation"), "note: %s" % rep.notes[0])
		var brief := rep.brief_result()
		check(not brief.ok and brief.failures == [beam] and brief.scenario == "normal_use", "brief result: %s" % brief)


## Steel columns on pad footings with a beam across: overloads soft ground.
func _frame_on_pads() -> void:
	var m := BuildingModel.new("frame", "Frame", BuildingCatalog.default_catalog())
	var ids := {}
	for k in ["a", "b"]:
		var x := 0.0 if k == "a" else 6.0
		ids["pad_" + k] = str(m.apply(C.place_part("pad_footing", 0, {"at": [x, 0, 0]}, "concrete", "pad_1000")).do.entry.id)
		ids["col_" + k] = str(m.apply(C.place_part("column", 0, {"at": [x, 0, 0]}, "steel", "uc_203x203x46")).do.entry.id)
	ids.beam = str(m.apply(C.place_part("beam", 0, {"a": [0, 3, 0], "b": [6, 3, 0]}, "steel", "ub_305x165x40")).do.entry.id)
	ids.slab = str(m.apply(C.place_part("slab", 0, {"outline": [[0, -4], [6, -4], [6, 0], [0, 0]], "y": 3.0}, "concrete", "slab_200")).do.entry.id)
	var g := StructureBuilding.graph(m, PackedStringArray(), {"ground_needs_foundations": true})
	check(g.anchor_ids().size() == 2, "the columns stand on their pads: %s" % g.anchor_ids())
	var col_sec := g.section(g.members[ids.col_a].section)
	check(col_sec.axial > 1000.0 and col_sec.axial < 2100.0, "a 3 m UC 203 buckles below its squash load: %f" % col_sec.axial)
	check(absf(g.section(g.members[ids.beam].section).bending - 198.8) < 1.0, "UB 305 bends at wy fy")
	check(g.plates[ids.slab].cantilever, "a slab held on one edge is a cantilever")
	check(_near(g.nodes[g.anchor_ids()[0]].bearing, 150.0), "1 m pad on clay: 150 kN")
	var rep := StructureBuilding.stress_test(m)
	check(ids.slab in rep.failed_parts(), "a 4 m slab cantilever fails: %s" % rep.summary)
	check(rep.notes.size() > 0 and str(rep.notes).contains("cantilevers"), "note says cantilever: %s" % str(rep.notes))
	m.apply(C.set_design_meta({"soil": "made_ground"}))
	rep = StructureBuilding.stress_test(m)
	var pads := rep.failed_parts()
	check(ids.pad_a in pads and ids.pad_b in pads, "pads on made ground give way: %s" % pads)
	var said := false
	for n in rep.notes:
		if n.begins_with("Foundation " + ids.pad_a):
			said = true
	check(said, "note names the pad: %s" % str(rep.notes))
	# Without a pad and with foundations required, the column has nothing to stand on.
	m.apply(C.delete([ids.pad_b]))
	var lone := StructureBuilding.stress_test(m, [], {"ground_needs_foundations": true})
	var lost := lone.failed_parts()
	check(ids.col_b in lost or ids.beam in lost, "without a pad the frame fails when foundations are required: %s" % lost)


func _collapse() -> void:
	var h := Samples.model_house()
	var m: BuildingModel = h.model
	var ids: Dictionary = h.ids
	check(StructureBuilding.collapse_after(m, PackedStringArray()).is_empty(), "nothing falls when nothing is removed")
	# Take the ground-floor front wall away: the front wall upstairs, its windows, and the
	# floor and roof edge lose their support along the front.
	var fell := StructureBuilding.collapse_after(m, PackedStringArray([ids.front_0]))
	check(ids.front_1 in fell, "the wall above falls: %s" % fell)
	check(ids.window_1 in fell and ids.window_2 in fell, "with its windows")
	check(not ids.front_0 in fell and not ids.back_0 in fell, "removed parts are not listed, the back wall stands")
	# Without the spine wall the joists span 6 m: overloaded in normal use, but under their
	# own weight they hold.
	var no_spine := StructureBuilding.graph(m, PackedStringArray([ids.spine_0]))
	var weak := StructureSolver.stress_test(no_spine)
	check(ids.floor_1 in weak.failed_parts(), "the floor is overloaded without the spine: %s" % weak.summary)
	var spine := StructureBuilding.collapse_after(m, PackedStringArray([ids.spine_0]))
	check(not ids.floor_1 in spine, "but stands under its own weight: %s" % spine)
	# Plant rooms upstairs: now the floor gives way, taking the partition on it.
	m.apply(C.retag(ids.bed_1, "plant_room"))
	m.apply(C.retag(ids.bed_2, "plant_room"))
	var heavy := StructureBuilding.collapse_after(m, PackedStringArray([ids.spine_0]))
	check(ids.floor_1 in heavy, "the loaded floor falls without the spine wall: %s" % heavy)
	check(ids.partition in heavy, "the partition on it goes too")
	check(not ids.roof in heavy, "the roof stays on the outside walls")
	check(StructureSolver.collapse_after(m, PackedStringArray([ids.spine_0])) == heavy, "StructureSolver.collapse_after is the same call")


func _determinism() -> void:
	var a := StructureBuilding.stress_test(Samples.model_house().model)
	var b := StructureBuilding.stress_test(BuildingModel.from_data(Samples.model_house().model.to_data()))
	b.graph_revision = a.graph_revision  # a reloaded model starts counting edits again
	check(a.digest() == b.digest(), "a reloaded design gives the same report")


func _near(x: float, y: float) -> bool:
	return absf(x - y) <= 1e-6 * maxf(1.0, absf(y))
