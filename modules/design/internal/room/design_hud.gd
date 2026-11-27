extends Control
## The design room's HUD, laid out like BSX's design room: the 2D or 3D view in the middle,
## the top bar (crew, level, grid, 2D/3D, undo, redo, save, load, other modules' actions),
## the left dock (tools, the tool's options, and the Rooms / Components / Levels browser), the
## right dock (a small 3D view, the View's panel, other modules' live assessment windows, the
## design summary, the cost), an optional section along the bottom of the middle, and the
## help bar along the bottom. Small text, so the columns hold a lot; each block of information
## is its own framed card with a title bar (click the title to fold it).

const PANEL_W := 300
## Height taken by the two-row top bar, px.
const TOP_H := 80
const COST_W := 340
## Body text size, px.
const FONT := 11
## The small 3D view's height, and the section's, px.
const MINI_H := 110
const SECTION_H := 280
const ModelChannel := preload("res://modules/design/internal/hall/hall_channels.gd").ModelChannel

var room: Node3D
var _session: DesignSession
var _model: BuildingModel
var _net: MultiplayerBus
var _tool_buttons: Dictionary = {}
var _crew_label: RichTextLabel
var _level_label: Label
var _view_button: Button
var _grid_pick: OptionButton
var _cost: RichTextLabel
## The help bar along the bottom: keys for the mode, what the pointer is over, messages.
var help: HelpBar
var _summary: RichTextLabel
var _hover_age := 0.0
var _cards: Dictionary = {}  # id -> Callable that repaints the card
var _options: VBoxContainer
var _actions: HBoxContainer
## The top bar's right end: the Walk inside button (from the walk module's action).
var _walk_slot: HBoxContainer
const TOP_RIGHT_ACTIONS := ["walk.inside"]
var _views: OptionButton
var _overlay_slot: VBoxContainer
var _side_slot: VBoxContainer
## The Rooms / Components / Levels tabs under the tools.
var browser: TabContainer
## The left and right docks (they move and roll up).
var left_dock: PanelContainer
var right_dock: PanelContainer
## Add rooms / Add objects, grouped and filtered, between the tools and the browser.
var palette: VBoxContainer
var _folded: Dictionary = {}
var _note_popup: PopupPanel
var _layers_pop: PopupMenu
var _look: CheckButton
var _note_text: LineEdit
var _note_at := Vector3.ZERO
var _note_target := ""
const LAYERS := [["rooms", "Rooms"], ["notes", "Notes"], ["pings", "Pings"], ["dimensions", "Wall lengths"]]
var _save_popup: PopupPanel
var _save_name: LineEdit
var _load_popup: PopupPanel
var _load_list: ItemList
var _cost_dirty := true
## Each part's and room's cost, kept up to date edit by edit.
var _book: DesignCostBook
var _book_rev := -1
var _cost_age := 0.0
## The cost panel redraws at most this often, s.
const COST_EVERY := 0.25
## Rooms listed in the cost panel; the Rooms tab lists them all.
const COST_ROOMS := 30
var _hover_text := ""
var _summary_dirty := true
## The whole design for the small views (every level, no plan cut).
var mini: DesignMiniWorld
var mini_3d: Control
var _mini_box: Control
var section: Control
var _section_box: Control
var _section_toggle: CheckButton


func _ready() -> void:
	_session = room.get("session")
	_model = _session.model
	_net = _session.net
	_book = DesignCostBook.new(_model)
	# Cost the building while the room opens; a design loaded later is costed a slice a frame.
	_book.update()
	theme = dense_theme(BsxTheme.get_theme())
	mini = DesignMiniWorld.new()
	add_child(mini)
	mini.setup(_session)
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_build_top()
	_build_tools()
	_build_cost()
	_build_section()
	_build_status()
	_build_banner()
	_session.tool_changed.connect(func(_t: String) -> void: refresh_banner())
	_session.presence.selection_changed.connect(func(_p: int, _ids: PackedStringArray) -> void: refresh_banner())
	resized.connect(refresh_banner)
	_build_popups()
	_session.tool_changed.connect(func(_t: String) -> void: _refresh_tools())
	_session.level_changed.connect(func(_l: int) -> void: refresh_bar())
	_session.status.connect(_show_status)
	_model.changed.connect(func(op: Dictionary) -> void:
		if str(op.get("op", "")) == "set_meta" and _session.tool == "note":
			_refresh_tools())
	_net.peer_joined.connect(func(_p: int, _pr: Dictionary) -> void: refresh_bar())
	_net.peer_left.connect(func(_p: int, _r: String) -> void: refresh_bar())
	_net.session_started.connect(func(_h: bool) -> void: refresh_bar())
	_net.session_ended.connect(func(_r: String) -> void: refresh_bar())
	var design := Modules.bus("design") as DesignBus
	design.actions_changed.connect(_build_actions)
	design.overlays_changed.connect(_build_views)
	design.panels_changed.connect(build_side_panels)
	design.overlay_changed.connect(func(id: String) -> void:
		if id == str(room.get("overlay")):
			show_overlay_panel(id))
	_build_actions()
	_build_views()
	build_side_panels()
	_refresh_tools()
	refresh_bar()


func _exit_tree() -> void:
	_book.unbind()


func _process(delta: float) -> void:
	# Up to 1.5 ms a frame of re-costing (all of it at once after an edit on most buildings),
	# and the panel redrawn at most four times a second.
	var current := _book.update(1500)
	_cost_age += delta
	if (_book.revision != _book_rev or _cost_dirty) and _cost_age >= COST_EVERY:
		if current or _cost_age >= 1.0:
			_cost_age = 0.0
			_cost_dirty = not current
			_book_rev = _book.revision
			_refresh_cost()
	_step_age += delta
	if _step_age >= 0.5:
		_step_age = 0.0
		refresh_steps()
	if _summary_dirty and is_inside_tree():
		_summary_dirty = false
		_refresh_summary()
	_hover_age += delta
	if _hover_age >= 0.1:
		_hover_age = 0.0
		_hover_text = _describe_hover()
	if _hover_text != "":
		help.hover(_hover_text)


## The game's theme made dense, like a CAD tool: small text everywhere and tight boxes, so
## the columns show a lot at once.
static func dense_theme(base: Theme) -> Theme:
	var th := base.duplicate() as Theme
	th.default_font_size = FONT
	for type in th.get_font_size_type_list():
		for n in th.get_font_size_list(type):
			th.set_font_size(n, type, mini(th.get_font_size(n, type), FONT + 1))
	for type in th.get_stylebox_type_list():
		for n in th.get_stylebox_list(type):
			var sb := th.get_stylebox(n, type)
			if sb == null:
				continue
			sb = sb.duplicate() as StyleBox
			sb.content_margin_top = minf(sb.content_margin_top, 2.0)
			sb.content_margin_bottom = minf(sb.content_margin_bottom, 2.0)
			sb.content_margin_left = minf(sb.content_margin_left, 5.0)
			sb.content_margin_right = minf(sb.content_margin_right, 5.0)
			th.set_stylebox(n, type, sb)
	for type in th.get_constant_type_list():
		for n in th.get_constant_list(type):
			if n in ["separation", "h_separation", "v_separation", "item_margin", "v_separation"]:
				th.set_constant(n, type, mini(th.get_constant(n, type), 3))
	return th


