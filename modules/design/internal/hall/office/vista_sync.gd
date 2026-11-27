extends Node
## The design office's shared vista: the picture every player sees through the window wall.
## Any player can share one (share_file or share_bytes); the host checks it and sends it to
## the whole crew, and to anyone who joins later in their join snapshot. The host keeps the
## last one in user:// so the office looks the same next time they open it.
## Lives under the design bus (node "Vista") for the whole game, so its event is known before
## the hall scene loads on a joining player.

const VistaImage := preload("res://modules/design/internal/hall/office/vista_image.gd")

const EVENT := "design.vista"
const SECTION := "design.vista"
const SAVED := "user://design/vista.webp"
const DEFAULT := "res://modules/design/internal/hall/office/default_vista.webp"

## A new vista arrived (or went back to the default).
signal changed
## Preparing a picture this player picked finished: error is "" when it was sent.
signal prepared(error: String)

## The shared vista's WebP bytes; empty for the default.
var data := PackedByteArray()
## Who shared it ("" for the default).
var shared_by := ""
var _net: MultiplayerBus
var _texture: Texture2D
var _task := -1


func _ready() -> void:
	name = "Vista"
	_net = Modules.bus("multiplayer") as MultiplayerBus
	_net.register_event(EVENT, _apply, _validate)
	_net.register_snapshot_provider(SECTION, self)
	if FileAccess.file_exists(SAVED):
		var bytes := FileAccess.get_file_as_bytes(SAVED)
		if VistaImage.texture_from(bytes) != null:
			_take(bytes, "")


func _exit_tree() -> void:
	if _net:
		_net.unregister_event(EVENT)
		_net.unregister_snapshot_provider(SECTION)
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## The sky's picture now (the default's when nobody has shared one).
func texture() -> Texture2D:
	if _texture == null:
		_texture = load(DEFAULT) as Texture2D
	return _texture


func is_default() -> bool:
	return data.is_empty()


func busy() -> bool:
	return _task >= 0


## Prepares a picture file on a worker thread and shares it; prepared() says how it went.
func share_file(path: String) -> void:
	if _task >= 0:
		prepared.emit("Still preparing the last picture.")
		return
	_task = WorkerThreadPool.add_task(_prepare.bind(path), false, "design vista")


func _prepare(path: String) -> void:
	var out: Dictionary = VistaImage.from_file(path)
	_prepared.call_deferred(out)


func _prepared(out: Dictionary) -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if str(out.error) == "":
		share_bytes(out.bytes)
	prepared.emit(str(out.error))


## Shares an already-prepared panorama (VistaImage.encode); empty bytes go back to the default.
func share_bytes(bytes: PackedByteArray) -> void:
	_net.request(EVENT, {"data": bytes})


func reset() -> void:
	share_bytes(PackedByteArray())


func _validate(sender: int, payload: Dictionary) -> Variant:
	var bytes: Variant = payload.get("data")
	if not bytes is PackedByteArray:
		return "no picture"
	if (bytes as PackedByteArray).size() > VistaImage.MAX_BYTES:
		return "picture too big"
	if not (bytes as PackedByteArray).is_empty() and VistaImage.texture_from(bytes) == null:
		return "not a picture"
	var who := "" if (bytes as PackedByteArray).is_empty() else _net.player_name(sender)
	return {"data": bytes, "by": who}


func _apply(payload: Dictionary) -> void:
	_take(payload.get("data", PackedByteArray()), str(payload.get("by", "")))
	if _net.is_host():
		_save()


func _take(bytes: PackedByteArray, by: String) -> void:
	var tex := VistaImage.texture_from(bytes) if not bytes.is_empty() else null
	if tex == null:
		bytes = PackedByteArray()
		by = ""
	data = bytes
	shared_by = by
	_texture = tex
	changed.emit()


func _save() -> void:
	DirAccess.make_dir_recursive_absolute(SAVED.get_base_dir())
	if data.is_empty():
		if FileAccess.file_exists(SAVED):
			DirAccess.remove_absolute(SAVED)
		return
	var f := FileAccess.open(SAVED, FileAccess.WRITE)
	if f:
		f.store_buffer(data)


func get_net_snapshot() -> Dictionary:
	return {"data": data, "by": shared_by}


func apply_net_snapshot(snap: Dictionary) -> void:
	_take(snap.get("data", PackedByteArray()), str(snap.get("by", "")))
