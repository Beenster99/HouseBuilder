extends Control
## The drawn cartoon face: bold ink outlines and flat colours, made only of simple shapes
## drawn in code (no image files), so every part can be recoloured. Only the features, on a clear background (the head itself is skin-coloured; beenster,
## 28 Nov: no outline, no hats, just facial features). Layers, back to front: freckles, beard,
## eyes and pupils, brows, glasses, moustache, mouth. `plate` adds a plain skin disc behind
## ## them for flat previews (settings pages, the gallery). Drawn on a SIZE x SIZE canvas, scaled
## to the control's size. FaceView renders one into a SubViewport and wraps it round the front
## of a skin-coloured head on each avatar; the settings and "Your avatar" pages show one as it
## is, for the player's own live face.

const FaceStateT := preload("res://modules/faces/api/face_state.gd")
const FaceLookT := preload("res://modules/faces/api/face_look.gd")

const SIZE := 256.0
const INK := Color("1b1b1b")
const EYE_WHITE := Color("fbfbf7")
const MOUTH_DARK := Color("3a1414")
const TONGUE := Color("d9574f")
const TEETH := Color("ffffff")
const CENTRE := Vector2(128, 128)
const RADIUS := 112.0
const LINE := 5.0

## Draw a plain skin disc behind the features (flat previews; the 3D head has its own skin).
var plate := false:
	set(v):
		plate = v
		queue_redraw()
var look: FaceLook = FaceLookT.new():
	set(v):
		look = v if v != null else FaceLookT.new()
		queue_redraw()
var state: FaceState = FaceStateT.new():
	set(v):
		state = v if v != null else FaceStateT.new()
		queue_redraw()
## 0 eyes open, 1 shut.
var blink := 0.0:
	set(v):
		blink = clampf(v, 0.0, 1.0)
		queue_redraw()
## Where the pupils point, -1..1 each way.
var gaze := Vector2.ZERO:
	set(v):
		gaze = v.clampf(-1.0, 1.0)
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var k := minf(size.x, size.y) / SIZE if size.x > 0.0 and size.y > 0.0 else 1.0
	draw_set_transform(Vector2((size.x - SIZE * k) * 0.5, (size.y - SIZE * k) * 0.5), 0.0, Vector2(k, k))
	if plate:
		draw_circle(CENTRE, RADIUS, look.skin_colour())
	if look.freckles:
		var dot := look.skin_colour().darkened(0.35)
		for side in [-1.0, 1.0]:
			for p: Vector2 in [Vector2(52, 150), Vector2(62, 160), Vector2(44, 162), Vector2(58, 140)]:
				draw_circle(Vector2(CENTRE.x + side * (CENTRE.x - p.x), p.y), 2.6, dot)
	if look.beard:
		_draw_beard()
	_draw_eyes()
	_draw_brows()
	_draw_glasses()
	_draw_mouth()
	if look.moustache:
		var c := look.hair_colour_value()
		var pts := PackedVector2Array([Vector2(100, 168), Vector2(114, 158), Vector2(128, 162),
				Vector2(142, 158), Vector2(156, 168), Vector2(142, 170), Vector2(128, 167), Vector2(114, 170)])
		draw_colored_polygon(pts, c)
		draw_polyline(_closed(pts), INK, 2.5, true)


func _draw_beard() -> void:
	var c := look.hair_colour_value()
	var pts := _arc_points(CENTRE, RADIUS, PI * 0.02, PI * 0.98, 24)
	pts.append(Vector2(60, 160))
	pts.append(Vector2(100, 196))
	pts.append(Vector2(156, 196))
	pts.append(Vector2(196, 160))
	draw_colored_polygon(pts, c)
	draw_polyline(_closed(pts), INK, 3.0, true)


# --- Eyes, brows, glasses -------------------------------------------------------------

func _eye_size() -> Vector2:
	match look.eyes:
		1:
			return Vector2(27, 36)
		3:
			return Vector2(38, 38)
	return Vector2(33, 33)