func _panel(min_w: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", BsxTheme.panel_style(6))
	p.custom_minimum_size.x = min_w
	p.mouse_filter = MOUSE_FILTER_STOP
	return p


func _button(text: String, press: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = FOCUS_NONE
	b.pressed.connect(press)
	return b


## Where the panels' sizes are kept between sessions.
const LAYOUT_PATH := "user://design/layout.cfg"


## Cards stacked with a grip between each: drag it to make one taller and the next shorter.
## The sizes are remembered (LAYOUT_PATH), per dock `id`.
func splitter(id: String) -> VSplitContainer:
	var sp := VSplitContainer.new()
	sp.name = "Split_" + id
	sp.size_flags_vertical = SIZE_EXPAND_FILL
	sp.add_theme_constant_override("separation", 8)
	sp.dragger_visibility = SplitContainer.DRAGGER_VISIBLE
	sp.tooltip_text = ""
	sp.set_meta("layout_id", id)
	sp.drag_ended.connect(func() -> void: _save_split(sp))
	return sp


func _load_split(sp: VSplitContainer) -> void:
	var cfg := ConfigFile.new()
	var key := str(sp.get_meta("layout_id"))
	if cfg.load(LAYOUT_PATH) != OK or not cfg.has_section_key("splits", key):
		return
	var v: Variant = cfg.get_value("splits", key)
	if v is Array or v is PackedInt32Array:
		var offs := PackedInt32Array(v)
		if offs.size() == sp.split_offsets.size() or sp.split_offsets.is_empty():
			sp.split_offsets = offs


func _save_split(sp: VSplitContainer) -> void:
	var cfg := ConfigFile.new()
	cfg.load(LAYOUT_PATH)
	cfg.set_value("splits", str(sp.get_meta("layout_id")), Array(sp.split_offsets))
	DirAccess.make_dir_recursive_absolute(LAYOUT_PATH.get_base_dir())
	cfg.save(LAYOUT_PATH)


## A framed card: a title bar (click it to fold the card) over its body, so each block of
## information stands apart. `tip` says what the card is for (the help bar shows it).
func card(title: String, body: Control, id: String, tip := "") -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "Card_" + id
	p.add_theme_stylebox_override("panel", BsxTheme.card_style(4.0, 0.9))
	p.size_flags_vertical = body.size_flags_vertical
	p.size_flags_stretch_ratio = body.size_flags_stretch_ratio
	p.mouse_filter = MOUSE_FILTER_PASS
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)
	var head := Button.new()
	head.name = "Title"
	head.flat = true
	head.focus_mode = FOCUS_NONE
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.tooltip_text = tip
	head.add_theme_font_size_override("font_size", 11)
	head.add_theme_color_override("font_color", BsxTheme.ACCENT)
	head.add_theme_color_override("font_hover_color", BsxTheme.ACCENT)
	head.add_theme_constant_override("h_separation", 4)
	var hb := StyleBoxFlat.new()
	hb.bg_color = Color(BsxTheme.ACCENT, 0.1)
	hb.content_margin_left = 4
	hb.content_margin_top = 1
	hb.content_margin_bottom = 1
	head.add_theme_stylebox_override("normal", hb)
	head.add_theme_stylebox_override("hover", hb)
	head.add_theme_stylebox_override("pressed", hb)
	v.add_child(head)
	v.add_child(body)
	var paint := func() -> void:
		var folded: bool = _folded.get(id, false)
		head.text = ("▸  " if folded else "▾  ") + title.to_upper()
		body.visible = not folded
		p.size_flags_vertical = SIZE_FILL if folded else body.size_flags_vertical
	head.pressed.connect(func() -> void:
		_folded[id] = not _folded.get(id, false)
		paint.call())
	_cards[id] = paint
	paint.call()
	return p


## Folds or opens a card by id (tests, keys).
func fold_card(id: String, folded: bool) -> void:
	_folded[id] = folded
	if _cards.has(id) and (_cards[id] as Callable).is_valid():
		(_cards[id] as Callable).call()


# --- Docks, sections and the mode banner ---------------------------------------------------

## Panels rolled up: dock id -> true.
var rolled: Dictionary = {}
var _dock_bottoms: Dictionary = {}
var _banner: PanelContainer
var _banner_text: RichTextLabel


## A title bar on a dock: drag it to move the dock, ▾ rolls it up to the bar, ⟲ puts it back.
func dock_header(p: PanelContainer, dock: VBoxContainer, title: String, id: String) -> void:
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(BsxTheme.ACCENT, 0.16)
	sb.border_color = Color(BsxTheme.ACCENT, 0.5)
	sb.border_width_bottom = 2
	sb.content_margin_left = 8
	sb.content_margin_right = 4
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	bar.add_theme_stylebox_override("panel", sb)
	bar.mouse_filter = MOUSE_FILTER_STOP
	bar.mouse_default_cursor_shape = CURSOR_MOVE
	bar.tooltip_text = "Drag to move this panel"
	var row := HBoxContainer.new()
	bar.add_child(row)
	var l := BsxTheme.hud_label("⠿  " + title, 12, BsxTheme.ACCENT)
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(l)
	var home := _button("⟲", func() -> void: reset_dock(p, id), "Put this panel back where it was")
	home.flat = true
	row.add_child(home)
	var roll := _button("▾", func() -> void: roll_dock(p, dock, id, not rolled.get(id, false)), "Roll up / down")
	roll.flat = true
	roll.name = "Roll"
	row.add_child(roll)
	dock.add_child(bar)
	bar.set_meta("home", [p.offset_left, p.offset_top, p.offset_right, p.offset_bottom])
	p.set_meta("home", bar.get_meta("home"))
	bar.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseMotion and ((e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT):
			var r := (e as InputEventMouseMotion).relative
			p.offset_left += r.x
			p.offset_right += r.x
			p.offset_top += r.y
			p.offset_bottom += r.y
			accept_event())


## Rolls a dock up to its title bar, or back down.
func roll_dock(p: PanelContainer, dock: VBoxContainer, id: String, up: bool) -> void:
	rolled[id] = up
	for i in range(1, dock.get_child_count()):
		var c := dock.get_child(i) as Control
		if up:
			c.set_meta("was_visible", c.visible)
			c.visible = false
		else:
			c.visible = bool(c.get_meta("was_visible", true))
	if up:
		_dock_bottoms[id] = [p.anchor_bottom, p.offset_bottom]
		p.anchor_bottom = p.anchor_top
		p.offset_bottom = p.offset_top + 36
	elif _dock_bottoms.has(id):
		p.anchor_bottom = float(_dock_bottoms[id][0])
		p.offset_bottom = float(_dock_bottoms[id][1])
	var roll := dock.get_child(0).find_child("Roll", true, false) as Button
	if roll:
		roll.text = "▸" if up else "▾"


func reset_dock(p: PanelContainer, id: String) -> void:
	var dock := p.get_child(0) as VBoxContainer
	if rolled.get(id, false):
		roll_dock(p, dock, id, false)
	var h: Array = p.get_meta("home")
	p.offset_left = float(h[0])
	p.offset_top = float(h[1])
	p.offset_right = float(h[2])
	p.offset_bottom = float(h[3])


## A section's heading: a bright title on a bar, and a line on how to use it.
func section_title(title: String, how: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var l := BsxTheme.hud_label(title, 13, BsxTheme.ACCENT)
	box.add_child(l)
	var h := Label.new()
	h.text = how
	h.add_theme_font_size_override("font_size", 11)
	h.modulate = BsxTheme.MUTED
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(h)
	var line := ColorRect.new()
	line.color = Color(BsxTheme.ACCENT, 0.35)
	line.custom_minimum_size.y = 1
	box.add_child(line)
	return box


## The banner over the middle: what mode this player is in and what a click does.
func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.name = "ModeBanner"
	_banner.mouse_filter = MOUSE_FILTER_IGNORE
	_banner.set_anchors_preset(PRESET_CENTER_TOP)
	_banner.position.y = TOP_H + 2
	_banner_text = RichTextLabel.new()
	_banner_text.bbcode_enabled = true
	_banner_text.fit_content = true
	_banner_text.scroll_active = false
	_banner_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_banner_text.mouse_filter = MOUSE_FILTER_IGNORE
	_banner.add_child(_banner_text)
	add_child(_banner)
	refresh_banner()


## Says the mode: SELECT (and what is selected) or the tool and what it will place.
func refresh_banner() -> void:
	if _banner == null:
		return
	var sel := _session.presence.my_selection()
	var colour := BsxTheme.LIVE
	var head := ""
	var how := ""
	if bool(room.call("stamping")):
		head = "PLACING"
		how = "click to place · R turns · Esc stops"
	elif _session.tool == "select":
		colour = Color(0.12, 0.55, 0.25) if BsxTheme.pencil() else Color(0.45, 1.0, 0.55)
		head = "SELECT MODE"
		if sel.is_empty():
			how = "click a room or part · drag empty floor to pan · Shift+drag a box to select many"
		else:
			var what := _session.label_of(sel[0]) if sel.size() == 1 else "%d items" % sel.size()
			how = "[b]%s[/b] selected · drag to move · corners and edges reshape a room · Del deletes · right-click: Edit / Delete" % what
	else:
		var t := _session.tool
		var label := t.capitalize()
		for d: Dictionary in DesignSession.TOOLS:
			if d.id == t:
				label = str(d.label)
		head = label.to_upper()
		match t:
			"room":
				head += ": " + str(_session.catalog.room_type(_session.room_type).get("label", _session.room_type)).to_upper()
				how = "drag on the plan to size it, let go to draw it"
			"fixture":
				head += ": " + str(_session.catalog.kind(_session.fixture_kind).get("label", "")).to_upper()
				how = "click to place · R turns"
			_:
				for d: Dictionary in DesignSession.TOOLS:
					if d.id == t:
						how = str(d.hint)
		how += " · [b]1[/b] or [b]Esc[/b]: back to Select"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(BsxTheme.PANEL, 0.94)
	sb.border_color = colour
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	_banner.add_theme_stylebox_override("panel", sb)
	_banner_text.text = "[color=#%s][b]%s[/b][/color]   [color=#%s]%s[/color]" % [colour.to_html(false), head,
			BsxTheme.TEXT.to_html(false), how]
	if help:
		help.set_help(head, HelpBar.keys_text(mode_keys()), colour)
	_banner.reset_size()
	_banner.position.x = (size.x - _banner.size.x) * 0.5


# --- Top bar ----------------------------------------------------------------------------

func _build_top() -> void:
	var p := _panel(0)
	p.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	p.offset_left = 8
	p.offset_right = -8
	p.offset_top = 8
	add_child(p)
	# Two rows: the room's own controls, then views, layers and other modules' buttons.
	var rows := VBoxContainer.new()
	p.add_child(rows)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	rows.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	rows.add_child(row2)
	var title := BsxTheme.hud_label("DESIGN ROOM", 14, BsxTheme.ACCENT)
	row.add_child(title)
	_crew_label = RichTextLabel.new()
	_crew_label.bbcode_enabled = true
	_crew_label.fit_content = true
	_crew_label.scroll_active = false
	_crew_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_crew_label.custom_minimum_size.x = 260
	_crew_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_crew_label.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(_crew_label)
	row.add_child(_button("▼", func() -> void: _session.set_level(_session.level - 1), "Level down (Page Down)"))
	_level_label = Label.new()
	_level_label.custom_minimum_size.x = 120
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_level_label)
	row.add_child(_button("▲", func() -> void: _session.set_level(_session.level + 1), "Level up (Page Up)"))
	row.add_child(_button("+ Storey", _session.add_level, "Add a storey on top"))
	row.add_child(VSeparator.new())
	row.add_child(Label.new())
	(row.get_child(row.get_child_count() - 1) as Label).text = "Grid"
	_grid_pick = OptionButton.new()
	_grid_pick.focus_mode = FOCUS_NONE
	for g: float in DesignSession.GRIDS:
		_grid_pick.add_item("%.2f m" % g)
	_grid_pick.select(maxi(0, DesignSession.GRIDS.find(_session.grid)))
	_grid_pick.item_selected.connect(func(i: int) -> void:
		_session.set_grid(DesignSession.GRIDS[i])
		Settings.set_value(DesignBus.SETTINGS, "grid", DesignSession.GRIDS[i])
		room.call("_draw_grid"))
	row.add_child(_grid_pick)
	_view_button = _button("2D plan", func() -> void: room.call("toggle_plan"), "Switch between the 3D view and the 2D plan (Tab)")
	row.add_child(_view_button)
	row.add_child(VSeparator.new())
	row.add_child(_button("Undo", _session.undo, "Undo your last edit (Ctrl+Z)"))
	row.add_child(_button("Redo", _session.redo, "Redo (Ctrl+Y)"))
	row.add_child(VSeparator.new())
	row.add_child(_button("Save", open_save, "Save this design to your library (Ctrl+S)"))
	row.add_child(_button("Load", open_load, "Load a design for everyone (Ctrl+O)"))
	row.add_child(_button("New", _session.new_design, "Start a new, empty design for everyone"))
	var layers := MenuButton.new()
	layers.text = "Layers"
	layers.flat = false
	layers.focus_mode = FOCUS_NONE
	layers.tooltip_text = "Show or hide rooms, notes, pings and wall lengths"
	var pop := layers.get_popup()
	_layers_pop = pop
	pop.hide_on_checkable_item_selection = false
	for i in LAYERS.size():
		pop.add_check_item(LAYERS[i][1], i)
		pop.set_item_checked(i, true)
	pop.id_pressed.connect(func(i: int) -> void:
		if i >= LAYER_ID0:
			# Another module's 3D layer: its own toggle (shared by it if it should be).
			var l: Dictionary = (Modules.bus("design") as DesignBus).layers.get(str(pop.get_item_metadata(pop.get_item_index(i))), {})
			if not l.is_empty():
				(l.toggle as Callable).call()
				pop.set_item_checked(pop.get_item_index(i), bool((l.is_on as Callable).call()))
			return
		var on := not pop.is_item_checked(i)
		pop.set_item_checked(i, on)
		set_layer(str(LAYERS[i][0]), on))
	pop.about_to_popup.connect(refresh_layer_menu)
	(Modules.bus("design") as DesignBus).layers_changed.connect(refresh_layer_menu)
	refresh_layer_menu()
	row2.add_child(layers)
	_look = CheckButton.new()
	_look.text = "Realistic"
	_look.focus_mode = FOCUS_NONE
	_look.tooltip_text = "Off: plain white sketch model with ink lines, for designing. On: real materials (V)"
	_look.button_pressed = ArtStyle.realistic()
	_look.toggled.connect(set_realistic)
	Graphics.changed.connect(_on_graphics_changed)
	row2.add_child(_look)
	_views = OptionButton.new()
	_views.focus_mode = FOCUS_NONE
	_views.tooltip_text = "The view you look through: Architect, or another discipline's overlay"
	_views.item_selected.connect(func(i: int) -> void: room.call("set_overlay", str(_views.get_item_metadata(i))))
	row2.add_child(_views)
	_section_toggle = CheckButton.new()
	_section_toggle.text = "Section"
	_section_toggle.focus_mode = FOCUS_NONE
	_section_toggle.tooltip_text = "A section through the building along the bottom (Shift+wheel on it moves the cut)"
	_section_toggle.toggled.connect(show_section)
	row2.add_child(_section_toggle)
	# The workflow comes first on the second row: 1 Get contract, 2 Design, 3 Build it,
	# 4 Hand over, with each module's buttons under its step.
	_actions = HBoxContainer.new()
	_actions.name = "Workflow"
	_actions.add_theme_constant_override("separation", 4)
	row2.add_child(_actions)
	row2.move_child(_actions, 0)
	var sep := VSeparator.new()
	row2.add_child(sep)
	row2.move_child(sep, 1)
	# Walking inside sits top right, on its own, where it's easy to find.
	_walk_slot = HBoxContainer.new()
	row.add_child(_walk_slot)
	row.add_child(_button("Menu", Menu.open_pause, "Pause menu (Esc)"))


## The look for this player: the sketch model (false) or real materials (true). It is the
## same setting as Graphics > Display > Look, so it sticks.
func set_realistic(on: bool) -> void:
	if on == ArtStyle.realistic():
		return
	GraphicsOptions.set_value("art_style", ArtStyle.REALISTIC if on else ArtStyle.MODEL)
	GraphicsOptions.save_settings()
	Graphics.apply_all()


func _on_graphics_changed() -> void:
	_look.set_pressed_no_signal(ArtStyle.realistic())


## The workflow's steps, in order, and which top-bar actions (DesignBus.register_action ids)
## belong under each. Actions not listed go at the end, after the steps.
const STEPS := [
	{"id": "contract", "title": "GET CONTRACT", "tip": "Pick a job from the contract board: its brief, plot and budget"},
	{"id": "design", "title": "DESIGN", "tip": "Draw the building, then let the engineers design and check it",
			"actions": ["structure.design", "services.design", "structure.stress", "services.route", "services.review"]},
	{"id": "build", "title": "BUILD IT", "tip": "Watch the crew build it, day by day", "actions": ["timelapse.build"]},
	{"id": "handover", "title": "HAND OVER", "tip": "Hand the finished building to the client and get paid"},
]
var _steps: Dictionary = {}  # step id -> PanelContainer
var _step_age := 10.0
var _contract_pop: PopupPanel
## The step this player is on now, and the one after it.
var step_now := "design"
var step_next := "build"


func _build_actions() -> void:
	for c in _actions.get_children():
		_actions.remove_child(c)
		c.queue_free()
	for c in _walk_slot.get_children():
		c.queue_free()
	_steps.clear()
	var design := Modules.bus("design") as DesignBus
	var placed := {}
	var n := 0
	for st: Dictionary in STEPS:
		n += 1
		if n > 1:
			var arrow := Label.new()
			arrow.text = "›"
			arrow.modulate = BsxTheme.MUTED
			_actions.add_child(arrow)
		var chip := PanelContainer.new()
		chip.name = "Step_" + str(st.id)
		chip.tooltip_text = str(st.tip)
		chip.mouse_filter = MOUSE_FILTER_PASS
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 3)
		chip.add_child(h)
		var head := Label.new()
		head.name = "Head"
		head.text = "%d %s" % [n, st.title]
		head.add_theme_font_size_override("font_size", 11)
		head.mouse_filter = MOUSE_FILTER_PASS
		head.tooltip_text = str(st.tip)
		h.add_child(head)
		match str(st.id):
			"contract":
				h.add_child(_button("Contracts…", open_contracts, "The contract board: take a job, see the brief"))
			"handover":
				var b := _button("Hand over", hand_over, "Hand the finished building to the client (after Build it)")
				b.name = "HandOver"
				h.add_child(b)
		for id: String in st.get("actions", []):
			if design.actions.has(id):
				var a: Dictionary = design.actions[id]
				var press: Callable = a.press
				h.add_child(_button(str(a.label), func() -> void: press.call(_model)))
				placed[id] = true
		_actions.add_child(chip)
		_steps[st.id] = chip
	var others := false
	for a: Dictionary in design.action_list():
		var id := str(a.get("id", ""))
		if placed.has(id):
			continue
		var press: Callable = a.press
		var b := _button(str(a.label), func() -> void: press.call(_model))
		if id in TOP_RIGHT_ACTIONS:
			b.text = str(a.label).to_upper()
			b.add_theme_color_override("font_color", BsxTheme.ACCENT)
			b.tooltip_text = "Walk round inside the design, first person"
			_walk_slot.add_child(b)
		else:
			if not others:
				others = true
				_actions.add_child(VSeparator.new())
			_actions.add_child(b)
	_step_age = 10.0
	refresh_steps()


