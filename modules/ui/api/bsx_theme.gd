class_name BsxTheme
extends RefCounted
## The shared look: a pencil drawing on paper, to sit with the game's SketchUp-style sketch
## view. Warm drawing paper, graphite lines gone over twice (PencilBox), a blue pencil for
## what's picked or important, a red pencil for warnings and an ochre one for live values.
## Every module's UI uses BsxTheme.get_theme() and the helpers below so screens match without
## copying styles; UiBus also makes it Godot's default theme (flag ui.pencil), so plain
## controls anywhere come out in pencil too. It can be switched back to the Classic look
## (set_pencil, the "Menu style" setting).
## Fonts stay plain (the person asked for no hand lettering): Barlow Condensed for titles,
## headings and buttons, Barlow for prose, JetBrains Mono for numbers. OFL, licences in fonts/.
## (The class keeps its BSX name so the many callers don't change; the look was BSX's.)

## The paper and the graphite.
const PAPER := Color(0.953, 0.937, 0.894)
const PAPER_DEEP := Color(0.91, 0.89, 0.84)
const INK := Color(0.17, 0.18, 0.2)
const INK_SOFT := Color(0.36, 0.38, 0.41)
const INK_FAINT := Color(0.17, 0.18, 0.2, 0.3)
## Coloured pencils: blue for picked or important, red for warnings, ochre for live values,
## green for good.
const BLUE := Color(0.17, 0.36, 0.58)
const RED := Color(0.7, 0.22, 0.17)
const OCHRE := Color(0.7, 0.46, 0.1)
const GREEN := Color(0.22, 0.48, 0.22)

## The switch: Settings > Gameplay "Menu style" (and the main menu's Settings list), Pencil
## or Classic (BSX's dark glass and cyan). Screens built after a switch use the new look;
## UiBus rebuilds the menu that's open.
const STYLE_SECTION := "interface"
const STYLE_KEY := "style"
const PENCIL := "Pencil"
const CLASSIC := "Classic"
const STYLES := ["Pencil", "Classic"]

## The palettes behind the names every screen uses (BsxTheme.TEXT and so on).
const PENCIL_COLOURS := {
	"BG": PAPER, "ACCENT": BLUE, "PANEL": Color(0.953, 0.937, 0.894, 0.97), "TEXT": INK,
	"MUTED": Color(0.36, 0.38, 0.41, 0.95), "HUD": INK, "HUD_DIM": Color(0.17, 0.18, 0.2, 0.55),
	"WARN": RED, "LIVE": OCHRE, "STATUS": OCHRE,
}
const CLASSIC_COLOURS := {
	"BG": Color(0.015, 0.02, 0.035), "ACCENT": Color(0.62, 0.9, 1.0), "PANEL": Color(0.02, 0.04, 0.07, 0.96),
	"TEXT": Color(0.875, 0.875, 0.875), "MUTED": Color(0.62, 0.9, 1.0, 0.55), "HUD": Color(0.62, 0.9, 1.0, 0.9),
	"HUD_DIM": Color(0.62, 0.9, 1.0, 0.35), "WARN": Color(1.0, 0.45, 0.2, 0.95), "LIVE": Color(1.0, 0.85, 0.2, 1.0),
	"STATUS": Color(1.0, 0.75, 0.5),
}

static var BG := PAPER
static var ACCENT := BLUE
static var PANEL := Color(0.953, 0.937, 0.894, 0.97)
static var TEXT := INK
static var MUTED := Color(0.36, 0.38, 0.41, 0.95)
## HUD colours: readouts (graphite with a paper halo in pencil), dim lines, warnings, live values.
static var HUD := INK
static var HUD_DIM := Color(0.17, 0.18, 0.2, 0.55)
static var WARN := RED
static var LIVE := OCHRE
static var STATUS := OCHRE
static var _pencil := true
static var _base_saved: Theme
static var _fallback_font: Font
static var _fallback_size := 16

const FONT_DIR := "res://modules/ui/api/fonts/"
const FACES := {
	"mono": "JetBrainsMono-Regular.ttf",
	"mono_medium": "JetBrainsMono-Medium.ttf",
	"mono_bold": "JetBrainsMono-Bold.ttf",
	"body": "Barlow-Regular.ttf",
	"body_medium": "Barlow-Medium.ttf",
	"display": "BarlowCondensed-SemiBold.ttf",
	"display_bold": "BarlowCondensed-Bold.ttf",
	"display_medium": "BarlowCondensed-Medium.ttf",
}
## Body text size for plain controls.
const BODY_SIZE := 17

