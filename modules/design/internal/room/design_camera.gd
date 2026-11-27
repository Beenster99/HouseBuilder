extends Camera3D
## The design room's camera: an orbit view in 3D, or a top-down plan in 2D (orthographic,
## north up). Right drag orbits (3D), middle drag or WASD pans, the wheel zooms.

const ORBIT_SPEED := 0.006
const KEY_PAN := 14.0
const ZOOM_STEP := 1.12
const MIN_DIST := 3.0
const MAX_DIST := 160.0
const PLAN_HEIGHT := 120.0

var focus := Vector3.ZERO
var yaw := deg_to_rad(35.0)
var pitch := deg_to_rad(-40.0)
var dist := 28.0
## true: the 2D plan view.
var plan := false
var limit := 60.0
var _orbiting := false
var _panning := false


func _ready() -> void:
	far = 800.0
	place()


func set_plan(on: bool) -> void:
	plan = on
	projection = PROJECTION_ORTHOGONAL if on else PROJECTION_PERSPECTIVE
	place()


func place() -> void:
	if plan:
		size = dist * 1.1
		global_transform = Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0.0, 0.0)),
				focus + Vector3(0, PLAN_HEIGHT, 0))
	else:
		var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
		global_transform = Transform3D(basis, focus + basis.z * dist)


func _process(delta: float) -> void:
	if Keys.typing():
		return
	var pan := Vector2.ZERO
	if InputMap.has_action(Keys.RIGHT):
		pan = Vector2(Input.get_action_strength(Keys.RIGHT) - Input.get_action_strength(Keys.LEFT),
				Input.get_action_strength(Keys.BACK) - Input.get_action_strength(Keys.FORWARD))
	if pan != Vector2.ZERO:
		move_focus(pan * KEY_PAN * delta * (dist / 28.0))
	place()


## Stops an orbit or pan in progress (the mark-up wheel took the middle button).
func stop_drag() -> void:
	_orbiting = false
	_panning = false


func move_focus(d: Vector2) -> void:
	var y := 0.0 if plan else yaw
	var right := Vector3(cos(y), 0.0, -sin(y))
	var back := Vector3(sin(y), 0.0, cos(y))
	focus += right * d.x + back * d.y
	focus.x = clampf(focus.x, -limit, limit)
	focus.z = clampf(focus.z, -limit, limit)


## Drags the view by a mouse movement, px (the ground follows the pointer).
func pan_pixels(rel: Vector2) -> void:
	var px := (dist * 1.1 / get_viewport().get_visible_rect().size.y) if plan else dist * 0.0025
	move_focus(-rel * px)


## Ground metres per screen pixel at the focus (plan: exact; 3D: near enough).
func metres_per_pixel() -> float:
	return (dist * 1.1 / maxf(get_viewport().get_visible_rect().size.y, 1.0)) if plan else dist * 0.0012


## Handles orbit, pan and zoom; true if it used the event.
func handle(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed and not plan
				return not plan
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
				return true
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					dist = clampf(dist / ZOOM_STEP, MIN_DIST, MAX_DIST)
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					dist = clampf(dist * ZOOM_STEP, MIN_DIST, MAX_DIST)
				return true
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			yaw -= mm.relative.x * ORBIT_SPEED
			pitch = clampf(pitch - mm.relative.y * ORBIT_SPEED, deg_to_rad(-89.0), deg_to_rad(-6.0))
			return true
		if _panning:
			pan_pixels(mm.relative)
			return true
	return false


## Where the mouse ray meets the horizontal plane at height y, or null.
func ground_point(mouse: Vector2, y: float) -> Variant:
	var from := project_ray_origin(mouse)
	var dir := project_ray_normal(mouse)
	return Plane(Vector3.UP, y).intersects_ray(from, dir)
