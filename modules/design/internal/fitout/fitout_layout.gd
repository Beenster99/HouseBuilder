class_name DesignFitoutLayout
extends RefCounted
## Lays furniture out in one room the way a person would: beds headboard to a wall with room
## to get in at the side and the foot, wardrobes, desks and kitchen runs backed against walls
## with clear floor in front, tables free standing with room round them for the chairs,
## bedside tables by the bed heads, chairs round the table, small things on a desk or worktop.
## Nothing overlaps anything (existing furniture, columns, stairs, walls through the room),
## nothing stands in a door's swing, tall things keep off the windows, pieces spread through
## the room, and there is still a 0.5 m way from the door to every piece. Works in any room
## outline, angled walls and L shapes included, inside the walls' faces.
##
##   var lay := DesignFitoutLayout.new(model, room_id)
##   var r := lay.place_all(items)   # items: DesignFitoutWords.read(...).items
##   r -> {"ops": [place ops], "placed": int, "wanted": int, "missing": {kind: count}}

const PERSON := 0.25
const EPS := 0.004
const MAX_PIECES := 120

var model: BuildingModel
var catalog: BuildingCatalog
var room: Dictionary
var level := 0
var room_type := ""
## The room's outline at the walls' centre lines, and inside the walls' faces.
var outline := PackedVector2Array()
var inner := PackedVector2Array()
## Inside faces: [{a, b, u (along), n (into the room), len}]
var edges: Array = []
## Convex corners of the inside faces.
var corners := PackedVector2Array()
## [{c, n, w, zone}] on the room's side of each door and window.
var doors: Array = []
var windows: Array = []
## Everything standing in the room: existing pieces (fixed) and ones placed here.
## {kind, rule, c, th, body, box (Rect2), zones, layer, fixed, y}
var placed: Array = []
var centroid := Vector2.ZERO
var bounds := Rect2()
var area := 0.0

# Walking grid for the door-to-everything check.
## 0: the best scores as they are; 1+: each try shuffles near-equal choices differently,
## so a tight room gets another go when the first layout leaves something out.
var variant := 0

var _cell := 0.1
var _gw := 0
var _gh := 0
var _free := PackedByteArray()
var _block := PackedInt32Array()


func _init(m: BuildingModel, room_id: String) -> void:
	model = m
	catalog = m.catalog
	room = m.rooms.get(room_id, {})
	if room.is_empty():
		return
	level = int(room.level)
	room_type = str(room.type)
	for p: Array in room.outline:
		outline.append(Vector2(float(p[0]), float(p[1])))
	_build()


func ok() -> bool:
	return inner.size() >= 3


# --- The room ------------------------------------------------------------------------------

func _build() -> void:
	var walls: Array = []
	for pid in model.parts_on(level):
		var e: Dictionary = model.parts[pid]
		if catalog.family_of(str(e.kind)) == "wall":
			var half := float(catalog.section(str(e.get("section", ""))).get("d", 0.2)) * 0.5
			walls.append({"id": pid, "a": Vector2(float(e.a[0]), float(e.a[2])), "b": Vector2(float(e.b[0]), float(e.b[2])), "half": half})
	var ccw := _signed_area(outline) > 0.0
	var n := outline.size()
	# Each edge moved in by its wall's half thickness, then the corners where they meet.
	var lines: Array = []
	var on_edge := {}
	for i in n:
		var p := outline[i]
		var q := outline[(i + 1) % n]
		var u := (q - p).normalized()
		var nin := Vector2(-u.y, u.x) if ccw else Vector2(u.y, -u.x)
		var inset := 0.02
		for w: Dictionary in walls:
			if _collinear(w.a, w.b, p, q):
				inset = maxf(inset, float(w.half) + 0.02)
				on_edge[w.id] = true
		lines.append([p + nin * inset, u])
	var pts := PackedVector2Array()
	for i in n:
		var l0: Array = lines[(i - 1 + n) % n]
		var l1: Array = lines[i]
		var hit: Variant = Geometry2D.line_intersects_line(l0[0], l0[1], l1[0], l1[1])
		pts.append(hit if hit is Vector2 and (hit as Vector2).distance_to(outline[i]) < 3.0 else (l1[0] as Vector2))
	var good := absf(_signed_area(pts)) > absf(_signed_area(outline)) * 0.3 and (_signed_area(pts) > 0.0) == ccw
	for p in pts:
		good = good and Geometry2D.is_point_in_polygon(p, outline)
	if not good:
		var shrunk := Geometry2D.offset_polygon(outline, -0.12)
		pts = PackedVector2Array()
		for poly: PackedVector2Array in shrunk:
			if absf(_signed_area(poly)) > absf(_signed_area(pts)):
				pts = poly
		ccw = _signed_area(pts) > 0.0
	inner = pts
	if inner.size() < 3:
		return
	area = absf(_signed_area(inner))
	bounds = Rect2(inner[0], Vector2.ZERO)
	var sum := Vector2.ZERO
	for p in inner:
		bounds = bounds.expand(p)
		sum += p
	centroid = sum / inner.size()
	if not Geometry2D.is_point_in_polygon(centroid, inner):
		centroid = _poly_centre(inner)
	var m := inner.size()
	for i in m:
		var a := inner[i]
		var b := inner[(i + 1) % m]
		if a.distance_to(b) < 0.05:
			continue
		var u := (b - a).normalized()
		edges.append({"a": a, "b": b, "u": u, "n": Vector2(-u.y, u.x) if ccw else Vector2(u.y, -u.x), "len": a.distance_to(b)})
		var prev := inner[(i - 1 + m) % m]
		var turn := (a - prev).cross(b - a)
		if (turn > 0.0) == ccw:
			corners.append(a)
	_openings(walls)
	_obstacles(walls, on_edge)
	_cell = clampf(sqrt(area) / 60.0, 0.08, 0.25)
	_grid()


