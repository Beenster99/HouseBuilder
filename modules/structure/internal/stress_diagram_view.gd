extends Node3D
## Draws the stress diagram (StructureDiagram) in building coordinates the way FE software
## plots results: solid, lit parts meshed into elements and contoured in banded rainbow
## colours, thin element lines over them, a colour legend beside the model, and Max and Min
## tags on leader lines. Lay it over the building's own view at the same transform; it
## hides itself while the diagram is off.

## Contours: the value rides in UV.x, so bands come out crisp whatever the element size.
const CONTOUR_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float top = 1.0;
uniform float bands = 12.0;
uniform float cut_y = 10000.0;
varying float u;
varying vec3 local;
vec3 jet(float t) {
	t = clamp(t, 0.0, 1.0);
	return clamp(vec3(1.5 - abs(4.0 * t - 3.0), 1.5 - abs(4.0 * t - 2.0), 1.5 - abs(4.0 * t - 1.0)), 0.0, 1.0);
}
void vertex() {
	u = UV.x;
	local = VERTEX;
}
void fragment() {
	if (local.y > cut_y) {
		discard;
	}
	float t = clamp(u / top, 0.0, 1.0);
	float b = (min(floor(t * bands), bands - 1.0) + 0.5) / bands;
	vec3 c = jet(b);
	ALBEDO = c;
	ROUGHNESS = 0.6;
	SPECULAR = 0.3;
}
"""

const LINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float cut_y = 10000.0;
uniform vec4 ink : source_color = vec4(0.05, 0.05, 0.08, 0.22);
varying vec3 local;
void vertex() {
	local = VERTEX;
}
void fragment() {
	if (local.y > cut_y) {
		discard;
	}
	ALBEDO = ink.rgb;
	ALPHA = ink.a;
}
"""

## Element lines sit just off the faces.
const LINE_LIFT := 0.006
const TAG_INK := Color(0.04, 0.04, 0.06)

var bus: Node
var _mesh: MeshInstance3D
var _lines: MeshInstance3D
var _tags: Node3D
var _legend: Node3D
var _mat: ShaderMaterial
var _line_mat: ShaderMaterial
var _centre := Vector3.ZERO
var _radius := 1.0
var _tag_mat: StandardMaterial3D
var _faces: SurfaceTool
var _edges: SurfaceTool
## What is drawn now (tests): {"bars", "panels", "cells", "tags", "legend"}.
var drawn := {"bars": 0, "panels": 0, "cells": 0, "tags": 0, "legend": 0}


func _init() -> void:
	name = "StressDiagram"
	var shader := Shader.new()
	shader.code = CONTOUR_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("bands", float(StructureDiagram.BANDS))
	_mesh = MeshInstance3D.new()
	_mesh.name = "Stress"
	add_child(_mesh)
	var line_shader := Shader.new()
	line_shader.code = LINE_SHADER
	_line_mat = ShaderMaterial.new()
	_line_mat.shader = line_shader
	_lines = MeshInstance3D.new()
	_lines.name = "Mesh"
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lines)
	_tag_mat = StandardMaterial3D.new()
	_tag_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tag_mat.albedo_color = TAG_INK
	_tag_mat.no_depth_test = true
	_tag_mat.render_priority = 2
	_tags = Node3D.new()
	_tags.name = "Tags"
	add_child(_tags)
	_legend = Node3D.new()
	_legend.name = "Legend"
	add_child(_legend)


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
	for n: Node3D in [_tags, _legend]:
		for c in n.get_children():
			n.remove_child(c)
			c.queue_free()
	drawn = {"bars": 0, "panels": 0, "cells": 0, "tags": 0, "legend": 0}
	_mesh.mesh = null
	_lines.mesh = null
	if d.is_empty():
		return
	var top := float(d.get("top", 1.0))
	_mat.set_shader_parameter("top", top)
	var cut := float(d.get("cut_y", StructureDiagram.NO_CUT))
	_mat.set_shader_parameter("cut_y", cut)
	_line_mat.set_shader_parameter("cut_y", cut)
	_faces = SurfaceTool.new()
	_faces.begin(Mesh.PRIMITIVE_TRIANGLES)
	_edges = SurfaceTool.new()
	_edges.begin(Mesh.PRIMITIVE_LINES)
	_add_bars(d)
	_add_panels(d)
	if drawn.bars + drawn.cells > 0:
		_faces.set_material(_mat)
		_mesh.mesh = _faces.commit()
		_edges.set_material(_line_mat)
		_lines.mesh = _edges.commit()
	_faces = null
	_edges = null
	var lo: Vector3 = d.get("box_lo", Vector3.ZERO)
	var hi: Vector3 = d.get("box_hi", Vector3.ZERO)
	var reach := maxf((hi - lo).length() * 0.12, 1.0)
	var centre := (lo + hi) * 0.5
	var hot_p: PackedVector3Array = d.get("hot_p", PackedVector3Array())
	var hot_u: PackedFloat32Array = d.get("hot_u", PackedFloat32Array())
	var hot_t: PackedStringArray = d.get("hot_t", PackedStringArray())
	for i in hot_p.size():
		var what := hot_t[i] if i < hot_t.size() else ""
		var head := "MAX %s" % _pct(hot_u[i]) if i == 0 else _pct(hot_u[i])
		_tag(hot_p[i], "%s\n%s" % [head, what] if what != "" else head, centre, reach * (1.0 + 0.35 * i), i == 0)
	if hot_p.size() > 0 and d.has("min_p"):
		_tag(d.min_p, "MIN %s" % _pct(float(d.min_u)), centre, reach * 0.8, false)
	_build_legend(top, lo, hi)


