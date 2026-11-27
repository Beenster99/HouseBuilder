extends ModuleTest
## Angled walls and odd-shaped slabs build in the timelapse exactly as designed: a wall at
## 30 degrees is a turned box along its own line, a triangular slab is a triangle (not the
## box around it), and the faces point outwards so they draw from every side.
##   tools/run_tests.sh timelapse


const View := preload("res://modules/timelapse/internal/timelapse_view.gd")


func run_tests() -> void:
	var m := BuildingModel.new()
	var dir := Vector3(cos(deg_to_rad(30.0)), 0, sin(deg_to_rad(30.0)))
	var b := dir * 6.0
	var wid := str(m.apply(BuildingCommands.place_part("wall_loadbearing", 0, {"a": [0, 0, 0], "b": [b.x, 0, b.z]}, "masonry")).do.entry.id)
	var sid := str(m.apply(BuildingCommands.place_part("slab", 0, {"outline": [[0, 0], [8, 0], [0, 6]]})).do.entry.id)
	var win := str(m.apply(BuildingCommands.place_opening("window_medium", wid, 3.0)).do.entry.id)
	# An L corner away from the rest: the walls must join up, not overlap or leave a notch.
	var c1 := str(m.apply(BuildingCommands.place_part("wall_loadbearing", 0, {"a": [20, 0, 20], "b": [26, 0, 20]}, "masonry")).do.entry.id)
	var c2 := str(m.apply(BuildingCommands.place_part("wall_loadbearing", 0, {"a": [26, 0, 20], "b": [26, 0, 26]}, "masonry")).do.entry.id)
	# A gable roof over 8 x 6 m, 3 m up: its slopes, not a flat slab.
	var rid := str(m.apply(BuildingCommands.place_part("roof_pitched", 0, {"outline": [[-30, 0], [-22, 0], [-22, 6], [-30, 6]], "y": 3.0}, "timber")).do.entry.id)
	var jet_kind := "airport.aircraft.jumbo"
	var jid := ""
	if m.catalog.kind(jet_kind).has("asset"):
		jid = str(m.apply(BuildingCommands.place_part(jet_kind, 0, {"at": [40, 0, 40]})).do.entry.id)
	var parts := BuildingParts.from_model(m)
	var wall: Dictionary = {}
	var slab: Dictionary = {}
	for p in parts:
		if p.id == wid:
			wall = p
		elif p.id == sid:
			slab = p
	check(wall.has("shape") and (wall.shape as Dictionary).has("obb"), "an angled wall carries its turned box")
	var obb: Transform3D = wall.shape.obb
	var along := obb.basis.x
	check(absf(along.length() - 6.0) < 0.01, "the wall is its own length (6 m), not its box's: %.2f" % along.length())
	check(along.normalized().dot(dir) > 0.999, "and runs along its own line")
	check(absf(obb.basis.y.length() - m.part_height(wid)) < 0.01 and obb.basis.y.normalized().dot(Vector3.UP) > 0.999,
			"standing its full height, upright")
	check(obb.origin.distance_to(Vector3(b.x * 0.5, m.part_height(wid) * 0.5, b.z * 0.5)) < 0.01, "centred on its line")

	var thick := WallJoins.new(m).thickness(c1)
	var lens: Array[float] = []
	for p in parts:
		if p.id in [c1, c2]:
			lens.append(((p.shape.obb as Transform3D).basis.x).length())
	lens.sort()
	check(lens.size() == 2 and absf(lens[0] - (6.0 - thick * 0.5)) < 0.01 and absf(lens[1] - (6.0 + thick * 0.5)) < 0.01,
			"at a corner one wall runs on by half the other's thickness and the other stops at its face: %s" % [lens])
	var roof: Dictionary = {}
	for p in parts:
		if p.id == rid:
			roof = p
	check(roof.has("shape") and (roof.shape as Dictionary).has("faces"), "a pitched roof carries its faces")
	if roof.has("shape") and roof.shape.has("faces"):
		var top := -INF
		var base := INF
		for f: Array in roof.shape.faces:
			for q: Vector3 in f[0]:
				top = maxf(top, q.y)
				base = minf(base, q.y)
		var pitch := float(m.parts[rid].get("pitch", m.catalog.kind("roof_pitched").get("pitch", 35.0)))
		var want := RoofShape.rise([[-30, 0], [-22, 0], [-22, 6], [-30, 6]], pitch, "gable")
		var west := INF
		for f: Array in roof.shape.faces:
			for q: Vector3 in f[0]:
				west = minf(west, q.x)
		check(base < 3.0 and absf(top - 3.0 - want) < 0.01, "on its walls, its ridge %.2f m up (want %.2f)" % [top - 3.0, want])
		check(absf(west - (-30.0 - RoofShape.EAVE)) < 0.01, "overhanging the walls by the eave: %.2f m" % (-30.0 - west))
		# Each face drawn facing the way RoofShape says it faces (slopes up and out, soffits down).
		var ok := (View.faces_mesh(roof.shape.faces).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() >= 18
		for f: Array in roof.shape.faces:
			var fv: PackedVector3Array = View.faces_mesh([f]).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for i in range(0, fv.size(), 3):
				if (fv[i + 2] - fv[i]).cross(fv[i + 1] - fv[i]).dot(f[1]) <= 0.0:
					ok = false
		check(ok, "its faces point outwards")
	check(slab.has("shape") and (slab.shape as Dictionary).has("outline")
			and (slab.shape.outline as PackedVector2Array).size() == 3, "a triangular slab keeps its three corners")

	# The schedule carries shapes through to its tasks.
	var sched := TimelapseSchedule.build(parts)
	var carried := 0
	for t: Dictionary in sched.tasks:
		if t.id in [wid, sid] and not (t.get("shape", {}) as Dictionary).is_empty():
			carried += 1
	check(carried == 2, "the schedule's tasks carry the shapes")

	# The slab's mesh: a triangle's area on top, faces pointing outwards.
	var mesh := View.slab_mesh(slab.shape.outline, 0.0, 0.2)
	var arr := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var top_area := 0.0
	var outward := true
	var centre := Vector3(8.0 / 3.0, -0.1, 2.0)
	for i in range(0, verts.size(), 3):
		var a := verts[i]
		var bb := verts[i + 1]
		var c := verts[i + 2]
		# Godot's front faces wind clockwise seen from outside: the normal is (c - a) x (b - a).
		var n := (c - a).cross(bb - a)
		var mid := (a + bb + c) / 3.0
		if n.dot(mid - centre) <= 0.0:
			outward = false
		if absf(a.y) < 0.001 and absf(bb.y) < 0.001 and absf(c.y) < 0.001:
			top_area += n.length() * 0.5
	check(absf(top_area - 24.0) < 0.01, "its top is the triangle's 24 m², not the box's 48: %.1f" % top_area)
	check(outward, "every face points outwards")

	# The view draws them: the wall's piece is turned, the slab's is its outline.
	var bus := Modules.bus("timelapse") as TimelapseBus
	bus.start_timelapse(parts, "Angled", false)
	var view: Node3D = load("res://modules/timelapse/internal/timelapse_view.tscn").instantiate()
	add_child(view)
	await frames(2)
	var wm := view._pieces[wid].mesh as MeshInstance3D
	var inv := (wall.shape.obb as Transform3D).affine_inverse()
	var inside := true
	var wv: PackedVector3Array = wm.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for v in wv:
		var q := inv * (wm.transform * v)
		if absf(q.x) > 0.501 or absf(q.y) > 0.501 or absf(q.z) > 0.501:
			inside = false
	check(inside and wv.size() > 0, "the timelapse draws the wall at its angle")
	check((wall.shape.get("cuts", []) as Array).size() >= 3, "round its window: %d pieces" % (wall.shape.get("cuts", []) as Array).size())
	var hole_free := true
	var win_mid: Vector3 = view._pieces[win].pivot.global_position + Vector3(0, 0.5, 0)
	for xf: Transform3D in wall.shape.cuts:
		var q := xf.affine_inverse() * win_mid
		if absf(q.x) < 0.5 and absf(q.y) < 0.5 and absf(q.z) < 0.5:
			hole_free = false
	check(hole_free, "leaving the window's hole open")
	check(view._pieces[sid].mesh.mesh is ArrayMesh, "and the slab as its outline")
	# A window in the angled wall: its library model, turned to the wall's line.
	var wp: Dictionary = view._pieces.get(win, {})
	check(wp.has("meshes") and (wp.meshes as Array).size() > 1, "the window builds as its library model, not a box")
	if wp.has("meshes"):
		var wn := wp.pivot as Node3D
		check(absf(wn.global_transform.basis.x.normalized().dot(dir)) > 0.99, "lined up with its angled wall")
	if jid != "":
		# A library object (the jumbo jet) builds as its own model, not its box.
		var jet: Dictionary = view._pieces[jid]
		check((jet.get("meshes", []) as Array).size() > 1 and (jet.pivot as Node3D).position.distance_to(Vector3(40, 0, 40)) < 0.01,
				"a library object builds as its own model where it was placed: %d meshes" % (jet.get("meshes", []) as Array).size())
		bus.request_seek(bus.total_days())
		await frames(2)
		var shown := (jet.pivot as Node3D).visible
		for mi: MeshInstance3D in jet.meshes:
			shown = shown and mi.transparency < 0.01
		check(shown, "and is solid once built")
	view.queue_free()
	await frames(1)
