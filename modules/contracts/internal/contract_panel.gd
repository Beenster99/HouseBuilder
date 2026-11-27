extends RichTextLabel
## The design room's live "Contract" window: the brief being worked on and how the design
## measures up to it right now, with a link to the full briefing document. With no contract
## taken on a real site it offers the brief written for that site (read it, accept it).
## Rebuilt a moment after each edit (debounced), when the stress test reports and when the
## contract changes. A contract just taken opens its briefing document once.
## Made by ContractsBus.make_panel(model).

const DEBOUNCE := 0.25
## Pass green on the dark screen look; a darker green on the pencil (paper) look.
const OK_SCREEN := Color(0.55, 0.95, 0.6)
const OK_PAPER := Color(0.16, 0.48, 0.22)

var bus: Node
var model: BuildingModel
var _timer: Timer
## Open the briefing document of a contract just taken (off where the brief is already shown,
## as on the Contracts wall screen).
var auto_brief := true
## Show the brief's dimension lines (off where the full document is beside it).
var show_spec := true
var _doc: PopupPanel


func setup(contracts: Node, building: BuildingModel) -> void:
	bus = contracts
	model = building
	bbcode_enabled = true
	fit_content = true
	scroll_active = false
	custom_minimum_size = Vector2(300, 0)
	add_theme_font_size_override("normal_font_size", 14)
	add_theme_font_size_override("bold_font_size", 15)
	add_theme_font_size_override("italics_font_size", 14)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = DEBOUNCE
	_timer.timeout.connect(refresh)
	add_child(_timer)
	if model != null:
		model.changed.connect(func(_op: Dictionary) -> void: poke())
	bus.active_changed.connect(poke)
	bus.report_taken.connect(poke)
	bus.board_changed.connect(poke)
	meta_clicked.connect(_on_link)
	refresh()


## Colours depend on where it is drawn (a wall screen keeps the classic look).
func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and bus != null:
		refresh()
		_open_pending.call_deferred()


## Something changed: refresh soon (many edits in a row refresh once).
func poke() -> void:
	if is_instance_valid(_timer) and is_inside_tree():
		_timer.start()
	else:
		refresh()


func refresh() -> void:
	var brief: Dictionary = bus.active
	if brief.is_empty():
		_offer_text()
		return
	_open_pending.call_deferred()
	var a: Dictionary = bus.assess(model)
	var lines := PackedStringArray()
	var muted := _c("MUTED").to_html()
	lines.append("[b]%s[/b]" % _esc(str(brief.get("title", ""))))
	lines.append("[color=#%s]%s · fee %s · %d days[/color]" % [muted, _esc(str(brief.get("client", ""))),
			ContractValidator.money(float(brief.get("fee", 0.0))), int(brief.get("deadline_days", 0))])
	lines.append("[url=read]Read the full brief[/url]")
	if show_spec:
		for line in ContractBrief.spec_lines(brief, model.catalog if model != null else null):
			lines.append(_esc(line))
	if a.is_empty():
		text = "\n".join(lines)
		return
	var cost := float(a.cost)
	var budget := float(a.budget)
	var over := cost > budget
	lines.append("Cost [color=#%s]%s[/color] of %s budget" % [(_c("WARN") if over else _ok()).to_html(),
			ContractValidator.money(cost), ContractValidator.money(budget)])
	lines.append("[color=#%s]%s[/color]" % [(_ok() if a.ok else _c("LIVE")).to_html(), _esc(str(a.summary))])
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