static var _theme: Theme
static var _fonts: Dictionary = {}
static var _icons: Dictionary = {}


## True while the pencil look is on.
static func pencil() -> bool:
	return _pencil


## The look the setting asks for (Pencil unless it says Classic).
static func style_setting() -> String:
	var v: Variant = Settings.get_value(STYLE_SECTION, STYLE_KEY)
	return CLASSIC if str(v) == CLASSIC else PENCIL


## Turns the pencil look on or off: the palette, every helper here and in TerminalKit, and
## Godot's default theme. Controls already built keep their look until rebuilt.
static func set_pencil(on: bool) -> void:
	_pencil = on
	var c: Dictionary = PENCIL_COLOURS if on else CLASSIC_COLOURS
	BG = c.BG
	ACCENT = c.ACCENT
	PANEL = c.PANEL
	TEXT = c.TEXT
	MUTED = c.MUTED
	HUD = c.HUD
	HUD_DIM = c.HUD_DIM
	WARN = c.WARN
	LIVE = c.LIVE
	STATUS = c.STATUS
	TerminalKit.use_pencil(on)
	_theme = null
	apply_everywhere()


## A face from FACES. Loaded once: fresh fonts draw as blocks for a frame.
static func font(face: String = "mono") -> Font:
	if not _fonts.has(face):
		var f := load(FONT_DIR + FACES.get(face, FACES["mono"])) as Font
		_fonts[face] = f if f else ThemeDB.fallback_font
	return _fonts[face]