## Works out the step this player is on, and lights it: done steps ticked, the current one
## framed in the accent colour, the next one named.
func refresh_steps() -> void:
	if _steps.is_empty():
		return
	var contracts := Modules.bus("contracts")
	var has_contracts := contracts != null and "active" in contracts
	var taken := has_contracts and not (contracts.get("active") as Dictionary).is_empty()
	var built := is_built()
	if has_contracts and not taken:
		step_now = "contract"
		step_next = "design"
	elif not built:
		step_now = "design"
		step_next = "build"
	else:
		step_now = "handover" if taken else "build"
		step_next = ""
	var order := ["contract", "design", "build", "handover"]
	var at := order.find(step_now)
	for i in order.size():
		var id: String = order[i]
		if not _steps.has(id):
			continue
		var chip: PanelContainer = _steps[id]
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 5
		sb.content_margin_right = 3
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		var head := chip.find_child("Head", true, false) as Label
		var colour := BsxTheme.MUTED
		var done := id != step_now and (i < at or (id == "contract" and taken))
		if id == step_now:
			sb.bg_color = Color(BsxTheme.ACCENT, 0.14)
			sb.border_color = BsxTheme.ACCENT
			sb.set_border_width_all(2)
			colour = BsxTheme.ACCENT
		elif done:
			sb.bg_color = Color(0.2, 0.6, 0.3, 0.08)
			sb.border_color = Color(0.12, 0.55, 0.25, 0.6)
			sb.set_border_width_all(1)
			colour = Color(0.12, 0.55, 0.25) if BsxTheme.pencil() else Color(0.45, 1.0, 0.55)
		else:
			sb.bg_color = Color(BsxTheme.PANEL, 0.0)
			sb.border_color = Color(BsxTheme.MUTED, 0.4)
			sb.set_border_width_all(1)
		chip.add_theme_stylebox_override("panel", sb)
		if head:
			var title := str(STEPS[i].title)
			head.text = ("▶ %d %s" % [i + 1, title]) if id == step_now else ("✓ " + title) if done else ("%d %s" % [i + 1, title])
			head.add_theme_color_override("font_color", colour)


