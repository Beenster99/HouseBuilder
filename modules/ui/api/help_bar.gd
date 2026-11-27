class_name HelpBar
extends CanvasLayer
## The help line along the bottom of every screen, always in the same place. Left: what this
## screen or mode is and what the keys and mouse do here. Right: the tip for what the
## pointer is over (a control's tooltip, or what a caller says is under it in the 3D world),
## or a passing message.
##
##   var help := HelpBar.new()
##   add_child(help)
##   help.set_help("TIMELAPSE", HelpBar.keys_text([["Space", "play / pause"], ["Esc", "back"]]))
##   help.set_help("SELECT MODE", "drag to move", Color.GREEN)  # head in its own colour
##   help.hover("Kitchen · room · 12.4 m²")   # each frame something in the world is pointed at
##   help.say("Saved", false)                  # a message for a few seconds (red when warn)
##   help.set_insets(320, 280)                 # span between side docks
##
## Text is bbcode. The bar ignores the mouse, so it never blocks a click. It works inside a
## SubViewport (it reads its own viewport's hovered control) and follows the menu style.

const NODE_NAME := "HelpBar"
const LAYER := 50
const MARGIN := 10.0
const FONT_SIZE := 15
const SAY_TIME := 5.0

var head := ""
var text := ""
var head_colour := Color(0, 0, 0, 0)
var inset_left := 24.0
var inset_right := 24.0

var _panel: PanelContainer
var _left: RichTextLabel
var _right: RichTextLabel
var _control_tip := ""
var _world_tip := ""
var _world_frame := -1
var _said := ""
var _said_warn := false
var _said_until := 0.0
var _pencil := false
var _shown_right := "-"


func _init() -> void:
	name = NODE_NAME
	layer = LAYER


func _ready() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Bar"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 24)
	_panel.add_child(row)
	_left = _rich("Help")
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left.size_flags_stretch_ratio = 1.6
	row.add_child(_left)
	_right = _rich("Tip")
	_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_right)
	get_viewport().size_changed.connect(_place)
	restyle()


## What the screen or mode is (`head`, in `colour` or the accent) and what to do here.
func set_help(new_head: String, how: String, colour := Color(0, 0, 0, 0)) -> void:
	if new_head == head and how == text and colour == head_colour:
		return
	head = new_head
	text = how
	head_colour = colour
	_refresh_left()


## What is under the pointer in the world (not a Control). Call it every frame while it
## applies; it lapses the first frame it isn't called.
func hover(tip: String) -> void:
	_world_tip = tip
	_world_frame = Engine.get_process_frames()


## A passing message on the tip side for a few seconds; red when `warn`.
func say(message: String, warn := false) -> void:
	_said = message
	_said_warn = warn
	_said_until = Time.get_ticks_msec() / 1000.0 + SAY_TIME
	_refresh_right()


## Space kept clear at the sides (docks), in pixels.
func set_insets(left: float, right: float) -> void:
	inset_left = left
	inset_right = right
	_place()


## Keys in the accent colour then what they do: "Space play / pause  ·  Esc back".
static func keys_text(pairs: Array) -> String:
	var out: PackedStringArray = []
	for p: Array in pairs:
		out.append("[color=#%s][b]%s[/b][/color] %s" % [BsxTheme.ACCENT.to_html(false), p[0], p[1]])
	return "  ·  ".join(out)


## The bar's text now, as bbcode: [help side, tip side].
func shown() -> PackedStringArray:
	return [_left.text if _left else "", _right.text if _right else ""]


## Re-reads the menu style (pencil or Classic). Done by itself when the style changes.
func restyle() -> void:
	if _panel == null:
		return
	_pencil = BsxTheme.pencil()
	var sb := BsxTheme.card_style(MARGIN, 0.94)
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	_panel.add_theme_stylebox_override("panel", sb)
	for l: RichTextLabel in [_left, _right]:
		l.add_theme_font_override("normal_font", BsxTheme.font("mono"))
		l.add_theme_font_override("bold_font", BsxTheme.font("mono_medium"))
		l.add_theme_font_size_override("normal_font_size", FONT_SIZE)
		l.add_theme_font_size_override("bold_font_size", FONT_SIZE)
	_refresh_left()
	_shown_right = "-"
	_refresh_right()


func _process(_delta: float) -> void:
	if BsxTheme.pencil() != _pencil:
		restyle()
	_control_tip = _hovered_tooltip()
	if _world_frame < Engine.get_process_frames() - 1:
		_world_tip = ""
	_refresh_right()


## The tooltip of what the pointer is over: a Tree item's or a tab's own, else the first
## control up the parents that has one.
func _hovered_tooltip() -> String:
	var c := get_viewport().gui_get_hovered_control()
	if c == null:
		return ""
	var at := c.get_local_mouse_position()
	if c is Tree:
		var item := (c as Tree).get_item_at_position(at)
		if item:
			var t := item.get_tooltip_text(maxi((c as Tree).get_column_at_position(at), 0))
			if t != "":
				return t
	elif c is TabBar:
		var tab := (c as TabBar).get_tab_idx_at_point(at)
		if tab >= 0 and (c as TabBar).get_tab_tooltip(tab) != "":
			return (c as TabBar).get_tab_tooltip(tab)
	while c != null:
		if c.tooltip_text != "":
			return c.tooltip_text
		c = c.get_parent_control()
	return ""


func _refresh_left() -> void:
	if _left == null:
		return
	var colour := head_colour if head_colour.a > 0.0 else BsxTheme.ACCENT
	var line := ""
	if head != "":
		line = "[color=#%s][b]%s[/b][/color]   " % [colour.to_html(false), head]
	_left.text = line + "[color=#%s]%s[/color]" % [BsxTheme.TEXT.to_html(false), text]
	_place.call_deferred()


func _refresh_right() -> void:
	if _right == null:
		return
	var tip := ""
	var colour := BsxTheme.MUTED
	if _said != "" and Time.get_ticks_msec() / 1000.0 < _said_until:
		tip = _said
		colour = BsxTheme.WARN if _said_warn else BsxTheme.STATUS
	elif _control_tip != "":
		tip = _control_tip
		colour = BsxTheme.TEXT
	elif _world_tip != "":
		tip = _world_tip
		colour = BsxTheme.TEXT
	var line := "[color=#%s]%s[/color]" % [colour.to_html(false), tip] if tip != "" else ""
	if line == _shown_right:
		return
	_shown_right = line
	_right.text = line
	_right.visible = tip != ""
	_place.call_deferred()


func _place() -> void:
	if _panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var w := maxf(vp.x - inset_left - inset_right, 200.0)
	_panel.custom_minimum_size.x = w
	_panel.size = Vector2(w, 0)
	_panel.reset_size()
	_panel.position = Vector2(inset_left, vp.y - _panel.size.y - MARGIN)


func _rich(node_name: String) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.name = node_name
	l.bbcode_enabled = true
	l.fit_content = false  # a fixed one-line height; long text is clipped, not widening the bar
	l.custom_minimum_size = Vector2(0, FONT_SIZE + 8)
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_OFF  # one line, always the same height
	l.clip_contents = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
