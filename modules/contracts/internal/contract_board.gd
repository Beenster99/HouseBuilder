extends MarginContainer
## The "Contracts" big-screen page (the design hall's wall screens, channel contracts.board).
## It shows the firm's tier and XP bar, the contracts on offer with an Accept button each,
## the contract being worked on with its live requirements, and what the next tier opens.
## Text is sized for about 12 px at its own size; the hall scales the page up. Made by
## ContractsBus.make_board(model); it refreshes itself on the bus's signals.

const BASE := 12

var bus: Node
var model: BuildingModel
var _header: Label
var _money: Label
var _bar: ProgressBar
var _bar_text: Label
var _offers: VBoxContainer
var _active_box: VBoxContainer
var _next: RichTextLabel
var _dirty := false


func setup(contracts: Node, building: BuildingModel) -> void:
	bus = contracts
	model = building
	for side: String in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_" + side, BASE * 2)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", BASE)
	add_child(page)
	var head := HBoxContainer.new()
	page.add_child(head)
	_header = _label("", BASE * 2)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_header)
	_money = _label("", int(BASE * 1.4))
	head.add_child(_money)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, BASE * 1.2)
	_bar.max_value = 1.0
	page.add_child(_bar)
	_bar_text = _label("", BASE, true)
	page.add_child(_bar_text)
	page.add_child(HSeparator.new())
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", BASE * 2)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(cols)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.2
	cols.add_child(left)
	left.add_child(_label("On offer", int(BASE * 1.4)))
	_offers = VBoxContainer.new()
	_offers.add_theme_constant_override("separation", BASE)
	left.add_child(_offers)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(_label("Current contract", int(BASE * 1.4)))
	_active_box = VBoxContainer.new()
	right.add_child(_active_box)
	right.add_child(HSeparator.new())
	_next = RichTextLabel.new()
	_next.bbcode_enabled = true
	_next.fit_content = true
	_next.scroll_active = false
	_next.add_theme_font_size_override("normal_font_size", BASE)
	_next.add_theme_font_size_override("bold_font_size", int(BASE * 1.4))
	right.add_child(_next)
	bus.board_changed.connect(_poke)
	bus.active_changed.connect(_poke)
	bus.career.changed.connect(_poke)
	refresh()


func _poke() -> void:
	if not is_inside_tree():
		refresh()
		return
	if _dirty:
		return
	_dirty = true
	refresh.call_deferred()


func refresh() -> void:
	_dirty = false
	if not is_instance_valid(bus):
		return
	var p: Dictionary = bus.career.progress()
	_header.text = "Tier %d · %s" % [int(p.tier), str(p.name)]
	_money.text = ContractValidator.money(float(bus.career.money))
	_bar.value = float(p.share)
	if int(p.next) >= 0:
		_bar_text.text = "%s of %s to tier %d, %s" % [ContractTiers.xp_text(int(p.xp)), ContractTiers.xp_text(int(p.next)),
				int(p.tier) + 1, str(p.next_name)]
	else:
		_bar_text.text = "%s · top tier" % ContractTiers.xp_text(int(p.xp))
	_fill_offers()
	_fill_active()
	_fill_next(p)


func _fill_offers() -> void:
	for c in _offers.get_children():
		c.queue_free()
	var busy := not (bus.active as Dictionary).is_empty()
	for b: Dictionary in bus.board:
		var card := VBoxContainer.new()
		card.name = "Offer_" + str(b.id).validate_node_name()
		card.add_child(_label(str(b.get("title", "")), int(BASE * 1.2)))
		card.add_child(_label("Tier %d · %s · fee %s · budget %s · %d days · +%s" % [int(b.get("tier", 1)), str(b.get("client", "")),
				ContractValidator.money(float(b.get("fee", 0.0))), ContractValidator.money(float(b.get("budget", 0.0))),
				int(b.get("deadline_days", 0)), ContractTiers.xp_text(int(b.get("xp", 0)))], BASE, true))
		card.add_child(_label(str(b.get("summary", "")), BASE))
		var accept := Button.new()
		accept.name = "Accept"
		accept.text = "Accept"
		accept.disabled = busy or int(b.get("tier", 1)) > bus.career.tier()
		accept.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		accept.add_theme_font_size_override("font_size", BASE)
		var bid := str(b.id)
		accept.pressed.connect(func() -> void: bus.accept(bid))
		card.add_child(accept)
		_offers.add_child(card)


func _fill_active() -> void:
	for c in _active_box.get_children():
		c.queue_free()
	if (bus.active as Dictionary).is_empty():
		_active_box.add_child(_label("None taken. Accept one of the contracts on offer to start designing.", BASE, true))
		return
	var panel: Control = bus.make_panel(model)
	panel.add_theme_font_size_override("normal_font_size", BASE)
	panel.add_theme_font_size_override("bold_font_size", int(BASE * 1.2))
	_active_box.add_child(panel)
	var row := HBoxContainer.new()
	var abandon := Button.new()
	abandon.name = "Abandon"
	abandon.text = "Abandon (−%s)" % ContractTiers.xp_text(ceili(int(bus.active.get("xp", 0)) * ContractsBus.ABANDON_XP_SHARE))
	abandon.add_theme_font_size_override("font_size", BASE)
	abandon.pressed.connect(func() -> void: bus.abandon())
	row.add_child(abandon)
	_active_box.add_child(row)


func _fill_next(p: Dictionary) -> void:
	var t := int(p.tier)
	if int(p.next) < 0:
		_next.text = "[b]Top tier[/b]\nEvery building type and material is open."
		return
	var nxt := ContractTiers.info(t + 1)
	var opens := PackedStringArray()
	for u: Dictionary in ContractCareer.unlocks_at(t + 1):
		opens.append(str(u.label).to_lower())
	_next.text = "[b]Next: tier %d, %s[/b]\n%s\nAt %s. Opens %s." % [t + 1, str(nxt.name), str(nxt.blurb),
			ContractTiers.xp_text(int(nxt.xp)), ", ".join(opens) if not opens.is_empty() else "nothing new"]


func _label(text: String, size: int, muted := false) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	if muted:
		l.add_theme_color_override("font_color", BsxTheme.MUTED)
	return l