## True once this design has been built in the timelapse (to its last day).
func is_built() -> bool:
	var tl := Modules.bus("timelapse")
	if tl == null or not tl.has_method("is_active") or not bool(tl.call("is_active")):
		return false
	return float(tl.call("day")) >= float(tl.call("total_days")) - 0.01


## Step 4: hands the building over. Before it is built, says so and starts the build.
func hand_over() -> void:
	var contracts := Modules.bus("contracts")
	if contracts == null or not "active" in contracts or (contracts.get("active") as Dictionary).is_empty():
		_show_status("Take a contract first (step 1, Contracts…): there's no client to hand over to.", true)
		return
	if not is_built():
		_show_status("Build it first: the hand-over comes at the end of the build.", true)
		var design := Modules.bus("design") as DesignBus
		if design.actions.has("timelapse.build"):
			(design.actions["timelapse.build"].press as Callable).call(_model)
		return
	var tl := Modules.bus("timelapse")
	contracts.call("hand_over", ceili(float(tl.call("total_days"))))
	_show_status("Handed over: the client has the keys.", false)


## Step 1: the contract board in a window over the designer.
func open_contracts() -> void:
	var design := Modules.bus("design") as DesignBus
	var ch: Dictionary = design.channels.get("contracts.board", {})
	if ch.is_empty() or not (ch.make as Callable).is_valid():
		_show_status("No contracts here: design freely.", false)
		return
	if _contract_pop:
		_contract_pop.queue_free()
	_contract_pop = PopupPanel.new()
	_contract_pop.name = "ContractsPopup"
	_contract_pop.add_theme_stylebox_override("panel", BsxTheme.panel_style(8))
	# A fixed-size page: the board's own lists scroll inside it.
	var box := MarginContainer.new()
	box.custom_minimum_size = Vector2(980, 620)
	_contract_pop.add_child(box)
	var page: Variant = (ch.make as Callable).call(_model)
	if page is Control:
		(page as Control).size_flags_horizontal = SIZE_EXPAND_FILL
		(page as Control).size_flags_vertical = SIZE_EXPAND_FILL
		box.add_child(page as Control)
	add_child(_contract_pop)
	_contract_pop.popup_centered()


