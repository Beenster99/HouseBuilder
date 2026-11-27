extends ModuleTest
## Screens in the world keep the Classic look while the game's own UI is pencil:
## on_screen, col / palette_for, as_screen, screen_theme and the *_for styles.
##   tools/run_tests.sh ui


func run_tests() -> void:
	var was := BsxTheme.pencil()
	BsxTheme.set_pencil(true)
	var screen := Control.new()
	screen.set_meta(BsxTheme.SCREEN_META, true)
	var inner := Label.new()
	screen.add_child(inner)
	var plain := Control.new()
	add_child(screen)
	add_child(plain)
	check(BsxTheme.on_screen(inner) and not BsxTheme.on_screen(plain), "a screen's children are on the screen")
	check(BsxTheme.col(inner, "TEXT") == BsxTheme.CLASSIC_COLOURS.TEXT, "on a screen, Classic colours")
	check(BsxTheme.col(plain, "TEXT") == BsxTheme.PENCIL_COLOURS.TEXT, "elsewhere, the pencil colours")
	check(TerminalKit.col(inner, "PLATE") == TerminalKit.CLASSIC_COLOURS.PLATE
			and TerminalKit.col(plain, "PLATE") == TerminalKit.PENCIL_COLOURS.PLATE, "the terminal kit's colours too")

	var inside: Array = BsxTheme.as_screen(func() -> Array:
		return [BsxTheme.pencil(), BsxTheme.TEXT, TerminalKit.PLATE, BsxTheme.panel_style() is StyleBoxFlat])
	check(not bool(inside[0]) and inside[1] == BsxTheme.CLASSIC_COLOURS.TEXT
			and inside[2] == TerminalKit.CLASSIC_COLOURS.PLATE and bool(inside[3]), "as_screen builds in Classic")
	check(BsxTheme.pencil() and BsxTheme.TEXT == BsxTheme.PENCIL_COLOURS.TEXT
			and TerminalKit.PLATE == TerminalKit.PENCIL_COLOURS.PLATE, "and puts pencil back after")
	check(BsxTheme.get_theme().default_font == BsxTheme.font("body"), "the pencil theme is untouched")

	check(BsxTheme.panel_style_for(inner) is StyleBoxFlat and not (BsxTheme.panel_style_for(plain) is StyleBoxFlat),
			"panel_style_for: flat Classic on a screen, pencil elsewhere")
	check(BsxTheme.card_style_for(inner) is StyleBoxFlat, "card_style_for too")

	var t := BsxTheme.screen_theme()
	check(t.has_stylebox("normal", "Button") and t.has_stylebox("panel", "PopupMenu") and t.has_stylebox("grabber_area", "HSlider"),
			"the screen theme covers every control")
	check(not (t.get_stylebox("normal", "Button") is PencilBox), "with no pencil in it")
	check(t.get_color("font_color", "Label") == BsxTheme.CLASSIC_COLOURS.TEXT, "labels in Classic text")
	screen.queue_free()
	plain.queue_free()
	BsxTheme.set_pencil(was)
	await frames(1)
