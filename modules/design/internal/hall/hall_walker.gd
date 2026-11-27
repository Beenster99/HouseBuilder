extends CharacterBody3D
## This player in the design hall, first person: WASD to walk (Keys' movement actions),
## Shift to run, the mouse to look. The camera is the one the crew module copies each player's
## head from, so everyone sees everyone's avatar walking round the room.

const EYE := 1.65
const WALK := 3.2
const RUN := 6.0
const LOOK := 0.0025
const GRAVITY := 18.0

var camera: Camera3D
## False while the designer, a full-screen panel or walk-inside has the player.
var enabled := true
var _pitch := -0.1


func _ready() -> void:
	name = "Walker"
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)
	camera = Camera3D.new()
	camera.name = "Eyes"
	camera.fov = 72.0
	camera.position.y = EYE
	camera.near = 0.05
	add_child(camera)
	camera.current = true


func look_at_point(p: Vector3) -> void:
	var d := p - (global_position + Vector3(0, EYE, 0))
	rotation.y = atan2(-d.x, -d.z)
	_pitch = atan2(d.y, Vector2(d.x, d.z).length())
	camera.rotation.x = _pitch


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		rotation.y -= mm.relative.x * LOOK
		_pitch = clampf(_pitch - mm.relative.y * LOOK, -1.45, 1.45)
		camera.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	var move := Vector2.ZERO
	if enabled and not Keys.typing():
		move = Input.get_vector(Keys.LEFT, Keys.RIGHT, Keys.FORWARD, Keys.BACK)
	var speed := RUN if enabled and Input.is_action_pressed(Keys.RUN) else WALK
	var dir := (global_basis * Vector3(move.x, 0, move.y)).normalized() * speed
	velocity.x = dir.x
	velocity.z = dir.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
