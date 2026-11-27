extends Node3D
## Draws a BuildingModel. Each entry's faces are worked out when it changes and kept; faces
## that share a level and a material are drawn together as one mesh (a batch), so a big
## building is a few dozen draw calls, not one per box. Edits only redo the entries they
## touch (a wall and its openings; the floors a stair or lift passes through) and the batches
## those sit in, once a frame. Levels above the one being worked on are hidden so plans read
## clearly. tint(id, colour) highlights selections and locks.

const ROOM_ALPHA := 0.38
const DEFAULT_COLOUR := Color(0.85, 0.85, 0.85)
const GLASS := Color(0.55, 0.78, 0.92, 0.45)
const DOOR := Color(0.5, 0.34, 0.2)

var model: BuildingModel
var level := 0
var show_rooms := true
## The plan's cut: in the 2D plan, walls on the working level are drawn only up to this
## height, as an architect's plan cuts them, so doors and windows show. INF in 3D.
var cut := INF
## entry id -> {level, room: bool, fam, geo: {batch key: [verts, normals]}, label: Node3D|null}
var _recs: Dictionary = {}
var _tints: Dictionary = {}  # entry id -> Color
var _mats: Dictionary = {}
## batch key "level|r or p|material id" -> {mat, mesh: MeshInstance3D|null, ids: {id: true}}
var _batches: Dictionary = {}
var _dirty_batches: Dictionary = {}
var _dirty: Dictionary = {}  # entry ids to redo at the next flush
var _hosted: Dictionary = {}  # wall id -> {opening id: true}
var _host_of: Dictionary = {}  # opening id -> wall id
var _slabs: Dictionary = {}  # level -> {slab id: true}
var _voids: Dictionary = {}  # level -> voids_on(level), for one flush
# The entry being built: batch key -> [verts, normals].
var _geo: Dictionary = {}
var _geo_level := 0
## How far from the camera (world m) library models keep their detail before a plain box
## stands in; a scaled-down copy (the holotable) sets it in its own units.
var lod_distance := 60.0
## Parts drawn with their library model (else a box until their turn), and those waiting.
var _model_ok: Dictionary = {}
var _model_wait: Dictionary = {}
const MODEL_BUDGET_US := 3000
## How walls meet at corners and tees, and which walls each one's ends touch (redrawn with it).
var _joins: WallJoins
var _wall_nb: Dictionary = {}
## Pitched roof -> the roofs on its level when last drawn (they join up, so redraw together).
var _roof_nb: Dictionary = {}
## A model node the entry being built adds (a library asset), or null.
var _geo_node: Node3D = null
var _geo_room := false
var _geo_cell := Vector2i.ZERO
## Batches are split into squares this size, m, so an edit remakes only a small mesh.
const CELL := 16.0
## Room labels keep their size on screen (sharp at any zoom) and fade with it; false draws
## them at a size in the world (the holotable's model, the small views).
var labels_fixed := true
## How see-through the building is drawn (0 solid): the ghost look while a 3D layer such as
## the stress diagram is on, so what's inside reads through the walls and floors.
var ghost := 0.0
## The ghost look's see-through amount.
const GHOST := 0.8
## How far parts that would share a face with another (a beam's top with a wall's, a pad's
## with a slab's, a column's ends) are set back so the two don't flicker (z-fight), m.
const INSET := 0.005
## A room's label fades in as the room grows from LABEL_FADE to twice that many pixels
## across on screen.
const LABEL_FADE := 45.0
var _fade_key := Vector4.INF
var _fade_count := -1


func bind(m: BuildingModel) -> void:
	model = m
	_joins = WallJoins.new(m)
	model.entry_added.connect(refresh)
	model.entry_changed.connect(refresh)
	model.entry_removed.connect(refresh)
	model.loaded.connect(rebuild)
	model.levels_changed.connect(rebuild)
	Graphics.changed.connect(rebuild)
	rebuild()


