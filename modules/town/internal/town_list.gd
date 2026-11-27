extends VBoxContainer
## The firm's finished buildings as a list: a plan sketch of each, its client, where, when it
## was handed over, its cost and profit. Used on the Our work screen (click to pick one) and
## as the design hall's "Our work" wall-screen page. Keeps itself up to date.

signal picked(record_id: String)

const THUMB := Vector2(84, 64)

var bus: TownBus
var selected := ""
var _head: Label
var _rows: VBoxContainer
var _cards: Dictionary = {}


class PlanThumb:
	extends Control
	## The ground floor in brief (TownRecord plan): rooms shaded, walls inked.
	var plan: Dictionary = {}
	var size_m := Vector2.ONE

	func _draw() -> void:
		var walls: Array = plan.get("walls", [])
		var rooms: Array = plan.get("rooms", [])
		var r := Rect2()
		var first := true
		for w: Array in walls:
			for p: Vector2 in [Vector2(w[0], w[1]), Vector2(w[2], w[3])]:
				r = Rect2(p, Vector2.ZERO) if first else r.expand(p)
				first = false
		for o: Array in rooms:
			for pt: Array in o:
				var p := Vector2(float(pt[0]), float(pt[1]))
				r = Rect2(p, Vector2.ZERO) if first else r.expand(p)
				first = false
		var ink := BsxTheme.col(self, "TEXT")
		draw_rect(Rect2(Vector2.ZERO, size), Color(ink, 0.05))
		if first:
			# No plan: a box the building's size.
			r = Rect2(Vector2.ZERO, size_m)
		var s := minf((size.x - 10.0) / maxf(r.size.x, 1.0), (size.y - 10.0) / maxf(r.size.y, 1.0))
		var off := (size - r.size * s) * 0.5 - r.position * s
		if first:
			draw_rect(Rect2(off, r.size * s), ink, false, 1.5)
			return
		for o: Array in rooms:
			var pts := PackedVector2Array()
			for pt: Array in o:
				pts.append(Vector2(float(pt[0]), float(pt[1])) * s + off)
			if pts.size() >= 3:
				draw_colored_polygon(pts, Color(ink, 0.12))
		for w: Array in walls:
			draw_line(Vector2(w[0], w[1]) * s + off, Vector2(w[2], w[3]) * s + off, ink, 1.6)


func bind(town: TownBus) -> void:
	bus = town
	add_theme_constant_override("separation", 6)
	_head = Label.new()
	_head.name = "Head"
	_head.add_theme_font_size_override("font_size", 15)
	_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_head)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	scroll.add_child(_rows)
	bus.records_changed.connect(refresh)
	refresh()


func _exit_tree() -> void:
	if bus and bus.records_changed.is_connected(refresh):
		bus.records_changed.disconnect(refresh)


func card_count() -> int:
	return _cards.size()


func refresh() -> void:
	if _rows == null:
		return
	for c in _rows.get_children():
		c.queue_free()
	_cards.clear()
	var recs := bus.records()
	var profit := 0.0
	var standing := 0
	for r: Dictionary in recs:
		profit += float(r.get("profit", 0.0))
		if not bool(r.get("demolished", false)):
			standing += 1
	if recs.is_empty():
		_head.text = "Nothing handed over yet. Every contract the crew passes stays standing here, on its site."
		return
	_head.text = "%d building%s handed over, %d standing. Total profit %s." % [recs.size(), "" if recs.size() == 1 else "s",
			standing, TownRecord.money(profit)]
	var list := recs.duplicate()
	list.reverse()  # newest first
	for r: Dictionary in list:
		var card := _card(r)
		_rows.add_child(card)
		_cards[str(r.id)] = card
	select(selected)


func select(rid: String) -> void:
	selected = rid
	for id: String in _cards:
		var card: PanelContainer = _cards[id]
		card.add_theme_stylebox_override("panel", BsxTheme.slot_style(id == rid))


func _card(r: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Card_" + str(r.id)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.tooltip_text = "Click to pick %s, then Visit to go and see it" % str(r.title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	var thumb := PlanThumb.new()
	thumb.custom_minimum_size = THUMB
	thumb.plan = r.get("plan", {})
	var sz: Array = r.get("size", [10.0, 10.0, 3.0])
	thumb.size_m = Vector2(float(sz[0]), float(sz[1]))
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(thumb)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var title := Label.new()
	title.text = str(r.title) + ("  (demolished)" if bool(r.get("demolished", false)) else "")
	title.add_theme_font_size_override("font_size", 16)
	text.add_child(title)
	for line: String in ["For %s" % str(r.client) if str(r.get("client", "")) != "" else "",
			TownRecord.summary_text(r)]:
		if line == "":
			continue
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_child(l)
	var rid := str(r.id)
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			select(rid)
			picked.emit(rid))
	return card
