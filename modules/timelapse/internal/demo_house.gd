extends RefCounted
## A two-storey 10 m x 8 m house as timelapse input, until the design room hands over real
## designs: pad footings, columns, beams, two slabs, walls with windows and doors, a roof,
## stairs and some fit-out. Same part shape as the building api adapter produces.

const W := 10.0
const D := 8.0
const H := 3.0
const T := 0.25


static func parts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pads: Array[String] = []
	var xs := [0.0, W / 2.0, W]
	var zs := [0.0, D]
	for i in xs.size():
		for j in zs.size():
			var x: float = xs[i]
			var z: float = zs[j]
			var pad := "pad_%d_%d" % [i, j]
			out.append(_part(pad, "pad", Vector3(x - 0.6, -0.8, z - 0.6), Vector3(1.2, 0.8, 1.2), []))
			pads.append(pad)
	var below: Dictionary = {}  # "i_j" -> id of what a column there rests on
	for i in xs.size():
		for j in zs.size():
			below["%d_%d" % [i, j]] = "pad_%d_%d" % [i, j]
	for level in 2:
		var y0 := level * H
		var cols: Array[String] = []
		for i in xs.size():
			for j in zs.size():
				var x: float = xs[i]
				var z: float = zs[j]
				var col := "col_L%d_%d_%d" % [level, i, j]
				out.append(_part(col, "column", Vector3(x - T / 2, y0, z - T / 2), Vector3(T, H - T, T),
						[below["%d_%d" % [i, j]]]))
				cols.append(col)
				below["%d_%d" % [i, j]] = col
		var beams: Array[String] = []
		for j in zs.size():
			for i in xs.size() - 1:
				var b := "beam_L%d_x%d_%d" % [level, i, j]
				var x0: float = xs[i]
				out.append(_part(b, "beam", Vector3(x0, y0 + H - T, float(zs[j]) - T / 2),
						Vector3(W / 2.0, T, T), ["col_L%d_%d_%d" % [level, i, j], "col_L%d_%d_%d" % [level, i + 1, j]]))
				beams.append(b)
		for i in xs.size():
			var b := "beam_L%d_z%d" % [level, i]
			out.append(_part(b, "beam", Vector3(float(xs[i]) - T / 2, y0 + H - T, 0.0), Vector3(T, T, D),
					["col_L%d_%d_0" % [level, i], "col_L%d_%d_1" % [level, i]]))
			beams.append(b)
		# Ground-floor slab on the ground, upper slab on the beams.
		if level == 0:
			out.append(_part("slab_L0", "slab", Vector3(0, 0, 0), Vector3(W, 0.2, D), pads))
		var top := "slab_L%d" % (level + 1) if level == 0 else "roof"
		if level == 0:
			out.append(_part(top, "slab", Vector3(0, y0 + H - 0.05, 0), Vector3(W, 0.2, D), beams))
		else:
			out.append(_part("roof", "roof", Vector3(-0.4, y0 + H, -0.4), Vector3(W + 0.8, 0.35, D + 0.8), beams))
		var slab := "slab_L%d" % level
		# Walls: long sides in two halves, short sides whole; the front gets a door at ground level.
		for j in zs.size():
			for i in xs.size() - 1:
				var wid := "wall_L%d_x%d_%d" % [level, i, j]
				out.append(_part(wid, "wall", Vector3(float(xs[i]), y0 + 0.2, float(zs[j]) - 0.1),
						Vector3(W / 2.0, H - 0.45, 0.2), [slab]))
				var kind := "door" if level == 0 and j == 0 and i == 0 else "window"
				var size := Vector3(1.0, 2.1, 0.22) if kind == "door" else Vector3(1.4, 1.2, 0.22)
				var y := y0 + 0.2 if kind == "door" else y0 + 1.0
				out.append(_part("%s_L%d_%d_%d" % [kind, level, i, j], kind,
						Vector3(float(xs[i]) + 1.8, y, float(zs[j]) - 0.11), size, [wid]))
		for i in [0, xs.size() - 1]:
			out.append(_part("wall_L%d_z%d" % [level, i], "wall", Vector3(float(xs[i]) - 0.1, y0 + 0.2, 0.0),
					Vector3(0.2, H - 0.45, D), [slab]))
		out.append(_part("fitout_L%d_kitchen" % level if level == 0 else "fitout_L%d_beds" % level, "fitout",
				Vector3(1.0, y0 + 0.2, 1.0), Vector3(3.0, 0.9, 0.7), [slab]))
	out.append(_part("stairs", "stairs", Vector3(W - 3.2, 0.2, D - 1.4), Vector3(3.0, H - 0.2, 1.0),
			["slab_L0", "slab_L1"]))
	return out


static func _part(id: String, kind: String, pos: Vector3, size: Vector3, supports: Array) -> Dictionary:
	return {"id": id, "kind": kind, "aabb": AABB(pos, size), "supported_by": supports.duplicate()}
