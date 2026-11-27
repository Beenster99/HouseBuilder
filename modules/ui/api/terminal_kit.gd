class_name TerminalKit
extends RefCounted
## The terminal look for every screen in the game, in pencil: sheets of drawing paper with
## graphite outlines (PencilBox), Barlow Condensed titles, Barlow prose, JetBrains Mono
## numbers, a blue pencil for the picked tab and the main action, and a
## double pencil rule under the header. Pass `glass = true` for an overlay over the game:
## the same sheets as tracing paper, see-through.
##   var row := TerminalKit.row([TerminalKit.cell_text("Lintel", "Precast concrete"),
##           TerminalKit.cell("24", 60), TerminalKit.cell("£ 120", 96, TerminalKit.TEXT, "mono_bold")], alt, glass)
## (The colour names are the BSX terminal's, kept so callers don't change: in pencil ORANGE
## is the blue pencil, PLATE and KIOSK are paper, EDGE and BLACK are graphite. With the
## Classic look (BsxTheme.set_pencil(false)) they and every helper are BSX's again.)

const PENCIL_COLOURS := {
	"KIOSK": Color(0.93, 0.915, 0.87),
	"PLATE": Color(0.953, 0.937, 0.894),
	"PLATE_HI": Color(0.925, 0.905, 0.855),
	"EDGE": Color(0.17, 0.18, 0.2),
	"STEEL": Color(0.36, 0.38, 0.41),
	"TEXT": Color(0.17, 0.18, 0.2),
	"DIM": Color(0.4, 0.42, 0.45),
	"ORANGE": Color(0.17, 0.36, 0.58),
	"ORANGE_HI": Color(0.25, 0.47, 0.72),
	"BLACK": Color(0.17, 0.18, 0.2),
	"DOCKET": Color(0.965, 0.955, 0.925),
	"INK": Color(0.17, 0.18, 0.2),
	"INK_DIM": Color(0.4, 0.42, 0.45),
	"GOOD": Color(0.22, 0.48, 0.22),
	"BAD": Color(0.7, 0.22, 0.17),
	"CYAN": Color(0.17, 0.36, 0.58),
	"AMBER": Color(0.7, 0.46, 0.1),
	"GLASS_DIM": Color(0.3, 0.32, 0.35),
}
const CLASSIC_COLOURS := {
	"KIOSK": Color("16191c"),
	"PLATE": Color("2a2f34"),
	"PLATE_HI": Color("363c42"),
	"EDGE": Color("0d0f11"),
	"STEEL": Color("8a939b"),
	"TEXT": Color("e4e2dc"),
	"DIM": Color("8b949c"),
	"ORANGE": Color("e8792b"),
	"ORANGE_HI": Color("ff9a4d"),
	"BLACK": Color("111111"),
	"DOCKET": Color("cfccc3"),
	"INK": Color("1f2328"),
	"INK_DIM": Color("5b6168"),
	"GOOD": Color("7fd47a"),
	"BAD": Color("ff5a3c"),
	"CYAN": Color("6fc8e8"),
	"AMBER": Color("e8c25a"),
	"GLASS_DIM": Color("b4bcc3"),
}
static var KIOSK := Color(0.93, 0.915, 0.87)
static var PLATE := Color(0.953, 0.937, 0.894)
static var PLATE_HI := Color(0.925, 0.905, 0.855)
static var EDGE := Color(0.17, 0.18, 0.2)
static var STEEL := Color(0.36, 0.38, 0.41)
static var TEXT := Color(0.17, 0.18, 0.2)
static var DIM := Color(0.4, 0.42, 0.45)
static var ORANGE := Color(0.17, 0.36, 0.58)
static var ORANGE_HI := Color(0.25, 0.47, 0.72)
static var BLACK := Color(0.17, 0.18, 0.2)
static var DOCKET := Color(0.965, 0.955, 0.925)
static var INK := Color(0.17, 0.18, 0.2)
static var INK_DIM := Color(0.4, 0.42, 0.45)
static var GOOD := Color(0.22, 0.48, 0.22)
static var BAD := Color(0.7, 0.22, 0.17)
static var CYAN := Color(0.17, 0.36, 0.58)
static var AMBER := Color(0.7, 0.46, 0.1)
## How opaque plates and the kiosk are on glass.
const GLASS_PLATE := 0.86
const GLASS_KIOSK := 0.9
## On glass (tracing paper over the game) a channel's text is this much bigger and its dim
## text this dark, so it reads over a busy scene (HoloTerminal applies it with glass_text()).
const GLASS_TEXT := 1.2
static var GLASS_DIM := Color(0.3, 0.32, 0.35)
## Settings > Gameplay "Terminal text": how big terminal and screen text and list rows are,
## so a tab can hold more. Sizes passed to the kit are at Standard; it scales them.
const TEXT_SECTION := "terminal"
const TEXT_KEY := "text"
const TEXT_SIZES := {"Compact": 0.82, "Standard": 1.0, "Large": 1.15}
const TEXT_DEFAULT := "Compact"


