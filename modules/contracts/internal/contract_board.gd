extends MarginContainer
## The "Contracts" big-screen page (the design hall's wall screens, channel contracts.board).
## It shows the firm's tier and XP bar, the contracts on offer (Read and Accept on each) and
## what the next tier opens, beside the full briefing document of the contract being worked
## on (with its live requirements) or of the offer being read (the site's own brief first).
## Text is sized for about 12 px at its own size; the hall scales the page up. Made by
## ContractsBus.make_board(model); it refreshes itself on the bus's signals.

const BASE := 12
## The lists' height on a wall screen (the page fills its slot), and in a scrolling window.
const MIN_LIST_H := BASE * 16
const TALL_LIST_H := BASE * 42

var bus: Node
var model: BuildingModel
var _header: Label
var _money: Label
var _bar: ProgressBar
var _bar_text: Label
var _offers: VBoxContainer
var _active_box: VBoxContainer
var _next: RichTextLabel
var _cols: HBoxContainer
var _firm: VBoxContainer
var _firm_button: Button
var _doc: RichTextLabel
var _doc_row: HBoxContainer
## The offer whose brief is shown while no contract is taken ("" for the first).
var selected := ""
var _dirty := false


func setup(contracts: Node, building: BuildingModel) -> void:
	bus = contracts
	model = building
	for side: String in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_" + side, BASE)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", BASE / 2)
	add_child(page)
	# Top: tier and money, then the XP bar with its line.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", BASE)
	page.add_child(head)
	_header = _label("", int(BASE * 1.6), false, true)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_header)
	_money = _label("", int(BASE * 1.4))
	head.add_child(_money)
	_firm_button = _button("FirmPage", "Firm", func() -> void:
		_firm.visible = not _firm.visible
		_cols.visible = not _firm.visible
		_poke())
	_firm_button.visible = Flags.is_on(ContractsBus.UNLOCK_FLAG)
	head.add_child(_firm_button)
	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", BASE)
	page.add_child(xp_row)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(BASE * 10, BASE * 0.8)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.max_value = 1.0
	xp_row.add_child(_bar)
	_bar_text = _label("", BASE - 1, true)
	xp_row.add_child(_bar_text)
	page.add_child(HSeparator.new())
	# Offers and the current contract side by side, each scrolling inside the page.
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", BASE)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(cols)
	_cols = cols
	# The Firm page (unlock tree): the tier ladder and the upgrades, in place of the lists.
	var firm_scroll := ScrollContainer.new()
	firm_scroll.name = "FirmScroll"
	firm_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	firm_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	firm_scroll.custom_minimum_size = Vector2(0, MIN_LIST_H)
	page.add_child(firm_scroll)
	_firm = VBoxContainer.new()
	_firm.name = "Firm"
	_firm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_firm.add_theme_constant_override("separation", BASE / 2)
	firm_scroll.add_child(_firm)
	_firm.visibility_changed.connect(func() -> void: firm_scroll.visible = _firm.visible)
	_firm.visible = false
	firm_scroll.visible = false
	var left := _column(cols, "On offer", 1.1)
	_offers = VBoxContainer.new()
	_offers.add_theme_constant_override("separation", BASE / 2)
	_offers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_offers)
	left.add_child(HSeparator.new())
	_next = RichTextLabel.new()
	_next.bbcode_enabled = true
	_next.fit_content = true
	_next.scroll_active = false
	_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next.add_theme_font_size_override("normal_font_size", BASE - 1)
	_next.add_theme_font_size_override("bold_font_size", BASE)
	left.add_child(_next)
	var right := _column(cols, "Brief", 1.3)
	_active_box = VBoxContainer.new()
	_active_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_active_box)
	_doc_row = HBoxContainer.new()
	_doc_row.add_theme_constant_override("separation", BASE / 2)
	right.add_child(_doc_row)
	_doc = RichTextLabel.new()
	_doc.name = "Briefing"
	_doc.bbcode_enabled = true
	_doc.fit_content = true
	_doc.scroll_active = false
	_doc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_doc.add_theme_font_size_override("normal_font_size", BASE - 1)
	_doc.add_theme_font_size_override("bold_font_size", BASE)
	right.add_child(_doc)
	bus.board_changed.connect(_poke)
	bus.active_changed.connect(_poke)
	bus.career.changed.connect(_poke)
	refresh()


