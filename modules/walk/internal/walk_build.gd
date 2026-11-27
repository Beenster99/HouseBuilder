extends Node3D
## Builds the building at full size for walk-inside (BSX WalkBuild, repurposed for the
## BuildingModel): solid floors with the stair and lift holes cut, walls in pieces round their
## doors and windows, doors that swing open as anyone comes near, glass in the windows, the
## stairs as steps you see and a ramp you walk up, lift shafts, columns, beams and roofs, the
## fittings as the asset library's models, and a lamp in every room. Drawn in the player's
## look (ArtStyle): the architectural model (white, ink edges from the camera pass, sun
## shadows) or realistic.
##
## Every piece you can aim at carries meta "walk" on its body: {kind ("part" | "room_floor" |
## "ground"), id, family, level}. Faces sharing a level, a material and a 16 m square are one
## mesh, as in the designer's view, and an edit redoes only what it touched.
##
## World space is the model's: metres, level n's floor at model.level_elevation(n).

const AssetLibrary := preload("res://modules/assets/api/asset_library.gd")
const WalkEdits := preload("res://modules/walk/internal/walk_edits.gd")

## The physics layer walk-inside uses (its own world, so any bit would do; BSX's).
const LAYER := 1 << 19
const CELL := 16.0
## How far a door swings open, and how near someone must be, m.
const DOOR_REACH := 1.8
const DOOR_SPEED := 3.0
## A lamp is lit only within this of the walker, m (a terminal has hundreds of rooms).
const LAMP_REACH := 28.0
## A floor under a room that no slab covers, m thick.
const ROOM_FLOOR := 0.05

var model: BuildingModel
## Built so far, for tests and the walker.
## Doors: id -> {hinge: Node3D, open: 0..1, centre: Vector3, sign: float}.
var doors: Dictionary = {}
## Room lamps: room id -> OmniLight3D.
var lamps: Dictionary = {}
## Stair ramps: part id -> true.
var ramps: Dictionary = {}

## entry id -> {level, fam, geo: {batch key: [verts, normals]}, body, nodes: [Node]}
var _recs: Dictionary = {}
var _batches: Dictionary = {}
var _dirty_batches: Dictionary = {}
var _dirty: Dictionary = {}
var _host_of: Dictionary = {}
var _hosted: Dictionary = {}
var _voids: Dictionary = {}
var _geo: Dictionary = {}
var _col := PackedVector3Array()
var _geo_level := 0
var _geo_cell := Vector2i.ZERO
var _mats: Dictionary = {}


func bind(m: BuildingModel) -> void:
	model = m
	name = "Building"
	model.entry_added.connect(refresh)
	model.entry_changed.connect(refresh)
	model.entry_removed.connect(refresh)
	model.loaded.connect(rebuild)
	model.levels_changed.connect(rebuild)
	Graphics.changed.connect(rebuild)
	rebuild()


func _exit_tree() -> void:
	if model == null:
		return
	for pair: Array in [[model.entry_added, refresh], [model.entry_changed, refresh], [model.entry_removed, refresh],
			[model.loaded, rebuild], [model.levels_changed, rebuild], [Graphics.changed, rebuild]]:
		var s: Signal = pair[0]
		if s.is_connected(pair[1]):
			s.disconnect(pair[1])


func _process(_delta: float) -> void:
	flush()


## Everything again (a load, a level change, the look changed).
func rebuild() -> void:
	for id: String in _recs.keys():
		_drop(id)
	for b: Dictionary in _batches.values():
		if b.mesh:
			(b.mesh as Node).queue_free()
	_batches.clear()
	_dirty_batches.clear()
	_recs.clear()
	_host_of.clear()
	_hosted.clear()
	_mats.clear()
	ArtStyle.clear_cache()
	for id: String in model.parts:
		_note_host(id)
		_dirty[id] = true
	for id: String in model.rooms:
		_dirty[id] = true
	flush()


func _note_host(id: String) -> void:
	var host := str(model.parts.get(id, {}).get("host", ""))
	var old := str(_host_of.get(id, ""))
	if old == host:
		return
	if old != "":
		(_hosted.get(old, {}) as Dictionary).erase(id)
		_dirty[old] = true
	_host_of.erase(id)
	if host != "":
		_host_of[id] = host
		if not _hosted.has(host):
			_hosted[host] = {}
		_hosted[host][id] = true


