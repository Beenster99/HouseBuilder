class_name FaceState
extends RefCounted
## What a player's face is doing right now: the mouth shape, how far it is open, the mood
## and whether the player has muted it. Packed into 2 bytes (11 bits used) for the wire:
##   bits 0-2 mouth (MOUTH_*), 3-6 openness 0..15, 7-9 mood (MOOD_*), 10 muted.
## Blinking and where the pupils point are worked out on each viewer's machine, not sent.

const MOUTH_CLOSED := 0
const MOUTH_SMILE := 1
const MOUTH_SMALL := 2
const MOUTH_WIDE := 3
const MOUTH_ROUND := 4
const MOUTH_TEETH := 5
const MOUTH_LAUGH := 6
const MOUTH_SHOUT := 7
const MOUTH_COUNT := 8
const MOUTH_NAMES: PackedStringArray = ["Closed", "Closed smile", "Small open", "Wide open",
		"Round", "Wide with teeth", "Laughing", "Shouting"]

const MOOD_NEUTRAL := 0
const MOOD_SMILE := 1
const MOOD_LAUGH := 2
const MOOD_SHOUT := 3
const MOOD_HAPPY := 4
const MOOD_SAD := 5
const MOOD_SURPRISED := 6
const MOOD_ANGRY := 7
const MOOD_NAMES: PackedStringArray = ["Neutral", "Smile", "Laugh", "Shout", "Happy", "Sad",
		"Surprised", "Angry"]

var mouth := MOUTH_CLOSED
## 0 (shut) to 15 (as wide as it goes).
var openness := 0
var mood := MOOD_NEUTRAL
var muted := false


static func make(m: int, open: int = 0, md: int = MOOD_NEUTRAL, mute := false) -> FaceState:
	var s := FaceState.new()
	s.mouth = clampi(m, 0, MOUTH_COUNT - 1)
	s.openness = clampi(open, 0, 15)
	s.mood = clampi(md, 0, MOOD_NAMES.size() - 1)
	s.muted = mute
	return s


func pack() -> int:
	return (mouth & 7) | ((openness & 15) << 3) | ((mood & 7) << 7) | ((1 if muted else 0) << 10)


static func unpack(bits: int) -> FaceState:
	bits = clampi(bits, 0, 0xFFFF)
	return make(bits & 7, (bits >> 3) & 15, (bits >> 7) & 7, ((bits >> 10) & 1) == 1)


func equals(other: FaceState) -> bool:
	return other != null and pack() == other.pack()


func duplicate_state() -> FaceState:
	return unpack(pack())


func _to_string() -> String:
	return "%s/%d/%s%s" % [MOUTH_NAMES[mouth], openness, MOOD_NAMES[mood], " muted" if muted else ""]
