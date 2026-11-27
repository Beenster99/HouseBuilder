extends ModuleTest

const C := preload("res://modules/building/api/building_commands.gd")
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
			if (f[1] as Vector3).y < 0.1:
				continue  # the slopes' ridge, not the gable ends' apexes
			for p: Vector3 in f[0]:
				if is_equal_approx(p.y, y) and not pts.any(func(q: Vector3) -> bool: return q.is_equal_approx(p)):
					pts.append(p)
		return pts
	var gable := RoofShape.faces(o, 45.0, "gable", RoofShape.EAVE)
	check(gable.size() == 7 and is_equal_approx(top.call(gable), 2.0), "a gable: 2 slopes, 2 ends, 2 soffits, ceiling, ridge 2 m up at 45° over 4 m: %.2f" % top.call(gable))
	var rg: Array = ridge.call(gable)
	check(rg.size() == 2 and is_equal_approx(absf((rg[0] as Vector3).x - (rg[1] as Vector3).x), 8.0 + 2.0 * RoofShape.EAVE) and is_equal_approx((rg[0] as Vector3).z, 2.0),
			"its ridge runs the long way, down the middle: %s" % str(rg))
	var hip := RoofShape.faces(o, 45.0, "hip", RoofShape.EAVE)
	var rh: Array = ridge.call(hip)
	check(rh.size() == 2 and is_equal_approx(absf((rh[0] as Vector3).x - (rh[1] as Vector3).x), 4.0), "a hip's ends slope in, so its ridge is shorter: %s" % str(rh))
	var square := RoofShape.faces([[0, 0], [4, 0], [4, 4], [0, 4]], 45.0, "hip", RoofShape.EAVE)
	check((ridge.call(square) as Array).size() == 1, "on a square a hip roof comes to a point")
	var mono := RoofShape.faces(o, 30.0, "mono", RoofShape.EAVE)
	check(is_equal_approx(top.call(mono), (4.0 + RoofShape.EAVE) * tan(deg_to_rad(30.0))), "a mono-pitch rises across the short way: %.2f" % top.call(mono))
	check(is_equal_approx(RoofShape.rise(o, 45.0, "gable"), 2.0) and is_equal_approx(RoofShape.rise(o, 30.0, "mono"), 4.0 * tan(deg_to_rad(30.0))), "rise() agrees (at the wall line)")
	# Eaves: the slopes overhang the walls on every side, carrying on down at the pitch.
	for form: String in RoofShape.FORMS:
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for f: Array in RoofShape.faces(o, 45.0, form, RoofShape.EAVE):
			for p: Vector3 in f[0]:
				lo = lo.min(p)
				hi = hi.max(p)
		var e := RoofShape.EAVE
		check(lo.is_equal_approx(Vector3(-e, -e, -e)) and is_equal_approx(hi.x, 8.0 + e) and is_equal_approx(hi.z, 4.0 + e),
				"a %s roof overhangs the walls by %.2f m all round, eaves below the wall tops: %s .. %s" % [form, e, lo, hi])
	check(RoofShape.faces(o, 45.0, "gable").size() == 5, "by default no eave and no soffits (stops at the walls)")
	var ups := gable.filter(func(f: Array) -> bool: return (f[1] as Vector3).y > 0.1).size()
	check(ups == 2, "both gable slopes face up and out")
	var turned := RoofShape.faces([[0, 0], [3, 0], [3, 7], [0, 7]], 45.0, "gable", RoofShape.EAVE)
	var rt: Array = ridge.call(turned)
	check(rt.size() == 2 and is_equal_approx(absf((rt[0] as Vector3).z - (rt[1] as Vector3).z), 7.0 + 2.0 * RoofShape.EAVE), "the ridge follows the longer side whichever way it lies")

	# T, L and cross plans: wings that meet in valleys, one roof surface over every point.
	var t_plan := [[0, 0], [12, 0], [12, 4], [8, 4], [8, 10], [4, 10], [4, 4], [0, 4]]
	check(RoofShape.wings(t_plan, "gable").size() == 2, "a T-shaped roof is two wings: %d" % RoofShape.wings(t_plan, "gable").size())
	var tn := tan(deg_to_rad(45.0))
	var t_faces := RoofShape.faces(t_plan, 45.0, "gable", RoofShape.EAVE)
	# Over the bar's middle, the stem's ridge has run on to meet the bar's: 2 m up.
	check(absf(_surface(t_faces, Vector2(6, 3)) - 2.0 * tn) < 0.01 and absf(_surface(t_faces, Vector2(4.5, 3)) - tn) < 0.01,
			"a T's wing runs on into the main roof, meeting it in valleys: %.2f, %.2f" % [_surface(t_faces, Vector2(6, 3)), _surface(t_faces, Vector2(4.5, 3))])
	check(_one_surface(t_faces, t_plan), "a T has one roof surface over every point, with no gable end showing inside")
	var l_plan := [[0, 0], [8, 0], [8, 4], [4, 4], [4, 9], [0, 9]]
	check(_one_surface(RoofShape.faces(l_plan, 40.0, "gable", RoofShape.EAVE), l_plan), "so does an L")
	check(_one_surface(RoofShape.faces(t_plan, 35.0, "hip", RoofShape.EAVE), t_plan), "and a hipped T")
	var plus := [[4, 0], [8, 0], [8, 4], [12, 4], [12, 8], [8, 8], [8, 12], [4, 12], [4, 8], [0, 8], [0, 4], [4, 4]]
	check(_one_surface(RoofShape.faces(plus, 45.0, "gable", RoofShape.EAVE), plus), "and a cross with four gables")
	# Two roofs drawn separately, a bar and a wing against it, join the same way.
	var bm := BuildingModel.new()
	bm.apply(C.place_part("roof_pitched", 0, {"outline": C.rect(0, 0, 12, 4), "y": 3.0, "pitch": 45.0}, "timber"))
	bm.apply(C.place_part("roof_pitched", 0, {"outline": C.rect(4, 4, 4, 6), "y": 3.0, "pitch": 45.0}, "timber"))
	var both: Array = []
	for rid: String in RoofShape.roof_parts(bm, 0):
		both.append_array(RoofShape.part_faces(bm, rid))
	check(RoofShape.roof_parts(bm, 0).size() == 2 and _one_surface(both, t_plan) and absf(_surface(both, Vector2(6, 3)) - 2.0 * tn) < 0.01,
			"two roofs drawn as a T join up as one")

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