## An entry changed: it (and a wall with its openings, the floors a stair or lift passes
## through, the room floors a slab covers) is redone at the next flush.
func refresh(id: String) -> void:
	_dirty[id] = true
	var e := model.entry(id)
	_note_host(id)
	if str(e.get("host", "")) != "":
		_dirty[str(e.host)] = true
	for o: String in _hosted.get(id, {}):
		_dirty[o] = true
	var rec: Dictionary = _recs.get(id, {})
	var fam := str(rec.get("fam", ""))
	if not e.is_empty() and model.parts.has(id):
		fam = model.catalog.family_of(str(e.kind))
	if fam == "circulation" or fam == "slab":
		var lo := mini(int(rec.get("level", 99999)), int(e.get("level", 99999)))
		var hi := maxi(int(rec.get("top", -1)), int(e.get("top_level", e.get("level", -1))))
		for l in range(maxi(lo, 0), mini(hi + 2, model.level_count())):
			for pid in model.parts_on(l):
				if model.catalog.family_of(str(model.parts[pid].kind)) == "slab":
					_dirty[pid] = true
			for rid in model.rooms_on(l):
				_dirty[rid] = true


func flush() -> void:
	if _dirty.is_empty() and _dirty_batches.is_empty():
		return
	_voids.clear()
	for id: String in _dirty.keys():
		_drop(id)
		if model.has(id) and model.table_of(id) != "connections":
			_build(id)
	_dirty.clear()
	for key: String in _dirty_batches.keys():
		if _batches.has(key):
			_build_batch(key)
	_dirty_batches.clear()


func _drop(id: String) -> void:
	var rec: Dictionary = _recs.get(id, {})
	if rec.is_empty():
		return
	for key: String in rec.geo:
		if _batches.has(key):
			(_batches[key].ids as Dictionary).erase(id)
			_dirty_batches[key] = true
	for n: Variant in rec.nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	doors.erase(id)
	lamps.erase(id)
	ramps.erase(id)
	_recs.erase(id)


func _build(id: String) -> void:
	_geo = {}
	_col = PackedVector3Array()
	var room := model.rooms.has(id)
	var e := model.entry(id)
	_geo_level = int(e.level) if room else model.level_of(id)
	_geo_cell = _cell_of(e)
	var rec := {"level": _geo_level, "fam": "room" if room else model.catalog.family_of(str(e.kind)),
			"top": int(e.get("top_level", _geo_level)), "nodes": []}
	_recs[id] = rec
	if room:
		_room(id, rec)
	else:
		_part(id, rec)
	if not _col.is_empty():
		var body := StaticBody3D.new()
		body.name = "Body_" + id
		body.collision_layer = LAYER
		body.collision_mask = 0
		body.set_meta("walk", {"kind": "room_floor" if room else "part", "id": id, "family": rec.fam, "level": _geo_level})
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(_col)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		add_child(body)
		rec.nodes.append(body)
	rec["geo"] = _geo
	for key: String in _geo:
		(_batches[key].ids as Dictionary)[id] = true
		_dirty_batches[key] = true
	_geo = {}


func _cell_of(e: Dictionary) -> Vector2i:
	if e.has("host") and model.parts.has(str(e.host)):
		e = model.parts[str(e.host)]
	var p: Variant = e.get("at", e.get("a", null))
	if p == null:
		var o: Array = e.get("outline", [])
		p = o[0] if not o.is_empty() else [0.0, 0.0]
		return Vector2i(floori(float(p[0]) / CELL), floori(float(p[1]) / CELL))
	return Vector2i(floori(float(p[0]) / CELL), floori(float(p[2]) / CELL))


func _build_batch(key: String) -> void:
	var b: Dictionary = _batches[key]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for id: String in b.ids:
		var g: Array = _recs[id].geo[key]
		verts.append_array(g[0])
		norms.append_array(g[1])
	if verts.is_empty():
		if b.mesh:
			(b.mesh as Node).queue_free()
		_batches.erase(key)
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if not b.mesh:
		var mi := MeshInstance3D.new()
		mi.name = "Batch" + key.replace("|", "_")
		mi.material_override = b.mat
		if _see_through(b.mat):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		b.mesh = mi
	(b.mesh as MeshInstance3D).mesh = mesh


