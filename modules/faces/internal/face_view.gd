extends Node3D
## A crewmate's talking face, hung on their avatar's head (MultiplayerBus.avatar_head): a
## bare skin-coloured head (no hat; the suit's headgear is set to none) with the drawn
## features (FaceDrawing, rendered into a small SubViewport) wrapped round its front. No
## outline, just the features (beenster, 28 Nov). The look comes from faces.look, the mouth and mood from the player's face
## state; blinking, the pupils' wander and the laughing bob are worked out here on each
## viewer's machine. The picture is only redrawn when something on it changes.

const FaceDrawing := preload("res://modules/faces/internal/face_drawing.gd")
const FaceStateT := preload("res://modules/faces/api/face_state.gd")
const FaceLookT := preload("res://modules/faces/api/face_look.gd")

const TEXTURE := 256
const BLINK_TIME := 0.14
## The head: a skin-coloured ball just over the avatar's own (radius 0.17), with the face
## wrapped round its front. SPAN is how much of the head (m) the face canvas covers.
const HEAD_RADIUS := 0.176
const SPAN := 0.40
const HEAD_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D face : source_color, filter_linear_mipmap;
uniform vec4 skin : source_color = vec4(0.96, 0.81, 0.68, 1.0);
uniform float span = 0.40;
uniform float lift = 0.0;
varying vec3 local_pos;
void vertex() {
	local_pos = VERTEX;
}
void fragment() {
	// Looking down -Z, like a camera: the canvas's left is the head's right (+X).
	vec2 uv = vec2(0.5 - local_pos.x / span, 0.5 - (local_pos.y - lift) / span);
	float inside = step(local_pos.z, 0.0) * step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	vec4 f = texture(face, clamp(uv, vec2(0.0), vec2(1.0)));
	float a = f.a * inside;
	ALBEDO = mix(skin.rgb, f.rgb, a);
	ROUGHNESS = 0.9;
	// The features stay crisp in shade, like ink.
	EMISSION = f.rgb * a * 0.35;
}
"""

var peer_id := 0
var drawing: Control
var head: MeshInstance3D
var _material: ShaderMaterial
var _lift := 0.0
var _viewport: SubViewport
var _state: FaceState = FaceStateT.new()
var _override: FaceState = null
var _override_left := 0.0
var _rng := RandomNumberGenerator.new()
var _blink_in := 3.0
var _blink_t := -1.0
var _gaze := Vector2.ZERO
var _gaze_to := Vector2.ZERO
var _gaze_in := 1.0
var _time := 0.0


func _init() -> void:
	name = "Face"
	_viewport = SubViewport.new()
	_viewport.name = "FaceViewport"
	_viewport.size = Vector2i(TEXTURE, TEXTURE)
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	drawing = FaceDrawing.new()
	drawing.size = Vector2(TEXTURE, TEXTURE)
	_viewport.add_child(drawing)
	head = MeshInstance3D.new()
	head.name = "Head"
	var ball := SphereMesh.new()
	ball.radius = HEAD_RADIUS
	ball.height = HEAD_RADIUS * 2.0
	ball.radial_segments = 48
	ball.rings = 24
	head.mesh = ball
	var shader := Shader.new()
	shader.code = HEAD_SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("span", SPAN)
	head.material_override = _material
	add_child(head)


func _ready() -> void:
	_rng.seed = hash(peer_id) + 7
	_blink_in = _rng.randf_range(1.5, 4.5)
	_material.set_shader_parameter("face", _viewport.get_texture())
	_redraw()


func set_look(look: FaceLook) -> void:
	drawing.look = look
	if look != null:
		_material.set_shader_parameter("skin", look.skin_colour())
	_redraw()


func look() -> FaceLook:
	return drawing.look


func set_state(s: FaceState) -> void:
	_state = s if s != null else FaceStateT.new()
	_show()


## A face for a few seconds whatever the voice says (an emote's face). The mouth still talks.
func hold_mood(mood: int, seconds: float) -> void:
	_override = FaceStateT.make(FaceStateT.MOUTH_CLOSED, 0, mood)
	_override_left = seconds
	_show()


## What the face shows now.
func shown() -> FaceState:
	return drawing.state


func _show() -> void:
	var s := _state.duplicate_state()
	if _override != null and _override_left > 0.0 and not s.muted:
		if s.mood == FaceStateT.MOOD_NEUTRAL or s.mood == FaceStateT.MOOD_SMILE:
			s.mood = _override.mood
	if not s.equals(drawing.state):
		drawing.state = s
		_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _override_left > 0.0:
		_override_left -= delta
		if _override_left <= 0.0:
			_override = null
			_show()
	# Blinking, at this player's own rhythm.
	var blink := 0.0
	if _blink_t >= 0.0:
		_blink_t += delta
		blink = 1.0 - absf(_blink_t / BLINK_TIME * 2.0 - 1.0)
		if _blink_t >= BLINK_TIME:
			_blink_t = -1.0
			blink = 0.0
	else:
		_blink_in -= delta
		if _blink_in <= 0.0:
			_blink_t = 0.0
			_blink_in = _rng.randf_range(2.0, 5.5)
	# The pupils wander a little round straight ahead (the head already points where they look).
	_gaze_in -= delta
	if _gaze_in <= 0.0:
		_gaze_in = _rng.randf_range(0.8, 2.5)
		_gaze_to = Vector2(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.3, 0.3)) if _rng.randf() < 0.6 else Vector2.ZERO
	_gaze = _gaze.move_toward(_gaze_to, delta * 4.0)
	var b := 1.0 if blink > 0.5 else 0.0
	if b != drawing.blink or not drawing.gaze.is_equal_approx(_gaze.snappedf(0.1)):
		drawing.blink = b
		drawing.gaze = _gaze.snappedf(0.1)
		_redraw()
	# Laughing bobs the head.
	var bob := sin(_time * 22.0) * 0.006 if drawing.state.mouth == FaceStateT.MOUTH_LAUGH else 0.0
	if bob != _lift:
		_lift = bob
		_material.set_shader_parameter("lift", bob)


func _redraw() -> void:
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
