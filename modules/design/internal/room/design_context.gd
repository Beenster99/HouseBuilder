extends Node
## Right-click on something in the design: a menu with Edit…, Delete and, for rooms, Remove
## this corner, Furnish and Save as module…, and anywhere (on something or bare floor) Walk
## inside from here, which starts walk-inside standing on that spot of the level. Edit opens a small form: a room's type and name,
## a part's material (and a fixture's turn). Every change goes through the building's sync, so
## everyone sees it and it undoes like any edit.

const C := preload("res://modules/building/api/building_commands.gd")

var session: DesignSession
var hud: Control
var menu: PopupMenu
var _target := ""
var _corner := -1
var _at := Vector3.ZERO
var _edit: PopupPanel
var _edit_body: VBoxContainer
var _save_module: PopupPanel
var _module_name: LineEdit
var _module_group: LineEdit

enum { EDIT, DELETE, CORNER, FURNISH, SAVE_MODULE, WALK }

const WALK_LABEL := "Walk inside from here"


func setup(p_session: DesignSession, p_hud: Control) -> void:
	session = p_session
	hud = p_hud
	name = "Context"
	menu = PopupMenu.new()
	menu.id_pressed.connect(_on_item)
	hud.add_child(menu)
	_edit = PopupPanel.new()
	_edit_body = VBoxContainer.new()
	_edit_body.custom_minimum_size = Vector2(340, 0)
	_edit.add_child(_edit_body)
	hud.add_child(_edit)
	_save_module = PopupPanel.new()
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(360, 0)
	_save_module.add_child(col)
	var l := Label.new()
	l.text = "Save this room and what's in it as a module"
	col.add_child(l)
	_module_name = LineEdit.new()
	_module_name.placeholder_text = "Name, e.g. En-suite bathroom"
	col.add_child(_module_name)
	_module_group = LineEdit.new()
	_module_group.placeholder_text = "Group, e.g. Bathrooms"
	col.add_child(_module_group)
	var b := Button.new()
	b.text = "Save module"
	b.pressed.connect(_do_save_module)
	col.add_child(b)
	hud.add_child(_save_module)


## Opens the menu for whatever is under `at` (world, raw) at screen point `screen`. False if
## there is nothing there.
func open_at(at: Vector3, screen: Vector2) -> bool:
	var sh := session.shape_hit(at)
	_corner = int(sh.i) if str(sh.get("mode", "")) == "corner" else -1
	_target = session.shape_room() if _corner >= 0 else session.pick(session.snap(at))
	_at = at
	if _target == "":
		if not can_walk():
			return false
		menu.clear()
		menu.add_item(WALK_LABEL, WALK)
		menu.popup(Rect2i(Vector2i(screen), Vector2i.ZERO))
		return true
	if not _target in session.presence.my_selection():
		session.presence.select(PackedStringArray([_target]))
	var room := session.model.rooms.has(_target)
	menu.clear()
	menu.add_item("Edit…", EDIT)
	menu.add_item("Delete  (Del)", DELETE)
	if room:
		if _corner >= 0:
			menu.add_item("Remove this corner", CORNER)
		menu.add_item("Furnish", FURNISH)
		var kits := Modules.bus("kits")
		if kits and kits.has_method("save_room"):
			menu.add_item("Save as module…", SAVE_MODULE)
	if can_walk():
		menu.add_separator()
		menu.add_item(WALK_LABEL, WALK)
	menu.popup(Rect2i(Vector2i(screen), Vector2i.ZERO))
	return true


func target() -> String:
	return _target


func _on_item(id: int) -> void:
	match id:
		EDIT:
			open_edit(_target)
		DELETE:
			session.delete_selection()
		CORNER:
			session.remove_corner(_corner)
		FURNISH:
			session.furnish_selection()
		SAVE_MODULE:
			_module_name.text = ""
			_save_module.popup_centered()
			_module_name.grab_focus()
		WALK:
			walk_here(_at)


## Whether walk-inside is there to start (the walk module, by name, with its flag on).
func can_walk() -> bool:
	var walk := Modules.bus("walk")
	return walk != null and walk.has_method("open") and Flags.is_on("walk.inside") \
			and not bool(walk.call("is_open"))


