class_name RoofShape
extends RefCounted
## The faces of pitched roofs over plan outlines, for anything that draws roofs (the designer's
## views, timelapse, walk-inside). Each roof is split into wings: a rectangle stays whole, an
## L, T, U or cross-shaped outline becomes one rectangle per wing. A wing's ridge runs along its
## longer side, or, where it joins another wing, on into that wing as far as its ridge, so the
## two meet in valleys the way real roofs do. Wings that overlap (from one outline, or from
## separate roofs drawn across each other on a level) are joined as one solid: only the parts
## of each that are not inside another are kept.
##   gable: two slopes and two upright triangular gable ends
##   hip:   four slopes (ends slope too), meeting at a ridge, or a point on a square
##   mono:  one slope rising across the short way, a tall upright side and two triangles
## Faces are [[Vector3, ...] (3 or 4 corners), outward normal], with y up from the roof's
## base (the top of the walls), plus the flat ceiling.
##   for f in RoofShape.faces(outline, 35.0, "gable"): draw(f[0], f[1])          # on its own
##   for f in RoofShape.part_faces(model, id, RoofShape.EAVE): draw(f[0], f[1])  # joined up

const FORMS := ["gable", "hip", "mono"]
## Catalog kind -> form.
const KIND_FORM := {"roof_pitched": "gable", "roof_gable": "gable", "roof_hip": "hip", "roof_mono": "mono"}


## The form a roof kind is drawn in ("" for a flat roof).
static func form_of(kind: String) -> String:
	return str(KIND_FORM.get(kind, ""))


## How high the ridge (or the high side) stands above the base, m.
static func rise(outline: Array, pitch: float, form: String) -> float:
	var f := frame(outline)
	if f.is_empty():
		return 0.0
	var w: float = f.w
	return tan(deg_to_rad(pitch)) * (w if form == "mono" else w * 0.5)


## The outline's box in its own lining: {o (corner, plan), u (along the ridge), v (across),
## l (length along u), w (width along v)} or {}.
static func frame(outline: Array) -> Dictionary:
	if outline.size() < 3:
		return {}
	var pts: Array[Vector2] = []
	for c: Array in outline:
		pts.append(Vector2(float(c[0]), float(c[1])))
	var u := Vector2.RIGHT
	var best := -1.0
	for i in pts.size():
		var e := pts[(i + 1) % pts.size()] - pts[i]
		if e.length() > best + 0.001:
			best = e.length()
			u = e.normalized()
	var v := Vector2(-u.y, u.x)
	var s0 := INF
	var s1 := -INF
	var r0 := INF
	var r1 := -INF
	for p in pts:
		s0 = minf(s0, p.dot(u))
		s1 = maxf(s1, p.dot(u))
		r0 = minf(r0, p.dot(v))
		r1 = maxf(r1, p.dot(v))
	if r1 - r0 > s1 - s0:
		# The ridge goes along the longer side.
		var t := u
		u = v
		v = -t
		var a := Vector2(s0, s1)
		s0 = r0
		s1 = r1
		r0 = -a.y
		r1 = -a.x
	if s1 - s0 < 0.01 or r1 - r0 < 0.01:
		return {}
	return {"o": u * s0 + v * r0, "u": u, "v": v, "l": s1 - s0, "w": r1 - r0}


## How far a pitched roof's slopes run out past the walls (eaves and verges), m: pass it to
## faces() for a roof that overhangs (the default 0 stops at the walls).
const EAVE := 0.35
## Faces closer than this to another wing's surface count as on it, m.
const EPS := 0.002


## One roof on its own (its outline split into wings, joined). The slopes run out past the
## outline by `eave` on every side (continuing down at the pitch, so the eaves sit a little
## below the wall tops); gable ends and the mono-pitch's tall side stand over the walls; the
## flat ceiling closes the roof at the base, and the slopes' undersides show under the overhang.
static func faces(outline: Array, pitch: float, form: String, eave: float = 0.0) -> Array:
	var roofs: Array = []
	for w: Dictionary in wings(outline, form):
		roofs.append({"wing": w, "pitch": pitch, "form": form, "dy": 0.0})
	_join(roofs)
	return _faces_of(roofs, range(roofs.size()), eave)


