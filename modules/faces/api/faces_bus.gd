class_name FacesBus
extends Node
## Talking faces (Modules.bus("faces")): a drawn cartoon face on every crewmate's avatar that
## talks, smiles, laughs and shouts with its player's voice, and a look each player picks so
## the crew can tell each other apart.
##
##   var faces := Modules.bus("faces") as FacesBus
##   faces.look_of(peer_id)          # FaceLook: skin, eyes, brows, extras, suit
##   faces.state_of(peer_id)         # FaceState: mouth shape, openness, mood, muted
##   faces.set_local_look(look)      # saved on this machine and shared with the crew
##   faces.look_changed / face_changed
##
## Each player's game reads its own microphone (FaceVoice; the crew talk on Discord, which the
## game can't hear) and sends only the 2-byte face state, 15 times a second at most and only
## while it changes. No audio is recorded, kept or sent. The look is the event "faces.look",
## sent on joining and on change, and in the join snapshot. Faces hang on the avatars through
## MultiplayerBus.avatar_added / avatar_head, and this player's own suit colour goes to
## MultiplayerBus.set_avatar_look with no headgear and no visor: a bare cartoon head with
## just the features (beenster, 28 Nov: no hats, no face outline).
## Face keys (Settings > Key binds, "Face"): happy, sad, surprised, angry for a few seconds,
## mute (the mouth stays shut), and the talk key for push-to-talk mode.
##
## Features (Flags): "faces" (the module), "faces.face" (faces on avatars, the face keys and
## the "Your avatar" page), "faces.voice" (the microphone and its settings section).

signal look_changed(peer_id: int, look: FaceLook)
signal face_changed(peer_id: int, state: FaceState)
## This player's own face changed (for previews), whether or not anyone else is connected.
signal local_face_changed(state: FaceState)

const FACE_FLAG := "faces.face"
const VOICE_FLAG := "faces.voice"
const SECTION := "faces"
const LOOK_EVENT := "faces.look"
const STATE_EVENT := "faces.state"
const SEND_HZ := 15.0
const MANUAL_TIME := 3.0
const EMOTE_TIME := 3.0
const KEY_GROUP := "Face"
const HAPPY_KEY := "faces.happy"
const SAD_KEY := "faces.sad"
const SURPRISED_KEY := "faces.surprised"
const ANGRY_KEY := "faces.angry"
const MUTE_KEY := "faces.mute"
const TALK_KEY := "faces.talk"
const AVATAR_PAGE := "faces.avatar"
const VOICE_SECTION := "faces.voice"
const GALLERY_SCENE := "faces.gallery"
## The face each emote pulls for its three seconds.
const EMOTE_MOODS := {"wave": FaceState.MOOD_HAPPY, "thumbs_up": FaceState.MOOD_HAPPY,
		"cheer": FaceState.MOOD_HAPPY, "come_here": FaceState.MOOD_SMILE,
		"point": FaceState.MOOD_SMILE, "thumbs_down": FaceState.MOOD_SAD,
		"help": FaceState.MOOD_SURPRISED, "stop": FaceState.MOOD_ANGRY}
const MANUAL_KEYS := {HAPPY_KEY: FaceState.MOOD_HAPPY, SAD_KEY: FaceState.MOOD_SAD,
		SURPRISED_KEY: FaceState.MOOD_SURPRISED, ANGRY_KEY: FaceState.MOOD_ANGRY}
const DEFAULTS := {"look": {}, "mic_on": true, "device": "Default", "threshold_db": -48.0,
		"normal_db": -28.0, "talk_mode": "open"}

const FaceView := preload("res://modules/faces/internal/face_view.gd")
const FaceVoice := preload("res://modules/faces/internal/face_voice.gd")

## The microphone side (FaceVoice), or null while faces.voice is off.
var voice: Node = null
## True while this player has muted their face (the mouth stays shut).
var muted := false
var _net: MultiplayerBus
var _looks: Dictionary = {}  # peer id -> FaceLook (shared looks)
var _states: Dictionary = {}  # peer id -> FaceState
var _views: Dictionary = {}  # peer id -> FaceView
var _local_state: FaceState = FaceState.new()
var _sent := -1
var _send_wait := 0.0
var _manual := FaceState.MOOD_NEUTRAL
var _manual_left := 0.0
var _registered := false


