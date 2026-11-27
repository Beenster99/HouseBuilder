extends RefCounted
## Awkward briefs: twists the generator adds to a brief (ContractTwists.apply). Plain data,
## so they can be tuned after a playtest.
##
## id, label, sentence (added to the brief's summary), tier (the lowest firm tier that sees
## it), uplift (the fee goes up by this share for the trouble), needs (what the plot must
## have: "" any plot, "site" a real one, or a site factor id such as "slope"), clashes (twists
## never paired with it), and what it does: budget/deadline factors, a material change, or
## a requirement added (see ContractValidator for each kind), with the checklist tip.

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
]

## The chance a brief gets a twist at all, by firm tier (1..7); a second twist comes with
## SECOND_SHARE of that chance.
const CHANCE := [0.0, 0.2, 0.28, 0.37, 0.45, 0.53, 0.62, 0.7]
const SECOND_SHARE := 0.4