## Every kind of control in pencil: buttons, fields, lists, tabs, sliders, menus, tooltips.
## Anything not set here falls back to Godot's default theme.
static func get_theme() -> Theme:
	if _theme:
		return _theme
	if not _pencil:
		_theme = Theme.new()
		_theme.set_color("font_color", "Label", TEXT)
		_theme.set_stylebox("panel", "PanelContainer", panel_style())
		_theme.set_stylebox("panel", "Panel", panel_style())
		return _theme
	var t := Theme.new()
	t.default_font = font("body")
	t.default_font_size = BODY_SIZE
	_theme = t
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(PAPER, 0.0))
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	t.set_stylebox("panel", "PopupPanel", panel_style(10))
	t.set_stylebox("panel", "TooltipPanel", card_style(8))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font("font", "TooltipLabel", font("body"))
	var sep := StyleBoxLine.new()
	sep.color = INK_FAINT
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	var vsep := StyleBoxLine.new()
	vsep.color = INK_FAINT
	vsep.thickness = 1
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)

	for type: String in ["Button", "OptionButton", "MenuButton", "LinkButton"]:
		_button_styles(t, type)
	t.set_font("font", "Button", font("display"))
	t.set_font("font", "OptionButton", font("display"))
	t.set_font("font", "MenuButton", font("display"))
	t.set_icon("arrow", "OptionButton", icon("arrow"))
	for type: String in ["CheckBox", "CheckButton"]:
		var none := StyleBoxEmpty.new()
		none.set_content_margin_all(4)
		var lit := PencilBox.make(Color(BLUE, 0.06), Color.TRANSPARENT, 4)
		for s: String in ["normal", "pressed", "disabled", "hover_pressed", "focus"]:
			t.set_stylebox(s, type, none)
		t.set_stylebox("hover", type, lit)
		t.set_stylebox("hover_pressed", type, lit)
		for c: String in ["font_color", "font_pressed_color", "font_focus_color"]:
			t.set_color(c, type, TEXT)
		t.set_color("font_hover_color", type, BLUE)
		t.set_color("font_hover_pressed_color", type, BLUE)
		t.set_color("font_disabled_color", type, Color(INK, 0.35))
	for n: String in ["checked", "unchecked", "radio_checked", "radio_unchecked",
			"checked_disabled", "unchecked_disabled", "radio_checked_disabled", "radio_unchecked_disabled"]:
		t.set_icon(n, "CheckBox", icon(n))
	for n: String in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
		t.set_icon(n, "CheckButton", icon("switch_on" if n.begins_with("checked") else "switch_off"))

	for type: String in ["LineEdit", "TextEdit", "CodeEdit"]:
		var field := PencilBox.make(Color(1, 1, 1, 0.55), Color(INK, 0.55), 6, 1.2)
		field.passes = 1
		field.content_margin_left = 10
		field.sides = Vector4i(0, 0, 0, 1) if type == "LineEdit" else Vector4i(1, 1, 1, 1)
		var focus := field.duplicate() as PencilBox
		focus.ink = BLUE
		focus.width = 2.0
		t.set_stylebox("normal", type, field)
		t.set_stylebox("focus", type, focus)
		var ro := field.duplicate() as PencilBox
		ro.fill = Color(PAPER_DEEP, 0.6)
		ro.ink = INK_FAINT
		t.set_stylebox("read_only", type, ro)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_placeholder_color", type, Color(INK, 0.4))
		t.set_color("caret_color", type, BLUE)
		t.set_color("selection_color", type, Color(BLUE, 0.25))
		t.set_color("font_selected_color", type, INK)
		t.set_color("font_readonly_color", type, Color(INK, 0.6))
		t.set_color("clear_button_color", type, INK_SOFT)
		t.set_color("clear_button_color_pressed", type, BLUE)

	var popup := PencilBox.make(PAPER, Color(INK, 0.85), 6)
	popup.shade = 4.0
	t.set_stylebox("panel", "PopupMenu", popup)
	var popup_hover := PencilBox.make(Color(BLUE, 0.1), Color.TRANSPARENT, 4)
	popup_hover.hatch = Color(BLUE, 0.18)
	popup_hover.hatch_gap = 5.0
	t.set_stylebox("hover", "PopupMenu", popup_hover)
	t.set_stylebox("separator", "PopupMenu", sep)
	t.set_font("font", "PopupMenu", font("body"))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", BLUE)
	t.set_color("font_disabled_color", "PopupMenu", Color(INK, 0.35))
	t.set_color("font_accelerator_color", "PopupMenu", INK_SOFT)
	t.set_color("font_separator_color", "PopupMenu", INK_SOFT)
	t.set_icon("checked", "PopupMenu", icon("checked"))
	t.set_icon("unchecked", "PopupMenu", icon("unchecked"))
	t.set_icon("radio_checked", "PopupMenu", icon("radio_checked"))
	t.set_icon("radio_unchecked", "PopupMenu", icon("radio_unchecked"))
	t.set_icon("submenu", "PopupMenu", icon("submenu"))

	# Sliders: a pencil line with a graphite knob.
	for type: String in ["HSlider", "VSlider"]:
		var track := StyleBoxLine.new()
		track.color = Color(INK, 0.6)
		track.thickness = 2
		track.vertical = type == "VSlider"
		track.grow_begin = 0
		track.grow_end = 0
		var line := StyleBoxFlat.new()
		line.bg_color = Color(INK, 0.55)
		line.content_margin_top = 1
		line.content_margin_bottom = 1
		var fill := StyleBoxFlat.new()
		fill.bg_color = BLUE
		fill.content_margin_top = 2
		fill.content_margin_bottom = 2
		t.set_stylebox("slider", type, line)
		t.set_stylebox("grabber_area", type, fill)
		t.set_stylebox("grabber_area_highlight", type, fill)
		t.set_icon("grabber", type, icon("knob"))
		t.set_icon("grabber_highlight", type, icon("knob_lit"))
		t.set_icon("grabber_disabled", type, icon("knob_off"))
		t.set_icon("tick", type, icon("tick"))

	var bar_back := PencilBox.make(Color(1, 1, 1, 0.4), Color(INK, 0.7), 0, 1.2)
	bar_back.passes = 1
	var bar_fill := PencilBox.make(Color(BLUE, 0.18), Color.TRANSPARENT, 0)
	bar_fill.hatch = Color(BLUE, 0.7)
	bar_fill.hatch_gap = 4.0
	t.set_stylebox("background", "ProgressBar", bar_back)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_color("font_outline_color", "ProgressBar", Color(PAPER, 0.0))

	# Tabs: index cards; the open one is drawn heavier with no bottom line.
	for type: String in ["TabContainer", "TabBar"]:
		var off := PencilBox.make(Color(PAPER_DEEP, 0.7), Color(INK, 0.45), 6, 1.2)
		off.passes = 1
		off.sides = Vector4i(1, 1, 1, 0)
		off.content_margin_left = 14
		off.content_margin_right = 14
		var on := off.duplicate() as PencilBox
		on.fill = PAPER
		on.ink = Color(INK, 0.9)
		on.width = 1.8
		on.passes = 2
		var hover := off.duplicate() as PencilBox
		hover.fill = Color(BLUE, 0.08)
		t.set_stylebox("tab_unselected", type, off)
		t.set_stylebox("tab_selected", type, on)
		t.set_stylebox("tab_hovered", type, hover)
		t.set_stylebox("tab_disabled", type, off)
		t.set_stylebox("tab_focus", type, StyleBoxEmpty.new())
		t.set_font("font", type, font("display"))
		t.set_color("font_selected_color", type, INK)
		t.set_color("font_unselected_color", type, INK_SOFT)
		t.set_color("font_hovered_color", type, BLUE)
		t.set_color("font_disabled_color", type, Color(INK, 0.3))
	t.set_stylebox("panel", "TabContainer", panel_style(14))
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())

	# Scroll bars: a faint pencil groove and a graphite thumb.
	for type: String in ["VScrollBar", "HScrollBar"]:
		var groove := StyleBoxFlat.new()
		groove.bg_color = Color(INK, 0.06)
		groove.set_content_margin_all(4)
		var thumb := StyleBoxFlat.new()
		thumb.bg_color = Color(INK, 0.35)
		thumb.set_corner_radius_all(3)
		var thumb_lit := thumb.duplicate() as StyleBoxFlat
		thumb_lit.bg_color = Color(INK, 0.55)
		var thumb_on := thumb.duplicate() as StyleBoxFlat
		thumb_on.bg_color = BLUE
		t.set_stylebox("scroll", type, groove)
		t.set_stylebox("grabber", type, thumb)
		t.set_stylebox("grabber_highlight", type, thumb_lit)
		t.set_stylebox("grabber_pressed", type, thumb_on)

	# Lists and trees: paper with pencil-shaded selection.
	var pick := PencilBox.make(Color(BLUE, 0.12), Color(BLUE, 0.6), 2, 1.2)
	pick.passes = 1
	var over := PencilBox.make(Color(INK, 0.05), Color.TRANSPARENT, 2)
	for type: String in ["ItemList", "Tree"]:
		var bg := PencilBox.make(Color(1, 1, 1, 0.35), Color(INK, 0.5), 6, 1.2)
		bg.passes = 1
		t.set_stylebox("panel", type, bg)
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_stylebox("selected", type, pick)
		t.set_stylebox("selected_focus", type, pick)
		t.set_stylebox("hovered", type, over)
		t.set_stylebox("cursor", type, StyleBoxEmpty.new())
		t.set_stylebox("cursor_unfocused", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, TEXT)
		t.set_color("font_selected_color", type, INK)
		t.set_color("font_hovered_color", type, INK)
		t.set_color("guide_color", type, INK_FAINT)
	t.set_color("title_button_color", "Tree", TEXT)
	t.set_stylebox("title_button_normal", "Tree", PencilBox.make(PAPER_DEEP, Color(INK, 0.5), 4, 1.0))
	t.set_icon("arrow", "Tree", icon("arrow"))
	t.set_icon("arrow_collapsed", "Tree", icon("submenu"))
	t.set_icon("checked", "Tree", icon("checked"))
	t.set_icon("unchecked", "Tree", icon("unchecked"))

	# Windows and dialogs.
	var win := PencilBox.make(PAPER, Color(INK, 0.85), 12)
	win.shade = 5.0
	for type: String in ["Window", "AcceptDialog", "ConfirmationDialog"]:
		t.set_stylebox("panel", type, panel_style(12))
		t.set_stylebox("embedded_border", type, win)
		t.set_stylebox("embedded_unfocused_border", type, win)
		t.set_color("title_color", type, INK)
		t.set_font("title_font", type, font("display"))
	return _theme