func _openings(walls: Array) -> void:
	for w: Dictionary in walls:
		var dir: Vector2 = (w.b - w.a).normalized()
		for oid in model.openings_in(str(w.id)):
			var o: Dictionary = model.parts[oid]
			var spec := catalog.kind(str(o.kind))
			var c: Vector2 = w.a + dir * float(o.t)
			var ow := float(o.get("w", spec.get("w", 0.9)))
			var nrm := Vector2(-dir.y, dir.x)
			var reach := float(w.half) + 0.3
			if not Geometry2D.is_point_in_polygon(c + nrm * reach, outline):
				nrm = -nrm
				if not Geometry2D.is_point_in_polygon(c + nrm * reach, outline):
					continue
			if _edge_distance(c, outline) > float(w.half) + 0.1 and not Geometry2D.is_point_in_polygon(c, outline):
				continue
			var sill := float(o.get("sill", spec.get("sill", 0.0)))
			var door := "door" in str(o.kind) or sill < 0.3
			var depth := maxf(ow, 0.8) + 0.25 if door else 0.45
			var face: Vector2 = c + nrm * float(w.half)
			var zone := _obb(face + nrm * depth * 0.5, dir, (ow + (0.3 if door else 0.1)) * 0.5, depth * 0.5)
			(doors if door else windows).append({"c": face, "n": nrm, "w": ow, "zone": zone})


func _obstacles(walls: Array, on_edge: Dictionary) -> void:
	for pid in model.parts_on(level):
		var e: Dictionary = model.parts[pid]
		var fam := catalog.family_of(str(e.kind))
		var poly := PackedVector2Array()
		var rule := {}
		if fam == "fixture":
			var r := DesignFitoutRules.rule(catalog, str(e.kind))
			if str(r.mode) in ["ceiling", "floor", "mounted", "top"]:
				continue
			rule = r
			for q: Array in model.footprint(pid):
				poly.append(Vector2(float(q[0]), float(q[1])))
		elif fam == "column" or fam == "circulation":
			var fp := model.footprint(pid)
			if fp.is_empty():
				var box := model.aabb_of(pid)
				fp = [[box.position.x, box.position.z], [box.end.x, box.position.z], [box.end.x, box.end.z], [box.position.x, box.end.z]]
			for q: Array in fp:
				poly.append(Vector2(float(q[0]), float(q[1])))
		else:
			continue
		if poly.size() >= 3 and _box_of(poly).intersects(bounds.grow(0.5)):
			_add_fixed(str(e.kind), rule, poly, e)
	for v: Dictionary in model.voids_on(level):
		var poly := PackedVector2Array()
		for q: Array in v.outline:
			poly.append(Vector2(float(q[0]), float(q[1])))
		if poly.size() >= 3:
			_add_fixed("", {}, poly, {})
	# Walls standing inside the room (not along its outline).
	for w: Dictionary in walls:
		if on_edge.has(w.id) or w.a.distance_to(w.b) < 0.05:
			continue
		var dir: Vector2 = (w.b - w.a).normalized()
		var poly := _obb((w.a + w.b) * 0.5, dir, w.a.distance_to(w.b) * 0.5 + float(w.half), float(w.half) + 0.02)
		if _box_of(poly).intersects(bounds) and (not Geometry2D.intersect_polygons(poly, inner).is_empty()):
			_add_fixed("", {}, poly, {})


func _add_fixed(kind: String, rule: Dictionary, poly: PackedVector2Array, e: Dictionary) -> void:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= poly.size()
	var th := deg_to_rad(float(e.get("rot", 0.0)))
	placed.append({"kind": kind, "rule": rule, "c": c, "th": th, "body": poly, "box": _box_of(poly), "zones": [],
		"layer": "body", "fixed": true, "y": 0.0})


# --- Placing -------------------------------------------------------------------------------

## Places every requested piece it can. items: [{kind, count, rel?, target?}].
func place_all(items: Array) -> Dictionary:
	var wanted := 0
	var pieces: Array = []
	var orders := {}
	for it: Dictionary in items:
		orders[str(it.kind)] = int(DesignFitoutRules.rule(catalog, str(it.kind)).order)
	# A table with chairs round it needs room for them as well as its own clear floor.
	var ringed := {}
	for it: Dictionary in items:
		if str(it.get("rel", "")) == "around":
			ringed[str(it.get("target", ""))] = true
	var i := 0
	for it: Dictionary in items:
		var kind := str(it.kind)
		var n := mini(int(it.get("count", 1)), MAX_PIECES)
		wanted += n
		if not catalog.has_kind(kind):
			continue
		var rule := DesignFitoutRules.rule(catalog, kind)
		if ringed.has(kind):
			rule.around = maxf(float(rule.around), 1.0)
		var order := int(rule.order)
		var target := str(it.get("target", ""))
		var rel := str(it.get("rel", ""))
		if orders.has(target) and target != kind and rel != "facing":
			order = maxi(order, int(orders[target]) + 1)
		pieces.append({"kind": kind, "count": n, "rule": rule, "rel": rel, "target": target,
			"order": order, "size": _size(kind).x * _size(kind).y, "i": i})
		i += 1
	# "A sofa facing the TV": the sofa goes first and the TV turns to face it.
	for p: Dictionary in pieces:
		if str(p.rel) != "facing":
			continue
		for q: Dictionary in pieces:
			if str(q.kind) == str(p.target) and q != p:
				q.order = maxi(int(q.order), int(p.order) + 1)
				if str(q.rel) == "":
					q.rel = "facing"
					q.target = str(p.kind)
	pieces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.order) != int(b.order):
			return int(a.order) < int(b.order)
		if not is_equal_approx(float(a.size), float(b.size)):
			return float(a.size) > float(b.size)
		return int(a.i) < int(b.i))
	var missing := {}
	var ops: Array = []
	var start := placed.size()
	if ok():
		for p: Dictionary in pieces:
			var got := 0
			if _rows_suit(p):
				got = _place_rows(p)
			for k in range(got, int(p.count)):
				if _place_one(p, k):
					got += 1
			if got < int(p.count):
				missing[p.kind] = int(p.count) - got
	else:
		for p: Dictionary in pieces:
			missing[p.kind] = int(p.count)
	for j in range(start, placed.size()):
		var e: Dictionary = placed[j]
		var at := Vector3(e.c.x, float(e.y), e.c.y)
		ops.append(BuildingCommands.place_part(str(e.kind), level, {"at": at, "rot": snappedf(fposmod(rad_to_deg(float(e.th)), 360.0), 0.01)}))
	return {"ops": ops, "placed": ops.size(), "wanted": wanted, "missing": missing}