func _process(_delta: float) -> void:
	if not visible or _legend.get_child_count() == 0:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	# Stand the legend to the viewer's right of the model, facing them, upright and at the
	# model's scale.
	var cam_local := global_transform.affine_inverse() * cam.global_position
	var to_cam := cam_local - _centre
	to_cam.y = 0.0
	if to_cam.length_squared() < 1e-6:
		return
	var right := Vector3.UP.cross(to_cam.normalized())
	_legend.position = Vector3(_centre.x, _legend.position.y, _centre.z) + right * _radius
	var s := _legend.global_basis.get_scale()
	to_cam = cam.global_position - _legend.global_position
	to_cam.y = 0.0
	_legend.global_basis = Basis.looking_at(-to_cam.normalized(), Vector3.UP).scaled(s)


static func _pct(u: float) -> String:
	return "no support" if u >= 2.5 else "%d%%" % roundi(u * 100.0)


func _add_bars(d: Dictionary) -> void:
	var bars: PackedVector3Array = d.get("bars", PackedVector3Array())
	var sizes: PackedFloat32Array = d.get("bar_d", PackedFloat32Array())
	var us: PackedByteArray = d.get("bar_u", PackedByteArray())
	var n := StructureDiagram.SAMPLES
	if us.size() != bars.size() / 2 * n:
		return
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
		var corners: Array[Vector3] = [side + up, -side + up, -side - up, side - up]
		for k in n:
			var p := a.lerp(b, float(k) / float(n - 1))
			for q in 4:
				_line(p + corners[q], p + corners[(q + 1) % 4], corners[q] + corners[(q + 1) % 4])
			if k == n - 1:
				break
			var p1 := a.lerp(b, float(k + 1) / float(n - 1))
			var u0 := StructureDiagram.from_byte(us[i * n + k])
			var u1 := StructureDiagram.from_byte(us[i * n + k + 1])
			for q in 4:
				var e0 := corners[q]
				var e1 := corners[(q + 1) % 4]
				_quad(p + e0, p + e1, p1 + e1, p1 + e0, u0, u0, u1, u1)
				_line(p + e0, p1 + e0, e0)
		for end in 2:
			var p := a if end == 0 else b
			var ue := StructureDiagram.from_byte(us[i * n + (0 if end == 0 else n - 1)])
			_quad(p + corners[0], p + corners[1], p + corners[2], p + corners[3], ue, ue, ue, ue)
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
		var at := func(i: int, j: int, face: float) -> Vector3:
			return o[p] + xs[p] * (float(i) / (cols - 1)) + ys[p] * (float(j) / (rows - 1)) + ns[p] * face
		var val := func(i: int, j: int) -> float:
			return StructureDiagram.from_byte(us[ui + j * cols + i])
		var has := func(i: int, j: int) -> bool:
			return i >= 0 and j >= 0 and i < cols - 1 and j < rows - 1 and ms[mi + j * (cols - 1) + i] == 1
		var lift := ns[p].normalized() * LINE_LIFT
		for j in rows - 1:
			for i in cols - 1:
				if not has.call(i, j):
					continue
				var u00: float = val.call(i, j)
				var u10: float = val.call(i + 1, j)
				var u11: float = val.call(i + 1, j + 1)
				var u01: float = val.call(i, j + 1)
				for face in [1.0, -1.0]:
					var q00: Vector3 = at.call(i, j, face)
					var q10: Vector3 = at.call(i + 1, j, face)
					var q11: Vector3 = at.call(i + 1, j + 1, face)
					var q01: Vector3 = at.call(i, j + 1, face)
					_quad(q00, q10, q11, q01, u00, u10, u11, u01)
					var off: Vector3 = lift * face
					_line(q00, q10, off)
					_line(q00, q01, off)
					if not has.call(i + 1, j):
						_line(q10, q11, off)
					if not has.call(i, j + 1):
						_line(q01, q11, off)
				# Close the solid where the panel ends: its edges, ends and opening reveals.
				for side: Array in [[0, -1, 0, 0, 1, 0], [1, 0, 1, 0, 1, 1], [0, 1, 0, 1, 1, 1], [-1, 0, 0, 0, 0, 1]]:
					if has.call(i + int(side[0]), j + int(side[1])):
						continue
					var i0: int = i + int(side[2])
					var j0: int = j + int(side[3])
					var i1: int = i + int(side[4])
					var j1: int = j + int(side[5])
					var v0: float = val.call(i0, j0)
					var v1: float = val.call(i1, j1)
					var f0: Vector3 = at.call(i0, j0, 1.0)
					var f1: Vector3 = at.call(i1, j1, 1.0)
					var b0: Vector3 = at.call(i0, j0, -1.0)
					var b1: Vector3 = at.call(i1, j1, -1.0)
					_quad(f0, f1, b1, b0, v0, v1, v1, v0)
					_line(f0, b0, Vector3.ZERO)
				drawn.cells += 1
		ui += cols * rows
		mi += (cols - 1) * (rows - 1)
		drawn.panels += 1


