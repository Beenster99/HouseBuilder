extends ModuleTest
## The rules with no microphone and no network: FaceState packs into 2 bytes and back,
## FaceLook survives junk, the voice rules pick mouths from made-up loudness and tone (and
## keyboard clicks don't open the mouth), laughing and shouting are spotted, and calibration
## sets a sensible threshold.
##   tools/run_tests.sh faces

const VoiceRules := preload("res://modules/faces/internal/voice_rules.gd")
const FaceVoice := preload("res://modules/faces/internal/face_voice.gd")
const DT := 1.0 / 60.0
const VOICE := Vector3(1.0, 0.8, 0.2)  # an "ah": strong low and middle


func run_tests() -> void:
	_state()
	_look()
	_shapes()
	_talking()
	_clicks()
	_laugh()
	_shout()
	_calibration()


func _state() -> void:
	var ok := true
	for m in FaceState.MOUTH_COUNT:
		for o in 16:
			for md in FaceState.MOOD_NAMES.size():
				for mu in [false, true]:
					var s := FaceState.make(m, o, md, mu)
					var bits := s.pack()
					var back := FaceState.unpack(bits)
					if bits < 0 or bits > 0xFFFF or back.mouth != m or back.openness != o or back.mood != md or back.muted != mu:
						ok = false
	check(ok, "every face state packs into 2 bytes and back")
	check(FaceState.make(99, 99, 99).pack() == FaceState.make(7, 15, 7).pack(), "out-of-range values are clamped")
	check(FaceState.unpack(-5).pack() == 0 and FaceState.unpack(0x7FFFFFFF).pack() <= 0xFFFF, "junk bits stay in range")


func _look() -> void:
	var a := FaceLook.random(hash("Ana"))
	check(a.equals(FaceLook.random(hash("Ana"))), "the same name always rolls the same look")
	var differ := 0
	for n in ["Ben", "Cat", "Dot", "Eve"]:
		if not FaceLook.random(hash(n)).equals(a):
			differ += 1
	check(differ == 4, "different names roll different looks")
	check(FaceLook.from_dict(a.to_dict()).equals(a), "a look survives to_dict / from_dict")
	var junk := FaceLook.from_dict({"suit": 999, "skin": -4, "eyes": "wide", "hair": NAN,
			"glasses": true, "sunglasses": true, "beard": "yes", "headgear": 2.0})
	check(junk.suit == FaceLook.SUITS.size() - 1 and junk.skin == 0 and junk.eyes == 0 and junk.hair == 0,
			"junk numbers clamp or fall back: %s" % [junk.to_dict()])
	check(not (junk.glasses and junk.sunglasses) and not junk.beard and junk.headgear == 2, "extras are only true for true")
	check(FaceLook.from_dict("nonsense").equals(FaceLook.new()) and FaceLook.from_dict(null).equals(FaceLook.new()),
			"not a dictionary gives the default look")
	check(FaceLook.HEADGEAR_IDS.size() == FaceLook.HEADGEAR_NAMES.size(), "every headgear has an avatar id")


func _shapes() -> void:
	check(VoiceRules.shape_for(VOICE, 0.0) == FaceState.MOUTH_CLOSED, "silent: closed")
	check(VoiceRules.shape_for(VOICE, 0.1) == FaceState.MOUTH_SMALL, "quiet speech: small open")
	check(VoiceRules.shape_for(Vector3(1.0, 0.9, 0.2), 0.7) == FaceState.MOUTH_WIDE, "\"ah\": wide open")
	check(VoiceRules.shape_for(Vector3(1.0, 0.15, 0.05), 0.7) == FaceState.MOUTH_ROUND, "\"oo\": round")
	check(VoiceRules.shape_for(Vector3(0.2, 0.3, 0.8), 0.7) == FaceState.MOUTH_TEETH, "\"ee\" and \"s\": teeth")


func _feed(r: Object, db: float, seconds: float, tone := VOICE) -> FaceState:
	var s: FaceState
	var t := 0.0
	while t < seconds - 0.0001:
		s = r.step(db, tone, DT)
		t += DT
	return s


func _talking() -> void:
	var r := VoiceRules.new()
	r.threshold_db = -50.0
	r.normal_db = -30.0
	check(_feed(r, -70.0, 0.5).mouth == FaceState.MOUTH_CLOSED, "background noise under the threshold: shut")
	var s := _feed(r, -30.0, 0.2)
	check(s.mouth == FaceState.MOUTH_WIDE and s.openness >= 9, "normal speech opens it wide: %s" % s)
	var quiet := _feed(r, -46.0, 0.2)
	check(quiet.mouth == FaceState.MOUTH_SMALL and quiet.openness < s.openness, "quieter speech opens it less: %s" % quiet)
	# Flapping: between syllables it shuts, and reopens at once.
	check(_feed(r, -70.0, 0.1).mouth == FaceState.MOUTH_CLOSED, "shuts between words")
	check(_feed(r, -30.0, 6.0 * DT).mouth != FaceState.MOUTH_CLOSED, "and reopens straight away on the next")
	# No flicker: once the shape changes it is held a moment, whatever the next frames say.
	_feed(r, -30.0, 0.3)
	check(r.step(-30.0, Vector3(1.0, 0.1, 0.05), DT).mouth == FaceState.MOUTH_ROUND, "an \"oo\" rounds the mouth")
	var flick: FaceState = r.step(-30.0, VOICE, DT)
	check(flick.mouth == FaceState.MOUTH_ROUND, "a shape is held at least %d ms" % int(VoiceRules.HOLD * 1000))
	check(_feed(r, -30.0, 0.1).mouth == FaceState.MOUTH_WIDE, "then changes")


