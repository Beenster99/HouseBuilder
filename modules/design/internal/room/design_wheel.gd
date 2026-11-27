extends Control
## The design room's mark-up wheel: hold the middle mouse button still and it opens round the
## pointer; move toward a slice and let go to use it. Let go in the middle to do nothing.
## Slices, clockwise from the top (ITEMS): Note, Ping, Measure, Notes on/off.

const ITEMS: Array[Dictionary] = [
	{"id": "note", "label": "Note"},
	{"id": "ping", "label": "Ping"},
	{"id": "measure", "label": "Measure"},
	{"id": "notes_layer", "label": "Notes on/off"},
]
const RADIUS := 110.0
const DEAD := 22.0
const SLICE := Color(0.02, 0.04, 0.07, 0.88)
const LIT := Color(0.62, 0.9, 1.0, 0.9)

var is_open := false
var centre := Vector2.ZERO
var _aim := Vector2.ZERO


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	visible = false


func open(at: Vector2) -> void:
	centre = at
	_aim = Vector2.ZERO
	is_open = true
	visible = true
	queue_redraw()


## Points the wheel: an offset from its centre, px.
func aim(offset: Vector2) -> void:
	_aim = offset
	queue_redraw()


## The slice the wheel points at, or "" in the middle.
func selected() -> String:
	if _aim.length() < DEAD:
		return ""
	# Angle clockwise from straight up, in slices.
	var ang := fposmod(atan2(_aim.x, -_aim.y), TAU)
	var n := ITEMS.size()
	return str(ITEMS[int(round(ang / (TAU / n))) % n].id)


## Closes the wheel and gives the chosen slice ("" for none).
func close() -> String:
	var pick := selected()
	is_open = false
	visible = false
	return pick


func _draw() -> void:
	if not is_open:
		return
	var n := ITEMS.size()
	var pick := selected()
	var font := BsxTheme.font("body_medium")
	for i in n:
		var mid := TAU / n * i
		var a0 := mid - TAU / n / 2.0
		var pts := PackedVector2Array([centre])
		for k in 17:
			var a := a0 + TAU / n * k / 16.0
			pts.append(centre + Vector2(sin(a), -cos(a)) * RADIUS)
		var lit := str(ITEMS[i].id) == pick
		draw_colored_polygon(pts, LIT if lit else Color(BsxTheme.PANEL, 0.92))
		var label := str(ITEMS[i].label)
		var at := centre + Vector2(sin(mid), -cos(mid)) * RADIUS * 0.62
		var size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 17)
		draw_string(font, at - Vector2(size.x / 2.0, -6), label, HORIZONTAL_ALIGNMENT_CENTER, -1, 17,
				Color(0.05, 0.05, 0.08) if lit else BsxTheme.TEXT)
	draw_circle(centre, DEAD, Color(BsxTheme.PANEL, 0.97))
	draw_arc(centre, DEAD, 0, TAU, 32, Color(BsxTheme.TEXT, 0.5), 1.5)
	draw_arc(centre, RADIUS, 0, TAU, 48, LIT, 2.0)