func batch_count() -> int:
	return _batches.size()


## The building parts and rooms built (tests).
func built_ids() -> PackedStringArray:
	return PackedStringArray(_recs.keys())


func node_of(id: String) -> Node:
	var rec: Dictionary = _recs.get(id, {})
	for n: Variant in rec.get("nodes", []):
		if is_instance_valid(n) and not n is StaticBody3D:
			return n
	return null


# Parts

func _part(id: String, rec: Dictionary) -> void:
	var e: Dictionary = model.parts[id]
	var cat := model.catalog
	var kind := str(e.kind)
	var spec := cat.kind(kind)
	var fam := cat.family_of(kind)
	var sec := cat.section(str(e.get("section", "")))
	var mat := ArtStyle.material(str(e.get("material", "")), fam)
	var floor_y := model.level_elevation(model.level_of(id))
	match cat.shape_of(kind):
		"point":
			var at := _v3(e.at) + Vector3(0, floor_y, 0)
			var rot := Basis(Vector3.UP, deg_to_rad(float(e.get("rot", 0.0))))
			if kind == "lift":
				var shaft := Vector3(float(e.get("w", spec.get("w", 2.0))), model.part_height(id), float(e.get("d", spec.get("d", 2.0))))
				_box(at + Vector3(0, shaft.y / 2.0, 0), shaft, rot, ArtStyle.material("glass", "opening"), true)
			elif fam == "fixture":
				_fixture(id, e, spec, at, rec)
			elif kind == "pile":
				var length := float(e.get("length", spec.get("length", 10.0)))
				var dia := float(sec.get("dia", 0.45))
				_box(at - Vector3(0, length / 2.0, 0), Vector3(dia, length, dia), rot, mat, false)
			elif str(sec.get("shape", "")) == "pad":
				var w := float(sec.get("w", 1.0))
				var d := float(sec.get("d", 0.5))
				_box(at - Vector3(0, d / 2.0, 0), Vector3(w, d, w), rot, mat, true)
			else:
				var h := model.part_height(id)
				var w := float(sec.get("w", 0.3))
				var d := float(sec.get("d", w))
				_box(at + Vector3(0, h / 2.0, 0), Vector3(w, h, d), rot, mat, true)
		"line":
			var a := _v3(e.a) + Vector3(0, floor_y, 0)
			var b := _v3(e.b) + Vector3(0, floor_y, 0)
			if fam == "wall":
				_wall(id, a, b, mat)
			elif kind == "stair":
				_stair(id, a, b, mat)
			else:
				var w := float(sec.get("w", 0.2))
				var d := float(sec.get("d", 0.3))
				_linear(a - Vector3(0, d / 2.0, 0), b - Vector3(0, d / 2.0, 0), w, d, mat, true)
		"area":
			var t := maxf(float(sec.get("d", 0.2)), 0.05)
			var y := floor_y + float(e.get("y", 0.0))
			var pieces: Array = [_outline(e.outline)]
			if fam == "slab" and absf(float(e.get("y", 0.0))) < 0.01:
				pieces = _cut_voids(pieces[0], _voids_on(model.level_of(id)))
			var pitch := float(e.get("pitch", spec.get("pitch", 0.0)))
			for poly: PackedVector2Array in pieces:
				_prism(poly, y - t, y, mat, true)
			if fam == "roof" and pitch > 0.0:
				_pitched(_outline(e.outline), y, pitch, mat)
		"opening":
			_opening(id, e, spec, rec)


func _voids_on(level: int) -> Array:
	if not _voids.has(level):
		_voids[level] = model.voids_on(level)
	return _voids[level]