func _quad(a: Vector3, b: Vector3, c: Vector3, e: Vector3, ua: float, ub: float, uc: float, ue: float) -> void:
	var nrm := (b - a).cross(e - a)
	if nrm.length_squared() < 1e-12:
		nrm = (c - b).cross(e - b)
	nrm = nrm.normalized()
	for v: Array in [[a, ua], [b, ub], [c, uc], [a, ua], [c, uc], [e, ue]]:
		_faces.set_normal(nrm)
		_faces.set_uv(Vector2(float(v[1]), 0.0))
		_faces.add_vertex(v[0])


func _line(a: Vector3, b: Vector3, lift: Vector3) -> void:
	var off := lift.normalized() * LINE_LIFT if lift.length_squared() > 1e-12 else Vector3.ZERO
	_edges.add_vertex(a + off)
	_edges.add_vertex(b + off)


## A tag on a leader line: a small dot at the point, a line up and out, the text at its end.
func _tag(p: Vector3, text: String, centre: Vector3, reach: float, worst: bool) -> void:
	var out := Vector3(p.x - centre.x, 0.0, p.z - centre.z)
	out = out.normalized() if out.length_squared() > 1e-6 else Vector3.RIGHT
	var end := p + Vector3(0, reach, 0) + out * reach * 0.6
	var tag := Node3D.new()
	_tags.add_child(tag)
	var dot := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.07 * reach
	ball.height = ball.radius * 2.0
	ball.radial_segments = 10
	ball.rings = 5
	dot.mesh = ball
	dot.material_override = _tag_mat
	dot.position = p
	tag.add_child(dot)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, _tag_mat)
	im.surface_add_vertex(p)
	im.surface_add_vertex(end)
	im.surface_end()
	var lead := MeshInstance3D.new()
	lead.mesh = im
	tag.add_child(lead)
	var label := Label3D.new()
	label.text = text
	label.position = end
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 30 if worst else 24
	label.outline_size = 14
	label.modulate = TAG_INK
	label.outline_modulate = Color(1, 1, 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.render_priority = 3
	label.outline_render_priority = 2
	tag.add_child(label)
	drawn.tags += 1


## The colour legend: BANDS blocks from 0 to top, values beside them, standing beside the
## model and turning to face whoever looks.
func _build_legend(top: float, lo: Vector3, hi: Vector3) -> void:
	var size := hi - lo
	var height := maxf(size.y, 3.0)
	var width := height * 0.09
	_centre = (lo + hi) * 0.5
	_radius = Vector2(size.x, size.z).length() * 0.5 + width * 2.0
	_legend.position = Vector3(hi.x + width * 2.0, lo.y, _centre.z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bands := StructureDiagram.BANDS
	var step := height / bands
	for k in bands:
		var c := StructureDiagram.jet((float(k) + 0.5) / bands)
		var y0 := k * step
		var y1 := (k + 1) * step
		for v: Vector3 in [Vector3(0, y0, 0), Vector3(width, y0, 0), Vector3(width, y1, 0),
				Vector3(0, y0, 0), Vector3(width, y1, 0), Vector3(0, y1, 0)]:
			st.set_color(c)
			st.add_vertex(v)
	var bar_mat := StandardMaterial3D.new()
	bar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bar_mat.vertex_color_use_as_albedo = true
	bar_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(bar_mat)
	var bar := MeshInstance3D.new()
	bar.name = "Bar"
	bar.mesh = st.commit()
	bar.position.x = -width * 0.5
	_legend.add_child(bar)
	var text_px := height * 0.0009
	for k in range(0, bands + 1, 2):
		_legend_label("%d%%" % roundi(top * 100.0 * k / bands), Vector3(width * 0.7, k * step, 0), text_px, 40)
	if top > 1.0:
		var y := height / top
		_legend_label("◀ capacity", Vector3(width * 0.7, y, 0), text_px, 34, Color(0.55, 0.0, 0.0))
	var title := _legend_label("Utilisation\n% of capacity", Vector3(-width * 0.5, height + step * 0.8, 0), text_px, 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	drawn.legend = bands


func _legend_label(text: String, at: Vector3, px: float, size: int, colour: Color = TAG_INK) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = at
	l.pixel_size = px
	l.font_size = size
	l.outline_size = 14
	l.modulate = colour
	l.outline_modulate = Color(1, 1, 1)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.double_sided = true
	_legend.add_child(l)
	return l
