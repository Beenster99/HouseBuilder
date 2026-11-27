extends Node
## The microphone side of the talking face. The player's own microphone (the one Discord
## uses too) plays into a bus of its own, added at run time, that only measures it: an
## AudioEffectSpectrumAnalyzer reads it and the bus is turned right down, so nothing is heard.
## Nothing is recorded, kept or sent; only the face that comes out of it (FaceState) goes to
## the crew. Each frame the level and three tone bands go through VoiceRules.
##
## Settings "faces": mic_on, device, threshold_db, normal_db, talk_mode ("open", or "hold"
## for players who use push-to-talk in Discord: the mouth only moves while TALK_KEY is held).
## calibrate(): stay quiet for QUIET_TIME, then talk for TALK_TIME, and the threshold and
## normal level are set from what was heard. feed() runs one frame by hand (tests, no mic).

signal calibration_changed(phase: String, left: float)
signal face_changed(state: FaceState)

const VoiceRules := preload("res://modules/faces/internal/voice_rules.gd")
const FaceStateT := preload("res://modules/faces/api/face_state.gd")

const SECTION := "faces"
const BUS := "FacesMic"
const TALK_KEY := "faces.talk"
const QUIET_TIME := 2.0
const TALK_TIME := 3.0
const SILENT_DB := -100.0
const LOW := Vector2(80, 400)
const MID := Vector2(400, 2000)
const HIGH := Vector2(2000, 8000)

var rules := VoiceRules.new()
## Last frame's loudness (dB, as the analyser reads it) and tone bands.
var level_db := SILENT_DB
var bands := Vector3.ZERO
## The face the voice makes right now.
var state: FaceState = FaceStateT.make(FaceStateT.MOUTH_CLOSED)
## "", "quiet" or "talk" while calibrating.
var calibration := ""
var _cal_left := 0.0
var _cal_quiet: PackedFloat32Array = []
var _cal_talk: PackedFloat32Array = []
var _player: AudioStreamPlayer
var _bus := -1
var _analyser: AudioEffectSpectrumAnalyzerInstance


func _ready() -> void:
	load_settings()
	Settings.changed.connect(_on_setting)
	_refresh_mic()


func _exit_tree() -> void:
	_stop_mic()


## Whether this build can read a microphone at all (project setting audio/driver/enable_input).
static func input_enabled() -> bool:
	return bool(ProjectSettings.get_setting("audio/driver/enable_input", false))


func listening() -> bool:
	return _analyser != null


## A line for the settings page saying what the microphone is doing.
func status() -> String:
	if not input_enabled():
		return "Microphone input is not switched on in this build yet."
	if not bool(Settings.get_value(SECTION, "mic_on")):
		return "Microphone off. Use the face keys to pull faces."
	if not listening():
		return "No microphone found."
	return "Listening to %s. Nothing is recorded or sent." % AudioServer.input_device


func devices() -> PackedStringArray:
	return AudioServer.get_input_device_list() if input_enabled() else PackedStringArray(["Default"])


func load_settings() -> void:
	rules.threshold_db = float(Settings.get_value(SECTION, "threshold_db"))
	rules.normal_db = float(Settings.get_value(SECTION, "normal_db"))


func calibrate() -> void:
	calibration = "quiet"
	_cal_left = QUIET_TIME
	_cal_quiet.clear()
	_cal_talk.clear()
	calibration_changed.emit(calibration, _cal_left)


func _process(delta: float) -> void:
	if _analyser == null:
		if calibration != "":
			feed(SILENT_DB, Vector3.ZERO, delta)
		elif not state.equals(FaceStateT.make(FaceStateT.MOUTH_CLOSED)):
			feed(SILENT_DB, Vector3.ZERO, delta)
		return
	var mode := AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX
	var low := _analyser.get_magnitude_for_frequency_range(LOW.x, LOW.y, mode).length()
	var mid := _analyser.get_magnitude_for_frequency_range(MID.x, MID.y, mode).length()
	var high := _analyser.get_magnitude_for_frequency_range(HIGH.x, HIGH.y, mode).length()
	var all := maxf(low, maxf(mid, high))
	var db := linear_to_db(all) if all > 0.0 else SILENT_DB
	if str(Settings.get_value(SECTION, "talk_mode")) == "hold" and not _talk_held():
		db = SILENT_DB
	feed(db, Vector3(low, mid, high), delta)