## Starts walk-inside standing at `at` on the working level, facing up the plan.
func walk_here(at: Vector3) -> Node:
	if not can_walk():
		return null
	session.cancel()
	var feet := Vector3(at.x, session.floor_y(), at.z)
	return Modules.bus("walk").call("open", session.model, self, {"at": feet, "yaw": 0.0})


## The edit form for an entry: a room's type and name, a part's material, a fixture's turn.
func open_edit(id: String) -> void:
	_target = id
	for c in _edit_body.get_children():
		c.queue_free()
	var cat := session.catalog
	var title := Label.new()
	_edit_body.add_child(title)
	var apply := Callable()
	if session.model.rooms.has(id):
		var e: Dictionary = session.model.rooms[id]
		title.text = "Edit room"
		var types := OptionButton.new()
		var ids: Array = cat.room_types.keys()
		ids.sort_custom(func(a: String, b: String) -> bool: return str(cat.room_type(a).label) < str(cat.room_type(b).label))
		for t: String in ids:
			types.add_item(str(cat.room_type(t).get("label", t)))
			types.set_item_metadata(types.item_count - 1, t)
			if t == str(e.type):
				types.select(types.item_count - 1)
		_edit_body.add_child(_row("Type", types))
		var nm := LineEdit.new()
		nm.text = str(e.get("name", ""))
		nm.placeholder_text = str(cat.room_type(str(e.type)).get("label", e.type))
		_edit_body.add_child(_row("Name", nm))
		apply = func() -> void:
			var ops: Array = []
			var t := str(types.get_item_metadata(types.selected))
			if t != str(e.type):
				ops.append(C.retag(id, t))
			if nm.text.strip_edges() != str(e.get("name", "")):
				ops.append(C.set_fields(id, {"name": nm.text.strip_edges() if nm.text.strip_edges() != "" else null}))
			_send(id, ops)
	elif session.model.parts.has(id):
		var e: Dictionary = session.model.parts[id]
		var kind := str(e.kind)
		title.text = "Edit %s" % str(cat.kind(kind).get("label", kind)).to_lower()
		var mats := cat.materials_for(kind)
		var pick := OptionButton.new()
		for m: String in mats:
			pick.add_item(str(cat.material(m).get("label", m)))
			pick.set_item_metadata(pick.item_count - 1, m)
			if m == str(e.get("material", "")):
				pick.select(pick.item_count - 1)
		if mats.size() > 1:
			_edit_body.add_child(_row("Material", pick))
		var turn := SpinBox.new()
		turn.min_value = 0
		turn.max_value = 345
		turn.step = 15
		turn.suffix = "°"
		turn.value = float(e.get("rot", 0.0))
		var point := cat.shape_of(kind) == "point"
		if point:
			_edit_body.add_child(_row("Turn", turn))
		if mats.size() <= 1 and not point:
			var none := Label.new()
			none.text = "Nothing to change here: drag it to move it, Del deletes it."
			none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_edit_body.add_child(none)
		apply = func() -> void:
			var fields := {}
			if mats.size() > 1 and pick.selected >= 0 and str(pick.get_item_metadata(pick.selected)) != str(e.get("material", "")):
				fields["material"] = str(pick.get_item_metadata(pick.selected))
			if point and not is_equal_approx(turn.value, float(e.get("rot", 0.0))):
				fields["rot"] = turn.value
			_send(id, [C.set_fields(id, fields)] if not fields.is_empty() else [])
	else:
		return
	var ok := Button.new()
	ok.text = "Apply"
	ok.pressed.connect(func() -> void:
		apply.call()
		_edit.hide())
	_edit_body.add_child(ok)
	_edit.reset_size()
	_edit.popup_centered()


func _send(id: String, ops: Array) -> void:
	if ops.is_empty():
		return
	if not session.presence.may_edit(id):
		session.status.emit("Someone is moving that", true)
		return
	session.sync.edit(C.batch(ops) if ops.size() > 1 else ops[0])


func _row(label: String, field: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 80
	h.add_child(l)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(field)
	return h


func _do_save_module() -> void:
	var kits := Modules.bus("kits")
	var n := _module_name.text.strip_edges()
	if n == "" or kits == null or not kits.has_method("save_room"):
		return
	var err := str(kits.call("save_room", session.model, _target, n, _module_group.text.strip_edges()))
	_save_module.hide()
	if err == "":
		session.status.emit("Saved \"%s\": it's in Add rooms > Saved modules" % n, false)
	else:
		session.status.emit(err, true)
