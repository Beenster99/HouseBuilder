extends ModuleTest
## Pitched roofs: RoofShape's faces for gable, hip and mono-pitch over an outline (ridge along
## the longer side, at the right height for the pitch), and the Roof tool placing them.
##   tools/run_tests.sh design


func run_tests() -> void:
	var o := [[0, 0], [8, 0], [8, 4], [0, 4]]
	var top := func(faces: Array) -> float:
		var y := 0.0
		for f: Array in faces:
			for p: Vector3 in f[0]:
				y = maxf(y, p.y)
		return y
	var ridge := func(faces: Array) -> Array:
		var pts: Array = []
		var y: float = top.call(faces)
		for f: Array in faces:
			for p: Vector3 in f[0]:
				if is_equal_approx(p.y, y) and not pts.any(func(q: Vector3) -> bool: return q.is_equal_approx(p)):
					pts.append(p)
		return pts
	var gable := RoofShape.faces(o, 45.0, "gable")
	check(gable.size() == 5 and is_equal_approx(top.call(gable), 2.0), "a gable: 2 slopes, 2 ends, underside, ridge 2 m up at 45° over 4 m: %.2f" % top.call(gable))
	var rg: Array = ridge.call(gable)
	check(rg.size() == 2 and is_equal_approx(absf((rg[0] as Vector3).x - (rg[1] as Vector3).x), 8.0) and is_equal_approx((rg[0] as Vector3).z, 2.0),
			"its ridge runs the long way, down the middle: %s" % str(rg))
	var hip := RoofShape.faces(o, 45.0, "hip")
	var rh: Array = ridge.call(hip)
	check(rh.size() == 2 and is_equal_approx(absf((rh[0] as Vector3).x - (rh[1] as Vector3).x), 4.0), "a hip's ends slope in, so its ridge is shorter: %s" % str(rh))
	var square := RoofShape.faces([[0, 0], [4, 0], [4, 4], [0, 4]], 45.0, "hip")
	check((ridge.call(square) as Array).size() == 1, "on a square a hip roof comes to a point")
	var mono := RoofShape.faces(o, 30.0, "mono")
	check(is_equal_approx(top.call(mono), 4.0 * tan(deg_to_rad(30.0))), "a mono-pitch rises across the short way: %.2f" % top.call(mono))
	check(is_equal_approx(RoofShape.rise(o, 45.0, "gable"), 2.0) and is_equal_approx(RoofShape.rise(o, 30.0, "mono"), top.call(mono)), "rise() agrees")
	var ups := gable.filter(func(f: Array) -> bool: return (f[1] as Vector3).y > 0.1).size()
	check(ups == 2, "both gable slopes face up and out")
	var turned := RoofShape.faces([[0, 0], [3, 0], [3, 7], [0, 7]], 45.0, "gable")
	var rt: Array = ridge.call(turned)
	check(rt.size() == 2 and is_equal_approx(absf((rt[0] as Vector3).z - (rt[1] as Vector3).z), 7.0), "the ridge follows the longer side whichever way it lies")

	# The Roof tool: a gable at the pitch set.
	var building := Modules.bus("building") as BuildingBus
	building.reset_data()
	var s := DesignSession.new()
	add_child(s)
	s.setup(Modules.bus("multiplayer") as MultiplayerBus, building.model, building.sync)
	check(Array(s.roof_forms()) == ["flat", "gable", "hip", "mono"], "the Roof tool offers flat, gable, hip and mono-pitch: %s" % str(s.roof_forms()))
	s.set_tool("roof")
	s.roof_form = "gable"
	s.roof_pitch = 40.0
	s.press(Vector3(0, 0, 0))
	s.press(Vector3(6, 0, 4))
	var roofs := building.model.parts_of_family("roof")
	check(roofs.size() == 1 and str(building.model.parts[roofs[0]].kind) == "roof_pitched" and is_equal_approx(float(building.model.parts[roofs[0]].pitch), 40.0),
			"it places a pitched roof at 40°")
	s.roof_form = "hip"
	s.press(Vector3(10, 0, 0))
	s.press(Vector3(16, 0, 4))
	check(Array(building.model.parts_of_family("roof")).any(func(r: String) -> bool: return str(building.model.parts[r].kind) == "roof_hip"), "and a hipped one")
	s.teardown()
	s.queue_free()
	building.reset_data()
