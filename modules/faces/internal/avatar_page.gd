extends HBoxContainer
## Settings > "Your avatar": pick how you look so the crew can tell you apart. Your face is
## live on the left (talk at it), the options on the right; Random rolls a look. Every change
## is saved on this machine and shared with the crew at once (FacesBus.set_local_look).

const LiveFace := preload("res://modules/faces/internal/live_face.gd")

var faces: Node = null
var look: FaceLook
var _face: Control
var _suit: ColorRect
var _pickers: Dictionary = {}  # field -> OptionButton
var _extras: Dictionary = {}  # field -> CheckBox


func _ready() -> void:
	name = "YourAvatar"
	add_theme_constant_override("separation", 16)
	look = faces.local_look() if faces != null else FaceLook.new()
	var left := VBoxContainer.new()
	add_child(left)
	_face = LiveFace.new()
	_face.name = "Preview"
	_face.faces = faces
	_face.plate = true
	_face.custom_minimum_size = Vector2(200, 200)
	left.add_child(_face)
	_suit = ColorRect.new()
	_suit.name = "SuitSwatch"
	_suit.custom_minimum_size = Vector2(200, 18)
	left.add_child(_suit)
	var random := Button.new()
	random.name = "Random"
	random.text = "Random"
	random.pressed.connect(func() -> void: _use(FaceLook.random(randi())))
	left.add_child(random)
	var hint := Label.new()
	hint.text = "Talk to see your face move."
	left.add_child(hint)

	var grid := GridContainer.new()
	grid.name = "Options"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(grid)
	_picker(grid, "suit", "Suit colour", FaceLook.SUIT_NAMES)
	var skins := PackedStringArray()
	for i in FaceLook.SKINS.size():
		skins.append("Tone %d" % (i + 1))
	_picker(grid, "skin", "Skin tone", skins)
	_picker(grid, "eyes", "Eyes", FaceLook.EYE_NAMES)
	_picker(grid, "brows", "Eyebrows", FaceLook.BROW_NAMES)
	_picker(grid, "hair_colour", "Brow and beard colour", FaceLook.HAIR_COLOUR_NAMES)
	for i in FaceLook.EXTRAS.size():
		var field: String = FaceLook.EXTRAS[i]
		grid.add_child(Control.new())
		var box := CheckBox.new()
		box.name = field.capitalize().replace(" ", "")
		box.text = FaceLook.EXTRA_NAMES[i]
		box.toggled.connect(func(on: bool) -> void:
			var d := look.to_dict()
			d[field] = on
			if on and field == "glasses":
				d.sunglasses = false
			elif on and field == "sunglasses":
				d.glasses = false
			_use(FaceLook.from_dict(d)))
		grid.add_child(box)
		_extras[field] = box
	_show()


func _picker(grid: GridContainer, field: String, label: String, names: PackedStringArray) -> void:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	var pick := OptionButton.new()
	pick.name = field.capitalize().replace(" ", "")
	for n in names:
		pick.add_item(n)
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.item_selected.connect(func(i: int) -> void:
		var d := look.to_dict()
		d[field] = i
		_use(FaceLook.from_dict(d)))
	grid.add_child(pick)
	_pickers[field] = pick


## Shows and saves a look.
func _use(l: FaceLook) -> void:
	look = l
	if faces != null:
		faces.set_local_look(look)
	_show()


func _show() -> void:
	var d := look.to_dict()
	for field: String in _pickers:
		(_pickers[field] as OptionButton).select(int(d[field]))
	for field: String in _extras:
		(_extras[field] as CheckBox).set_pressed_no_signal(bool(d[field]))
	_face.look = look
	_suit.color = look.suit_colour()
