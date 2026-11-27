extends Node3D
## Our work: the map of everything the firm has built and the list of its buildings. Pick
## one and Visit takes the whole crew on this screen to its site, where it still stands with
## the firm's other work around it (TownVisit). Esc there, or Back to the map, comes back.
## Opened from the main menu's "Our work" (flag town.map).

const ListScript := preload("res://modules/town/internal/town_list.gd")
const MapScript := preload("res://modules/town/internal/town_map.gd")
const VisitScript := preload("res://modules/town/internal/town_visit.gd")

var bus: TownBus
var visit_view: Node3D
var help: HelpBar
var list: Control
var map: Control
var selected := ""
var _map_layer: CanvasLayer
var _visit_layer: CanvasLayer
var _detail: RichTextLabel
var _visit_button: Button
var _visit_title: Label
var _visit_info: Label
var _who: Label
var _backdrop: ColorRect


func _ready() -> void:
	bus = Modules.bus("town") as TownBus
	name = "TownScreen"
	_build_map_ui()
	_build_visit_ui()
	help = HelpBar.new()
	add_child(help)
	bus.visit_changed.connect(_follow_visit)
	bus.records_changed.connect(_on_records)
	bus.here_changed.connect(_show_who)
	bus.set_here(true)
	var recs := bus.records()
	if not recs.is_empty():
		pick(str(recs[recs.size() - 1].id))
	_follow_visit()
	_show_who()


func _exit_tree() -> void:
	if bus:
		for pair: Array in [[bus.visit_changed, _follow_visit], [bus.records_changed, _on_records], [bus.here_changed, _show_who]]:
			if (pair[0] as Signal).is_connected(pair[1]):
				(pair[0] as Signal).disconnect(pair[1])
		bus.set_here(false)


func _build_map_ui() -> void:
	_map_layer = CanvasLayer.new()
	_map_layer.name = "MapLayer"
	add_child(_map_layer)
	_backdrop = BsxTheme.paper_backdrop(true)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_layer.add_child(_backdrop)
	var side := PanelContainer.new()
	side.name = "Side"
	side.add_theme_stylebox_override("panel", BsxTheme.panel_style(14))
	side.anchor_bottom = 1.0
	side.offset_left = 16
	side.offset_top = 16
	side.offset_right = 456
	side.offset_bottom = -52
	_map_layer.add_child(side)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	side.add_child(box)
	box.add_child(BsxTheme.title("OUR WORK", 30))
	list = ListScript.new()
	list.name = "List"
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(400, 200)
	box.add_child(list)
	list.call("bind", bus)
	list.connect("picked", pick)
	box.add_child(BsxTheme.rule())
	_detail = RichTextLabel.new()
	_detail.name = "Detail"
	_detail.bbcode_enabled = true
	_detail.fit_content = true
	_detail.scroll_active = false
	_detail.custom_minimum_size = Vector2(400, 0)
	_detail.add_theme_font_size_override("normal_font_size", 14)
	_detail.add_theme_font_size_override("bold_font_size", 15)
	box.add_child(_detail)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	_visit_button = BsxTheme.button("Visit with the crew", func() -> void:
		if selected != "":
			bus.visit(selected))
	_visit_button.name = "Visit"
	_visit_button.tooltip_text = "Go to the building's site, with everyone on this screen"
	buttons.add_child(_visit_button)
	var back := BsxTheme.button("Main menu", func() -> void: Router.goto("main_menu"))
	back.tooltip_text = "Back to the main menu"
	buttons.add_child(back)
	map = MapScript.new()
	map.name = "Map"
	map.anchor_right = 1.0
	map.anchor_bottom = 1.0
	map.offset_left = 476
	map.offset_top = 16
	map.offset_right = -16
	map.offset_bottom = -52
	_map_layer.add_child(map)
	map.call("bind", bus)
	map.connect("picked", pick)
	_who = BsxTheme.hud_label("", 14)
	_who.anchor_left = 1.0
	_who.anchor_right = 1.0
	_who.offset_left = -420
	_who.offset_right = -24
	_who.offset_top = 20
	_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_map_layer.add_child(_who)


