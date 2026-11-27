class_name RoofShape
extends RefCounted
## The faces of a pitched roof over a plan outline, for anything that draws roofs (the
## designer's views; timelapse and walk-inside can use it too). The roof covers the outline's
## box, lined up with its longest edge; the ridge runs along the longer side.
##   gable: two slopes and two upright triangular gable ends
##   hip:   four slopes (ends slope too), meeting at a ridge, or a point on a square
##   mono:  one slope rising across the short way, a tall upright side and two triangles
## Faces are [[Vector3, ...] (3 or 4 corners), outward normal], with y up from the roof's
## base (the top of the walls), plus the flat underside.
##   for f in RoofShape.faces(outline, 35.0, "gable"): draw(f[0], f[1])

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


static func faces(outline: Array, pitch: float, form: String) -> Array:
	var f := frame(outline)
	if f.is_empty():
		return []
	var l: float = f.l
	var w: float = f.w
	var o: Vector2 = f.o
	var u: Vector2 = f.u
	var v: Vector2 = f.v
	var tn := tan(deg_to_rad(clampf(pitch, 0.0, 79.0)))
	# (s along the ridge, r across, height) -> building coordinates.
	var at := func(s: float, r: float, y: float) -> Vector3:
		var p := o + u * s + v * r
		return Vector3(p.x, y, p.y)
	var out: Array = []
	match form:
		"mono":
			var h := w * tn
			out.append([at.call(0.0, 0.0, 0.0), at.call(l, 0.0, 0.0), at.call(l, w, h), at.call(0.0, w, h)])
			out.append([at.call(0.0, w, 0.0), at.call(l, w, 0.0), at.call(l, w, h), at.call(0.0, w, h)])
			out.append([at.call(0.0, 0.0, 0.0), at.call(0.0, w, 0.0), at.call(0.0, w, h)])
			out.append([at.call(l, 0.0, 0.0), at.call(l, w, 0.0), at.call(l, w, h)])
		"hip":
			var h := w * 0.5 * tn
			var e := minf(w * 0.5, l * 0.5)
			out.append([at.call(0.0, 0.0, 0.0), at.call(l, 0.0, 0.0), at.call(l - e, w * 0.5, h), at.call(e, w * 0.5, h)])
			out.append([at.call(0.0, w, 0.0), at.call(l, w, 0.0), at.call(l - e, w * 0.5, h), at.call(e, w * 0.5, h)])
			out.append([at.call(0.0, 0.0, 0.0), at.call(0.0, w, 0.0), at.call(e, w * 0.5, h)])
			out.append([at.call(l, 0.0, 0.0), at.call(l, w, 0.0), at.call(l - e, w * 0.5, h)])
		_:
			var h := w * 0.5 * tn
			out.append([at.call(0.0, 0.0, 0.0), at.call(l, 0.0, 0.0), at.call(l, w * 0.5, h), at.call(0.0, w * 0.5, h)])
			out.append([at.call(0.0, w, 0.0), at.call(l, w, 0.0), at.call(l, w * 0.5, h), at.call(0.0, w * 0.5, h)])
			out.append([at.call(0.0, 0.0, 0.0), at.call(0.0, w, 0.0), at.call(0.0, w * 0.5, h)])
			out.append([at.call(l, 0.0, 0.0), at.call(l, w, 0.0), at.call(l, w * 0.5, h)])
	out.append([at.call(0.0, 0.0, 0.0), at.call(l, 0.0, 0.0), at.call(l, w, 0.0), at.call(0.0, w, 0.0)])
	# Outward normals, from the middle of the roof.
	var mid: Vector3 = at.call(l * 0.5, w * 0.5, 0.0) + Vector3(0, 0.01, 0)
	var faces_out: Array = []
	for i in out.size():
		var p: Array = out[i]
		var n := ((p[1] as Vector3) - (p[0] as Vector3)).cross((p[2] as Vector3) - (p[0] as Vector3)).normalized()
		if i == out.size() - 1:
			n = Vector3.DOWN
		else:
			var c := Vector3.ZERO
			for q: Vector3 in p:
				c += q
			c /= p.size()
			if n.dot(c - mid) < 0.0:
				n = -n
		faces_out.append([p, n])
	return faces_out
