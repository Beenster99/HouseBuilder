extends VBoxContainer
## The Engineer view's panel in the design room: the stress test verdict, how each
## scenario went, what failed and what to try, a colour key and the Stress test button.

const WIDTH := 320

var _bus: Node
var _summary: Label
var _scenarios: Label
var _notes: Label


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_constant_override("separation", 6)
	add_child(BsxTheme.title("Structural engineer", 20))
	_summary = _wrap_label()
	add_child(_summary)
	_scenarios = _wrap_label()
	add_child(_scenarios)
	_notes = _wrap_label()
	_notes.add_theme_color_override("font_color", BsxTheme.MUTED)
	add_child(_notes)
	add_child(_key())
	var run := BsxTheme.button("Stress test", func() -> void: _bus.run_stress_test())
	run.custom_minimum_size = Vector2(150, 36)
	add_child(run)


func bind(bus: Node) -> void:
	_bus = bus
	bus.report_changed.connect(_show)
	_show(bus.last_report())


func _wrap_label() -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH, 0)
	return l


func _key() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for pair: Array in [[StructureBus.GREEN, "Below 70%"], [StructureBus.AMBER, "70-100%"], [StructureBus.RED, "Failed"]]:
		var swatch := ColorRect.new()
		swatch.color = pair[0]
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var l := Label.new()
		l.text = pair[1]
		row.add_child(l)
	return row


func _show(report: StructureReport) -> void:
	if not is_instance_valid(_summary):
		return
	if report == null:
		_summary.text = "Not tested yet. Press Stress test to check the building under normal use, a storm and an earthquake."
		_scenarios.text = ""
		_notes.text = ""
		return
	_summary.text = report.summary
	var lines := PackedStringArray()
	for r in report.results:
		var worst: Dictionary = r.worst()
		lines.append("%s: %s, worst %d%%" % [r.scenario_title, "passes" if r.passed() else "fails",
				roundi(minf(float(worst.u), 9.99) * 100.0)])
	_scenarios.text = "\n".join(lines)
	_notes.text = "\n".join(report.notes)
