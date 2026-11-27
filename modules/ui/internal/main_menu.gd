extends Control
## Main menu, over the splash picture: the game's name, then four sections down the left:
##   Single player   Continue (the latest save), New, Load, Delete, then the demos and tools
##                   other modules registered with Menu (grouped entries under their heading)
##   Online          the entries modules registered in the "Online" group (Host, Join)
##   Settings        Gameplay, Graphics (BSX's graphics screen) and Sound
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


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = BsxTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BsxTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var pic := TextureRect.new()
	pic.name = "Splash"
	pic.texture = load(Warmup.SPLASH_IMAGE)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(pic)
	# Darken the left side for the menu.
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
	var title := BsxTheme.title("FREDDIBNAH", 64)
	col.add_child(title)
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
		b.toggle_mode = true
		b.custom_minimum_size.y = 52
		main.add_child(b)
		_sections[id] = b
	main.add_child(_spacer(8))
	var exit := BsxTheme.button("Exit game", func() -> void: get_tree().quit())
	exit.name = "ExitGame"
	exit.custom_minimum_size.y = 52
	main.add_child(exit)

	entry_box = VBoxContainer.new()
	entry_box.name = "Choices"
	entry_box.custom_minimum_size = Vector2(340, 0)
	entry_box.add_theme_constant_override("separation", 12)
	row.add_child(entry_box)

	Menu.entries_changed.connect(_fill_entries)
	open_section(SINGLE)


func open_section(id: String) -> void:
	section = id
	for s: String in _sections:
		(_sections[s] as Button).set_pressed_no_signal(s == id)
	_fill_entries()


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
			cont.disabled = not playable
			entry_box.add_child(cont)
		var go := BsxTheme.button("New", func() -> void: _open_games("new"))
		go.name = "Start"
		go.disabled = not playable
		entry_box.add_child(go)
		var load_button := BsxTheme.button("Load", func() -> void: _open_games("load"))
		load_button.name = "LoadGame"
		load_button.disabled = games.is_empty() or not playable
		entry_box.add_child(load_button)
		var del := BsxTheme.button("Delete", func() -> void: _open_games("delete"))
		del.name = "DeleteGame"
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
			head.add_theme_color_override("font_color", Color(BsxTheme.ACCENT, 0.85))
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
	entry_box.add_child(gameplay)
	var graphics := BsxTheme.button("Graphics", _open_graphics)
	graphics.name = "Graphics"
	entry_box.add_child(graphics)
	var sound := BsxTheme.button("Sound", func() -> void: _open_settings(Menu.SOUND))
	sound.name = "Sound"
	entry_box.add_child(sound)
	var more := BsxTheme.button("More settings", func() -> void: Router.goto(UiBus.SETTINGS))
	more.name = "MoreSettings"
	entry_box.add_child(more)


func _entry_button(e: Dictionary) -> Button:
	var args: Dictionary = e.get("args", {})
	var b := BsxTheme.button(e.label, func(): Router.goto_loading(e.scene, args))
	b.name = e.id
	b.disabled = not Router.has_scene(e.scene)
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
		_fill_entries())
	add_child(panel)


## The graphics settings over the menu (the menu hides until it's closed), BSX's screen.
func _open_graphics() -> void:
	_center.visible = false
	var panel := GraphicsPanel.new()
	panel.name = "GraphicsPanel"
	panel.closed.connect(func() -> void: _center.visible = true)
	add_child(panel)


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
	var back := BsxTheme.button("Back", func() -> void:
		over.queue_free()
		_center.visible = true)
	back.name = "Back"
	box.add_child(back)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		var over := get_node_or_null("SettingsOverlay")
		if over:
			over.queue_free()
			_center.visible = true
			get_viewport().set_input_as_handled()


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c
