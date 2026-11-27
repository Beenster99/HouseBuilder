extends Node3D
## Draws a SitePack in a neutral architectural-model style: terrain coloured by land use,
## extruded neighbour buildings, roads and paths draped on the ground, trees, power lines,
## barriers, water, and the plot outlined. Neighbours, the terrain and buildings on the plot
## get static colliders, so Jolt debris lands on them and demolition can score hits.
##
## Every neighbour's collider is in group NEIGHBOUR_GROUP with meta "site_building"
## (its pack id), "protected" (bool) and "site_building_data" (the pack entry).
## Built in one go by build(pack); cheap to free and rebuild when the site changes.

const NEIGHBOUR_GROUP := "site_neighbours"
const PLOT_GROUP := "site_plot_buildings"
const LIFT := 0.06  # draped things sit this far over the ground
## Height between flat layers (roads, paths...), m; features in one layer step up by
## FEATURE_STEP each (a few of them), so crossing roads of different surfaces don't fight.
const LAYER_GAP := 0.2
const FEATURE_STEP := 0.015
## Barriers are thin boxes this thick, so a fence along a building's wall never shares its plane.
const BARRIER_THICK := 0.08

const C_GROUND := Color(0.5, 0.53, 0.46)
const C_GRASS := Color(0.42, 0.56, 0.36)
const C_WOOD := Color(0.42, 0.56, 0.38)
const C_WATER := Color(0.48, 0.66, 0.8)
const C_PAVED := Color(0.6, 0.6, 0.58)
const C_ROAD := Color(0.36, 0.37, 0.4)
const C_PATH := Color(0.82, 0.78, 0.68)
const C_BUILDING := Color(0.92, 0.91, 0.88)
const C_ROOF := Color(0.84, 0.83, 0.8)
const C_PROTECTED := Color(0.9, 0.8, 0.62)
const C_ON_PLOT := Color(0.95, 0.62, 0.35)
const C_PLOT := Color(1.0, 0.55, 0.15)
const C_TREE := Color(0.36, 0.55, 0.32)
const C_TRUNK := Color(0.45, 0.35, 0.25)
const C_WIRE := Color(0.2, 0.2, 0.22)
const C_BARRIER := Color(0.7, 0.66, 0.6)

var pack: SitePack
var neighbour_count := 0


func build(p: SitePack) -> void:
	pack = p
	name = "Site_" + p.id()
	_terrain()
	_buildings()
	# Each flat layer at its own height, far enough apart that none share a plane on a slope:
	# water < roads < railways < paths < the plot outline.
	_lines("waterways", C_WATER, 3.0, LIFT)
	_lines("roads", C_ROAD, 6.0, LIFT + LAYER_GAP)
	_lines("railways", Color(0.45, 0.4, 0.38), 3.0, LIFT + LAYER_GAP * 2.0)
	_lines("paths", C_PATH, 2.0, LIFT + LAYER_GAP * 3.0)
	_barriers()
	_trees()
	_power_lines()
	_plot()


# --- Terrain -----------------------------------------------------------------------------

