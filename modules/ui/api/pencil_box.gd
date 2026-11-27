class_name PencilBox
extends StyleBox
## A box drawn in pencil on paper: a paper fill, a graphite outline gone over twice with a
## little wobble and the strokes running past the corners, and optional 45 degree hatching
## (shading) or a smudge along the bottom and right (a drawn shadow). The wobble is seeded
## from the box's size, so a box keeps its lines while it stays the same size.
##   panel.add_theme_stylebox_override("panel", PencilBox.make(BsxTheme.PAPER, BsxTheme.INK))

## The paper. Transparent leaves the scene showing through.
@export var fill := Color(0.953, 0.937, 0.894)
## The graphite. Transparent draws no outline.
@export var ink := Color(0.18, 0.19, 0.21, 0.85)
@export var width := 1.6
## How many times the outline is gone over (1 or 2 reads best).
@export var passes := 2
## How far a stroke strays from the true edge, in pixels.
@export var wobble := 1.1
## How far strokes run past the corners, in pixels.
@export var overshoot := 4.0
## Hatching: 45 degree shading lines inside the box. Alpha 0 = none.
@export var hatch := Color(0.18, 0.19, 0.21, 0.0)
@export var hatch_gap := 7.0
## A soft pencil shadow along the bottom and right edges, this many pixels wide (0 = none).
@export var shade := 0.0
## Draw only these sides (left, top, right, bottom).
@export var sides := Vector4i(1, 1, 1, 1)
## Mixed into the wobble seed so neighbouring boxes of one size differ.
@export var seed_offset := 0


## A pencil box with all content margins set to `margin`.
static func make(p_fill: Color, p_ink: Color, margin := 10.0, p_width := 1.6) -> PencilBox:
	var b := PencilBox.new()
	b.fill = p_fill
	b.ink = p_ink
	b.width = p_width
	b.set_content_margin_all(margin)
	return b


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var rs := RenderingServer
	if fill.a > 0.0:
		rs.canvas_item_add_rect(to_canvas_item, rect, fill)
	if hatch.a > 0.0:
		_hatch(to_canvas_item, rect.grow(-2.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(roundi(rect.size.x), roundi(rect.size.y), seed_offset))
	if shade > 0.0:
		var s := Color(ink, ink.a * 0.18)
		var r := rect.position + rect.size
		rs.canvas_item_add_rect(to_canvas_item, Rect2(Vector2(rect.position.x + shade, r.y), Vector2(rect.size.x, shade)), s)
		rs.canvas_item_add_rect(to_canvas_item, Rect2(Vector2(r.x, rect.position.y + shade), Vector2(shade, rect.size.y - shade)), s)
	if ink.a <= 0.0 or width <= 0.0:
		return
	var a := rect.position
	var b := Vector2(rect.end.x, rect.position.y)
	var c := rect.end
	var d := Vector2(rect.position.x, rect.end.y)
	var edges := [[d, a, sides.x], [a, b, sides.y], [b, c, sides.z], [c, d, sides.w]]
	for p in maxi(1, passes):
		var col := Color(ink, ink.a * (1.0 if p == 0 else 0.55))
		var w := width if p == 0 else maxf(1.0, width * 0.7)
		for e: Array in edges:
			if int(e[2]) != 0:
				_stroke(to_canvas_item, e[0], e[1], col, w, rng)


## One pencil stroke from `from` to `to`: overshoots both ends a little and bows gently.
func _stroke(item: RID, from: Vector2, to: Vector2, col: Color, w: float, rng: RandomNumberGenerator) -> void:
	var along := to - from
	var length := along.length()
	if length < 1.0:
		return
	var dir := along / length
	var normal := Vector2(-dir.y, dir.x)
	var over := minf(overshoot, length * 0.15)
	var start := from - dir * over * rng.randf_range(0.2, 1.0) + normal * rng.randf_range(-wobble, wobble)
	var end := to + dir * over * rng.randf_range(0.2, 1.0) + normal * rng.randf_range(-wobble, wobble)
	var bow := rng.randf_range(-wobble, wobble) * clampf(length / 120.0, 0.4, 1.6)
	var steps := clampi(int(length / 40.0) + 2, 2, 12)
	var pts := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / steps
		var bend := sin(t * PI) * bow + rng.randf_range(-0.25, 0.25) * wobble
		pts.append(start.lerp(end, t) + normal * bend)
	RenderingServer.canvas_item_add_polyline(item, pts, PackedColorArray([col]), w, true)


## Diagonal shading lines clipped to `r`.
func _hatch(item: RID, r: Rect2) -> void:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var gap := maxf(3.0, hatch_gap)
	# Lines x - y = k, from the bottom-left corner's k to the top-right's.
	var k := r.position.x - r.end.y
	var k_end := r.end.x - r.position.y
	k += fposmod(-k, gap)
	while k <= k_end:
		# Clip the line x = y + k to the rectangle.
		var y0 := maxf(r.position.y, r.position.x - k)
		var y1 := minf(r.end.y, r.end.x - k)
		if y1 > y0:
			RenderingServer.canvas_item_add_line(item, Vector2(y1 + k, y1), Vector2(y0 + k, y0), hatch, 1.0, true)
		k += gap
