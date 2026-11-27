extends TabContainer
## The design room's browser, docked under the tools (as in BSX's design room): tabs listing the
## building's Rooms, Components and Levels. Click a row to select it (and look at it); the
## lists keep up with every player's edits.

var room: Node3D
var _session: DesignSession
var _model: BuildingModel
var _rooms: ItemList
var _parts: ItemList
var _levels: ItemList
var _dirty := true


func _ready() -> void:
	_session = room.get("session")
	_model = _session.model
	size_flags_vertical = SIZE_EXPAND_FILL
	custom_minimum_size.y = 220
	_rooms = _list("Rooms", _pick_room)
	_parts = _list("Components", _pick_kind)
	_levels = _list("Levels", func(i: int) -> void: _session.set_level(int(_levels.get_item_metadata(i))))
	_model.changed.connect(_mark)
	_model.loaded.connect(_mark.bind(null))
	_model.levels_changed.connect(_mark.bind(null))
	_session.level_changed.connect(func(_l: int) -> void: _mark(null))


func _mark(_op: Variant = null) -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty and is_visible_in_tree():
		refresh()


func _list(title: String, pick: Callable) -> ItemList:
	var l := ItemList.new()
	l.name = title
	l.focus_mode = FOCUS_NONE
	l.size_flags_vertical = SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 14)
	l.item_clicked.connect(func(i: int, _at: Vector2, _b: int) -> void: pick.call(i))
	add_child(l)
	return l


## Fills the three lists from the model (the room calls it on changes, once a frame at most).
func refresh() -> void:
	_dirty = false
	var cat := _model.catalog
	_rooms.clear()
	for rid in _model.rooms_on(_session.level):
		var r := BuildingQuantities.room(_model, rid)
		var label := str(cat.room_type(str(_model.rooms[rid].type)).get("label", _model.rooms[rid].type))
		var i := _rooms.add_item("%s   %.1f m²%s" % [label, float(r.area), "  (small)" if bool(r.short) else ""])
		_rooms.set_item_metadata(i, rid)
		if bool(r.short):
			_rooms.set_item_custom_fg_color(i, BsxTheme.WARN)
		_rooms.set_item_tooltip(i, "Min %.1f m², fits %d" % [float(r.min_area), int(r.capacity)])
	_parts.clear()
	var counts: Dictionary = {}
	for pid in _model.parts_on(_session.level):
		var k := str(_model.parts[pid].kind)
		counts[k] = int(counts.get(k, 0)) + 1
	var kinds: Array = counts.keys()
	kinds.sort_custom(func(a: String, b: String) -> bool:
		var fa := cat.family_of(a)
		var fb := cat.family_of(b)
		return fa < fb if fa != fb else a < b)
	for k: String in kinds:
		var i := _parts.add_item("%s × %d   (%s)" % [str(cat.kind(k).get("label", k)), int(counts[k]), cat.family_of(k)])
		_parts.set_item_metadata(i, k)
	_levels.clear()
	for l in _model.level_count():
		var lv: Dictionary = _model.levels[l]
		var i := _levels.add_item("%s%s   %d rooms" % ["▶ " if l == _session.level else "", str(lv.get("name", "Level %d" % l)),
				_model.rooms_on(l).size()])
		_levels.set_item_metadata(i, l)


func _pick_room(i: int) -> void:
	var rid := str(_rooms.get_item_metadata(i))
	_session.presence.select(PackedStringArray([rid]))
	var o: Array = _model.rooms[rid].outline
	var c := Vector2.ZERO
	for p: Variant in o:
		c += Vector2(p[0], p[1]) if p is Array else p as Vector2
	if not o.is_empty():
		c /= o.size()
		var cam: Variant = room.get("camera")
		if cam != null:
			cam.set("focus", Vector3(c.x, _session.floor_y(), c.y))
			cam.call("place")


func _pick_kind(i: int) -> void:
	var k := str(_parts.get_item_metadata(i))
	var ids := PackedStringArray()
	for pid in _model.parts_on(_session.level):
		if str(_model.parts[pid].kind) == k:
			ids.append(pid)
	_session.presence.select(ids)


func room_rows() -> int:
	return _rooms.item_count


func component_rows() -> int:
	return _parts.item_count
