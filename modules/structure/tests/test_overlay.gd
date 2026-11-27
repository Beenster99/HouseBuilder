extends ModuleTest
## The Engineer view in the design room: the Stress test button and overlay register with
## the design bus, parts are coloured by their worst utilisation, and the panel follows
## each new report.
##   tools/run_tests.sh structure

const Samples := preload("res://modules/structure/tests/samples.gd")


## Stands in for the design bus: records what was registered and refreshed.
class FakeDesign:
	extends Node
	var actions := {}
	var overlays := {}
	var refreshed: Array[String] = []
	var tags := {}
	var focused: Array[String] = []

	func set_part_tags(source: String, t: Dictionary) -> void:
		tags[source] = t

	func focus_part(id: String) -> void:
		focused.append(id)

	func register_action(id: String, label: String, press: Callable, order: int = 50) -> void:
		actions[id] = {"label": label, "press": press, "order": order}

	func unregister_action(id: String) -> void:
		actions.erase(id)

	func register_overlay(id: String, label: String, tints: Callable, panel: Callable = Callable(), order: int = 50) -> void:
		overlays[id] = {"label": label, "tints": tints, "panel": panel, "order": order}

	func unregister_overlay(id: String) -> void:
		overlays.erase(id)

	func refresh_overlay(id: String) -> void:
		refreshed.append(id)


func run_tests() -> void:
	await _real_design_room()
	_tints_and_panel()


func _real_design_room() -> void:
	await get_tree().process_frame
	var design := Modules.bus("design")
	if design == null or not Flags.is_on(StructureBus.STRESS_TEST_FLAG):
		check(true, "design room not loaded; nothing to hook")
		return
	check(design.actions.has(StructureBus.ACTION), "Stress test button on the design room's top bar")
	check(design.overlays.has(StructureBus.OVERLAY), "Engineer view in the View picker")
	check(str(design.overlays[StructureBus.OVERLAY].label) == "Engineer", "named Engineer")
	if Flags.is_on(StructureBus.LIVE_FLAG) and design.has_method("register_panel"):
		check(design.panels.has(StructureBus.LIVE_PANEL), "the live engineer window is always open")
		check(not (design.overlays[StructureBus.OVERLAY].panel as Callable).is_valid(), "so the Engineer view adds no second panel")


func _tints_and_panel() -> void:
	var bus := StructureBus.new()
	var design := FakeDesign.new()
	bus.hook_design(design)
	check(design.actions[StructureBus.ACTION].label == "Stress test", "action registered")
	check(design.actions[StructureBus.DESIGN_ACTION].label == "Design structure", "Design structure next to it")
	var tints: Callable = design.overlays[StructureBus.OVERLAY].tints
	check((tints.call(null) as Dictionary).is_empty(), "no colours before the first test")
	var panel: Control = (design.overlays[StructureBus.OVERLAY].panel as Callable).call()
	check(panel != null, "panel made")
	check(_text(panel).contains("Not tested yet"), "panel asks for a test first")

	var h := Samples.model_house()
	var good := StructureBuilding.stress_test(h.model)
	bus.apply_net_snapshot({"report": good.to_dict()})
	check(design.refreshed == [StructureBus.OVERLAY], "a new report refreshes the view")
	var colours: Dictionary = tints.call(h.model)
	var front := str(h.ids.front_0)
	check(colours.has(front), "the front wall is coloured")
	check(colours.get(front) == StructureBus.colour_for(good.part_envelope(front)), "coloured by its worst utilisation")
	var reds := 0
	for id: String in colours:
		if colours[id] == StructureBus.RED:
			reds += 1
	check(reds == good.failed_parts().size(), "red exactly where parts fail: %d" % reds)
	check(_text(panel).contains("Normal use") or _text(panel).contains("passes") or _text(panel).contains("fails"),
			"panel lists the scenarios: %s" % _text(panel))

	# Take the ground-floor walls away: the floor and roof above must turn red.
	var bad := StructureBuilding.stress_test(h.model)
	var removed := PackedStringArray()
	for id: String in h.ids:
		if id.ends_with("_0") and not id.begins_with("window"):
			removed.append(str(h.ids[id]))
	check(not removed.is_empty(), "the sample house has ground-floor walls")
	if not removed.is_empty():
		bad = StructureSolver.stress_test(StructureBuilding.graph(h.model, removed))
		bus.apply_net_snapshot({"report": bad.to_dict()})
		colours = tints.call(h.model)
		check(colours.values().has(StructureBus.RED), "no ground-floor walls: the view shows red")
		check(_text(panel).contains("fails"), "panel says it fails")
		var tags: Dictionary = design.tags.get(StructureBus.TAGS, {})
		check(not tags.is_empty() and tags.size() == bad.failed_parts().size(), "the design tags each failing part by number (%d)" % tags.size())
		var link := _first_link(panel)
		check(link != null, "a note naming a part is a link")
		if link:
			link.pressed.emit()
			check(design.focused == [str(link.get_meta("part_id"))], "pressing it shows that part on the design")
		check(str(bad.summary).contains("floor"), "and parts are named with their floor: %s" % bad.summary)

	check(StructureBus.colour_for(0.2) == StructureBus.GREEN, "low is green")
	check(StructureBus.colour_for(0.85) == StructureBus.AMBER, "near capacity is amber")
	check(StructureBus.colour_for(1.4) == StructureBus.RED, "over capacity is red")
	panel.free()
	design.free()
	bus.free()


func _first_link(c: Node) -> Button:
	if c is Button and c.has_meta("part_id"):
		return c
	for k in c.get_children():
		var b := _first_link(k)
		if b:
			return b
	return null


func _text(c: Node) -> String:
	var out := ""
	if c is Label:
		out += (c as Label).text + "\n"
	elif c is Button:
		out += (c as Button).text + "\n"
	for k in c.get_children():
		out += _text(k)
	return out
