extends RefCounted
## Test buildings for the structure tests.


## Two-storey steel-framed house, 8 m by 6 m: columns on a 4 m by 6 m grid on pad
## footings in clay, steel floor beams spanning 6 m, a pitched roof of rafters to a ridge,
## and cross braces in the end and side bays. A sensible design that should pass.
static func house(braced: bool = true, order_seed: int = 0) -> StructureGraph:
	var g := StructureGraph.new()
	var xs := [0.0, 4.0, 8.0]
	var zs := [0.0, 6.0]
	var levels := [0.0, 2.8, 5.6]
	var ops: Array[Callable] = []
	var pad := StructureSections.foundation_capacity("pad", 1.0, "clay")
	# Nodes first (members need them), in a shuffled order when asked.
	var node_ops: Array[Callable] = []
	for xi in xs.size():
		for zi in zs.size():
			for li in levels.size():
				var id := "n%d%d%d" % [xi, zi, li]
				var p := Vector3(xs[xi], levels[li], zs[zi])
				if li == 0:
					node_ops.append(func() -> void: g.add_anchor(id, p, pad))
				else:
					node_ops.append(func() -> void: g.add_node(id, p))
		var rid := "r%d" % xi
		var rp := Vector3(xs[xi], 7.6, 3.0)
		node_ops.append(func() -> void: g.add_node(rid, rp))
	_shuffle(node_ops, order_seed)
	for op in node_ops:
		op.call()
	for xi in xs.size():
		var trib := 2.0 if xi != 1 else 4.0
		var floor_sec := "steel.ub_305x165x40" if xi == 1 else "steel.ub_203x133x25"
		for zi in zs.size():
			for li in [1, 2]:
				ops.append(_member.bind(g, "c%d%d%d" % [xi, zi, li], "n%d%d%d" % [xi, zi, li - 1],
						"n%d%d%d" % [xi, zi, li], StructureGraph.COLUMN, "steel.uc_203x203x46", 1.0, {}))
			ops.append(_member.bind(g, "rf%d%d" % [xi, zi], "n%d%d2" % [xi, zi], "r%d" % xi,
					StructureGraph.RAFTER, "steel.ub_203x133x25", trib,
					{"dead": StructureLoads.ROOF_COVERING_KPA, "snow": StructureLoads.SNOW_KPA}))
		# Floor beams span 6 m front to back, carrying a strip trib metres wide.
		ops.append(_member.bind(g, "f%d" % xi, "n%d01" % xi, "n%d11" % xi, StructureGraph.BEAM,
				floor_sec, trib, {"dead": 0.5 + StructureLoads.FLOOR_FINISHES_KPA,
				"live": StructureLoads.live_kpa("bedroom")}))
		ops.append(_member.bind(g, "t%d" % xi, "n%d02" % xi, "n%d12" % xi, StructureGraph.BEAM,
				"steel.ub_203x133x25", trib, {"dead": 0.5, "live": 0.25}))
	# Edge beams along the front and back, and the ridge.
	for xi in [0, 1]:
		for zi in zs.size():
			for li in [1, 2]:
				ops.append(_member.bind(g, "e%d%d%d" % [xi, zi, li], "n%d%d%d" % [xi, zi, li],
						"n%d%d%d" % [xi + 1, zi, li], StructureGraph.BEAM, "steel.ub_203x133x25", 1.0, {}))
		ops.append(_member.bind(g, "ridge%d" % xi, "r%d" % xi, "r%d" % (xi + 1), StructureGraph.BEAM,
				"steel.ub_203x133x25", 1.0, {}))
	if braced:
		for li in [1, 2]:
			# Side bays (push along x) and end bays (push along z).
			ops.append(_member.bind(g, "bx0%d" % li, "n00%d" % (li - 1), "n10%d" % li, StructureGraph.BRACE, "steel.angle_100x100x8", 1.0, {}))
			ops.append(_member.bind(g, "bx1%d" % li, "n21%d" % (li - 1), "n11%d" % li, StructureGraph.BRACE, "steel.angle_100x100x8", 1.0, {}))
			ops.append(_member.bind(g, "bz0%d" % li, "n00%d" % (li - 1), "n01%d" % li, StructureGraph.BRACE, "steel.angle_100x100x8", 1.0, {}))
			ops.append(_member.bind(g, "bz2%d" % li, "n21%d" % (li - 1), "n20%d" % li, StructureGraph.BRACE, "steel.angle_100x100x8", 1.0, {}))
	_shuffle(ops, order_seed)
	for op in ops:
		op.call()
	g.auto_wind_areas(3.0)
	return g