func register_module() -> void:
	_registered = true
	Settings.register(SECTION, DEFAULTS)
	if Flags.is_on(FACE_FLAG):
		Keys.register(HAPPY_KEY, "Happy face", KEY_F5, KEY_GROUP)
		Keys.register(SAD_KEY, "Sad face", KEY_F6, KEY_GROUP)
		Keys.register(SURPRISED_KEY, "Surprised face", KEY_F7, KEY_GROUP)
		Keys.register(ANGRY_KEY, "Angry face", KEY_F8, KEY_GROUP)
		Keys.register(MUTE_KEY, "Mute my face", KEY_F9, KEY_GROUP)
		Menu.register_settings_page(AVATAR_PAGE, "Your avatar", _avatar_page, 15)
	if Flags.is_on(VOICE_FLAG):
		Keys.register(TALK_KEY, "Talk (push-to-talk mode)", KEY_B, KEY_GROUP)
		Menu.register_settings_section(Menu.SOUND, VOICE_SECTION, "Talking face", _voice_section, 40)
	Router.register_scene(GALLERY_SCENE, "res://modules/faces/internal/face_gallery.tscn")
	Shots.register("faces_mouths", GALLERY_SCENE)
	var net := Modules.bus("multiplayer") as MultiplayerBus
	if net != null:
		bind(net)


func unregister_module() -> void:
	unbind()
	if _registered:
		for k in [HAPPY_KEY, SAD_KEY, SURPRISED_KEY, ANGRY_KEY, MUTE_KEY, TALK_KEY]:
			if Keys.has(k):
				Keys.unregister(k)
		Menu.unregister_settings_page(AVATAR_PAGE)
		Menu.unregister_settings_section(Menu.SOUND, VOICE_SECTION)
		_registered = false


## Ties faces to a session (register_module does this with the game's own; tests bind their
## own MultiplayerBus per player).
func bind(net: MultiplayerBus) -> void:
	unbind()
	Settings.register(SECTION, DEFAULTS)
	_net = net
	net.register_event(LOOK_EVENT, _apply_look, _validate_look)
	net.register_event(STATE_EVENT, _apply_state, _validate_state)
	net.register_snapshot_provider(SECTION, self)
	net.avatar_added.connect(_on_avatar_added)
	net.peer_left.connect(_on_peer_left)
	net.emote_received.connect(_on_emote)
	net.session_started.connect(_on_session_started)
	net.session_ended.connect(_on_session_ended)
	if Flags.is_on(VOICE_FLAG) and voice == null:
		voice = FaceVoice.new()
		voice.name = "Voice"
		add_child(voice)
	publish_look()


func unbind() -> void:
	if _net == null:
		return
	_net.unregister_event(LOOK_EVENT)
	_net.unregister_event(STATE_EVENT)
	_net.unregister_snapshot_provider(SECTION)
	for s: Array in [[_net.avatar_added, _on_avatar_added], [_net.peer_left, _on_peer_left],
			[_net.emote_received, _on_emote], [_net.session_started, _on_session_started],
			[_net.session_ended, _on_session_ended]]:
		if (s[0] as Signal).is_connected(s[1]):
			(s[0] as Signal).disconnect(s[1])
	for v in _views.values():
		if is_instance_valid(v):
			v.queue_free()
	_views.clear()
	_net = null


# --- Looks -----------------------------------------------------------------------------

## This player's look: the one picked on the "Your avatar" page, or one rolled from their
## name until they pick one.
func local_look() -> FaceLook:
	var saved: Variant = Settings.get_value(SECTION, "look")
	if saved is Dictionary and not (saved as Dictionary).is_empty():
		return FaceLook.from_dict(saved)
	return FaceLook.random(hash(str(Settings.get_value("multiplayer", "player_name"))))


## Saves this player's look on this machine and shares it with the crew.
func set_local_look(look: FaceLook) -> void:
	Settings.set_value(SECTION, "look", look.to_dict())
	Settings.save()
	publish_look()


## Sends this player's look to the crew and dresses their avatar to match.
func publish_look() -> void:
	if _net == null:
		return
	var look := local_look()
	_net.request(LOOK_EVENT, {"look": look.to_dict()})
	if Flags.is_on(FACE_FLAG):
		_net.set_avatar_look(_net.local_peer_id(), {"suit": look.suit_colour(),
				"headgear": "none", "visor": false})


## A player's look (rolled from their name until theirs arrives).
func look_of(peer_id: int) -> FaceLook:
	if _looks.has(peer_id):
		return _looks[peer_id]
	if _net != null and peer_id == _net.local_peer_id():
		return local_look()
	var who := _net.player_name(peer_id) if _net != null else str(peer_id)
	return FaceLook.random(hash(who))


func _validate_look(sender: int, p: Dictionary) -> Variant:
	if not p.get("look") is Dictionary:
		return "no look"
	return {"peer": sender, "look": FaceLook.from_dict(p.look).to_dict()}


func _apply_look(p: Dictionary) -> void:
	var peer := int(p.get("peer", 0))
	var look := FaceLook.from_dict(p.get("look"))
	_looks[peer] = look
	var view: Node = _views.get(peer)
	if is_instance_valid(view):
		view.set_look(look)
	look_changed.emit(peer, look)


func get_net_snapshot() -> Dictionary:
	var looks := []
	for peer: int in _looks:
		looks.append([peer, (_looks[peer] as FaceLook).to_dict()])
	var states := []
	for peer: int in _states:
		states.append([peer, (_states[peer] as FaceState).pack()])
	return {"looks": looks, "states": states}