## Switches the palette and the helpers between pencil and Classic (BsxTheme.set_pencil).
static func use_pencil(on: bool) -> void:
	var c: Dictionary = PENCIL_COLOURS if on else CLASSIC_COLOURS
	KIOSK = c.KIOSK
	PLATE = c.PLATE
	PLATE_HI = c.PLATE_HI
	EDGE = c.EDGE
	STEEL = c.STEEL
	TEXT = c.TEXT
	DIM = c.DIM
	ORANGE = c.ORANGE
	ORANGE_HI = c.ORANGE_HI
	BLACK = c.BLACK
	DOCKET = c.DOCKET
	INK = c.INK
	INK_DIM = c.INK_DIM
	GOOD = c.GOOD
	BAD = c.BAD
	CYAN = c.CYAN
	AMBER = c.AMBER
	GLASS_DIM = c.GLASS_DIM


static func pencil() -> bool:
	return BsxTheme.pencil()


## The chosen text scale (Compact by default).
static func text_scale() -> float:
	var v: Variant = Settings.get_value(TEXT_SECTION, TEXT_KEY)
	return float(TEXT_SIZES.get(str(v), TEXT_SIZES[TEXT_DEFAULT]))


## Makes a label or button readable on glass: bigger text, dim text brighter. Once per node.
static func glass_text(c: Control) -> void:
	if c.has_meta("glass_text") or not (c is Label or c is Button or c is LineEdit):
		return
	c.set_meta("glass_text", true)
	c.add_theme_font_size_override("font_size", roundi(c.get_theme_font_size("font_size") * GLASS_TEXT))
	var key := "font_color"
	if c.has_theme_color_override(key):
		var col := c.get_theme_color(key)
		if col.is_equal_approx(DIM) or col.is_equal_approx(STEEL):
			c.add_theme_color_override(key, GLASS_DIM)


## A size, font or width, at the chosen text scale.
static func px(n: float) -> int:
	return maxi(1, roundi(n * text_scale()))


static func font(face: String) -> Font:
	return BsxTheme.font(face)


## A plate colour, see-through on glass.
static func tone(c: Color, glass: bool, alpha := GLASS_PLATE) -> Color:
	return Color(c, c.a * alpha) if glass else c


static func box(bg: Color, border_color := Color.TRANSPARENT, border := 0, margin := 0.0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	if border > 0:
		b.border_color = border_color
		b.set_border_width_all(border)
	b.set_content_margin_all(margin)
	b.anti_aliasing = false
	return b


## A sheet of paper with a pencil outline (tracing paper on glass).
static func plate(margin := 12.0, glass := false, bg := PLATE) -> StyleBox:
	if not pencil():
		return _plate_classic(margin, glass, bg)
	var b := PencilBox.make(tone(bg, glass), Color(EDGE, 0.7 if glass else 0.8), margin, 1.5)
	b.shade = 0.0 if glass else 3.0
	return b


static func _plate_classic(margin := 12.0, glass := false, bg := PLATE) -> StyleBoxFlat:
	var b := box(tone(bg, glass), tone(EDGE, glass, 0.8), 2, margin)
	b.border_width_top = 3
	b.shadow_color = Color(0, 0, 0, 0.12 if glass else 0.35)
	b.shadow_size = 3
	return b


static func label(text: String, face: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(face))
	l.add_theme_font_size_override("font_size", px(size))
	l.add_theme_color_override("font_color", color)
	return l


## A pencil button: the main action (`filled`) is drawn heavier in blue pencil and shaded
## in, the rest are graphite outlines; `on` underlines a picked tab in blue.
static func button(text: String, filled := false, size := 20, on := false, glass := false) -> Button:
	if not pencil():
		return _button_classic(text, filled, size, on, glass)
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font("display_bold" if filled or on else "display"))
	b.add_theme_font_size_override("font_size", px(size))
	var m := px(6.0)
	var normal := BsxTheme.button_style("pressed" if filled else "normal", m)
	if glass:
		normal.fill = Color(normal.fill, normal.fill.a * GLASS_PLATE)
	if on:
		normal = PencilBox.make(tone(PLATE, glass), ORANGE, m, 2.2)
		normal.content_margin_left = m + 6.0
		normal.content_margin_right = m + 6.0
		normal.sides = Vector4i(0, 0, 0, 1)
		normal.hatch = Color(ORANGE, 0.12)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", BsxTheme.button_style("hover", m))
	b.add_theme_stylebox_override("pressed", BsxTheme.button_style("pressed", m))
	b.add_theme_stylebox_override("hover_pressed", BsxTheme.button_style("pressed", m))
	b.add_theme_stylebox_override("disabled", BsxTheme.button_style("disabled", m))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ink := ORANGE if filled or on else STEEL
	b.add_theme_color_override("font_color", ink if filled or on else TEXT)
	b.add_theme_color_override("font_hover_color", ORANGE)
	b.add_theme_color_override("font_pressed_color", ORANGE)
	b.add_theme_color_override("font_hover_pressed_color", ORANGE)
	b.add_theme_color_override("font_disabled_color", Color(TEXT, 0.35))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func() -> void: Sfx.press(b))
	b.set_meta("sfx", true)
	return b


