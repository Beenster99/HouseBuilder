class_name StructureSections
extends RefCounted
## Design strengths of the structural sections and foundations the solver knows, in kN and
## kN·m (SI, simplified design values with safety factors built in). Members name a section
## by id ("steel.ub_305x165x40"). Sections marked per_width (walls, slabs) give values per
## metre of member width, and the member's width scales them.
##
## Numbers are plausible game values for playtesting, not a design code.

## axial: compression or tension capacity (kN, includes buckling for a storey-high post).
## bending: moment capacity (kN·m). shear: shear capacity (kN; for walls, in-plane racking).
## weight: self weight (kN per metre of length, per metre of width when per_width).
const SECTIONS := {
	# Timber (C24 softwood, GL24 glulam)
	"timber.joist_47x200": {"material": "timber", "axial": 120.0, "bending": 6.5, "shear": 25.0, "weight": 0.045},
	"timber.beam_75x225": {"material": "timber", "axial": 220.0, "bending": 12.0, "shear": 40.0, "weight": 0.08},
	"timber.glulam_115x360": {"material": "timber", "axial": 600.0, "bending": 45.0, "shear": 90.0, "weight": 0.2},
	"timber.rafter_47x150": {"material": "timber", "axial": 90.0, "bending": 4.0, "shear": 18.0, "weight": 0.035},
	"timber.post_100x100": {"material": "timber", "axial": 150.0, "bending": 3.0, "shear": 20.0, "weight": 0.05},
	"timber.post_150x150": {"material": "timber", "axial": 350.0, "bending": 9.0, "shear": 40.0, "weight": 0.11},
	"timber.brace_100x50": {"material": "timber", "axial": 60.0, "bending": 1.0, "shear": 10.0, "weight": 0.025},
	"timber.stud_wall": {"material": "timber", "axial": 60.0, "bending": 2.0, "shear": 6.0, "weight": 0.4, "per_width": true},
	# Steel (S355)
	"steel.ub_203x133x25": {"material": "steel", "axial": 600.0, "bending": 90.0, "shear": 250.0, "weight": 0.25},
	"steel.ub_305x165x40": {"material": "steel", "axial": 1000.0, "bending": 210.0, "shear": 450.0, "weight": 0.4},
	"steel.ub_457x191x67": {"material": "steel", "axial": 1700.0, "bending": 520.0, "shear": 800.0, "weight": 0.66},
	"steel.uc_203x203x46": {"material": "steel", "axial": 1500.0, "bending": 175.0, "shear": 350.0, "weight": 0.46},
	"steel.uc_254x254x73": {"material": "steel", "axial": 2600.0, "bending": 340.0, "shear": 560.0, "weight": 0.72},
	"steel.chs_114x5": {"material": "steel", "axial": 450.0, "bending": 15.0, "shear": 100.0, "weight": 0.13},
	"steel.angle_100x100x8": {"material": "steel", "axial": 200.0, "bending": 5.0, "shear": 80.0, "weight": 0.12},
	# Reinforced concrete (C30)
	"concrete.column_300x300": {"material": "concrete", "axial": 1800.0, "bending": 120.0, "shear": 150.0, "weight": 2.25},
	"concrete.column_450x450": {"material": "concrete", "axial": 4000.0, "bending": 350.0, "shear": 330.0, "weight": 5.1},
	"concrete.beam_300x500": {"material": "concrete", "axial": 2000.0, "bending": 250.0, "shear": 220.0, "weight": 3.75},
	"concrete.slab_200": {"material": "concrete", "axial": 1000.0, "bending": 45.0, "shear": 90.0, "weight": 5.0, "per_width": true},
	"concrete.wall_200": {"material": "concrete", "axial": 1500.0, "bending": 30.0, "shear": 150.0, "weight": 5.0, "per_width": true},
	# Masonry
	"masonry.wall_100": {"material": "masonry", "axial": 180.0, "bending": 1.5, "shear": 12.0, "weight": 2.2, "per_width": true},
	"masonry.wall_cavity_300": {"material": "masonry", "axial": 300.0, "bending": 3.0, "shear": 20.0, "weight": 4.0, "per_width": true},
	"masonry.lintel_150x215": {"material": "masonry", "axial": 100.0, "bending": 6.0, "shear": 25.0, "weight": 0.6},
}

## Safe bearing pressure of the ground (kPa), by soil type.
const SOIL_BEARING := {
	"rock": 1000.0,
	"gravel": 300.0,
	"sand": 200.0,
	"clay": 150.0,
	"soft_clay": 75.0,
	"made_ground": 50.0,
}

## Width of a strip footing (m) and capacity of one pile (kN, independent of the soil).
const STRIP_WIDTH := 0.6
const PILE_CAPACITY := 600.0


static func has(section_id: String) -> bool:
	return SECTIONS.has(section_id)


## The section's numbers, or {} if unknown.
static func get_section(section_id: String) -> Dictionary:
	return SECTIONS.get(section_id, {})


static func ids() -> PackedStringArray:
	var out := PackedStringArray(SECTIONS.keys())
	out.sort()
	return out


## Bearing capacity (kN) of a foundation. kind: "pad" or "raft" (size = plan area m²),
## "strip" (size = length m), "pile" (size = number of piles). Unknown soil counts as clay.
static func foundation_capacity(kind: String, size: float, soil: String = "clay") -> float:
	var kpa: float = SOIL_BEARING.get(soil, SOIL_BEARING["clay"])
	match kind:
		"pad", "raft":
			return size * kpa
		"strip":
			return size * STRIP_WIDTH * kpa
		"pile":
			return size * PILE_CAPACITY
	return 0.0
