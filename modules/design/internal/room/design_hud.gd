extends Control
## The design room's HUD: the top bar (crew, level, grid, 2D/3D, undo, redo, save, load,
## other modules' actions), the tool column with the tool's options, the live cost and
## requirement panel, and the status line.

const PANEL_W := 300
const COST_W := 340

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
var _status: Label
var _options: VBoxContainer
var _actions: HBoxContainer
var _views: OptionButton
var _overlay_slot: VBoxContainer
var _note_popup: PopupPanel
var _note_text: LineEdit
var _note_at := Vector3.ZERO
var _note_target := ""
const LAYERS := [["rooms", "Rooms"], ["notes", "Notes"], ["pings", "Pings"], ["dimensions", "Wall lengths"]]
var _save_popup: PopupPanel
var _save_name: LineEdit
var _load_popup: PopupPanel
var _load_list: ItemList
var _cost_dirty := true
var _status_age := 0.0


func _ready() -> void:
	_session = room.get("session")
	_model = _session.model
	_net = _session.net
	theme = BsxTheme.get_theme()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_build_top()
	_build_tools()
	_build_cost()
	_build_status()
	_build_popups()
	_session.tool_changed.connect(func(_t: String) -> void: _refresh_tools())
	_session.level_changed.connect(func(_l: int) -> void: refresh_bar())
	_session.status.connect(_show_status)
	_model.changed.connect(func(op: Dictionary) -> void:
		_cost_dirty = true
		if str(op.get("op", "")) == "set_meta" and _session.tool == "note":
			_refresh_tools())
	_model.loaded.connect(func() -> void: _cost_dirty = true)
	_net.peer_joined.connect(func(_p: int, _pr: Dictionary) -> void: refresh_bar())
	_net.peer_left.connect(func(_p: int, _r: String) -> void: refresh_bar())
	_net.session_started.connect(func(_h: bool) -> void: refresh_bar())
	_net.session_ended.connect(func(_r: String) -> void: refresh_bar())
	var design := Modules.bus("design") as DesignBus
	design.actions_changed.connect(_build_actions)
	design.overlays_changed.connect(_build_views)
	design.overlay_changed.connect(func(id: String) -> void:
		if id == str(room.get("overlay")):
			show_overlay_panel(id))
	_build_actions()
	_build_views()
	_refresh_tools()
	refresh_bar()


func _process(delta: float) -> void:
	if _cost_dirty:
		_cost_dirty = false
		_refresh_cost()
	_status_age += delta
	if _status_age > 6.0 and _status.modulate.a > 0.0:
		_status.modulate.a = maxf(0.0, _status.modulate.a - delta)


