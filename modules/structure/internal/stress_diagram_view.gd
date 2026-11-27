extends Node3D
## Draws the stress diagram (StructureDiagram) in building coordinates: walls and floors as
## colour-graded sheets on both faces, beams, columns and foundations as graded boxes, and a
## pulsing marker with its utilisation over each of the worst spots. Lay it over the
## building's own view at the same transform; it hides itself while the diagram is off.

const PULSE_SPEED := 3.0
const MARK_SIZE := 0.35
## Faces working at least this hard are drawn solid; the rest see-through, so the trouble
## inside a building (a floor, a beam) shows through its walls.
const SOLID_FROM := 0.6
const SEE_THROUGH := 0.38

var bus: Node
var _mesh: MeshInstance3D
var _glass: MeshInstance3D
var _glass_mat: StandardMaterial3D
var _solid: SurfaceTool
var _clear: SurfaceTool
var _marks: Node3D
var _mat: StandardMaterial3D
var _mark_mat: StandardMaterial3D
var _age := 0.0
## What is drawn now (tests): {"bars", "panels", "cells", "marks"}.
var drawn := {"bars": 0, "panels": 0, "cells": 0, "marks": 0}


func _init() -> void:
	name = "StressDiagram"
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh = MeshInstance3D.new()
	_mesh.name = "Stress"
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_glass_mat = _mat.duplicate() as StandardMaterial3D
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_glass = MeshInstance3D.new()
	_glass.name = "Glass"
	_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glass)
	_mark_mat = StandardMaterial3D.new()
	_mark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mark_mat.albedo_color = Color(1.0, 0.1, 0.35, 0.55)
	_mark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mark_mat.no_depth_test = true
	_mark_mat.render_priority = 2
	_marks = Node3D.new()
	_marks.name = "Worst"
	add_child(_marks)


## bus: the structure bus (or a stand-in with diagram_on, last_report(), report_changed and
## diagram_changed).
func bind(p_bus: Node) -> void:
	bus = p_bus
	bus.report_changed.connect(func(_r: StructureReport) -> void: redraw())
	bus.diagram_changed.connect(func(_on: bool) -> void: redraw())
	redraw()


func redraw() -> void:
	if bus == null:
		return
	visible = bool(bus.get("diagram_on"))
	var report: StructureReport = bus.call("last_report")
	show_diagram(report.diagram if report != null and visible else {})


## Draws one diagram (StructureDiagram.build's result); {} clears it.
func show_diagram(d: Dictionary) -> void:
	for c in _marks.get_children():
		c.queue_free()
	drawn = {"bars": 0, "panels": 0, "cells": 0, "marks": 0}
	_mesh.mesh = null
	_glass.mesh = null
	if d.is_empty():
		return
	_solid = SurfaceTool.new()
	_solid.begin(Mesh.PRIMITIVE_TRIANGLES)
	_clear = SurfaceTool.new()
	_clear.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_bars(d)
	_add_panels(d)
	_mesh.mesh = _finish(_solid, _mat)
	_glass.mesh = _finish(_clear, _glass_mat)
	_solid = null
	_clear = null
	var hot_p: PackedVector3Array = d.get("hot_p", PackedVector3Array())
	var hot_u: PackedFloat32Array = d.get("hot_u", PackedFloat32Array())
	var hot_t: PackedStringArray = d.get("hot_t", PackedStringArray())
	for i in hot_p.size():
		_mark(hot_p[i], hot_u[i], hot_t[i] if i < hot_t.size() else "", i == 0)
	drawn.marks = hot_p.size()


func _process(delta: float) -> void:
	if not visible or _marks.get_child_count() == 0:
		return
	_age += delta
	var s := 1.0 + 0.25 * sin(_age * PULSE_SPEED)
	for m in _marks.get_children():
		var ball := m.get_node_or_null("Ball") as Node3D
		if ball:
			ball.scale = Vector3.ONE * s


