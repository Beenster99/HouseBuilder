class_name DesignPresence
extends Node
## Who is doing what in the design room, shared with the crew:
##   - selections: each player's selected part ids, shown on everyone's view in their colour;
##   - soft locks: a player dragging parts locks them so nobody else can move, edit or delete
##     them. A lock lasts until it is let go, its player leaves, or LOCK_TIMEOUT seconds pass
##     without being renewed (a drag renews it every LOCK_RENEW seconds);
##   - cursors: each player's snapped pointer, and the start of what they are drawing, are
##     movers ("player:<peer>:design_cursor" and ":design_anchor"), so they stream at 20 Hz.
##
## Selections are host-validated events, so every player agrees on them. Locks are session
## claims, which the building's host validator checks before it accepts an edit.

signal selection_changed(peer_id: int, ids: PackedStringArray)
signal locks_changed
signal peers_changed
## Entries to flash for a moment on every player's screen (the engineer's new supports).
signal pulsed(ids: PackedStringArray)

const SELECT_EVENT := "design.select"
const PULSE_EVENT := "design.pulse"
const SNAPSHOT := "design.presence"
const LOCK_TIMEOUT := 8.0
const LOCK_RENEW := 2.0
## A cursor parked this far down is hidden (the pointer is off the grid or the player is away).
const HIDDEN_Y := -10000.0
const MAX_IDS := 256

var net: MultiplayerBus
## peer -> PackedStringArray of selected ids.
var selections: Dictionary = {}
## This player's drag locks: entry id -> when last renewed (seconds).
var _my_locks: Dictionary = {}
## This player's cursor and drag anchor (movers), and every other player's copies.
var my_cursor: Node3D
var my_anchor: Node3D
var _others: Dictionary = {}  # peer -> {"cursor": Node3D, "anchor": Node3D}
var _me := 1
var _sweep := 0.0
var _peer_check := 0.0
var _last_peer_set: Array = []


func bind(bus: MultiplayerBus) -> void:
	net = bus
	net.register_event(SELECT_EVENT, _apply_select, _validate_select)
	net.register_event(PULSE_EVENT, _apply_pulse, _validate_pulse)
	net.claim_changed.connect(_on_claim_changed)
	net.register_snapshot_provider(SNAPSHOT, self)
	net.peer_left.connect(_on_peer_left)
	net.session_started.connect(_on_session_started)
	net.session_ended.connect(_on_session_ended)
	my_cursor = _marker("MyCursor")
	my_anchor = _marker("MyAnchor")
	_resync_movers()


func unbind() -> void:
	if net == null:
		return
	net.unregister_event(SELECT_EVENT)
	net.unregister_event(PULSE_EVENT)
	net.unregister_snapshot_provider(SNAPSHOT)
	net.peer_left.disconnect(_on_peer_left)
	net.session_started.disconnect(_on_session_started)
	net.session_ended.disconnect(_on_session_ended)
	net.claim_changed.disconnect(_on_claim_changed)
	net.unregister_mover(cursor_id(_me))
	net.unregister_mover(anchor_id(_me))
	for peer: int in _others:
		net.unregister_mover(cursor_id(peer))
		net.unregister_mover(anchor_id(peer))
	net = null


static func cursor_id(peer: int) -> String:
	return "player:%d:design_cursor" % peer


static func anchor_id(peer: int) -> String:
	return "player:%d:design_anchor" % peer


func _marker(n: String) -> Node3D:
	var m := Node3D.new()
	m.name = n
	m.position = Vector3(0, HIDDEN_Y, 0)
	add_child(m)
	return m


# --- Cursors --------------------------------------------------------------------------

## Where this player's pointer is (snapped, world metres), or null to hide it.
func set_cursor(at: Variant) -> void:
	my_cursor.position = at if at is Vector3 else Vector3(0, HIDDEN_Y, 0)


## The start of what this player is drawing (a wall's first corner), or null for none.
func set_anchor(at: Variant) -> void:
	my_anchor.position = at if at is Vector3 else Vector3(0, HIDDEN_Y, 0)


## Every other player's cursor and anchor: peer -> {"cursor": Vector3 or null, "anchor": ...}.
func others() -> Dictionary:
	var out := {}
	for peer: int in _others:
		var c: Node3D = _others[peer].cursor
		var a: Node3D = _others[peer].anchor
		out[peer] = {"cursor": _shown(c.position), "anchor": _shown(a.position)}
	return out


static func _shown(p: Vector3) -> Variant:
	return null if p.y < HIDDEN_Y * 0.5 else p


func _process(delta: float) -> void:
	if net == null:
		return
	_peer_check -= delta
	if _peer_check <= 0.0:
		_peer_check = 0.5
		_resync_movers()
	_sweep -= delta
	if _sweep <= 0.0:
		_sweep = 0.5
		sweep_locks()


## Registers this player's cursor movers and a follower pair for each other player.
func _resync_movers() -> void:
	if net == null:
		return
	var me := net.local_peer_id()
	if me != _me:
		net.unregister_mover(cursor_id(_me))
		net.unregister_mover(anchor_id(_me))
		_me = me
	net.register_mover(cursor_id(_me), my_cursor)
	net.register_mover(anchor_id(_me), my_anchor)
	var want: Array = []
	for p in net.peers():
		if int(p) != _me:
			want.append(int(p))
	for peer: int in _others.keys():
		if not peer in want:
			_drop_other(peer)
	for peer: int in want:
		if not _others.has(peer):
			var c := _marker("Cursor_%d" % peer)
			var a := _marker("Anchor_%d" % peer)
			_others[peer] = {"cursor": c, "anchor": a}
			net.register_mover(cursor_id(peer), c)
			net.register_mover(anchor_id(peer), a)
	want.sort()
	if want != _last_peer_set:
		_last_peer_set = want
		peers_changed.emit()


