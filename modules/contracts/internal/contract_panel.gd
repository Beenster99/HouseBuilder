extends RichTextLabel
## The design room's live "Contract" window: the brief being worked on and how the design
## measures up to it right now. Rebuilt a moment after each edit (debounced), when the stress
## test reports and when the contract changes. Made by ContractsBus.make_panel(model).

const DEBOUNCE := 0.25
const OK_COLOUR := Color(0.55, 0.95, 0.6)

var bus: Node
var model: BuildingModel
var _timer: Timer


func setup(contracts: Node, building: BuildingModel) -> void:
	bus = contracts
	model = building
	bbcode_enabled = true
	fit_content = true
	scroll_active = false
	custom_minimum_size = Vector2(300, 0)
	add_theme_font_size_override("normal_font_size", 14)
	add_theme_font_size_override("bold_font_size", 15)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = DEBOUNCE
	_timer.timeout.connect(refresh)
	add_child(_timer)
	if model != null:
		model.changed.connect(func(_op: Dictionary) -> void: poke())
	bus.active_changed.connect(poke)
	bus.report_taken.connect(poke)
	refresh()


## Something changed: refresh soon (many edits in a row refresh once).
func poke() -> void:
	if is_instance_valid(_timer) and is_inside_tree():
		_timer.start()
	else:
		refresh()


func refresh() -> void:
	var brief: Dictionary = bus.active
	if brief.is_empty():
		text = "[color=#%s]No contract taken.[/color]" % BsxTheme.MUTED.to_html()
		return
	var a: Dictionary = bus.assess(model)
	var lines := PackedStringArray()
	var muted := BsxTheme.MUTED.to_html()
	lines.append("[b]%s[/b]" % _esc(str(brief.get("title", ""))))
	lines.append("[color=#%s]%s · fee %s · %d days[/color]" % [muted, _esc(str(brief.get("client", ""))),
			ContractValidator.money(float(brief.get("fee", 0.0))), int(brief.get("deadline_days", 0))])
	if a.is_empty():
		text = "\n".join(lines)
		return
	var cost := float(a.cost)
	var budget := float(a.budget)
	var over := cost > budget
	lines.append("Cost [color=#%s]%s[/color] of %s budget" % [(BsxTheme.WARN if over else OK_COLOUR).to_html(),
			ContractValidator.money(cost), ContractValidator.money(budget)])
	lines.append("[color=#%s]%s[/color]" % [(OK_COLOUR if a.ok else BsxTheme.LIVE).to_html(), _esc(str(a.summary))])
	lines.append("")
	lines.append("[b]Requirements %d / %d[/b]" % [int(a.passed), int(a.total)])
	for it: Dictionary in a.items:
		if it.hard:
			lines.append_array(_item_lines(it, muted))
	var goals := false
	for it: Dictionary in a.items:
		if not it.hard:
			if not goals:
				lines.append("")
				lines.append("[b]Bonus goals[/b]")
				goals = true
			lines.append_array(_item_lines(it, muted))
	text = "\n".join(lines)


func _item_lines(it: Dictionary, muted: String) -> PackedStringArray:
	var out := PackedStringArray()
	var mark := "[color=#%s]✓[/color]" % OK_COLOUR.to_html() if it.ok else "[color=#%s]✗[/color]" % BsxTheme.WARN.to_html()
	var bonus := "  [color=#%s]+%s[/color]" % [muted, ContractValidator.money(float(it.bonus))] if not it.hard and float(it.bonus) > 0.0 else ""
	var pct := "" if it.ok or float(it.progress) <= 0.0 else "  [color=#%s]%d%%[/color]" % [muted, roundi(float(it.progress) * 100.0)]
	out.append("%s %s%s%s" % [mark, _esc(str(it.label)), pct, bonus])
	if not it.ok:
		if str(it.detail) != "":
			out.append("   [color=#%s]%s[/color]" % [muted, _esc(str(it.detail))])
		if str(it.tip) != "":
			out.append("   [i]%s[/i]" % _esc(str(it.tip)))
	return out


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")
