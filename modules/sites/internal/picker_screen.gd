extends Control
## The Real sites list: every pool site with its preview, difficulty, what it suits and the
## curator's description. Picking one opens the site viewer and loads it for the crew.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = BsxTheme.get_theme()
	var bg := ColorRect.new()
	bg.color = BsxTheme.col(self, "BG")  # paper in the pencil look, dark in the classic one
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var col := VBoxContainer.new()
	margin.add_child(col)
	col.add_child(BsxTheme.title("Real sites", 40))
	col.add_child(BsxTheme.muted("Real plots from OpenStreetMap. © OpenStreetMap contributors."))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	for s: Dictionary in SitePool.list():
		list.add_child(_row(s))
	col.add_child(BsxTheme.button("Back", func() -> void: Router.goto("main_menu")))


func _row(s: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	if str(s.preview) != "":
		var img := Image.load_from_file(ProjectSettings.globalize_path(s.preview))
		if img:
			img.resize(160, 160)
			var tex := TextureRect.new()
			tex.texture = ImageTexture.create_from_image(img)
			tex.custom_minimum_size = Vector2(160, 160)
			row.add_child(tex)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(BsxTheme.hud_label("%s   difficulty %d/5" % [s.name, s.rating], 22))
	var suits := ", ".join(PackedStringArray(s.suited_to)).replace("_", " ")
	var desc := BsxTheme.muted("%s\nSuits: %s. Ground: %s. Suggested cost x%.2f." % [s.description, suits,
			str(s.soil).replace("_", " "), float(s.cost_multiplier_hint)])
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc)
	var site_id: String = s.id
	info.add_child(BsxTheme.button("Visit this site", func() -> void:
		Router.goto(SitesBus.VIEW_SCENE, {"id": site_id})))
	return row