func _place_one(p: Dictionary, k: int) -> bool:
	var rule: Dictionary = p.rule
	for relax: float in [1.0, 0.6]:
		var cands := _candidates(p, relax)
		for c: Dictionary in cands:
			c["score"] = _score(p, c, k)
		cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) < float(b.score))
		var tries := 0
		for c: Dictionary in cands:
			if not _fits(c, str(c.layer), bool(rule.tall)):
				continue
			var e := _entry(p, c)
			if not (c.zones as Array).is_empty() and not _walkable_with(e):
				tries += 1
				if tries >= 6:
					break
				continue
			_commit(e)
			return true
	return false


func _entry(p: Dictionary, c: Dictionary) -> Dictionary:
	return {"kind": p.kind, "rule": p.rule, "c": c.c, "th": c.th, "body": c.body, "box": _box_of(c.body), "zones": c.zones,
		"layer": c.layer, "fixed": false, "y": float(c.get("y", 0.0))}


func _commit(e: Dictionary) -> void:
	placed.append(e)
	if str(e.layer) == "body":
		_mark(e.body, 1)


# --- Candidates ----------------------------------------------------------------------------

func _candidates(p: Dictionary, relax: float) -> Array:
	var rule: Dictionary = p.rule
	var kind := str(p.kind)
	var mode := str(rule.mode)
	var sz := _size(kind)
	var out: Array = []
	var rel := str(p.rel)
	match mode:
		"bed":
			out = _wall_cands(sz, false, func(c: Dictionary) -> Array: return _bed_zones(c, rule, relax), "body")
		"wall":
			out = _wall_cands(sz, bool(rule.along), func(c: Dictionary) -> Array:
				return [_front_zone(c, float(rule.front) * relax)] if float(rule.front) > 0.0 else [], "body")
			if rel != "against":
				out.append_array(_free_cands(sz, 4, float(rule.front) * relax, 0.0, "body", 8.0))
		"corner":
			out = _wall_cands(sz, false, func(_c: Dictionary) -> Array: return [], "body")
		"free":
			var turns := 4 if float(rule.front) > 0.0 else 2
			out = _free_cands(sz, turns, float(rule.front) * relax, float(rule.around) * relax, "body", 0.0)
			if "coffee" in kind:
				out.append_array(_before_cands(sz, ["sofa", "armchair", "corner_sofa"], 0.45, "body"))
		"seat":
			out = _seat_cands(p, sz)
			if out.is_empty() or rel == "":
				out.append_array(_wall_cands(sz, false, func(c: Dictionary) -> Array: return [_front_zone(c, 0.5 * relax)], "body"))
				out.append_array(_free_cands(sz, 4, 0.5 * relax, 0.0, "body", 2.0))
		"bedside":
			out = _bedside_cands(sz)
			out.append_array(_wall_cands(sz, false, func(c: Dictionary) -> Array: return [_front_zone(c, 0.5 * relax)], "body"))
		"top":
			out = _top_cands(sz)
			out.append_array(_wall_cands(sz, false, func(_c: Dictionary) -> Array: return [], "body"))
		"floor":
			out = _free_cands(sz, 2, 0.0, 0.0, "floor", 0.0)
			out.append_array(_before_cands(sz, ["sofa", "armchair", "corner_sofa"], 0.15, "floor"))
		"mounted":
			out = _wall_cands(sz, false, func(_c: Dictionary) -> Array: return [], "mounted")
			for c: Dictionary in out:
				c["y"] = float(rule.get("y", 0.0))
		"ceiling":
			out = _ceiling_cands(sz)
	return out


## Backed onto each inside face, sliding along it. along: the long side to the wall.
func _wall_cands(sz: Vector2, along: bool, zones: Callable, layer: String) -> Array:
	var out: Array = []
	var aw := sz.y if along else sz.x
	var dp := sz.x if along else sz.y
	var perim := 0.0
	for e: Dictionary in edges:
		perim += float(e.len)
	var step := clampf(perim / 260.0, 0.05, 0.3)
	for ei in edges.size():
		var e: Dictionary = edges[ei]
		var length := float(e.len)
		if length < aw + 0.02:
			continue
		var u: Vector2 = e.u
		var nin: Vector2 = e.n
		var th := atan2(-nin.x, -nin.y)
		var steps := maxi(1, floori((length - aw) / step))
		for si in steps + 1:
			var s := aw * 0.5 + (length - aw) * (float(si) / float(steps) if steps > 0 else 0.5)
			var c: Vector2 = e.a + u * s + nin * (dp * 0.5 + 0.01)
			var cand := {"c": c, "th": th + (PI * 0.5 if along else 0.0), "body": _obb(c, u, aw * 0.5, dp * 0.5), "edge": ei,
				"s": s, "u": u, "n": nin, "aw": aw, "dp": dp, "layer": layer, "wall": true}
			cand["zones"] = zones.call(cand)
			out.append(cand)
	return out