static func _button_styles(t: Theme, type: String) -> void:
	t.set_stylebox("normal", type, button_style("normal"))
	t.set_stylebox("hover", type, button_style("hover"))
	t.set_stylebox("pressed", type, button_style("pressed"))
	t.set_stylebox("hover_pressed", type, button_style("pressed"))
	t.set_stylebox("disabled", type, button_style("disabled"))
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_color("font_color", type, TEXT)
	t.set_color("font_hover_color", type, BLUE)
	t.set_color("font_pressed_color", type, BLUE)
	t.set_color("font_hover_pressed_color", type, BLUE)
	t.set_color("font_focus_color", type, TEXT)
	t.set_color("font_disabled_color", type, Color(INK, 0.35))
	t.set_color("icon_normal_color", type, INK)
	t.set_color("icon_hover_color", type, BLUE)
	t.set_color("icon_pressed_color", type, BLUE)


## A button's box in one state: normal (pencil outline on paper), hover (blue pencil, light
## shading), pressed (blue outline over blue hatching, as a picked option is shaded in),
## disabled (faint).
static func button_style(state: String, margin := 8.0) -> PencilBox:
	var b := PencilBox.make(Color(PAPER, 0.92), Color(INK, 0.75), margin, 1.5)
	b.content_margin_left = margin + 6.0
	b.content_margin_right = margin + 6.0
	match state:
		"hover":
			b.ink = BLUE
			b.fill = Color(0.94, 0.94, 0.92, 0.96)
			b.hatch = Color(BLUE, 0.12)
		"pressed":
			b.ink = BLUE
			b.width = 2.0
			b.fill = Color(0.9, 0.92, 0.94, 0.97)
			b.hatch = Color(BLUE, 0.3)
			b.hatch_gap = 5.0
		"disabled":
			b.ink = Color(INK, 0.25)
			b.fill = Color(PAPER, 0.6)
			b.passes = 1
	return b