func _panel(min_w: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", BsxTheme.panel_style(10))
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


# --- Top bar ----------------------------------------------------------------------------

func _build_top() -> void:
	var p := _panel(0)
	p.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	p.offset_left = 8
	p.offset_right = -8
	p.offset_top = 8
	add_child(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	p.add_child(row)
	var title := BsxTheme.hud_label("DESIGN ROOM", 20, BsxTheme.ACCENT)
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
	pop.hide_on_checkable_item_selection = false
	for i in LAYERS.size():
		pop.add_check_item(LAYERS[i][1], i)
		pop.set_item_checked(i, true)
	pop.id_pressed.connect(func(i: int) -> void:
		var on := not pop.is_item_checked(i)
		pop.set_item_checked(i, on)
		set_layer(str(LAYERS[i][0]), on))
	row.add_child(layers)
	_views = OptionButton.new()
	_views.focus_mode = FOCUS_NONE
	_views.tooltip_text = "The view you look through: Architect, or another discipline's overlay"
	_views.item_selected.connect(func(i: int) -> void: room.call("set_overlay", str(_views.get_item_metadata(i))))
	row.add_child(_views)
	_actions = HBoxContainer.new()
	row.add_child(_actions)
	row.add_child(_button("Menu", Menu.open_pause, "Pause menu (Esc)"))


func _build_actions() -> void:
	for c in _actions.get_children():
		c.queue_free()
	var design := Modules.bus("design") as DesignBus
	for a: Dictionary in design.action_list():
		var press: Callable = a.press
		_actions.add_child(_button(str(a.label), func() -> void: press.call(_model)))


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
			_overlay_slot.add_child(panel)


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
	p.offset_top = 64
	p.offset_bottom = -44
	p.offset_right = 8 + PANEL_W
	add_child(p)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(col)
	col.add_child(BsxTheme.hud_label("TOOLS", 16, BsxTheme.HUD_DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	col.add_child(grid)
	for t: Dictionary in DesignSession.TOOLS:
		var key := "" if int(t.key) == KEY_NONE else "  [%s]" % OS.get_keycode_string(int(t.key))
		var b := _button(str(t.label) + key, func() -> void: _session.set_tool(str(t.id)), str(t.hint))
		b.toggle_mode = true
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(b)
		_tool_buttons[t.id] = b
	col.add_child(HSeparator.new())
	_options = VBoxContainer.new()
	col.add_child(_options)
	col.add_child(HSeparator.new())
	var keys := Label.new()
	keys.text = "Left drag: use tool\nRight drag: orbit · Middle: pan · Wheel: zoom\nMiddle click: ping · Tab 2D/3D · PgUp/PgDn level\nDel delete · Ctrl+Z undo · Ctrl+Y redo · R turn · Esc cancel"
	keys.add_theme_font_size_override("font_size", 13)
	keys.modulate = BsxTheme.MUTED
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(keys)


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
	p.offset_top = 64
	p.offset_bottom = -44
	add_child(p)
	var col := VBoxContainer.new()
	p.add_child(col)
	_overlay_slot = VBoxContainer.new()
	_overlay_slot.visible = false
	_overlay_slot.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(_overlay_slot)
	_cost = RichTextLabel.new()
	_cost.bbcode_enabled = true
	_cost.scroll_active = true
	_cost.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(_cost)


func _refresh_cost() -> void:
	var s := DesignCosts.summary(_model)
	var cur := str(s.currency)
	var t := "[font_size=14][color=#%s]COST · LIVE[/color][/font_size]\n" % BsxTheme.HUD_DIM.to_html(false)
	t += "[font_size=30][b]%s[/b][/font_size]\n" % DesignCosts.money(s.total, cur)
	t += "[color=#%s]structure %s · fit-out %s · floor %.0f m²[/color]\n" % [BsxTheme.MUTED.to_html(false),
			DesignCosts.money(s.structure, cur), DesignCosts.money(s.fit_out, cur), s.floor_area]
	if float(s.floor_area) > 0.0:
		t += "[color=#%s]%s per m²[/color]\n" % [BsxTheme.MUTED.to_html(false), DesignCosts.money(float(s.total) / float(s.floor_area), cur)]
	t += "\n[b]By element[/b]\n"
	t += _rows(s.families, cur)
	if (s.families as Array).is_empty():
		t += "[color=#%s]Nothing placed yet.[/color]\n" % BsxTheme.MUTED.to_html(false)
	t += "\n[b]By level[/b]\n"
	t += _rows(s.levels, cur)
	t += "\n[b]Rooms[/b]\n"
	for r: Dictionary in s.rooms:
		var c := BsxTheme.WARN.to_html(false) if r.short else BsxTheme.TEXT.to_html(false)
		t += "[color=#%s]%s · L%d · %.1f m²%s[/color]\n" % [c, r.label, int(r.level), r.area,
				" (min %.0f)" % r.min_area if r.short else ""]
	if (s.rooms as Array).is_empty():
		t += "[color=#%s]No rooms yet: paint one with the Room tool.[/color]\n" % BsxTheme.MUTED.to_html(false)
	var notes: Array = s.notes
	if not notes.is_empty():
		t += "\n[b]Notes[/b]\n"
		for n: Dictionary in notes:
			var c := BsxTheme.WARN.to_html(false) if n.warn else BsxTheme.LIVE.to_html(false)
			t += "[color=#%s]• %s[/color]\n  [color=#%s]%s[/color]\n" % [c, n.text, BsxTheme.MUTED.to_html(false), n.tip]
	_cost.text = t


## Label and money in two columns, the money right-aligned.
static func _rows(rows: Array, cur: String) -> String:
	if rows.is_empty():
		return ""
	var t := "[table=2]"
	for r: Dictionary in rows:
		t += "[cell expand=3]%s[/cell][cell expand=1][right]%s[/right][/cell]" % [r.label, DesignCosts.money(r.cost, cur)]
	return t + "[/table]\n"


# --- Status line ------------------------------------------------------------------------

func _build_status() -> void:
	var p := _panel(0)
	p.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	p.offset_left = 16 + PANEL_W
	p.offset_right = -16 - COST_W
	p.offset_bottom = -8
	p.offset_top = -40
	p.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(p)
	_status = Label.new()
	_status.clip_text = true
	p.add_child(_status)


func _show_status(text: String, warn: bool) -> void:
	_status.text = text
	_status.modulate = BsxTheme.WARN if warn else BsxTheme.TEXT
	_status_age = 0.0


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
