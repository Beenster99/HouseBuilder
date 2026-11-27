extends PanelContainer
## The "Real-world sites" channel on the design hall's wall screens: the curated site pool
## (where each one is, how big the plot is, what makes it hard) beside the site the crew
## is on now and how to start on one. Built small (about 12 px text); the hall scales it.

const SIZE := Vector2(1280, 720)
const TEXT := 12
const HEAD := 22
const MAX_ROWS := 24
const STARS := "★★★★★"

var _bus: Node
var _current: VBoxContainer
var _rows: VBoxContainer
var _buttons: Array[Button] = []
var _status: Label


func _init() -> void:
	custom_minimum_size = SIZE
	add_theme_stylebox_override("panel", BsxTheme.panel_style(16))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	add_child(cols)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 2.0
	left.add_theme_constant_override("separation", 4)
	cols.add_child(left)
	left.add_child(BsxTheme.title("Real-world sites", HEAD))
	left.add_child(_label("Curated plots from OpenStreetMap. Difficulty 1 (easy) to 5 (very hard).", true))
	_status = _label("", false, 14)
	_status.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3))
	left.add_child(_status)
	left.add_child(_row(["Site", "Where", "Plot", "Difficulty", "Constraints"], true))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 2)
	scroll.add_child(_rows)
	_current = VBoxContainer.new()
	_current.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_current.add_theme_constant_override("separation", 6)
	cols.add_child(_current)


## bus: the sites bus (load_site, current, site_changed).
func bind(bus: Node) -> void:
	_bus = bus
	_fill_pool()
	bus.site_changed.connect(_show_current)
	_show_current(bus.current())


func _pick(site_id: String) -> void:
	var name := str(SitePool.summary(site_id).get("name", site_id))
	_status.text = "Loading %s for everyone..." % name
	_bus.load_site(site_id)


func _fill_pool() -> void:
	_buttons.clear()
	for c in _rows.get_children():
		c.queue_free()
	var sites := SitePool.list()
	sites.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.rating < b.rating or (a.rating == b.rating and a.name < b.name))
	for s: Dictionary in sites.slice(0, MAX_ROWS):
		var constraints: Array = s.get("constraints", [])
		var row := _row([str(s.name), str(s.get("location", "")), str(s.get("plot_size", "")),
				STARS.left(int(s.rating)), ", ".join(constraints.slice(0, 3)) if not constraints.is_empty() else "none"], false)
		var go := Button.new()
		go.text = "Build here"
		go.add_theme_font_size_override("font_size", TEXT)
		go.tooltip_text = "Load this site for the whole crew"
		# Act on the press: on a wall screen the pointer follows the view, and a hand that
		# drifts off the button before letting go would otherwise cancel the click.
		go.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		go.custom_minimum_size = Vector2(96, 30)
		go.toggle_mode = false
		var sid := str(s.id)
		go.set_meta("site_id", sid)
		go.pressed.connect(func() -> void: _pick(sid))
		_buttons.append(go)
		row.add_child(go)
		_rows.add_child(row)
	if sites.size() > MAX_ROWS:
		_rows.add_child(_label("…and %d more in Real sites on the main menu." % (sites.size() - MAX_ROWS), true))
	if sites.is_empty():
		_rows.add_child(_label("No site packs found.", true))


func _show_current(pack: SitePack) -> void:
	if not is_instance_valid(_current):
		return
	for c in _current.get_children():
		c.queue_free()
	_current.add_child(BsxTheme.title("Current site", HEAD))
	for b in _buttons:
		var here := pack != null and str(b.get_meta("site_id")) == pack.id()
		b.text = "Current" if here else "Build here"
		b.disabled = here
	if is_instance_valid(_status):
		_status.text = "Now building on %s." % pack.title() if pack else ""
	if pack == null:
		_current.add_child(_label("No real site yet: you are designing on the open sandbox plot.", false))
		_current.add_child(_label("To start on a real site, press Build here beside one on the left, or pick one from Real sites on the main menu. Everyone in the session moves to it, and the plot's soil goes to the structural engineer.", true))
		return
	_current.add_child(_label(pack.title(), false, 16))
	_current.add_child(_label(pack.location_text(), true))
	_current.add_child(_label("Plot: %s. Ground: %s." % [pack.plot_size_text(), pack.soil().replace("_", " ")], false))
	_current.add_child(_label("Difficulty %s (%d of 5), cost × %.2f" % [STARS.left(pack.rating()), pack.rating(), pack.cost_multiplier_hint()], false))
	var roads := pack.access()
	_current.add_child(_label("Access: %s." % (", ".join(roads.map(func(r: Dictionary) -> String:
			return "%s (%d m frontage)" % [str(r.get("name", r.get("road", "road"))), roundi(float(r.get("frontage_m", 0.0)))]))
			if not roads.is_empty() else "no road access"), false))
	if not pack.existing_buildings().is_empty():
		_current.add_child(_label("%d existing building(s) on the plot to clear first." % pack.existing_buildings().size(), false))
	var notes := pack.notes_text()
	if notes != "":
		_current.add_child(_label(notes, true))
	_current.add_child(_label("Draw the building around the plot's centre; the orange outline is the boundary.", true))
	_current.add_child(_label("\n".join(pack.attribution()), true, 10))


func _row(cells: Array, header: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var widths := [175, 140, 180, 60, 0]
	for i in cells.size():
		var l := _label(str(cells[i]), header)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF if i < 4 else TextServer.AUTOWRAP_WORD_SMART
		l.clip_text = i < 4
		l.custom_minimum_size = Vector2(widths[i], 0)
		if i == 4:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i == 3 and not header:
			l.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3))
		row.add_child(l)
	return row


func _label(text: String, muted: bool, size: int = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	if muted:
		l.add_theme_color_override("font_color", BsxTheme.col(self, "MUTED"))
	return l