func _eye_centre(side: float) -> Vector2:
	var e := _eye_size()
	return Vector2(CENTRE.x + side * (e.x - 1.0), 104)


func _draw_eyes() -> void:
	var e := _eye_size()
	var mood := state.mood
	if state.mouth == FaceStateT.MOUTH_LAUGH or mood == FaceStateT.MOOD_LAUGH:
		# Squeezed shut with laughing: arcs.
		for side in [-1.0, 1.0]:
			var c := _eye_centre(side) + Vector2(0, 8)
			draw_arc(c, e.x * 0.7, PI * 1.1, PI * 1.9, 16, INK, 6.0, true)
		return
	if mood == FaceStateT.MOOD_SURPRISED or mood == FaceStateT.MOOD_SHOUT and state.mouth == FaceStateT.MOUTH_SHOUT:
		e *= 1.12
	var lid := blink
	if look.eyes == 2:  # sleepy: the lids sit half down
		lid = maxf(lid, 0.45)
	if mood == FaceStateT.MOOD_HAPPY or mood == FaceStateT.MOOD_SMILE:
		lid = maxf(lid, 0.15)
	for side in [-1.0, 1.0]:
		var c := _eye_centre(side)
		if lid >= 0.95:
			draw_line(c + Vector2(-e.x * 0.8, 4), c + Vector2(e.x * 0.8, 4), INK, 5.0, true)
			continue
		var eye := _ellipse(c, e, 28)
		draw_colored_polygon(eye, EYE_WHITE)
		var pupil_r := 4.5 if mood == FaceStateT.MOOD_SURPRISED else 6.5
		var reach := Vector2(e.x - pupil_r - 8.0, e.y - pupil_r - 8.0)
		var p := c + Vector2(gaze.x * reach.x, gaze.y * reach.y) + Vector2(-side * 3.0, 4.0)
		if not look.sunglasses:
			draw_circle(p, pupil_r, INK)
		if lid > 0.0:
			# The upper lid: skin over the top of the eye, down to `lid` of its height.
			var cut := c.y - e.y + 2.0 * e.y * lid
			var lid_pts := PackedVector2Array()
			for q in eye:
				lid_pts.append(Vector2(q.x, minf(q.y, cut)))
			draw_colored_polygon(lid_pts, look.skin_colour())
			draw_line(Vector2(c.x - _half_width_at(e, cut - c.y), cut), Vector2(c.x + _half_width_at(e, cut - c.y), cut), INK, 3.5, true)
		draw_polyline(_closed(eye), INK, 3.5, true)


func _draw_brows() -> void:
	if look.brows == 3:
		return
	var width := 4.0 if look.brows == 0 else (9.0 if look.brows == 1 else 5.0)
	var lift := 0.0
	var inner := 0.0  # + drops the inner ends (cross), - lifts them (worried)
	match state.mood:
		FaceStateT.MOOD_SURPRISED:
			lift = 14.0
		FaceStateT.MOOD_SHOUT:
			if state.mouth == FaceStateT.MOUTH_SHOUT:
				lift = 12.0
			else:
				inner = 10.0
		FaceStateT.MOOD_ANGRY:
			inner = 12.0
		FaceStateT.MOOD_SAD:
			inner = -10.0
		FaceStateT.MOOD_HAPPY, FaceStateT.MOOD_LAUGH:
			lift = 6.0
	# Louder talk lifts the brows a little.
	lift += float(state.openness) * 0.4
	var e := _eye_size()
	var c := look.hair_colour_value()
	if c.get_luminance() > 0.6:
		c = c.darkened(0.45)
	for side in [-1.0, 1.0]:
		var ec := _eye_centre(side)
		var y := ec.y - e.y - 10.0 - lift
		var a := Vector2(CENTRE.x + side * 8.0, y + inner)
		var b := Vector2(ec.x + side * (e.x * 0.75), y - inner * 0.3)
		if look.brows == 2:
			var mid := (a + b) * 0.5 + Vector2(0, -9)
			draw_polyline(PackedVector2Array([a, mid, b]), c, width, true)
		else:
			draw_line(a, b, c, width, true)


