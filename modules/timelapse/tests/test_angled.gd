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
	check(wm.transform.basis.x.normalized().dot(dir) > 0.999, "the timelapse draws the wall at its angle")
	check(view._pieces[sid].mesh.mesh is ArrayMesh, "and the slab as its outline")
	view.queue_free()
	await frames(1)
