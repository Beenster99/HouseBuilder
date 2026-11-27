extends Control
## Main menu, over the splash picture: the game's name, then four sections down the left:
##   Single player   Continue (the latest save), New, Load, Delete, then the demos and tools
##                   other modules registered with Menu (grouped entries under their heading)
##   Online          the entries modules registered in the "Online" group (Host, Join)
##   Settings        Gameplay, Graphics and Sound
##   Exit game
## Picking a section lists its choices beside it. New, Load and Delete open the games panel
## over the menu; Settings pages open over it too, and the menu comes back when they close.

const SINGLE := "single"
const ONLINE := "online"
const SETTINGS := "settings"
## Menu entries in this group go under Online; the rest under Single player.
const ONLINE_GROUP := "Online"

## The open section's choices (Single player's on first show).
var entry_box: VBoxContainer
var section := SINGLE
var _center: Control
var _sections: Dictionary = {}  # id -> Button
## The help line along the bottom, as on every screen.
var help: HelpBar

const SECTION_TIPS := {
	SINGLE: "Play on your own: carry on, start a new firm, or load or delete a saved one",
	ONLINE: "Play with up to two friends: host a game, or join one",
	SETTINGS: "Gameplay, graphics and sound",
}
## The section open last, so the menu comes back on it when it's rebuilt (a menu style switch).
static var _last_section := ""


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = BsxTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# The splash picture drawn over in pencil, fading to plain paper under the menu, on
	# drawing paper with a faint grid.
	add_child(BsxTheme.paper_backdrop())
	var pic := BsxTheme.pencil_picture(load(Warmup.SPLASH_IMAGE), Vector2(0.38, 0.62))
	pic.name = "Splash"
	add_child(pic)
	if BsxTheme.pencil():
		var grid := BsxTheme.paper_backdrop()
		grid.name = "Grid"
		(grid.material as ShaderMaterial).set_shader_parameter("paper", Color(BsxTheme.PAPER, 0.0))
		add_child(grid)
	else:
		# Classic: darken the left side for the menu.
		var shade := TextureRect.new()
		var grad := GradientTexture2D.new()
		grad.gradient = Gradient.new()
		grad.gradient.set_color(0, Color(BsxTheme.BG, 0.94))
		grad.gradient.set_color(1, Color(BsxTheme.BG, 0.0))
		grad.fill_from = Vector2(0.35, 0)
		grad.fill_to = Vector2(0.85, 0)
		shade.texture = grad
		shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(shade)

	_center = MarginContainer.new()
	_center.name = "Menu"
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		_center.add_theme_constant_override("margin_" + side, 72 if side == "left" else 64)
	add_child(_center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_center.add_child(col)
	var title := BsxTheme.title("FredDibnah", 76)
	col.add_child(title)
	var rule := BsxTheme.rule(10.0)
	rule.custom_minimum_size.x = 460
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(rule)
	var sub := BsxTheme.muted("design it together, build it, bring it down  -  version %s" % BuildInfo.label().trim_prefix("v"))
	sub.name = "Version"
	col.add_child(sub)
	col.add_child(_spacer(36))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	col.add_child(row)
	var main := VBoxContainer.new()
	main.name = "Sections"
	main.custom_minimum_size = Vector2(300, 0)
	main.add_theme_constant_override("separation", 12)
	row.add_child(main)
	for s: Array in [[SINGLE, "Single player", "SinglePlayer"], [ONLINE, "Online", "Online"],
			[SETTINGS, "Settings", "Settings"]]:
		var id: String = s[0]
		var b := BsxTheme.button(str(s[1]), func() -> void: open_section(id))
		b.name = str(s[2])
		b.tooltip_text = SECTION_TIPS[id]
		b.toggle_mode = true
		b.custom_minimum_size.y = 52
		main.add_child(b)
		_sections[id] = b
	main.add_child(_spacer(8))
	var exit := BsxTheme.button("Exit game", func() -> void: Modules.quit_game())
	exit.name = "ExitGame"
	exit.tooltip_text = "Close the game"
	exit.custom_minimum_size.y = 52
	main.add_child(exit)

	entry_box = VBoxContainer.new()
	entry_box.name = "Choices"
	entry_box.custom_minimum_size = Vector2(340, 0)
	entry_box.add_theme_constant_override("separation", 12)
	row.add_child(entry_box)

	help = HelpBar.new()
	add_child(help)
	Menu.entries_changed.connect(_fill_entries)
	open_section(_last_section if _last_section != "" else SINGLE)
	_last_section = ""


func open_section(id: String) -> void:
	section = id
	for s: String in _sections:
		(_sections[s] as Button).set_pressed_no_signal(s == id)
	_fill_entries()
	_menu_help()


func _menu_help() -> void:
	var heads := {SINGLE: "SINGLE PLAYER", ONLINE: "ONLINE", SETTINGS: "SETTINGS"}
	help.set_help("MAIN MENU: " + str(heads.get(section, "")),
			HelpBar.keys_text([["click", "pick a section, then a choice beside it"]]))


func _fill_entries() -> void:
	for child in entry_box.get_children():
		entry_box.remove_child(child)  # now, so the new buttons can take the same names
		child.queue_free()
	match section:
		SINGLE:
			_fill_single()
		ONLINE:
			_fill_online()
		SETTINGS:
			_fill_settings()


func _fill_single() -> void:
	var start := Menu.start()
	if not start.is_empty():
		var playable := Router.has_scene(start.scene)
		var games := Saves.games()
		if not games.is_empty():
			var latest: Dictionary = games[0]
			var cont := BsxTheme.button("Continue  -  %s" % latest.name, func() -> void: _continue(latest.slot))
			cont.name = "Continue"
			cont.tooltip_text = "Carry on with your latest game"
			cont.disabled = not playable
			entry_box.add_child(cont)
		var go := BsxTheme.button("New", func() -> void: _open_games("new"))
		go.name = "Start"
		go.tooltip_text = "Start a new firm in a new save slot"
		go.disabled = not playable
		entry_box.add_child(go)
		var load_button := BsxTheme.button("Load", func() -> void: _open_games("load"))
		load_button.name = "LoadGame"
		load_button.tooltip_text = "Pick a saved game to play"
		load_button.disabled = games.is_empty() or not playable
		entry_box.add_child(load_button)
		var del := BsxTheme.button("Delete", func() -> void: _open_games("delete"))
		del.name = "DeleteGame"
		del.tooltip_text = "Pick a saved game to delete"
		del.disabled = games.is_empty()
		entry_box.add_child(del)
	var shown := 0
	var headed := {}
	for e in Menu.entries():
		if str(e.get("group", "")) == ONLINE_GROUP:
			continue
		if not start.is_empty() and e.scene == start.scene:
			continue  # New already goes there
		var group: String = e.get("group", "")
		if group == "":
			group = "Demos and tools"
		if not headed.has(group):
			headed[group] = true
			entry_box.add_child(_spacer(4))
			var head := BsxTheme.muted(group)
			head.name = "Group_" + group.validate_node_name()
			head.add_theme_color_override("font_color", BsxTheme.ACCENT)
			head.add_theme_font_override("font", BsxTheme.font("display"))
			entry_box.add_child(head)
		entry_box.add_child(_entry_button(e))
		shown += 1
	if start.is_empty() and shown == 0:
		var none := BsxTheme.muted("Nothing to play yet in this build.")
		entry_box.add_child(none)


func _fill_online() -> void:
	var any := false
	for e in Menu.entries():
		if str(e.get("group", "")) == ONLINE_GROUP:
			entry_box.add_child(_entry_button(e))
			any = true
	if not any:
		entry_box.add_child(BsxTheme.muted("Online play isn't in this build."))


func _fill_settings() -> void:
	var gameplay := BsxTheme.button("Gameplay", func() -> void: _open_settings(Menu.GAMEPLAY))
	gameplay.name = "Gameplay"
	gameplay.tooltip_text = "Your name, controls and how the game plays"
	entry_box.add_child(gameplay)
	var graphics := BsxTheme.button("Graphics", _open_graphics)
	graphics.name = "Graphics"
	graphics.tooltip_text = "Look (architectural model or realistic), display and quality"
	entry_box.add_child(graphics)
	var sound := BsxTheme.button("Sound", func() -> void: _open_settings(Menu.SOUND))
	sound.name = "Sound"
	sound.tooltip_text = "Volumes"
	entry_box.add_child(sound)
	var style := BsxTheme.button("Menu style:  %s" % BsxTheme.style_setting(), func() -> void:
		_last_section = SETTINGS
		Settings.set_value(BsxTheme.STYLE_SECTION, BsxTheme.STYLE_KEY,
				BsxTheme.CLASSIC if BsxTheme.style_setting() == BsxTheme.PENCIL else BsxTheme.PENCIL)
		Settings.save())
	style.name = "MenuStyle"
	entry_box.add_child(style)
	var more := BsxTheme.button("More settings", func() -> void: Router.goto(UiBus.SETTINGS))
	more.name = "MoreSettings"
	more.tooltip_text = "Every setting, on its own screen"
	entry_box.add_child(more)


func _entry_button(e: Dictionary) -> Button:
	var args: Dictionary = e.get("args", {})
	var b := BsxTheme.button(e.label, func(): Router.goto_loading(e.scene, args))
	b.name = e.id
	b.disabled = not Router.has_scene(e.scene)
	b.tooltip_text = str(e.get("hint", ""))
	return b


func _continue(slot: String) -> void:
	var start := Menu.start()
	if Saves.continue_game(slot) == OK:
		Router.goto_loading(start.scene, start.args)


## The games panel over the menu, set up for New, Load or Delete.
func _open_games(mode: String) -> void:
	_center.visible = false
	var panel := GamesPanel.new()
	panel.name = "GamesPanel"
	panel.mode = mode
	panel.closed.connect(func() -> void:
		_center.visible = true
		_fill_entries()
		_menu_help())
	add_child(panel)
	var what := {"new": "NEW GAME", "load": "LOAD", "delete": "DELETE"}
	help.set_help(str(what.get(mode, "GAMES")), HelpBar.keys_text([["click", "pick a game"], ["Esc", "back"]]))


## The graphics settings over the menu (the menu hides until it's closed).
func _open_graphics() -> void:
	_center.visible = false
	var panel := GraphicsPanel.new()
	panel.name = "GraphicsPanel"
	panel.closed.connect(func() -> void:
		_center.visible = true
		_menu_help())
	add_child(panel)
	help.set_help("GRAPHICS", HelpBar.keys_text([["click", "change a setting"], ["Esc", "back"]]))


## Gameplay or Sound: that tab of the in-game settings, over the menu, with Back.
func _open_settings(tab: String) -> void:
	_center.visible = false
	var over := PanelContainer.new()
	over.name = "SettingsOverlay"
	over.add_theme_stylebox_override("panel", BsxTheme.panel_style(24))
	over.set_anchors_preset(Control.PRESET_CENTER)
	over.custom_minimum_size = Vector2(900, 560)
	add_child(over)
	over.position = (size - over.custom_minimum_size) * 0.5
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	over.add_child(box)
	var tabs := SettingsTabs.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	tabs.open_tab(tab)
	help.set_help(tab.to_upper(), HelpBar.keys_text([["click", "change a setting"], ["Esc", "back"]]))
	var back := BsxTheme.button("Back", func() -> void:
		over.queue_free()
		_center.visible = true
		_menu_help())
	back.name = "Back"
	box.add_child(back)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		var over := get_node_or_null("SettingsOverlay")
		if over:
			over.queue_free()
			_center.visible = true
			_menu_help()
			get_viewport().set_input_as_handled()


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c
