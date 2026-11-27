extends Node3D
## The "Service runs" 3D layer: every route in the last report drawn in building coordinates
## as a thin coloured tube per system (ServicesRates.COLOURS), with a block at each source
## and a dot at every point it feeds. Drawn over the building (no depth test) so the runs read
## through walls and floors; the design view goes see-through while it is on. It follows
## every report and hides itself while the layer is off (ServicesBus.runs_on).

## Tube thickness by system, m: cables thin, pipes thicker, waste thickest.
const THICK := {"power": 0.03, "lighting": 0.03, "cold_water": 0.045, "hot_water": 0.045, "heating": 0.05, "waste": 0.08}
const END_DOT := 0.09
const SOURCE_BLOCK := 0.25

var bus: Node
var _mesh: MeshInstance3D
var _mats := {}
## What is drawn now (tests): {"segments", "ends", "sources"}.
var drawn := {"segments": 0, "ends": 0, "sources": 0}


func _init() -> void:
	name = "ServiceRuns"
	_mesh = MeshInstance3D.new()
	_mesh.name = "Runs"
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func bind(p_bus: Node) -> void:
	bus = p_bus
	bus.report_changed.connect(func(r: ServicesReport) -> void: redraw(r))
	bus.runs_changed.connect(_follow)
	redraw(bus.last_report())
	_follow()


func _follow() -> void:
	visible = bool(bus.runs_on) if bus else false


func redraw(report: ServicesReport) -> void:
	drawn = {"segments": 0, "ends": 0, "sources": 0}
	var mesh := ArrayMesh.new()
	if report != null:
		for s: String in ServicesRates.SYSTEMS:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var any := false
			var t := float(THICK.get(s, 0.04))
			for line: Array in report.routes(s):
				for k in range(line.size() - 1):
					_tube(st, line[k], line[k + 1], t)
					drawn.segments += 1
				_cube(st, line[line.size() - 1], END_DOT)
				drawn.ends += 1
				any = true
			var src: Dictionary = report.system(s).get("source", {})
			if src.has("at") and ServicesRates.shares(s) == s:
				var at: Array = src.at
				if at.size() >= 3:
					_cube(st, Vector3(float(at[0]), float(at[1]), float(at[2])), SOURCE_BLOCK)
					drawn.sources += 1
					any = true
			if any:
				st.set_material(_mat(s))
				st.commit(mesh)
	_mesh.mesh = mesh


func _mat(s: String) -> StandardMaterial3D:
	if not _mats.has(s):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = ServicesRates.colour(s)
		m.no_depth_test = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.render_priority = 2
		_mats[s] = m
	return _mats[s]


## A square tube of side t from a to b.
func _tube(st: SurfaceTool, a: Vector3, b: Vector3, t: float) -> void:
	var d := b - a
	if d.length() < 0.001:
		return
	var f := d.normalized()
	var up := Vector3.UP if absf(f.y) < 0.9 else Vector3.RIGHT
	var u := f.cross(up).normalized() * (t * 0.5)
	var v := f.cross(u).normalized() * (t * 0.5)
	var c := [u + v, u - v, -u - v, -u + v]
	for i in 4:
		var p: Vector3 = c[i]
		var q: Vector3 = c[(i + 1) % 4]
		_quad(st, a + p, a + q, b + q, b + p)


func _cube(st: SurfaceTool, at: Vector3, size: float) -> void:
	var h := size * 0.5
	var x := Vector3(h, 0, 0)
	var y := Vector3(0, h, 0)
	var z := Vector3(0, 0, h)
	for f: Array in [[x, y, z], [-x, z, y], [y, z, x], [-y, x, z], [z, x, y], [-z, y, x]]:
		var n: Vector3 = f[0]
		var a: Vector3 = f[1]
		var b: Vector3 = f[2]
		_quad(st, at + n - a - b, at + n + a - b, at + n + a + b, at + n - a + b)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for p: Vector3 in [a, b, c, a, c, d]:
		st.add_vertex(p)