static func _button_classic(text: String, filled := false, size := 20, on := false, glass := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font("display_bold" if filled else "display"))
	b.add_theme_font_size_override("font_size", px(size))
	var bg := ORANGE if filled else (PLATE_HI if on else PLATE)
	var a := 0.85 if filled else GLASS_PLATE + 0.1
	var normal := box(tone(bg, glass, a), ORANGE if on else tone(EDGE, glass, 0.8), 2, px(8.0))
	if on:
		normal.border_width_left = 0
		normal.border_width_right = 0
		normal.border_width_top = 0
		normal.border_width_bottom = 4
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", box(tone(ORANGE_HI if filled else PLATE_HI, glass, a + 0.1), ORANGE, 2, 8.0))
	b.add_theme_stylebox_override("pressed", box(tone(ORANGE.darkened(0.2), glass, 0.9), ORANGE, 2, 8.0))
	b.add_theme_stylebox_override("disabled", box(Color(bg, 0.25 if glass else 0.35), tone(EDGE, glass, 0.6), 2, 8.0))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ink := BLACK if filled else (TEXT if on else STEEL)
	b.add_theme_color_override("font_color", ink)
	b.add_theme_color_override("font_hover_color", BLACK if filled else TEXT)
	b.add_theme_color_override("font_pressed_color", BLACK if filled else TEXT)
	b.add_theme_color_override("font_disabled_color", Color(ink, 0.4))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func() -> void: Sfx.press(b))
	b.set_meta("sfx", true)
	return b


## A search box in the terminal's plate style; `on_changed(text)` as the player types.
static func search(placeholder: String, on_changed: Callable, glass := false) -> LineEdit:
	if not pencil():
		return _search_classic(placeholder, on_changed, glass)
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.clear_button_enabled = true
	e.custom_minimum_size = Vector2(px(220), px(34))
	e.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	e.add_theme_font_override("font", font("body_medium"))
	e.add_theme_font_size_override("font_size", px(17))
	e.add_theme_color_override("font_color", TEXT)
	e.add_theme_color_override("font_placeholder_color", DIM)
	e.add_theme_color_override("caret_color", ORANGE)
	var st := PencilBox.make(Color(1, 1, 1, 0.5 if glass else 0.6), Color(EDGE, 0.6), 6.0, 1.2)
	st.passes = 1
	st.content_margin_left = 10
	e.add_theme_stylebox_override("normal", st)
	var focus := st.duplicate() as PencilBox
	focus.ink = ORANGE
	focus.width = 2.0
	e.add_theme_stylebox_override("focus", focus)
	e.text_changed.connect(on_changed)
	return e


static func _search_classic(placeholder: String, on_changed: Callable, glass := false) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.clear_button_enabled = true
	e.custom_minimum_size = Vector2(px(220), px(34))
	e.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	e.add_theme_font_override("font", font("body_medium"))
	e.add_theme_font_size_override("font_size", px(17))
	e.add_theme_color_override("font_color", TEXT)
	e.add_theme_color_override("font_placeholder_color", DIM)
	e.add_theme_color_override("caret_color", ORANGE)
	var st := box(tone(EDGE, glass, 0.7), tone(PLATE_HI, glass, 0.9), 2, 6.0)
	st.content_margin_left = 10
	e.add_theme_stylebox_override("normal", st)
	var focus := box(tone(EDGE, glass, 0.8), ORANGE, 2, 6.0)
	focus.content_margin_left = 10
	e.add_theme_stylebox_override("focus", focus)
	e.text_changed.connect(on_changed)
	return e


