extends RefCounted
## A small 3D model of a BuildingModel (one module, or one object) for previews and the
## placing ghost: floors as plates, walls as boxes with their door and window holes, and
## every fitting, door and window drawn by the asset library in the current look.

const SLAB := 0.15
const WALL_T := 0.2


## The model of `m`'s level 0, centred on plan point `centre` (so the node's origin is the
## module's centre on the floor). cut > 0 draws walls only that high (a cutaway, so the
## fittings inside show), without the doors and windows themselves.
static func build(m: BuildingModel, centre: Vector3 = Vector3.ZERO, cut: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "KitModel"
	var cat := m.catalog
	var walls: Dictionary = {}
	for pid: String in m.parts:
		var e: Dictionary = m.parts[pid]
		if e.has("host"):
			(walls.get_or_add(str(e.host), []) as Array).append(e)
	for rid: String in m.rooms:
		root.add_child(_plate(m.rooms[rid].outline, 0.02, "", "slab"))
	for pid: String in BuildingModel.sort_ids(m.parts.keys()):
		var e: Dictionary = m.parts[pid]
		var kind := str(e.kind)
		var fam := cat.family_of(kind)
		if e.has("host"):
			continue
		if e.has("outline"):
			if fam != "roof":
				root.add_child(_plate(e.outline, float(e.get("y", 0.0)), str(e.get("material", "")), fam))
		elif e.has("a") and e.has("b"):
			var h := float(e.get("height", m.level_height(int(e.get("level", 0)))))
			if cut > 0.0:
				h = minf(h, cut)
			if fam == "wall":
				var t := float(cat.section(str(e.get("section", ""))).get("d", WALL_T))
				_wall(root, m, _v3(e.a), _v3(e.b), h, t, walls.get(pid, []), str(e.get("material", "")), cut <= 0.0)
			elif fam == "beam":
				var a := _v3(e.a)
				var b := _v3(e.b)
				root.add_child(_bar(a, b, 0.2, 0.3, a.y - 0.15, str(e.get("material", "")), fam))
		elif e.has("at"):
			var at := _v3(e.at)
			var node: Node3D
			if fam == "column":
				var h := float(e.get("height", m.level_height(0)))
				node = AssetLibrary.make_kind(kind, {"size": Vector3(0.3, h, 0.3), "family": fam})
				if AssetLibrary.id_for_kind(kind) == "":
					node.position.y = 0.0
			else:
				var spec := cat.kind(kind)
				node = AssetLibrary.make_kind(kind, {"size": Vector3(float(spec.get("w", 0.6)), float(spec.get("h", 0.8)), float(spec.get("d", 0.6))), "family": fam})
			node.position += Vector3(at.x, at.y, at.z)
			node.rotation.y = deg_to_rad(float(e.get("rot", 0.0)))
			root.add_child(node)
	for c in root.get_children():
		(c as Node3D).position -= Vector3(centre.x, 0, centre.z)
	return root


## One catalog kind on its own (an object preview): the asset, or a box of its size.
static func object(cat: BuildingCatalog, kind: String) -> Node3D:
	var spec := cat.kind(kind)
	var size := Vector3(float(spec.get("w", 0.6)), float(spec.get("h", 0.8)), float(spec.get("d", 0.6)))
	if str(spec.get("shape", "")) == "opening":
		size.z = 0.2
	if size.y <= 0.0:
		size.y = 1.0
	return AssetLibrary.make_kind(kind, {"size": size, "family": str(spec.get("family", ""))})


static func _wall(root: Node3D, m: BuildingModel, a: Vector3, b: Vector3, h: float, t: float, openings: Array, mat: String, fill := true) -> void:
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	if length < 0.01:
		return
	var cat := m.catalog
	var holes: Array = []
	for o: Dictionary in openings:
		var spec := cat.kind(str(o.kind))
		var w := float(o.get("w", spec.get("w", 0.9)))
		var oh := float(o.get("h", spec.get("h", 2.0)))
		var sill := float(o.get("sill", spec.get("sill", 0.0)))
		if sill >= h:
			continue
		holes.append([float(o.t) - w / 2.0, float(o.t) + w / 2.0, sill, minf(sill + oh, h), o])
	holes.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var dir := (b - a) / length
	var at := 0.0
	for hole: Array in holes:
		var s := clampf(hole[0], 0.0, length)
		var e := clampf(hole[1], 0.0, length)
		if s > at:
			root.add_child(_bar(a + dir * at, a + dir * s, t, h, a.y, mat, "wall"))
		if float(hole[2]) > 0.0:
			root.add_child(_bar(a + dir * s, a + dir * e, t, float(hole[2]), a.y, mat, "wall"))
		if float(hole[3]) < h:
			var top := _bar(a + dir * s, a + dir * e, t, h - float(hole[3]), a.y + float(hole[3]), mat, "wall")
			root.add_child(top)
		if fill:
			var o: Dictionary = hole[4]
			var node := object(cat, str(o.kind))
			var mid := a + dir * float(o.t)
			node.position = Vector3(mid.x, a.y + float(hole[2]), mid.z)
			node.rotation.y = atan2(-dir.z, dir.x)
			root.add_child(node)
		at = maxf(at, e)
	if at < length:
		root.add_child(_bar(a + dir * at, b, t, h, a.y, mat, "wall"))


## A box from a to b (plan), `thick` across, `tall` high, its foot at y0.
static func _bar(a: Vector3, b: Vector3, thick: float, tall: float, y0: float, mat: String, fam: String) -> MeshInstance3D:
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(maxf(length, 0.01), maxf(tall, 0.01), thick)
	mi.mesh = box
	mi.material_override = ArtStyle.material(mat, fam)
	mi.position = Vector3((a.x + b.x) / 2.0, y0 + tall / 2.0, (a.z + b.z) / 2.0)
	mi.rotation.y = atan2(-(b.z - a.z), b.x - a.x)
	return mi


static func _plate(outline: Variant, y: float, mat: String, fam: String) -> MeshInstance3D:
	var pts := PackedVector2Array()
	for p: Variant in outline:
		pts.append(Vector2(float(p[0]), float(p[1])) if p is Array else p as Vector2)
	var tris := Geometry2D.triangulate_polygon(pts)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Top face, then the edge band, so the plate reads as a slab.
	# Both windings: outlines may run either way round.
	for i in range(0, tris.size(), 3):
		for k: int in [0, 2, 1, 0, 1, 2]:
			var p := pts[tris[i + k]]
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x, y, p.y))
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		var n := Vector3(q.y - p.y, 0, -(q.x - p.x)).normalized()
		for v: Vector3 in [Vector3(p.x, y, p.y), Vector3(q.x, y, q.y), Vector3(q.x, y - SLAB, q.y),
				Vector3(p.x, y, p.y), Vector3(q.x, y - SLAB, q.y), Vector3(p.x, y - SLAB, p.y),
				Vector3(p.x, y, p.y), Vector3(q.x, y - SLAB, q.y), Vector3(q.x, y, q.y),
				Vector3(p.x, y, p.y), Vector3(p.x, y - SLAB, p.y), Vector3(q.x, y - SLAB, q.y)]:
			st.set_normal(n)
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = ArtStyle.material(mat, fam)
	return mi


static func _v3(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return a if a is Vector3 else Vector3.ZERO