func apply_net_snapshot(data: Dictionary) -> void:
	for row: Variant in data.get("looks", []):
		if row is Array and (row as Array).size() == 2:
			_apply_look({"peer": int(row[0]), "look": row[1]})
	for row: Variant in data.get("states", []):
		if row is Array and (row as Array).size() == 2:
			_apply_state({"peer": int(row[0]), "s": int(row[1])})


# --- Face state ------------------------------------------------------------------------

## What a player's face is doing (this player's own too).
func state_of(peer_id: int) -> FaceState:
	if _net != null and peer_id == _net.local_peer_id():
		return _local_state
	return _states.get(peer_id, FaceState.new())


## This player's face right now: their voice, a face key, or shut while muted.
func local_state() -> FaceState:
	return _local_state


## Pulls a face by hand for MANUAL_TIME (the face keys; works with the microphone off).
func pull_face(mood: int) -> void:
	_manual = clampi(mood, 0, FaceState.MOOD_NAMES.size() - 1)
	_manual_left = MANUAL_TIME


func set_muted(on: bool) -> void:
	muted = on


func _validate_state(sender: int, p: Dictionary) -> Variant:
	return {"peer": sender, "s": clampi(int(p.get("s", 0)), 0, 0xFFFF)}


func _apply_state(p: Dictionary) -> void:
	var peer := int(p.get("peer", 0))
	if _net != null and peer == _net.local_peer_id():
		return
	var s := FaceState.unpack(int(p.get("s", 0)))
	_states[peer] = s
	var view: Node = _views.get(peer)
	if is_instance_valid(view):
		view.set_state(s)
	face_changed.emit(peer, s)


func _process(delta: float) -> void:
	if _net == null:
		return
	if _manual_left > 0.0:
		_manual_left -= delta
	var s: FaceState = voice.state.duplicate_state() if voice != null else FaceState.new()
	if _manual_left > 0.0:
		s.mood = _manual
		if s.mouth == FaceState.MOUTH_SMILE:
			s.mouth = FaceState.MOUTH_CLOSED
	if muted:
		s = FaceState.make(FaceState.MOUTH_CLOSED, 0, s.mood if _manual_left > 0.0 else FaceState.MOOD_NEUTRAL, true)
	if not s.equals(_local_state):
		_local_state = s
		local_face_changed.emit(s)
	_send_wait -= delta
	if _send_wait <= 0.0 and s.pack() != _sent and _net.is_online():
		_sent = s.pack()
		_send_wait = 1.0 / SEND_HZ
		_net.request(STATE_EVENT, {"s": _sent})


func _unhandled_input(event: InputEvent) -> void:
	if _net == null or not Flags.is_on(FACE_FLAG) or event.is_echo():
		return
	for key: String in MANUAL_KEYS:
		if InputMap.has_action(key) and event.is_action_pressed(key):
			pull_face(MANUAL_KEYS[key])
	if InputMap.has_action(MUTE_KEY) and event.is_action_pressed(MUTE_KEY):
		set_muted(not muted)


# --- Avatars ---------------------------------------------------------------------------

## The face on a crewmate's avatar (FaceView), or null.
func view_of(peer_id: int) -> Node3D:
	var v: Variant = _views.get(peer_id)
	return v if is_instance_valid(v) else null


func _on_avatar_added(peer_id: int, _avatar: Node3D) -> void:
	if not Flags.is_on(FACE_FLAG):
		return
	var head := _net.avatar_head(peer_id)
	if head == null:
		return
	var old: Variant = _views.get(peer_id)
	if is_instance_valid(old):
		if (old as Node).get_parent() == head:
			return
		(old as Node).queue_free()
	var view := FaceView.new()
	view.peer_id = peer_id
	head.add_child(view)
	view.set_look(look_of(peer_id))
	view.set_state(state_of(peer_id))
	_views[peer_id] = view


func _on_peer_left(peer_id: int, _reason: String) -> void:
	_looks.erase(peer_id)
	_states.erase(peer_id)
	_views.erase(peer_id)


func _on_emote(e: Dictionary) -> void:
	var view := view_of(int(e.get("peer", 0)))
	if view != null and EMOTE_MOODS.has(str(e.get("emote", ""))):
		view.hold_mood(EMOTE_MOODS[str(e.emote)], EMOTE_TIME)


func _on_session_started(_as_host: bool) -> void:
	_sent = -1
	publish_look()


func _on_session_ended(_reason: String) -> void:
	_looks.clear()
	_states.clear()
	_sent = -1


# --- Pages -----------------------------------------------------------------------------

func _avatar_page() -> Control:
	var page: Control = preload("res://modules/faces/internal/avatar_page.gd").new()
	page.faces = self
	return page


func _voice_section() -> Control:
	var section: Control = preload("res://modules/faces/internal/voice_section.gd").new()
	section.faces = self
	return section
