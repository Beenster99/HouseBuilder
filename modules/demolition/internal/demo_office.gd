extends RefCounted
## A five-storey concrete-frame office, 15 m x 10 m, as demolition input until real designs
## arrive: pad footings, a 4 x 3 grid of columns, beams both ways and a slab per bay on every
## floor, plus two protected neighbours either side.

const BAY := 5.0
const STOREY := 3.5
const LEVELS := 5
const COL := 0.4
const BEAM := 0.45
const SLAB := 0.2


static func parts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx := 4
	var nz := 3
	var below: Dictionary = {}
	for i in nx:
		for k in nz:
			var id := "pad_%d_%d" % [i, k]
			out.append(_p(id, "foundation", Vector3(i * BAY - 0.7, -0.6, k * BAY - 0.7), Vector3(1.4, 0.6, 1.4), []))
			below["%d_%d" % [i, k]] = id
	for level in LEVELS:
		var y0 := level * STOREY
		var top := y0 + STOREY
		for i in nx:
			for k in nz:
				var id := "col_%d_%d_%d" % [level, i, k]
				out.append(_p(id, "column", Vector3(i * BAY - COL / 2, y0, k * BAY - COL / 2),
						Vector3(COL, STOREY - BEAM, COL), [below["%d_%d" % [i, k]]]))
		# Beams sit on the column tops; the next storey's columns stand on the beam joints.
		for k in nz:
			for i in nx - 1:
				out.append(_p("bx_%d_%d_%d" % [level, i, k], "beam",
						Vector3(i * BAY, top - BEAM, k * BAY - BEAM / 2), Vector3(BAY, BEAM, BEAM),
						["col_%d_%d_%d" % [level, i, k], "col_%d_%d_%d" % [level, i + 1, k]]))
		for i in nx:
			for k in nz - 1:
				out.append(_p("bz_%d_%d_%d" % [level, i, k], "beam",
						Vector3(i * BAY - BEAM / 2, top - BEAM, k * BAY), Vector3(BEAM, BEAM, BAY),
						["col_%d_%d_%d" % [level, i, k], "col_%d_%d_%d" % [level, i, k + 1]]))
		for i in nx - 1:
			for k in nz - 1:
				out.append(_p("slab_%d_%d_%d" % [level, i, k], "roof" if level == LEVELS - 1 else "slab",
						Vector3(i * BAY + BEAM / 2, top, k * BAY + BEAM / 2), Vector3(BAY - BEAM, SLAB, BAY - BEAM),
						["bx_%d_%d_%d" % [level, i, k], "bx_%d_%d_%d" % [level, i, k + 1],
						"bz_%d_%d_%d" % [level, i, k], "bz_%d_%d_%d" % [level, i + 1, k]]))
		for i in nx:
			for k in nz:
				below["%d_%d" % [i, k]] = "col_%d_%d_%d" % [level, i, k]
	return out


## Protected buildings next door (world boxes).
static func neighbours() -> Array:
	return [AABB(Vector3(-15.0, 0.0, -1.0), Vector3(8.0, 12.0, 12.0)),
			AABB(Vector3(23.0, 0.0, -3.0), Vector3(9.0, 9.0, 9.0))]


static func _p(id: String, family: String, pos: Vector3, size: Vector3, supports: Array) -> Dictionary:
	return {"id": id, "kind": family, "family": family, "material": "concrete",
			"aabb": AABB(pos, size), "supported_by": supports.duplicate(), "cost": 0.0, "level": 0}