## Free standing, on a grid over the room, square to its longest wall.
func _free_cands(sz: Vector2, turns: int, front: float, around: float, layer: String, penalty: float) -> Array:
	var out: Array = []
	var base := 0.0
	var longest := 0.0
	for e: Dictionary in edges:
		if float(e.len) > longest:
			longest = float(e.len)
			base = atan2(-(e.n as Vector2).x, -(e.n as Vector2).y)
	var step := clampf(sqrt(area) / 28.0, 0.1, 0.6)
	var nx := maxi(1, floori(bounds.size.x / step))
	var nz := maxi(1, floori(bounds.size.y / step))
	for t in turns:
		var th := base + PI * 0.5 * t
		for ix in nx + 1:
			for iz in nz + 1:
				var c := bounds.position + Vector2(ix * bounds.size.x / nx, iz * bounds.size.y / nz)
				if not Geometry2D.is_point_in_polygon(c, inner):
					continue
				out.append(_own_frame(c, th, sz, front, around, layer, penalty))
	return out


func _own_frame(c: Vector2, th: float, sz: Vector2, front: float, around: float, layer: String, penalty: float) -> Dictionary:
	var ax := Vector2(cos(th), -sin(th))
	var bk := Vector2(sin(th), cos(th))
	var zones: Array = []
	if front > 0.0:
		zones.append(_obb(c - bk * (sz.y * 0.5 + front * 0.5), ax, sz.x * 0.5, front * 0.5))
	if around > 0.0:
		zones.append(_obb(c + bk * (sz.y * 0.5 + around * 0.5), ax, sz.x * 0.5, around * 0.5))
		zones.append(_obb(c + ax * (sz.x * 0.5 + around * 0.5), bk, sz.y * 0.5, around * 0.5))
		zones.append(_obb(c - ax * (sz.x * 0.5 + around * 0.5), bk, sz.y * 0.5, around * 0.5))
		if front <= 0.0:
			zones.append(_obb(c - bk * (sz.y * 0.5 + around * 0.5), ax, sz.x * 0.5, around * 0.5))
	return {"c": c, "th": th, "body": _obb(c, ax, sz.x * 0.5, sz.y * 0.5), "zones": zones, "layer": layer, "penalty": penalty}


## In front of a placed sofa or armchair (a coffee table, a rug), facing it.
func _before_cands(sz: Vector2, words: Array, gap: float, layer: String) -> Array:
	var out: Array = []
	for e: Dictionary in placed:
		if not _kind_has(str(e.kind), words):
			continue
		var th := float(e.th)
		var bk := Vector2(sin(th), cos(th))
		var esz := _size(str(e.kind))
		var c: Vector2 = e.c - bk * (esz.y * 0.5 + gap + sz.y * 0.5)
		var cand := _own_frame(c, th, sz, 0.0, 0.0, layer, -2.0)
		cand["ignore"] = e
		out.append(cand)
	return out


## Round a table, at a desk, or along a wall when there is neither.
func _seat_cands(p: Dictionary, sz: Vector2) -> Array:
	var out: Array = []
	for e: Dictionary in placed:
		var k := str(e.kind)
		if k == "" or (str(p.target) != "" and k != str(p.target) and str(p.rel) == "around"):
			continue
		var table := DesignFitoutRules.is_table(catalog, k) and not "coffee" in k and not "side" in k
		var desk := "desk" in k and not "and chair" in str(catalog.kind(k).get("label", "")).to_lower() and not "bench" in k
		if not (table or desk):
			continue
		var th := float(e.th)
		var ax := Vector2(cos(th), -sin(th))
		var bk := Vector2(sin(th), cos(th))
		var esz := _size(k)
		# Sides: [outward direction, length along it, half depth to the edge]
		var sides: Array = [[-bk, ax, esz.x, esz.y * 0.5]]
		if table:
			sides.append([bk, ax, esz.x, esz.y * 0.5])
			sides.append([ax, bk, esz.y, esz.x * 0.5])
			sides.append([-ax, bk, esz.y, esz.x * 0.5])
		for sd: Array in sides:
			var out_dir: Vector2 = sd[0]
			var along: Vector2 = sd[1]
			var n := maxi(1, floori(float(sd[2]) / 0.6)) if table else 1
			for i in n:
				var off := (float(i) - (n - 1) * 0.5) * float(sd[2]) / n
				var c: Vector2 = e.c + out_dir * (float(sd[3]) + sz.y * 0.5 + 0.02) + along * off
				var cth := atan2(out_dir.x, out_dir.y)
				var cand := _own_frame(c, cth, sz, 0.0, 0.0, "body", -3.0)
				cand["zones"] = [_obb(c + out_dir * (sz.y * 0.5 + 0.2), along, sz.x * 0.5, 0.2)]
				cand["ignore"] = e
				out.append(cand)
	return out


## Beside each bed's head, backed onto the same wall.
func _bedside_cands(sz: Vector2) -> Array:
	var out: Array = []
	for e: Dictionary in placed:
		if str(e.kind) == "" or not DesignFitoutRules.is_bed(catalog, str(e.kind)):
			continue
		var th := float(e.th)
		var ax := Vector2(cos(th), -sin(th))
		var bk := Vector2(sin(th), cos(th))
		var esz := _size(str(e.kind))
		for side: float in [-1.0, 1.0]:
			var c: Vector2 = e.c + ax * side * (esz.x * 0.5 + sz.x * 0.5 + 0.03) + bk * (esz.y * 0.5 - sz.y * 0.5)
			var cand := _own_frame(c, th, sz, 0.0, 0.0, "body", -4.0)
			cand["ignore"] = e
			out.append(cand)
	return out


