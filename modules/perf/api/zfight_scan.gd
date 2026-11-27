class_name ZFightScan
extends RefCounted
## Finds z-fighting: visible surfaces that lie in the same plane, face the same way and
## overlap, so the depth buffer can't decide which to draw and they flicker as the camera
## moves. Works on the scene tree as built (headless too: it reads the meshes' triangles).
##
##   var fights := ZFightScan.scan(scene_root)
##   for f in fights: print(ZFightScan.describe(f))
##
## Each result: {a, b: who owns the two surfaces (an entry id from the "entry_id" meta on
## a parent, else the node path under root), area: m² of overlap, at: a point in it,
## normal}. Surfaces closer than PLANE_GAP count as one plane: at a camera distance of
## 50 m a 24-bit depth buffer can't separate much less than that. Fix one by moving or
## shrinking a surface (say, a floor finish 5 mm above the slab, or a wall stopping at the
## slab's face), not with render priority, which only works for transparent materials.
## Overlaps between surfaces of the same opaque material don't flicker (the same pixels
## win either way) and aren't reported; nor are those hidden inside an opaque box.

## Parallel surfaces nearer than this fight, m.
const PLANE_GAP := 0.002
## Normals this close count as the same direction (about 1.8 degrees).
const SAME_DIRECTION := 0.9995
## Overlaps smaller than this are ignored, m² (shared edges, slivers).
const MIN_AREA := 0.0004
const CELL := 2.0
const MAX_CELLS := 64.0
const SOLID_CELL := 4.0
## How far in front of a fight to look for a solid box hiding it, m.
const HIDDEN_PROBE := 0.01


## options: skip (owner substrings to leave out), ground_y (the ground's height, default 0:
## undersides at or below it are never seen and are left out).
static func scan(root: Node, options: Dictionary = {}) -> Array[Dictionary]:
	var solids := {}  # world -> {cell: [[inverse transform, local box]]}: boxes that hide what's inside
	var tris := _collect(root, options, solids)
	var buckets := {}
	for i in tris.size():
		var t: Dictionary = tris[i]
		var key := _plane_key(t.n, t.d, t.world)
		if not buckets.has(key):
			buckets[key] = []
		(buckets[key] as Array).append(i)
	var pairs := {}  # "a|b" -> result
	var seen := {}
	for key: Variant in buckets:
		# Planes near a bucket edge: also compare with the next bucket up.
		var k: Array = key
		var near := [key, [k[0], k[1] + 1, k[2]]]
		var list: Array = []
		for nk: Variant in near:
			if buckets.has(nk):
				list.append_array(buckets[nk])
		if list.size() < 2:
			continue
		_compare(tris, list, pairs, seen, solids)
	var out: Array[Dictionary] = []
	for p: String in pairs:
		out.append(pairs[p])
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x.area) > float(y.area))
	return out


static func describe(f: Dictionary) -> String:
	var at: Vector3 = f.at
	return "%s and %s overlap %.2f m² in one plane at (%.2f, %.2f, %.2f), facing %s" % [f.a, f.b, f.area,
			at.x, at.y, at.z, _dir(f.normal)]


