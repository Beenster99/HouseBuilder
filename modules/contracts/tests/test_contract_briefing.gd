extends ModuleTest
## The client's briefing document: every section a designer needs, the site's problems with
## what they mean for the design, a brief written for a real site picked without a contract,
## and where the document is shown (the Contracts wall screen, the designer's Contract window
## and its briefing window).
##   tools/run_tests.sh contracts

const SITE := "bath-hillside-garages"


func run_tests() -> void:
	_document()
	_for_site()
	await _site_picked()


func _document() -> void:
	var b := ContractGenerator.generate(5, "bungalow", 2)
	var t := ContractBriefing.text(b)
	var all_there := true
	for h: String in ["The client", "What to build", "Rooms", "Money and time", "The site", "Materials", "Bonus goals", "How it will be judged"]:
		if not t.contains("\n" + h + "\n"):
			all_there = false
	check(all_there, "the briefing has every section:\n%s" % t)
	check(t.contains(str(b.client)) and t.contains("bungalow") and t.contains("single storey"), "it says who the client is and what to build")
	check(t.contains("bedrooms, at least") and t.contains("m2 of rooms in all"), "with each room's size and the floor area")
	check(t.contains(ContractValidator.money(float(b.budget))) and t.contains(ContractValidator.money(float(b.fee)))
			and t.contains("%d days" % int(b.deadline_days)) and t.contains(ContractTiers.xp_text(int(b.xp))),
			"the budget, fee, deadline and XP")
	check(t.contains("Structure (walls, floors") and t.contains("brick and block"), "the materials")
	check(t.contains("1. ") and t.contains("Keep inside the plot boundary"), "and numbers the requirements it is judged on")
	var bb := ContractBriefing.bbcode(b, "777777")
	check(bb.begins_with("[font_size=") and bb.contains("[b]How it will be judged[/b]"), "as BBCode for the screens")
	check(ContractBriefing.story(ContractBrief.authored()[0]) != "", "a hand-written brief has a client paragraph too")


func _for_site() -> void:
	var pack := SitePool.open(SITE)
	check(pack != null and pack.ok(), "the test site reads")
	var b := ContractGenerator.for_site(SITE, 3, 2)
	check(bool(b.get("for_site", false)) and str(b.site.id) == SITE and str(b.id).begins_with("site-"), "a brief is written for a picked site")
	var kind := str(ContractGenerator.TYPES_SCRIPT.SITE_KIND.get(str(b.type), ""))
	check(kind in pack.suited_to() and int(b.tier) <= 2, "for a building the site suits and the firm's tier offers (%s)" % b.type)
	check(ContractGenerator.for_site(SITE, 3, 2) == b, "the same for the same seed")
	var t := ContractBriefing.text(b)
	var factors_ok := true
	for f: Dictionary in pack.factors():
		if not t.contains(str(f.label)):
			factors_ok = false
	check(factors_ok and t.contains("Site constraints and what they mean for the design") and t.contains("What it means for you: Step the floors"),
			"every site problem is listed with what it means for the design")
	check(t.contains(pack.title()) and t.contains("Access: no road") and t.contains("to demolish first"), "with the site's facts")
	check(ContractGenerator.for_site("no-such-site", 1, 1).is_empty(), "an unknown site gives no brief")
	check(ContractBriefing.site_advice("ground_wet").contains("Raise the ground floor"), "wet ground means a raised floor")


func _site_picked() -> void:
	var sites := Modules.bus("sites") as SitesBus
	var bus := ContractsBus.new()
	add_child(bus)
	bus.career.set_xp(1000)
	bus._deal_board(4)
	var design := FakeDesign.new()
	add_child(design)
	bus.hook_design(design)
	var pack := SitePool.open(SITE)
	bus._on_site_changed(pack)
	await frames(2)
	check(bool(bus.board[0].get("for_site", false)) and str(bus.board[0].site.id) == SITE and bus.board.size() == ContractsBus.BOARD_SIZE,
			"picking a site with no contract deals its brief to the top of the board")
	bus._on_site_changed(pack)
	await frames(2)
	check(bus.board.filter(func(o: Dictionary) -> bool: return bool(o.get("for_site", false))).size() == 1, "only once")
	# The wall screen shows its full brief, with Read on every offer.
	var board: Control = bus.make_board(null)
	add_child(board)
	await frames(2)
	sites._apply_load(SitesBus.pack_payload(SITE, SitePool.text_of(SITE)))
	bus._on_site_changed(sites.current())
	await frames(2)
	var doc := board.find_child("Briefing", true, false) as RichTextLabel
	check(doc != null and doc.get_parsed_text().contains("How it will be judged") and doc.get_parsed_text().contains(pack.title()),
			"the Contracts screen shows the site's full brief")
	var reads := board.find_children("Read", "Button", true, false)
	check(reads.size() == ContractsBus.BOARD_SIZE, "with a Read button on every offer")
	(reads[2] as Button).pressed.emit()
	await frames(2)
	check(doc.get_parsed_text().contains(str(bus.board[2].title)), "Read shows that offer's brief")
	# The designer's Contract window offers it.
	check(design.panels.has(ContractsBus.PANEL_ID), "the designer gets a Contract window for the site's brief")
	var panel: RichTextLabel = (design.panels[ContractsBus.PANEL_ID].make as Callable).call(null)
	add_child(panel)
	check(panel.get_parsed_text().contains("Brief for this site") and panel.get_parsed_text().contains("Read the full brief"), "offering it there")
	panel.open_briefing(bus.site_offer())
	var win := panel.find_child("BriefingWindow", true, false)
	check(win != null and (win.find_child("Briefing", true, false) as RichTextLabel).get_parsed_text().contains("What to build"),
			"Read opens the briefing document in a window")
	panel.meta_clicked.emit("accept")
	await frames(3)
	await get_tree().create_timer(0.4).timeout
	check(bool(bus.active.get("for_site", false)) and str(bus.briefing_pending) == "", "accepting it takes the contract and opens its brief once")
	check(panel.get_parsed_text().contains("Requirements") and panel.get_parsed_text().contains("Read the full brief"),
			"then the window checks the design against it, with the brief a click away")
	sites._apply_clear({})
	panel.queue_free()
	board.queue_free()
	bus.queue_free()
	design.queue_free()


class FakeDesign extends Node:
	var panels := {}
	var channels := {}
	func register_panel(id: String, title: String, make: Callable, order: int = 50) -> void:
		panels[id] = {"title": title, "make": make, "order": order}
	func unregister_panel(id: String) -> void:
		panels.erase(id)
	func register_channel(id: String, title: String, make: Callable, order: int = 50) -> void:
		channels[id] = {"title": title, "make": make, "order": order}
	func unregister_channel(id: String) -> void:
		channels.erase(id)
