extends ModuleTest
## The stress diagram: an FE-style picture of the stress test over the model. Walls and
## floors come out as graded sheets, frame members as graded bars, the worst spots marked;
## it travels with live reports while the crew has it on, and draws in 3D.
##   tools/run_tests.sh structure

const Samples := preload("res://modules/structure/tests/samples.gd")
const View := preload("res://modules/structure/internal/stress_diagram_view.gd")


class FakeDesign:
	extends Node
	var layers := {}

	func register_action(_id: String, _label: String, _press: Callable, _order: int = 50) -> void:
		pass

	func unregister_action(_id: String) -> void:
		pass

	func register_overlay(_id: String, _label: String, _tints: Callable, _panel: Callable = Callable(), _order: int = 50) -> void:
		pass

	func unregister_overlay(_id: String) -> void:
		pass

	func refresh_overlay(_id: String) -> void:
		pass

	func register_layer(id: String, label: String, make: Callable, toggle: Callable, is_on: Callable, order: int = 50) -> void:
		layers[id] = {"label": label, "make": make, "toggle": toggle, "is_on": is_on, "order": order}

	func unregister_layer(id: String) -> void:
		layers.erase(id)


func run_tests() -> void:
	await get_tree().process_frame
	var design := Modules.bus("design")
	if design and design.has_method("register_layer") and Flags.is_on(StructureBus.DIAGRAM_FLAG):
		check(design.layers.has(StructureBus.LAYER), "the design room and holotable list the stress diagram")
	_scale()
	_build()
	_sends()
	await _live()
	_layer()


func _scale() -> void:
	check(StructureDiagram.colour(0.0).b > 0.4 and StructureDiagram.colour(0.0).r < 0.1, "least is blue")
	check(StructureDiagram.colour(0.5).g > 0.9, "half way is green")
	var yellow := StructureDiagram.colour(0.7)
	check(yellow.r > 0.6 and yellow.g > 0.6 and yellow.b < 0.2, "higher is yellow")
	var red := StructureDiagram.colour(1.0)
	check(red.r > 0.5 and red.g < 0.1 and red.b < 0.1, "the top of the legend is red")
	check(StructureDiagram.colour(0.51, 2.0) == StructureDiagram.colour(0.52, 2.0), "in bands, like a contour plot")
	check(StructureDiagram.profile("bending", 0.5, false, 0.0, 0.0) > StructureDiagram.profile("bending", 0.0, false, 0.0, 0.0),
			"a beam bends most at mid-span")
	check(StructureDiagram.profile("bending", 0.0, true, 0.0, 0.0) > StructureDiagram.profile("bending", 1.0, true, 0.0, 0.0),
			"a cantilever at its root")
	check(StructureDiagram.profile("axial", 0.0, false, 0.0, 0.0) > StructureDiagram.profile("axial", 1.0, false, 0.0, 0.0),
			"a column at its foot")


func _build() -> void:
	var h := Samples.model_house()
	var model: BuildingModel = h.model
	var g := StructureBuilding.graph(model)
	var sound := StructureSolver.stress_test(g)
	var d := StructureDiagram.build(g, sound)
	var walls := 0
	for id: String in g.shapes:
		if str(g.shapes[id].type) == "wall":
			walls += 1
	check(walls >= 9, "the walls are drawn as walls (%d)" % walls)
	check((d.pan_o as PackedVector3Array).size() >= walls, "each a sheet, and the floors too (%d)" % (d.pan_o as PackedVector3Array).size())
	var cells := 0
	var cr: PackedInt32Array = d.pan_cr
	for p in cr.size() / 2:
		cells += cr[p * 2] * cr[p * 2 + 1]
	check((d.pan_u as PackedByteArray).size() == cells, "a value at every grid point")
	var holes := (d.pan_m as PackedByteArray).count(0)
	check(holes > 0, "with the doors and windows left out (%d cells)" % holes)
	check((d.bars as PackedVector3Array).size() / 2 * StructureDiagram.SAMPLES == (d.bar_u as PackedByteArray).size(),
			"bars graded along their length")
	var shades := {}
	for b in d.pan_u:
		shades[b / 10] = true
	check(shades.size() >= 3, "graded, not flat (%d bands)" % shades.size())
	var worst := 0.0
	for u in d.hot_u:
		worst = maxf(worst, u)
	check(worst < 1.0, "a sound house has nothing over the limit (%d amber spots)" % (d.hot_u as PackedFloat32Array).size())

	model.apply(BuildingCommands.delete([h.ids.spine_0, h.ids.strip_spine]))
	g = StructureBuilding.graph(model)
	var broken := StructureSolver.stress_test(g)
	d = StructureDiagram.build(g, broken)
	check(not broken.passed() and (d.hot_p as PackedVector3Array).size() > 0, "taking the spine wall out marks the hot spots")
	check(float(d.hot_u[0]) >= 1.0, "worst first, over the limit (%.0f%%)" % (float(d.hot_u[0]) * 100.0))
	var peak := 0
	for b in d.pan_u:
		peak = maxi(peak, b)
	check(peak >= 100, "and the floor it held goes over capacity")
	var view := View.new()
	add_child(view)
	view.show_diagram(d)
	check(view.drawn.cells > 0 and view.drawn.bars > 0, "drawn in 3D: %s" % [view.drawn])
	check(view.drawn.tags == (d.hot_p as PackedVector3Array).size() + 1, "tagged Max and Min")
	check(view.drawn.legend == StructureDiagram.BANDS, "with a legend")
	check(view.get_node("Stress").mesh != null and view.get_node("Mesh").mesh != null, "solid parts with element lines")
	check(float(d.top) >= float(d.hot_u[0]) - 0.01 and float(d.top) <= 2.55, "the legend reaches the worst value (%.2f)" % float(d.top))
	view.show_diagram({})
	check(view.get_node("Stress").mesh == null and view.get_node("Mesh").mesh == null, "and cleared")
	view.free()