func _finish(st: SurfaceTool, mat: Material) -> ArrayMesh:
	var arrays := st.commit_to_arrays()
	if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null or (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		return null
	st.set_material(mat)
	return st.commit()


func _add_bars(d: Dictionary) -> void:
	var bars: PackedVector3Array = d.get("bars", PackedVector3Array())
	var sizes: PackedFloat32Array = d.get("bar_d", PackedFloat32Array())
	var us: PackedByteArray = d.get("bar_u", PackedByteArray())
	var n := StructureDiagram.SAMPLES
	for i in bars.size() / 2:
		var a := bars[i * 2]
		var b := bars[i * 2 + 1]
		var axis := b - a
		if axis.length_squared() < 1e-8:
			continue
		var dir := axis.normalized()
		var side := dir.cross(Vector3.UP)
		if side.length_squared() < 1e-6:
			side = dir.cross(Vector3.RIGHT)
		side = side.normalized() * sizes[i] * 0.5
		var up := side.cross(dir).normalized() * sizes[i] * 0.5
		var corners := [side + up, -side + up, -side - up, side - up]
		for k in n - 1:
			var f0 := float(k) / float(n - 1)
			var f1 := float(k + 1) / float(n - 1)
			var u0 := StructureDiagram.from_byte(us[i * n + k])
			var u1 := StructureDiagram.from_byte(us[i * n + k + 1])
			var c0 := StructureDiagram.colour(u0)
			var c1 := StructureDiagram.colour(u1)
			var hot := maxf(u0, u1) >= SOLID_FROM
			var p0 := a.lerp(b, f0)
			var p1 := a.lerp(b, f1)
			for q in 4:
				var e0: Vector3 = corners[q]
				var e1: Vector3 = corners[(q + 1) % 4]
				_quad(hot, p0 + e0, p0 + e1, p1 + e1, p1 + e0, c0, c0, c1, c1)
		for end in 2:
			var p := a if end == 0 else b
			var ue := StructureDiagram.from_byte(us[i * n + (0 if end == 0 else n - 1)])
			var c := StructureDiagram.colour(ue)
			_quad(ue >= SOLID_FROM, p + corners[0], p + corners[1], p + corners[2], p + corners[3], c, c, c, c)
		drawn.bars += 1


func _add_panels(d: Dictionary) -> void:
	var o: PackedVector3Array = d.get("pan_o", PackedVector3Array())
	var xs: PackedVector3Array = d.get("pan_x", PackedVector3Array())
	var ys: PackedVector3Array = d.get("pan_y", PackedVector3Array())
	var ns: PackedVector3Array = d.get("pan_n", PackedVector3Array())
	var cr: PackedInt32Array = d.get("pan_cr", PackedInt32Array())
	var us: PackedByteArray = d.get("pan_u", PackedByteArray())
	var ms: PackedByteArray = d.get("pan_m", PackedByteArray())
	var ui := 0
	var mi := 0
	for p in o.size():
		var cols := cr[p * 2]
		var rows := cr[p * 2 + 1]
		var colours: Array[Color] = []
		colours.resize(cols * rows)
		for k in cols * rows:
			colours[k] = StructureDiagram.colour(StructureDiagram.from_byte(us[ui + k]))
		for face in [1.0, -1.0]:
			var base: Vector3 = o[p] + ns[p] * face
			for j in rows - 1:
				for i in cols - 1:
					if ms[mi + j * (cols - 1) + i] == 0:
						continue
					var p00 := base + xs[p] * (float(i) / (cols - 1)) + ys[p] * (float(j) / (rows - 1))
					var p10 := base + xs[p] * (float(i + 1) / (cols - 1)) + ys[p] * (float(j) / (rows - 1))
					var p11 := base + xs[p] * (float(i + 1) / (cols - 1)) + ys[p] * (float(j + 1) / (rows - 1))
					var p01 := base + xs[p] * (float(i) / (cols - 1)) + ys[p] * (float(j + 1) / (rows - 1))
					var top := maxi(maxi(us[ui + j * cols + i], us[ui + j * cols + i + 1]),
							maxi(us[ui + (j + 1) * cols + i + 1], us[ui + (j + 1) * cols + i]))
					_quad(StructureDiagram.from_byte(top) >= SOLID_FROM, p00, p10, p11, p01, colours[j * cols + i], colours[j * cols + i + 1],
							colours[(j + 1) * cols + i + 1], colours[(j + 1) * cols + i])
					if face > 0.0:
						drawn.cells += 1
		ui += cols * rows
		mi += (cols - 1) * (rows - 1)
		drawn.panels += 1


func _quad(solid: bool, a: Vector3, b: Vector3, c: Vector3, e: Vector3,
		ca: Color, cb: Color, cc: Color, ce: Color) -> void:
	var st := _solid if solid else _clear
	for v: Array in [[a, ca], [b, cb], [c, cc], [a, ca], [c, cc], [e, ce]]:
		var col: Color = v[1]
		if not solid:
			col.a = SEE_THROUGH
		st.set_color(col)
		st.add_vertex(v[0])


func _mark(p: Vector3, u: float, text: String, worst: bool) -> void:
	var m := Node3D.new()
	m.position = p
	_marks.add_child(m)
	var ball := MeshInstance3D.new()
	ball.name = "Ball"
	var sphere := SphereMesh.new()
	sphere.radius = MARK_SIZE * (1.4 if worst else 1.0)
	sphere.height = sphere.radius * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	ball.mesh = sphere
	ball.material_override = _mark_mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add_child(ball)
	var label := Label3D.new()
	label.name = "Label"
	var amount := "no support" if u >= StructureResult.UNSUPPORTED else "%d%%" % roundi(u * 100.0)
	label.text = "%s  %s" % [amount, text] if text != "" else amount
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0012
	label.font_size = 28 if worst else 22
	label.outline_size = 8
	label.modulate = Color(1.0, 0.92, 0.9)
	label.outline_modulate = Color(0.25, 0.0, 0.05)
	label.render_priority = 3
	label.position = Vector3(0, MARK_SIZE * 2.2, 0)
	m.add_child(label)
