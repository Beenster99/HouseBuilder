extends Node3D
## A crewmate's talking face, hung on their avatar's head (MultiplayerBus.avatar_head): the
## drawn face (FaceDrawing) rendered into a small SubViewport and shown on a flat round plate
## where the helmet's visor is, unshaded so it reads the same in the model look and the
## realistic one. The look comes from faces.look, the mouth and mood from the player's face
## state; blinking, the pupils' wander and the laughing bob are worked out here on each
## viewer's machine. The picture is only redrawn when something on it changes.

const FaceDrawing := preload("res://modules/faces/internal/face_drawing.gd")
const FaceStateT := preload("res://modules/faces/api/face_state.gd")
const FaceLookT := preload("res://modules/faces/api/face_look.gd")

const PLATE := 0.27
## In front of the helmet (radius 0.17) and its visor (to 0.18).
const PLATE_Z := -0.186
const TEXTURE := 256
const BLINK_TIME := 0.14
## Under a hard hat or cap there is no head below the brim, so the face hangs lower (just
## under the brim) with a skin-coloured head behind it for side views.
const UNDER_HAT_Y := -0.085
const UNDER_HAT_PLATE := 0.25

var peer_id := 0
var drawing: Control
var plate: MeshInstance3D
var skull: MeshInstance3D
var _plate_y := -0.005
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
	plate = MeshInstance3D.new()
	plate.name = "Plate"
	var quad := QuadMesh.new()
	quad.size = Vector2(PLATE, PLATE)
	plate.mesh = quad
	plate.position = Vector3(0, -0.005, PLATE_Z)
	plate.rotation = Vector3(0, PI, 0)
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	plate.material_override = mat
	add_child(plate)
	skull = MeshInstance3D.new()
	skull.name = "Skull"
	var ball := SphereMesh.new()
	ball.radius = 0.125
	ball.height = 0.25
	skull.mesh = ball
	skull.position = Vector3(0, UNDER_HAT_Y, -0.05)
	skull.material_override = StandardMaterial3D.new()
	skull.visible = false
	add_child(skull)


func _ready() -> void:
	_rng.seed = hash(peer_id) + 7
	_blink_in = _rng.randf_range(1.5, 4.5)
	(plate.material_override as StandardMaterial3D).albedo_texture = _viewport.get_texture()
	_redraw()


func set_look(look: FaceLook) -> void:
	drawing.look = look
	var hat := look != null and (look.headgear == FaceLookT.HARD_HAT or look.headgear == FaceLookT.CAP)
	_plate_y = UNDER_HAT_Y if hat else -0.005
	(plate.mesh as QuadMesh).size = Vector2.ONE * (UNDER_HAT_PLATE if hat else PLATE)
	plate.position.y = _plate_y
	skull.visible = hat
	if look != null:
		(skull.material_override as StandardMaterial3D).albedo_color = look.skin_colour()
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


## What the plate shows now.
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
	var bob := sin(_time * 22.0) * 0.008 if drawing.state.mouth == FaceStateT.MOUTH_LAUGH else 0.0
	plate.position.y = _plate_y + bob


func _redraw() -> void:
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
