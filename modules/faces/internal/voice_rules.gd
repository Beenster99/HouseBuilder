extends RefCounted
## The rules that turn a microphone's loudness and tone into a face, with no microphone in
## sight: FaceVoice feeds step() a level in dB and three band strengths each frame, and
## tests feed it made-up numbers.
##   var rules := VoiceRules.new()
##   rules.threshold_db = -48.0; rules.normal_db = -30.0
##   var face := rules.step(level_db, Vector3(low, mid, high), delta)   # a FaceState
##
## Loudness above the threshold opens the mouth, and how far above sets how wide. The tone
## picks the shape: mostly low sound is round ("oo", "oh"), mostly high is teeth ("ee", "s",
## "sh"), the rest wide open ("ah"). A sound must last ONSET before the mouth opens, so
## keyboard clicks and bumps on the desk don't flap it, and every shape is held at least HOLD.
## Laughing is a run of short loud bursts with quiet between, four to six a second: LAUGH_BURSTS
## in a row switch to the laughing face, held LAUGH_HOLD after the last, then a closed smile
## for SMILE_AFTER. Shouting is SHOUT_OVER dB above the normal speaking level for SHOUT_TIME.

const FaceStateT := preload("res://modules/faces/api/face_state.gd")

const ONSET := 0.06
const HOLD := 0.07
## A mouth that was talking this recently reopens without waiting ONSET.
const REOPEN := 0.25
## openness below this (0..1) is the small mouth whatever the tone.
const SMALL_BELOW := 0.3
## Share of the sound in the high band (2-8 kHz) that picks teeth, and in the low band
## (80-400 Hz) that picks round.
const TEETH_SHARE := 0.42
const ROUND_SHARE := 0.62
const BURST_MIN := 0.04
const BURST_MAX := 0.3
const GAP_MIN := 0.04
const GAP_MAX := 0.4
## Bursts start this many dB over the threshold (a laugh is loud, a mumble isn't).
const BURST_OVER := 4.0
const LAUGH_BURSTS := 3
const LAUGH_HOLD := 0.5
const SMILE_AFTER := 2.0
const SHOUT_OVER := 9.0
const SHOUT_TIME := 0.3
## The frown after a shout, once the player has gone quiet.
const SHOUT_FROWN := 1.0

## Below this the mouth stays shut (calibration sets it a little over the room's noise).
var threshold_db := -48.0
## The player's ordinary speaking level (calibration measures it).
var normal_db := -28.0

var _above := 0.0
var _below := 0.0
var _quiet_for := 10.0
var _shape := FaceStateT.MOUTH_CLOSED
var _shape_age := 1.0
# Laugh detector.
var _in_burst := false
var _burst_len := 0.0
var _gap_len := 0.0
var _bursts := 0
var _laugh_left := 0.0
var _smile_left := 0.0
# Shout detector.
var _loud := 0.0
var _shouting := false
var _frown_left := 0.0


## 0..1: how far the mouth opens for a level in dB.
func openness_for(level_db: float) -> float:
	var top := maxf(normal_db + 6.0, threshold_db + 6.0)
	return clampf((level_db - threshold_db) / (top - threshold_db), 0.0, 1.0)


## The mouth shape for three band strengths (low 80-400 Hz, mid 400-2000, high 2-8 kHz) at an
## openness of 0..1. Pure: no timing, no state.
static func shape_for(bands: Vector3, open: float) -> int:
	if open <= 0.0:
		return FaceStateT.MOUTH_CLOSED
	if open < SMALL_BELOW:
		return FaceStateT.MOUTH_SMALL
	var total := maxf(bands.x, 0.0) + maxf(bands.y, 0.0) + maxf(bands.z, 0.0)
	if total <= 0.0:
		return FaceStateT.MOUTH_WIDE
	if maxf(bands.z, 0.0) / total >= TEETH_SHARE:
		return FaceStateT.MOUTH_TEETH
	if maxf(bands.x, 0.0) / total >= ROUND_SHARE:
		return FaceStateT.MOUTH_ROUND
	return FaceStateT.MOUTH_WIDE


