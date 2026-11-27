extends VBoxContainer
## The left column's "add" palette: Rooms and Objects, each grouped (DesignBus.palette_groups,
## the same groups walk-inside's Tab menu shows) with a filter box. Picking a room type arms
## the Room tool with it (drag on the plan to size the room, let go to draw it); picking an
## object arms Furniture, Door or Window with it. Another module's group (saved modules)
## gets its own pick. In contract mode, items the firm has not unlocked yet are greyed with the
## tier that opens them (DesignBus.locked_tier) and cannot be picked.

var room: Node3D
var _session: DesignSession
var _tabs: TabContainer
var _trees: Dictionary = {}  # kind -> Tree
var _filters: Dictionary = {}  # kind -> LineEdit
var _dirty := true


func _ready() -> void:
	_session = room.get("session")
	size_flags_vertical = SIZE_EXPAND_FILL
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = SIZE_EXPAND_FILL
	_tabs.custom_minimum_size.y = 200
	add_child(_tabs)
	for kind: String in ["rooms", "objects"]:
		var box := VBoxContainer.new()
		box.name = "Add rooms" if kind == "rooms" else "Add objects"
		_tabs.add_child(box)
		var f := LineEdit.new()
		f.placeholder_text = "Filter (name or group)"
		f.clear_button_enabled = true
		f.text_changed.connect(func(_t: String) -> void: fill(kind))
		box.add_child(f)
		_filters[kind] = f
		var t := Tree.new()
		t.hide_root = true
		t.focus_mode = FOCUS_NONE
		t.size_flags_vertical = SIZE_EXPAND_FILL
		t.item_selected.connect(func() -> void: _picked(kind))
		box.add_child(t)
		_trees[kind] = t
	var design := Modules.bus("design") as DesignBus
	design.palette_changed.connect(func() -> void: _dirty = true)
	_session.tool_changed.connect(func(_t: String) -> void: _show_current())


func _process(_delta: float) -> void:
	if _dirty and is_visible_in_tree():
		_dirty = false
		fill("rooms")
		fill("objects")


## Lists `kind`'s groups as folding branches, filtered by its box.
func fill(kind: String) -> void:
	var design := Modules.bus("design") as DesignBus
	var groups := DesignBus.filter_groups(design.palette_groups(kind), (_filters[kind] as LineEdit).text)
	var t: Tree = _trees[kind]
	t.clear()
	var root := t.create_item()
	var filtering := (_filters[kind] as LineEdit).text.strip_edges() != ""
	for g: Dictionary in groups:
		var head := t.create_item(root)
		head.set_text(0, "%s  (%d)" % [str(g.title), (g.items as Array).size()])
		head.set_selectable(0, false)
		head.set_custom_color(0, BsxTheme.HUD_DIM)
		head.collapsed = not filtering and groups.size() > 1 and not _holds_current(kind, g)
		for it: Dictionary in g.items:
			var row := t.create_item(head)
			var lock := int(it.get("lock", 0))
			row.set_text(0, str(it.label) if lock <= 0 else "%s   Tier %d" % [str(it.label), lock])
			row.set_metadata(0, {"id": str(it.id), "source": str(g.get("source", "")), "lock": lock})
			if lock > 0:
				# Not open to this firm yet: greyed, with the tier that opens it.
				row.set_selectable(0, false)
				row.set_tooltip_text(0, "Opens at tier %d" % lock)
			else:
				row.set_tooltip_text(0, ", ".join(it.get("tags", PackedStringArray())))
	_show_current()


## Item count shown for `kind` (tests).
func row_count(kind: String) -> int:
	var n := 0
	var root: TreeItem = (_trees[kind] as Tree).get_root()
	if root == null:
		return 0
	for g in root.get_children():
		n += g.get_child_count()
	return n


func set_filter(kind: String, text: String) -> void:
	(_filters[kind] as LineEdit).text = text
	fill(kind)


## Picks an item by id, as a click on it would (tests, keys).
func pick(kind: String, id: String) -> bool:
	var root: TreeItem = (_trees[kind] as Tree).get_root()
	if root == null:
		return false
	for g in root.get_children():
		for row in g.get_children():
			if str((row.get_metadata(0) as Dictionary).id) == id:
				_use(kind, row.get_metadata(0) as Dictionary)
				return true
	return false


func _picked(kind: String) -> void:
	var row := (_trees[kind] as Tree).get_selected()
	if row == null or row.get_metadata(0) == null:
		return
	_use(kind, row.get_metadata(0) as Dictionary)


func _use(kind: String, m: Dictionary) -> void:
	if int(m.get("lock", 0)) > 0:
		return
	var id := str(m.id)
	var source := str(m.get("source", ""))
	var design := Modules.bus("design") as DesignBus
	design.palette_previewed.emit(kind, id, source)
	if source != "":
		var g: Dictionary = design.palette_extra.get("%s:%s" % [kind, source], {})
		if (g.get("pick", Callable()) as Callable).is_valid():
			(g.pick as Callable).call(id)
		return
	if kind == "rooms":
		_session.use_room_type(id)
	else:
		_session.use_kind(id)


func _holds_current(kind: String, g: Dictionary) -> bool:
	var cur := _current(kind)
	for it: Dictionary in g.items:
		if str(it.id) == cur:
			return true
	return false


func _current(kind: String) -> String:
	if kind == "rooms":
		return _session.room_type if _session.tool == "room" else ""
	match _session.tool:
		"fixture": return _session.fixture_kind
		"door": return _session.door_kind
		"window": return _session.window_kind
	return ""


## Highlights what the armed tool will place.
func _show_current() -> void:
	for kind: String in _trees:
		var t: Tree = _trees[kind]
		var root := t.get_root()
		if root == null:
			continue
		var cur := _current(kind)
		for g in root.get_children():
			for row in g.get_children():
				var meta := row.get_metadata(0) as Dictionary
				var on := cur != "" and str(meta.id) == cur
				row.set_custom_color(0, BsxTheme.ACCENT if on else (BsxTheme.HUD_DIM if int(meta.get("lock", 0)) > 0 else BsxTheme.TEXT))