## Menu ids of other modules' 3D layers start here.
const LAYER_ID0 := 100


## Lists other modules' 3D layers (DesignBus.register_layer) under the room's own in the
## Layers menu, ticked when on.
func refresh_layer_menu() -> void:
	var pop := _layers_pop
	if pop == null:
		return
	while pop.item_count > LAYERS.size():
		pop.remove_item(pop.item_count - 1)
	var list := (Modules.bus("design") as DesignBus).layer_list()
	if list.is_empty():
		return
	pop.add_separator()
	for i in list.size():
		var l: Dictionary = list[i]
		pop.add_check_item(str(l.label), LAYER_ID0 + i)
		var idx := pop.item_count - 1
		pop.set_item_metadata(idx, str(l.id))
		pop.set_item_checked(idx, bool((l.is_on as Callable).call()) if (l.is_on as Callable).is_valid() else false)


## Flips a layer from outside the menu (the mark-up wheel), keeping the menu's tick in step.
func toggle_layer(id: String) -> void:
	for i in LAYERS.size():
		if LAYERS[i][0] == id:
			var on := not _layers_pop.is_item_checked(i)
			_layers_pop.set_item_checked(i, on)
			set_layer(id, on)


func set_layer(id: String, on: bool) -> void:
	if id == "rooms":
		(room.get("view") as Node).call("set_show_rooms", on)
	else:
		(room.get("marks") as Node).call("set_layer", id, on)


func _build_views() -> void:
	_views.clear()
	_views.add_item("View: Architect")
	_views.set_item_metadata(0, "")
	var design := Modules.bus("design") as DesignBus
	for o: Dictionary in design.overlay_list():
		_views.add_item("View: %s" % o.label)
		_views.set_item_metadata(_views.item_count - 1, o.id)
	var cur := str(room.get("overlay"))
	for i in _views.item_count:
		if str(_views.get_item_metadata(i)) == cur:
			_views.select(i)
	_views.visible = _views.item_count > 1


## Puts the overlay's panel (if it has one) above the cost panel; "" takes it away.
func show_overlay_panel(id: String) -> void:
	for c in _overlay_slot.get_children():
		c.queue_free()
	var design := Modules.bus("design") as DesignBus
	var o: Dictionary = design.overlays.get(id, {})
	var make: Callable = o.get("panel", Callable())
	_overlay_slot.visible = make.is_valid()
	if make.is_valid():
		var panel: Variant = make.call()
		if panel is Control:
			_overlay_slot.add_child(card("View: " + str(o.get("label", id)), panel as Control, "overlay",
					"The %s view's own panel" % o.get("label", id)))


