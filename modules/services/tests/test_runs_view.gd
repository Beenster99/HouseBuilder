extends ModuleTest
## The Service runs layer draws every route of the report in its system's colour, follows new
## reports, and shows only while this player has it on.
##   tools/run_tests.sh services

const Samples := preload("res://modules/services/tests/samples.gd")


func run_tests() -> void:
	var bus := ServicesBus.new()
	add_child(bus)
	var view: Node3D = bus.make_runs_layer()
	add_child(view)
	check(not view.visible, "hidden until turned on")
	check(int(view.get("drawn").segments) == 0, "nothing drawn before a report")

	var rep := ServicesConsultant.route(Samples.house(true))
	bus.call("_apply_route", {"report": rep.to_dict()})
	var drawn: Dictionary = view.get("drawn")
	var want := 0
	var ends := 0
	for s: String in ServicesRates.SYSTEMS:
		for line: Array in rep.routes(s):
			want += line.size() - 1
			ends += 1
	check(want > 0 and int(drawn.segments) == want, "every route segment drawn: %d of %d" % [int(drawn.segments), want])
	check(int(drawn.ends) == ends, "a dot at every point fed")
	check(int(drawn.sources) == 4, "a block at the four plant units (lighting and heating share): %d" % int(drawn.sources))
	var mi := view.get_node("Runs") as MeshInstance3D
	var colours := {}
	for i in mi.mesh.get_surface_count():
		colours[(mi.mesh.surface_get_material(i) as StandardMaterial3D).albedo_color.to_html()] = true
	check(colours.size() == ServicesRates.SYSTEMS.size(), "one colour per system: %d" % colours.size())

	bus.toggle_runs()
	check(bus.runs_on and view.visible, "Service runs on shows it")
	bus.set_runs(false)
	check(not view.visible, "and off hides it")

	bus.call("_apply_route", {"report": ServicesConsultant.route(Samples.house(false)).to_dict()})
	check(int(view.get("drawn").segments) > 0, "redrawn for a new report")
	view.queue_free()
	bus.queue_free()