## On a desk, table or worktop, at its back.
func _top_cands(sz: Vector2) -> Array:
	var out: Array = []
	for e: Dictionary in placed:
		var k := str(e.kind)
		if k == "" or not DesignFitoutRules.is_surface(k):
			continue
		var th := float(e.th)
		var ax := Vector2(cos(th), -sin(th))
		var bk := Vector2(sin(th), cos(th))
		var esz := _size(k)
		var h := float(catalog.kind(k).get("h", 0.75))
		for f: float in [-0.3, 0.3, 0.0]:
			var c: Vector2 = e.c + ax * f * maxf(esz.x - sz.x, 0.0) + bk * maxf(0.0, esz.y * 0.5 - sz.y * 0.5 - 0.05)
			var cand := _own_frame(c, th, sz, 0.0, 0.0, "top", -5.0)
			cand["y"] = h
			cand["host"] = e
			out.append(cand)
	return out


func _ceiling_cands(sz: Vector2) -> Array:
	var out: Array = []
	for e: Dictionary in placed:
		if DesignFitoutRules.is_table(catalog, str(e.kind)) and not "coffee" in str(e.kind):
			out.append(_own_frame(e.c, float(e.th), sz, 0.0, 0.0, "ceiling", -3.0))
	out.append(_own_frame(centroid, 0.0, sz, 0.0, 0.0, "ceiling", 0.0))
	out.append_array(_free_cands(sz, 1, 0.0, 0.0, "ceiling", 2.0))
	return out


func _bed_zones(c: Dictionary, rule: Dictionary, relax: float) -> Array:
	var u: Vector2 = c.u
	var nin: Vector2 = c.n
	var aw := float(c.aw)
	var dp := float(c.dp)
	var side := float(rule.side) * relax
	var foot := float(rule.front) * relax
	var zones: Array = [_obb(c.c + nin * (dp * 0.5 + foot * 0.5), u, aw * 0.5, foot * 0.5)]
	var left := _obb(c.c - u * (aw * 0.5 + side * 0.5) + nin * 0.25, u, side * 0.5, (dp - 0.5) * 0.5)
	var right := _obb(c.c + u * (aw * 0.5 + side * 0.5) + nin * 0.25, u, side * 0.5, (dp - 0.5) * 0.5)
	# A double bed may lose one side in a small room on the second, tighter try.
	if bool(rule.both_sides) and relax >= 1.0:
		zones.append(left)
		zones.append(right)
	else:
		# One side free is enough for a single bed: the one that fits.
		zones.append(left if _zone_free(left) or not _zone_free(right) else right)
	return zones


func _front_zone(c: Dictionary, f: float) -> PackedVector2Array:
	var nin: Vector2 = c.n
	return _obb(c.c + nin * (float(c.dp) * 0.5 + f * 0.5), c.u, float(c.aw) * 0.5, f * 0.5)


# --- Scoring -------------------------------------------------------------------------------

func _score(p: Dictionary, c: Dictionary, k: int) -> float:
	var rule: Dictionary = p.rule
	var kind := str(p.kind)
	var pos: Vector2 = c.c
	var th := float(c.th)
	var front := -Vector2(sin(th), cos(th))
	if bool(rule.along):
		front = c.n
	var s := float(c.get("penalty", 0.0))
	if variant > 0:
		s += fposmod(sin(pos.dot(Vector2(12.9898, 78.233)) + th * 3.17 + variant * 7.71) * 43758.5453, 1.0) * 2.5
	var rel := str(p.rel)
	var target := str(p.target)
	var mode := str(rule.mode)
	# What the description asked for.
	var spot := Vector2.INF
	match target:
		"window":
			spot = _nearest(pos, windows)
		"door":
			spot = _nearest(pos, doors)
		"corner":
			spot = _nearest_point(pos, corners)
		"centre":
			spot = centroid
		"wall", "":
			pass
		_:
			var best := INF
			for e: Dictionary in placed:
				if str(e.kind) == target and e.c.distance_to(pos) < best:
					best = e.c.distance_to(pos)
					spot = e.c
	if spot != Vector2.INF:
		var d := pos.distance_to(spot)
		match rel:
			"facing":
				s += (1.0 - front.dot((spot - pos).normalized())) * 4.0 + d * 0.1
			"away":
				s -= minf(d, 6.0) * 1.0
			"foot":
				s += d * 1.5
			_:
				s += d * 1.5
	if rel == "against" and not c.has("wall"):
		s += 50.0
	if (rel == "in" and target == "centre") and c.has("wall"):
		s += 3.0
	# Spread out: keep clear of what is already there; runs (kitchen units, lockers) line up.
	var run := _is_run(kind)
	var nearest_same := INF
	var nearest_any := INF
	for e: Dictionary in placed:
		if str(e.layer) != "body" or is_same(e, c.get("ignore")) or is_same(e, c.get("host")):
			continue
		var d := (e.c as Vector2).distance_to(pos)
		nearest_any = minf(nearest_any, d)
		if str(e.kind) == kind:
			nearest_same = minf(nearest_same, d)
	if run and nearest_same < INF:
		s += minf(nearest_same, 8.0) * 1.2
	elif mode in ["bed", "wall", "free", "corner"] and nearest_any < INF:
		s -= minf(nearest_any, 3.5) * (0.9 if mode == "bed" else 0.4)
	# Nothing standing between the sofa and the TV.
	if mode in ["wall", "free", "seat", "corner"] and not ("coffee" in kind or _is_screen(kind) or "sofa" in kind):
		var view := _sightline()
		if not view.is_empty() and Geometry2D.get_closest_point_to_segment(pos, view[0], view[1]).distance_to(pos) < 0.9:
			s += 4.0
	# Keep pieces away from doors.
	if mode in ["bed", "wall", "free", "corner", "seat"]:
		for dr: Dictionary in doors:
			s += maxf(0.0, 2.0 - pos.distance_to(dr.c)) * 1.5
	match mode:
		"bed":
			# Headboard not under a window; the first bed central on its wall.
			if _under_window(c):
				s += 1.5
			if k == 0 and _none_placed():
				s += absf(float(c.s) - float(edges[int(c.edge)].len) * 0.5) * 0.3
			s -= float(edges[int(c.edge)].len) * 0.05
		"wall":
			if c.has("wall"):
				if "desk" in kind and rel == "":
					var wdw := _nearest(pos, windows)
					if wdw != Vector2.INF:
						s += pos.distance_to(wdw) * 0.4
				if "wardrobe" in kind or "tall" in kind:
					s += minf(_nearest_point(pos, corners).distance_to(pos), 3.0) * 0.3
				if _is_screen(kind):
					s += _facing_seats(pos, front) * 2.0
			if "sofa" in kind:
				s += _facing_screen(pos, front) * 1.5
				# Looking into the room, not at a wall close in front.
				s -= minf(_view(pos, front), 4.5) * 0.8
		"free":
			s += pos.distance_to(centroid) * 0.35
			if "sofa" in kind or "armchair" in kind or "lounge" in kind:
				s += _facing_screen(pos, front) * 1.5
				s += (1.0 - front.dot((centroid - pos).normalized())) * 0.5
				# Armchairs with the sofa, not off on their own.
				var sofa := INF
				for e: Dictionary in placed:
					if "sofa" in str(e.kind):
						sofa = minf(sofa, pos.distance_to(e.c))
				if sofa < INF and not "sofa" in kind:
					s += sofa * 0.8
		"corner":
			s += minf(_nearest_point(pos, corners).distance_to(pos), 5.0) * 1.0
		"mounted":
			if _is_screen(kind):
				s += _facing_seats(pos, front) * 2.0
			elif "kitchen" in kind:
				var unit := INF
				for e: Dictionary in placed:
					if "kitchen" in str(e.kind) and str(e.layer) == "body":
						unit = minf(unit, pos.distance_to(e.c))
				s += minf(unit, 8.0) * 1.5
			else:
				# Pictures over a bed or sofa, else mid wall.
				var over := INF
				for e: Dictionary in placed:
					if DesignFitoutRules.is_bed(catalog, str(e.kind)) or "sofa" in str(e.kind):
						over = minf(over, pos.distance_to(e.c))
				s += minf(over, 4.0) * 0.5
				s -= minf(nearest_any, 3.0) * 0.1
		"floor":
			s += pos.distance_to(centroid) * 0.3
		"seat":
			if not c.has("ignore"):
				s += pos.distance_to(centroid) * 0.1
	return s