## A fitting: the asset library's model (a plain box until it has one), solid to walk into.
func _fixture(id: String, e: Dictionary, spec: Dictionary, at: Vector3, rec: Dictionary) -> void:
	var size := WalkEdits.size_of(model, str(e.kind), e)
	var node := AssetLibrary.make_kind(str(e.kind), {"size": size, "family": "fixture"})
	node.name = "Part_" + id
	node.position = at
	node.rotation.y = deg_to_rad(float(e.get("rot", 0.0)))
	add_child(node)
	rec.nodes.append(node)
	var basis := Basis(Vector3.UP, node.rotation.y)
	_box_faces(at + Vector3(0, size.y / 2.0, 0), size, basis, _col)


## A door (a leaf that swings open as anyone comes near) or a window (glass you can't walk
## through). The wall's pieces leave the hole.
func _opening(id: String, e: Dictionary, spec: Dictionary, rec: Dictionary) -> void:
	var pts := model.points_of(id)
	if pts.size() != 2:
		return
	var h := float(e.get("h", spec.get("h", 2.0)))
	var w := pts[0].distance_to(pts[1])
	var glass := str(e.get("material", "")) == "glass" or str(e.kind).begins_with("window")
	if glass:
		var m := ArtStyle.material("glass", "opening")
		_linear(pts[0] + Vector3(0, h / 2.0, 0), pts[1] + Vector3(0, h / 2.0, 0), 0.04, h, m, true)
		return
	# A door: hinged at its a end, swinging away from whoever opens it.
	var hinge := Node3D.new()
	hinge.name = "Door_" + id
	hinge.position = pts[0]
	var along := (pts[1] - pts[0]).normalized()
	hinge.basis = Basis(Vector3.UP, -Vector2(along.x, along.z).angle())
	var leaf := MeshInstance3D.new()
	leaf.name = "Leaf"
	var bm := BoxMesh.new()
	bm.size = Vector3(w - 0.02, h - 0.02, 0.045)
	leaf.mesh = bm
	leaf.position = Vector3(w / 2.0, h / 2.0, 0)
	var door_mat := str(e.get("material", ""))
	leaf.material_override = ArtStyle.material(door_mat if door_mat != "" and door_mat != "glass" else "timber", "fixture")
	hinge.add_child(leaf)
	# The leaf is aimed at like any part (to remove it or retag it), but doesn't block you.
	var body := StaticBody3D.new()
	body.name = "DoorBody_" + id
	body.collision_layer = LAYER
	body.collision_mask = 0
	body.set_meta("walk", {"kind": "part", "id": id, "family": "opening", "level": model.level_of(id), "door": true})
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	cs.disabled = false
	body.add_child(cs)
	leaf.add_child(body)
	add_child(hinge)
	rec.nodes.append(hinge)
	doors[id] = {"hinge": hinge, "leaf_body": body, "open": 0.0, "centre": (pts[0] + pts[1]) / 2.0,
			"normal": Vector3(-along.z, 0, along.x), "basis": hinge.basis, "sign": 1.0}


## Doors swing open towards no one when anybody in `near` (feet positions) is close.
func update_doors(near: Array[Vector3], delta: float) -> void:
	for id: String in doors:
		var d: Dictionary = doors[id]
		var c: Vector3 = d.centre
		var want := 0.0
		for p in near:
			var flat := Vector3(p.x - c.x, 0, p.z - c.z)
			if flat.length() < DOOR_REACH and absf(p.y - c.y) < 1.5:
				want = 1.0
				if float(d.open) < 0.05:
					# Swing away from whoever walks up.
					d.sign = -1.0 if flat.dot(d.normal) > 0.0 else 1.0
				break
		d.open = move_toward(float(d.open), want, delta * DOOR_SPEED)
		var hinge: Node3D = d.hinge
		if is_instance_valid(hinge):
			hinge.basis = (d.basis as Basis) * Basis(Vector3.UP, float(d.sign) * float(d.open) * PI * 0.5)
			# A shut door stops you (it opens as you come up to it); an open one does not.
			(d.leaf_body as StaticBody3D).collision_layer = LAYER if float(d.open) < 0.5 else 0


func door_open(id: String) -> float:
	return float(doors.get(id, {}).get("open", 0.0))