func _draw_glasses() -> void:
	if not (look.glasses or look.sunglasses):
		return
	var e := _eye_size()
	for side in [-1.0, 1.0]:
		var c := _eye_centre(side)
		var lens := _ellipse(c, e * 0.92, 24)
		if look.sunglasses:
			draw_colored_polygon(lens, Color("1f2a33"))
			draw_line(c + Vector2(-e.x * 0.35, -e.y * 0.4), c + Vector2(-e.x * 0.1, -e.y * 0.55), Color(1, 1, 1, 0.5), 3.0, true)
		draw_polyline(_closed(lens), INK, 4.0, true)
		draw_line(c + Vector2(side * e.x * 0.92, 0), Vector2(CENTRE.x + side * (RADIUS - 4.0), c.y - 4.0), INK, 4.0, true)


# --- Mouth -----------------------------------------------------------------------------

func _draw_mouth() -> void:
	var c := Vector2(128, 182)
	var o := float(state.openness)
	match state.mouth:
		FaceStateT.MOUTH_CLOSED:
			match state.mood:
				FaceStateT.MOOD_SAD:
					draw_arc(c + Vector2(0, 18), 22.0, PI * 1.2, PI * 1.8, 12, INK, LINE, true)
				FaceStateT.MOOD_SURPRISED:
					var m := _ellipse(c, Vector2(7, 9), 16)
					draw_colored_polygon(m, MOUTH_DARK)
					draw_polyline(_closed(m), INK, 3.5, true)
				FaceStateT.MOOD_ANGRY, FaceStateT.MOOD_SHOUT:
					draw_polyline(PackedVector2Array([c + Vector2(-22, 4), c + Vector2(-8, 0), c + Vector2(8, 0), c + Vector2(22, 4)]), INK, LINE, true)
				FaceStateT.MOOD_HAPPY, FaceStateT.MOOD_SMILE, FaceStateT.MOOD_LAUGH:
					draw_arc(c + Vector2(0, -16), 24.0, PI * 0.2, PI * 0.8, 12, INK, LINE, true)
				_:
					draw_line(c + Vector2(-18, 0), c + Vector2(18, 0), INK, LINE, true)
		FaceStateT.MOUTH_SMILE:
			draw_arc(c + Vector2(0, -18), 28.0, PI * 0.18, PI * 0.82, 14, INK, LINE, true)
		FaceStateT.MOUTH_SMALL:
			_open_mouth(_ellipse(c, Vector2(13, 4.0 + o * 0.9), 20), c, false)
		FaceStateT.MOUTH_WIDE:
			_open_mouth(_ellipse(c, Vector2(27, 8.0 + o * 1.5), 24), c, false)
		FaceStateT.MOUTH_ROUND:
			var r := 8.0 + o * 0.7
			_open_mouth(_ellipse(c, Vector2(r * 0.85, r), 20), c, false)
		FaceStateT.MOUTH_TEETH:
			var h := 6.0 + o * 0.7
			var pts := _rounded_rect(Rect2(c.x - 30, c.y - h, 60, h * 2.0), minf(h, 8.0))
			draw_colored_polygon(pts, MOUTH_DARK)
			draw_colored_polygon(_rounded_rect(Rect2(c.x - 28, c.y - h + 1, 56, h * 2.0 - 2.0), minf(h, 7.0)), TEETH)
			draw_line(Vector2(c.x - 28, c.y), Vector2(c.x + 28, c.y), INK, 2.0, true)
			for x in [-14.0, 0.0, 14.0]:
				draw_line(Vector2(c.x + x, c.y - h + 2), Vector2(c.x + x, c.y + h - 2), Color(0, 0, 0, 0.35), 1.5, true)
			draw_polyline(_closed(pts), INK, 3.5, true)
		FaceStateT.MOUTH_LAUGH:
			# A big D on its side: flat top of teeth, round bottom, tongue.
			var w := 46.0
			var h := 20.0 + o * 1.5
			var pts := PackedVector2Array()
			for i in 21:
				var a := PI * float(i) / 20.0
				pts.append(Vector2(c.x - cos(a) * w, c.y - 10 + sin(a) * h))
			draw_colored_polygon(pts, MOUTH_DARK)
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - w + 3, c.y - 9), Vector2(c.x + w - 3, c.y - 9),
					Vector2(c.x + w - 7, c.y - 1), Vector2(c.x - w + 7, c.y - 1)]), TEETH)
			draw_colored_polygon(_ellipse(Vector2(c.x, c.y - 10 + h * 0.75), Vector2(w * 0.45, h * 0.28), 16), TONGUE)
			draw_polyline(_closed(pts), INK, LINE, true)
		FaceStateT.MOUTH_SHOUT:
			var w := 32.0
			var h := 16.0 + o * 1.5
			var pts := PackedVector2Array([Vector2(c.x - w * 0.8, c.y - h), Vector2(c.x + w * 0.8, c.y - h),
					Vector2(c.x + w, c.y + h * 0.5), Vector2(c.x + w * 0.5, c.y + h), Vector2(c.x - w * 0.5, c.y + h),
					Vector2(c.x - w, c.y + h * 0.5)])
			draw_colored_polygon(pts, MOUTH_DARK)
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - w * 0.78, c.y - h + 1), Vector2(c.x + w * 0.78, c.y - h + 1),
					Vector2(c.x + w * 0.74, c.y - h + 7), Vector2(c.x - w * 0.74, c.y - h + 7)]), TEETH)
			draw_colored_polygon(_ellipse(Vector2(c.x, c.y + h * 0.6), Vector2(w * 0.5, h * 0.3), 16), TONGUE)
			draw_polyline(_closed(pts), INK, LINE, true)