func refresh_bar() -> void:
	if _level_label == null:
		return
	var lv: Dictionary = _model.levels[_session.level]
	_level_label.text = "%s (%d/%d)" % [str(lv.get("name", "Level")), _session.level + 1, _model.level_count()]
	var mode := "Solo"
	if _net.is_online():
		mode = "Hosting" if _net.is_host() else "Joined"
	var names: PackedStringArray = []
	var peers := _net.peers()
	var ids: Array = peers.keys()
	ids.sort()
	for peer: int in ids:
		names.append("[color=#%s]%s[/color]" % [_net.player_colour(peer).to_html(false), _net.player_name(peer)])
	_crew_label.text = "%s · %s" % [mode, "  ".join(names)]
	var cam: Variant = room.get("camera")
	_view_button.text = "3D view" if cam != null and bool(cam.get("plan")) else "2D plan"


# --- Tools ------------------------------------------------------------------------------

func _build_tools() -> void:
	var p := _panel(PANEL_W)
	p.set_anchors_and_offsets_preset(PRESET_LEFT_WIDE)
	p.offset_left = 8
	p.offset_top = TOP_H
	p.offset_bottom = -58
	p.offset_right = 8 + PANEL_W
	add_child(p)
	var dock := VBoxContainer.new()
	p.add_child(dock)
	dock_header(p, dock, "DESIGN TOOLS", "left")
	dock.add_theme_constant_override("separation", 6)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.1
	var split := splitter("left")
	dock.add_child(split)
	split.add_child(card("Tools", scroll, "tools", "Pick a tool: 1 Select · 2 Room · 3 Wall … (keys); its options show under the buttons"))
	palette = preload("res://modules/design/internal/room/design_palette.gd").new()
	palette.name = "Palette"
	palette.set("room", room)
	split.add_child(card("Add to the design", palette, "add", "Pick a room type or an object, then draw it on the plan"))
	browser = preload("res://modules/design/internal/room/design_browser.gd").new()
	browser.name = "Browser"
	browser.set("room", room)
	browser.size_flags_vertical = SIZE_EXPAND_FILL
	split.add_child(card("In this design", browser, "browser", "Everything in the design: click to select · right-click a part for Edit / Delete"))
	left_dock = p
	_load_split(split)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(col)
	var grid := GridContainer.new()
	grid.columns = 3
	col.add_child(grid)
	for t: Dictionary in DesignSession.TOOLS:
		var key := "" if int(t.key) == KEY_NONE else "  [%s]" % OS.get_keycode_string(int(t.key))
		var b := _button(str(t.label) + key, func() -> void: _session.set_tool(str(t.id)), str(t.hint))
		b.toggle_mode = true
		# The armed tool stands out: filled in its colour (Select green, the rest amber).
		var on := StyleBoxFlat.new()
		on.bg_color = Color(0.45, 1.0, 0.55, 0.3) if t.id == "select" else Color(BsxTheme.LIVE, 0.28)
		on.border_color = (Color(0.12, 0.55, 0.25) if BsxTheme.pencil() else Color(0.45, 1.0, 0.55)) if t.id == "select" else BsxTheme.LIVE
		on.set_border_width_all(2)
		on.set_corner_radius_all(3)
		on.content_margin_left = 6
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		b.add_theme_color_override("font_pressed_color", BsxTheme.TEXT)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(b)
		_tool_buttons[t.id] = b
	col.add_child(HSeparator.new())
	_options = VBoxContainer.new()
	col.add_child(_options)


func _refresh_tools() -> void:
	for id: String in _tool_buttons:
		(_tool_buttons[id] as Button).set_pressed_no_signal(id == _session.tool)
	for c in _options.get_children():
		c.queue_free()
	var cat := _session.catalog
	match _session.tool:
		"room", "select":
			var types := PackedStringArray()
			for category: String in ["domestic", "office", "services", "education", "police", "health", "transport"]:
				types.append_array(cat.room_types_in(category))
			_option("Room type", types, _session.room_type, func(v: String) -> void:
				_session.room_type = v
				if _session.tool == "select":
					_session.retag_selection(), func(v: String) -> String: return str(cat.room_type(v).get("label", v)))
			if _session.tool == "room":
				var walls := CheckBox.new()
				walls.text = "Walls round new rooms"
				walls.button_pressed = _session.auto_walls
				walls.focus_mode = FOCUS_NONE
				walls.toggled.connect(func(on: bool) -> void:
					_session.auto_walls = on
					Settings.set_value(DesignBus.SETTINGS, "auto_walls", on))
				_options.add_child(walls)
				_wall_material()
			else:
				var hint := Label.new()
				hint.text = "Pick a type to retag the selected rooms (T)."
				hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				hint.modulate = BsxTheme.MUTED
				_options.add_child(hint)
				_furnish_box()
		"wall":
			_wall_material()
		"door":
			_option("Door", cat.kinds_in("opening").duplicate(), _session.door_kind, func(v: String) -> void: _session.door_kind = v,
					func(v: String) -> String: return str(cat.kind(v).get("label", v)), "door")
		"window":
			_option("Window", cat.kinds_in("opening").duplicate(), _session.window_kind, func(v: String) -> void: _session.window_kind = v,
					func(v: String) -> String: return str(cat.kind(v).get("label", v)), "window")
		"column", "beam":
			_option("Material", cat.materials_for(DesignSession.KIND[_session.tool]), _session.frame_material,
					func(v: String) -> void: _session.frame_material = v, func(v: String) -> String: return str(cat.material(v).get("label", v)))
		"note":
			_notes_list()
		"fixture":
			_option("Furniture", cat.kinds_in("fixture"), _session.fixture_kind, func(v: String) -> void: _session.fixture_kind = v,
					func(v: String) -> String: return str(cat.kind(v).get("label", v)))


func _furnish_box() -> void:
	var l := Label.new()
	l.text = "Furnish the selected rooms"
	_options.add_child(l)
	_options.add_child(_button("Usual layout", func() -> void: _session.furnish_selection(), "Furniture this kind of room usually has"))
	var text := LineEdit.new()
	text.placeholder_text = "or describe: 2 single beds, a desk"
	var go := func() -> void: _session.furnish_selection(text.text)
	text.text_submitted.connect(func(_t: String) -> void: go.call())
	_options.add_child(text)
	_options.add_child(_button("Furnish from description", go))


func _notes_list() -> void:
	var notes: Array = (room.get("marks") as Node).get_script().notes_of(_model)
	var l := Label.new()
	l.text = "Notes in this design (%d)" % notes.size()
	_options.add_child(l)
	for n: Dictionary in notes:
		var row := HBoxContainer.new()
		var t := Label.new()
		t.text = "L%d %s: %s" % [int(n.get("level", 0)), str(n.get("author", "")), str(n.get("text", ""))]
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(t)
		var key := str(n.key)
		row.add_child(_button("×", func() -> void: _session.remove_note(key), "Remove this note"))
		_options.add_child(row)


func ask_note(at: Vector3, target: String) -> void:
	_note_at = at
	_note_target = target
	_note_text.text = ""
	_note_text.placeholder_text = "Note on %s" % (_session.label_of(target) if target != "" else "this spot")
	_note_popup.popup_centered()
	_note_text.grab_focus()


