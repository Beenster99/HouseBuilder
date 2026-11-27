extends ModuleTest
## The help bar along the bottom of every screen: context text, control tooltips, world
## hovers that lapse, passing messages, insets, and keys formatting.
##   tools/run_tests.sh ui


func run_tests() -> void:
	var bar := HelpBar.new()
	add_child(bar)
	await frames(1)
	bar.set_help("TIMELAPSE", HelpBar.keys_text([["Space", "play / pause"], ["Esc", "back"]]))
	await frames(2)
	var shown := bar.shown()
	check(shown[0].contains("TIMELAPSE") and shown[0].contains("Space") and shown[0].contains("play / pause"),
			"the help side shows the head and the keys: %s" % shown[0])
	check(shown[1] == "", "nothing on the tip side at first")
	var panel := bar.get_node("Bar") as Control
	var vp := get_viewport().get_visible_rect().size
	check(absf(panel.position.y + panel.size.y - (vp.y - HelpBar.MARGIN)) < 2.0, "the bar sits along the bottom")
	check(panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the bar never takes a click")

	bar.hover("Kitchen · room · 12.4 m²")
	await frames(1)
	check(bar.shown()[1].contains("Kitchen"), "a world hover shows on the tip side")
	await frames(3)
	check(bar.shown()[1] == "", "a world hover lapses when it isn't repeated")

	bar.say("Can't put a door there", true)
	await frames(1)
	check(bar.shown()[1].contains("door") and bar.shown()[1].contains(BsxTheme.WARN.to_html(false)),
			"a warning shows in the warning colour")
	bar._said_until = 0.0
	await frames(1)
	check(bar.shown()[1] == "", "a message goes after its time")

	bar.set_insets(300, 200)
	await frames(2)
	check(is_equal_approx(panel.position.x, 300.0) and absf(panel.size.x - maxf(vp.x - 500.0, 200.0)) < 1.0,
			"insets keep the bar between side docks: x %.0f, width %.0f of %.0f" % [panel.position.x, panel.size.x, vp.x])
	check(HelpBar.keys_text([["F", "fire"]]).contains("[b]F[/b]"), "keys are bold")
	bar.queue_free()
	await frames(1)
