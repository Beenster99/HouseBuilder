extends RefCounted
## Awkward briefs: twists the generator adds to a brief (ContractTwists.apply). Plain data,
## so they can be tuned after a playtest.
##
## id, label, sentence (added to the brief's summary), tier (the lowest firm tier that sees
## it), uplift (the fee goes up by this share for the trouble), needs (what the plot must
## have: "" any plot, "site" a real one, or a site factor id such as "slope"), clashes (twists
## never paired with it), and what it does: budget/deadline factors, a material change, or
## a requirement added (see ContractValidator for each kind), with the checklist tip.
## categories (optional): the building categories it suits. existing: a building already on
## the plot that must be kept ("house", "frontage"), set up locked when the job is accepted.

const TWISTS := [
	{"id": "shoestring", "label": "Shoestring", "tier": 1, "uplift": 0.06, "needs": "", "clashes": [],
		"sentence": "Money is tight: the build budget is 15% below what this would normally cost.",
		"budget": 0.85},
	{"id": "rush", "label": "Rush job", "tier": 1, "uplift": 0.08, "needs": "", "clashes": [],
		"sentence": "The client needs it fast: the deadline is 30% shorter than usual.",
		"deadline": 0.7},
	{"id": "material_ban", "label": "Material ban", "tier": 2, "uplift": 0.04, "needs": "", "clashes": ["timber_only"],
		"sentence": "The client will not have %s in the structure.", "ban": ["steel", "concrete", "masonry", "timber"]},
	{"id": "timber_only", "label": "Timber only", "tier": 2, "uplift": 0.06, "needs": "", "clashes": ["material_ban"],
		"sentence": "The client wants a low-carbon building: the structure must be timber.", "only": ["timber", "glulam"],
		"max_storeys": 3},
	{"id": "flood_zone", "label": "Flood zone", "tier": 2, "uplift": 0.06, "needs": "", "clashes": [],
		"sentence": "The plot is in a flood zone: the ground floor must sit at least 0.6 m above the ground, with no bedrooms on it.",
		"require": {"kind": "raised_floor", "value": 0.6}},
	{"id": "tight_neighbours", "label": "Tight neighbours", "tier": 2, "uplift": 0.05, "needs": "neighbours", "clashes": [],
		"sentence": "The neighbours are close: nothing may come within 1 m of the boundary.",
		"require": {"kind": "boundary_gap", "value": 1.0}},
	{"id": "open_plan", "label": "Open plan", "tier": 3, "uplift": 0.05, "needs": "", "clashes": [],
		"sentence": "The client wants open, flexible floors: no columns standing inside the ground-floor rooms.",
		"require": {"kind": "column_free"}},
	{"id": "soft_ground", "label": "Soft ground", "tier": 4, "uplift": 0.06, "needs": "ground", "clashes": [],
		"sentence": "The ground is poor: the building must stand on piles or a raft.",
		"require": {"kind": "foundation_type", "allowed": ["pile", "raft"]}},
	{"id": "sloping_plot", "label": "Sloping plot", "tier": 4, "uplift": 0.08, "needs": "slope", "clashes": [],
		"sentence": "The plot slopes hard: the building must stand on piles, which can be cut to the slope.",
		"require": {"kind": "foundation_type", "allowed": ["pile"]}},
	{"id": "extension", "label": "Extension", "tier": 2, "uplift": 0.07, "needs": "", "clashes": ["flood_zone", "soft_ground", "sloping_plot", "keep_frontage"],
		"categories": ["domestic", "hospitality"],
		"sentence": "There is already a small house at the back of the plot: it stays as it is, and the new rooms are built on to it.",
		"existing": "house", "require": {"kind": "keep_existing"}},
	{"id": "keep_frontage", "label": "Keep the frontage", "tier": 3, "uplift": 0.06, "needs": "", "clashes": ["flood_zone", "soft_ground", "sloping_plot", "extension"],
		"categories": ["retail", "office", "civic", "hospitality", "leisure", "justice"],
		"sentence": "The old street front is listed: its wall stays as it is, and the new building goes up behind it.",
		"existing": "frontage", "require": {"kind": "keep_existing"}},
]

## The chance a brief gets a twist at all, by firm tier (1..7); a second twist comes with
## SECOND_SHARE of that chance.
const CHANCE := [0.0, 0.2, 0.28, 0.37, 0.45, 0.53, 0.62, 0.7]
const SECOND_SHARE := 0.4