## Triangles of every visible mesh under root, in world space: {n, d, p: PackedVector3Array, owner}.
static func _collect(root: Node, options: Dictionary, solids: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var skip: Array = options.get("skip", [])
	var ground_y := float(options.get("ground_y", 0.0))
	for node: Node in [root] + root.find_children("*", "GeometryInstance3D", true, false):
		if not node is GeometryInstance3D:
			continue
		var gi := node as GeometryInstance3D
		if not gi.is_visible_in_tree() or gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var owner := _owner_of(root, gi)
		# Meshes in different worlds (a minimap's SubViewport) never share a depth buffer.
		var world := gi.get_world_3d().get_instance_id() if gi.get_world_3d() else 0
		if _skipped(owner, skip):
			continue
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
			var mi := gi as MeshInstance3D
			var mesh := mi.mesh
			for s in mesh.get_surface_count():
				_add_faces(out, _surface_faces(mesh, s), gi.global_transform, owner, world, ground_y, _look_of(mi, s, false))
			if mesh.get_faces().size() == 36 and _opaque(mi):
				_add_solid(solids, gi.global_transform, mesh.get_aabb(), world)
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh:
			var mm := (gi as MultiMeshInstance3D).multimesh
			if mm.mesh == null:
				continue
			var count := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			for s in mm.mesh.get_surface_count():
				var faces := _surface_faces(mm.mesh, s)
				var look := _look_of(gi, s, mm.use_colors or mm.use_custom_data, mm.mesh)
				for i in count:
					_add_faces(out, faces, gi.global_transform * mm.get_instance_transform(i), "%s#%d" % [owner, i], world, ground_y, look)
	return out


static func _skipped(owner: String, skip: Array) -> bool:
	for s: String in skip:
		if owner.contains(s):
			return true
	return false


## One surface's triangles (lines and points have none), in the mesh's space.
static func _surface_faces(mesh: Mesh, s: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	if mesh is PrimitiveMesh or mesh is ArrayMesh:
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return out
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty():
			for i: int in idx:
				out.append(verts[i])
		else:
			out = verts
		return out
	return mesh.get_faces() if s == 0 else out


## What a surface looks like: two coplanar overlapping triangles with the same look draw
## the same pixels whichever wins, so they don't flicker (a forest's crowns of one mesh,
## a road network in one material). "" when it can differ from triangle to triangle
## (vertex or instance colours, no material to compare).
static func _look_of(gi: GeometryInstance3D, s: int, per_instance: bool, mesh: Mesh = null) -> String:
	if per_instance or gi.transparency > 0.0:
		return ""
	if mesh == null and gi is MeshInstance3D:
		mesh = (gi as MeshInstance3D).mesh
	if mesh == null or mesh.surface_get_arrays(s)[Mesh.ARRAY_COLOR] != null:
		return ""
	var mat: Material = gi.material_override
	if mat == null and gi is MeshInstance3D:
		mat = (gi as MeshInstance3D).get_active_material(s)
	if mat == null:
		mat = mesh.surface_get_material(s)
	if mat == null or (mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED):
		return ""
	return str(mat.get_instance_id())


static func _add_faces(out: Array[Dictionary], faces: PackedVector3Array, xf: Transform3D, owner: String, world: int, ground_y: float = 0.0, look: String = "") -> void:
	for i in range(0, faces.size() - 2, 3):
		var a := xf * faces[i]
		var b := xf * faces[i + 1]
		var c := xf * faces[i + 2]
		var cr := (b - a).cross(c - a)
		var len2 := cr.length_squared()
		if len2 < 1e-10:
			continue
		var n := cr / sqrt(len2)
		# Undersides at or below the ground are never seen (the camera stays above it).
		if n.y < -0.99 and a.y <= ground_y + PLANE_GAP:
			continue
		out.append({"n": n, "d": n.dot(a), "p": PackedVector3Array([a, b, c]), "owner": owner, "world": world, "look": look})


static func _plane_key(n: Vector3, d: float, world: int) -> Array:
	return [Vector3i(roundi(n.x * 50.0), roundi(n.y * 50.0), roundi(n.z * 50.0)), floori(d / (PLANE_GAP * 2.0)), world]


static func _compare(tris: Array[Dictionary], list: Array, pairs: Dictionary, seen: Dictionary, solids: Dictionary) -> void:
	var n: Vector3 = tris[list[0]].n
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := n.cross(u)
	# A grid over the plane so only triangles near each other are compared.
	var flat := {}
	var rects := {}
	var bigs: Array = []
	var grid := {}
	for i: int in list:
		var p: PackedVector3Array = tris[i].p
		var poly := PackedVector2Array([Vector2(p[0].dot(u), p[0].dot(v)), Vector2(p[1].dot(u), p[1].dot(v)),
				Vector2(p[2].dot(u), p[2].dot(v))])
		flat[i] = poly
		var r := Rect2(poly[0], Vector2.ZERO).expand(poly[1]).expand(poly[2])
		rects[i] = r
		if (r.size.x / CELL + 1.0) * (r.size.y / CELL + 1.0) > MAX_CELLS:
			bigs.append(i)  # a ground plane or a whole slab: checked against everything by box
			continue
		for gx in range(floori(r.position.x / CELL), floori(r.end.x / CELL) + 1):
			for gy in range(floori(r.position.y / CELL), floori(r.end.y / CELL) + 1):
				var g := Vector2i(gx, gy)
				if not grid.has(g):
					grid[g] = []
				(grid[g] as Array).append(i)
	var candidates: Array = []  # [i, j]
	for g: Vector2i in grid:
		var cell: Array = grid[g]
		for x in cell.size():
			for y in range(x + 1, cell.size()):
				candidates.append([cell[x], cell[y]])
	for big: int in bigs:
		for j: int in list:
			if j != big and (rects[big] as Rect2).intersects(rects[j]):
				candidates.append([big, j])
	for c: Array in candidates:
		var i: int = c[0]
		var j: int = c[1]
		var key := Vector2i(mini(i, j), maxi(i, j))
		if seen.has(key):
			continue
		seen[key] = true
		var ti: Dictionary = tris[i]
		var tj: Dictionary = tris[j]
		if (ti.n as Vector3).dot(tj.n) < SAME_DIRECTION or absf(float(ti.d) - float(tj.d)) > PLANE_GAP:
			continue
		if str(ti.look) != "" and ti.look == tj.look:
			continue
		var area := 0.0
		var centre := Vector2.ZERO
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(flat[i], flat[j]):
			var pa := _area(piece)
			area += pa
			centre += _centroid(piece) * pa
		if area < MIN_AREA:
			continue
		centre /= area
		var at := u * centre.x + v * centre.y + (ti.n as Vector3) * float(ti.d)
		# Inside another solid (two walls overlapping at a corner, the cut faces of chunks)
		# nobody sees it.
		if _hidden(solids, int(ti.world), at + (ti.n as Vector3) * HIDDEN_PROBE):
			continue
		var oa: String = ti.owner
		var ob: String = tj.owner
		var pk := "%s|%s" % [mini_s(oa, ob), maxi_s(oa, ob)]
		if not pairs.has(pk):
			pairs[pk] = {"a": mini_s(oa, ob), "b": maxi_s(oa, ob), "area": 0.0, "at": at, "normal": ti.n}
		pairs[pk].area = float(pairs[pk].area) + area


## Only opaque boxes hide what's inside them (a see-through room volume doesn't).
static func _opaque(mi: MeshInstance3D) -> bool:
	if mi.transparency > 0.0:
		return false
	var mat: Material = mi.material_override
	if mat == null and mi.mesh.get_surface_count() > 0:
		mat = mi.get_active_material(0)
	if mat is BaseMaterial3D:
		return (mat as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
	return mat == null or mat is ShaderMaterial


static func _add_solid(solids: Dictionary, xf: Transform3D, box: AABB, world: int) -> void:
	if not solids.has(world):
		solids[world] = {}
	var cells: Dictionary = solids[world]
	var wb := xf * box
	var entry := [xf.affine_inverse(), box.grow(-0.001)]
	for x in range(floori(wb.position.x / SOLID_CELL), floori(wb.end.x / SOLID_CELL) + 1):
		for y in range(floori(wb.position.y / SOLID_CELL), floori(wb.end.y / SOLID_CELL) + 1):
			for z in range(floori(wb.position.z / SOLID_CELL), floori(wb.end.z / SOLID_CELL) + 1):
				var c := Vector3i(x, y, z)
				if not cells.has(c):
					cells[c] = []
				(cells[c] as Array).append(entry)


static func _hidden(solids: Dictionary, world: int, p: Vector3) -> bool:
	if not solids.has(world):
		return false
	var c := Vector3i(floori(p.x / SOLID_CELL), floori(p.y / SOLID_CELL), floori(p.z / SOLID_CELL))
	for entry: Array in (solids[world] as Dictionary).get(c, []):
		if (entry[1] as AABB).has_point((entry[0] as Transform3D) * p):
			return true
	return false


static func mini_s(a: String, b: String) -> String:
	return a if a < b else b


static func maxi_s(a: String, b: String) -> String:
	return b if a < b else a


static func _area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		s += poly[i].cross(poly[(i + 1) % poly.size()])
	return absf(s) * 0.5


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / maxf(1.0, poly.size())


static func _owner_of(root: Node, n: Node) -> String:
	var at := n
	while at and at != root.get_parent():
		if at.has_meta("entry_id"):
			return str(at.get_meta("entry_id"))
		at = at.get_parent()
	return str(root.get_path_to(n))


static func _dir(n: Vector3) -> String:
	var a := n.abs()
	if a.y >= a.x and a.y >= a.z:
		return "up" if n.y > 0 else "down"
	if a.x >= a.z:
		return "+x" if n.x > 0 else "-x"
	return "+z" if n.z > 0 else "-z"