static func _member(g: StructureGraph, id: String, a: String, b: String, kind: String, section: String,
		width: float, kpa: Dictionary) -> void:
	var why := g.add_member(id, a, b, kind, section, width)
	assert(why == "", why)
	for case: String in kpa:
		g.add_area_load(id, case, kpa[case])


static func _shuffle(ops: Array[Callable], order_seed: int) -> void:
	if order_seed == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = order_seed
	for i in range(ops.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := ops[i]
		ops[i] = ops[j]
		ops[j] = t


## A two-storey masonry house as a BuildingModel, 8 m by 6 m: cavity walls on strip
## footings, a blockwork spine wall across the middle, a joisted timber first floor, a
## pitched roof, a front door and windows, and bedrooms upstairs. Returns {model, ids}
## where ids names the parts ("front_0", "spine_0", "floor_1", ...).
static func model_house() -> Dictionary:
	var C := BuildingCommands
	var m := BuildingModel.new("test_house", "Test house", BuildingCatalog.default_catalog())
	var ids := {}
	var put := func(key: String, op: Dictionary) -> void:
		var r := m.apply(op)
		assert(not r.is_empty(), "refused: %s" % key)
		ids[key] = str(r.do.entry.id) if r.do.has("entry") else ""
	m.apply(C.add_level(3.0, "First floor"))
	var walls := {"front": [[0, 0, 0], [8, 0, 0]], "right": [[8, 0, 0], [8, 0, 6]],
			"back": [[8, 0, 6], [0, 0, 6]], "left": [[0, 0, 6], [0, 0, 0]]}
	for w: String in ["front", "right", "back", "left"]:
		put.call("strip_" + w, C.place_part("strip_footing", 0, {"a": walls[w][0], "b": walls[w][1]}, "concrete", "strip_600x225"))
		for lv in [0, 1]:
			put.call("%s_%d" % [w, lv], C.place_part("wall_loadbearing", lv, {"a": walls[w][0], "b": walls[w][1]}, "masonry", "wall_cavity_300"))
	put.call("strip_spine", C.place_part("strip_footing", 0, {"a": [4, 0, 0], "b": [4, 0, 6]}, "concrete", "strip_600x225"))
	put.call("spine_0", C.place_part("wall_loadbearing", 0, {"a": [4, 0, 0], "b": [4, 0, 6]}, "masonry", "wall_block_140"))
	put.call("ground", C.place_part("slab", 0, {"outline": C.rect(0, 0, 8, 6), "y": 0.0}, "concrete", "slab_150"))
	put.call("floor_1", C.place_part("slab", 1, {"outline": C.rect(0, 0, 8, 6), "y": 0.0}, "timber", "floor_joist_225"))
	put.call("roof", C.place_part("roof_pitched", 1, {"outline": C.rect(0, 0, 8, 6), "y": 3.0}, "timber"))
	put.call("door", C.place_opening("door_external", ids.front_0, 2.0))
	put.call("window_0", C.place_opening("window_medium", ids.front_0, 6.0))
	put.call("window_1", C.place_opening("window_medium", ids.front_1, 2.0))
	put.call("window_2", C.place_opening("window_medium", ids.front_1, 6.0))
	put.call("bed_1", C.place_room("bedroom", 1, C.rect(0, 0, 4, 6), "Bedroom 1"))
	put.call("bed_2", C.place_room("bedroom", 1, C.rect(4, 0, 4, 6), "Bedroom 2"))
	put.call("partition", C.place_part("wall_partition", 1, {"a": [2, 0, 0], "b": [2, 0, 6]}, "timber"))
	return {"model": m, "ids": ids}
