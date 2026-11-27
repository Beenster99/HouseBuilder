class_name WalkBus
extends Node
## Walk-inside mode's bus (Modules.bus("walk")), ported from BSX Ltd's design room
## (modules/design/internal/walk): the open building built round you at full size, in the
## architectural model look (white, ink edges, sun shadows) or the realistic one, to walk or
## fly through and design in. Everything you change in here goes through BuildingSync, so the
## designer, the holotable and every other player follow.
##
##   var walk := Modules.bus("walk") as WalkBus
##   walk.open(model, get_tree().current_scene)    # lays the walk view over that scene
##   walk.closed.connect(...)                       # Esc: back to whatever opened it
##   walk.walkers                                   # who is walking, where, and their pointer
##
## The design room's designer gets a "Walk inside" button on its top bar (DesignBus
## register_action, found by name: walk does not depend on design). While the view is open it
## holds HudSlots.claim_pointer(POINTER), so the hall's own walker and screens stand down.
##
## walkers: peer id -> {name, colour, pos (feet, world m), yaw (rad), aim (Vector3 world, or
## null when aiming at nothing), flying}, for the design room to draw each walking player on
## the holotable model and their pointer on the plan and 3D screens. walkers_changed when
## someone starts or stops walking; positions and pointers update every frame (read them in
## _process). Your own entry is there too while you walk.
##
## Features (Flags): "walk" (the module), "walk.inside" (the view and its designer button).

signal opened
signal closed
## Someone started or stopped walking (or flying).
signal walkers_changed

const FLAG := "walk.inside"
const ACTION := "walk.inside"
const LABEL := "Walk inside"
const POINTER := "walk.inside"
const EVENT := "walk.state"
const SECTION := "walk"
const VIEW_SCRIPT := "res://modules/walk/internal/walk_inside.gd"
## Movers: each walker's body and pointer, driven by that player (the "player:" prefix).
const BODY_MOVER := "player:%d:walk"
const AIM_MOVER := "player:%d:walkaim"
## The pointer mover sits here when its player aims at nothing.
const NO_AIM := Vector3(0, -10000, 0)

var walkers: Dictionary = {}
## The open walk view (WalkInside), or null.
var view: Node = null
var _net: MultiplayerBus
## peer id -> {body: Node3D, aim: Node3D}: where other players' walks land.
var _proxies: Dictionary = {}
var _design: Node = null
var _lent: Camera3D = null
var _sections: Dictionary = {}
var _takers: Dictionary = {}
var _preview: Callable = Callable()


func register_module() -> void:
	if Modules.ready_done:
		_hook()
	else:
		Modules.modules_ready.connect(_hook, CONNECT_ONE_SHOT)


func unregister_module() -> void:
	close()
	if _design and is_instance_valid(_design) and _design.has_method("unregister_action"):
		_design.call("unregister_action", ACTION)
	if _net:
		_net.unregister_event(EVENT)
		_net.unregister_snapshot_provider(SECTION)
		for peer: int in _proxies.keys():
			_drop_proxy(peer)
	_net = null


func _hook() -> void:
	bind(Modules.bus("multiplayer") as MultiplayerBus)
	hook_design(Modules.bus("design"))


## Shares walk state through a session's bus (tests bind their own).
func bind(net: MultiplayerBus) -> void:
	if net == null:
		return
	_net = net
	_net.register_event(EVENT, _apply_state, _stamp)
	_net.register_snapshot_provider(SECTION, self)
	_net.peer_left.connect(_on_peer_left)
	_net.session_ended.connect(_on_session_ended)


func net() -> MultiplayerBus:
	return _net


## The designer's "Walk inside" button (a design bus or a stand-in in tests).
func hook_design(design: Node) -> void:
	if design == null or not design.has_method("register_action") or not Flags.is_on(FLAG):
		return
	_design = design
	design.call("register_action", ACTION, LABEL, func(model: BuildingModel) -> void:
		open(model, _pressed_in()), 45)


## The viewport the designer's button was pressed in (the designer can be drawn inside a
## SubViewport in the hall), else the current scene.
func _pressed_in() -> Node:
	for vp: Node in get_tree().root.find_children("*", "SubViewport", true, false):
		var c := (vp as SubViewport).gui_get_hovered_control()
		if c is Button and (c as Button).text == LABEL:
			return vp
	return get_tree().current_scene


