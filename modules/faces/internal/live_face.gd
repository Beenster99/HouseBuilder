extends "res://modules/faces/internal/face_drawing.gd"
## This player's own face, live: their look and whatever their voice and face keys are doing
## now, blinking now and then. For the "Your avatar" page and the Talking face settings, so a
## player can talk at it and see what the crew will see.

var faces: Node = null
var _blink_in := 2.5
var _blink_t := -1.0


func _process(delta: float) -> void:
	if faces == null:
		return
	var s: FaceState = faces.local_state()
	if not s.equals(state):
		state = s
	if _blink_t >= 0.0:
		_blink_t += delta
		if _blink_t > 0.14:
			_blink_t = -1.0
			blink = 0.0
	else:
		_blink_in -= delta
		if _blink_in <= 0.0:
			_blink_in = randf_range(2.0, 5.0)
			_blink_t = 0.0
			blink = 1.0
