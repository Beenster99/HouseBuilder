class_name SandboxBus
extends Node
## The sandbox module's bus (Modules.bus("sandbox")): the Phase 0 shared site. Everyone in
## the session stands on one plot, sees each other's snapped cursors (movers
## "player:<peer>:cursor") and can drop test crates that Jolt simulates on the host and
## streams to the crew. Later phases build the design room on this site.
##
## State changes are host-validated events, so solo and online run the same code:
##   bus.request_drop(Vector3(2, 0, 3))   # a crate falls from DROP_HEIGHT above that point
##   bus.request_clear()

signal crate_added(crate_id: String, at: Vector3)
signal cleared

const SITE_SCENE := "sandbox.site"
const DROP := "sandbox.drop"
const CLEAR := "sandbox.clear"
const MAX_CRATES := 60
const DROP_HEIGHT := 6.0
const PLOT_HALF := 40.0
## Cursor and placement grid, m (the plan's default design-room snap).
const GRID := 0.25

## crate id -> drop point, in drop order.
var crates: Dictionary = {}
var _next := 1
var net: MultiplayerBus


func register_module() -> void:
	net = Modules.bus("multiplayer") as MultiplayerBus
	Router.register_scene(SITE_SCENE, "res://modules/sandbox/internal/site.tscn")
	Menu.set_start(SITE_SCENE, 10)
	Shots.register("sandbox_site", SITE_SCENE)
	net.register_event(DROP, _apply_drop, _validate_drop)
	net.register_event(CLEAR, _apply_clear)
	net.register_snapshot_provider("sandbox", self)
	net.session_ended.connect(func(_reason: String) -> void: _reset())
	_dev_launch.call_deferred(OS.get_cmdline_user_args())


func unregister_module() -> void:
	Menu.clear_start(SITE_SCENE)
	if net:
		net.unregister_event(DROP)
		net.unregister_event(CLEAR)
		net.unregister_snapshot_provider("sandbox")


## Two windows on one PC without the menus, for testing co-op:
##   godot --path . -- --host          hosts and opens the game's start scene (Menu.start())
##   godot --path . -- --join=127.0.0.1 joins and opens it once in
## The start scene is the highest-priority Menu.set_start: this site, or the design room.
func _dev_launch(args: PackedStringArray) -> void:
	for arg in args:
		if arg == "--host":
			if net.host() == OK:
				_open_start()
		elif arg.begins_with("--join="):
			net.session_started.connect(func(_as_host: bool) -> void: _open_start(), CONNECT_ONE_SHOT)
			net.join(arg.trim_prefix("--join="))


func _open_start() -> void:
	var start := Menu.start()
	Router.goto(str(start.get("scene", SITE_SCENE)), start.get("args", {}))


static func snap(p: Vector3) -> Vector3:
	return Vector3(snappedf(p.x, GRID), snappedf(p.y, GRID), snappedf(p.z, GRID))


static func cursor_id(peer_id: int) -> String:
	return "player:%d:cursor" % peer_id


func request_drop(at: Vector3) -> void:
	net.request(DROP, {"at": at})


func request_clear() -> void:
	net.request(CLEAR, {})


func _validate_drop(_sender: int, p: Dictionary) -> Variant:
	if crates.size() >= MAX_CRATES:
		return "the site holds %d crates at most" % MAX_CRATES
	var at: Variant = p.get("at")
	if not at is Vector3:
		return "no drop point"
	var v := snap(at as Vector3)
	if absf(v.x) > PLOT_HALF or absf(v.z) > PLOT_HALF:
		return "outside the plot"
	var out := {"at": Vector3(v.x, DROP_HEIGHT, v.z), "id": "crate:%d" % _next}
	_next += 1
	return out


func _apply_drop(p: Dictionary) -> void:
	var id := str(p.get("id", ""))
	if id == "" or crates.has(id):
		return
	crates[id] = p.get("at", Vector3.ZERO)
	_next = maxi(_next, id.trim_prefix("crate:").to_int() + 1)
	crate_added.emit(id, crates[id])


func _apply_clear(_p: Dictionary) -> void:
	crates.clear()
	cleared.emit()


func _reset() -> void:
	crates.clear()
	_next = 1


func get_net_snapshot() -> Dictionary:
	return {"crates": crates.duplicate(), "next": _next}


func apply_net_snapshot(data: Dictionary) -> void:
	crates = (data.get("crates", {}) as Dictionary).duplicate()
	_next = int(data.get("next", 1))
	cleared.emit()
	for id: String in crates:
		crate_added.emit(id, crates[id])