func _process(_delta: float) -> void:
	_upgrade_models()
	flush()
	if labels_fixed:
		fade_labels(get_viewport().get_camera_3d())


## Room labels fade out as the view zooms out: a room smaller than LABEL_FADE px across on
## screen loses its label, so a big plan seen whole isn't buried in text.
func fade_labels(cam: Camera3D) -> void:
	if cam == null:
		return
	var key := Vector4(cam.size if cam.projection == Camera3D.PROJECTION_ORTHOGONAL else cam.fov,
			cam.global_position.x, cam.global_position.y, cam.global_position.z)
	if key.is_equal_approx(_fade_key) and _fade_count == _recs.size():
		return
	_fade_key = key
	_fade_count = _recs.size()
	var vh := float(get_viewport().get_visible_rect().size.y)
	for r: Dictionary in _recs.values():
		if r.label == null or not _visible(int(r.level), true):
			continue
		var l := r.label as Label3D
		var a := fade_alpha(cam, vh, l.global_position, float(l.get_meta("span", 4.0)))
		l.visible = a > 0.01
		l.modulate.a = a
		l.outline_modulate.a = 0.85 * a


## How much a label for something `span` m across at `at` shows (0..1) through `cam` on a
## view `vh` px high: none under LABEL_FADE px across on screen, all from twice that.
static func fade_alpha(cam: Camera3D, vh: float, at: Vector3, span: float) -> float:
	if vh < 1.0:
		return 1.0
	var per_px := 0.0
	if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		per_px = cam.size / vh
	else:
		per_px = 2.0 * tan(deg_to_rad(cam.fov) * 0.5) / vh * maxf(cam.global_position.distance_to(at), 0.1)
	var px := span / maxf(per_px, 0.00001)
	return clampf((px - LABEL_FADE) / LABEL_FADE, 0.0, 1.0)


## Every entry again (a load, a new level, the look or the plan cut changed).
func rebuild() -> void:
	for r: Dictionary in _recs.values():
		if r.label:
			(r.label as Node).queue_free()
		if r.get("node"):
			(r.node as Node).queue_free()
	for b: Dictionary in _batches.values():
		if b.mesh:
			(b.mesh as Node).queue_free()
	_recs.clear()
	_batches.clear()
	_dirty_batches.clear()
	_hosted.clear()
	_host_of.clear()
	_slabs.clear()
	_dirty.clear()
	for id: String in model.parts:
		var host := str(model.parts[id].get("host", ""))
		if host != "":
			_host_of[id] = host
			if not _hosted.has(host):
				_hosted[host] = {}
			_hosted[host][id] = true
	for id: String in model.parts:
		_dirty[id] = true
	for id: String in model.rooms:
		_dirty[id] = true
	flush()


## Marks an entry to redraw (and, for a wall or opening, the wall with its openings; for a
## stair or lift, the floors it passes through). The work happens at the next flush().
func refresh(id: String) -> void:
	_dirty[id] = true
	# A wall's neighbours join differently when it moves, comes or goes: before and after.
	for n: String in _wall_nb.get(id, PackedStringArray()):
		_dirty[n] = true
	if _joins and model.parts.has(id):
		for n: String in _joins.neighbours(id):
			_dirty[n] = true
	# A pitched roof's neighbours join up with it: those on its level before and after.
	for n: String in _roof_nb.get(id, PackedStringArray()):
		_dirty[n] = true
	if model.parts.has(id) and RoofShape.form_of(str(model.parts[id].get("kind", ""))) != "":
		for n: String in RoofShape.roof_parts(model, model.level_of(id)):
			_dirty[n] = true
	var e := model.entry(id)
	var old_host := str(_host_of.get(id, ""))
	var host := str(e.get("host", ""))
	if old_host != host:
		if old_host != "":
			(_hosted.get(old_host, {}) as Dictionary).erase(id)
			_dirty[old_host] = true
		_host_of.erase(id)
		if host != "":
			_host_of[id] = host
			if not _hosted.has(host):
				_hosted[host] = {}
			_hosted[host][id] = true
	if host != "":
		_dirty[host] = true
	for o: String in _hosted.get(id, {}):
		_dirty[o] = true
	if e.is_empty():
		_hosted.erase(id)
	var rec: Dictionary = _recs.get(id, {})
	if str(rec.get("fam", "")) == "circulation" or (not e.is_empty() and model.catalog.family_of(str(e.get("kind", ""))) == "circulation"):
		var lo := mini(int(rec.get("level", 99999)), int(e.get("level", 99999)))
		var hi := maxi(int(rec.get("top", -1)), int(e.get("top_level", e.get("level", -1))))
		for l in range(lo, hi + 2):
			for sid: String in _slabs.get(l, {}):
				_dirty[sid] = true