func _terrain() -> void:
	var t := pack.terrain_grid()
	var size: Vector2i = t.size
	var origin: Vector2 = t.origin
	var step: float = t.spacing
	var heights: PackedFloat32Array = t.heights
	var colours := PackedColorArray()
	colours.resize(size.x * size.y)
	colours.fill(C_GROUND)
	# Land use: larger areas first so smaller ones paint over them.
	var areas: Array = pack.features("areas").duplicate()
	areas.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _area_of(a.outline) > _area_of(b.outline))
	for a: Dictionary in areas:
		var col := _area_colour(str(a.kind))
		if col.a == 0.0:
			continue
		var poly := _poly(a.outline)
		var bb := _bounds(poly)
		var i0 := maxi(int((bb.position.x - origin.x) / step), 0)
		var i1 := mini(int((bb.end.x - origin.x) / step) + 1, size.x - 1)
		var j0 := maxi(int((bb.position.y - origin.y) / step), 0)
		var j1 := mini(int((bb.end.y - origin.y) / step) + 1, size.y - 1)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				if Geometry2D.is_point_in_polygon(Vector2(origin.x + i * step, origin.y + j * step), poly):
					colours[j * size.x + i] = col
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in size.y:
		for i in size.x:
			st.set_color(colours[j * size.x + i])
			st.add_vertex(Vector3(origin.x + i * step, heights[j * size.x + i], origin.y + j * step))
	for j in size.y - 1:
		for i in size.x - 1:
			var k := j * size.x + i
			st.add_index(k)
			st.add_index(k + 1)
			st.add_index(k + size.x)
			st.add_index(k + 1)
			st.add_index(k + size.x + 1)
			st.add_index(k + size.x)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = st.commit()
	mi.material_override = _material(Color.WHITE, true)
	add_child(mi)
	# Collision: a height map scaled to the grid spacing, centred on the grid.
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var shape := HeightMapShape3D.new()
	shape.map_width = size.x
	shape.map_depth = size.y
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(step, 1.0, step)
	cs.position = Vector3(origin.x + (size.x - 1) * step * 0.5, 0.0, origin.y + (size.y - 1) * step * 0.5)
	body.add_child(cs)
	add_child(body)


static func _area_colour(kind: String) -> Color:
	if kind.begins_with("natural:water") or kind.begins_with("waterway:"):
		return C_WATER
	if kind in ["natural:wood", "landuse:forest", "natural:scrub"]:
		return C_WOOD
	if kind in ["landuse:grass", "leisure:park", "landuse:meadow", "leisure:garden", "landuse:farmland",
			"natural:grassland", "landuse:recreation_ground", "leisure:pitch", "landuse:village_green"]:
		return C_GRASS
	if kind in ["amenity:parking", "landuse:retail", "landuse:commercial", "landuse:industrial",
			"area:highway", "place:square", "landuse:railway"]:
		return C_PAVED
	return Color(0, 0, 0, 0)


# --- Buildings ---------------------------------------------------------------------------

func _buildings() -> void:
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roofs := SurfaceTool.new()
	roofs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bodies := Node3D.new()
	bodies.name = "BuildingBodies"
	add_child(bodies)
	for b: Dictionary in pack.buildings():
		var poly := _poly(b.outline)
		if poly.size() < 3:
			continue
		var on_plot := bool(b.get("on_plot", false))
		var prot := bool(b.get("protected", false))
		var base := float(b.get("base_y", 0.0)) - 0.3  # sink a little: slopes leave no gap
		var top := float(b.get("base_y", 0.0)) + float(b.get("height_m", 6.0))
		var bottom := base + float(b.get("min_height_m", 0.0))
		var col := C_ON_PLOT if on_plot else (C_PROTECTED if prot else C_BUILDING)
		var tris := PackedVector3Array()
		var n := poly.size()
		for i in n:
			var a := poly[i]
			var c := poly[(i + 1) % n]
			var q := [Vector3(a.x, bottom, a.y), Vector3(c.x, bottom, c.y), Vector3(c.x, top, c.y), Vector3(a.x, top, a.y)]
			for v in [q[0], q[2], q[1], q[0], q[3], q[2]]:
				walls.set_color(col)
				walls.add_vertex(v)
				tris.append(v)
		var idx := Geometry2D.triangulate_polygon(poly)
		for k in range(0, idx.size(), 3):
			for v in [idx[k], idx[k + 2], idx[k + 1]]:
				var p := Vector3(poly[v].x, top, poly[v].y)
				roofs.set_color(col.darkened(0.06) if not on_plot else col)
				roofs.add_vertex(p)
				tris.append(p)
		# Collider for physics and scoring.
		var body := StaticBody3D.new()
		body.name = str(b.id).replace(".", "_")
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(tris)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		body.set_meta("site_building", str(b.id))
		body.set_meta("protected", prot)
		body.set_meta("site_building_data", b)
		body.add_to_group(PLOT_GROUP if on_plot else NEIGHBOUR_GROUP)
		if not on_plot:
			neighbour_count += 1
		bodies.add_child(body)
	walls.generate_normals()
	roofs.generate_normals()
	for pair in [["BuildingWalls", walls], ["BuildingRoofs", roofs]]:
		var mi := MeshInstance3D.new()
		mi.name = pair[0]
		mi.mesh = (pair[1] as SurfaceTool).commit()
		mi.material_override = _material(Color.WHITE, true)
		add_child(mi)


