class_name FaceLook
extends RefCounted
## How a player looks, so the crew can tell each other apart: plain data, picked on the
## "Your avatar" page, kept in Settings on the player's own machine and shared with the crew
## by the faces.look event. Every field is a small index into the tables below.
##   var look := FaceLook.random(hash("Ana"))
##   var copy := FaceLook.from_dict(look.to_dict())   # from_dict clamps junk to valid values
## suit, headgear and headgear_colour dress the avatar itself (MultiplayerBus.set_avatar_look,
## once multiplayer has it); the rest is the drawn face.

const SUITS: Array[Color] = [Color("e8792b"), Color("d94141"), Color("3f7fd9"), Color("3fa65a"),
		Color("e0c03a"), Color("8a55c9"), Color("2fb5b0"), Color("e46fa8"), Color("5b5f66"),
		Color("f2f0e8")]
const SUIT_NAMES: PackedStringArray = ["Orange", "Red", "Blue", "Green", "Yellow", "Purple",
		"Teal", "Pink", "Grey", "White"]
const HEADGEAR_NAMES: PackedStringArray = ["Hard hat", "Helmet", "Cap", "None"]
## What the avatar wears for each, in MultiplayerBus.set_avatar_look's words.
const HEADGEAR_IDS: PackedStringArray = ["hard_hat", "helmet", "cap", "none"]
const HARD_HAT := 0
const HELMET := 1
const CAP := 2
const NO_HEADGEAR := 3
const HEADGEAR_COLOURS: Array[Color] = [Color("f2d22e"), Color("f2f0e8"), Color("e8792b"),
		Color("3f7fd9"), Color("d94141"), Color("3fa65a")]
const HEADGEAR_COLOUR_NAMES: PackedStringArray = ["Yellow", "White", "Orange", "Blue", "Red", "Green"]
const SKINS: Array[Color] = [Color("fde3cf"), Color("f6cfae"), Color("eab68b"), Color("d79e6c"),
		Color("b97c4e"), Color("94603a"), Color("6e4429"), Color("4b2e1c")]
const EYE_NAMES: PackedStringArray = ["Round", "Oval", "Sleepy", "Wide"]
const BROW_NAMES: PackedStringArray = ["Thin", "Thick", "Arched", "None"]
const HAIR_NAMES: PackedStringArray = ["Short", "Spiky", "Fringe", "Long", "Curly", "Bald"]
const BALD := 5
const HAIR_COLOURS: Array[Color] = [Color("1d1a17"), Color("4a2f1d"), Color("7b4a26"),
		Color("b5793c"), Color("e1c27a"), Color("b4442a"), Color("9a9a9a"), Color("eeeeee")]
const HAIR_COLOUR_NAMES: PackedStringArray = ["Black", "Dark brown", "Brown", "Light brown",
		"Blond", "Ginger", "Grey", "White"]
const EXTRAS: PackedStringArray = ["glasses", "sunglasses", "moustache", "beard", "freckles"]
const EXTRA_NAMES: PackedStringArray = ["Glasses", "Sunglasses", "Moustache", "Beard", "Freckles"]

var suit := 0
var headgear := HARD_HAT
var headgear_colour := 0
var skin := 1
var eyes := 0
var brows := 0
var hair := 0
var hair_colour := 1
var glasses := false
var sunglasses := false
var moustache := false
var beard := false
var freckles := false


## A look rolled from a seed: the same seed always gives the same look, so a player who never
## opens the page still has their own look (rolled from their name).
static func random(seed_value: int) -> FaceLook:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var l := FaceLook.new()
	l.suit = rng.randi_range(0, SUITS.size() - 1)
	l.headgear = HARD_HAT if rng.randf() < 0.5 else rng.randi_range(0, HEADGEAR_NAMES.size() - 1)
	l.headgear_colour = rng.randi_range(0, HEADGEAR_COLOURS.size() - 1)
	l.skin = rng.randi_range(0, SKINS.size() - 1)
	l.eyes = rng.randi_range(0, EYE_NAMES.size() - 1)
	l.brows = rng.randi_range(0, BROW_NAMES.size() - 1)
	l.hair = rng.randi_range(0, HAIR_NAMES.size() - 1)
	l.hair_colour = rng.randi_range(0, HAIR_COLOURS.size() - 1)
	var r := rng.randf()
	l.glasses = r < 0.2
	l.sunglasses = r >= 0.2 and r < 0.28
	l.moustache = rng.randf() < 0.2
	l.beard = rng.randf() < 0.15
	l.freckles = rng.randf() < 0.2
	return l


func to_dict() -> Dictionary:
	return {"suit": suit, "headgear": headgear, "headgear_colour": headgear_colour, "skin": skin,
			"eyes": eyes, "brows": brows, "hair": hair, "hair_colour": hair_colour,
			"glasses": glasses, "sunglasses": sunglasses, "moustache": moustache, "beard": beard,
			"freckles": freckles}


## Anything missing, of the wrong type or out of range falls back to a valid value.
static func from_dict(d: Variant) -> FaceLook:
	var l := FaceLook.new()
	if not d is Dictionary:
		return l
	var src: Dictionary = d
	l.suit = _index(src, "suit", SUITS.size(), l.suit)
	l.headgear = _index(src, "headgear", HEADGEAR_NAMES.size(), l.headgear)
	l.headgear_colour = _index(src, "headgear_colour", HEADGEAR_COLOURS.size(), l.headgear_colour)
	l.skin = _index(src, "skin", SKINS.size(), l.skin)
	l.eyes = _index(src, "eyes", EYE_NAMES.size(), l.eyes)
	l.brows = _index(src, "brows", BROW_NAMES.size(), l.brows)
	l.hair = _index(src, "hair", HAIR_NAMES.size(), l.hair)
	l.hair_colour = _index(src, "hair_colour", HAIR_COLOURS.size(), l.hair_colour)
	for e in EXTRAS:
		var v: Variant = src.get(e)
		l.set(e, v is bool and v)
	if l.glasses and l.sunglasses:
		l.glasses = false
	return l


func equals(other: FaceLook) -> bool:
	return other != null and to_dict() == other.to_dict()


func suit_colour() -> Color:
	return SUITS[suit]


func skin_colour() -> Color:
	return SKINS[skin]


func hair_colour_value() -> Color:
	return HAIR_COLOURS[hair_colour]


func headgear_colour_value() -> Color:
	return HEADGEAR_COLOURS[headgear_colour]


static func _index(src: Dictionary, key: String, count: int, fallback: int) -> int:
	var v: Variant = src.get(key)
	if not (v is int or v is float) or (v is float and not is_finite(v)):
		return fallback
	return clampi(int(v), 0, count - 1)
