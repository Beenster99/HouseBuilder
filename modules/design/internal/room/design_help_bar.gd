class_name DesignHelpBar
extends PanelContainer
## (Stands in until the shared ui HelpBar lands; the hall and designer then move to it.)
## The help bar along the bottom of a screen, in the same place on every screen and mode, so
## help is always where the eye expects it:
## - left, what the keys and mouse do here and now (set_keys, from keys_text pairs);
## - right, what the thing under the pointer is: the hovered control's tooltip, picked up by
##   itself, or hover(text) each frame for things in the 3D world;
## - a message (say) takes the right side for a few seconds, red when it is a warning.
##
## Self-contained (only BsxTheme), so any screen can use it: DesignHelpBar.attach(parent).

## The bar's height, px.
const HEIGHT := 30
## A message shows this long, s.
const SAY_FOR := 5.0

var _keys: RichTextLabel
var _tip: Label
var _say_age := 99.0
var _hover := ""
var _hover_frame := -10


## A bar along the bottom of `parent`, from `left` to `right` px in from its sides.
static func attach(parent: Node, left := 8.0, right := 8.0, bottom := 6.0) -> DesignHelpBar:
	var bar := DesignHelpBar.new()
	parent.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = left
	bar.offset_right = -right
	bar.offset_bottom = -bottom
	bar.offset_top = -bottom - HEIGHT
	return bar


## "[b]Key[/b] does · [b]Key[/b] does" from [[key, what], ...], keys in the accent colour.
static func keys_text(pairs: Array) -> String:
	var parts := PackedStringArray()
	var acc := BsxTheme.ACCENT.to_html(false)
	for p: Array in pairs:
		parts.append("[color=#%s][b]%s[/b][/color] %s" % [acc, str(p[0]), str(p[1])])
	return "   ".join(parts)


func _init() -> void:
	name = "HelpBar"
	mouse_filter = MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(h)
	var badge := Label.new()
	badge.text = "HELP"
	badge.add_theme_font_size_override("font_size", 11)
	badge.mouse_filter = MOUSE_FILTER_IGNORE
	badge.name = "Badge"
	h.add_child(badge)
	_keys = RichTextLabel.new()
	_keys.bbcode_enabled = true
	_keys.scroll_active = false
	_keys.autowrap_mode = TextServer.AUTOWRAP_OFF
	_keys.clip_contents = true
	_keys.size_flags_horizontal = SIZE_EXPAND_FILL
	_keys.size_flags_stretch_ratio = 1.4
	_keys.size_flags_vertical = SIZE_SHRINK_CENTER
	_keys.fit_content = true
	_keys.mouse_filter = MOUSE_FILTER_IGNORE
	_keys.add_theme_font_size_override("normal_font_size", 12)
	_keys.add_theme_font_size_override("bold_font_size", 12)
	h.add_child(_keys)
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.custom_minimum_size.x = 1
	rule.mouse_filter = MOUSE_FILTER_IGNORE
	h.add_child(rule)
	_tip = Label.new()
	_tip.clip_text = true
	_tip.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_tip.size_flags_horizontal = SIZE_EXPAND_FILL
	_tip.add_theme_font_size_override("font_size", 12)
	_tip.mouse_filter = MOUSE_FILTER_IGNORE
	h.add_child(_tip)
	restyle()


## Picks up the theme's colours again (after the menu style changes).
func restyle() -> void:
	add_theme_stylebox_override("panel", BsxTheme.card_style(6.0, 0.95))
	var badge := find_child("Badge", true, false) as Label
	if badge:
		badge.add_theme_color_override("font_color", BsxTheme.ACCENT)
	var rule := find_child("Rule", true, false) as ColorRect
	if rule:
		rule.color = Color(BsxTheme.MUTED, 0.5)
	_keys.add_theme_color_override("default_color", BsxTheme.TEXT)


## What the keys and mouse do here (bbcode; keys_text makes it from pairs).
func set_keys(bbcode: String) -> void:
	if _keys.text != bbcode:
		_keys.text = bbcode


func keys() -> String:
	return _keys.text


## What the pointer is over in the world; call each frame it is there.
func hover(text: String) -> void:
	_hover = text
	_hover_frame = Engine.get_process_frames()


## A message for a few seconds.
func say(text: String, warn := false) -> void:
	_tip.text = text
	_tip.add_theme_color_override("font_color", BsxTheme.WARN if warn else BsxTheme.LIVE)
	_say_age = 0.0


## What the right side shows now.
func tip() -> String:
	return _tip.text


func _process(delta: float) -> void:
	_say_age += delta
	if _say_age < SAY_FOR:
		return
	var text := _control_tip()
	if text == "" and Engine.get_process_frames() - _hover_frame <= 1:
		text = _hover
	_tip.text = text
	_tip.add_theme_color_override("font_color", BsxTheme.TEXT)


## The tooltip of the control under the mouse (or of the nearest parent that has one).
func _control_tip() -> String:
	var c := get_viewport().gui_get_hovered_control()
	while c != null:
		if c.tooltip_text != "":
			return c.tooltip_text.replace("\n", " · ")
		if c is TabBar:
			var tb := c as TabBar
			var i := tb.get_tab_idx_at_point(tb.get_local_mouse_position())
			if i >= 0 and tb.get_tab_tooltip(i) != "":
				return tb.get_tab_tooltip(i)
		if c is Tree:
			var t := c as Tree
			var it := t.get_item_at_position(t.get_local_mouse_position())
			if it != null and it.get_tooltip_text(0) != "":
				return "%s: %s" % [it.get_text(0), it.get_tooltip_text(0)]
		c = c.get_parent() as Control
	return ""