## Does the waiting work now: the dirty entries, then the batches they changed.
func flush() -> void:
	if _dirty.is_empty() and _dirty_batches.is_empty():
		return
	_voids.clear()
	var ids := _dirty.keys()
	_dirty.clear()
	for id: String in ids:
		_drop(id)
		if model.parts.has(id) or model.rooms.has(id):
			_build(id)
	for key: String in _dirty_batches:
		_build_batch(key)
	_dirty_batches.clear()


func _drop(id: String) -> void:
	var r: Dictionary = _recs.get(id, {})
	if r.is_empty():
		return
	for key: String in r.geo:
		_dirty_batches[key] = true
		(_batches[key].ids as Dictionary).erase(id)
	if r.label:
		(r.label as Node).queue_free()
	if r.get("node"):
		(r.node as Node).queue_free()
	if str(r.fam) == "slab":
		(_slabs.get(int(r.level), {}) as Dictionary).erase(id)
	_recs.erase(id)


func show_level(l: int) -> void:
	var was := level
	level = l
	if cut < INF and was != l:
		rebuild()
		return
	_apply_visibility()


func set_cut(height: float) -> void:
	if height != cut:
		cut = height
		rebuild()


func set_show_rooms(on: bool) -> void:
	show_rooms = on
	_apply_visibility()


## Entries drawn.
func node_count() -> int:
	flush()
	return _recs.size()


func has_node_for(id: String) -> bool:
	flush()
	return _recs.has(id)


## Meshes drawn (draw calls, near enough).
func batch_count() -> int:
	flush()
	var n := 0
	for b: Dictionary in _batches.values():
		if b.mesh:
			n += 1
	return n


func tint(id: String, colour: Variant) -> void:
	var had: Variant = _tints.get(id)
	if colour == null:
		_tints.erase(id)
	else:
		_tints[id] = colour
	if had != colour and _recs.has(id):
		_dirty[id] = true


func tints() -> Dictionary:
	return _tints.duplicate()


func _visible(lv: int, room: bool) -> bool:
	return lv == level and show_rooms if room else lv <= level


func _apply_visibility() -> void:
	for key: String in _batches:
		var b: Dictionary = _batches[key]
		if b.mesh:
			(b.mesh as Node3D).visible = _visible(int(b.level), bool(b.room))
	for r: Dictionary in _recs.values():
		if r.label:
			(r.label as Node3D).visible = _visible(int(r.level), bool(r.room))
		if r.get("node"):
			(r.node as Node3D).visible = _visible(int(r.level), false)
	_fade_count = -1


