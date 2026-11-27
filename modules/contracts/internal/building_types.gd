extends RefCounted
## What each kind of building needs, for ContractGenerator to roll briefs from. Plain data.
##
## program: rooms the client wants, [type, min count, max count, per-room capacity or 0].
## A count grows with the brief's size roll (0..1). extras: other hard requirements, added
## as they are. goals: soft goals, each with a bonus as a share of the fee.
## rate: budget per m2 of floor, GBP, matched to the building catalog's prices (a plain
## shell with fit-out comes in around 900 to 1,200 per m2), so a careful design fits.
## rep: reputation needed before this type is offered. storeys: [min, max] allowed.
## circulation: extra floor area on top of the rooms (corridors, walls).

const TYPES := {
	"bungalow": {"label": "Bungalow", "category": "domestic", "rep": 0, "storeys": [1, 1], "rate": 1350.0, "circulation": 0.15,
		"program": [["bedroom", 2, 3, 0], ["bathroom", 1, 1, 0], ["kitchen", 1, 1, 0], ["living_room", 1, 1, 0], ["hallway", 1, 1, 0]],
		"extras": [], "goals": [["garage", 0.04], ["utility", 0.02]]},
	"terraced_house": {"label": "Terraced house", "category": "domestic", "rep": 0, "storeys": [2, 2], "rate": 1300.0, "circulation": 0.12,
		"program": [["bedroom", 2, 3, 0], ["bathroom", 1, 1, 0], ["kitchen", 1, 1, 0], ["living_room", 1, 1, 0]],
		"extras": [{"kind": "max_footprint", "value": 60.0}], "goals": [["wc_room", 0.02], ["study", 0.03]]},
	"semi_detached": {"label": "Semi-detached house", "category": "domestic", "rep": 0, "storeys": [2, 2], "rate": 1300.0, "circulation": 0.15,
		"program": [["bedroom", 3, 3, 0], ["bathroom", 1, 2, 0], ["kitchen", 1, 1, 0], ["living_room", 1, 1, 0], ["hallway", 1, 1, 0]],
		"extras": [], "goals": [["garage", 0.04], ["wc_room", 0.02]]},
	"detached_house": {"label": "Detached house", "category": "domestic", "rep": 5, "storeys": [1, 2], "rate": 1300.0, "circulation": 0.18,
		"program": [["bedroom", 3, 5, 0], ["bathroom", 2, 3, 0], ["kitchen", 1, 1, 0], ["living_room", 1, 1, 0], ["garage", 1, 1, 0]],
		"extras": [{"kind": "double_bedroom", "count": 1}], "goals": [["study", 0.03], ["utility", 0.02], ["dining_room", 0.03]]},
	"nursery": {"label": "Day nursery", "category": "education", "rep": 8, "storeys": [1, 1], "rate": 1150.0, "circulation": 0.2,
		"program": [["classroom", 2, 3, 20], ["toilet_block", 1, 1, 0], ["kitchen", 1, 1, 0], ["staff_room", 1, 1, 0]],
		"extras": [{"kind": "accessible_entrance"}, {"kind": "exit_distance", "value": 30.0}], "goals": [["store_room", 0.02]]},
	"primary_school": {"label": "Primary school", "category": "education", "rep": 10, "storeys": [1, 2], "rate": 1100.0, "circulation": 0.2,
		"program": [["classroom", 6, 14, 30], ["school_hall", 1, 1, 0], ["toilet_block", 1, 2, 0], ["staff_room", 1, 1, 0]],
		"extras": [{"kind": "accessible_entrance"}, {"kind": "exit_distance", "value": 30.0}, {"kind": "lift_if_storeys"}],
		"goals": [["library", 0.04], ["commercial_kitchen", 0.04]]},
	"secondary_school": {"label": "Secondary school", "category": "education", "rep": 30, "storeys": [2, 3], "rate": 1150.0, "circulation": 0.22,
		"program": [["classroom", 16, 30, 30], ["school_hall", 1, 1, 0], ["library", 1, 1, 0], ["toilet_block", 2, 4, 0], ["staff_room", 1, 1, 0], ["commercial_kitchen", 1, 1, 0]],
		"extras": [{"kind": "accessible_entrance"}, {"kind": "exit_distance", "value": 30.0}, {"kind": "lift_if_storeys"}, {"kind": "structure"}],
		"goals": [["meeting_room", 0.02]]},
	"community_hall": {"label": "Community hall", "category": "civic", "rep": 5, "storeys": [1, 1], "rate": 1150.0, "circulation": 0.15,
		"program": [["school_hall", 1, 1, 0], ["kitchen", 1, 1, 0], ["wc_room", 2, 3, 0], ["store_room", 1, 1, 0]],
		"extras": [{"kind": "accessible_entrance"}, {"kind": "exit_distance", "value": 30.0}], "goals": [["meeting_room", 0.03]]},
	"library_branch": {"label": "Branch library", "category": "civic", "rep": 12, "storeys": [1, 2], "rate": 1200.0, "circulation": 0.18,
		"program": [["library", 1, 2, 0], ["reception", 1, 1, 0], ["meeting_room", 1, 2, 0], ["wc_room", 2, 2, 0]],
		"extras": [{"kind": "accessible_entrance"}, {"kind": "exit_distance", "value": 30.0}, {"kind": "lift_if_storeys"}], "goals": [["study", 0.02]]},
	"police_station": {"label": "Police station", "category": "police", "rep": 20, "storeys": [1, 2], "rate": 1400.0, "circulation": 0.2,
		"program": [["reception", 1, 1, 0], ["custody_desk", 1, 1, 0], ["custody_cell", 4, 10, 1], ["interview_room", 1, 3, 0],
			["vehicle_bay", 1, 1, 0], ["locker_room", 1, 1, 0], ["office", 1, 3, 0]],
		"extras": [{"kind": "accessible_entrance"}, {"kind": "secure_cells"}, {"kind": "near", "a": "custody_cell", "b": "custody_desk", "value": 15.0},
			{"kind": "vehicle_access"}, {"kind": "exit_distance", "value": 30.0}],
		"goals": [["meeting_room", 0.02], ["store_room", 0.02]]},
	"fire_station": {"label": "Fire station", "category": "civic", "rep": 25, "storeys": [1, 2], "rate": 1350.0, "circulation": 0.15,
		"program": [["vehicle_bay", 2, 4, 0], ["locker_room", 1, 1, 0], ["kitchen", 1, 1, 0], ["office", 1, 2, 0], ["bathroom", 1, 2, 0]],
		"extras": [{"kind": "vehicle_access"}, {"kind": "exit_distance", "value": 30.0}], "goals": [["meeting_room", 0.02]]},
	"office_block": {"label": "Office block", "category": "office", "rep": 30, "storeys": [2, 5], "rate": 1250.0, "circulation": 0.2,
		"program": [["office", 4, 16, 0], ["meeting_room", 2, 6, 0], ["reception", 1, 1, 0], ["toilet_block", 2, 5, 0], ["plant_room", 1, 1, 0]],
		"extras": [{"kind": "accessible_entrance"}, {"kind": "exit_distance", "value": 45.0}, {"kind": "lift_if_storeys"}, {"kind": "structure"}],
		"goals": [["staff_room", 0.02]]},
	"health_clinic": {"label": "Health clinic", "category": "health", "rep": 35, "storeys": [1, 2], "rate": 1500.0, "circulation": 0.22,
		"program": [["waiting_area", 1, 1, 0], ["reception", 1, 1, 0], ["single_room", 4, 8, 1], ["nurses_station", 1, 1, 0], ["toilet_block", 1, 2, 0]],
		"extras": [{"kind": "accessible_entrance"}, {"kind": "exit_distance", "value": 30.0}, {"kind": "lift_if_storeys"}],
		"goals": [["store_room", 0.02]]},
	"care_home": {"label": "Care home", "category": "health", "rep": 40, "storeys": [1, 3], "rate": 1450.0, "circulation": 0.25,
		"program": [["single_room", 12, 30, 1], ["dining_room", 1, 2, 0], ["living_room", 1, 3, 0], ["commercial_kitchen", 1, 1, 0], ["nurses_station", 1, 2, 0], ["bathroom", 2, 6, 0]],
		"extras": [{"kind": "accessible_entrance"}, {"kind": "exit_distance", "value": 30.0}, {"kind": "lift_if_storeys"}, {"kind": "structure"}],
		"goals": [["store_room", 0.02]]},
	"hospital_wing": {"label": "Hospital wing", "category": "health", "rep": 60, "storeys": [2, 4], "rate": 1800.0, "circulation": 0.3,
		"program": [["ward_bay", 2, 6, 6], ["single_room", 4, 12, 1], ["nurses_station", 1, 3, 0], ["operating_theatre", 0, 2, 0], ["backup_power", 1, 1, 0], ["plant_room", 1, 1, 0]],
		"extras": [{"kind": "accessible_entrance"}, {"kind": "exit_distance", "value": 30.0}, {"kind": "lift_if_storeys"}, {"kind": "structure"}],
		"goals": [["waiting_area", 0.02]]},
	"airport_terminal": {"label": "Airport terminal", "category": "transport", "rep": 80, "storeys": [1, 3], "rate": 1600.0, "circulation": 0.25,
		"program": [["check_in_hall", 1, 1, 0], ["security_hall", 1, 1, 0], ["departure_lounge", 1, 1, 0], ["gate_lounge", 3, 10, 0],
			["baggage_hall", 1, 1, 0], ["retail_unit", 2, 8, 0], ["toilet_block", 3, 8, 0]],
		"extras": [{"kind": "accessible_entrance"}, {"kind": "exit_distance", "value": 45.0}, {"kind": "lift_if_storeys"}, {"kind": "structure"}],
		"goals": [["plant_room", 0.02]]},
}