func _drop_other(peer: int) -> void:
	var pair: Dictionary = _others[peer]
	net.unregister_mover(cursor_id(peer))
	net.unregister_mover(anchor_id(peer))
	(pair.cursor as Node).queue_free()
	(pair.anchor as Node).queue_free()
	_others.erase(peer)


# --- Selections -------------------------------------------------------------------------

func select(ids: PackedStringArray) -> void:
	net.request(SELECT_EVENT, {"ids": Array(ids)})


## Flashes entries for everyone in the session.
func pulse(ids: PackedStringArray) -> void:
	if not ids.is_empty():
		net.request(PULSE_EVENT, {"ids": Array(ids)})


func _validate_pulse(_sender: int, p: Dictionary) -> Variant:
	var ids: Variant = _clean_ids(p.get("ids", []))
	if ids == null:
		return "bad pulse"
	return {"ids": ids}


func _apply_pulse(p: Dictionary) -> void:
	pulsed.emit(PackedStringArray(p.ids))


func selection_of(peer: int) -> PackedStringArray:
	return selections.get(peer, PackedStringArray())


func my_selection() -> PackedStringArray:
	return selection_of(net.local_peer_id())


## The peer whose selection includes the id (other than this player), or 0.
func selected_by_other(id: String) -> int:
	for peer: int in selections:
		if peer != net.local_peer_id() and id in (selections[peer] as PackedStringArray):
			return peer
	return 0


func _validate_select(sender: int, p: Dictionary) -> Variant:
	var ids: Variant = _clean_ids(p.get("ids", []))
	if ids == null:
		return "bad selection"
	return {"peer": sender, "ids": ids}


func _apply_select(p: Dictionary) -> void:
	var peer := int(p.peer)
	var ids := PackedStringArray(p.ids)
	if ids.is_empty():
		selections.erase(peer)
	else:
		selections[peer] = ids
	selection_changed.emit(peer, ids)


static func _clean_ids(raw: Variant) -> Variant:
	if not raw is Array or (raw as Array).size() > MAX_IDS:
		return null
	var out: Array = []
	for v in raw:
		var s := str(v)
		if s == "" or s.length() > 64:
			return null
		if not s in out:
			out.append(s)
	return out


# --- Soft locks -------------------------------------------------------------------------
#
# A drag claims its parts with MultiplayerBus.claim, and the building's host validator
# refuses other players' edits to claimed entries. The claim goes on drop, when the player
# leaves (the session frees their claims), or LOCK_TIMEOUT seconds after the drag last
# moved (a stalled drag lets go by itself).

## Locks parts for a drag, or renews this player's lock on them.
func lock(ids: PackedStringArray) -> void:
	for id in ids:
		if not _my_locks.has(id) and net.claim_owner(id) != net.local_peer_id():
			net.claim(id)
		_my_locks[id] = _now()
	locks_changed.emit()


func unlock(ids: PackedStringArray) -> void:
	for id in ids:
		if _my_locks.erase(id) or net.claim_owner(id) == net.local_peer_id():
			net.release(id)
	locks_changed.emit()


## Peer holding a lock on the entry, or 0.
func locked_by(id: String) -> int:
	return net.claim_owner(id)


## True if this player may change the entry (nobody else has it locked).
func may_edit(id: String) -> bool:
	var owner := locked_by(id)
	return owner == 0 or owner == net.local_peer_id()


func my_locks() -> PackedStringArray:
	return PackedStringArray(_my_locks.keys())


## Lets go of this player's locks not renewed within LOCK_TIMEOUT.
func sweep_locks() -> void:
	var stale := PackedStringArray()
	for id: String in _my_locks:
		if _now() - float(_my_locks[id]) > LOCK_TIMEOUT:
			stale.append(id)
	if not stale.is_empty():
		unlock(stale)


var clock_override := -1.0


func _now() -> float:
	return clock_override if clock_override >= 0.0 else Time.get_ticks_msec() / 1000.0


func _on_peer_left(peer: int, _why: String) -> void:
	if net.is_host():
		if selections.has(peer):
			net.host_emit(SELECT_EVENT, {"peer": peer, "ids": []})


func _on_session_started(_as_host: bool) -> void:
	_resync_movers()


func _on_claim_changed(_id: String, _peer: int) -> void:
	locks_changed.emit()


func _on_session_ended(_reason: String) -> void:
	var me := net.local_peer_id()
	for peer: int in selections.keys():
		if peer != me:
			selections.erase(peer)
	_my_locks.clear()
	locks_changed.emit()
	_resync_movers()


func get_net_snapshot() -> Dictionary:
	var sel := {}
	for peer: int in selections:
		sel[peer] = Array(selections[peer])
	return {"selections": sel}


func apply_net_snapshot(data: Dictionary) -> void:
	selections.clear()
	var sel: Dictionary = data.get("selections", {})
	for peer in sel:
		selections[int(peer)] = PackedStringArray(sel[peer])
	for peer: int in selections:
		selection_changed.emit(peer, selections[peer])
