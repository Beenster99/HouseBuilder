extends VBoxContainer
## The M&E view's panel in the design room: the consultant's verdict, each system's length
## and cost, what is wrong and why, and buttons to route again or let it design the rest.

const WIDTH := 320

var _bus: Node
var _summary: Label
var _systems: Label
var _notes: Label
var _said: Label


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_constant_override("separation", 6)
	add_child(BsxTheme.title("M&E consultant", 20))
	_summary = _wrap_label()
	add_child(_summary)
	_systems = _wrap_label()
	add_child(_systems)
	_notes = _wrap_label()
	_notes.add_theme_color_override("font_color", BsxTheme.MUTED)
	add_child(_notes)
	var row := HBoxContainer.new()
	add_child(row)
	var route := BsxTheme.button("Route services", func() -> void: _bus.run_consultant())
	route.custom_minimum_size = Vector2(150, 36)
	row.add_child(route)
	var design := BsxTheme.button("Design services", func() -> void: _bus.design_services())
	design.custom_minimum_size = Vector2(150, 36)
	row.add_child(design)
	_said = _wrap_label()
	add_child(_said)


func bind(bus: Node) -> void:
	_bus = bus
	bus.report_changed.connect(_show)
	bus.design_done.connect(func(notes: PackedStringArray) -> void: _said.text = "\n".join(notes))
	_show(bus.last_report())


func _wrap_label() -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH, 0)
	return l


func _show(report: ServicesReport) -> void:
	if report == null:
		_summary.text = "Not routed yet. Route services to see the wiring and pipework."
		_systems.text = ""
		_notes.text = ""
		return
	_summary.text = report.summary
	var lines := PackedStringArray()
	for s in ServicesRates.SYSTEMS:
		var sys := report.system(s)
		if not sys.is_empty():
			lines.append("%s: %.1f m, %s" % [ServicesRates.label(s), float(sys.length), ServicesConsultant._money(float(sys.cost))])
	_systems.text = "\n".join(lines)
	var rest := PackedStringArray()
	for n in report.notes.slice(1):
		if not n.begins_with(ServicesRates.label("power") + ":") and not n.contains(" m of "):
			rest.append(n)
	_notes.text = "\n".join(rest)
