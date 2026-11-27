class_name WallJoins
extends RefCounted
## How walls meet, so corners and tees join cleanly wherever walls are drawn as boxes along
## their centre lines (the designer's plan and 3D, the small views, the holotable; timelapse
## and walk-inside can use it too). Where two walls turn a corner, one runs on by half the
## other's thickness and the other stops at its face; a wall that ends against another's side
## (a tee) stops at that face; walls that carry straight on just meet.
##
##   var joins := WallJoins.new(model)
##   var ext := joins.ends(id)          # Vector2(at a, at b): + runs on past the point, - stops short
##   var a2 := a - dir * ext.x;  var b2 := b + dir * ext.y
##   joins.neighbours(id)              # walls whose joins change when this one does
##
## Pure reads of the model, indexed per model revision.

const NEAR := 0.03
## Directions this close to parallel (cos) count as carrying straight on.
const STRAIGHT := 0.985
const CELL := 2.0
const DEFAULT_THICKNESS := 0.2

var model: BuildingModel
var _rev := -1
var _cells: Dictionary = {}  # "level|x|z" -> Array of wall ids


func _init(m: BuildingModel) -> void:
	model = m


## A wall's thickness, m.
func thickness(id: String) -> float:
	var e: Dictionary = model.parts.get(id, {})
	return float(model.catalog.section(str(e.get("section", ""))).get("d", DEFAULT_THICKNESS))


## How far to run wall `id`'s a and b ends on (+) or stop them short (-) along its line.
func ends(id: String) -> Vector2:
	var e: Dictionary = model.parts.get(id, {})
	if not _is_wall(e):
		return Vector2.ZERO
	_index()
	var lv := model.level_of(id)
	var a := _p(e.a)
	var b := _p(e.b)
	return Vector2(_end(id, lv, a, b), _end(id, lv, b, a))


## The walls touching `id`'s ends or ending on it: their joins depend on it.
func neighbours(id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var e: Dictionary = model.parts.get(id, {})
	if not _is_wall(e):
		return out
	_index()
	var lv := model.level_of(id)
	var a := _p(e.a)
	var b := _p(e.b)
	var seen := {}
	for p: Vector2 in [a, b]:
		for wid: String in _near(lv, p):
			seen[wid] = true
	# Walls ending somewhere along this one (tees).
	var steps := maxi(1, ceili(a.distance_to(b) / CELL))
	for i in steps + 1:
		for wid: String in _near(lv, a.lerp(b, float(i) / steps)):
			seen[wid] = true
	for wid: String in seen:
		if wid == id:
			continue
		var w: Dictionary = model.parts[wid]
		var wa := _p(w.a)
		var wb := _p(w.b)
		if _on_seg(wa, a, b) or _on_seg(wb, a, b) or _on_seg(a, wa, wb) or _on_seg(b, wa, wb):
			out.append(wid)
	return out


func _end(id: String, lv: int, p: Vector2, far: Vector2) -> float:
	var mine := (far - p).normalized()
	var here: Array = []  # [id, direction away from p]
	for wid: String in _near(lv, p):
		if wid == id:
			continue
		var w: Dictionary = model.parts[wid]
		var wa := _p(w.a)
		var wb := _p(w.b)
		if wa.distance_to(p) < NEAR or wb.distance_to(p) < NEAR:
			var d := ((wb if wa.distance_to(p) < NEAR else wa) - p).normalized()
			if d.dot(mine) > STRAIGHT:
				continue  # lying along this one: not a join
			here.append([wid, d])
		elif _on_seg(p, wa, wb):
			return -thickness(wid) / 2.0  # a tee: stop at its face
	if here.is_empty():
		return 0.0
	for h: Array in here:
		if (h[1] as Vector2).dot(mine) < -STRAIGHT:
			return 0.0  # this wall carries straight on through
	# Another pair carries straight on through here: this one is a tee against them.
	for i in here.size():
		for j in range(i + 1, here.size()):
			if (here[i][1] as Vector2).dot(here[j][1] as Vector2) < -STRAIGHT:
				return -maxf(thickness(str(here[i][0])), thickness(str(here[j][0]))) / 2.0
	# A corner: the first by id runs on over the others' ends, the rest stop at its face.
	var owner := id
	var widest := 0.0
	for h: Array in here:
		widest = maxf(widest, thickness(str(h[0])))
		if _before(str(h[0]), owner):
			owner = str(h[0])
	return widest / 2.0 if owner == id else -thickness(owner) / 2.0


static func _before(x: String, y: String) -> bool:
	var nx := x.substr(1).to_int()
	var ny := y.substr(1).to_int()
	return nx < ny if nx != ny else x < y


func _is_wall(e: Dictionary) -> bool:
	return not e.is_empty() and e.has("a") and e.has("b") and model.catalog.family_of(str(e.get("kind", ""))) == "wall"


static func _p(v: Array) -> Vector2:
	return Vector2(float(v[0]), float(v[2]))


static func _on_seg(p: Vector2, a: Vector2, b: Vector2) -> bool:
	return Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < NEAR


func _near(lv: int, p: Vector2) -> Array:
	var out: Array = []
	var cx := floori(p.x / CELL)
	var cz := floori(p.y / CELL)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for wid: String in _cells.get("%d|%d|%d" % [lv, cx + dx, cz + dz], []):
				if not wid in out:
					out.append(wid)
	return out


func _index() -> void:
	if _rev == model.revision:
		return
	_rev = model.revision
	_cells.clear()
	for id: String in model.parts:
		var e: Dictionary = model.parts[id]
		if not _is_wall(e):
			continue
		var lv := model.level_of(id)
		var a := _p(e.a)
		var b := _p(e.b)
		var steps := maxi(1, ceili(a.distance_to(b) / (CELL * 0.5)))
		var done := {}
		for i in steps + 1:
			var q := a.lerp(b, float(i) / steps)
			var key := "%d|%d|%d" % [lv, floori(q.x / CELL), floori(q.y / CELL)]
			if done.has(key):
				continue
			done[key] = true
			if not _cells.has(key):
				_cells[key] = []
			(_cells[key] as Array).append(id)