## Roof part `id`'s faces, joined with every other pitched roof on its level (y up from its
## own base). Redraw all of roof_parts() on the level when one of them changes.
static func part_faces(model: BuildingModel, id: String, eave: float = EAVE) -> Array:
	var e: Dictionary = model.parts.get(id, {})
	if form_of(str(e.get("kind", ""))) == "" or not e.has("outline"):
		return []
	var y0 := float(e.get("y", 0.0))
	var roofs: Array = []
	var mine: Array = []
	for pid: String in roof_parts(model, model.level_of(id)):
		var p: Dictionary = model.parts[pid]
		var pf := form_of(str(p.kind))
		var pitch := float(p.get("pitch", model.catalog.kind(str(p.kind)).get("pitch", 35.0)))
		for w: Dictionary in wings(p.outline, pf):
			if pid == id:
				mine.append(roofs.size())
			roofs.append({"wing": w, "pitch": pitch, "form": pf, "dy": float(p.get("y", 0.0)) - y0})
	_join(roofs)
	return _faces_of(roofs, mine, eave)


## The pitched roof parts on a level, in a fixed order. Each one's faces depend on all of them.
static func roof_parts(model: BuildingModel, level: int) -> PackedStringArray:
	var out := PackedStringArray()
	for pid: String in model.parts_on(level):
		var p: Dictionary = model.parts.get(pid, {})
		if p.has("outline") and form_of(str(p.get("kind", ""))) != "":
			out.append(pid)
	out.sort()
	return out


## An outline split into wing rectangles: {c (centre), x (axis), hx, hy (half sizes along x
## and across), joined (sides +x, -x, +y, -y that run on into another wing), ridge}. A
## rectangle, a mono-pitch or an outline with slanted edges is one wing over its box.
static func wings(outline: Array, form: String) -> Array:
	var f := frame(outline)
	if f.is_empty():
		return []
	var u: Vector2 = f.u
	var v: Vector2 = f.v
	var pts: Array[Vector2] = []
	for c: Array in outline:
		var p := Vector2(float(c[0]), float(c[1]))
		pts.append(Vector2(p.dot(u), p.dot(v)))
	var rects: Array = []
	if form != "mono" and _rectilinear(pts):
		var a := _slices(pts, false)
		var b := _slices(pts, true)
		rects = a if _better(a, b) else b
	if rects.is_empty():
		var box := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			box = box.expand(p)
		rects = [box]
	var out: Array = []
	for r: Rect2 in rects:
		var c := r.get_center()
		out.append({"c": u * c.x + v * c.y, "x": u, "hx": r.size.x * 0.5, "hy": r.size.y * 0.5,
				"joined": [false, false, false, false], "ridge": Vector2.ZERO})
	return out


static func _rectilinear(pts: Array[Vector2]) -> bool:
	for i in pts.size():
		var d := pts[(i + 1) % pts.size()] - pts[i]
		if absf(d.x) > 0.01 and absf(d.y) > 0.01:
			return false
	return true


## The outline cut into strips across its first coordinate (its second if `turned`), strips
## with the same spans merged: Rect2s in (s, r).
static func _slices(pts: Array[Vector2], turned: bool) -> Array:
	var q: Array[Vector2] = []
	for p in pts:
		q.append(Vector2(p.y, p.x) if turned else p)
	var cuts: Array[float] = []
	for p in q:
		if not cuts.any(func(x: float) -> bool: return absf(x - p.x) < 0.01):
			cuts.append(p.x)
	cuts.sort()
	var rects: Array = []
	var open: Dictionary = {}
	for i in cuts.size() - 1:
		var a0 := cuts[i]
		var a1 := cuts[i + 1]
		var am := (a0 + a1) * 0.5
		var hits: Array[float] = []
		for k in q.size():
			var p0 := q[k]
			var p1 := q[(k + 1) % q.size()]
			if absf(p0.y - p1.y) < 0.01 and minf(p0.x, p1.x) < am and maxf(p0.x, p1.x) > am:
				hits.append(p0.y)
		hits.sort()
		var now: Dictionary = {}
		for j in range(0, hits.size() - 1, 2):
			var key := "%.3f|%.3f" % [hits[j], hits[j + 1]]
			var r: Array = open.get(key, [])
			if r.is_empty():
				r = [a0, a1, hits[j], hits[j + 1]]
				rects.append(r)
			r[1] = a1
			now[key] = r
		open = now
	var out: Array = []
	for r: Array in rects:
		var box := Rect2(float(r[0]), float(r[2]), float(r[1]) - float(r[0]), float(r[3]) - float(r[2]))
		if turned:
			box = Rect2(box.position.y, box.position.x, box.size.y, box.size.x)
		out.append(box)
	return out