## [sofa centre, screen centre] once both are in, else [].
func _sightline() -> Array:
	var sofa := Vector2.INF
	var screen := Vector2.INF
	for e: Dictionary in placed:
		if "sofa" in str(e.kind):
			sofa = e.c
		elif _is_screen(str(e.kind)):
			screen = e.c
	return [] if sofa == Vector2.INF or screen == Vector2.INF else [sofa, screen]


## How far the room's walls are straight ahead of pos, m.
func _view(pos: Vector2, dir: Vector2) -> float:
	var far := pos + dir * 50.0
	var best := 50.0
	for e: Dictionary in edges:
		var hit: Variant = Geometry2D.segment_intersects_segment(pos, far, e.a, e.b)
		if hit is Vector2:
			best = minf(best, pos.distance_to(hit))
	return best


func _none_placed() -> bool:
	for e: Dictionary in placed:
		if not bool(e.fixed):
			return false
	return true


func _facing_screen(pos: Vector2, front: Vector2) -> float:
	for e: Dictionary in placed:
		if _is_screen(str(e.kind)):
			return 1.0 - front.dot(((e.c as Vector2) - pos).normalized())
	return 0.0


func _facing_seats(pos: Vector2, front: Vector2) -> float:
	for e: Dictionary in placed:
		if "sofa" in str(e.kind) or "armchair" in str(e.kind):
			return 1.0 - front.dot(((e.c as Vector2) - pos).normalized())
	return 0.0


func _under_window(c: Dictionary) -> bool:
	for w: Dictionary in windows:
		if Geometry2D.is_point_in_polygon(w.c + (w.n as Vector2) * 0.2, c.body.duplicate()) or _overlap(w.zone, c.body):
			return true
	return false


# --- Checks --------------------------------------------------------------------------------

## Body inside the room, clear of doors, of every other piece and of their clear floor; its
## own clear floor inside the room and clear of every other piece.
func _fits(c: Dictionary, layer: String, tall: bool) -> bool:
	var body: PackedVector2Array = c.body
	if not _inside(body):
		return false
	var box := _box_of(body)
	for dr: Dictionary in doors:
		if _overlap(dr.zone, body):
			return false
	if tall or layer == "mounted":
		for w: Dictionary in windows:
			if _overlap(w.zone, body):
				return false
	var ignore: Variant = c.get("ignore")
	var host: Variant = c.get("host")
	for e: Dictionary in placed:
		if is_same(e, host):
			continue
		var el := str(e.layer)
		match layer:
			"body":
				if el == "body" and (e.box as Rect2).grow(0.01).intersects(box) and _overlap(e.body, body):
					return false
				if el == "body" and not is_same(e, ignore):
					for z: PackedVector2Array in e.zones:
						if _overlap(z, body):
							return false
			"floor", "ceiling", "top":
				if el == layer and _overlap(e.body, body):
					return false
			"mounted":
				if el == "mounted" and _overlap(e.body, body):
					return false
				if el == "body" and bool((e.rule as Dictionary).get("tall", false)) and _overlap(e.body, body):
					return false
	for z: PackedVector2Array in c.zones:
		if not _zone_free(z, ignore):
			return false
	return true


