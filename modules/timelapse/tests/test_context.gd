extends ModuleTest
## On a real site the timelapse builds in its real surroundings: the loaded site's terrain,
## roads, neighbours and trees go round the build in place of the plain ground, and go
## again when the site is cleared.
##   tools/run_tests.sh timelapse


func run_tests() -> void:
	var sites := Modules.bus("sites")
	if sites == null or not sites.has_method("load_site"):
		check(true, "no sites module: nothing to show")
		return
	var bus := Modules.bus("timelapse") as TimelapseBus
	bus.start_timelapse(load("res://modules/timelapse/internal/demo_house.gd").parts(), "Context", false)
	var view: Node3D = load("res://modules/timelapse/internal/timelapse_view.tscn").instantiate()
	add_child(view)
	await frames(2)
	check(view.context == null and view._ground.visible, "no site loaded: the plain ground")
	sites.call("load_site", "tewkesbury-floodplain")
	await frames(2)
	check(view.context != null and view.context.is_inside_tree() and not view._ground.visible,
			"a real site loaded: its surroundings round the build, not the plain ground")
	check(view.context != null and view.context.get_child_count() > 0, "with something in it")
	sites.call("clear_site")
	await frames(2)
	check(view.context == null and view._ground.visible, "cleared: back to the plain ground")
	view.queue_free()
	await frames(1)