## Opens walk-inside from `parent` (the current scene, or a node in the designer's own
## viewport): the building in a world of its own, drawn over the whole screen. When `parent`
## is inside a SubViewport (the designer drawn in the hall), a stand-in camera is made current
## there, so that view steps aside (HUD and input) until the walk closes and frees it.
## spawn: {at: Vector3 (feet), yaw} to start somewhere given.
## sync: the edits' way to the host (default: the building bus's, for its shared model).
## Returns the view (or the one already open).
func open(model: BuildingModel = null, parent: Node = null, spawn: Dictionary = {}, sync: BuildingSync = null) -> Node:
	if view and is_instance_valid(view):
		return view
	if model == null:
		var b := Modules.bus("building") as BuildingBus
		model = b.model if b else null
	if model == null:
		return null
	if parent == null:
		parent = get_tree().current_scene if get_tree().current_scene else self
	var v: Node = (load(VIEW_SCRIPT) as GDScript).new()
	var vp := parent.get_viewport() if parent.is_inside_tree() else null
	if parent is Viewport:
		vp = parent as Viewport
	if vp and vp != get_tree().root:
		_lend_camera(vp)
		parent = get_tree().current_scene if get_tree().current_scene else self
	parent.add_child(v)
	v.call("setup", self, model, sync if sync else _sync_for(model), spawn)
	view = v
	HudSlots.claim_pointer(POINTER)
	opened.emit()
	return v


## Closes the view (Esc does this); the player is back where they were.
func close() -> void:
	if view == null:
		return
	var v := view
	view = null
	if is_instance_valid(v):
		v.queue_free()
		if v.is_inside_tree():
			v.get_parent().remove_child(v)
	if _lent and is_instance_valid(_lent):
		_lent.queue_free()
		if _lent.is_inside_tree():
			_lent.get_parent().remove_child(_lent)
	_lent = null
	HudSlots.release_pointer(POINTER)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	closed.emit()


## A camera made current in the view walk-inside was opened from, so that view stands down.
func _lend_camera(vp: Viewport) -> void:
	var cam := Camera3D.new()
	cam.name = "WalkInsideLent"
	cam.position = Vector3(0, -1000, 0)
	vp.add_child(cam)
	cam.make_current()
	_lent = cam


## The camera lent to the designer's view while walking (null when none).
func lent_camera() -> Camera3D:
	return _lent


# The Tab menu's hooks: other modules add to walk-inside's Tab menu without walk knowing them.
#   walk.register_tab_section("modules.saved", "Saved modules", func(view) -> Control: ..., 30)
#   walk.set_preview_maker(func(item: Dictionary) -> Control: ...)   # an item's turning model and figures
#   walk.register_taker("modules", func(view, item: Dictionary) -> bool: ...)  # items that aren't catalog kinds
# The view (WalkInside) gives a section: model, sync, holding, take_new(kind), aim(), where(),
# use_item(item). Items are {id, label, tags} as in DesignBus.palette_groups.

## Adds a section under the Tab menu's lists. make(view) -> Control each time it is drawn.
func register_tab_section(id: String, title: String, make: Callable, order: int = 50) -> void:
	_sections[id] = {"title": title, "make": make, "order": order}


func unregister_tab_section(id: String) -> void:
	_sections.erase(id)


## Sections, lowest order first: [{id, title, make, order}].
func tab_sections() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in _sections:
		var s: Dictionary = _sections[id].duplicate()
		s["id"] = id
		out.append(s)
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.order) < int(y.order))
	return out


## make(item) -> Control: the preview shown when an item is picked in the Tab menu (it is then
## taken with TAKE). An invalid Callable takes items straight away again.
func set_preview_maker(make: Callable) -> void:
	_preview = make


func has_preview() -> bool:
	return _preview.is_valid()


func make_preview(item: Dictionary) -> Control:
	if not _preview.is_valid():
		return null
	var c: Variant = _preview.call(item)
	return c if c is Control else null


## take(view, item) -> bool: handles items the building catalog doesn't know (a saved module).
func register_taker(id: String, take: Callable) -> void:
	_takers[id] = take


func unregister_taker(id: String) -> void:
	_takers.erase(id)


## Gives an item to the takers; true if one took it.
func take_item(view: Node, item: Dictionary) -> bool:
	for id: String in _takers:
		var t: Callable = _takers[id]
		if t.is_valid() and bool(t.call(view, item)):
			return true
	return false


func is_open() -> bool:
	return view != null and is_instance_valid(view)