func _open_mouth(pts: PackedVector2Array, c: Vector2, _teeth: bool) -> void:
	draw_colored_polygon(pts, MOUTH_DARK)
	var bottom := 0.0
	for p in pts:
		bottom = maxf(bottom, p.y)
	var depth := bottom - c.y
	if depth > 8.0:
		var tongue := PackedVector2Array()
		for p in pts:
			if p.y > c.y + depth * 0.35:
				tongue.append(p)
		if tongue.size() >= 3:
			draw_colored_polygon(tongue, TONGUE)
	draw_polyline(_closed(pts), INK, 3.5, true)


# --- Shapes ----------------------------------------------------------------------------

static func _ellipse(c: Vector2, r: Vector2, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return pts


static func _arc_points(c: Vector2, r: float, from: float, to: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if n <= 0:
		return pts
	for i in n + 1:
		var a := lerpf(from, to, float(i) / float(n))
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


static func _rounded_rect(r: Rect2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	radius = minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var corners := [[r.position + Vector2(r.size.x - radius, radius), -PI * 0.5],
			[r.position + Vector2(r.size.x - radius, r.size.y - radius), 0.0],
			[r.position + Vector2(radius, r.size.y - radius), PI * 0.5],
			[r.position + Vector2(radius, radius), PI]]
	for corner: Array in corners:
		var at: Vector2 = corner[0]
		var start: float = corner[1]
		for i in 5:
			var a := start + PI * 0.5 * float(i) / 4.0
			pts.append(at + Vector2(cos(a), sin(a)) * radius)
	return pts


static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	if out.size() > 0:
		out.append(out[0])
	return out


static func _half_width_at(r: Vector2, dy: float) -> float:
	var t := clampf(dy / r.y, -1.0, 1.0)
	return r.x * sqrt(1.0 - t * t)