## A wall in pieces round its openings: solid runs, and the pieces under and over each.
func _wall(id: String, a: Vector3, b: Vector3, mat: Material) -> void:
	var e: Dictionary = model.parts[id]
	var h := model.part_height(id)
	var t := float(model.catalog.section(str(e.get("section", ""))).get("d", 0.2))
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	if length < 0.01:
		return
	var holes: Array = []
	for oid: String in _hosted.get(id, {}):
		if not model.parts.has(oid):
			continue
		var o: Dictionary = model.parts[oid]
		var spec := model.catalog.kind(str(o.kind))
		var w := float(o.get("w", spec.get("w", 0.9)))
		var sill := float(o.get("sill", spec.get("sill", 0.0)))
		var oh := float(o.get("h", spec.get("h", 2.0)))
		holes.append([clampf(float(o.t) - w / 2.0, 0.0, length), clampf(float(o.t) + w / 2.0, 0.0, length), sill, sill + oh])
	holes.sort_custom(func(x: Array, z: Array) -> bool: return x[0] < z[0])
	var dir := (b - a) / length
	var up := Vector3.UP
	var cursor := 0.0
	for hole: Array in holes:
		if hole[0] > cursor:
			_linear(a + dir * cursor + up * h / 2.0, a + dir * hole[0] + up * h / 2.0, t, h, mat, true)
		var bottom: float = hole[2]
		var top: float = minf(hole[3], h)
		if bottom > 0.01:
			_linear(a + dir * hole[0] + up * bottom / 2.0, a + dir * hole[1] + up * bottom / 2.0, t, bottom, mat, true)
		if top < h - 0.01:
			_linear(a + dir * hole[0] + up * (top + h) / 2.0, a + dir * hole[1] + up * (top + h) / 2.0, t, h - top, mat, true)
		cursor = maxf(cursor, hole[1])
	if cursor < length:
		_linear(a + dir * cursor + up * h / 2.0, b + up * h / 2.0, t, h, mat, true)


## A flight of steps from a (foot) to b (head) up to the next floor: steps to see, a ramp
## to walk (BSX: "the stairs are a ramp up to the deck above").
func _stair(id: String, a: Vector3, b: Vector3, mat: Material) -> void:
	var rise := model.level_height(model.level_of(id))
	var w := model.stair_width(id)
	var steps := maxi(2, int(round(rise / 0.18)))
	for i in steps:
		var f0 := float(i) / steps
		var f1 := float(i + 1) / steps
		var hh := rise * f1
		_linear(a.lerp(b, f0) + Vector3(0, hh / 2.0, 0), a.lerp(b, f1) + Vector3(0, hh / 2.0, 0), w, hh, mat, false)
	var side := Vector3(b.z - a.z, 0, a.x - b.x).normalized() * w * 0.5
	var top := b + Vector3(0, rise, 0)
	# The ramp from the floor at the foot to the floor above at the head, and on past it a
	# little so you step off onto the landing.
	var run := (b - a).normalized() * 0.3
	var q: Array[Vector3] = [a - run * 0.0 + side, a - side, top + run - side, top + run + side]
	_col.append_array(PackedVector3Array([q[0], q[1], q[2], q[0], q[2], q[3]]))
	ramps[id] = true


## A pitched roof over an outline: a ridge along its longer side (gable ends).
func _pitched(poly: PackedVector2Array, y: float, pitch: float, mat: Material) -> void:
	if poly.size() < 3:
		return
	var box := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		box = box.expand(p)
	var along_x := box.size.x >= box.size.y
	var span := box.size.y if along_x else box.size.x
	var rise := span * 0.5 * tan(deg_to_rad(pitch))
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var x0 := box.position.x
	var x1 := box.end.x
	var z0 := box.position.y
	var z1 := box.end.y
	var top := y + rise
	if along_x:
		var zm := (z0 + z1) / 2.0
		var s1: Array[Vector3] = [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, top, zm), Vector3(x0, top, zm)]
		var s2: Array[Vector3] = [Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(x1, top, zm), Vector3(x0, top, zm)]
		_quad(verts, norms, s1, Vector3(0, 1, -rise / maxf(span * 0.5, 0.01)).normalized())
		_quad(verts, norms, s2, Vector3(0, 1, rise / maxf(span * 0.5, 0.01)).normalized())
		_tri(verts, norms, Vector3(x0, y, z0), Vector3(x0, y, z1), Vector3(x0, top, zm), Vector3.LEFT)
		_tri(verts, norms, Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x1, top, zm), Vector3.RIGHT)
	else:
		var xm := (x0 + x1) / 2.0
		var s1b: Array[Vector3] = [Vector3(x0, y, z0), Vector3(x0, y, z1), Vector3(xm, top, z1), Vector3(xm, top, z0)]
		var s2b: Array[Vector3] = [Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(xm, top, z1), Vector3(xm, top, z0)]
		_quad(verts, norms, s1b, Vector3(-rise / maxf(span * 0.5, 0.01), 1, 0).normalized())
		_quad(verts, norms, s2b, Vector3(rise / maxf(span * 0.5, 0.01), 1, 0).normalized())
		_tri(verts, norms, Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(xm, top, z0), Vector3.FORWARD)
		_tri(verts, norms, Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(xm, top, z1), Vector3.BACK)
	_add(mat, verts, norms)
	_col.append_array(verts)