## The heights of the faces facing up (or down, `up` false) over plan point p.
static func _hits(faces: Array, p: Vector2, up: bool) -> Array:
	var out: Array = []
	for f: Array in faces:
		var n: Vector3 = f[1]
		if (n.y > 0.05) != up or (not up and n.y > -0.05):
			continue
		var q: Array = f[0]
		for k in range(1, q.size() - 1):
			var a: Vector3 = q[0]
			var b: Vector3 = q[k]
			var c: Vector3 = q[k + 1]
			var bc := Geometry2D.point_is_inside_triangle(p, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z))
			if bc:
				# Height of the plane through a, b, c at p.
				var nn := (b - a).cross(c - a)
				out.append(a.y - (nn.x * (p.x - a.x) + nn.z * (p.y - a.z)) / nn.y)
				break
	return out


## The roof's height over plan point p (the highest face facing up).
static func _surface(faces: Array, p: Vector2) -> float:
	var h := -INF
	for y: float in _hits(faces, p, true):
		h = maxf(h, y)
	return h


## Over every sample point inside the plan: exactly one face looking up and one ceiling.
func _one_surface(faces: Array, plan: Array) -> bool:
	var poly := PackedVector2Array()
	for c: Array in plan:
		poly.append(Vector2(float(c[0]), float(c[1])))
	var bad := 0
	for i in 60:
		for j in 60:
			var p := Vector2(-1.0 + i * 0.237 + 0.011, -1.0 + j * 0.237 + 0.017)
			if not Geometry2D.is_point_in_polygon(p, poly):
				continue
			var ups := _hits(faces, p, true).size()
			var downs := _hits(faces, p, false).filter(func(y: float) -> bool: return absf(y) < 0.001).size()
			if ups != 1 or downs != 1:
				if bad < 3:
					print("    at %s: %d surfaces, %d ceilings" % [p, ups, downs])
				bad += 1
	return bad == 0