## A row of filter chips (ALL first when `all` is set); `on_pick(name)`, "" for ALL.
static func chips(names: PackedStringArray, current: String, on_pick: Callable, glass := false, all := true) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	var list := PackedStringArray([""]) if all else PackedStringArray()
	list.append_array(names)
	for n in list:
		var b := button(n.to_upper() if n != "" else "ALL", false, 15, n == current, glass)
		b.pressed.connect(on_pick.bind(n))
		flow.add_child(b)
	return flow


## Column headings over a list: specs are [text, width] (width 0 = takes the rest).
static func columns(specs: Array) -> MarginContainer:
	var head := HBoxContainer.new()
	for spec: Array in specs:
		var l := label(spec[0], "display_medium", 14, DIM)
		if int(spec[1]) == 0:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			l.custom_minimum_size.x = px(spec[1])
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head.add_child(l)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_right", 22)
	pad.add_child(head)
	return pad


## One line of a list, as a ledger: ruled in faint pencil underneath, alternate lines a
## shade deeper. `cells` sit left to right.
static func row(cells: Array, alt := false, glass := false) -> PanelContainer:
	if not pencil():
		return _row_classic(cells, alt, glass)
	var panel := PanelContainer.new()
	var st := PencilBox.make(tone(PLATE_HI if alt else PLATE, glass), Color(EDGE, 0.22), 0, 1.0)
	st.passes = 1
	st.wobble = 0.5
	st.overshoot = 0.0
	st.sides = Vector4i(0, 0, 0, 1)
	st.content_margin_left = 10
	st.content_margin_right = 8
	st.content_margin_top = px(5)
	st.content_margin_bottom = px(5)
	panel.add_theme_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	panel.add_child(h)
	for c: Control in cells:
		h.add_child(c)
	return panel


static func _row_classic(cells: Array, alt := false, glass := false) -> PanelContainer:
	var panel := PanelContainer.new()
	var st := box(tone(PLATE_HI if alt else PLATE, glass), Color.TRANSPARENT, 0, 0)
	st.content_margin_left = 10
	st.content_margin_right = 8
	st.content_margin_top = px(5)
	st.content_margin_bottom = px(5)
	panel.add_theme_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	panel.add_child(h)
	for c: Control in cells:
		h.add_child(c)
	return panel


## A list's name cell: a name over a dim small-caps line; it takes the row's spare width.
static func cell_text(title: String, sub: String = "") -> VBoxContainer:
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -3)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := label(title, "body_medium", 19, TEXT)
	t.clip_text = true
	names.add_child(t)
	if sub != "":
		names.add_child(label(sub.to_upper(), "display_medium", 13, DIM))
	return names


## A right-aligned number cell `width` wide.
static func cell(text: String, width: float, color := DIM, face := "mono_medium") -> Label:
	var l := label(text, face, 17, color)
	l.custom_minimum_size.x = px(width)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## A small coloured tag: "NEW", "IN STOCK", "ON JOB".
static func tag(text: String, color: Color, size := 15) -> CenterContainer:
	if not pencil():
		return _tag_classic(text, color, size)
	var p := PanelContainer.new()
	var st := PencilBox.make(Color(color, 0.08), Color(color, 0.85), 0.0, 1.2)
	st.wobble = 0.6
	st.overshoot = 2.0
	st.content_margin_left = 6
	st.content_margin_right = 6
	st.content_margin_top = 1
	st.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", st)
	p.add_child(label(text.to_upper(), "mono_medium", size, color))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var c := CenterContainer.new()
	c.add_child(p)
	return c


static func _tag_classic(text: String, color: Color, size := 15) -> CenterContainer:
	var p := PanelContainer.new()
	var st := box(Color(color, 0.16), color, 1, 0.0)
	st.content_margin_left = 6
	st.content_margin_right = 6
	st.content_margin_top = 1
	st.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", st)
	p.add_child(label(text.to_upper(), "mono_medium", size, color))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var c := CenterContainer.new()
	c.add_child(p)
	return c


## A scrolling list body; add rows to the returned box (its parent is the ScrollContainer).
static func list() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box_ := VBoxContainer.new()
	box_.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box_.add_theme_constant_override("separation", 3)
	scroll.add_child(box_)
	return box_


