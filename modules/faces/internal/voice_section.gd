extends VBoxContainer
## Settings > Sound > "Talking face": the microphone on or off and which one, how sensitive it
## is (with a live meter and your own face to talk at), Calibrate, and the talk mode for
## players who use push-to-talk in Discord.

const LiveFace := preload("res://modules/faces/internal/live_face.gd")
const SECTION := "faces"
## The sensitivity slider is the threshold turned round: right is more sensitive.
const LOUDEST := -15.0
const QUIETEST := -75.0

var faces: Node = null
var _meter: ProgressBar
var _slider: HSlider
var _status: Label
var _cal: Button
var _cal_note: Label


func _ready() -> void:
	name = "TalkingFace"
	add_theme_constant_override("separation", 6)
	var voice: Node = faces.voice if faces != null else null
	var row := HBoxContainer.new()
	add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var face := LiveFace.new()
	face.name = "Preview"
	face.faces = faces
	face.look = faces.local_look() if faces != null else null
	face.plate = true
	face.custom_minimum_size = Vector2(96, 96)
	row.add_child(face)

	var mic := CheckButton.new()
	mic.name = "MicOn"
	mic.text = "Use my microphone for my face"
	mic.button_pressed = bool(Settings.get_value(SECTION, "mic_on"))
	mic.toggled.connect(func(on: bool) -> void: _save_setting("mic_on", on))
	left.add_child(mic)

	var dev_row := HBoxContainer.new()
	left.add_child(dev_row)
	dev_row.add_child(_label("Microphone"))
	var dev := OptionButton.new()
	dev.name = "Device"
	dev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var names: PackedStringArray = voice.devices() if voice != null else PackedStringArray(["Default"])
	var current := str(Settings.get_value(SECTION, "device"))
	for i in names.size():
		dev.add_item(names[i])
		if names[i] == current:
			dev.select(i)
	dev.item_selected.connect(func(i: int) -> void: _save_setting("device", dev.get_item_text(i)))
	dev_row.add_child(dev)

	var sens_row := HBoxContainer.new()
	left.add_child(sens_row)
	sens_row.add_child(_label("Sensitivity"))
	_slider = HSlider.new()
	_slider.name = "Sensitivity"
	_slider.min_value = 0.0
	_slider.max_value = LOUDEST - QUIETEST
	_slider.step = 0.5
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.value = LOUDEST - float(Settings.get_value(SECTION, "threshold_db"))
	_slider.value_changed.connect(func(v: float) -> void: _save_setting("threshold_db", LOUDEST - v))
	sens_row.add_child(_slider)

	_meter = ProgressBar.new()
	_meter.name = "Meter"
	_meter.min_value = -90.0
	_meter.max_value = -10.0
	_meter.show_percentage = false
	_meter.custom_minimum_size = Vector2(0, 10)
	left.add_child(_meter)

	var cal_row := HBoxContainer.new()
	left.add_child(cal_row)
	_cal = Button.new()
	_cal.name = "Calibrate"
	_cal.text = "Calibrate"
	_cal.pressed.connect(func() -> void:
		if faces != null and faces.voice != null:
			faces.voice.calibrate())
	cal_row.add_child(_cal)
	_cal_note = _label("Stay quiet for two seconds, then talk for three.")
	_cal_note.name = "CalibrateNote"
	cal_row.add_child(_cal_note)

	var mode_row := HBoxContainer.new()
	left.add_child(mode_row)
	mode_row.add_child(_label("Talk mode"))
	var mode := OptionButton.new()
	mode.name = "TalkMode"
	mode.add_item("Open mic")
	mode.add_item("Only while %s is held" % Keys.prompt("faces.talk"))
	mode.select(1 if str(Settings.get_value(SECTION, "talk_mode")) == "hold" else 0)
	mode.item_selected.connect(func(i: int) -> void: _save_setting("talk_mode", "hold" if i == 1 else "open"))
	mode_row.add_child(mode)

	_status = _label("")
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_status)
	var keys := _label("%s mutes your face. Muting in Discord doesn't." % Keys.prompt("faces.mute"))
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(keys)
	if voice != null:
		voice.calibration_changed.connect(_on_calibration)


func _process(_delta: float) -> void:
	var voice: Node = faces.voice if faces != null else null
	if voice == null:
		_status.text = "The talking face is switched off."
		return
	_meter.value = clampf(voice.level_db, _meter.min_value, _meter.max_value)
	_meter.modulate = Color(0.55, 0.85, 0.55) if voice.level_db > voice.rules.threshold_db else Color(0.7, 0.7, 0.7)
	_status.text = voice.status()


func _on_calibration(phase: String, left: float) -> void:
	_cal.disabled = phase != ""
	match phase:
		"quiet":
			_cal_note.text = "Stay quiet... %.0f" % ceilf(left)
		"talk":
			_cal_note.text = "Now talk normally... %.0f" % ceilf(left)
		_:
			_cal_note.text = "Done. Threshold %.0f dB, normal %.0f dB." % [
					float(Settings.get_value(SECTION, "threshold_db")), float(Settings.get_value(SECTION, "normal_db"))]
			_slider.set_value_no_signal(LOUDEST - float(Settings.get_value(SECTION, "threshold_db")))


func _save_setting(key: String, value: Variant) -> void:
	Settings.set_value(SECTION, key, value)
	Settings.save()


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l
