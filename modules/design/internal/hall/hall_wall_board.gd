extends PanelContainer
## A whole wall of the design hall as one big screen split into panels side by side (ported
## from BSX's WallBoard). Each panel shows one channel (HallChannels: the plan, side view, 3D
## view, bill of materials, cost and checks, the consultants' windows) and has a header with
## < and > to flip channels, shared with everyone in the room (HallScreens). F at a panel shows
## it full screen (DesignHall.open_fullscreen).

const T := preload("res://modules/ui/api/terminal_kit.gd")
const HallChannels := preload("res://modules/design/internal/hall/hall_channels.gd")

var hall: Node
var wall_id := ""
## Pixels per metre the wall is drawn at (sizes text so it reads from across the room).
var px_per_m := 150.0
## One entry per panel: {view (channel id), share (of the wall's width)}.
var panels: Array[Dictionary] = []
## A board of its own (the full-screen copy of one panel): its channels are not shared.
var local := false
var _row: HBoxContainer
var _slots: Array[Control] = []


## Built in the classic screen look: the boards are TV screens, not the game's own UI.
func setup(p_hall: Node, id: String, layout: Array, density: float) -> void:
	set_meta(BsxTheme.SCREEN_META, true)
	BsxTheme.as_screen(func() -> void: _setup(p_hall, id, layout, density))


func _setup(p_hall: Node, id: String, layout: Array, density: float) -> void:
	hall = p_hall
	wall_id = id
	px_per_m = density
	name = "Wall_" + id
	add_theme_stylebox_override("panel", T.box(BsxTheme.PANEL, Color(T.EDGE, 0.7), 2, 0.0))
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", int(px_per_m * 0.12))
	add_child(_row)
	var screens: Node = hall.get("screens")
	for p in layout:
		var view := str(p[0])
		var shared: Variant = null if local else screens.call("get_value", _key(panels.size()))
		if shared is String:
			view = str(shared)
		panels.append({"view": view, "share": float(p[1])})
		var slot := VBoxContainer.new()
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.size_flags_stretch_ratio = float(p[1])
		slot.add_theme_constant_override("separation", 0)
		_row.add_child(slot)
		_slots.append(slot)
		_fill(_slots.size() - 1)
	screens.connect("changed", _on_screen_changed)
	(Modules.bus("design") as DesignBus).panels_changed.connect(_on_panels_changed)
	(Modules.bus("design") as DesignBus).channels_changed.connect(_on_panels_changed)


func _exit_tree() -> void:
	var design := Modules.bus("design") as DesignBus
	if design.panels_changed.is_connected(_on_panels_changed):
		design.panels_changed.disconnect(_on_panels_changed)
		design.channels_changed.disconnect(_on_panels_changed)


## The shared key for panel `i` of this wall.
func _key(i: int) -> String:
	return "wall:%s:%d" % [wall_id, i]


func _on_screen_changed(key: String, value: Variant) -> void:
	if local or not key.begins_with("wall:%s:" % wall_id):
		return
	var i := int(key.get_slice(":", 2))
	if i < 0 or i >= panels.size() or str(panels[i].view) == str(value):
		return
	panels[i].view = str(value)
	_fill(i)


## A module offered or took back a window: panels showing one are built again.
func _on_panels_changed() -> void:
	for i in panels.size():
		if str(panels[i].view).begins_with("panel:") or str(panels[i].view).begins_with("channel:"):
			_fill(i)


func views() -> PackedStringArray:
	var out := PackedStringArray()
	for c: Dictionary in HallChannels.channels(hall):
		out.append(str(c.id))
	return out


## Flips panel `i` to the next (or previous) channel.
func step(i: int, by: int) -> void:
	var all := views()
	var at := all.find(str(panels[i].view))
	set_view(i, all[posmod(at + by, all.size())])


## Shows `view` on panel `i`, for everyone in the room.
func set_view(i: int, view: String) -> void:
	if not local:
		hall.get("screens").call("set_value", _key(i), view)
	if str(panels[i].view) != view:
		panels[i].view = view
		_fill(i)


## The control panel `i` shows now.
func content(i: int) -> Control:
	var slot := _slots[i]
	return slot.get_child(1) as Control if slot.get_child_count() > 1 else null


func _fill(i: int) -> void:
	BsxTheme.as_screen(func() -> void: _fill_now(i))


func _fill_now(i: int) -> void:
	var slot := _slots[i]
	for c in slot.get_children():
		slot.remove_child(c)
		c.queue_free()
	var view := str(panels[i].view)
	var font := int(px_per_m * 0.16)
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", T.box(Color(BsxTheme.ACCENT, 0.16), Color.TRANSPARENT, 0, px_per_m * 0.04))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", int(px_per_m * 0.08))
	head.add_child(bar)
	var prev := T.button("<", false, font)
	prev.name = "Prev"
	prev.focus_mode = Control.FOCUS_NONE
	prev.pressed.connect(step.bind(i, -1))
	bar.add_child(prev)
	var title := T.label(HallChannels.title_of(hall, view), "display_bold", font, T.TEXT)
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(title)
	var next := T.button(">", false, font)
	next.name = "Next"
	next.focus_mode = Control.FOCUS_NONE
	next.pressed.connect(step.bind(i, 1))
	bar.add_child(next)
	slot.add_child(head)
	var body := HallChannels.make(view, hall, int(font * 0.85))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.add_child(body)


## The panel under a point on the board (its pixels), or -1.
func panel_at(px: Vector2) -> int:
	for i in _slots.size():
		if _slots[i].get_global_rect().has_point(px):
			return i
	return -1
