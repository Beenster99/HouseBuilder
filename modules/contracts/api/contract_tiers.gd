class_name ContractTiers
extends RefCounted
## The architecture firm's tiers. The firm earns XP for each contract it completes, and XP
## raises its tier. Each tier offers bigger and more complex buildings, from small works up
## to major projects. Building types name their tier in internal/building_types.gd. Plain
## data and static helpers.
##
##   ContractTiers.tier_for(xp)        # 1..TIERS.size()
##   ContractTiers.info(3)             # {tier, xp, name, blurb, award}
##   ContractTiers.progress(xp)        # {tier, name, xp, floor, next, next_name, share}
##   ContractTiers.MAX_XP              # the top tier's threshold (the debug menu's Max XP)
##
## xp: XP needed to reach the tier. award: about what one contract at the tier earns. A
## tier takes about four contracts at the tier below.

const TIERS := [
	{"tier": 1, "xp": 0, "name": "Small works", "award": 250,
		"blurb": "Garden studios, garages, corner shops and sports pavilions: one storey, a handful of rooms."},
	{"tier": 2, "xp": 1000, "name": "Homes", "award": 500,
		"blurb": "Bungalows, terraces, semi-detached houses and holiday lodges."},
	{"tier": 3, "xp": 3000, "name": "Family homes and community", "award": 1000,
		"blurb": "Detached houses, rows of houses, guest houses, pubs, industrial units, community halls and day nurseries. Structural steel and trusses."},
	{"tier": 4, "xp": 7000, "name": "Public buildings", "award": 2000,
		"blurb": "Primary schools, branch libraries, fire stations, bus stations, shopping parades and retreats. Piles and glulam."},
	{"tier": 5, "xp": 15000, "name": "Civic and commercial", "award": 3500,
		"blurb": "Police stations, office blocks, secondary schools, apartment buildings, council offices, business centres, hotels and cinemas. Curtain walling and rafts."},
	{"tier": 6, "xp": 30000, "name": "Healthcare and landmarks", "award": 6000,
		"blurb": "Health clinics, care homes, theatres, law courts, mansion houses and retail parks."},
	{"tier": 7, "xp": 60000, "name": "Major projects", "award": 12000,
		"blurb": "Hospital wings, airport terminals, train stations and prisons."},
]
const MAX_XP := 60000


static func tier_for(xp: int) -> int:
	var t := 1
	for d: Dictionary in TIERS:
		if xp >= int(d.xp):
			t = int(d.tier)
	return t


static func top() -> int:
	return TIERS.size()


## A tier's row ({} outside 1..top()).
static func info(tier: int) -> Dictionary:
	return (TIERS[tier - 1] as Dictionary).duplicate() if tier >= 1 and tier <= TIERS.size() else {}


## Where the firm stands: its tier and name, its xp, the tier's floor, the next tier's
## threshold and name (-1 and "" at the top), and share (0..1) of the way there.
static func progress(xp: int) -> Dictionary:
	var t := tier_for(xp)
	var cur := info(t)
	var nxt := info(t + 1)
	var out := {"tier": t, "name": str(cur.name), "xp": xp, "floor": int(cur.xp), "next": -1, "next_name": "", "share": 1.0}
	if not nxt.is_empty():
		out.next = int(nxt.xp)
		out.next_name = str(nxt.name)
		out.share = clampf(float(xp - int(cur.xp)) / float(int(nxt.xp) - int(cur.xp)), 0.0, 1.0)
	return out


## "1,450 XP" style.
static func xp_text(xp: int) -> String:
	var s := str(absi(xp))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if xp < 0 else "") + s + out + " XP"
