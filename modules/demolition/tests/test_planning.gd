extends ModuleTest
## Easier charge planning: a whole plan at once, charge sizes, auto-sequence presets that
## bring the building down a chosen way, and the charges panel's timeline groups.
##   tools/run_tests.sh demolition

const DemoOffice := preload("res://modules/demolition/internal/demo_office.gd")


func run_tests() -> void:
	var bus := Modules.bus("demolition") as DemolitionBus
	bus.start_demolition(DemoOffice.parts(), "Office", {"open": false})

	# Auto sequences: the lowest storey's supports, timed the chosen way.
	var implode := DemolitionRules.sequence(bus.parts, "implode")
	check(implode.size() >= 4 and implode.size() <= DemolitionBus.MAX_CHARGES, "implode charges the lowest storey: %d" % implode.size())
	var lowest := INF
	for id: String in implode:
		lowest = minf(lowest, (bus.by_id[id].aabb as AABB).position.y)
	var all_low := true
	var centre := Vector3.ZERO
	for p: Dictionary in bus.parts:
		centre += (p.aabb as AABB).get_center()
	centre /= bus.parts.size()
	var first_d := INF
	var last_d := -INF
	var first_t := INF
	var last_t := -INF
	for id: String in implode:
		all_low = all_low and (bus.by_id[id].aabb as AABB).position.y < lowest + 0.5
		var c := (bus.by_id[id].aabb as AABB).get_center()
		var dist := Vector2(c.x - centre.x, c.z - centre.z).length()
		if float(implode[id]) < first_t or (float(implode[id]) == first_t and dist < first_d):
			first_t = implode[id]
			first_d = dist
		if float(implode[id]) > last_t:
			last_t = implode[id]
			last_d = dist
	check(all_low and first_d < last_d and last_t > first_t, "middle first, the outside after")
	var north := DemolitionRules.sequence(bus.parts, "fall_north")
	var z_first := INF
	var z_last := -INF
	for id: String in north:
		var z := (bus.by_id[id].aabb as AABB).get_center().z
		if is_zero_approx(float(north[id])):
			z_first = minf(z_first, z)
		if is_equal_approx(float(north[id]), DemolitionRules.SEQUENCE_SPAN):
			z_last = maxf(z_last, z)
	check(z_first < z_last, "falling north, the north side goes first")

	# A whole plan at once, sizes kept.
	var plan := {}
	for id: String in north:
		plan[id] = {"delay": north[id], "size": 2}
	bus.request_plan(plan)
	check(bus.charges.size() == north.size() and bus.size_of(north.keys()[0]) == 2 and bus.power_of(north.keys()[0]) > 1.0,
			"the plan goes on in one go, heavy charges")
	bus.request_plan({"pad_0_0": 0.0, "nothing": 0.5})
	check(bus.charges.is_empty(), "foundations and unknown parts are left out of a plan")

	# The panel: presets, groups, moving a group, clearing.
	var view: Node3D = load("res://modules/demolition/internal/demolition_view.tscn").instantiate()
	add_child(view)
	await frames(2)
	check(view.find_child("ChargesPanel", true, false) != null, "a charges panel")
	view.apply_sequence("implode")
	await frames(1)
	var gs: Array = view.groups()
	check(gs.size() >= 2 and bus.charges.size() == implode.size(), "the preset fills the timeline: %d groups" % gs.size())
	check(view._preview, "and shows the fall")
	var d0: float = gs[0][0]
	var n0: int = (gs[0][1] as Array).size()
	view.shift_group(d0, 0.25)
	await frames(1)
	var moved := 0
	for id: String in gs[0][1]:
		if is_equal_approx(float(bus.charges.get(id, -1.0)), d0 + 0.25):
			moved += 1
	check(moved == n0, "a group moves later as one")
	view.remove_group(float(view.groups()[0][0]))
	await frames(1)
	check(bus.charges.size() < implode.size(), "a group comes off")
	# The career: locked sizes and presets grey out; a blast consultant shows the debris.
	var career := _Career.new()
	view.career = career
	view._set_size(2)
	view._refresh_panel()
	var sizes: Array = view._size_buttons
	check(sizes[2].disabled and not sizes[1].disabled and view._size == 1, "a locked heavy charge greys out and can't be picked")
	check(view._sequence.is_item_disabled(1), "locked auto sequences grey out")
	var before: int = bus.charges.size()
	view.apply_sequence("fall_north")
	await frames(1)
	check(bus.charges.size() == before, "a locked preset does nothing")
	view._set_preview(true)
	check(view.debris_zones().is_empty(), "no debris preview without a blast consultant")
	career.consultant = true
	view._set_preview(true)
	var zones: Array = view.debris_zones()
	check(zones.size() == bus.charges.size() and zones.size() > 0 and float(zones[0].radius) > 1.0,
			"the blast consultant shows each charge's debris zone: %s" % str(zones.slice(0, 1)))
	check(DemolitionRules.throw_reach(1.6, 1.0) > DemolitionRules.throw_reach(0.6, 1.0), "heavier charges throw further")
	view.career = null
	view._set_size(0)
	bus.request_plan({})
	await frames(1)
	check(bus.charges.is_empty() and view.groups().is_empty(), "clear all")
	view.queue_free()
	await frames(1)
	bus.apply_net_snapshot({})


class _Career:
	var consultant := false

	func locked_tier(id: String) -> int:
		return {"gear:charge_heavy": 4, "gear:delay_presets": 3}.get(id, 0)

	func effect(name: String, fallback := 0.0) -> float:
		return 1.0 if name == "debris_preview" and consultant else fallback
