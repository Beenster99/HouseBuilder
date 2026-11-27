extends Control
## Screenshot point "faces_mouths" (Router scene faces.gallery): all eight mouth shapes side
## by side, then the moods, on a few different looks, for a quick visual check.

const FaceDrawing := preload("res://modules/faces/internal/face_drawing.gd")


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("eeeae0")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 8
	grid.position = Vector2(24, 24)
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	add_child(grid)
	var looks: Array[FaceLook] = [FaceLook.new(), FaceLook.random(3), FaceLook.random(11)]
	looks[0].headgear = FaceLook.NO_HEADGEAR
	for m in FaceState.MOUTH_COUNT:
		_cell(grid, looks[0], FaceState.make(m, 10, FaceState.MOOD_LAUGH if m == FaceState.MOUTH_LAUGH else (FaceState.MOOD_SHOUT if m == FaceState.MOUTH_SHOUT else FaceState.MOOD_NEUTRAL)), FaceState.MOUTH_NAMES[m])
	for md in FaceState.MOOD_NAMES.size():
		_cell(grid, looks[1], FaceState.make(FaceState.MOUTH_CLOSED, 0, md), FaceState.MOOD_NAMES[md])
	for md in FaceState.MOOD_NAMES.size():
		_cell(grid, looks[2], FaceState.make(FaceState.MOUTH_WIDE if md % 2 == 0 else FaceState.MOUTH_TEETH, 8, md), FaceState.MOOD_NAMES[md] + " talking")


func _cell(grid: GridContainer, look: FaceLook, state: FaceState, text: String) -> void:
	var box := VBoxContainer.new()
	var face := FaceDrawing.new()
	face.custom_minimum_size = Vector2(140, 140)
	face.look = look
	face.state = state
	box.add_child(face)
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Color("1b1b1b"))
	box.add_child(l)
	grid.add_child(box)
