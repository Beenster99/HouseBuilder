extends ModuleTest
## The graph paper never runs out: it follows the camera wherever it goes and keeps its height
## and snap settings.


func run_tests() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	var grid := InfiniteGrid.new()
	add_child(grid)
	grid.height = 3.0
	cam.global_position = Vector3(2500.4, 40, -1800.6)
	await frames(2)
	check(grid.global_position.distance_to(Vector3(2500, 3, -1801)) < 0.01,
			"the grid follows the camera far beyond any plot: %s" % grid.global_position)
	check((grid.mesh as PlaneMesh).size.x >= 2000.0, "and reaches past the camera's far view")
	grid.set_snap(0.25, Vector3(1, 0, 2))
	var st := grid.state()
	check(is_equal_approx(float(st.snap_step), 0.25) and st.snap_focus == Vector3(1, 0, 2), "the snap grid is set")
	check(grid.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "it casts no shadow")
	grid.queue_free()
	cam.queue_free()
