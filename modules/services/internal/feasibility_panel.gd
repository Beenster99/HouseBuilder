extends VBoxContainer
## The design room's always-on Feasibility window, made to be read at a glance: one verdict
## chip, then a row per goal (structure, services, brief, cost) with a coloured bar and a
## short figure. The issues and what to do stay folded under Details until asked for.
## Redone a moment after each edit (ServicesBus.review_done).

const WIDTH := 280
const FONT := 11
const GOOD := Color(0.36, 0.8, 0.47)
const WARN := Color(0.98, 0.72, 0.25)
const BAD := Color(0.95, 0.36, 0.3)
## Text, idle and track colours come from the look the panel sits in (BsxTheme.col): the
## classic dark screen or the pencil UI. Only the status colours are fixed.
## Longest issue line shown in Details (characters).
const LINE_MAX := 96
const ISSUES_SHOWN := 5


## A thin bar: fill 0..1 of the track in a colour, with an optional goal mark.
class Bar extends Control:
	var fill := 0.0
	var colour := Color.WHITE
	var mark := -1.0  # 0..1 where the goal line sits, < 0 for none
	var ink := Color.WHITE  # the look's text colour, for the track and the goal mark

	func _init() -> void:
		custom_minimum_size = Vector2(110, 8)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_value(f: float, c: Color, goal := -1.0) -> void:
		fill = clampf(f, 0.0, 1.0)
		colour = c
		mark = goal
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(ink, 0.1))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * fill, size.y)), colour)
		if mark >= 0.0:
			var x := roundf(size.x * mark)
			draw_line(Vector2(x, -2), Vector2(x, size.y + 2), Color(ink, 0.7), 1.0)