## One frame of sound: gives the face for it.
func step(level_db: float, bands: Vector3, dt: float) -> FaceState:
	if not is_finite(level_db):
		level_db = -100.0
	dt = clampf(dt, 0.0, 0.25)
	var laughing := _step_laugh(level_db, dt)
	var shouting := _step_shout(level_db, dt)
	# Onset gate: a sound must last ONSET before the mouth opens.
	if level_db > threshold_db:
		_above += dt
		_below = 0.0
	else:
		_below += dt
		_above = 0.0
	# Between words the mouth reopens at once; only a fresh sound after a pause waits ONSET.
	var open := 0.0
	if _above > 0.0 and (_above >= ONSET or _quiet_for < REOPEN):
		open = openness_for(level_db)
	if open > 0.0:
		_quiet_for = 0.0
	else:
		_quiet_for += dt
	var mood := FaceStateT.MOOD_NEUTRAL
	var want: int
	if laughing:
		mood = FaceStateT.MOOD_LAUGH
		want = FaceStateT.MOUTH_LAUGH
		open = maxf(open, 0.5)
	elif shouting and open > 0.0:
		mood = FaceStateT.MOOD_SHOUT
		want = FaceStateT.MOUTH_SHOUT
	else:
		want = shape_for(bands, open)
		if _frown_left > 0.0:
			mood = FaceStateT.MOOD_SHOUT
		elif _smile_left > 0.0:
			mood = FaceStateT.MOOD_SMILE
			if want == FaceStateT.MOUTH_CLOSED:
				want = FaceStateT.MOUTH_SMILE
	_shape_age += dt
	if want != _shape and _shape_age >= HOLD:
		_shape = want
		_shape_age = 0.0
	var shown_open := 0 if _shape == FaceStateT.MOUTH_CLOSED or _shape == FaceStateT.MOUTH_SMILE else maxi(1, roundi(open * 15.0))
	return FaceStateT.make(_shape, shown_open, mood)


func laughing() -> bool:
	return _laugh_left > 0.0


func shouting() -> bool:
	return _shouting


func reset() -> void:
	_above = 0.0
	_below = 0.0
	_quiet_for = 10.0
	_shape = FaceStateT.MOUTH_CLOSED
	_shape_age = 1.0
	_in_burst = false
	_burst_len = 0.0
	_gap_len = 0.0
	_bursts = 0
	_laugh_left = 0.0
	_smile_left = 0.0
	_loud = 0.0
	_shouting = false
	_frown_left = 0.0


func _step_laugh(level_db: float, dt: float) -> bool:
	var loud := level_db > threshold_db + BURST_OVER
	var quiet := level_db <= threshold_db + 1.0
	if _in_burst:
		_burst_len += dt
		if quiet:
			_in_burst = false
			_gap_len = 0.0
			if _burst_len >= BURST_MIN and _burst_len <= BURST_MAX:
				_bursts += 1
				if _bursts >= LAUGH_BURSTS:
					_laugh_left = LAUGH_HOLD
			else:
				_bursts = 0
		elif _burst_len > BURST_MAX:
			_bursts = 0
	else:
		_gap_len += dt
		if loud:
			if _bursts > 0 and _gap_len < GAP_MIN:
				_bursts = 0
			_in_burst = true
			_burst_len = 0.0
		elif _gap_len > GAP_MAX:
			_bursts = 0
	if _laugh_left > 0.0:
		# Keeps laughing while the bursts keep coming; the hold counts from the last one.
		if not _in_burst:
			_laugh_left -= dt
		if _laugh_left <= 0.0:
			_smile_left = SMILE_AFTER
			_bursts = 0
		return _laugh_left > 0.0
	_smile_left = maxf(_smile_left - dt, 0.0)
	return false


func _step_shout(level_db: float, dt: float) -> bool:
	if level_db > normal_db + SHOUT_OVER:
		_loud += dt
		if _loud >= SHOUT_TIME:
			_shouting = true
	else:
		_loud = 0.0
		if _shouting and level_db <= threshold_db:
			_shouting = false
			_frown_left = SHOUT_FROWN
	if not _shouting:
		_frown_left = maxf(_frown_left - dt, 0.0)
	return _shouting