## A titled column whose contents scroll, so a long list never stretches the page.
func _column(parent: Control, title: String, ratio: float) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = ratio
	col.custom_minimum_size = Vector2(BASE * 12, 0)
	parent.add_child(col)
	col.add_child(_label(title, int(BASE * 1.2)))
	var scroll := ScrollContainer.new()
	scroll.name = "ColumnScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# A scroll box has no height of its own: give it some, so the page still shows its lists
	# when it sits in something that does not hand it a height (a scrolling window).
	scroll.custom_minimum_size = Vector2(0, MIN_LIST_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	return inner


func _poke() -> void:
	if not is_inside_tree():
		refresh()
		return
	if _dirty:
		return
	_dirty = true
	refresh.call_deferred()


## Colours depend on where the page is drawn (a wall screen keeps the classic look), so
## they are set again once it is in place.
func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and is_instance_valid(bus):
		# In a scrolling window (the designer's Contracts... step) the lists get a tall page.
		var tall := get_parent() is ScrollContainer
		for sc in find_children("ColumnScroll", "ScrollContainer", true, false):
			(sc as Control).custom_minimum_size.y = TALL_LIST_H if tall else MIN_LIST_H
		refresh()


func refresh() -> void:
	_dirty = false
	if not is_instance_valid(bus):
		return
	_recolour.call_deferred()
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
	_fill_doc()
	_fill_next(p)
	if _firm.visible:
		_fill_firm()


## The Firm page: what each tier opens (ticked when reached) and the upgrades to buy.
func _fill_firm() -> void:
	for c in _firm.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	var t: int = bus.career.tier()
	_firm.add_child(_label("Firm upgrades: kept for good, paid from the firm's money.", int(BASE * 1.2)))
	for u: Dictionary in ContractCareer.DATA.UPGRADES:
		var row := HBoxContainer.new()
		row.name = "Upgrade_" + str(u.id)
		row.add_theme_constant_override("separation", BASE)
		var owned: bool = bus.career.has_upgrade(str(u.id))
		var text := _label("%s · %s · %s" % [str(u.label), ContractValidator.money(float(u.price)), str(u.blurb)], BASE - 1, owned, true)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		if owned:
			var have := "Bought" + (" (%s)" % ContractBrief.material_word(bus.career.deal_material) if str(u.get("option", "")) == "material" else "")
			row.add_child(_label(have, BASE - 2, true))
		elif str(u.get("option", "")) == "material":
			for m: String in ["timber", "masonry", "concrete", "steel"]:
				var mat := m
				var b := _button("Buy_" + m, "Buy for %s" % ContractBrief.material_word(m), func() -> void: bus.buy(str(u.id), mat))
				b.disabled = bus.career.cannot_buy(str(u.id), m) != ""
				row.add_child(b)
		else:
			var b := _button("Buy", "Buy", func() -> void: bus.buy(str(u.id)))
			b.disabled = bus.career.cannot_buy(str(u.id)) != ""
			row.add_child(b)
		_firm.add_child(row)
	_firm.add_child(HSeparator.new())
	_firm.add_child(_label("What each tier opens", int(BASE * 1.2)))
	for d: Dictionary in ContractTiers.TIERS:
		var opens := PackedStringArray()
		for u: Dictionary in ContractCareer.unlocks_at(int(d.tier)):
			opens.append(str(u.label))
		var mark := "✓ " if int(d.tier) <= t else "   "
		var l := _wrapped("%sTier %d, %s (%s): %s." % [mark, int(d.tier), str(d.name), ContractTiers.xp_text(int(d.xp)), ", ".join(opens)],
				BASE - 1, int(d.tier) > t)
		_firm.add_child(l)


## The brief shown: the contract taken, else the offer picked with Read, else the brief for
## the site the crew is on, else the first offer.
func shown_brief() -> Dictionary:
	if not (bus.active as Dictionary).is_empty():
		return bus.active
	for b: Dictionary in bus.board:
		if str(b.id) == selected:
			return b
	var site: Dictionary = bus.site_offer()
	if not site.is_empty():
		return site
	return bus.board[0] if not (bus.board as Array).is_empty() else {}


func _fill_doc() -> void:
	for c in _doc_row.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	var b := shown_brief()
	_doc.text = ContractBriefing.bbcode(b, BsxTheme.col(self, "MUTED").to_html(), model.catalog if model != null else null, int(BASE * 1.5)) \
			if not b.is_empty() else ""
	if b.is_empty() or not (bus.active as Dictionary).is_empty():
		return
	var accept := _button("AcceptBrief", "Accept this contract", func() -> void: bus.accept(str(b.id)))
	accept.disabled = int(b.get("tier", 1)) > bus.career.tier()
	_doc_row.add_child(accept)
	if accept.disabled:
		_doc_row.add_child(_label("Needs a tier %d firm." % int(b.get("tier", 1)), BASE - 2, true))


func _fill_offers() -> void:
	for c in _offers.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	var busy := not (bus.active as Dictionary).is_empty()
	for b: Dictionary in bus.board:
		var card := VBoxContainer.new()
		card.name = "Offer_" + str(b.id).validate_node_name()
		card.add_theme_constant_override("separation", 0)
		var row := HBoxContainer.new()
		card.add_child(row)
		var title := _label(str(b.get("title", "")), BASE, false, true)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.tooltip_text = str(b.get("summary", ""))
		row.add_child(title)
		var bid := str(b.id)
		if bid == str(shown_brief().get("id", "")) and busy == false:
			title.text = "▸ " + title.text
		var read := _button("Read", "Read", func() -> void:
			selected = bid
			_poke())
		read.disabled = busy
		row.add_child(read)
		var accept := _button("Accept", "Accept", func() -> void: bus.accept(bid))
		accept.disabled = busy or (int(b.get("tier", 1)) > bus.career.tier() and not bool(b.get("patron", false)))
		row.add_child(accept)
		var line := "Tier %d · fee %s · %d days · +%s · %s" % [int(b.get("tier", 1)),
				ContractValidator.money(float(b.get("fee", 0.0))), int(b.get("deadline_days", 0)),
				ContractTiers.xp_text(int(b.get("xp", 0))), str(b.get("client", ""))]
		# The survey kit reads the site before you take the job.
		var site: Dictionary = b.get("site", {}) if b.get("site") is Dictionary else {}
		if bus.effect("survey") > 0.0 and str(site.get("id", "")) != "":
			var pack := SitePool.open(str(site.id))
			if pack != null and pack.ok():
				line += " · survey: difficulty %d, cost ×%.2f" % [pack.rating(), pack.cost_multiplier_hint()]
		if b.has("client_standing"):
			line += " (%s)" % ContractClients.LEVELS[int(b.client_standing)]
		if not (b.get("twists", []) as Array).is_empty():
			var names := PackedStringArray()
			for n: Variant in b.get("twist_notes", []):
				names.append(str((n as Dictionary).get("label", "")))
			line += " · " + ", ".join(names)
		card.add_child(_label(line, BASE - 2, true, true))
		_offers.add_child(card)


func _fill_active() -> void:
	for c in _active_box.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	if (bus.active as Dictionary).is_empty():
		_active_box.add_child(_wrapped("No contract taken yet. Read a brief, then accept it to start designing.", BASE - 1, true))
		return
	var panel: Control = bus.make_panel(model)
	# The full brief is shown below it.
	panel.set("auto_brief", false)
	panel.set("show_spec", false)
	panel.custom_minimum_size = Vector2.ZERO
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_font_size_override("normal_font_size", BASE - 1)
	panel.add_theme_font_size_override("bold_font_size", BASE)
	panel.add_theme_font_size_override("italics_font_size", BASE - 1)
	_active_box.add_child(panel)
	var row := HBoxContainer.new()
	var abandon := Button.new()
	abandon.name = "Abandon"
	abandon.text = "Abandon (−%s)" % ContractTiers.xp_text(ceili(int(bus.active.get("xp", 0)) * ContractsBus.ABANDON_XP_SHARE))
	abandon.add_theme_font_size_override("font_size", BASE - 2)
	abandon.pressed.connect(func() -> void: bus.abandon())
	row.add_child(abandon)
	_active_box.add_child(row)
	_active_box.add_child(HSeparator.new())


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


## A small button that acts on the press (on a wall screen the pointer follows the view, and
## a hand that drifts off the button before letting go would otherwise cancel the click).
func _button(id: String, text: String, press: Callable) -> Button:
	var b := Button.new()
	b.name = id
	b.text = text
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	b.add_theme_font_size_override("font_size", BASE - 2)
	b.pressed.connect(press)
	return b


## A label; wrap: word wrapping (else one line, cut short with "..." if it is too long).
func _label(text: String, size: int, muted := false, one_line := false) -> Label:
	var l := Label.new()
	l.text = text
	if one_line:
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.clip_text = true
	l.add_theme_font_size_override("font_size", size)
	if muted:
		l.set_meta("muted", true)
		l.add_theme_color_override("font_color", BsxTheme.col(self, "MUTED"))
	return l


func _wrapped(text: String, size: int, muted := false) -> Label:
	var l := _label(text, size, muted)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _recolour() -> void:
	if not is_inside_tree():
		return
	var muted := BsxTheme.col(self, "MUTED")
	for n in find_children("*", "Label", true, false):
		if n.has_meta("muted"):
			(n as Label).add_theme_color_override("font_color", muted)
