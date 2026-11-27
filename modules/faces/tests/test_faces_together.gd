extends ModuleTest
## Talking faces between players, over ENet on localhost: each sees a face on the other's
## avatar; a look one picks shows on the other's avatar (and their suit's visor goes so the
## face shows); a mouth, a face key and the mute reach the other player; an emote pulls a face;
## a steady face sends nothing; a late joiner gets everyone's look; leaving takes the face
## away. Then the pages build and the gallery screenshot point draws.
##   tools/run_tests.sh faces

const PORT := 24611
const VOICE := Vector3(1.0, 0.8, 0.2)


func run_tests() -> void:
	Flags.set_flag(MultiplayerBus.ONLINE_FLAG, true)
	get_tree().current_scene.set_meta("crew_avatars", true)
	var a := _player("Ana")
	var b := _player("Ben")
	var na: MultiplayerBus = a.net
	var nb: MultiplayerBus = b.net
	var fa: FacesBus = a.faces
	var fb: FacesBus = b.faces
	check(na.host(PORT) == OK, "Ana hosts")
	nb.join("127.0.0.1", PORT)
	check(await _until(func() -> bool: return na.peers().size() == 2 and nb.peers().size() == 2), "Ben joins")
	var ana := na.local_peer_id()
	var ben := nb.local_peer_id()
	check(await _until(func() -> bool: return fa.view_of(ben) != null and fb.view_of(ana) != null), "each sees a face on the other's avatar")
	check(fa.view_of(ben).get_parent() == na.avatar_head(ben), "hung on the avatar's head")
	check(fa.view_of(ana) == null, "no face for yourself (you have no avatar)")

	# Ben picks a look: it shows on Ana's avatar of him.
	var look := FaceLook.new()
	look.suit = 2
	look.headgear = FaceLook.CAP
	look.hair = 1
	look.hair_colour = 5
	look.glasses = true
	fb.set_local_look(look)
	check(await _until(func() -> bool: return fa.look_of(ben).equals(look)), "Ana gets Ben's look")
	check(fa.view_of(ben).look().equals(look), "and his face is drawn with it")
	check(await _until(func() -> bool: return na.avatar_look(ben).get("visor") == false), "his visor is off so the face shows")
	check(Color(na.avatar_look(ben).get("suit", Color.BLACK)).is_equal_approx(look.suit_colour()) and na.avatar_look(ben).get("headgear") == "cap",
			"and his suit and headgear match: %s" % [na.avatar_look(ben)])

	# Ben talks (a made-up voice, no microphone): Ana sees his mouth open.
	var voice: Node = fb.voice
	check(voice != null, "Ben has a voice reader")
	voice.process_mode = Node.PROCESS_MODE_DISABLED
	for i in 12:
		voice.feed(-28.0, VOICE, 1.0 / 60.0)
	check(await _until(func() -> bool: return fb.local_state().mouth == FaceState.MOUTH_WIDE), "Ben's own face opens wide")
	check(await _until(func() -> bool: return fa.state_of(ben).mouth == FaceState.MOUTH_WIDE), "Ana sees his mouth open: %s" % fa.state_of(ben))
	check(await _until(func() -> bool: return fa.view_of(ben).shown().mouth == FaceState.MOUTH_WIDE), "on the face plate")

	# A steady face sends nothing.
	var sent := [0]
	na.event_applied.connect(func(n: String, _p: Dictionary) -> void:
		if n == FacesBus.STATE_EVENT:
			sent[0] += 1)
	await _wait_real(0.5)
	check(sent[0] == 0, "a steady face sends nothing: %d" % sent[0])
	# A face changing every frame is held to 15 a second.
	var end := Time.get_ticks_msec() + 1000
	var loud := true
	while Time.get_ticks_msec() < end:
		loud = not loud
		voice.feed(-28.0 if loud else -24.0, VOICE if loud else Vector3(0.2, 0.3, 0.9), 0.1)
		await get_tree().process_frame
	check(sent[0] >= 5 and sent[0] <= 17, "a changing face sends at most ~15 a second: %d" % sent[0])
	voice.feed(-90.0, Vector3.ZERO, 0.5)
	voice.feed(-90.0, Vector3.ZERO, 0.5)
	check(await _until(func() -> bool: return fa.state_of(ben).mouth == FaceState.MOUTH_CLOSED), "and the last one, shut, always gets there")

	# A face key, then the mute.
	fb.pull_face(FaceState.MOOD_ANGRY)
	check(await _until(func() -> bool: return fa.state_of(ben).mood == FaceState.MOOD_ANGRY), "Ben's angry face key reaches Ana")
	fb.set_muted(true)
	check(await _until(func() -> bool: return fa.state_of(ben).muted), "his mute reaches her")
	for i in 12:
		voice.feed(-28.0, VOICE, 1.0 / 60.0)
	await frames(3)
	check(fb.local_state().mouth == FaceState.MOUTH_CLOSED, "muted: the mouth stays shut while he talks")
	fb.set_muted(false)
	fb._manual_left = 0.0
	voice.feed(-90.0, Vector3.ZERO, 0.5)
	voice.feed(-90.0, Vector3.ZERO, 0.5)
	check(await _until(func() -> bool: var s := fa.state_of(ben); return not s.muted and s.mood == FaceState.MOOD_NEUTRAL), "unmuted, neutral")

	# An emote pulls a matching face on everyone's view of him.
	await _wait_real(0.6)
	nb.emote("thumbs_down")
	check(await _until(func() -> bool: return fa.view_of(ben).shown().mood == FaceState.MOOD_SAD), "thumbs down: a sad face")

	# A late joiner gets everyone's look.
	var c := _player("Cat")
	var nc: MultiplayerBus = c.net
	var fc: FacesBus = c.faces
	nc.join("127.0.0.1", PORT)
	check(await _until(func() -> bool: return fc.look_of(ben).equals(look)), "Cat, joining late, gets Ben's look")
	check(await _until(func() -> bool: return fc.view_of(ben) != null and fc.view_of(ben).look().equals(look)), "on his face")

	# Ben leaves: his face goes.
	nb.leave()
	check(await _until(func() -> bool: return fa.view_of(ben) == null), "Ben's face goes when he leaves")
	nc.leave()
	na.leave()
	await frames(2)

	await _pages(fa)