## A sheet of paper with a pencil outline: menus, dialogs and side panels.
static func panel_style(margin: int = 20) -> StyleBox:
	if not _pencil:
		return _flat(PANEL, Color(ACCENT, 0.5), 2, 6, margin)
	var s := PencilBox.make(PANEL, Color(INK, 0.8), margin, 1.6)
	s.shade = 4.0
	return s


## The FD badge's box: shaded blue pencil (Classic: solid orange).
static func badge_style() -> StyleBox:
	if not _pencil:
		return _flat(TerminalKit.ORANGE, Color.TRANSPARENT, 0, 0, 0)
	var b := PencilBox.make(Color(BLUE, 0.1), BLUE, 0, 2.0)
	b.hatch = Color(BLUE, 0.25)
	b.hatch_gap = 5.0
	return b


## A small card for over a scene (HUD boxes, tooltips): paper, lighter line, no shadow.
static func card_style(margin := 10.0, alpha := 0.92) -> StyleBox:
	if not _pencil:
		return _flat(Color(PANEL, PANEL.a * alpha * 0.6), Color(ACCENT, 0.35), 1, 4, margin)
	var s := PencilBox.make(Color(PAPER, alpha), Color(INK, 0.6), margin, 1.3)
	s.passes = 1
	return s


## A HUD slot box, as a hotbar: shaded in blue pencil when `on`.
static func slot_style(on: bool) -> StyleBox:
	if not _pencil:
		var f := _flat(Color(ACCENT, 0.18) if on else Color(0, 0, 0, 0.35), HUD if on else Color(ACCENT, 0.18), 2, 4, 10)
		f.content_margin_left = 16
		f.content_margin_right = 16
		return f
	var s := PencilBox.make(Color(PAPER, 0.9 if on else 0.75), BLUE if on else Color(INK, 0.45), 10, 2.0 if on else 1.3)
	s.content_margin_left = 16
	s.content_margin_right = 16
	if on:
		s.hatch = Color(BLUE, 0.22)
		s.hatch_gap = 5.0
	else:
		s.passes = 1
	return s


## A HUD readout: graphite with a paper halo, readable over any scene.
static func hud_label(text: String = "", size: int = 18, color: Color = HUD) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ls := LabelSettings.new()
	ls.font = font("mono_medium" if _pencil else "mono")
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = 6 if _pencil else 4
	ls.outline_color = Color(PAPER, 0.85) if _pencil else Color(0, 0, 0, 0.6)
	l.label_settings = ls
	return l


## A heading.
static func title(text: String, size: int = 52) -> Label:
	var l := Label.new()
	l.text = text
	if _pencil:
		l.add_theme_font_override("font", font("display_bold"))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", INK if _pencil else ACCENT)
	return l


