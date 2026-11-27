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
var _age := 0.0
var _stale_tabs: Dictionary = {}
## The lists catch up with edits at most this often, s.
const EVERY := 0.5


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
	tab_changed.connect(_on_tab)


func _on_tab(t: int) -> void:
	if not _stale_tabs.has(t):
		return
	_stale_tabs.erase(t)
	if t == 0:
		_fill_rooms()
	elif t == 1:
		_fill_components()
	else:
		_fill_levels()


func _mark(_op: Variant = null) -> void:
	_dirty = true


func _process(delta: float) -> void:
	_age += delta
	if _dirty and _age >= EVERY and is_visible_in_tree():
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


## Fills the tab on show (all three with all=true) from the model. Edits call it at most
## twice a second, and switching tabs fills the new one.
func refresh(all := false) -> void:
	_dirty = false
	_age = 0.0
	var tab := current_tab
	if all or tab == 0:
		_fill_rooms()
	if all or tab == 1:
		_fill_components()
	if all or tab == 2:
		_fill_levels()
	if not all:
		_stale_tabs = {0: true, 1: true, 2: true}
		_stale_tabs.erase(tab)


func _fill_rooms() -> void:
	var cat := _model.catalog
	var rows: Array = []
	for rid: String in _model.rooms:
		var e: Dictionary = _model.rooms[rid]
		if int(e.level) != _session.level:
			continue
		var rt := cat.room_type(str(e.type))
		var label := str(e.get("name", ""))
		if label == "":
			label = str(rt.get("label", e.type))
		rows.append([label, rid, e, rt])
	rows.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] if x[0] != y[0] else x[1] < y[1])
	_rooms.clear()
	for r: Array in rows:
		var e: Dictionary = r[2]
		var rt: Dictionary = r[3]
		var area := BuildingModel.outline_area(e.outline)
		var min_area := float(rt.get("min_area", 0.0))
		var short := area + BuildingModel.EPS < min_area
		var i := _rooms.add_item("%s   %.1f m²%s" % [r[0], area, "  (small)" if short else ""])
		_rooms.set_item_metadata(i, r[1])
		if short:
			_rooms.set_item_custom_fg_color(i, BsxTheme.WARN)
		_rooms.set_item_tooltip(i, "At least %.1f m² for a %s" % [min_area, str(rt.get("label", e.type)).to_lower()])


func _fill_components() -> void:
	var cat := _model.catalog
	var counts: Dictionary = {}
	for pid: String in _model.parts:
		var e: Dictionary = _model.parts[pid]
		# Openings count on their wall's level.
		var lv := int(e.get("level", -1)) if not e.has("host") else _model.level_of(pid)
		if lv == _session.level:
			var k := str(e.kind)
			counts[k] = int(counts.get(k, 0)) + 1
	var kinds: Array = counts.keys()
	kinds.sort_custom(func(a: String, b: String) -> bool:
		var fa := cat.family_of(a)
		var fb := cat.family_of(b)
		return fa < fb if fa != fb else a < b)
	_parts.clear()
	for k: String in kinds:
		var i := _parts.add_item("%s × %d   (%s)" % [str(cat.kind(k).get("label", k)), int(counts[k]), cat.family_of(k)])
		_parts.set_item_metadata(i, k)


func _fill_levels() -> void:
	var per := {}
	for rid: String in _model.rooms:
		var l := int(_model.rooms[rid].level)
		per[l] = int(per.get(l, 0)) + 1
	_levels.clear()
	for l in _model.level_count():
		var lv: Dictionary = _model.levels[l]
		var i := _levels.add_item("%s%s   %d rooms" % ["▶ " if l == _session.level else "", str(lv.get("name", "Level %d" % l)),
				int(per.get(l, 0))])
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
	for pid: String in _model.parts:
		if str(_model.parts[pid].kind) == k and _model.level_of(pid) == _session.level:
			ids.append(pid)
	_session.presence.select(ids)


func room_rows() -> int:
	return _rooms.item_count


func component_rows() -> int:
	return _parts.item_count