func _build_visit_ui() -> void:
	_visit_layer = CanvasLayer.new()
	_visit_layer.name = "VisitLayer"
	_visit_layer.visible = false
	add_child(_visit_layer)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", BsxTheme.panel_style(14))
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(380, 0)
	_visit_layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_visit_title = BsxTheme.hud_label("", 22)
	box.add_child(_visit_title)
	_visit_info = BsxTheme.hud_label("", 14)
	_visit_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_visit_info.custom_minimum_size = Vector2(360, 0)
	box.add_child(_visit_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var back := BsxTheme.button("Back to the map", func() -> void: bus.leave())
	back.name = "BackToMap"
	back.tooltip_text = "Everyone goes back to the map of the firm's work"
	row.add_child(back)
	var walk := BsxTheme.button("Walk (F)", func() -> void:
		if visit_view:
			visit_view.call("set_mode", "walk" if str(visit_view.get("mode")) == "orbit" else "orbit"))
	walk.tooltip_text = "Walk about at full size, or back to orbiting"
	row.add_child(walk)
	var inside := BsxTheme.button("Walk inside (I)", func() -> void:
		if visit_view:
			visit_view.call("walk_inside"))
	inside.name = "WalkInside"
	inside.tooltip_text = "Walk round inside the nearest building (look only: nothing can change)"
	row.add_child(inside)


func _on_records() -> void:
	if selected == "" or bus.record(selected).is_empty():
		var recs := bus.records()
		selected = ""
		if not recs.is_empty():
			pick(str(recs[recs.size() - 1].id))
			return
	_show_detail()


func pick(rid: String) -> void:
	selected = rid
	list.call("select", rid)
	map.call("select", rid)
	_show_detail()


func _show_detail() -> void:
	var r := bus.record(selected)
	_visit_button.disabled = r.is_empty()
	if r.is_empty():
		_detail.text = "[b]No buildings yet[/b]\nFinish a contract and hand it over: it stays standing on its site, and shows up here and on the map."
		return
	var lines := PackedStringArray(["[b]%s[/b]" % str(r.title)])
	if str(r.get("client", "")) != "":
		lines.append("Client: %s" % str(r.client))
	lines.append("Site: %s" % (str(r.site_name) if str(r.get("site_name", "")) != "" else "the firm's yard (no real site)"))
	lines.append("Handed over %s after %d days." % [TownRecord.date_text(int(r.handed_over)), int(r.days)])
	lines.append("Fee %s, cost %s, profit %s." % [TownRecord.money(float(r.fee)), TownRecord.money(float(r.cost)), TownRecord.money(float(r.profit))])
	var sz: Array = r.get("size", [0, 0, 0])
	lines.append("%d parts, %.0f × %.0f m, %.0f m high." % [int(r.parts), float(sz[0]), float(sz[1]), float(sz[2])])
	var crew: Array = r.get("crew", [])
	if not crew.is_empty():
		lines.append("Crew: %s" % ", ".join(PackedStringArray(crew)))
	var nearby := 0
	if str(r.site_id) != "":
		nearby = bus.on_site(str(r.site_id)).size() - 1
	if nearby > 0:
		lines.append("%d more of the firm's buildings on this site." % nearby)
	if bus.being_redeveloped() == str(r.id):
		lines.append("[color=#b05a00]Being redeveloped: the crew's contract brings it down.[/color]")
	if bool(r.get("demolished", false)):
		lines.append("Demolished %s." % TownRecord.date_text(int(r.demolished_at)))
	_detail.text = "\n".join(lines)


func _show_who() -> void:
	var names := PackedStringArray()
	for peer: int in bus.here:
		names.append(str(bus.here[peer].get("name", "Player")))
	_who.text = ("Here: " + ", ".join(names)) if names.size() > 1 else ""


## The crew's visit: build the site view for it, or come back to the map.
func _follow_visit() -> void:
	var rid := bus.visiting
	if visit_view != null and str(visit_view.get("record").get("id", "")) == rid:
		return
	if visit_view != null:
		visit_view.queue_free()
		remove_child(visit_view)
		visit_view = null
	var rec := bus.record(rid)
	if rid == "" or rec.is_empty() or not bus.has_model(rid):
		_map_layer.visible = true
		_visit_layer.visible = false
		return
	visit_view = VisitScript.new()
	add_child(visit_view)
	visit_view.call("setup", bus, rid)
	_map_layer.visible = false
	_visit_layer.visible = true
	_visit_title.text = str(rec.title).to_upper()
	_visit_info.text = TownRecord.plaque_text(rec).get_slice("\n", 1) + "\n" + TownRecord.summary_text(rec)
	if visit_view.get("pack") == null and str(rec.site_id) != "":
		_visit_info.text += "\n(The site could not be drawn here, so it stands in the yard.)"


func _process(_delta: float) -> void:
	if visit_view != null and bool(visit_view.call("is_walking_inside")):
		_visit_layer.visible = false
		help.visible = false
		return
	help.visible = true
	if visit_view != null:
		_visit_layer.visible = true
		var h: Array = visit_view.call("help_text")
		help.set_help(str(h[0]), str(h[1]))
	else:
		help.set_help("OUR WORK", HelpBar.keys_text([["Click", "pick a building on the list or a pin on the map"],
				["Visit", "go and see it with the crew"], ["Esc", "main menu"]]))


func _unhandled_input(event: InputEvent) -> void:
	if visit_view == null and event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		Router.goto("main_menu")
		get_viewport().set_input_as_handled()
