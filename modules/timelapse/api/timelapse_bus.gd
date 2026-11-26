class_name TimelapseBus
extends Node
## The timelapse module's bus (Modules.bus("timelapse")): the crew watches the building go up
## together. The host builds the schedule (TimelapseSchedule) and owns one shared clock; every
## peer replays the same schedule from that clock, so only the clock crosses the network.
##
##   bus.start_timelapse(parts, "Family house")   # anyone may ask; the host schedules it
##   bus.request_play(false) / request_speed(10.0) / request_seek(42.0)
##   bus.day()                                    # the shared build day, same on every peer
##
## Parts are the building api adapter's Dictionaries (see TimelapseSchedule).

signal started(title: String)
signal clock_changed
signal finished

const VIEW_SCENE := "timelapse.view"
const START := "timelapse.start"
const CLOCK := "timelapse.clock"
const DEMO_FLAG := "timelapse.demo"
## Build days per real second the crew can pick.
const SPEEDS: Array[float] = [0.25, 1.0, 2.0, 5.0, 10.0, 30.0]
const DEFAULT_SPEED := 2.0
## More parts than this are refused (a request's payload has to fit the network).
const MAX_PARTS := 6000

var schedule: Dictionary = {}
var title := ""
var net: MultiplayerBus
var _playing := false
var _speed := DEFAULT_SPEED
var _anchor_day := 0.0
var _anchor_time := 0.0
var _was_done := false


func register_module() -> void:
	net = Modules.bus("multiplayer") as MultiplayerBus
	Router.register_scene(VIEW_SCENE, "res://modules/timelapse/internal/timelapse_view.tscn")
	Router.set_loading_title(VIEW_SCENE, "Timelapse")
	if Flags.is_on(DEMO_FLAG):
		Menu.register_entry(DEMO_FLAG, "Timelapse demo", VIEW_SCENE, 20, {"demo": true})
	net.register_event(START, _apply_start, _validate_start)
	net.register_event(CLOCK, _apply_clock, _validate_clock)
	net.register_snapshot_provider("timelapse", self)
	net.session_ended.connect(func(_reason: String) -> void: _reset())


func unregister_module() -> void:
	Menu.unregister_entry(DEMO_FLAG)
	if net:
		net.unregister_event(START)
		net.unregister_event(CLOCK)
		net.unregister_snapshot_provider("timelapse")


func _process(_delta: float) -> void:
	if not is_active():
		return
	var done := day() >= total_days()
	if done and not _was_done:
		finished.emit()
	_was_done = done


# --- Asking ----------------------------------------------------------------------------

## Asks the host to schedule `parts` and start playing it for everyone. `open` takes every
## peer to the timelapse view.
func start_timelapse(parts: Array, building_title: String, open := true, options: Dictionary = {}) -> void:
	net.request(START, {"parts": parts, "title": building_title, "open": open, "options": options})


func request_play(play: bool) -> void:
	net.request(CLOCK, {"playing": play, "speed": _speed, "day": _restart_day(play)})


func request_speed(days_per_second: float) -> void:
	net.request(CLOCK, {"playing": _playing, "speed": days_per_second, "day": day()})


func request_seek(to_day: float) -> void:
	net.request(CLOCK, {"playing": _playing, "speed": _speed, "day": to_day})


# --- Reading ---------------------------------------------------------------------------

func is_active() -> bool:
	return not schedule.is_empty()


func total_days() -> float:
	return float(schedule.get("days", 0.0))


## The shared build day: the host's clock, so every peer reads the same day.
func day() -> float:
	if not _playing:
		return _anchor_day
	return clampf(_anchor_day + (net.server_time() - _anchor_time) * _speed, 0.0, total_days())


func is_playing() -> bool:
	return _playing and day() < total_days()


func speed() -> float:
	return _speed


func tasks() -> Array:
	return schedule.get("tasks", [])


# --- Events (host validates, everyone applies) -----------------------------------------

func _validate_start(_sender: int, p: Dictionary) -> Variant:
	var parts: Variant = p.get("parts")
	if not parts is Array or (parts as Array).is_empty():
		return "nothing to build"
	if (parts as Array).size() > MAX_PARTS:
		return "too many parts for a timelapse (%d, at most %d)" % [(parts as Array).size(), MAX_PARTS]
	var built := TimelapseSchedule.build(parts, p.get("options", {}))
	return {"schedule": built, "title": str(p.get("title", "Building")), "open": bool(p.get("open", true)),
			"playing": true, "speed": DEFAULT_SPEED, "day": 0.0, "at": net.server_time()}


func _apply_start(p: Dictionary) -> void:
	schedule = p.get("schedule", {})
	title = str(p.get("title", ""))
	_take_clock(p)
	_was_done = false
	started.emit(title)
	if bool(p.get("open", true)) and Router.has_scene(VIEW_SCENE) and Router.current_id != VIEW_SCENE:
		Router.goto(VIEW_SCENE)


func _validate_clock(_sender: int, p: Dictionary) -> Variant:
	if not is_active():
		return "no timelapse running"
	var s := float(p.get("speed", _speed))
	if not SPEEDS.has(s):
		return "unknown speed %s" % s
	return {"playing": bool(p.get("playing", _playing)), "speed": s,
			"day": clampf(float(p.get("day", day())), 0.0, total_days()), "at": net.server_time()}


func _apply_clock(p: Dictionary) -> void:
	_take_clock(p)
	_was_done = day() >= total_days()
	clock_changed.emit()


func _take_clock(p: Dictionary) -> void:
	_playing = bool(p.get("playing", false))
	_speed = float(p.get("speed", DEFAULT_SPEED))
	_anchor_day = float(p.get("day", 0.0))
	_anchor_time = float(p.get("at", net.server_time()))


## Play from the end starts again from day 0.
func _restart_day(play: bool) -> float:
	var d := day()
	return 0.0 if play and d >= total_days() else d


func _reset() -> void:
	schedule = {}
	title = ""
	_playing = false
	_anchor_day = 0.0


func get_net_snapshot() -> Dictionary:
	if not is_active():
		return {}
	return {"schedule": schedule, "title": title, "open": false, "playing": _playing,
			"speed": _speed, "day": day(), "at": net.server_time()}


func apply_net_snapshot(data: Dictionary) -> void:
	if data.is_empty():
		_reset()
		return
	_apply_start(data)