func _sends() -> void:
	var h := Samples.model_house()
	var g := StructureBuilding.graph(h.model)
	var full := StructureSolver.stress_test(g)
	var digest := full.compact().digest()
	full.diagram = StructureDiagram.build(g, full)
	var small := full.compact()
	check(small.digest() == digest, "the diagram leaves the report's fingerprint alone")
	var wire := StructureReport.from_dict(bytes_to_var(var_to_bytes(small.to_dict())))
	check((wire.diagram.pan_u as PackedByteArray) == (full.diagram.pan_u as PackedByteArray), "and arrives whole")
	var size := var_to_bytes(small.diagram).size()
	check(size < 64 * 1024, "small enough to send with each report (%d bytes)" % size)


func _live() -> void:
	var bus := StructureBus.new()
	var model: BuildingModel = Samples.model_house().model
	var reports: Array = []
	bus.report_changed.connect(func(r: StructureReport) -> void: reports.append(r))
	bus.watch(model)
	await _run(bus, func() -> bool: return not reports.is_empty())
	check(reports.size() == 1 and reports[0].diagram.is_empty(), "off by default: reports carry no diagram")
	var flips: Array = []
	bus.diagram_changed.connect(func(on: bool) -> void: flips.append(on))
	var view: Node3D = bus.make_diagram()
	add_child(view)
	check(not view.visible, "the view hides while off")
	bus.set_diagram(true)
	check(flips == [true] and bus.diagram_on, "turned on")
	await _run(bus, func() -> bool: return reports.size() >= 2)
	check(reports.size() == 2 and not reports[1].diagram.is_empty(), "the next check brings the diagram at once")
	check(view.visible and view.drawn.cells > 0, "and the view draws it")
	check(bus.get_net_snapshot().diagram == true, "late joiners get it on")
	bus.toggle_diagram()
	check(not bus.diagram_on and not view.visible, "toggled off again")
	bus.watch(null)
	view.free()
	bus.free()


func _layer() -> void:
	var bus := StructureBus.new()
	var design := FakeDesign.new()
	bus.hook_design(design)
	check(design.layers.has(StructureBus.LAYER) and design.layers[StructureBus.LAYER].label == "Stress diagram",
			"the diagram offers itself as a layer for the table and the 3D view")
	var layer: Dictionary = design.layers[StructureBus.LAYER]
	(layer.toggle as Callable).call()
	check(bool((layer.is_on as Callable).call()), "the layer's toggle turns it on")
	var node: Node3D = (layer.make as Callable).call(null)
	check(node != null and node.name == "StressDiagram", "and makes its 3D view")
	node.free()
	design.free()
	bus.free()


func _run(bus: StructureBus, done: Callable, seconds: float = 30.0) -> void:
	var start := Time.get_ticks_msec()
	while not done.call() and Time.get_ticks_msec() - start < seconds * 1000.0:
		bus._process(0.1)
		await get_tree().process_frame