## The shared building's sync when `model` is the shared one, else an unbound one (tests,
## previews): edits from walk-inside always go through BuildingSync.
func _sync_for(model: BuildingModel) -> BuildingSync:
	var b := Modules.bus("building") as BuildingBus
	if b and b.model == model:
		return b.sync
	return BuildingSync.new(model)


# Walking together (BSX DesignBus.set_walking / walkers): who is in walk-inside is a host
# event, so everyone agrees; where they are streams as movers.

## Says whether this player is walking (and flying), for everyone.
func set_state(walking: bool, flying := false) -> void:
	if _net == null:
		_apply_state({"peer": 1, "on": walking, "flying": flying})
		return
	_net.request(EVENT, {"on": walking, "flying": flying})


func local_peer() -> int:
	return _net.local_peer_id() if _net else 1


func _stamp(sender: int, p: Dictionary) -> Variant:
	return {"peer": sender, "on": bool(p.get("on", false)), "flying": bool(p.get("flying", false))}


func _apply_state(p: Dictionary) -> void:
	var peer := int(p.get("peer", 0))
	var was := walkers.has(peer)
	if bool(p.get("on", false)):
		var w: Dictionary = walkers.get(peer, {"pos": Vector3.ZERO, "yaw": 0.0, "aim": null})
		w["name"] = _net.player_name(peer) if _net else "You"
		w["colour"] = _net.player_colour(peer) if _net else Color(0.3, 0.7, 1.0)
		w["flying"] = bool(p.get("flying", false))
		walkers[peer] = w
		if peer != local_peer():
			_add_proxy(peer)
		walkers_changed.emit()
	elif was:
		walkers.erase(peer)
		_drop_proxy(peer)
		walkers_changed.emit()


func _add_proxy(peer: int) -> void:
	if _proxies.has(peer) or _net == null:
		return
	var body := Node3D.new()
	body.name = "Walker_%d" % peer
	var aim := Node3D.new()
	aim.name = "WalkerAim_%d" % peer
	aim.position = NO_AIM
	add_child(body)
	add_child(aim)
	_net.register_mover(BODY_MOVER % peer, body)
	_net.register_mover(AIM_MOVER % peer, aim)
	_proxies[peer] = {"body": body, "aim": aim}


func _drop_proxy(peer: int) -> void:
	var p: Dictionary = _proxies.get(peer, {})
	if p.is_empty():
		return
	_proxies.erase(peer)
	if _net:
		_net.unregister_mover(BODY_MOVER % peer)
		_net.unregister_mover(AIM_MOVER % peer)
	for k: String in ["body", "aim"]:
		if is_instance_valid(p[k]):
			(p[k] as Node).queue_free()


## Where another walker's figure is (their streamed body), or null.
func proxy_body(peer: int) -> Node3D:
	var p: Dictionary = _proxies.get(peer, {})
	return p.get("body") if not p.is_empty() else null


func proxy_aim(peer: int) -> Node3D:
	var p: Dictionary = _proxies.get(peer, {})
	return p.get("aim") if not p.is_empty() else null


func _process(_delta: float) -> void:
	for peer: int in walkers:
		var w: Dictionary = walkers[peer]
		if _proxies.has(peer):
			var body: Node3D = _proxies[peer].body
			var aim: Node3D = _proxies[peer].aim
			w["pos"] = body.position
			w["yaw"] = body.rotation.y
			w["aim"] = null if aim.position.y < NO_AIM.y * 0.5 else aim.position
		elif peer == local_peer() and is_open():
			w["pos"] = view.call("feet")
			w["yaw"] = float(view.call("yaw"))
			w["aim"] = view.call("aim_point")


func _on_peer_left(peer: int, _why: String) -> void:
	if walkers.erase(peer):
		_drop_proxy(peer)
		walkers_changed.emit()


func _on_session_ended(_why: String) -> void:
	for peer: int in walkers.keys():
		if peer != local_peer():
			walkers.erase(peer)
			_drop_proxy(peer)
	walkers_changed.emit()


func get_net_snapshot() -> Dictionary:
	var out := {}
	for peer: int in walkers:
		out[str(peer)] = bool(walkers[peer].get("flying", false))
	return {"walkers": out}


func apply_net_snapshot(data: Dictionary) -> void:
	var got: Dictionary = data.get("walkers", {})
	for k: String in got:
		_apply_state({"peer": int(k), "on": true, "flying": bool(got[k])})