## A docket: the side panel with a title over a rule (the purchase order's paper). On glass
## it's pale frosted glass with light ink.
static func docket(title: String, ref: String = "", glass := false) -> Dictionary:
	if not pencil():
		return _docket_classic(title, ref, glass)
	var paper := PanelContainer.new()
	paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := PencilBox.make(Color(DOCKET, 0.82) if glass else DOCKET, Color(EDGE, 0.75), 14, 1.5)
	st.shade = 0.0 if glass else 3.0
	paper.add_theme_stylebox_override("panel", st)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	paper.add_child(col)
	var top := HBoxContainer.new()
	var t := label(title, "display_bold", 26, INK)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	if ref != "":
		top.add_child(label(ref, "mono_medium", 14, INK_DIM))
	col.add_child(top)
	var rule := BsxTheme.rule(6.0)
	col.add_child(rule)
	return {"panel": paper, "body": col}


static func _docket_classic(title: String, ref: String = "", glass := false) -> Dictionary:
	var paper := PanelContainer.new()
	paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := box(Color(DOCKET, 0.16) if glass else DOCKET, tone(EDGE, glass, 0.8), 2, 14)
	st.border_width_top = 8
	st.border_color = STEEL.darkened(0.3) if not glass else Color(STEEL, 0.6)
	paper.add_theme_stylebox_override("panel", st)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	paper.add_child(col)
	var top := HBoxContainer.new()
	var t := label(title.to_upper(), "display_bold", 26, TEXT if glass else INK)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	if ref != "":
		top.add_child(label(ref, "mono_medium", 14, DIM if glass else INK_DIM))
	col.add_child(top)
	var rule := ColorRect.new()
	rule.color = Color(TEXT, 0.4) if glass else INK
	rule.custom_minimum_size.y = 2
	col.add_child(rule)
	return {"panel": paper, "body": col}


## The sections other modules added to `channel` (HudSlots.register_holo_section), one
## docket each, kept up to date as they come and go. Put it where the channel wants them.
static func sections(channel: String, glass := false) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.name = "Sections"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	var fill := func() -> void:
		for c in col.get_children():
			col.remove_child(c)
			c.queue_free()
		for sec: Dictionary in HudSlots.holo_sections(channel):
			var d := docket(str(sec.label), "", glass)
			d.panel.name = "Section_" + str(sec.id).validate_node_name()
			var f: Callable = sec.factory
			var made: Variant = f.call(glass) if f.get_argument_count() >= 1 else f.call()
			if made is Control:
				d.body.add_child(made)
			col.add_child(d.panel)
	fill.call()
	var on_change := func(ch: String) -> void:
		if ch == channel and is_instance_valid(col):
			fill.call()
	HudSlots.holo_sections_changed.connect(on_change)
	col.tree_exiting.connect(func() -> void:
		if HudSlots.holo_sections_changed.is_connected(on_change):
			HudSlots.holo_sections_changed.disconnect(on_change))
	return col


## A big figure with its caption, for summaries ("STOCK VALUE  CR 12,400").
static func figure(what: String, value: String, colour := TEXT, glass := false) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", plate(12.0, glass))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.add_child(label(what.to_upper(), "display_medium", 15, DIM))
	v.add_child(label(value, "mono_bold", 28, colour))
	p.add_child(v)
	return p


## "12,400".
static func money(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## The rule under a header: a double pencil line (it was BSX's orange and black hazard
## stripes; the name stays for callers).
class HazardRule:
	extends Control
	var glass := false

	func _init(height := 8.0, p_glass := false) -> void:
		custom_minimum_size.y = height
		glass = p_glass
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		if not BsxTheme.pencil():
			# BSX's diagonal orange and black stripes.
			var a := 0.75 if glass else 1.0
			draw_rect(Rect2(Vector2.ZERO, size), Color(TerminalKit.BLACK, 0.5 if glass else 1.0))
			var h := size.y
			var x := -h
			while x < size.x + h:
				draw_colored_polygon(PackedVector2Array([Vector2(x, h), Vector2(x + h, 0), Vector2(x + h * 2, 0), Vector2(x + h, h)]), Color(TerminalKit.ORANGE, a))
				x += h * 3
			return
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(roundi(size.x))
		var mid := size.y * 0.5
		for p in 2:
			var y := mid + (p - 0.5) * minf(4.0, size.y * 0.6)
			var pts := PackedVector2Array()
			var steps := clampi(int(size.x / 60.0) + 2, 2, 40)
			var x0 := rng.randf_range(-2.0, 6.0)
			var x1 := size.x - rng.randf_range(-2.0, 12.0)
			for i in steps + 1:
				var t := float(i) / steps
				pts.append(Vector2(lerpf(x0, x1, t), y + sin(t * PI) * rng.randf_range(-0.8, 0.8) + rng.randf_range(-0.3, 0.3)))
			draw_polyline(pts, Color(TerminalKit.EDGE, (0.85 if p == 0 else 0.5) * (0.8 if glass else 1.0)), 1.6 if p == 0 else 1.1, true)