static func muted(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", MUTED)
	return l


static func button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 42)
	if _pencil:
		b.theme = get_theme()
	b.pressed.connect(on_pressed)
	b.pressed.connect(func() -> void: Sfx.press(b))
	b.set_meta("sfx", true)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			Sfx.play("hover", null, -20.0))
	return b


## Drawing paper with a faint drafting grid, filling its parent: a menu's background
## (Classic: the plain dark background).
static func paper_backdrop(grid := true) -> ColorRect:
	var r := ColorRect.new()
	r.name = "Paper"
	r.color = PAPER if _pencil else BG
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	if not _pencil:
		return r
	var m := ShaderMaterial.new()
	m.shader = load("res://modules/ui/api/shaders/paper.gdshader")
	m.set_shader_parameter("paper", PAPER)
	if not grid:
		m.set_shader_parameter("grid", Color(0, 0, 0, 0))
	r.material = m
	return r


## A picture drawn over in pencil (edges outlined, shadows hatched) on paper, faded out to
## plain paper towards the left from `fade.x` to `fade.y` (0 to 1 across).
static func pencil_picture(texture: Texture2D, fade := Vector2(-1.0, 0.0)) -> TextureRect:
	var pic := TextureRect.new()
	pic.texture = texture
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	if not _pencil:
		return pic
	var m := ShaderMaterial.new()
	m.shader = load("res://modules/ui/api/shaders/pencil_sketch.gdshader")
	m.set_shader_parameter("paper", PAPER)
	m.set_shader_parameter("fade", fade)
	pic.material = m
	return pic


## A ruled pencil line across its parent: under titles and headers (Classic: a thin
## accent line).
static func rule(height := 8.0) -> Control:
	if not _pencil:
		var r := ColorRect.new()
		r.color = Color(ACCENT, 0.5)
		r.custom_minimum_size.y = 2
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return r
	return PencilRule.new(height)


