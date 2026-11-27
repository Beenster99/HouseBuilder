class_name DesignBounds
extends RefCounted
## The building's extent (world m), kept up to date edit by edit: an added or changed entry
## grows it; a load or a change of levels works it out again from everything. Taking a part
## away leaves it as it was until then (a little too big is harmless for framing a view,
## and walking every part of a big building takes tens of ms).
##
##   var b := DesignBounds.new(model)
##   b.box()   # AABB

const EMPTY := AABB(Vector3(-10, 0, -10), Vector3(20, 6, 20))

var model: BuildingModel
var _box := AABB()
var _empty := true
var _stale := true


func _init(m: BuildingModel) -> void:
	model = m
	model.entry_added.connect(_grow)
	model.entry_changed.connect(_grow)
	model.loaded.connect(_restale)
	model.levels_changed.connect(_restale)


func box() -> AABB:
	if _stale:
		_stale = false
		_empty = true
		for id: String in model.parts:
			_grow(id)
		for id: String in model.rooms:
			_grow(id)
	if _empty:
		return EMPTY
	var out := _box
	out.size.y = maxf(out.size.y, 3.0)
	return out


func _restale() -> void:
	_stale = true


func _grow(id: String) -> void:
	if _stale:
		return
	var b := AABB()
	if model.parts.has(id):
		b = model.aabb_of(id)
	elif model.rooms.has(id):
		var r: Dictionary = model.rooms[id]
		var y := model.level_elevation(int(r.level))
		var first := true
		for p: Variant in r.outline:
			var v := Vector3(float(p[0]), y, float(p[1]))
			b = AABB(v, Vector3.ZERO) if first else b.expand(v)
			first = false
		if first:
			return
	else:
		return
	_box = b if _empty else _box.merge(b)
	_empty = false