# --- Lines on the ground -------------------------------------------------------------------

func _lines(kind: String, col: Color, default_width: float, lift: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var fi := -1
	for f: Dictionary in pack.features(kind):
		if bool(f.get("tunnel", false)) or str(f.get("kind", "")) == "subway":
			continue
		fi += 1
		var own := lift + float(fi % 5) * FEATURE_STEP
		var w := float(f.get("width_m", default_width)) * 0.5
		var pts := _densify(_poly(f.line), 2.0)
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var side := (b - a).orthogonal().normalized() * w
			# Two strips either side of the centre line, so a wide road follows the ground
			# across its width as well as along it.
			for half: Array in [[a + side, a, b, b + side], [a, a - side, b - side, b]]:
				var v3: Array = []
				for q: Vector2 in half:
					# Neighbouring pieces overlap at bends: alternate them a hair apart.
					v3.append(Vector3(q.x, pack.height_at(q.x, q.y) + own + float(i % 2) * 0.006, q.y))
				for v in [v3[0], v3[1], v3[2], v3[0], v3[2], v3[3]]:
					st.set_normal(Vector3.UP)
					st.add_vertex(v)
			any = true
	if not any:
		return
	var mi := MeshInstance3D.new()
	mi.name = kind.capitalize()
	mi.mesh = st.commit()
	# One plain colour per layer (no vertex colours): where a layer's own pieces overlap,
	# the same material wins either way, so nothing flickers.
	mi.material_override = _material(col, false, true)
	add_child(mi)


func _barriers() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for f: Dictionary in pack.features("barriers"):
		var h := float(f.get("height_m", 1.2))
		var pts := _densify(_poly(f.line), 4.0)
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var ya := pack.height_at(a.x, a.y)
			var yb := pack.height_at(b.x, b.y)
			var off2 := (b - a).orthogonal().normalized() * BARRIER_THICK * 0.5
			var off := Vector3(off2.x, 0.0, off2.y)
			var a0 := Vector3(a.x, ya, a.y)
			var b0 := Vector3(b.x, yb, b.y)
			var up := Vector3(0, h, 0)
			# Two faces, a top and the two ends: a thin wall of its own.
			var quads := [[a0 + off, b0 + off, b0 + off + up, a0 + off + up],
					[b0 - off, a0 - off, a0 - off + up, b0 - off + up],
					[a0 + off + up, b0 + off + up, b0 - off + up, a0 - off + up]]
			if i == 0:
				quads.append([a0 - off, a0 + off, a0 + off + up, a0 - off + up])
			if i == pts.size() - 2:
				quads.append([b0 + off, b0 - off, b0 - off + up, b0 + off + up])
			for q: Array in quads:
				for v in [q[0], q[1], q[2], q[0], q[2], q[3]]:
					st.set_color(C_BARRIER)
					st.add_vertex(v)
			any = true
	if not any:
		return
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Barriers"
	mi.mesh = st.commit()
	mi.material_override = _material(Color.WHITE, true)
	add_child(mi)


func _trees() -> void:
	var trees: Array = pack.features("trees")
	if trees.is_empty():
		return
	var crown := SphereMesh.new()
	crown.radius = 0.5
	crown.height = 1.0
	crown.radial_segments = 8
	crown.rings = 4
	crown.material = _material(C_TREE, false)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.18
	trunk.height = 1.0
	trunk.radial_segments = 6
	trunk.material = _material(C_TRUNK, false)
	for pair in [["TreeCrowns", crown], ["TreeTrunks", trunk]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pair[1]
		mm.instance_count = trees.size()
		for i in trees.size():
			var t: Dictionary = trees[i]
			var pos: Array = t.pos
			var base := float(t.get("base_y", pack.height_at(float(pos[0]), float(pos[1]))))
			var h := float(t.get("height_m", 9.0))
			var c := float(t.get("crown_m", 6.0))
			var xf: Transform3D
			if pair[0] == "TreeCrowns":
				xf = Transform3D(Basis.from_scale(Vector3(c, h * 0.6, c)), Vector3(float(pos[0]), base + h * 0.65, float(pos[1])))
			else:
				xf = Transform3D(Basis.from_scale(Vector3(1.0, h * 0.5, 1.0)), Vector3(float(pos[0]), base + h * 0.25, float(pos[1])))
			mm.set_instance_transform(i, xf)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = pair[0]
		mmi.multimesh = mm
		add_child(mmi)


func _power_lines() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var poles := SurfaceTool.new()
	poles.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for f: Dictionary in pack.features("power_lines"):
		if str(f.get("kind", "")) == "cable":
			continue
		var h := float(f.get("height_m", 15.0 if str(f.kind) == "line" else 8.0))
		var pts := _poly(f.line)
		for i in pts.size():
			var p := pts[i]
			var y := pack.height_at(p.x, p.y)
			_box(poles, Vector3(p.x, y + h * 0.5, p.y), Vector3(0.4, h, 0.4), C_WIRE)
			if i + 1 < pts.size():
				var q := pts[i + 1]
				st.set_color(C_WIRE)
				st.add_vertex(Vector3(p.x, y + h, p.y))
				st.set_color(C_WIRE)
				st.add_vertex(Vector3(q.x, pack.height_at(q.x, q.y) + h, q.y))
			any = true
	if not any:
		return
	for pair in [["PowerLines", st], ["PowerPoles", poles]]:
		var mi := MeshInstance3D.new()
		mi.name = pair[0]
		mi.mesh = (pair[1] as SurfaceTool).commit()
		mi.material_override = _material(Color.WHITE, true)
		add_child(mi)


# --- The plot ----------------------------------------------------------------------------

func _plot() -> void:
	var poly := _poly(pack.plot_outline())
	if poly.size() < 3:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := _densify(poly + PackedVector2Array([poly[0]]), 2.0)
	for i in ring.size() - 1:
		var a := ring[i]
		var b := ring[i + 1]
		var side := (b - a).orthogonal().normalized() * 0.6
		var quad := [a + side, a - side, b - side, b + side]
		var v3: Array = []
		for q: Vector2 in quad:
			v3.append(Vector3(q.x, pack.height_at(q.x, q.y) + LIFT + LAYER_GAP * 4.0, q.y))
		for v in [v3[0], v3[1], v3[2], v3[0], v3[2], v3[3]]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.name = "PlotOutline"
	mi.mesh = st.commit()
	mi.material_override = _material(C_PLOT, false, true)
	add_child(mi)


# --- Helpers -----------------------------------------------------------------------------

static func _material(col: Color, vertex_colours: bool, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.vertex_color_use_as_albedo = vertex_colours
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	m.metallic_specular = 0.05
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var faces := [
		[Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
		[Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)],
		[Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1)],
		[Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1)],
		[Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(-1, 1, -1)],
	]
	for f: Array in faces:
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.add_vertex(c + (f[k] as Vector3) * h)


static func _poly(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in pts:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


static func _densify(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in pts.size():
		if i > 0:
			var a := pts[i - 1]
			var b := pts[i]
			var n := maxi(int(a.distance_to(b) / step), 1)
			for k in range(1, n):
				out.append(a.lerp(b, float(k) / n))
		out.append(pts[i])
	return out


static func _bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


static func _area_of(outline: Array) -> float:
	var s := 0.0
	var n := outline.size()
	for i in n:
		var p: Array = outline[i]
		var q: Array = outline[(i + 1) % n]
		s += float(p[0]) * float(q[1]) - float(q[0]) * float(p[1])
	return absf(s) * 0.5