func _build(id: String) -> void:
	_geo = {}
	var room := model.rooms.has(id)
	_geo_room = room
	_geo_level = int(model.rooms[id].level) if room else model.level_of(id)
	_geo_cell = _cell_of(id)
	var rec := {"level": _geo_level, "room": room, "fam": "", "label": null, "top": _geo_level}
	if room:
		rec.label = _room(id)
		_fade_count = -1
	else:
		var e: Dictionary = model.parts[id]
		rec.fam = model.catalog.family_of(str(e.kind))
		rec.top = int(e.get("top_level", _geo_level))
		_part(id)
		if rec.fam == "slab":
			if not _slabs.has(_geo_level):
				_slabs[_geo_level] = {}
			_slabs[_geo_level][id] = true
	rec["geo"] = _geo
	if _geo_node:
		rec["node"] = _geo_node
		add_child(_geo_node)
		_geo_node.visible = _visible(_geo_level, false)
		_ghost_node(_geo_node)
		_geo_node = null
	for key: String in _geo:
		(_batches[key].ids as Dictionary)[id] = true
		_dirty_batches[key] = true
	if rec.label:
		add_child(rec.label as Node)
		(rec.label as Node3D).visible = _visible(_geo_level, room)
	_recs[id] = rec
	_geo = {}


