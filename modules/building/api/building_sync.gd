class_name BuildingSync
extends RefCounted
## Shares one BuildingModel between the players of a session. Edits are requests to the
## host: the host applies them through its BuildingHistory (which also gives everyone their
## own undo and redo) and broadcasts the op as applied; every other peer applies that op
## as is, so all copies stay identical. Joining players get the whole model as a snapshot.
##
##   var sync := BuildingSync.new(model)
##   sync.bind(net, "building")          # a MultiplayerBus; the prefix names its events
##   sync.edit(BuildingCommands.move(["p3"], Vector3(0.25, 0, 0)), "drag-12")
##   sync.undo()                         # this player's last edit
##   sync.redo()
##   sync.load_design(data)              # replace the building for everyone
##
## Unbound (no session), edit/undo/redo/load_design apply straight to the model, so tools
## and tests work the same without a network.
##
## Events (prefix "building"): "building.edit" {op, group?}, "building.undo", "building.redo",
## "building.load" {data}. Broadcast payloads: {op, author, seq, sum?}. Snapshot section:
## the prefix.
##
## Soft locks: the host refuses an edit to an entry that another player has claimed with
## MultiplayerBus.claim(entry id).
##
## Desync check: every CHECK_EVERY edits the host sends its model's checksum, and a client
## whose own checksum differs emits desync() (and the session can resend a snapshot).

## A client's model no longer matches the host's.
signal desync(seq: int)
## The host refused one of this player's requests.
signal rejected(reason: String)
## Any op from the session was applied here: {op, author, seq}.
signal applied(payload: Dictionary)

const CHECK_EVERY := 10

var model: BuildingModel
var history: BuildingHistory
var net: MultiplayerBus
var prefix := "building"


func _init(building: BuildingModel, hist: BuildingHistory = null) -> void:
	model = building
	history = hist if hist != null else BuildingHistory.new(building)


## Ties this model to a session's bus. Call unbind() before binding to another.
func bind(bus: MultiplayerBus, event_prefix: String = "building") -> void:
	unbind()
	net = bus
	prefix = event_prefix
	net.register_event(_ev("edit"), _apply_op, _validate_edit)
	net.register_event(_ev("undo"), _apply_op, _validate_undo)
	net.register_event(_ev("redo"), _apply_op, _validate_redo)
	net.register_event(_ev("load"), _apply_load, _validate_load)
	net.register_snapshot_provider(prefix, self)
	net.request_rejected.connect(_on_rejected)


func unbind() -> void:
	if net == null:
		return
	for e: String in ["edit", "undo", "redo", "load"]:
		net.unregister_event(_ev(e))
	net.unregister_snapshot_provider(prefix)
	if net.request_rejected.is_connected(_on_rejected):
		net.request_rejected.disconnect(_on_rejected)
	net = null


func is_bound() -> bool:
	return net != null


## Asks for an edit (an op from BuildingCommands). group: see BuildingHistory.commit.
func edit(op: Dictionary, group: String = "") -> void:
	if net == null:
		history.commit(op, _me(), group)
		return
	var payload := {"op": op}
	if group != "":
		payload["group"] = group
	net.request(_ev("edit"), payload)


func undo() -> void:
	if net == null:
		history.undo(_me())
	else:
		net.request(_ev("undo"))


func redo() -> void:
	if net == null:
		history.redo(_me())
	else:
		net.request(_ev("redo"))


## Replaces the building for everyone with saved data (BuildingModel.to_data()).
func load_design(data: Dictionary) -> void:
	if net == null:
		if model.load_data(data).ok:
			history.clear()
		return
	net.request(_ev("load"), {"data": data})


# Host side

func _validate_edit(sender: int, payload: Dictionary) -> Variant:
	var op: Variant = payload.get("op")
	if not op is Dictionary:
		return "no edit"
	var held := _held_by_other(op, sender)
	if held != "":
		return "%s is being edited by %s" % [held, net.player_name(net.claim_owner(held))]
	var done := history.commit(op, str(sender), str(payload.get("group", "")))
	return _broadcast(done, sender, "that edit does not fit")


func _validate_undo(sender: int, _payload: Dictionary) -> Variant:
	return _broadcast(history.undo(str(sender)), sender, "nothing to undo")


func _validate_redo(sender: int, _payload: Dictionary) -> Variant:
	return _broadcast(history.redo(str(sender)), sender, "nothing to redo")


func _validate_load(_sender: int, payload: Dictionary) -> Variant:
	var data: Variant = payload.get("data")
	if not data is Dictionary or BuildingModel.from_data(data, model.catalog) == null:
		return "not a building design"
	return {"data": data}


## The payload the host broadcasts for an op it has already applied, or the refusal.
func _broadcast(done: Dictionary, sender: int, refusal: String) -> Variant:
	if done.is_empty():
		return refusal
	var out := {"op": done, "author": str(sender), "seq": history.seq}
	if history.seq % CHECK_EVERY == 0:
		out["sum"] = model.checksum()
	return out


# Every peer

func _apply_op(payload: Dictionary) -> void:
	# The host applied it while validating; everyone else applies it now.
	if not net.is_host():
		model.apply(payload.get("op", {}))
		if payload.has("sum") and int(payload.sum) != model.checksum():
			desync.emit(int(payload.get("seq", 0)))
	applied.emit(payload)


func _apply_load(payload: Dictionary) -> void:
	model.load_data(payload.get("data", {}))
	history.clear()
	applied.emit({"op": {"op": "load"}, "author": "", "seq": 0})


func get_net_snapshot() -> Dictionary:
	return model.to_data()


func apply_net_snapshot(data: Dictionary) -> void:
	model.load_data(data)
	history.clear()


# Helpers

func _ev(what: String) -> String:
	return "%s.%s" % [prefix, what]


func _me() -> String:
	return str(net.local_peer_id()) if net != null else "1"


func _on_rejected(event_name: String, reason: String) -> void:
	if event_name.begins_with(prefix + "."):
		rejected.emit(reason)


## The first entry an op touches that another player has claimed, or "".
func _held_by_other(op: Dictionary, sender: int) -> String:
	for eid in _ids_of(op):
		var owner := net.claim_owner(eid)
		if owner != 0 and owner != sender:
			return eid
	return ""


static func _ids_of(op: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	match str(op.get("op", "")):
		"set", "retag":
			out.append(str(op.get("id", "")))
		"remove":
			if op.has("ids"):
				for i: Variant in op.ids:
					out.append(str(i))
			else:
				out.append(str(op.get("id", "")))
		"move":
			for i: Variant in op.get("ids", []):
				out.append(str(i))
		"batch":
			for o: Variant in op.get("ops", []):
				if o is Dictionary:
					out.append_array(_ids_of(o))
	return out