## One frame of sound, from the microphone or a test.
func feed(db: float, tone: Vector3, delta: float) -> FaceState:
	level_db = db
	bands = tone
	if calibration != "":
		_step_calibration(db, delta)
	var s := rules.step(db, tone, delta)
	if not s.equals(state):
		state = s
		face_changed.emit(state)
	return state


func _step_calibration(db: float, delta: float) -> void:
	if calibration == "quiet":
		_cal_quiet.append(db)
	else:
		_cal_talk.append(db)
	_cal_left -= delta
	if _cal_left > 0.0:
		calibration_changed.emit(calibration, _cal_left)
		return
	if calibration == "quiet":
		calibration = "talk"
		_cal_left = TALK_TIME
		calibration_changed.emit(calibration, _cal_left)
		return
	var result := calibration_result(_cal_quiet, _cal_talk)
	calibration = ""
	Settings.set_value(SECTION, "threshold_db", result.threshold_db)
	Settings.set_value(SECTION, "normal_db", result.normal_db)
	Settings.save()
	load_settings()
	calibration_changed.emit("", 0.0)


## Threshold a little over the loudest of the quiet (ignoring the odd bump), and the normal
## level from the middle of the talking. Pure, for tests.
static func calibration_result(quiet: PackedFloat32Array, talk: PackedFloat32Array) -> Dictionary:
	var q := Array(quiet).filter(func(v: float) -> bool: return is_finite(v))
	q.sort()
	var floor_db := -80.0
	if not q.is_empty():
		floor_db = maxf(float(q[mini(q.size() - 1, int(q.size() * 0.9))]), -90.0)
	var threshold := clampf(floor_db + 6.0, -75.0, -10.0)
	var t := Array(talk).filter(func(v: float) -> bool: return is_finite(v) and v > threshold)
	t.sort()
	var normal := threshold + 15.0
	if t.size() >= 5:
		normal = maxf(float(t[t.size() / 2]), threshold + 6.0)
	return {"threshold_db": snappedf(threshold, 0.5), "normal_db": snappedf(normal, 0.5)}


func _talk_held() -> bool:
	return InputMap.has_action(TALK_KEY) and Input.is_action_pressed(TALK_KEY)


func _on_setting(section: String, key: String, _value: Variant) -> void:
	if section != SECTION:
		return
	if key == "mic_on" or key == "device":
		_refresh_mic()
	elif key == "threshold_db" or key == "normal_db":
		load_settings()


func _refresh_mic() -> void:
	var want := input_enabled() and bool(Settings.get_value(SECTION, "mic_on")) \
			and DisplayServer.get_name() != "headless"
	if not want:
		_stop_mic()
		return
	var device := str(Settings.get_value(SECTION, "device"))
	if device != "" and device in AudioServer.get_input_device_list():
		AudioServer.input_device = device
	if _analyser != null:
		return
	_bus = AudioServer.get_bus_index(BUS)
	if _bus < 0:
		_bus = AudioServer.bus_count
		AudioServer.add_bus(_bus)
		AudioServer.set_bus_name(_bus, BUS)
		var analyser := AudioEffectSpectrumAnalyzer.new()
		analyser.buffer_length = 0.1
		analyser.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
		AudioServer.add_bus_effect(_bus, analyser, 0)
		# Effects run before the bus volume, so the analyser hears it and nobody else does.
		AudioServer.set_bus_volume_db(_bus, -80.0)
		AudioServer.set_bus_send(_bus, "Master")
	_player = AudioStreamPlayer.new()
	_player.name = "Mic"
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = BUS
	add_child(_player)
	_player.play()
	_analyser = AudioServer.get_bus_effect_instance(_bus, 0) as AudioEffectSpectrumAnalyzerInstance


func _stop_mic() -> void:
	_analyser = null
	if _player != null:
		_player.stop()
		_player.queue_free()
		_player = null
	var bus := AudioServer.get_bus_index(BUS)
	if bus >= 0:
		AudioServer.remove_bus(bus)
	_bus = -1
	level_db = SILENT_DB