static func _flat(bg: Color, border: Color, width: int, radius: int, margin: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


## With the pencil look on, makes the pencil theme Godot's default, so controls anywhere
## (including ones on their own CanvasLayer, which don't inherit a parent's theme) are drawn
## in pencil; with it off, puts Godot's own default back.
static func apply_everywhere() -> void:
	var base := ThemeDB.get_default_theme()
	if base == null:
		return
	if _base_saved == null:
		_base_saved = base.duplicate(true) as Theme
		_fallback_font = ThemeDB.fallback_font
		_fallback_size = ThemeDB.fallback_font_size
	var on := _pencil and Flags.is_on("ui.pencil")
	if base.has_meta("pencil") == on:
		return
	base.clear()
	base.merge_with(_base_saved)
	base.default_font = _base_saved.default_font
	base.default_font_size = _base_saved.default_font_size
	ThemeDB.fallback_font = _fallback_font
	ThemeDB.fallback_font_size = _fallback_size
	base.remove_meta("pencil")
	if on:
		base.merge_with(get_theme())
		base.default_font = font("body")
		base.default_font_size = BODY_SIZE
		base.set_meta("pencil", true)
		ThemeDB.fallback_font = font("body")
		ThemeDB.fallback_font_size = BODY_SIZE


## Small drawn icons (check boxes, radio buttons, switches, knobs, arrows), made once.
static func icon(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var s := 20
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ink := Color(INK, 0.35) if id.ends_with("_disabled") or id == "knob_off" else INK
	var base := id.trim_suffix("_disabled")
	match base:
		"unchecked", "checked":
			_box(img, Rect2(3, 3, 14, 14), ink)
			if base == "checked":
				_line(img, Vector2(5, 10), Vector2(9, 15), BLUE if ink == INK else ink, 1.6)
				_line(img, Vector2(9, 15), Vector2(18, 1), BLUE if ink == INK else ink, 1.6)
		"radio_unchecked", "radio_checked":
			_ring(img, Vector2(10, 10), 7.0, ink, 1.0)
			if base == "radio_checked":
				_disc(img, Vector2(10, 10), 3.6, BLUE if ink == INK else ink)
		"switch_off", "switch_on":
			img = Image.create(34, 20, false, Image.FORMAT_RGBA8)
			img.fill(Color(0, 0, 0, 0))
			_box(img, Rect2(2, 4, 30, 12), ink)
			if base == "switch_on":
				_hatch_rect(img, Rect2(3, 5, 28, 10), Color(BLUE, 0.5))
				_disc(img, Vector2(25, 10), 5.0, BLUE)
			else:
				_ring(img, Vector2(9, 10), 5.0, ink, 1.0)
		"knob", "knob_lit", "knob_off":
			_disc(img, Vector2(10, 10), 6.5, Color(PAPER, 1.0))
			_ring(img, Vector2(10, 10), 6.5, BLUE if id == "knob_lit" else ink, 1.2)
			_disc(img, Vector2(10, 10), 2.0, BLUE if id == "knob_lit" else ink)
		"arrow":
			_line(img, Vector2(5, 8), Vector2(10, 13), ink, 1.2)
			_line(img, Vector2(10, 13), Vector2(15, 8), ink, 1.2)
		"submenu":
			_line(img, Vector2(8, 5), Vector2(13, 10), ink, 1.2)
			_line(img, Vector2(13, 10), Vector2(8, 15), ink, 1.2)
		"tick":
			img = Image.create(2, 8, false, Image.FORMAT_RGBA8)
			img.fill(Color(INK, 0.5))
	var tex := ImageTexture.create_from_image(img)
	_icons[id] = tex
	return tex


static func _plot(img: Image, p: Vector2, c: Color, r: float) -> void:
	for y in range(floori(p.y - r - 1), ceili(p.y + r + 1) + 1):
		for x in range(floori(p.x - r - 1), ceili(p.x + r + 1) + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var d := Vector2(x + 0.5, y + 0.5).distance_to(p)
			var a := clampf(r + 0.5 - d, 0.0, 1.0) * c.a
			if a <= 0.0:
				continue
			var was := img.get_pixel(x, y)
			if a > was.a:
				img.set_pixel(x, y, Color(c, a))


static func _line(img: Image, a: Vector2, b: Vector2, c: Color, r: float) -> void:
	var n := maxi(2, ceili(a.distance_to(b) * 3.0))
	for i in n + 1:
		_plot(img, a.lerp(b, float(i) / n), c, r)


static func _box(img: Image, r: Rect2, c: Color) -> void:
	_line(img, r.position + Vector2(-1, 0.3), Vector2(r.end.x + 0.5, r.position.y), c, 0.9)
	_line(img, Vector2(r.end.x, r.position.y - 0.5), r.end + Vector2(0.3, 0.8), c, 0.9)
	_line(img, r.end, Vector2(r.position.x - 0.6, r.end.y - 0.2), c, 0.9)
	_line(img, Vector2(r.position.x, r.end.y + 0.6), r.position + Vector2(0.3, -0.8), c, 0.9)


static func _ring(img: Image, centre: Vector2, radius: float, c: Color, r: float) -> void:
	var n := 48
	for i in n + 3:
		var a := TAU * i / n
		_plot(img, centre + Vector2(cos(a), sin(a)) * radius, c, r * 0.8)


static func _disc(img: Image, centre: Vector2, radius: float, c: Color) -> void:
	_plot(img, centre, c, radius)


static func _hatch_rect(img: Image, r: Rect2, c: Color) -> void:
	for y in range(int(r.position.y), int(r.end.y)):
		for x in range(int(r.position.x), int(r.end.x)):
			if (x + y) % 3 == 0:
				img.set_pixel(x, y, c)


## A double pencil line, slightly uneven, across the control's width.
class PencilRule:
	extends Control
	var ink := Color(0.17, 0.18, 0.2, 0.8)

	func _init(height := 8.0, p_ink := Color(0.17, 0.18, 0.2, 0.8)) -> void:
		custom_minimum_size.y = height
		ink = p_ink
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(roundi(size.x))
		var mid := size.y * 0.5
		for p in 2:
			var y := mid + (p - 0.5) * minf(4.0, size.y * 0.5)
			var pts := PackedVector2Array()
			var steps := clampi(int(size.x / 60.0) + 2, 2, 40)
			var x0 := rng.randf_range(-2.0, 4.0)
			var x1 := size.x - rng.randf_range(-2.0, 10.0)
			for i in steps + 1:
				var t := float(i) / steps
				pts.append(Vector2(lerpf(x0, x1, t), y + sin(t * PI) * rng.randf_range(-0.8, 0.8) + rng.randf_range(-0.3, 0.3)))
			draw_polyline(pts, Color(ink, ink.a * (1.0 if p == 0 else 0.6)), 1.6 if p == 0 else 1.1, true)
