extends Node
## What the hall's shared things show, the same for everyone in the room (BSX's DesignBus
## screens): each wall panel's channel ("wall:<wall>:<panel>" -> channel id) and the
## holotable's turn, zoom and pan ("holo.turn", "holo.zoom", "holo.pan"). A change is a
## host-validated event, so everyone agrees; a joining player gets them in the snapshot.

signal changed(key: String, value: Variant)

const EVENT := "design.hall_screen"
const SNAPSHOT := "design.hall_screens"
const MAX_KEY := 64

var net: MultiplayerBus
var values: Dictionary = {}


func bind(bus: MultiplayerBus) -> void:
	net = bus
	net.register_event(EVENT, _apply, _validate)
	net.register_snapshot_provider(SNAPSHOT, self)


func _exit_tree() -> void:
	if net:
		net.unregister_event(EVENT)
		net.unregister_snapshot_provider(SNAPSHOT)
		net = null


## Shows `value` under `key` for everyone (this player sees it at once).
func set_value(key: String, value: Variant) -> void:
	if values.get(key) == value:
		return
	values[key] = value
	changed.emit(key, value)
	if net:
		net.request(EVENT, {"key": key, "value": value})


func get_value(key: String, default: Variant = null) -> Variant:
	return values.get(key, default)


func _validate(_sender: int, p: Dictionary) -> Variant:
	var key := str(p.get("key", ""))
	var v: Variant = p.get("value")
	if key == "" or key.length() > MAX_KEY:
		return "bad screen key"
	if not (v is String or v is float or v is int or v is bool or v is Vector2):
		return "bad screen value"
	if v is String and (v as String).length() > MAX_KEY:
		return "bad screen value"
	return {"key": key, "value": v}


func _apply(p: Dictionary) -> void:
	var key := str(p.key)
	if values.get(key) == p.value:
		return
	values[key] = p.value
	changed.emit(key, p.value)


func get_net_snapshot() -> Dictionary:
	return {"values": values.duplicate()}


func apply_net_snapshot(data: Dictionary) -> void:
	var got: Dictionary = data.get("values", {})
	for key: String in got:
		if values.get(key) != got[key]:
			values[key] = got[key]
			changed.emit(key, got[key])
