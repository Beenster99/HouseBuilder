extends RefCounted
## What a contract firm unlocks by tier and what it can buy. Plain data, tuned after
## playtests. ids: "material:<id>", "kind:<catalog kind>", "roof:<flat|mono|gable|hip>",
## "lib:<library palette group>", "gear:<demolition gear>".

## Always in force: materials and part kinds held back until a tier.
const CORE := [
	{"tier": 1, "id": "material:timber", "label": "Timber"},
	{"tier": 1, "id": "material:masonry", "label": "Brick and block"},
	{"tier": 1, "id": "material:concrete", "label": "Reinforced concrete"},
	{"tier": 1, "id": "material:glass", "label": "Glazing"},
	{"tier": 1, "id": "material:ceramic", "label": "Sanitaryware"},
	{"tier": 3, "id": "material:steel", "label": "Structural steel"},
	{"tier": 3, "id": "kind:truss", "label": "Trusses"},
	{"tier": 4, "id": "kind:pile", "label": "Bored piles"},
	{"tier": 4, "id": "material:glulam", "label": "Glulam"},
	{"tier": 5, "id": "kind:curtain_wall", "label": "Curtain walling"},
	{"tier": 5, "id": "kind:raft", "label": "Raft foundations"},
]

## The wider tree (flag contracts.unlock_tree): roof shapes, library groups, lifts and
## demolition gear.
const TREE := [
	{"tier": 1, "id": "roof:flat", "label": "Flat roofs"},
	{"tier": 1, "id": "roof:mono", "label": "Mono-pitch roofs"},
	{"tier": 1, "id": "gear:charge_small", "label": "Small charges"},
	{"tier": 1, "id": "lib:furniture", "label": "Furniture"},
	{"tier": 1, "id": "lib:home", "label": "Home fittings"},
	{"tier": 1, "id": "lib:services", "label": "Services fittings"},
	{"tier": 1, "id": "lib:office", "label": "Office furniture"},
	{"tier": 1, "id": "lib:retail", "label": "Shop fittings"},
	{"tier": 1, "id": "lib:sport", "label": "Sport"},
	{"tier": 1, "id": "lib:street_and_garden", "label": "Street and garden"},
	{"tier": 1, "id": "lib:landscape", "label": "Landscape"},
	{"tier": 1, "id": "lib:gates_and_posts", "label": "Gates and posts"},
	{"tier": 1, "id": "lib:vehicles", "label": "Vehicles"},
	{"tier": 1, "id": "lib:site_plant", "label": "Site plant"},
	{"tier": 1, "id": "lib:farm", "label": "Farm"},
	{"tier": 1, "id": "lib:animals", "label": "Animals"},
	{"tier": 2, "id": "roof:gable", "label": "Gable roofs"},
	{"tier": 2, "id": "roof:hip", "label": "Hipped roofs"},
	{"tier": 2, "id": "gear:charge_standard", "label": "Standard charges"},
	{"tier": 3, "id": "lib:education", "label": "School furniture"},
	{"tier": 3, "id": "lib:catering_and_hotel", "label": "Catering and hotel fittings"},
	{"tier": 3, "id": "lib:industrial", "label": "Industrial equipment"},
	{"tier": 3, "id": "gear:delay_presets", "label": "Firing delay presets"},
	{"tier": 4, "id": "kind:lift", "label": "Lifts"},
	{"tier": 4, "id": "gear:charge_heavy", "label": "Heavy charges"},
	{"tier": 4, "id": "lib:stations", "label": "Station fittings"},
	{"tier": 5, "id": "lib:police", "label": "Police equipment"},
	{"tier": 5, "id": "lib:theatre_and_cinema", "label": "Theatre and cinema fittings"},
	{"tier": 5, "id": "gear:wrecking_ball", "label": "The wrecking ball"},
	{"tier": 6, "id": "lib:healthcare", "label": "Medical equipment"},
	{"tier": 6, "id": "lib:courts_and_prison", "label": "Court and prison fittings"},
	{"tier": 7, "id": "lib:airport", "label": "Airport equipment"},
	{"tier": 7, "id": "lib:energy", "label": "Energy plant"},
	{"tier": 7, "id": "lib:water", "label": "Water plant"},
]

## Catalog kinds that are a roof shape.
const KIND_UNLOCK := {"roof_flat": "roof:flat", "roof_mono": "roof:mono", "roof_pitched": "roof:gable", "roof_gable": "roof:gable", "roof_hip": "roof:hip"}

## Firm upgrades bought with money, kept for good. effect: name -> value, read through
## ContractsBus.effect(name). A deal takes an option (a material).
const UPGRADES := [
	{"id": "survey_kit", "label": "Site survey kit", "price": 20000.0,
		"blurb": "See each offer's site difficulty and extra cost before you accept.", "effect": {"survey": 1.0}},
	{"id": "bulk_deal", "label": "Bulk supplier deal", "price": 50000.0, "option": "material",
		"blurb": "5% off everything in one structural material.", "effect": {"material_discount": 0.05}},
	{"id": "second_crew", "label": "Second crew", "price": 60000.0,
		"blurb": "Builds go 15% faster, so deadlines are easier to make.", "effect": {"schedule_factor": 0.85}},
	{"id": "blast_consultant", "label": "Blast consultant", "price": 70000.0,
		"blurb": "Shows where the debris will land before you fire.", "effect": {"debris_preview": 1.0}},
	{"id": "in_house_engineer", "label": "In-house engineer", "price": 80000.0,
		"blurb": "The structure checks name the cheapest fix.", "effect": {"engineer_hints": 1.0}},
]