func _clicks() -> void:
	var r := VoiceRules.new()
	r.threshold_db = -50.0
	r.normal_db = -30.0
	_feed(r, -80.0, 1.0)
	var opened := false
	# Typing: loud 1-2 frame clicks, eight a second, for two seconds.
	for i in 16:
		for f in 7:
			var s: FaceState = r.step(-25.0 if f < 2 else -80.0, Vector3(0.1, 0.3, 1.0), DT)
			opened = opened or s.mouth != FaceState.MOUTH_CLOSED
	check(not opened, "keyboard clicks don't open the mouth")
	check(not r.laughing(), "and aren't a laugh")


func _laugh() -> void:
	var r := VoiceRules.new()
	r.threshold_db = -50.0
	r.normal_db = -30.0
	_feed(r, -80.0, 1.0)
	# "Ha ha ha ha": 0.1 s loud, 0.1 s quiet, five a second.
	var laughed := false
	var mouth_while := -1
	for i in 5:
		var s := _feed(r, -28.0, 0.1)
		laughed = laughed or s.mood == FaceState.MOOD_LAUGH
		if s.mood == FaceState.MOOD_LAUGH:
			mouth_while = s.mouth
		_feed(r, -80.0, 0.1)
	check(laughed and mouth_while == FaceState.MOUTH_LAUGH, "a run of short bursts is a laugh, with the big toothy smile")
	check(r.laughing(), "still laughing just after the last burst")
	var after := _feed(r, -80.0, 0.6)
	check(not r.laughing() and after.mood == FaceState.MOOD_SMILE and after.mouth == FaceState.MOUTH_SMILE,
			"half a second after, a closed smile: %s" % after)
	var later := _feed(r, -80.0, 2.1)
	check(later.mood == FaceState.MOOD_NEUTRAL and later.mouth == FaceState.MOUTH_CLOSED, "and two seconds later, neutral")
	# Ordinary talk: long syllables, not a laugh.
	var r2 := VoiceRules.new()
	r2.threshold_db = -50.0
	r2.normal_db = -30.0
	var talk_laughed := false
	for i in 6:
		talk_laughed = talk_laughed or _feed(r2, -30.0, 0.45).mood == FaceState.MOOD_LAUGH
		talk_laughed = talk_laughed or _feed(r2, -70.0, 0.15).mood == FaceState.MOOD_LAUGH
	check(not talk_laughed, "ordinary talk isn't a laugh")


func _shout() -> void:
	var r := VoiceRules.new()
	r.threshold_db = -50.0
	r.normal_db = -30.0
	var brief := _feed(r, -15.0, 0.15)
	check(brief.mood != FaceState.MOOD_SHOUT, "a brief loud word isn't a shout")
	var s := _feed(r, -15.0, 0.4)
	check(s.mood == FaceState.MOOD_SHOUT and s.mouth == FaceState.MOUTH_SHOUT, "loud for over 0.3 s is a shout: %s" % s)
	var quiet := _feed(r, -80.0, 0.3)
	check(quiet.mood == FaceState.MOOD_SHOUT and quiet.mouth == FaceState.MOUTH_CLOSED, "gone quiet after a shout: a frown")
	check(_feed(r, -80.0, 1.0).mood == FaceState.MOOD_NEUTRAL, "which passes")


func _calibration() -> void:
	var quiet := PackedFloat32Array()
	for i in 120:
		quiet.append(-62.0 + randf() * 4.0)
	quiet.append(-20.0)  # a bump on the desk
	var talk := PackedFloat32Array()
	for i in 180:
		talk.append(-34.0 + randf() * 8.0 if i % 4 != 0 else -70.0)
	var res: Dictionary = FaceVoice.calibration_result(quiet, talk)
	check(res.threshold_db > -60.0 and res.threshold_db < -50.0, "threshold a little over the room's noise: %s" % [res])
	check(res.normal_db > -35.0 and res.normal_db < -25.0, "normal level from the talking: %s" % [res])
	var none: Dictionary = FaceVoice.calibration_result(PackedFloat32Array(), PackedFloat32Array())
	check(none.normal_db > none.threshold_db, "nothing heard still gives usable numbers: %s" % [none])
