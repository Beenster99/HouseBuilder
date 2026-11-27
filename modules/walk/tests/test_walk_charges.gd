extends ModuleTest
## Walk-inside in demolition: open with {"mode": "charges"} and you walk the building to put
## charges on its structure from inside (DemolitionBus.request_charge, with the point you aim
## at when demolition takes one). The wheel sets the delay; the same click again takes the
## charge off; building edits are off; firing closes the walk.
##   tools/run_tests.sh walk

const WalkTest := preload("res://modules/walk/tests/test_walk.gd")
const WalkInside := preload("res://modules/walk/internal/walk_inside.gd")


func run_tests() -> void:
	var walk := Modules.bus("walk") as WalkBus
	var b := Modules.bus("building") as BuildingBus
	var demo := Modules.bus("demolition")
	check(demo != null, "the demolition module is loaded")
	if demo == null:
		return
	var house: Node = WalkTest.new()
	house.call("_house", b)
	house.free()
	await frames(2)
	var model := b.model
	demo.call("start_from_model", model, {"open": false})
	await frames(3)
	check(bool(demo.call("is_active")), "a demolition is set up from the building")
	var v: WalkInside = walk.open(model, self, {}, null, {"mode": "charges"})
	await frames(5)
	check(v != null and v.mode == "charges", "walk-inside opens to place charges")
	var parts_before := model.parts.size()

	# Aim at a wall from inside and click: a charge on it at the delay you've set.
	var wall := ""
	for pid: String in model.parts_of_family("wall"):
		wall = pid
		break
	var we: Dictionary = model.parts[wall]
	var wa := Vector3(float(we.a[0]), 0, float(we.a[2]))
	var wb := Vector3(float(we.b[0]), 0, float(we.b[2]))
	var floor_y := model.level_elevation(model.level_of(wall))
	# Low down near one end, clear of doors and windows.
	var target := wa + (wb - wa).normalized() * 0.6 + Vector3(0, floor_y + 0.4, 0)
	v.body.position = target + _out_of(model, wall) * 2.0 + Vector3(0, -target.y + floor_y + 0.95, 0)
	_face(v, target)
	await _physics(3)
	await frames(2)
	if v.aimed_part() != wall:
		wall = v.aimed_part()
	check(wall != "" and model.catalog.family_of(str(model.parts[wall].kind)) in WalkInside.CHARGE_FAMILIES,
			"aiming at a %s" % (model.parts[wall].kind if wall != "" else "nothing"))
	v.step_delay(2)
	await frames(2)
	check(is_equal_approx(v.charge_delay, 0.5), "the wheel sets the delay: %.2f s" % v.charge_delay)
	check(v.help_text().contains("charge it at 0.50 s"), "the help bar says so: %s" % v.help_text())
	v.click()
	await frames(3)
	var charges: Dictionary = demo.get("charges")
	check(charges.has(wall) and is_equal_approx(float(charges[wall]), 0.5), "click: a charge on it at 0.5 s: %s" % charges)
	check(v._charge_marks != null and v._charge_marks.get_child_count() == 1, "marked red, with its delay")
	check(model.parts.size() == parts_before, "the building isn't edited")

	# Building edits are off: Tab, X and R do nothing.
	for key: Key in [KEY_TAB, KEY_X, KEY_R]:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		ev.pressed = true
		v._input(ev)
	await frames(2)
	check(not v.is_palette_open() and model.parts.has(wall) and v.holding.is_empty(), "Tab, X and R don't edit the building")

	# The same click again takes it off.
	v.click()
	await frames(3)
	charges = demo.get("charges")
	check(not charges.has(wall) and v._charge_marks.get_child_count() == 0, "clicked again at the same delay: the charge is off")

	# Firing closes the walk so you can watch.
	v.click()
	await frames(3)
	demo.call("request_fire")
	await frames(3)
	check(not walk.is_open(), "firing takes you back out to watch")
	demo.call("request_reset")
	await frames(2)


## The way out of a wall's face toward where you'd stand (the side away from the building's middle).
func _out_of(model: BuildingModel, wall: String) -> Vector3:
	var e: Dictionary = model.parts[wall]
	var a := Vector3(float(e.a[0]), 0, float(e.a[2]))
	var bb := Vector3(float(e.b[0]), 0, float(e.b[2]))
	var n := (bb - a).normalized().cross(Vector3.UP)
	var mid := Vector3.ZERO
	var c := 0
	for pid: String in model.parts_of_family("wall"):
		var w: Dictionary = model.parts[pid]
		mid += Vector3(float(w.a[0]), 0, float(w.a[2]))
		c += 1
	mid /= maxf(c, 1)
	# Inside: toward the middle.
	return n if n.dot(mid - (a + bb) * 0.5) > 0.0 else -n


func _face(v: WalkInside, at: Vector3) -> void:
	var eye := v.body.position + Vector3(0, 0.7, 0)
	var d := at - eye
	v.body.rotation.y = atan2(-d.x, -d.z)
	v._pitch = atan2(d.y, Vector2(d.x, d.z).length())
	v.camera.rotation.x = v._pitch


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