## Fewer wings, or as many with longer short ones.
static func _better(a: Array, b: Array) -> bool:
	if b.is_empty():
		return true
	if a.size() != b.size():
		return a.size() < b.size()
	var score := func(rs: Array) -> float:
		var m := INF
		for r: Rect2 in rs:
			m = minf(m, maxf(r.size.x, r.size.y))
		return m
	return float(score.call(a)) >= float(score.call(b))


## Where a wing's whole side lies on another wing (an L's or T's join), it runs on into that
## wing as far as its middle, with its ridge running that way, so the two meet in valleys.
static func _join(roofs: Array) -> void:
	var grow: Array = []
	for i in roofs.size():
		grow.append([0.0, 0.0, 0.0, 0.0])
		var r: Dictionary = roofs[i]
		if r.form == "mono":
			continue
		var w: Dictionary = r.wing
		for k in 4:
			var side := _side(w, k)
			var n: Vector2 = side[0]
			var mid: Vector2 = side[1]
			var t: Vector2 = side[2]
			var half: float = side[3]
			for j in roofs.size():
				var o: Dictionary = roofs[j]
				if j == i or o.form == "mono" or absf(float(o.dy) - float(r.dy)) > 0.01:
					continue
				var ow: Dictionary = o.wing
				var al := absf(n.dot(ow.x))
				if al > 0.001 and al < 0.999:
					continue
				if not (_inside(ow, mid + t * half) and _inside(ow, mid - t * half)) or n.dot((ow.c as Vector2) - mid) < 0.01:
					continue
				var depth := 0.0
				for c: Vector2 in _corners(ow):
					depth = maxf(depth, n.dot(c - mid))
				if depth > 0.01:
					grow[i][k] = maxf(float(grow[i][k]), depth * 0.5)
	for i in roofs.size():
		var w: Dictionary = roofs[i].wing
		var x: Vector2 = w.x
		var y := Vector2(-x.y, x.x)
		var g: Array = grow[i]
		for k in 4:
			var t: float = g[k]
			if t <= 0.0:
				continue
			w.joined[k] = true
			var n: Vector2 = [x, -x, y, -y][k]
			w.c = (w.c as Vector2) + n * t * 0.5
			if k < 2:
				w.hx = float(w.hx) + t * 0.5
			else:
				w.hy = float(w.hy) + t * 0.5
			if (w.ridge as Vector2) == Vector2.ZERO:
				w.ridge = x if k < 2 else y


## Side k of a wing (+x, -x, +y, -y): [outward normal, middle, along, half length].
static func _side(w: Dictionary, k: int) -> Array:
	var x: Vector2 = w.x
	var y := Vector2(-x.y, x.x)
	var c: Vector2 = w.c
	match k:
		0:
			return [x, c + x * float(w.hx), y, float(w.hy)]
		1:
			return [-x, c - x * float(w.hx), y, float(w.hy)]
		2:
			return [y, c + y * float(w.hy), x, float(w.hx)]
	return [-y, c - y * float(w.hy), x, float(w.hx)]


static func _inside(w: Dictionary, p: Vector2) -> bool:
	var x: Vector2 = w.x
	var d := p - (w.c as Vector2)
	return absf(d.dot(x)) <= float(w.hx) + 0.01 and absf(d.dot(Vector2(-x.y, x.x))) <= float(w.hy) + 0.01


static func _corners(w: Dictionary) -> Array[Vector2]:
	var x: Vector2 = w.x
	var y := Vector2(-x.y, x.x)
	var c: Vector2 = w.c
	var a := x * float(w.hx)
	var b := y * float(w.hy)
	return [c - a - b, c + a - b, c + a + b, c - a + b]