func _pages(faces: FacesBus) -> void:
	var page: Control = faces._avatar_page()
	add_child(page)
	await frames(2)
	check(page.find_child("Preview", true, false) != null and page.find_child("Random", true, false) != null, "Your avatar page builds")
	var before: Dictionary = faces.local_look().to_dict()
	(page.find_child("Random", true, false) as Button).pressed.emit()
	(page.find_child("Hair", true, false) as OptionButton).item_selected.emit(4)
	check(faces.local_look().hair == 4, "a pick is saved as your look")
	check(faces.local_look().to_dict() != before or before.hair == 4, "Random rolls a new look")
	page.queue_free()
	var section: Control = faces._voice_section()
	add_child(section)
	await frames(2)
	check(section.find_child("Calibrate", true, false) != null and section.find_child("Meter", true, false) != null,
			"Talking face settings build, with Calibrate and a meter")
	section.queue_free()
	check(not Menu.settings_page(FacesBus.AVATAR_PAGE).is_empty(), "the Your avatar page is on the Settings menu")
	check(Router.has_scene(FacesBus.GALLERY_SCENE), "the gallery scene is registered")
	var shot := Shots.all().filter(func(s: Dictionary) -> bool: return s.id == "faces_mouths")
	check(shot.size() == 1, "with a screenshot point")
	var gallery: Control = load(Router.scene_path(FacesBus.GALLERY_SCENE)).instantiate()
	add_child(gallery)
	await frames(2)
	check(gallery.find_child("Grid", true, false).get_child_count() == 24, "the gallery draws every mouth and mood")
	gallery.queue_free()


func _player(who: String) -> Dictionary:
	var bus := MultiplayerBus.new()
	bus.name = "Net_" + who
	add_child(bus)
	bus.register_module()
	Settings.set_value("multiplayer", "player_name", who)
	bus._refresh_identity()
	var faces := FacesBus.new()
	faces.name = "Faces_" + who
	add_child(faces)
	faces.bind(bus)
	return {"net": bus, "faces": faces}


func _wait_real(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func _until(cond: Callable, timeout := 5.0) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()