var _bus: Node
var _chip: Label
var _fix: Label
var _rows := {}  # area -> {dot, bar, value}
var _names: Array[Label] = []
var _details_button: Button
var _details: Label


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_constant_override("separation", 3)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	add_child(head)
	_chip = _label("…", FONT + 1)
	head.add_child(_chip)
	_fix = _label("", FONT - 1)
	_fix.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fix.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_fix)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 2)
	add_child(grid)
	for area: String in ["structure", "services", "requirements", "budget"]:
		var dot := _label("●", FONT)
		var name_l := _label({"structure": "Structure", "services": "Services", "requirements": "Brief", "budget": "Cost"}[area], FONT)
		name_l.custom_minimum_size = Vector2(56, 0)
		_names.append(name_l)
		var bar := Bar.new()
		var value := _label("", FONT)
		value.custom_minimum_size = Vector2(78, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		for c: Control in [dot, name_l, bar, value]:
			grid.add_child(c)
		_rows[area] = {"dot": dot, "bar": bar, "value": value}
	_details_button = Button.new()
	_details_button.flat = true
	_details_button.toggle_mode = true
	_details_button.text = "Details ▸"
	_details_button.add_theme_font_size_override("font_size", FONT - 1)
	_details_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_details_button.toggled.connect(func(on: bool) -> void:
		_details.visible = on
		_details_button.text = "Details ▾" if on else "Details ▸")
	add_child(_details_button)
	_details = _label("", FONT - 1)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.custom_minimum_size = Vector2(WIDTH, 0)
	_details.visible = false
	add_child(_details)


func bind(bus: Node) -> void:
	_bus = bus
	bus.review_done.connect(_show)
	if bus.last_review().is_empty():
		_chip.text = "Assessing…"
		_chip.add_theme_color_override("font_color", _idle())
		bus.call("_schedule")
	else:
		_show(bus.last_review())


func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		_apply_palette()


## Text in the look's colours; called when the panel enters the tree and on every refresh.
func _apply_palette() -> void:
	if not is_inside_tree():
		return
	var text := BsxTheme.col(self, "TEXT")
	var muted := BsxTheme.col(self, "MUTED")
	for row: Dictionary in _rows.values():
		(row.value as Label).add_theme_color_override("font_color", text)
		(row.bar as Bar).ink = text
		(row.bar as Bar).queue_redraw()
	for l: Label in _names:
		l.add_theme_color_override("font_color", text)
	_fix.add_theme_color_override("font_color", muted)
	_details.add_theme_color_override("font_color", muted)
	_details_button.add_theme_color_override("font_color", muted)


func _idle() -> Color:
	return BsxTheme.col(self, "MUTED") if is_inside_tree() else Color(0.5, 0.55, 0.6)


func _show(r: Dictionary) -> void:
	_apply_palette()
	var idle := _idle()
	var areas: Dictionary = r.get("areas", {})
	var feasible := bool(r.get("feasible", false))
	if areas.is_empty():
		_chip.text = "NOTHING YET"
		_chip.add_theme_color_override("font_color", idle)
		_fix.text = "Draw some rooms"
		for area: String in _rows:
			_set_row(area, idle, 0.0, "–")
		_details.text = ""
		return
	_chip.text = "FEASIBLE" if feasible else "NOT YET"
	_chip.add_theme_color_override("font_color", GOOD if feasible else BAD)
	_fix.text = _fix_line(r)
	var cost: Dictionary = r.get("cost", {})

	var st: Dictionary = areas.get("structure", {})
	var worst := float(st.get("worst", 0.0))
	_set_row("structure", _util_colour(worst), worst / 1.5,
		"%d%% %s" % [roundi(worst * 100.0), ("· %d fail" % int(st.failing)) if int(st.get("failing", 0)) > 0 else "used"], 1.0 / 1.5)

	var sv: Dictionary = areas.get("services", {})
	var total := maxi(int(sv.get("total", 0)), 1)
	var served := int(sv.get("served", 0))
	_set_row("services", GOOD if served >= total else (WARN if served * 2 >= total else BAD), float(served) / total,
		"%d/%d rooms" % [served, int(sv.get("total", 0))])

	var req: Dictionary = areas.get("requirements", {})
	if req.is_empty():
		_set_row("requirements", idle, 0.0, "no contract")
	else:
		var rt := maxi(int(req.total), 1)
		_set_row("requirements", GOOD if bool(req.ok) else (WARN if float(req.passed) / rt >= 0.75 else BAD),
			float(req.passed) / rt, "%d/%d met" % [int(req.passed), int(req.total)])

	var budget := float(cost.get("budget", 0.0))
	var all_in := float(cost.get("total", 0.0))
	if budget > 0.0:
		var f := all_in / budget
		_set_row("budget", GOOD if f <= 0.9 else (WARN if f <= 1.0 else BAD), f / 1.25,
			"%s/%s" % [_short(all_in), _short(budget)], 1.0 / 1.25)
	else:
		_set_row("budget", idle, 0.0, _short(all_in))

	var lines := PackedStringArray()
	for i: Dictionary in (r.get("issues", []) as Array).slice(0, ISSUES_SHOWN):
		var t := ("%s %s" % [i.text, i.tip]).strip_edges()
		if t.length() > LINE_MAX:
			t = t.substr(0, LINE_MAX - 1) + "…"
		lines.append("• " + t)
	if lines.is_empty():
		lines.append("Nothing to fix.")
	_details.text = "\n".join(lines)


func _set_row(area: String, colour: Color, fill: float, value: String, goal := -1.0) -> void:
	var row: Dictionary = _rows[area]
	(row.dot as Label).add_theme_color_override("font_color", colour)
	(row.bar as Bar).set_value(fill, colour, goal)
	(row.value as Label).text = value


## One short line: what the engineers can do about it.
func _fix_line(r: Dictionary) -> String:
	if bool(r.get("feasible", false)):
		return _short(float(r.get("cost", {}).get("total", 0.0))) + " all in"
	var fixes: Dictionary = r.get("fixes", {})
	if fixes.is_empty():
		return ""
	var names := PackedStringArray()
	for k: String in ["structure", "services"]:
		if fixes.has(k) and bool(fixes[k].possible):
			names.append(k)
	if names.is_empty():
		return "needs a rethink"
	var after := _short(float(r.get("cost", {}).get("after_fixes", 0.0)))
	return "Design %s fixes it · %s" % [" + ".join(names), after] if bool(r.get("fixable", false)) \
		else "Design %s helps · %s" % [" + ".join(names), after]


static func _util_colour(u: float) -> Color:
	return GOOD if u < 0.7 else (WARN if u <= 1.0 else BAD)


## £163k, £1.2m, £950.
static func _short(v: float) -> String:
	if v >= 1000000.0:
		return "£%.1fm" % (v / 1000000.0)
	if v >= 1000.0:
		return "£%dk" % roundi(v / 1000.0)
	return "£%d" % roundi(v)
