extends PanelContainer
## The floating object preview: a small window with a title bar to drag it by, a roll-up
## button that folds it to its bar, and a close button. It stays where the player left it
## (per viewport) and shows whatever was clicked last.

signal closed

var preview: KitPreview
var _bar: HBoxContainer
var _title: Label
var _fold: Button
var _drag_from: Variant = null
var rolled := false


func _init() -> void:
	name = "KitPreviewWindow"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := BsxTheme.panel_style(10)
	add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	_bar = HBoxContainer.new()
	_bar.name = "Bar"
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_bar.gui_input.connect(_on_bar_input)
	col.add_child(_bar)
	_title = Label.new()
	_title.text = "PREVIEW"
	_title.add_theme_font_size_override("font_size", 12)
	_title.add_theme_color_override("font_color", BsxTheme.MUTED)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.mouse_filter = Control.MOUSE_FILTER_PASS
	_bar.add_child(_title)
	_fold = _small("▾", "Roll up", toggle_roll)
	_fold.name = "Fold"
	_bar.add_child(_fold)
	var x := _small("×", "Close", func() -> void:
		hide()
		closed.emit())
	x.name = "Close"
	_bar.add_child(x)
	preview = KitPreview.new()
	col.add_child(preview)


func toggle_roll() -> void:
	set_rolled(not rolled)


func set_rolled(on: bool) -> void:
	rolled = on
	preview.visible = not on
	_fold.text = "▸" if on else "▾"
	_fold.tooltip_text = "Roll down" if on else "Roll up"
	reset_size()


func _small(text: String, tip: String, press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(26, 22)
	b.pressed.connect(press)
	return b


func _on_bar_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		if mb.double_click:
			toggle_roll()
		_drag_from = mb.global_position - global_position if mb.pressed else null
		accept_event()
	elif ev is InputEventMouseMotion and _drag_from != null:
		var vp := get_viewport_rect().size
		var to: Vector2 = (ev as InputEventMouseMotion).global_position - (_drag_from as Vector2)
		position = to.clamp(Vector2.ZERO, (vp - Vector2(80, 30)).max(Vector2.ZERO))
		accept_event()
