extends ModuleTest
## Service runs (cables and pipes from Route services) draw as thin tubes centred on their
## line, not as beams hanging below it.
##   tools/run_tests.sh design

const C := preload("res://modules/building/api/building_commands.gd")
const DesignView := preload("res://modules/design/internal/room/design_view.gd")


func run_tests() -> void:
	var m := BuildingModel.new()
	var sizes := {"cable_power": 0.03, "pipe_cold": 0.05, "pipe_waste": 0.1}
	var z := 0.0
	for k: String in sizes:
		m.apply(C.place_part(k, 0, {"a": [0, 2.0, z], "b": [4, 2.0, z]}, ""))
		z += 2.0
	var v: Node3D = DesignView.new()
	add_child(v)
	v.call("bind", m)
	await frames(3)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in v.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var bb := mi.global_transform * mi.mesh.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	check(not first, "the runs are drawn")
	check(absf(box.end.y - 2.05) < 0.01 and absf(box.position.y - 1.95) < 0.01,
			"tubes are centred on their line, the widest (waste) 0.1 m across: %s" % box)
	for k: String in sizes:
		check(is_equal_approx(DesignView.tube_dia(k), float(sizes[k])), "%s is %.2f m across" % [k, sizes[k]])
	v.queue_free()