## The square an entry's batch is in: from where it stands (an opening goes with its wall).
func _cell_of(id: String) -> Vector2i:
	var e := model.entry(id)
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
		var m: Material = b.mat
		if m is BaseMaterial3D and (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transparency = ghost
		add_child(mi)
		b.mesh = mi
	(b.mesh as MeshInstance3D).mesh = mesh
	(b.mesh as Node3D).visible = _visible(int(b.level), bool(b.room))


## Draws the building see-through (on) or solid.
func set_ghost(on: bool) -> void:
	var g := GHOST if on else 0.0
	if is_equal_approx(g, ghost):
		return
	ghost = g
	for key: String in _batches:
		var mi: Variant = _batches[key].mesh
		if mi is MeshInstance3D and is_instance_valid(mi):
			(mi as MeshInstance3D).transparency = g
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if on \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for r: Dictionary in _recs.values():
		if r.get("node") and is_instance_valid(r.node):
			_ghost_node(r.node as Node)


## A model node (a library asset) see-through with the rest while the view is a ghost.
func _ghost_node(n: Node) -> void:
	for mi: GeometryInstance3D in n.find_children("*", "GeometryInstance3D", true, false):
		mi.transparency = ghost
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if ghost > 0.0 \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## The arrays the entry being built adds faces of this colour or material to.
func _target(c: Variant) -> Array:
	var mat := _mat(c)
	var key := "%d|%s|%d|%d|%d" % [_geo_level, "r" if _geo_room else "p", mat.get_instance_id(), _geo_cell.x, _geo_cell.y]
	if not _batches.has(key):
		_batches[key] = {"mat": mat, "mesh": null, "ids": {}, "level": _geo_level, "room": _geo_room}
	if not _geo.has(key):
		_geo[key] = [PackedVector3Array(), PackedVector3Array()]
	return _geo[key]


func _part(id: String) -> void:
	var e: Dictionary = model.parts[id]
	var cat := model.catalog
	var kind := str(e.kind)
	var spec := cat.kind(kind)
	var fam := cat.family_of(kind)
	var sec := cat.section(str(e.get("section", "")))
	# The game's look (ArtStyle: clean model or realistic), or the highlight when tinted.
	var colour: Variant = _colour(id, ArtStyle.material(str(e.get("material", "")), fam).albedo_color) \
			if _tints.has(id) else ArtStyle.material(str(e.get("material", "")), fam)
	var floor_y := model.level_elevation(model.level_of(id))
	match cat.shape_of(kind):
		"point":
			var at := _v3(e.at) + Vector3(0, floor_y, 0)
			var rot := Basis(Vector3.UP, deg_to_rad(float(e.get("rot", 0.0))))
			if kind == "lift":
				var shaft := Vector3(float(e.get("w", spec.get("w", 2.0))), model.part_height(id), float(e.get("d", spec.get("d", 2.0))))
				var c: Variant = _colour(id, Color(0.55, 0.6, 0.68, 0.55)) if _tints.has(id) else ArtStyle.material("glass", "opening")
				_box(at + Vector3(0, shaft.y / 2.0, 0), shaft, rot, c)
			elif fam == "fixture":
				# Its library model (a bed, a car, an airliner...) at true size, else a box.
				var size := Vector3(float(spec.get("w", 0.5)), float(spec.get("h", 0.8)), float(spec.get("d", 0.5)))
				if not _model_of(id, kind, "fixture", size, size, at, deg_to_rad(float(e.get("rot", 0.0)))):
					_box(at + Vector3(0, size.y / 2.0, 0), size, rot, colour)
			elif kind == "pile":
				var length := float(e.get("length", spec.get("length", 10.0)))
				var dia := float(sec.get("dia", 0.45))
				_box(at - Vector3(0, length / 2.0, 0), Vector3(dia, length, dia), rot, colour)
			elif str(sec.get("shape", "")) == "pad":
				var w := float(sec.get("w", 1.0))
				var d := float(sec.get("d", 0.5))
				_box(at - Vector3(0, d / 2.0 + INSET, 0), Vector3(w, d, w), rot, colour)
			else:
				var h := model.part_height(id)
				var w := float(sec.get("w", 0.3))
				var d := float(sec.get("d", w))
				# Columns stop just short of floor and beam/wall tops, so their caps don't fight.
				_box(at + Vector3(0, h / 2.0 - INSET, 0), Vector3(w, h - 3.0 * INSET, d), rot, colour)
		"line":
			var a := _v3(e.a) + Vector3(0, floor_y, 0)
			var b := _v3(e.b) + Vector3(0, floor_y, 0)
			if fam == "wall":
				_wall(id, a, b, colour)
			elif kind == "stair":
				_stair(id, a, b, colour)
			elif fam == "service":
				# Cable and pipe runs: thin tubes centred on their line.
				_tube(a, b, tube_dia(kind) / 2.0, colour)
			else:
				var w := float(sec.get("w", 0.2))
				var d := float(sec.get("d", 0.3))
				# Beams hang below their line (their top is at a and b).
				# (just below, so a top flush with a wall's or slab's doesn't fight it)
				var along := (b - a).normalized() * INSET
				_linear(a + along - Vector3(0, d / 2.0 + INSET, 0), b - along - Vector3(0, d / 2.0 + INSET, 0), w, d, colour)
		"area" when fam == "roof" and RoofShape.form_of(kind) != "":
			# A pitched roof (gable, hip, mono-pitch): its slopes, ends and underside.
			var y0 := floor_y + float(e.get("y", 0.0))
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			# Joined with the level's other pitched roofs (valleys where wings meet).
			_roof_nb[id] = RoofShape.roof_parts(model, model.level_of(id))
			for f: Array in RoofShape.part_faces(model, id, RoofShape.EAVE):
				var pts: Array = f[0]
				var lift := func(q: Vector3) -> Vector3: return q + Vector3(0, y0, 0)
				if pts.size() == 3:
					_tri(verts, norms, lift.call(pts[0]), lift.call(pts[1]), lift.call(pts[2]), f[1])
				else:
					_quad(verts, norms, [lift.call(pts[0]), lift.call(pts[1]), lift.call(pts[2]), lift.call(pts[3])] as Array[Vector3], f[1])
			_add(colour, verts, norms)
		"area":
			var t := maxf(float(sec.get("d", 0.2)), 0.05)
			var y := floor_y + float(e.get("y", 0.0))
			var pieces: Array = [_outline(e.outline)]
			if fam == "slab" and absf(float(e.get("y", 0.0))) < 0.01:
				var lv := model.level_of(id)
				if not _voids.has(lv):
					_voids[lv] = model.voids_on(lv)
				pieces = _cut_voids(pieces[0], _voids[lv])
			for poly: PackedVector2Array in pieces:
				_prism(poly, y - t, y, colour)
		"opening":
			var pts := model.points_of(id)
			if pts.size() == 2:
				var h := float(e.get("h", spec.get("h", 2.0)))
				if model.level_of(id) == level:
					h = minf(h, maxf(0.05, cut - float(e.get("sill", spec.get("sill", 0.0)))))
				var dir := pts[1] - pts[0]
				var w := Vector2(dir.x, dir.z).length()
				var t := float(cat.section(str(model.parts.get(str(e.get("host", "")), {}).get("section", ""))).get("d", 0.2))
				if _model_of(id, kind, "opening", Vector3(w, h, t), Vector3(w, float(e.get("h", spec.get("h", 2.0))), 0.0),
						(pts[0] + pts[1]) * 0.5, atan2(-dir.z, dir.x)):
					return
				var glass := str(e.get("material", "")) == "glass" or kind.begins_with("window")
				var c: Variant = _colour(id, GLASS if glass else DOOR) if _tints.has(id) \
						else ArtStyle.material("glass" if glass else "timber", "opening" if glass else "fixture")
				_linear(pts[0] + Vector3(0, h / 2.0, 0), pts[1] + Vector3(0, h / 2.0, 0), 0.06, h, c)


## A part drawn as its library model (when the kind has one): `size` its box, `fit` what the
## model is scaled to (0: its own size), standing at `pos` (bottom centre) turned `yaw`. While
## tinted (selected, or in someone's hands) a see-through box of that colour goes round it.
## False if the kind has no model (draw it some other way).
func _model_of(id: String, kind: String, fam: String, size: Vector3, fit: Vector3, pos: Vector3, yaw: float) -> bool:
	if AssetLibrary.id_for_kind(kind) == "" and str(model.catalog.kind(kind).get("asset", "")) == "":
		return false
	if not _model_ok.has(id):
		# A box for now; the model comes a few at a time over the next frames, so opening a
		# big design (an airport) stays quick.
		if not _model_wait.has(id):
			_model_wait[id] = true
		return false
	_geo_node = AssetLibrary.make_kind(kind, {"size": size, "family": fam, "fit": fit, "lod": lod_distance})
	_geo_node.name = "Asset_" + id
	_geo_node.position = pos
	_geo_node.rotation.y = yaw
	if _tints.has(id):
		var t: Color = _tints[id]
		_box(pos + Vector3(0, size.y / 2.0, 0), size, Basis(Vector3.UP, yaw), Color(t.r, t.g, t.b, 0.3))
	return true


## Swaps waiting boxes for their library models, a few milliseconds' worth a frame.
func _upgrade_models() -> void:
	if _model_wait.is_empty():
		return
	var end := Time.get_ticks_usec() + MODEL_BUDGET_US
	for id: String in _model_wait.keys():
		_model_wait.erase(id)
		_model_ok[id] = true
		if model.parts.has(id):
			_drop(id)
			_build(id)
		if Time.get_ticks_usec() > end:
			break


## A wall drawn in pieces around its openings: solid runs, and the pieces under and over each.
func _wall(id: String, a: Vector3, b: Vector3, colour: Variant) -> void:
	var e: Dictionary = model.parts[id]
	var h := model.part_height(id)
	if model.level_of(id) == level:
		h = minf(h, cut)
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
	# Corners and tees: run on over a neighbour's end or stop at its face (WallJoins).
	var ext := _joins.ends(id) if _joins else Vector2.ZERO
	_wall_nb[id] = _joins.neighbours(id) if _joins else PackedStringArray()
	var cursor := -ext.x
	length += ext.y
	for hole: Array in holes:
		if hole[0] > cursor:
			_linear(a + dir * cursor + up * h / 2.0, a + dir * hole[0] + up * h / 2.0, t, h, colour)
		var bottom: float = hole[2]
		var top: float = minf(hole[3], h)
		if bottom > 0.01:
			_linear(a + dir * hole[0] + up * bottom / 2.0, a + dir * hole[1] + up * bottom / 2.0, t, bottom, colour)
		if top < h - 0.01:
			_linear(a + dir * hole[0] + up * (top + h) / 2.0, a + dir * hole[1] + up * (top + h) / 2.0, t, h - top, colour)
		cursor = maxf(cursor, hole[1])
	if cursor < length:
		_linear(a + dir * cursor + up * h / 2.0, a + dir * length + up * h / 2.0, t, h, colour)


## A flight of steps from a (foot) to b (head), rising to the next level's floor.
func _stair(id: String, a: Vector3, b: Vector3, colour: Variant) -> void:
	var rise := model.level_height(model.level_of(id))
	var w := model.stair_width(id)
	var steps := maxi(2, int(round(rise / 0.18)))
	for i in steps:
		var f0 := float(i) / steps
		var f1 := float(i + 1) / steps
		var h := rise * f1
		_linear(a.lerp(b, f0) + Vector3(0, h / 2.0, 0), a.lerp(b, f1) + Vector3(0, h / 2.0, 0), w, h, colour)


## A floor outline with stair and lift holes taken out, as pieces with no holes in them (each
## hole splits the floor in two through its middle first, so no piece wraps round a hole).
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


## A room's tinted floor, and its name and area on a label (returned, not yet in the tree).
func _room(id: String) -> Label3D:
	var e: Dictionary = model.rooms[id]
	var rt := model.catalog.room_type(str(e.type))
	var c := Color.html(str(rt.get("colour", "dddddd")))
	c.a = ROOM_ALPHA
	c = _colour(id, c)
	var y := model.level_elevation(int(e.level))
	var poly := _outline(e.outline)
	# A tint on the floor: its top only, so its edges can't fight the walls' ends.
	_flat(poly, y + 0.04, c)
	if poly.size() < 3:
		return null
	var centre := Vector2.ZERO
	for v in poly:
		centre += v
	centre /= poly.size()
	var label := Label3D.new()
	var title := str(e.get("name", ""))
	if title == "":
		title = str(rt.get("label", e.type))
	var area := BuildingModel.outline_area(e.outline)
	var min_area := float(rt.get("min_area", 0.0))
	var short := area + BuildingModel.EPS < min_area
	label.text = "%s\n%.1f m²%s" % [title, area, "  (min %.0f)" % min_area if short else ""]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	if labels_fixed:
		# Drawn at its size on screen, so it is sharp at any zoom; fade_labels() thins
		# them out as the view zooms out.
		label.fixed_size = true
		label.font_size = 26
		label.outline_size = 7
		label.pixel_size = 0.0013
	else:
		label.font_size = 36
		label.pixel_size = 0.01
	label.set_meta("span", sqrt(maxf(area, 0.01)))
	label.modulate = Color(1.0, 0.55, 0.35) if short else Color(0.08, 0.08, 0.1)
	label.outline_modulate = Color(1, 1, 1, 0.85)
	if not labels_fixed:
		label.outline_size = 8
	label.position = Vector3(centre.x, y + 0.5, centre.y)
	return label


func _colour(id: String, base: Color) -> Color:
	if _tints.has(id):
		var t: Color = _tints[id]
		var out := base.lerp(t, 0.7)
		out.a = maxf(base.a, 0.6)
		return out
	return base


func _mat(c: Variant) -> Material:
	if c is Material:
		return c
	var key: String = (c as Color).to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	if (c as Color).a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


## Adds faces to the entry being built: tris as corner triples, each face's outward normal.
func _add(c: Variant, verts: PackedVector3Array, norms: PackedVector3Array) -> void:
	var t := _target(c)
	var v: PackedVector3Array = t[0]
	var n: PackedVector3Array = t[1]
	v.append_array(verts)
	n.append_array(norms)
	t[0] = v
	t[1] = n


## A box: centre, size (x along, y up, z across) turned by basis.
func _box(centre: Vector3, size: Vector3, basis: Basis, c: Variant) -> void:
	var h := size / 2.0
	var verts := PackedVector3Array()
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
			var normal := (basis * nl).normalized()
			_quad(verts, norms, corners, normal)
	_add(c, verts, norms)


## Two triangles for a quad, wound to face its normal.
static func _quad(verts: PackedVector3Array, norms: PackedVector3Array, p: Array[Vector3], normal: Vector3) -> void:
	_tri(verts, norms, p[0], p[1], p[2], normal)
	_tri(verts, norms, p[0], p[2], p[3], normal)


## One triangle facing normal (Godot draws clockwise-wound faces as the front).
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


## A bar from a to b (centre line), w wide and h tall.
func _linear(a: Vector3, b: Vector3, w: float, h: float, c: Variant) -> void:
	var d := b - a
	var plan := Vector2(d.x, d.z)
	if d.length() < 0.01:
		return
	var basis := Basis(Vector3.UP, -plan.angle())
	if absf(d.y) > 0.001:
		basis = basis * Basis(Vector3.BACK, atan2(d.y, plan.length()))
	_box((a + b) / 2.0, Vector3(d.length(), h, w), basis, c)


## How thick a service run of `kind` is drawn, m: cables thin, pipes by bore, waste widest.
static func tube_dia(kind: String) -> float:
	if kind.begins_with("cable"):
		return 0.03
	if kind == "pipe_waste":
		return 0.1
	return 0.05


const TUBE_SIDES := 8


## A round tube of radius r from a to b (centre line), TUBE_SIDES sided with smooth sides.
func _tube(a: Vector3, b: Vector3, r: float, c: Variant) -> void:
	var d := b - a
	if d.length() < 0.01:
		return
	var ax := d.normalized()
	var side := ax.cross(Vector3.UP)
	if side.length() < 0.01:
		side = ax.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(ax).normalized()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for i in TUBE_SIDES:
		var t0 := TAU * i / TUBE_SIDES
		var t1 := TAU * (i + 1) / TUBE_SIDES
		var n0 := side * cos(t0) + up * sin(t0)
		var n1 := side * cos(t1) + up * sin(t1)
		var q: Array[Vector3] = [a + n0 * r, b + n0 * r, b + n1 * r, a + n1 * r]
		var qn: Array[Vector3] = [n0, n0, n1, n1]
		# Wound to face outward (Godot's front faces are clockwise).
		var flip := (q[1] - q[0]).cross(q[2] - q[0]).dot(n0 + n1) > 0.0
		for k: int in ([0, 2, 1, 0, 3, 2] if flip else [0, 1, 2, 0, 2, 3]):
			verts.append(q[k])
			norms.append(qn[k])
	_add(c, verts, norms)


## A flat face over a polygon at height y, facing up.
func _flat(poly: PackedVector2Array, y: float, c: Variant) -> void:
	if poly.size() < 3:
		return
	if Geometry2D.is_polygon_clockwise(poly):
		poly.reverse()
	var tris := Geometry2D.triangulate_polygon(poly)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for i in range(0, tris.size(), 3):
		var p0 := poly[tris[i]]
		var p1 := poly[tris[i + 1]]
		var p2 := poly[tris[i + 2]]
		_tri(verts, norms, Vector3(p0.x, y, p0.y), Vector3(p1.x, y, p1.y), Vector3(p2.x, y, p2.y), Vector3.UP)
	if not verts.is_empty():
		_add(c, verts, norms)


func _prism(poly: PackedVector2Array, bottom: float, top: float, c: Variant) -> void:
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
		var normal := Vector3(out.x, 0, out.y)
		var quad: Array[Vector3] = [Vector3(p.x, bottom, p.y), Vector3(q.x, bottom, q.y), Vector3(q.x, top, q.y), Vector3(p.x, top, p.y)]
		_quad(verts, norms, quad, normal)
	_add(c, verts, norms)


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