## A wing's lining: {o, u (along the ridge), v, l, w, open0, open1 (its ends at s = 0 and l
## run on into another wing)}.
static func _wing_frame(wg: Dictionary) -> Dictionary:
	var x: Vector2 = wg.x
	var u: Vector2 = wg.ridge
	if u == Vector2.ZERO:
		u = x if float(wg.hx) >= float(wg.hy) - 0.001 else Vector2(-x.y, x.x)
	var v := Vector2(-u.y, u.x)
	var along_x := absf(u.dot(x)) > 0.5
	var l := 2.0 * float(wg.hx if along_x else wg.hy)
	var w := 2.0 * float(wg.hy if along_x else wg.hx)
	var out := {"o": (wg.c as Vector2) - u * l * 0.5 - v * w * 0.5, "u": u, "v": v, "l": l, "w": w, "open0": false, "open1": false}
	var y := Vector2(-x.y, x.x)
	for k in 4:
		if not wg.joined[k]:
			continue
		var n: Vector2 = [x, -x, y, -y][k]
		if n.dot(u) > 0.9:
			out.open1 = true
		elif n.dot(u) < -0.9:
			out.open0 = true
	return out


## A wing's faces and the solid they bound: {faces: [[corners, normal, ceiling?]], planes:
## [[normal, d]] (inside where normal . p < d, down to the eaves), inner (the same over the
## walls only, down to the base)}.
static func _wing(fr: Dictionary, pitch: float, form: String, eave: float, dy: float) -> Dictionary:
	var l: float = fr.l
	var w: float = fr.w
	var o: Vector2 = fr.o
	var u: Vector2 = fr.u
	var v: Vector2 = fr.v
	var e := maxf(eave, 0.0)
	var tn := tan(deg_to_rad(clampf(pitch, 0.0, 79.0)))
	var dn := -e * tn  # the eaves' height
	var at := func(s: float, r: float, y: float) -> Vector3:
		var p := o + u * s + v * r
		return Vector3(p.x, y + dy, p.y)
	var slopes: Array = []
	var walls: Array = []
	match form:
		"mono":
			var h := w * tn
			slopes.append([at.call(-e, -e, dn), at.call(l + e, -e, dn), at.call(l + e, w + e, h - dn), at.call(-e, w + e, h - dn)])
			walls.append([at.call(0.0, w, 0.0), at.call(l, w, 0.0), at.call(l, w, h), at.call(0.0, w, h)])
			walls.append([at.call(0.0, 0.0, 0.0), at.call(0.0, w, 0.0), at.call(0.0, w, h)])
			walls.append([at.call(l, 0.0, 0.0), at.call(l, w, 0.0), at.call(l, w, h)])
		"hip":
			var h := w * 0.5 * tn
			var lo := -e
			var hl := l + e
			var hw := w + e
			var k := minf((w + 2.0 * e) * 0.5, (l + 2.0 * e) * 0.5)
			var k0 := 0.0 if fr.open0 else k
			var k1 := 0.0 if fr.open1 else k
			var m := w * 0.5
			slopes.append([at.call(lo, lo, dn), at.call(hl, lo, dn), at.call(hl - k1, m, h), at.call(lo + k0, m, h)])
			slopes.append([at.call(lo, hw, dn), at.call(hl, hw, dn), at.call(hl - k1, m, h), at.call(lo + k0, m, h)])
			if fr.open0:
				walls.append([at.call(0.0, 0.0, 0.0), at.call(0.0, w, 0.0), at.call(0.0, m, h)])
			else:
				slopes.append([at.call(lo, lo, dn), at.call(lo, hw, dn), at.call(lo + k0, m, h)])
			if fr.open1:
				walls.append([at.call(l, 0.0, 0.0), at.call(l, w, 0.0), at.call(l, m, h)])
			else:
				slopes.append([at.call(hl, lo, dn), at.call(hl, hw, dn), at.call(hl - k1, m, h)])
		_:
			var h := w * 0.5 * tn
			var m := w * 0.5
			slopes.append([at.call(-e, -e, dn), at.call(l + e, -e, dn), at.call(l + e, m, h), at.call(-e, m, h)])
			slopes.append([at.call(-e, w + e, dn), at.call(l + e, w + e, dn), at.call(l + e, m, h), at.call(-e, m, h)])
			walls.append([at.call(0.0, 0.0, 0.0), at.call(0.0, w, 0.0), at.call(0.0, m, h)])
			walls.append([at.call(l, 0.0, 0.0), at.call(l, w, 0.0), at.call(l, m, h)])
	# Outward normals, from the middle of the roof.
	var mid: Vector3 = at.call(l * 0.5, w * 0.5, 0.0) + Vector3(0, 0.01, 0)
	var outward := func(p: Array) -> Vector3:
		var n := ((p[1] as Vector3) - (p[0] as Vector3)).cross((p[2] as Vector3) - (p[0] as Vector3)).normalized()
		var c := Vector3.ZERO
		for q: Vector3 in p:
			c += q
		c /= p.size()
		return -n if n.dot(c - mid) < 0.0 else n
	var out: Array = []
	var planes: Array = []
	for p: Array in slopes:
		var n: Vector3 = outward.call(p)
		out.append([p, n, false])
		planes.append([n, n.dot(p[0])])
	for p: Array in walls:
		out.append([p, outward.call(p), false])
	if e > 0.0:
		for p: Array in slopes:
			out.append([p, -(outward.call(p) as Vector3), false])
	out.append([[at.call(0.0, 0.0, 0.0), at.call(l, 0.0, 0.0), at.call(l, w, 0.0), at.call(0.0, w, 0.0)], Vector3.DOWN, true])
	# The sides of its box, out to the eaves and verges.
	# (and, for cutting other ceilings, of the box over the walls: its ceiling's own edges)
	var inner := planes.duplicate()
	var lo3: Vector3 = at.call(-e, -e, 0.0)
	var hi3: Vector3 = at.call(l + e, w + e, 0.0)
	var lo0: Vector3 = at.call(0.0, 0.0, 0.0)
	var hi0: Vector3 = at.call(l, w, 0.0)
	for n2: Vector2 in [u, -u, v, -v]:
		var n3 := Vector3(n2.x, 0.0, n2.y)
		planes.append([n3, maxf(n3.dot(lo3), n3.dot(hi3))])
		inner.append([n3, maxf(n3.dot(lo0), n3.dot(hi0))])
	planes.append([Vector3.DOWN, -(dy + dn)])
	inner.append([Vector3.DOWN, -dy])
	return {"faces": out, "planes": planes, "inner": inner}