# Rooms: a lamp under each ceiling, and a floor where no slab covers the room yet (so an
# unfinished design can still be walked).

func _room(id: String, rec: Dictionary) -> void:
	var e: Dictionary = model.rooms[id]
	var level := int(e.level)
	var poly := _outline(e.outline)
	if poly.size() < 3:
		return
	var y := model.level_elevation(level)
	var centre := Vector2.ZERO
	for v in poly:
		centre += v
	centre /= poly.size()
	if not _slab_under(level, centre):
		_prism(poly, y - ROOM_FLOOR, y, ArtStyle.material("plaster", "room"), true)
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp_" + id
	var area := BuildingModel.outline_area(e.outline)
	lamp.omni_range = clampf(sqrt(area) * 1.2, 4.0, 14.0)
	lamp.light_energy = 0.9 if ArtStyle.realistic() else 0.45
	lamp.light_color = Color(1.0, 0.96, 0.88)
	lamp.shadow_enabled = false
	lamp.position = Vector3(centre.x, y + model.level_height(level) - 0.35, centre.y)
	lamp.visible = false
	add_child(lamp)
	rec.nodes.append(lamp)
	lamps[id] = lamp


func _slab_under(level: int, p: Vector2) -> bool:
	for pid in model.parts_on(level):
		var e: Dictionary = model.parts[pid]
		if model.catalog.family_of(str(e.kind)) in ["slab", "foundation"] and e.has("outline") \
				and absf(float(e.get("y", 0.0))) < 0.05 and BuildingModel.outline_has_point(e.outline, p.x, p.y):
			return true
	return false


## Lights the lamps near the walker only.
func update_lamps(at: Vector3) -> void:
	for id: String in lamps:
		var l: OmniLight3D = lamps[id]
		if is_instance_valid(l):
			l.visible = l.position.distance_to(at) < LAMP_REACH


# Geometry (the designer view's batching, with a collision copy of each solid face)