## No contract: the brief written for the site the crew is on, if there is one.
func _offer_text() -> void:
	var muted := _c("MUTED").to_html()
	var offer: Dictionary = bus.site_offer() if bus.has_method("site_offer") else {}
	if offer.is_empty():
		text = "[color=#%s]No contract taken.[/color]" % muted
		return
	var lines := PackedStringArray()
	lines.append("[b]Brief for this site[/b]")
	lines.append("[b]%s[/b]" % _esc(str(offer.get("title", ""))))
	lines.append("[color=#%s]%s · fee %s · %d days · tier %d[/color]" % [muted, _esc(str(offer.get("client", ""))),
			ContractValidator.money(float(offer.get("fee", 0.0))), int(offer.get("deadline_days", 0)), int(offer.get("tier", 1))])
	lines.append(_esc(ContractBriefing.story(offer)))
	for line in ContractBrief.spec_lines(offer, model.catalog if model != null else null):
		lines.append(_esc(line))
	lines.append("")
	lines.append("[url=read]Read the full brief[/url]    [url=accept]Accept this contract[/url]")
	text = "\n".join(lines)


func _on_link(meta: Variant) -> void:
	match str(meta):
		"read":
			open_briefing(bus.active if not (bus.active as Dictionary).is_empty() else bus.site_offer())
		"accept":
			var offer: Dictionary = bus.site_offer()
			if not offer.is_empty():
				bus.accept(str(offer.id))


func _open_pending() -> void:
	if not auto_brief or not is_inside_tree() or not is_visible_in_tree():
		return
	var id := str((bus.active as Dictionary).get("id", ""))
	if id != "" and str(bus.briefing_pending) == id:
		bus.briefing_pending = ""
		open_briefing(bus.active)


## Opens a brief's full briefing document in a window over the design room.
func open_briefing(brief: Dictionary) -> void:
	if brief.is_empty():
		return
	if is_instance_valid(_doc):
		_doc.queue_free()
	_doc = PopupPanel.new()
	_doc.name = "BriefingWindow"
	_doc.add_theme_stylebox_override("panel", BsxTheme.panel_style(12))
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(720, 560)
	_doc.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var doc := RichTextLabel.new()
	doc.name = "Briefing"
	doc.bbcode_enabled = true
	doc.fit_content = true
	doc.scroll_active = false
	doc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doc.add_theme_font_size_override("normal_font_size", 14)
	doc.add_theme_font_size_override("bold_font_size", 16)
	doc.text = ContractBriefing.bbcode(brief, _c("MUTED").to_html(), model.catalog if model != null else null)
	scroll.add_child(doc)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(row)
	if (bus.active as Dictionary).is_empty() and not brief.is_empty():
		var take := Button.new()
		take.name = "Accept"
		take.text = "Accept this contract"
		var bid := str(brief.id)
		take.pressed.connect(func() -> void:
			bus.accept(bid)
			_doc.hide())
		row.add_child(take)
	var close := Button.new()
	close.name = "Close"
	close.text = "Close"
	close.pressed.connect(func() -> void: _doc.hide())
	row.add_child(close)
	add_child(_doc)
	_doc.popup_centered()


func _item_lines(it: Dictionary, muted: String) -> PackedStringArray:
	var out := PackedStringArray()
	var mark := "[color=#%s]✓[/color]" % _ok().to_html() if it.ok else "[color=#%s]✗[/color]" % _c("WARN").to_html()
	var bonus := "  [color=#%s]+%s[/color]" % [muted, ContractValidator.money(float(it.bonus))] if not it.hard and float(it.bonus) > 0.0 else ""
	var pct := "" if it.ok or float(it.progress) <= 0.0 else "  [color=#%s]%d%%[/color]" % [muted, roundi(float(it.progress) * 100.0)]
	out.append("%s %s%s%s" % [mark, _esc(str(it.label)), pct, bonus])
	if not it.ok:
		if str(it.detail) != "":
			out.append("   [color=#%s]%s[/color]" % [muted, _esc(str(it.detail))])
		if str(it.tip) != "":
			out.append("   [i]%s[/i]" % _esc(str(it.tip)))
	return out


## A palette colour for where this panel is drawn (the wall screens use the classic look).
func _c(colour_name: String) -> Color:
	return BsxTheme.col(self, colour_name)


func _ok() -> Color:
	return OK_SCREEN if BsxTheme.palette_for(self) == BsxTheme.CLASSIC_COLOURS else OK_PAPER


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")
