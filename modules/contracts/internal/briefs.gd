extends RefCounted
## Hand-written briefs: the plan's three first contracts. Plain data in ContractBrief's shape.
## Budgets are matched to the building catalog's prices; tune them in playtesting.

const BRIEFS := [
	{
		"id": "house_detached_3bed", "title": "Three-bedroom detached house", "type": "detached_house",
		"client": "The Okafor family",
		"summary": "A family home on a quiet plot: three bedrooms (one a proper double), two bathrooms, a kitchen and a garage, on no more than two floors.",
		"budget": 180000.0, "fee": 202000.0, "deadline_days": 150, "reputation": {"min": 0, "reward": 4},
		"requirements": [
			{"id": "bedrooms", "kind": "rooms", "type": "bedroom", "count": 3},
			{"id": "double", "kind": "double_bedroom", "count": 1},
			{"id": "bathrooms", "kind": "rooms", "type": "bathroom", "count": 2},
			{"id": "kitchen", "kind": "rooms", "type": "kitchen", "count": 1},
			{"id": "garage", "kind": "rooms", "type": "garage", "count": 1},
			{"id": "storeys", "kind": "max_storeys", "value": 2},
			{"id": "budget", "kind": "budget"},
		],
		"goals": [
			{"id": "study", "kind": "rooms", "type": "study", "count": 1, "bonus": 6000.0},
			{"id": "thrifty", "kind": "budget", "share": 0.9, "bonus": 8000.0},
		],
	},
	{
		"id": "school_primary_8", "title": "Eight-class primary school", "type": "primary_school",
		"client": "The county council",
		"summary": "A primary school for 240 pupils: eight classrooms of 30, a hall, an accessible entrance, and a fire exit within 30 m of every room.",
		"budget": 900000.0, "fee": 1010000.0, "deadline_days": 420, "reputation": {"min": 0, "reward": 10},
		"requirements": [
			{"id": "classrooms", "kind": "rooms", "type": "classroom", "count": 8, "capacity": 30},
			{"id": "hall", "kind": "rooms", "type": "school_hall", "count": 1},
			{"id": "toilets", "kind": "rooms", "type": "toilet_block", "count": 1},
			{"id": "staff", "kind": "rooms", "type": "staff_room", "count": 1},
			{"id": "entrance", "kind": "accessible_entrance"},
			{"id": "exits", "kind": "exit_distance", "value": 30.0},
			{"id": "lift", "kind": "lift_if_storeys"},
			{"id": "budget", "kind": "budget"},
		],
		"goals": [
			{"id": "library", "kind": "rooms", "type": "library", "count": 1, "bonus": 25000.0},
			{"id": "thrifty", "kind": "budget", "share": 0.9, "bonus": 30000.0},
		],
	},
	{
		"id": "police_station_town", "title": "Town police station", "type": "police_station",
		"client": "The county constabulary",
		"summary": "A town police station: a public front desk, a custody suite of four cells behind secure doors close to the custody desk, an interview room, and a vehicle bay.",
		"budget": 600000.0, "fee": 672000.0, "deadline_days": 330, "reputation": {"min": 0, "reward": 8},
		"requirements": [
			{"id": "front_desk", "kind": "rooms", "type": "reception", "count": 1},
			{"id": "custody_desk", "kind": "rooms", "type": "custody_desk", "count": 1},
			{"id": "cells", "kind": "rooms", "type": "custody_cell", "count": 4, "capacity": 1},
			{"id": "secure", "kind": "secure_cells"},
			{"id": "near_desk", "kind": "near", "a": "custody_cell", "b": "custody_desk", "value": 15.0},
			{"id": "interview", "kind": "rooms", "type": "interview_room", "count": 1},
			{"id": "vehicle_bay", "kind": "rooms", "type": "vehicle_bay", "count": 1},
			{"id": "vehicle_door", "kind": "vehicle_access"},
			{"id": "entrance", "kind": "accessible_entrance"},
			{"id": "exits", "kind": "exit_distance", "value": 30.0},
			{"id": "budget", "kind": "budget"},
		],
		"goals": [
			{"id": "lockers", "kind": "rooms", "type": "locker_room", "count": 1, "bonus": 10000.0},
			{"id": "thrifty", "kind": "budget", "share": 0.9, "bonus": 20000.0},
		],
	},
]