func _zone_free(z: PackedVector2Array, ignore: Variant = null) -> bool:
	if not _inside(_shrink(z, 0.03)):
		return false
	var box := _box_of(z)
	for e: Dictionary in placed:
		if is_same(e, ignore) or str(e.layer) != "body":
			continue
		if (e.box as Rect2).intersects(box) and _overlap(e.body, z):
			return false
	return true


func _inside(poly: PackedVector2Array) -> bool:
	return Geometry2D.clip_polygons(poly, inner).is_empty()


## Separating axes for two convex outlines; touching does not count.
static func _overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for poly: PackedVector2Array in [a, b]:
		var n := poly.size()
		for i in n:
			var e := poly[(i + 1) % n] - poly[i]
			if e.length_squared() < 1e-10:
				continue
			var axis := Vector2(-e.y, e.x).normalized()
			var amin := INF
			var amax := -INF
			for p in a:
				var d := axis.dot(p)
				amin = minf(amin, d)
				amax = maxf(amax, d)
			var bmin := INF
			var bmax := -INF
			for p in b:
				var d := axis.dot(p)
				bmin = minf(bmin, d)
				bmax = maxf(bmax, d)
			if amax <= bmin + EPS or bmax <= amin + EPS:
				return false
	return true


# --- Rows (many of one thing: a classroom of desks, a hall of chairs, a ward of beds) -----

func _rows_suit(p: Dictionary) -> bool:
	var mode := str((p.rule as Dictionary).mode)
	var sz := _size(str(p.kind))
	return int(p.count) >= 6 and str(p.rel) == "" and mode in ["seat", "free", "wall"] and sz.x * sz.y < 3.0 \
			and not _is_run(str(p.kind))


## Rows facing the longest wall without a door (or the teacher's desk), with aisles.
func _place_rows(p: Dictionary) -> int:
	var kind := str(p.kind)
	var sz := _size(kind)
	var best_e := -1
	var best := -INF
	for ei in edges.size():
		var e: Dictionary = edges[ei]
		var v := float(e.len)
		for dr: Dictionary in doors:
			if _edge_distance_seg(dr.c, e.a, e.b) < 0.4:
				v -= 100.0
		for q: Dictionary in placed:
			if "teacher" in str(q.kind) or "projection" in str(q.kind):
				v += 50.0 - _edge_distance_seg(q.c, e.a, e.b) * 10.0
		if v > best:
			best = v
			best_e = ei
	if best_e < 0:
		return 0
	var e: Dictionary = edges[best_e]
	var u: Vector2 = e.u
	var nin: Vector2 = e.n
	var th := atan2(nin.x, nin.y)
	var desk := "desk" in kind or DesignFitoutRules.is_table(catalog, kind)
	var gap_u := 0.1 if desk else 0.05
	var block := 2 if desk else 8
	var aisle := 0.7 if desk else 1.0
	var row := sz.y + (0.75 if desk else 0.45)
	var front := 1.6 if desk or str((p.rule as Dictionary).mode) == "seat" else 0.6
	# Across: as many as fit between the side walls with aisles, centred.
	var lo := INF
	var hi := -INF
	var far := 0.0
	for q in inner:
		var a := (q - (e.a as Vector2)).dot(u)
		lo = minf(lo, a)
		hi = maxf(hi, a)
		far = maxf(far, (q - (e.a as Vector2)).dot(nin))
	var width := hi - lo - 1.2
	var xs: Array = []
	var x := 0.0
	var i := 0
	while x + sz.x <= width:
		xs.append(x + sz.x * 0.5)
		x += sz.x + gap_u
		i += 1
		if i % block == 0:
			x += aisle
	if xs.is_empty():
		return 0
	var shift: float = lo + 0.6 + (width - (float(xs[-1]) + sz.x * 0.5)) * 0.5
	var got := 0
	var z := front + sz.y * 0.5
	while z + sz.y * 0.5 < far - 0.6 and got < int(p.count):
		for xv: float in xs:
			if got >= int(p.count):
				break
			var c: Vector2 = (e.a as Vector2) + u * (shift + xv) + nin * z
			var cand := _own_frame(c, th, sz, 0.0, 0.0, "body", 0.0)
			if _fits(cand, "body", false):
				_commit(_entry(p, cand))
				got += 1
		z += row
	return got


# --- The way in ----------------------------------------------------------------------------

func _grid() -> void:
	_gw = maxi(1, ceili(bounds.size.x / _cell))
	_gh = maxi(1, ceili(bounds.size.y / _cell))
	_free.resize(_gw * _gh)
	_block.resize(_gw * _gh)
	_block.fill(0)
	for iz in _gh:
		for ix in _gw:
			var p := _cell_pos(ix, iz)
			_free[iz * _gw + ix] = 1 if Geometry2D.is_point_in_polygon(p, inner) and _edge_distance(p, inner) >= PERSON else 0
	for e: Dictionary in placed:
		if str(e.layer) == "body":
			_mark(e.body, 1)


func _cell_pos(ix: int, iz: int) -> Vector2:
	return bounds.position + Vector2((ix + 0.5) * _cell, (iz + 0.5) * _cell)


func _mark(body: PackedVector2Array, by: int) -> void:
	var box := _box_of(body).grow(PERSON)
	var x0 := clampi(floori((box.position.x - bounds.position.x) / _cell), 0, _gw - 1)
	var x1 := clampi(ceili((box.end.x - bounds.position.x) / _cell), 0, _gw - 1)
	var z0 := clampi(floori((box.position.y - bounds.position.y) / _cell), 0, _gh - 1)
	var z1 := clampi(ceili((box.end.y - bounds.position.y) / _cell), 0, _gh - 1)
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var p := _cell_pos(ix, iz)
			if Geometry2D.is_point_in_polygon(p, body) or _edge_distance(p, body) < PERSON:
				_block[iz * _gw + ix] += by