## The sites pool's suited_to value for each building type (SitePool.for_building).
const SITE_KIND := {
	"bungalow": "house", "terraced_house": "house", "semi_detached": "house", "detached_house": "house",
	"nursery": "school", "primary_school": "school", "secondary_school": "school",
	"community_hall": "civic", "library_branch": "civic", "fire_station": "civic",
	"police_station": "police_station", "office_block": "office",
	"health_clinic": "hospital", "care_home": "hospital", "hospital_wing": "hospital",
	"airport_terminal": "airport_terminal",
}

## Who asks for each category, for the brief's client line.
const CLIENTS := {
	"domestic": ["The Okafor family", "Mr and Mrs Patel", "A retired couple", "Hughes Homes", "A young family", "The Lindqvists"],
	"education": ["The county council", "St Anne's Academy Trust", "Riverside Learning Trust", "The diocese"],
	"civic": ["The parish council", "The borough council", "A community trust"],
	"police": ["The county constabulary", "The police and crime commissioner"],
	"office": ["Harbour Street Developments", "A tech start-up", "Northgate Property"],
	"health": ["The NHS trust", "Meadow Care Ltd", "The health board"],
	"transport": ["The regional airport authority"],
}

## Size words for titles, by size roll.
const SIZES: PackedStringArray = ["Compact", "Modest", "Roomy", "Large", "Grand"]