## The faces of wings `mine`, each cut back where it lies inside another wing. Where two
## wings' faces lie in one plane, the earlier wing keeps its face.
static func _faces_of(roofs: Array, mine: Array, eave: float) -> Array:
	var geo: Array = []
	for r: Dictionary in roofs:
		var fr := _wing_frame(r.wing)
		geo.append(_wing(fr, float(r.pitch), str(r.form), eave, float(r.dy)))
	var out: Array = []
	for i: int in mine:
		for f: Array in geo[i].faces:
			var pieces: Array = [f[0]]
			for j in geo.size():
				if j == i or pieces.is_empty():
					continue
				var g: Dictionary = geo[j]
				# Ceilings meet ceilings over the walls; the rest meet the whole roof.
				var planes: Array = g.inner if f[2] else g.planes
				var bias := EPS if j < i else -EPS
				var kept: Array = []
				for p: Array in pieces:
					kept.append_array(_outside(p, planes, bias))
				pieces = kept
			for p: Array in pieces:
				if p.size() <= 4:
					out.append([p, f[1]])
				else:
					for k in range(1, p.size() - 1):
						out.append([[p[0], p[k], p[k + 1]], f[1]])
	return out


## The pieces of convex polygon `poly` outside the solid bounded by `planes`.
static func _outside(poly: Array, planes: Array, bias: float) -> Array:
	var out: Array = []
	var rest := poly
	for pl: Array in planes:
		var front := _clip(rest, pl[0], pl[1], bias, true)
		if _area(front) > 1e-5:
			out.append(front)
		rest = _clip(rest, pl[0], pl[1], bias, false)
		if _area(rest) <= 1e-5:
			return out
	return out


static func _clip(poly: Array, n: Vector3, d: float, bias: float, front: bool) -> Array:
	var out: Array = []
	var sz := poly.size()
	for i in sz:
		var a: Vector3 = poly[i]
		var b: Vector3 = poly[(i + 1) % sz]
		var fa := n.dot(a) - d - bias
		var fb := n.dot(b) - d - bias
		if not front:
			fa = -fa
			fb = -fb
		if fa >= 0.0:
			out.append(a)
		if (fa >= 0.0) != (fb >= 0.0):
			out.append(a.lerp(b, fa / (fa - fb)))
	return out


static func _area(poly: Array) -> float:
	if poly.size() < 3:
		return 0.0
	var a := Vector3.ZERO
	for i in range(1, poly.size() - 1):
		a += ((poly[i] as Vector3) - (poly[0] as Vector3)).cross((poly[i + 1] as Vector3) - (poly[0] as Vector3))
	return a.length() * 0.5
