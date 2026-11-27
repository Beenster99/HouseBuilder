extends ModuleTest
## WallJoins: walls meet cleanly. At a corner one runs on by half the other's thickness and
## the other stops at its face; a wall ending on another's side stops at that face; walls
## carrying straight on just meet.
##   tools/run_tests.sh design

const C := preload("res://modules/building/api/building_commands.gd")


func run_tests() -> void:
	var m := BuildingModel.new()
	var w := func(a: Vector2, b: Vector2) -> String:
		m.apply(C.place_part("wall_loadbearing", 0, {"a": [a.x, 0, a.y], "b": [b.x, 0, b.y]}, "masonry"))
		return str(m.parts.keys()[-1])
	# An L corner, a tee on the long wall, and a straight run.
	var w1: String = w.call(Vector2(0, 0), Vector2(6, 0))
	var w2: String = w.call(Vector2(0, 0), Vector2(0, 4))
	var w3: String = w.call(Vector2(3, 0), Vector2(3, 4))
	var w4: String = w.call(Vector2(0, 4), Vector2(0, 8))
	var j := WallJoins.new(m)
	var t := j.thickness(w1)
	check(t > 0.05, "walls have a thickness: %.2f" % t)
	check(is_equal_approx(j.ends(w1).x, t / 2.0) and is_equal_approx(j.ends(w2).x, -t / 2.0),
			"at the corner one runs on over the other's end, the other stops at its face: %s %s" % [j.ends(w1), j.ends(w2)])
	check(is_equal_approx(j.ends(w3).x, -t / 2.0), "a wall ending on another's side stops at its face: %s" % j.ends(w3))
	check(is_zero_approx(j.ends(w1).y) and is_zero_approx(j.ends(w3).y), "free ends stay where they are")
	check(is_zero_approx(j.ends(w2).y) and is_zero_approx(j.ends(w4).x), "walls carrying straight on just meet")
	check(w3 in j.neighbours(w1) and w2 in j.neighbours(w1) and not w4 in j.neighbours(w1), "a wall knows which walls join it")
	# Three ends at a point, two of them in a straight line: the third is a tee against them.
	var w5: String = w.call(Vector2(10, 0), Vector2(14, 0))
	var w6: String = w.call(Vector2(14, 0), Vector2(18, 0))
	var w7: String = w.call(Vector2(14, 0), Vector2(14, 3))
	check(is_zero_approx(j.ends(w5).y) and is_zero_approx(j.ends(w6).x) and is_equal_approx(j.ends(w7).x, -t / 2.0),
			"a tee made of three ends: the straight pair meet, the third stops at their face")
	# Moving a wall redraws its neighbours' joins.
	m.apply(C.move([w2], Vector3(1, 0, 0)))
	check(is_zero_approx(j.ends(w1).x), "a wall moved away leaves its neighbour's end free")
