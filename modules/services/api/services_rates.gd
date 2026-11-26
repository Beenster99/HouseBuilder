class_name ServicesRates
extends RefCounted
## What the M&E consultant routes and what it costs. Approximate UK installed rates (GBP,
## 2025 to 2026, materials and labour), game values to tune in playtesting.
##
## Systems, in the order the consultant routes them:
##   power      cable from the consumer unit to a lighting and socket point in every room
##   cold_water from the incoming water main to every wet fixture (and the boiler)
##   hot_water  from the boiler to every basin, bath, shower and sink
##   waste      from every wet fixture down to the soil stack (never runs uphill)

const SYSTEMS: PackedStringArray = ["power", "cold_water", "hot_water", "waste"]

const SYSTEM := {
	"power": {"label": "Power", "run": "cable", "source": "consumer unit", "source_kind": "consumer_unit",
		"per_m": 14.0, "per_point": 220.0, "source_cost": 750.0, "height": 2.6},
	"cold_water": {"label": "Cold water", "run": "pipe", "source": "water main", "source_kind": "water_main",
		"per_m": 30.0, "per_point": 45.0, "source_cost": 1800.0, "height": 0.25},
	"hot_water": {"label": "Hot water", "run": "pipe", "source": "boiler", "source_kind": "boiler",
		"per_m": 34.0, "per_point": 45.0, "source_cost": 2800.0, "height": 0.35},
	"waste": {"label": "Waste", "run": "pipe", "source": "soil stack", "source_kind": "soil_stack",
		"per_m": 40.0, "per_m_wc": 75.0, "per_point": 60.0, "source_cost": 1200.0, "height": 0.05},
}

## Holes the routes make. A route through a door opening needs none.
const PENETRATION := {"wall": 15.0, "structural_wall": 90.0, "floor": 60.0, "riser_floor": 30.0}

## Runs in these rooms go in a ceiling void or a service zone: cheaper per metre.
const SERVICE_ZONE_FACTOR := 0.8
## Room types where a riser goes through the floor at the riser rate.
const RISER_ROOMS: PackedStringArray = ["plant_room", "store_room", "utility", "backup_power"]
## Room types no service may run through.
const NO_GO_ROOMS: PackedStringArray = ["lift_shaft"]
## Wall kinds no route may pass through except at a door.
const SEALED_WALLS: PackedStringArray = ["curtain_wall"]

## Room types that must be plumbed. hot: needs hot water as well as cold and waste.
const WET_ROOMS := {
	"bathroom": {"hot": true}, "wc_room": {"hot": false}, "kitchen": {"hot": true},
	"utility": {"hot": true}, "toilet_block": {"hot": true}, "commercial_kitchen": {"hot": true},
}

## Fixture kinds the routes end at: which systems each needs. A room's first kitchen unit
## (by id) is its sink; the others need nothing.
const FIXTURE_NEEDS := {
	"wc": ["cold_water", "waste"],
	"basin": ["cold_water", "hot_water", "waste"],
	"bath": ["cold_water", "hot_water", "waste"],
	"shower": ["cold_water", "hot_water", "waste"],
	"kitchen_unit": ["cold_water", "hot_water", "waste"],
}

## Longest waste branch from a fixture to the soil stack before the consultant warns (m).
const MAX_BRANCH := {"wc": 6.0, "default": 4.0}

## Where the consultant puts a source the players have not placed, best room type first.
const AUTO_ROOMS := {
	"power": ["plant_room", "utility", "garage", "hallway", "store_room", "corridor", "reception", "kitchen"],
	"cold_water": ["plant_room", "utility", "kitchen", "garage", "hallway", "corridor"],
	"hot_water": ["plant_room", "utility", "kitchen", "garage", "bathroom", "store_room"],
}


static func label(system: String) -> String:
	return str(SYSTEM.get(system, {}).get("label", system))


static func is_system(system: String) -> bool:
	return system in SYSTEMS


static func is_wet_room(room_type: String) -> bool:
	return WET_ROOMS.has(room_type)