func _do_note() -> void:
	_session.add_note(_note_at, _note_target, _note_text.text)
	_note_popup.hide()


func _wall_material() -> void:
	var cat := _session.catalog
	_option("Wall", cat.materials_for("wall_loadbearing"), _session.wall_material, func(v: String) -> void: _session.wall_material = v,
			func(v: String) -> String: return str(cat.material(v).get("label", v)))


func _option(label: String, values: PackedStringArray, current: String, pick: Callable, name_of: Callable, only := "") -> void:
	var l := Label.new()
	l.text = label
	_options.add_child(l)
	var o := OptionButton.new()
	o.focus_mode = FOCUS_NONE
	o.fit_to_longest_item = false
	var list := PackedStringArray()
	for v in values:
		if only == "" or v.begins_with(only):
			list.append(v)
	for v in list:
		o.add_item(str(name_of.call(v)))
	o.select(maxi(0, list.find(current)))
	o.item_selected.connect(func(i: int) -> void: pick.call(list[i]))
	_options.add_child(o)


# --- Cost panel -------------------------------------------------------------------------

func _build_cost() -> void:
	var p := _panel(COST_W)
	p.set_anchors_and_offsets_preset(PRESET_RIGHT_WIDE)
	p.offset_right = -8
	p.offset_left = -8 - COST_W
	p.offset_top = TOP_H
	p.offset_bottom = -58
	add_child(p)
	var dock := VBoxContainer.new()
	p.add_child(dock)
	dock_header(p, dock, "VIEWS AND CHECKS", "right")
	dock.add_theme_constant_override("separation", 6)
	right_dock = p
	# The small 3D view on top: the whole building, whatever the middle is showing.
	_mini_box = PanelContainer.new()
	_mini_box.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_mini_box.custom_minimum_size.y = MINI_H
	var m := ModelChannel.new()
	m.setup(mini, "3d")
	m.distance = 0.75
	m.name = "Mini3D"
	m.tooltip_text = "The whole building, every level: drag to turn, wheel to zoom, middle-click to ping"
	mini_3d = m
	_mini_box.add_child(m)
	_mini_box.size_flags_vertical = SIZE_EXPAND_FILL
	var split := splitter("right")
	dock.add_child(split)
	split.add_child(card("3D view", _mini_box, "mini", "The whole building, every level, whatever the middle shows"))
	# Under it the dock scrolls as one: the summary, the View's panel, the live windows, the cost.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 2.2
	split.add_child(scroll)
	_load_split(split)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	scroll.add_child(col)
	_summary = RichTextLabel.new()
	_summary.name = "Summary"
	_summary.bbcode_enabled = true
	_summary.scroll_active = false
	_summary.fit_content = true
	_summary.mouse_filter = MOUSE_FILTER_PASS
	col.add_child(card("Design summary", _summary, "summary", "The design at a glance: size, parts, cost, checks and what you have selected"))
	_overlay_slot = VBoxContainer.new()
	_overlay_slot.visible = false
	col.add_child(_overlay_slot)
	_side_slot = VBoxContainer.new()
	_side_slot.name = "SidePanels"
	_side_slot.visible = false
	_side_slot.add_theme_constant_override("separation", 6)
	col.add_child(_side_slot)
	_cost = RichTextLabel.new()
	_cost.bbcode_enabled = true
	_cost.scroll_active = false
	_cost.fit_content = true
	_cost.mouse_filter = MOUSE_FILTER_PASS
	col.add_child(card("Cost", _cost, "cost", "What the design costs, live: by element, by level and by room"))
	_session.presence.selection_changed.connect(func(_p: int, _ids: PackedStringArray) -> void: _summary_dirty = true)


## Rebuilds the other modules' always-on windows (DesignBus.register_panel), each under a
## title button that folds it.
func build_side_panels() -> void:
	for c in _side_slot.get_children():
		_side_slot.remove_child(c)
		c.queue_free()
	var list := (Modules.bus("design") as DesignBus).panel_list()
	_side_slot.visible = not list.is_empty()
	for p: Dictionary in list:
		var id := str(p.id)
		var body: Variant = (p.make as Callable).call(_model) if (p.make as Callable).is_valid() else null
		if body is Control:
			_side_slot.add_child(card(str(p.title), body as Control, "panel:" + id, "%s: live, updated as the design changes" % p.title))


## Folds or opens a side panel (tests, keys).
func fold_side_panel(id: String, folded: bool) -> void:
	fold_card("panel:" + id, folded)


func side_panel_count() -> int:
	return (Modules.bus("design") as DesignBus).panels.size() if _side_slot.visible else 0


func _refresh_cost() -> void:
	var sum := _book.summary()
	_cost.text = DesignCosts.bbcode(sum, COST_ROOMS, 18)
	_refresh_summary(sum)


## Folds or opens the small 3D view at the top of the right dock.
func show_mini_3d(on: bool) -> void:
	fold_card("mini", not on)


# --- Section ----------------------------------------------------------------------------

func _build_section() -> void:
	var p := _panel(0)
	p.name = "Section"
	p.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	p.offset_left = 16 + PANEL_W
	p.offset_right = -16 - COST_W
	p.offset_bottom = -62
	p.offset_top = -62 - SECTION_H
	p.visible = false
	add_child(p)
	_section_box = p
	var m := ModelChannel.new()
	m.setup(mini, "section")
	m.name = "SectionView"
	section = m
	p.add_child(m)


## Shows or hides the section along the bottom of the middle.
func show_section(on: bool) -> void:
	_section_box.visible = on
	if _section_toggle.button_pressed != on:
		_section_toggle.set_pressed_no_signal(on)


# --- Status line ------------------------------------------------------------------------

func _build_status() -> void:
	help = HelpBar.new()
	add_child(help)
	help.set_insets(8, 8)
	# The bar is a layer of its own: it hides with the HUD (walking inside, the hall).
	visibility_changed.connect(func() -> void: help.visible = is_visible_in_tree())
	help.visible = is_visible_in_tree()


func _show_status(text: String, warn: bool) -> void:
	help.say(text, warn)


## What the keys and mouse do in this player's mode now: [[key, what], ...].
func mode_keys() -> Array:
	var out: Array = []
	if bool(room.call("stamping")):
		out = [["LMB", "place"], ["R", "turn"], ["Esc", "stop"]]
	else:
		match _session.tool:
			"select":
				if _session.presence.my_selection().is_empty():
					out = [["LMB", "select"], ["LMB drag", "pan"], ["Shift+drag", "box select"], ["Shift", "add"], ["RMB", "Edit / Delete menu"]]
				else:
					out = [["LMB drag", "move"], ["Handles", "reshape"], ["Del", "delete"], ["Shift+M", "mirror copy"], ["Shift+drag", "box adds"], ["RMB", "Edit / Delete"], ["Esc", "deselect"]]
			"room", "slab", "roof", "raft":
				out = [["LMB drag", "size it"], ["release", "draw it"], ["Esc", "Select"]]
			"wall", "partition", "beam", "footing", "stair":
				out = [["LMB", "each point"], ["RMB", "end the run"], ["Esc", "Select"]]
			"measure":
				out = [["LMB", "two points"], ["Esc", "Select"]]
			_:
				out = [["LMB", "place"], ["R", "turn"], ["Esc", "Select"]]
	out.append_array([["Wheel", "zoom"], ["RMB drag", "orbit"], ["MMB", "ping (on a ping: clear it) · hold: wheel"], ["Tab", "2D/3D"],
			["PgUp/Dn", "level"], ["Ctrl+Z", "undo"]])
	return out


