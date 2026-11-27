class_name InfiniteGrid
extends MeshInstance3D
## Graph paper on a flat plane that never runs out: 1 m lines, every 5th darker, every 50th
## darker still, drawn by a shader in world space so it goes on as far as the eye can see.
## Lines thin out where they would crowd together (zoomed out) and fade with distance from
## the camera. An optional fine snap grid shows near a focus point.
##
##   var grid := InfiniteGrid.new()
##   add_child(grid)
##   grid.height = 3.0            # the plane it lies on (follow the working level)
##   grid.set_snap(0.25, focus)   # fine lines every 0.25 m near `focus`; 0 or >= 1 hides them
##
## It follows the viewing camera each frame (the plane is RADIUS across), so there is no edge.

const RADIUS := 2000.0
const FADE_FROM := 60.0
const FADE_TO := 600.0
const SNAP_REACH := 12.0

var height := 0.0:
	set(v):
		height = v
		_follow()
var colour := Color(0, 0, 0, 1)

var _mat: ShaderMaterial

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 colour : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float snap_step = 0.0;
uniform vec3 snap_focus = vec3(0.0);
uniform float snap_reach = 12.0;
uniform float fade_from = 60.0;
uniform float fade_to = 600.0;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Coverage of lines every `step` metres, thinning out as they crowd on screen.
float lines(vec2 p, float step) {
	vec2 c = p / step;
	vec2 w = fwidth(c);
	vec2 g = abs(fract(c - 0.5) - 0.5) / max(w, vec2(1e-5));
	float on = 1.0 - min(min(g.x, g.y), 1.0);
	float crowd = max(w.x, w.y);
	return on * (1.0 - smoothstep(0.08, 0.3, crowd));
}

void fragment() {
	vec2 p = world.xz;
	float a = max(max(lines(p, 1.0) * 0.16, lines(p, 5.0) * 0.38), lines(p, 50.0) * 0.5);
	if (snap_step > 0.0 && snap_step < 1.0) {
		float near = 1.0 - smoothstep(snap_reach * 0.75, snap_reach, max(abs(p.x - snap_focus.x), abs(p.y - snap_focus.z)));
		a = max(a, lines(p, snap_step) * 0.07 * near);
	}
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = length(cam.xz - p);
	// An orthographic plan sits high above: measure from the point under it instead.
	a *= 1.0 - smoothstep(fade_from, fade_to, d);
	ALBEDO = colour.rgb;
	ALPHA = a * colour.a;
}
"""


func _init() -> void:
	name = "Grid"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	plane.size = Vector2(RADIUS * 2.0, RADIUS * 2.0)
	mesh = plane
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("fade_from", FADE_FROM)
	_mat.set_shader_parameter("fade_to", FADE_TO)
	_mat.set_shader_parameter("snap_reach", SNAP_REACH)
	material_override = _mat
	extra_cull_margin = 16.0


## Fine snap lines every `step` m within SNAP_REACH of `focus` (hidden when step is 0 or >= 1).
func set_snap(step: float, focus: Vector3) -> void:
	_mat.set_shader_parameter("snap_step", step)
	_mat.set_shader_parameter("snap_focus", focus)


func set_colour(c: Color) -> void:
	colour = c
	_mat.set_shader_parameter("colour", c)


## The shader's current settings, for tests: {snap_step, snap_focus, height}.
func state() -> Dictionary:
	return {"snap_step": float(_mat.get_shader_parameter("snap_step")),
			"snap_focus": _mat.get_shader_parameter("snap_focus"), "height": height}


func _process(_delta: float) -> void:
	_follow()


func _follow() -> void:
	if not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	var at := cam.global_position if cam else Vector3.ZERO
	# Whole-metre steps keep it still under the eye (the lines are in world space anyway).
	global_position = Vector3(roundf(at.x), height, roundf(at.z))
