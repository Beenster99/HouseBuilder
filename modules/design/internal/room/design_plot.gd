class_name DesignPlot
extends Node3D
## The taken contract's plot as a red line on the ground, so players can see what they must
## build inside (the brief's within_plot requirement). A real site loaded from the sites module
## draws its own boundary, so this shows only for briefs with no real site loaded.
## Reads Modules.bus("contracts").active.site.plot ([[x, z], ...]) if that module is there.

const COLOUR := Color(0.85, 0.12, 0.1)
## How often it looks for a change, s.
const EVERY := 0.5

var line: MeshInstance3D
var label: Label3D
var _key := ""
var _age := 10.0


func _ready() -> void:
	name = "ContractPlot"
	line = MeshInstance3D.new()
	line.mesh = ImmediateMesh.new()
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = COLOUR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	line.material_override = mat
	add_child(line)
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0012
	label.font_size = 26
	label.outline_size = 8
	label.outline_modulate = Color(1, 1, 1, 0.85)
	label.modulate = COLOUR
	label.no_depth_test = true
	add_child(label)
	visible = false


func _process(delta: float) -> void:
	_age += delta
	if _age < EVERY:
		return
	_age = 0.0
	var plot := plot_now()
	var key := str(plot)
	if key != _key:
		_key = key
		_draw(plot)


## The outline to draw now ([] for none).
static func plot_now() -> Array:
	var contracts := Modules.bus("contracts")
	if contracts == null or not "active" in contracts:
		return []
	var active: Dictionary = contracts.get("active")
	var site: Variant = active.get("site", {})
	if not site is Dictionary:
		return []
	var plot: Array = (site as Dictionary).get("plot", [])
	if plot.size() < 3:
		return []
	# A real site that is loaded draws its own boundary.
	var sites := Modules.bus("sites")
	if str((site as Dictionary).get("id", "")) != "" and sites != null and sites.has_method("current") \
			and sites.call("current") != null:
		return []
	return plot


func _draw(plot: Array) -> void:
	var im: ImmediateMesh = line.mesh
	im.clear_surfaces()
	visible = not plot.is_empty()
	if plot.is_empty():
		return
	var y := 0.03
	var w := 0.12  # the line drawn as a thin strip, so it reads from above
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in plot.size():
		var a := Vector2(float(plot[i][0]), float(plot[i][1]))
		var b := Vector2(float(plot[(i + 1) % plot.size()][0]), float(plot[(i + 1) % plot.size()][1]))
		lo = lo.min(a)
		hi = hi.max(a)
		var n := (b - a).orthogonal().normalized() * w * 0.5
		var q := [a - n, a + n, b + n, b - n]
		for k: int in [0, 1, 2, 0, 2, 3]:
			var v: Vector2 = q[k]
			im.surface_add_vertex(Vector3(v.x, y, v.y))
	im.surface_end()
	var size := hi - lo
	label.text = "CONTRACT PLOT  %.1f × %.1f m · %.0f m²" % [size.x, size.y, BuildingModel.outline_area(plot)]
	label.position = Vector3((lo.x + hi.x) * 0.5, 0.4, lo.y - 0.6)