## What the pointer is over on the plan or model: a room's size, a part's kind and material.
func _describe_hover() -> String:
	if _session.cursor == null or bool(room.call("_pointer_over_hud")):
		return ""
	var id := _session.pick(_session.cursor as Vector3)
	if id == "":
		return "%s · grid %.2f m" % [_where(_session.cursor as Vector3), _session.grid]
	return describe(id)


func _where(at: Vector3) -> String:
	return "x %.2f  z %.2f m" % [at.x, at.z]


## One line on an entry: "Kitchen · room · 12.4 m² (min 9) · Ground floor".
func describe(id: String) -> String:
	var bits := PackedStringArray([_session.label_of(id)])
	if _model.rooms.has(id):
		var r: Dictionary = _model.rooms[id]
		bits.append("room")
		bits.append("%.1f m²" % BuildingModel.outline_area(r.get("outline", []) as Array))
		bits.append(_level_name(int(r.get("level", 0))))
	elif _model.parts.has(id):
		var e: Dictionary = _model.parts[id]
		var mat := str(e.get("material", ""))
		if mat != "":
			bits.append(str(_session.catalog.material(mat).get("label", mat)))
		if e.has("a") and e.has("b"):
			var a: Array = e.a
			var b: Array = e.b
			bits.append("%.2f m long" % Vector2(float(b[0]) - float(a[0]), float(b[2]) - float(a[2])).length())
		bits.append(_level_name(int(e.get("level", 0))))
	bits.append("right-click: Edit / Delete")
	return " · ".join(bits)


func _level_name(i: int) -> String:
	if i < 0 or i >= _model.level_count():
		return "level %d" % i
	return str(_model.levels[i].get("name", "Level %d" % i))


## The design at a glance, and what this player has selected.
func _refresh_summary(sum: Dictionary = {}) -> void:
	if _summary == null:
		return
	if sum.is_empty():
		sum = _book.summary()
	var dim := BsxTheme.MUTED.to_html(false)
	var cur := str(sum.get("currency", ""))
	var rows: Array = [
		["Levels", str(_model.level_count())],
		["Rooms", "%d · %.0f m²" % [(sum.get("rooms", []) as Array).size(), float(sum.get("floor_area", 0.0))]],
		["Parts", str(_model.parts.size())],
		["Cost", DesignCosts.money(float(sum.get("total", 0.0)), cur)],
	]
	if float(sum.get("floor_area", 0.0)) > 0.0:
		rows.append(["per m²", DesignCosts.money(float(sum.total) / float(sum.floor_area), cur)])
	var warn := 0
	for n: Dictionary in sum.get("notes", []):
		if bool(n.get("warn", false)):
			warn += 1
	var checks := "all clear" if warn == 0 else "%d to look at (see Cost)" % warn
	rows.append(["Checks", "[color=#%s]%s[/color]" % [(BsxTheme.WARN if warn > 0 else Color(0.12, 0.55, 0.25)).to_html(false), checks]])
	var t := "[table=2]"
	for r: Array in rows:
		t += "[cell][color=#%s]%s[/color]  [/cell][cell]%s[/cell]" % [dim, r[0], r[1]]
	t += "[/table]"
	var sel := _session.presence.my_selection()
	if not sel.is_empty():
		t += "\n[b]Selected[/b]  [color=#%s]%d[/color]\n" % [dim, sel.size()]
		for i in mini(sel.size(), 4):
			t += "%s\n" % describe(sel[i]).trim_suffix(" · right-click: Edit / Delete")
		if sel.size() > 4:
			t += "[color=#%s]and %d more[/color]\n" % [dim, sel.size() - 4]
	_summary.text = t


# --- Save and load ------------------------------------------------------------------------

func _build_popups() -> void:
	_save_popup = PopupPanel.new()
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(380, 0)
	_save_popup.add_child(col)
	var l := Label.new()
	l.text = "Save design as"
	col.add_child(l)
	_save_name = LineEdit.new()
	_save_name.text_submitted.connect(func(_t: String) -> void: _do_save())
	col.add_child(_save_name)
	col.add_child(_button("Save", _do_save))
	add_child(_save_popup)

	_note_popup = PopupPanel.new()
	var col3 := VBoxContainer.new()
	col3.custom_minimum_size = Vector2(420, 0)
	_note_popup.add_child(col3)
	var l3 := Label.new()
	l3.text = "Note for the team"
	col3.add_child(l3)
	_note_text = LineEdit.new()
	_note_text.max_length = 280
	_note_text.text_submitted.connect(func(_t: String) -> void: _do_note())
	col3.add_child(_note_text)
	col3.add_child(_button("Pin note", _do_note))
	add_child(_note_popup)

	_load_popup = PopupPanel.new()
	var col2 := VBoxContainer.new()
	col2.custom_minimum_size = Vector2(380, 320)
	_load_popup.add_child(col2)
	var l2 := Label.new()
	l2.text = "Load a design (replaces the building for everyone)"
	col2.add_child(l2)
	_load_list = ItemList.new()
	_load_list.size_flags_vertical = SIZE_EXPAND_FILL
	_load_list.item_activated.connect(func(_i: int) -> void: _do_load())
	col2.add_child(_load_list)
	col2.add_child(_button("Load", _do_load))
	add_child(_load_popup)


func open_save() -> void:
	_save_name.text = _model.name if _model.name != "New building" else "My house"
	_save_popup.popup_centered()
	_save_name.grab_focus()
	_save_name.select_all()


func _do_save() -> void:
	var n := _save_name.text.strip_edges()
	if n == "":
		return
	_session.save_design(n)
	_save_popup.hide()


func open_load() -> void:
	_load_list.clear()
	for n in DesignSession.list_designs():
		_load_list.add_item(n)
	if _load_list.item_count == 0:
		_load_list.add_item("(no saved designs yet)")
		_load_list.set_item_disabled(0, true)
	_load_popup.popup_centered()


func _do_load() -> void:
	var sel := _load_list.get_selected_items()
	if sel.is_empty() or _load_list.is_item_disabled(sel[0]):
		return
	_session.load_design(_load_list.get_item_text(sel[0]))
	_load_popup.hide()