static func _see_through(m: Material) -> bool:
	return m is BaseMaterial3D and (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED


func _target(mat: Material) -> Array:
	var key := "%d|%d|%d|%d" % [_geo_level, mat.get_instance_id(), _geo_cell.x, _geo_cell.y]
	if not _batches.has(key):
		_batches[key] = {"mat": mat, "mesh": null, "ids": {}}
	if not _geo.has(key):
		_geo[key] = [PackedVector3Array(), PackedVector3Array()]
	return _geo[key]


func _add(mat: Material, verts: PackedVector3Array, norms: PackedVector3Array) -> void:
	var t := _target(mat)
	var v: PackedVector3Array = t[0]
	var n: PackedVector3Array = t[1]
	v.append_array(verts)
	n.append_array(norms)
	t[0] = v
	t[1] = n


func _box(centre: Vector3, size: Vector3, basis: Basis, mat: Material, solid: bool) -> void:
	var verts := PackedVector3Array()
	var norms := _box_faces(centre, size, basis, verts)
	_add(mat, verts, norms)
	if solid:
		_col.append_array(verts)


static func _box_faces(centre: Vector3, size: Vector3, basis: Basis, verts: PackedVector3Array) -> PackedVector3Array:
	var h := size / 2.0
	var norms := PackedVector3Array()
	for axis in 3:
		for sgn: float in [-1.0, 1.0]:
			var nl := Vector3.ZERO
			nl[axis] = sgn
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			var w := Vector3.ZERO
			w[(axis + 2) % 3] = 1.0
			var corners: Array[Vector3] = []
			for q: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				corners.append(centre + basis * ((nl + u * q.x + w * q.y) * h))
			_quad(verts, norms, corners, (basis * nl).normalized())
	return norms


static func _quad(verts: PackedVector3Array, norms: PackedVector3Array, p: Array[Vector3], normal: Vector3) -> void:
	_tri(verts, norms, p[0], p[1], p[2], normal)
	_tri(verts, norms, p[0], p[2], p[3], normal)


static func _tri(verts: PackedVector3Array, norms: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var x := b
		b = c
		c = x
	verts.append(a)
	verts.append(b)
	verts.append(c)
	norms.append(normal)
	norms.append(normal)
	norms.append(normal)


func _linear(a: Vector3, b: Vector3, w: float, h: float, mat: Material, solid: bool) -> void:
	var d := b - a
	var plan := Vector2(d.x, d.z)
	if d.length() < 0.01:
		return
	var basis := Basis(Vector3.UP, -plan.angle())
	if absf(d.y) > 0.001:
		basis = basis * Basis(Vector3.BACK, atan2(d.y, plan.length()))
	_box((a + b) / 2.0, Vector3(d.length(), h, w), basis, mat, solid)


func _prism(poly: PackedVector2Array, bottom: float, top: float, mat: Material, solid: bool) -> void:
	if poly.size() < 3:
		return
	if Geometry2D.is_polygon_clockwise(poly):
		poly.reverse()
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		return
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for i in range(0, tris.size(), 3):
		var p0 := poly[tris[i]]
		var p1 := poly[tris[i + 1]]
		var p2 := poly[tris[i + 2]]
		_tri(verts, norms, Vector3(p0.x, top, p0.y), Vector3(p1.x, top, p1.y), Vector3(p2.x, top, p2.y), Vector3.UP)
		_tri(verts, norms, Vector3(p0.x, bottom, p0.y), Vector3(p1.x, bottom, p1.y), Vector3(p2.x, bottom, p2.y), Vector3.DOWN)
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var edge := q - p
		if edge.length() < 0.0001:
			continue
		var out := Vector2(edge.y, -edge.x).normalized()
		if Geometry2D.is_point_in_polygon((p + q) / 2.0 + out * 0.001, poly):
			out = -out
		var quad: Array[Vector3] = [Vector3(p.x, bottom, p.y), Vector3(q.x, bottom, q.y), Vector3(q.x, top, q.y), Vector3(p.x, top, p.y)]
		_quad(verts, norms, quad, Vector3(out.x, 0, out.y))
	_add(mat, verts, norms)
	if solid:
		_col.append_array(verts)


## A floor outline with its stair and lift holes taken out, as pieces with no holes in them.
static func _cut_voids(poly: PackedVector2Array, voids: Array) -> Array:
	var pieces: Array = [poly]
	for v: Dictionary in voids:
		var hole := _outline(v.outline)
		if hole.size() < 3:
			continue
		var cx := 0.0
		for p in hole:
			cx += p.x
		cx /= hole.size()
		var big := 10000.0
		var left := PackedVector2Array([Vector2(-big, -big), Vector2(cx, -big), Vector2(cx, big), Vector2(-big, big)])
		var right := PackedVector2Array([Vector2(cx, -big), Vector2(big, -big), Vector2(big, big), Vector2(cx, big)])
		var next: Array = []
		for piece: PackedVector2Array in pieces:
			for half: PackedVector2Array in [left, right]:
				for part: PackedVector2Array in Geometry2D.intersect_polygons(piece, half):
					for rest: PackedVector2Array in Geometry2D.clip_polygons(part, hole):
						next.append(rest)
		pieces = next
	return pieces


static func _v3(a: Variant) -> Vector3:
	if a is Vector3:
		return a
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


static func _outline(raw: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Variant in raw:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out
