class_name StructureLoads
extends RefCounted
## Characteristic (unfactored) loads the building adapter applies, in kPa (kN/m²).
## Scenarios multiply these by their factors (see StructureScenario).

const CASES: PackedStringArray = ["dead", "live", "snow"]

## Imposed floor load by room type. Unknown types use DEFAULT_LIVE_KPA.
const LIVE_KPA := {
	"bedroom": 1.5, "bathroom": 1.5, "living": 1.5, "kitchen": 1.5, "dining": 1.5,
	"hallway": 1.5, "landing": 1.5, "residential": 1.5,
	"garage": 2.5, "office": 2.5, "ward": 2.0, "custody_cell": 2.0, "front_desk": 3.0,
	"classroom": 3.0, "corridor": 3.0, "stairs": 3.0, "lobby": 4.0,
	"hall": 5.0, "assembly": 5.0, "gym": 5.0, "terminal": 5.0, "gate": 4.0,
	"storage": 5.0, "plant": 7.5, "vehicle_bay": 5.0,
	"roof": 0.6,
}
const DEFAULT_LIVE_KPA := 2.5

## Finishes, screed, services and partitions on a floor, on top of the slab's own weight.
const FLOOR_FINISHES_KPA := 1.0
## Roof coverings (tiles, battens, membrane, insulation).
const ROOF_COVERING_KPA := 0.75
## Ground snow load on a roof.
const SNOW_KPA := 0.6


static func live_kpa(room_type: String) -> float:
	return LIVE_KPA.get(room_type, DEFAULT_LIVE_KPA)
