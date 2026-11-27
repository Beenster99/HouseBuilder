extends ModuleTest
## Walk-inside to look round a finished building (the town's): WalkBus.open(copy, parent,
## spawn, null, {"mode": "view"}). Walk, fly and swap the look as usual; nothing can be
## changed: no Tab, pick up, push, edit, remove, door or paste, and the model never changes.
##   tools/run_tests.sh walk

const WalkTest := preload("res://modules/walk/tests/test_walk.gd")
const WalkInside := preload("res://modules/walk/internal/walk_inside.gd")


func run_tests() -> void:
	var walk := Modules.bus("walk") as WalkBus
	var b := Modules.bus("building") as BuildingBus
	var house: Node = WalkTest.new()
	house.call("_house", b)
	house.free()
	await frames(2)
	var copy := BuildingModel.from_data(b.model.to_data())
	check(copy != null and copy != b.model and copy.parts.size() == b.model.parts.size(), "a stored copy of a finished building")
	var rev := copy.revision
	var v: WalkInside = walk.open(copy, self, {"at": Vector3(2.0, 0.0, 4.5), "yaw": 0.0}, null, {"mode": "view"})
	await frames(5)
	check(v != null and v.mode == "view" and walk.is_open(), "it opens to look round")
	check(v.help_text().begins_with("VIEWING") and v.help_text().contains("Q fly") and not v.help_text().contains("Tab"),
			"the help bar says VIEWING, with only the walking keys: %s" % v.help_text())

	# Aim at the back wall and try every edit.
	v.body.position = Vector3(2.0, 0.95, 3.0)
	var eye := v.body.position + Vector3(0, 0.7, 0)
	var d := Vector3(2.0, 1.5, 0.0) - eye
	v.body.rotation.y = atan2(-d.x, -d.z)
	v._pitch = atan2(d.y, Vector2(d.x, d.z).length())
	v.camera.rotation.x = v._pitch
	await _physics(3)
	check(v.aimed_part() != "", "aiming at a wall")
	for key: Key in [KEY_TAB, KEY_E, KEY_X, KEY_DELETE, KEY_F, KEY_R]:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		ev.pressed = true
		v._input(ev)
	for key: Key in [KEY_C, KEY_V, KEY_Z]:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		ev.ctrl_pressed = true
		ev.pressed = true
		v._input(ev)
	for button: MouseButton in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var mb := InputEventMouseButton.new()
		mb.button_index = button
		mb.pressed = true
		v._input(mb)
	v.click()
	await frames(3)
	check(copy.revision == rev and not v.is_palette_open() and v.holding.is_empty() and v.edit_id == "",
			"Tab, E, X, F, R, Ctrl+C/V/Z, click and the wheel change nothing")

	# Fly and swap the look as usual; Esc takes you back.
	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	q.pressed = true
	v._input(q)
	check(v.flying, "Q flies")
	await frames(1)
	check(v.help_text().contains("C down"), "and the help bar says how")
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	v._input(esc)
	await frames(2)
	check(not walk.is_open() and copy.revision == rev, "Esc takes you back; the building is as it was")


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
