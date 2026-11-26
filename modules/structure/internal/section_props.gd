extends RefCounted
## Design strengths (StructureSections shape: axial kN, bending kN·m, shear kN, weight kN/m)
## worked out from a building catalog's raw section and material properties. Simple rules
## with the safety factors folded in; numbers to tune in playtesting, not a design code.
##
## Material strength is MPa (bending for timber, yield for steel, cylinder for concrete and
## masonry), E is GPa, density kg/m³. 1 MPa over 1 m² is 1000 kN.

const G := 9.81
## Timber: load-duration and material factors, and shear strength (MPa).
const TIMBER_FACTOR := 0.6
const TIMBER_SHEAR_MPA := 4.0
## Joisted floors and roofs: joists 47 mm wide at 400 mm centres, plus boards and ceiling.
const JOISTS_PER_M := 2.5
const JOIST_WIDTH := 0.047
const JOIST_FLOOR_EXTRA_KPA := 0.3
## A pitched roof with no section: rafters 47 x 150.
const RAFTER_DEPTH := 0.15
## Walls: slenderness allowance on axial strength, and racking (in-plane shear) MPa.
const WALL_SLENDERNESS := 0.6
const RACKING_MPA := {"masonry": 0.25, "concrete": 1.0}
## Timber frame walls, per metre (axial kN, racking kN, bending kN·m, weight kPa per m height).
const TIMBER_WALL := {"axial": 60.0, "shear": 6.0, "bending": 2.0, "weight": 0.5}
## Flexural tension (MPa) of a wall spanning along its length as a deep beam.
const WALL_BEAM_TENSION_MPA := {"masonry": 0.25, "concrete": 3.0, "timber": 1.0}


## A frame member (column, beam, brace, truss). length > 0 adds buckling for posts.
static func frame(sec: Dictionary, mat_id: String, mat: Dictionary, family: String, length: float) -> Dictionary:
	var f := float(mat.get("strength", 0.0)) * 1000.0
	var e := float(mat.get("e", 0.0)) * 1.0e6
	var density := float(mat.get("density", 0.0))
	var w := float(sec.get("w", 0.0))
	var d := float(sec.get("d", 0.0))
	var area := float(sec.get("area", w * d))
	var wy := float(sec.get("wy", w * d * d / 6.0))
	var out := {"material": mat_id, "axial": 0.0, "bending": 0.0, "shear": 0.0, "weight": 0.0}
	if str(sec.get("shape", "")) == "truss":
		var dens := 7850.0 if mat_id == "steel" else maxf(density, 1.0)
		var chord := float(sec.get("kg_m", 0.0)) / dens * 0.35
		var ft := f if mat_id == "steel" else f * TIMBER_FACTOR
		out.axial = chord * ft
		out.bending = chord * ft * d
		out.shear = chord * ft * 0.5
		out.weight = float(sec.get("kg_m", 0.0)) * G / 1000.0
		return out
	match mat_id:
		"steel":
			out.axial = area * f
			out.bending = wy * f
			out.shear = 0.35 * area * f
		"timber", "glulam":
			out.axial = area * f * 0.9 * TIMBER_FACTOR
			out.bending = wy * f * TIMBER_FACTOR
			out.shear = area * TIMBER_SHEAR_MPA * 1000.0 * TIMBER_FACTOR * 2.0 / 3.0
		"concrete":
			# Reinforced: squash load with bars, bending of a typically reinforced section.
			out.axial = 0.6 * f * area
			out.bending = 0.12 * f * w * d * d
			out.shear = 1.2 * 1000.0 * area
		_:
			out.axial = 0.4 * f * area
			out.bending = 0.1 * wy * f
			out.shear = 0.25 * 1000.0 * area
	if sec.has("kg_m"):
		out.weight = float(sec.kg_m) * G / 1000.0
	else:
		out.weight = area * density * G / 1000.0
	if family == "column" and length > 0.0 and e > 0.0:
		# Rankine: 1 / N = 1 / squash + 1 / Euler, pinned ends, about the weaker axis.
		var i_min := _i_min(sec, w, d)
		if i_min > 0.0:
			var euler := PI * PI * e * i_min / (length * length)
			out.axial = 1.0 / (1.0 / out.axial + 1.0 / euler)
	return out


static func _i_min(sec: Dictionary, w: float, d: float) -> float:
	match str(sec.get("shape", "")):
		"i":
			var r := w / d if d > 0.0 else 1.0
			return float(sec.get("iy", 0.0)) * minf(r * r * 0.35, 1.0)
		"chs":
			return float(sec.get("iy", 0.0))
	var a := minf(w, d)
	var b := maxf(w, d)
	return b * a * a * a / 12.0


## A floor or roof plate, per metre width. sec may be {} (pitched roof: rafters).
static func plate(sec: Dictionary, mat_id: String, mat: Dictionary) -> Dictionary:
	var f := float(mat.get("strength", 0.0)) * 1000.0
	var density := float(mat.get("density", 0.0))
	var d := float(sec.get("d", RAFTER_DEPTH))
	var out := {"material": mat_id, "axial": 1000.0, "bending": 0.0, "shear": 0.0, "weight": 0.0, "per_width": true}
	if mat_id == "concrete":
		out.bending = 0.04 * f * d * d
		out.shear = 0.6 * 1000.0 * d
		out.weight = d * density * G / 1000.0
		return out
	# Timber joists or rafters at centres.
	var area := JOISTS_PER_M * JOIST_WIDTH * d
	var ft := f * TIMBER_FACTOR
	out.bending = JOISTS_PER_M * JOIST_WIDTH * d * d / 6.0 * ft
	out.shear = area * TIMBER_SHEAR_MPA * 1000.0 * TIMBER_FACTOR * 2.0 / 3.0
	out.weight = area * density * G / 1000.0 + JOIST_FLOOR_EXTRA_KPA
	return out


## A load-bearing wall standing up, per metre of wall: axial, racking shear, own weight per
## metre of height.
static func wall(sec: Dictionary, mat_id: String, mat: Dictionary) -> Dictionary:
	if mat_id == "timber":
		var t := float(sec.get("d", 0.14)) / 0.14
		return {"material": mat_id, "axial": TIMBER_WALL.axial * t, "shear": TIMBER_WALL.shear,
				"bending": TIMBER_WALL.bending, "weight": TIMBER_WALL.weight, "per_width": true}
	var f := float(mat.get("strength", 0.0)) * 1000.0
	var d := float(sec.get("d", 0.2))
	var k := 0.45 if mat_id == "concrete" else 0.4
	return {"material": mat_id, "axial": k * f * d * WALL_SLENDERNESS,
			"shear": float(RACKING_MPA.get(mat_id, 0.25)) * 1000.0 * d,
			"bending": 0.1 * f * d * d * 0.1, "weight": d * float(mat.get("density", 0.0)) * G / 1000.0,
			"per_width": true}


## A wall spanning along its length between supports (and over openings) as a deep beam
## depth metres deep. No weight: the upright parts of the wall carry that.
static func wall_beam(sec: Dictionary, mat_id: String, depth: float) -> Dictionary:
	var d := float(sec.get("d", 0.2))
	var ft := float(WALL_BEAM_TENSION_MPA.get(mat_id, 0.25)) * 1000.0
	var shear_mpa := float(RACKING_MPA.get(mat_id, 0.1 if mat_id == "timber" else 0.25))
	return {"material": mat_id, "axial": 1.0e6, "bending": ft * d * depth * depth / 6.0,
			"shear": shear_mpa * 1000.0 * d * depth, "weight": 0.0}