## Whether, with this piece in, every placed piece's clear floor can still be walked to
## from a door. Rooms with no door are not checked.
func _walkable_with(e: Dictionary) -> bool:
	if doors.is_empty():
		return true
	_mark(e.body, 1)
	var seen := PackedByteArray()
	seen.resize(_gw * _gh)
	var queue := PackedInt32Array()
	for dr: Dictionary in doors:
		var p: Vector2 = dr.c + (dr.n as Vector2) * (PERSON + _cell)
		for dx in range(-3, 4):
			var q := p + (dr.n as Vector2).orthogonal() * dx * _cell
			var ix := floori((q.x - bounds.position.x) / _cell)
			var iz := floori((q.y - bounds.position.y) / _cell)
			if ix >= 0 and iz >= 0 and ix < _gw and iz < _gh:
				var id := iz * _gw + ix
				if _block[id] == 0 and seen[id] == 0:
					seen[id] = 1
					queue.append(id)
	var head := 0
	while head < queue.size():
		var id := queue[head]
		head += 1
		var ix := id % _gw
		@warning_ignore("integer_division")
		var iz := id / _gw
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var jx := ix + d.x
			var jz := iz + d.y
			if jx < 0 or jz < 0 or jx >= _gw or jz >= _gh:
				continue
			var j := jz * _gw + jx
			if seen[j] == 0 and _free[j] == 1 and _block[j] == 0:
				seen[j] = 1
				queue.append(j)
	var ok_all := true
	if queue.size() > 0:
		for q: Dictionary in placed + [e]:
			if bool(q.fixed) or (q.zones as Array).is_empty():
				continue
			if not _reached(q.zones, seen):
				ok_all = false
				break
	_mark(e.body, -1)
	return ok_all


func _reached(zones: Array, seen: PackedByteArray) -> bool:
	for z: PackedVector2Array in zones:
		var box := _box_of(z).grow(0.2)
		var x0 := clampi(floori((box.position.x - bounds.position.x) / _cell), 0, _gw - 1)
		var x1 := clampi(ceili((box.end.x - bounds.position.x) / _cell), 0, _gw - 1)
		var z0 := clampi(floori((box.position.y - bounds.position.y) / _cell), 0, _gh - 1)
		var z1 := clampi(ceili((box.end.y - bounds.position.y) / _cell), 0, _gh - 1)
		for iz in range(z0, z1 + 1):
			for ix in range(x0, x1 + 1):
				if seen[iz * _gw + ix] == 1:
					var p := _cell_pos(ix, iz)
					if Geometry2D.is_point_in_polygon(p, z) or _edge_distance(p, z) < 0.2:
						return true
	return false


# --- Small helpers -------------------------------------------------------------------------

func _size(kind: String) -> Vector2:
	var k := catalog.kind(kind)
	return Vector2(maxf(float(k.get("w", 0.6)), 0.05), maxf(float(k.get("d", 0.6)), 0.05))


func _is_run(kind: String) -> bool:
	for w: String in ["kitchen", "locker", "filing", "base_", "lab_bench", "urinal", "basin", "wc", "beam_"]:
		if w in kind:
			return true
	return false


func _is_screen(kind: String) -> bool:
	return "tv" in kind or "television" in kind or "projection" in kind


func _kind_has(kind: String, words: Array) -> bool:
	for w: String in words:
		if w in kind:
			return true
	return false


func _nearest(pos: Vector2, list: Array) -> Vector2:
	var best := Vector2.INF
	for o: Dictionary in list:
		if best == Vector2.INF or pos.distance_to(o.c) < pos.distance_to(best):
			best = o.c
	return best


static func _nearest_point(pos: Vector2, pts: PackedVector2Array) -> Vector2:
	var best := pos + Vector2(1000, 0)
	for p in pts:
		if pos.distance_to(p) < pos.distance_to(best):
			best = p
	return best


## A rectangle: centre, its x axis (unit), half sizes along x and across.
static func _obb(c: Vector2, ax: Vector2, hx: float, hy: float) -> PackedVector2Array:
	var py := Vector2(-ax.y, ax.x)
	return PackedVector2Array([c - ax * hx - py * hy, c + ax * hx - py * hy, c + ax * hx + py * hy, c - ax * hx + py * hy])


static func _shrink(poly: PackedVector2Array, by: float) -> PackedVector2Array:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= poly.size()
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + (c - p).normalized() * minf(by, (c - p).length() * 0.5))
	return out


static func _box_of(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


static func _signed_area(poly: PackedVector2Array) -> float:
	var s := 0.0
	var n := poly.size()
	for i in n:
		s += poly[i].cross(poly[(i + 1) % n])
	return s * 0.5


static func _edge_distance(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	var n := poly.size()
	for i in n:
		best = minf(best, _edge_distance_seg(p, poly[i], poly[(i + 1) % n]))
	return best


static func _edge_distance_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))


static func _collinear(wa: Vector2, wb: Vector2, p: Vector2, q: Vector2) -> bool:
	var len := p.distance_to(q)
	if len < 0.01:
		return false
	var u := (q - p) / len
	var nrm := Vector2(-u.y, u.x)
	if absf((wa - p).dot(nrm)) > 0.08 or absf((wb - p).dot(nrm)) > 0.08:
		return false
	var s0 := (wa - p).dot(u)
	var s1 := (wb - p).dot(u)
	return minf(maxf(s0, s1), len) - maxf(minf(s0, s1), 0.0) > 0.1


static func _poly_centre(poly: PackedVector2Array) -> Vector2:
	var box := _box_of(poly)
	var best := poly[0]
	var best_d := -1.0
	for ix in 12:
		for iz in 12:
			var p := box.position + Vector2((ix + 0.5) / 12.0 * box.size.x, (iz + 0.5) / 12.0 * box.size.y)
			if Geometry2D.is_point_in_polygon(p, poly):
				var d := _edge_distance(p, poly)
				if d > best_d:
					best_d = d
					best = p
	return best
