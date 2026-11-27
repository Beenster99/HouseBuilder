extends VBoxContainer
## The design room's always-on Feasibility window: the consultant's live verdict on the
## design (structure, services, contract fit and cost), redone a moment after each edit.

const WIDTH := 300
const OK := Color(0.45, 0.85, 0.55)
const BAD := Color(1.0, 0.5, 0.4)

var _bus: Node
var _verdict: Label
var _areas: Label
var _issues: Label


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_constant_override("separation", 4)
	_verdict = _wrap()
	add_child(_verdict)
	_areas = _wrap()
	add_child(_areas)
	_issues = _wrap()
	_issues.add_theme_color_override("font_color", BsxTheme.MUTED)
	add_child(_issues)


func bind(bus: Node) -> void:
	_bus = bus
	bus.review_done.connect(_show)
	if bus.last_review().is_empty():
		_verdict.text = "Assessing the design..."
		bus.call("_schedule")
	else:
		_show(bus.last_review())


func _wrap() -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH, 0)
	return l


func _show(r: Dictionary) -> void:
	_verdict.text = str(r.get("summary", ""))
	_verdict.add_theme_color_override("font_color", OK if bool(r.get("feasible", false)) else BAD)
	var lines := PackedStringArray()
	var names := {"structure": "Structure", "services": "Services", "requirements": "Brief", "budget": "Cost"}
	for a: String in ["structure", "services", "requirements", "budget"]:
		var area: Dictionary = r.get("areas", {}).get(a, {})
		if not area.is_empty():
			lines.append("%s %s: %s" % ["✓" if bool(area.ok) else "✗", names[a], str(area.summary)])
	_areas.text = "\n".join(lines)
	var issues := PackedStringArray()
	for i: Dictionary in (r.get("issues", []) as Array).slice(0, 5):
		issues.append(("- %s %s" % [i.text, i.tip]).strip_edges())
	_issues.text = "\n".join(issues)
