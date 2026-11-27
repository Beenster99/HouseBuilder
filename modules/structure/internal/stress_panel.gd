extends VBoxContainer
## The Engineer view's panel in the design room: the stress test verdict, how each
## scenario went, what failed and what to try, a colour key, the Stress test button and
## Design structure, with what the engineer last changed. The live version (the design
## room's always-open window) has no title of its own, says when the host is checking, and
## has the switch that lets the engineer place supports by itself as the crew designs.

const WIDTH := 320

var _bus: Node
var _summary: Label
var _scenarios: Label
var _notes: Label
var _said: Label
var _title: Control
var _status: Label
var _auto: CheckButton


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_constant_override("separation", 6)
	_title = BsxTheme.title("Structural engineer", 20)
	add_child(_title)
	_status = _wrap_label()
	_status.add_theme_color_override("font_color", BsxTheme.MUTED)
	_status.visible = false
	add_child(_status)
	_summary = _wrap_label()
	add_child(_summary)
	_scenarios = _wrap_label()
	add_child(_scenarios)
	_notes = _wrap_label()
	_notes.add_theme_color_override("font_color", BsxTheme.MUTED)
	add_child(_notes)
	add_child(_key())
	var row := HBoxContainer.new()
	add_child(row)
	var run := BsxTheme.button("Stress test", func() -> void: _bus.run_stress_test())
	run.custom_minimum_size = Vector2(150, 36)
	row.add_child(run)
	var fix := BsxTheme.button("Design structure", func() -> void: _bus.design_structure())
	fix.custom_minimum_size = Vector2(150, 36)
	fix.tooltip_text = "The engineer adds columns, beams and footings and upsizes what fails, as one undoable edit"
	row.add_child(fix)
	_auto = CheckButton.new()
	_auto.text = "Engineer builds as you design"
	_auto.tooltip_text = "The engineer adds and upsizes columns, beams and footings by itself whenever the building fails"
	_auto.visible = false
	_auto.toggled.connect(func(on: bool) -> void:
		if _bus and on != bool(_bus.live_engineer):
			_bus.set_live_engineer(on))
	add_child(_auto)
	_said = _wrap_label()
	add_child(_said)


func bind(bus: Node, live: bool = false) -> void:
	_bus = bus
	if live:
		_title.visible = false
		_status.visible = true
		_auto.visible = true
		_auto.set_pressed_no_signal(bool(bus.live_engineer))
		bus.live_engineer_changed.connect(_on_engineer)
		bus.checking_changed.connect(_on_checking)
		bus.engineer_placed.connect(func(_left: int) -> void: _on_checking(false))
		_on_checking(bus.is_checking())
	bus.report_changed.connect(_show)
	bus.design_done.connect(func(notes: PackedStringArray) -> void:
		if is_instance_valid(_said):
			_said.text = "\n".join(notes))
	_show(bus.last_report())


func _on_engineer(on: bool) -> void:
	_auto.set_pressed_no_signal(on)


func _on_checking(busy: bool) -> void:
	var placing: int = _bus.pending_placements()
	if busy:
		_status.text = "Checking the structure..."
	elif placing > 0:
		_status.text = "The engineer is placing %d more %s..." % [placing, "part" if placing == 1 else "parts"]
	else:
		_status.text = "Checked live as you design."


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
