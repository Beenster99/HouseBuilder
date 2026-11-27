extends ModuleTest
## Briefs with a building already on the plot: locked parts in the building model refuse
## edits; the extension and keep-the-frontage twists put one on the plot, accepting the job
## starts the design from it, and keep_existing checks it is still there as it was.
##   tools/run_tests.sh contracts

const C := preload("res://modules/building/api/building_commands.gd")


func run_tests() -> void:
	var saved := Flags.all()
	_locked_model()
	_twists()
	_accept()
	Flags.use(saved)


func _locked_model() -> void:
	var m := BuildingModel.new()
	var w := str(m.apply(C.place_part("wall_loadbearing", 0, {"a": [0, 0, 0], "b": [6, 0, 0], "locked": true}, "masonry")).do.entry.id)
	var free := str(m.apply(C.place_part("wall_loadbearing", 0, {"a": [6, 0, 0], "b": [6, 0, 5]}, "masonry")).do.entry.id)
	check(m.is_locked(w) and not m.is_locked(free) and m.locked_ids() == PackedStringArray([w]), "a part can be locked")
	check(m.apply(C.move([w], Vector3(1, 0, 0))).is_empty(), "a locked wall will not move")
	check(m.apply(C.set_fields(w, {"height": 4.0})).is_empty() and m.apply(C.retag(w, "wall_partition")).is_empty(), "or change")
	check(m.apply(C.delete([w])).is_empty() and m.apply(C.delete([w, free])).is_empty(), "or go, even in a group")
	check(m.apply(C.place_opening("window_medium", w, 3.0)).is_empty(), "and takes no new openings")
	check(not m.apply(C.move([free], Vector3(0, 0, 1))).is_empty(), "the other wall still moves")
	var room := m.apply(C.place_room("kitchen", 0, C.rect(0, 0, 3, 3)))
	var rid := str(room.do.entry.id)
	check(not m.apply(C.set_fields(rid, {"locked": true})).is_empty() and m.is_locked(rid), "setting locked alone locks an entry")
	check(m.apply(C.retag(rid, "bedroom")).is_empty(), "a locked room keeps its type")
	check(not m.apply(C.set_fields(rid, {"locked": null})).is_empty() and not m.apply(C.retag(rid, "bedroom")).is_empty(), "and unlocking frees it")
	var copy := BuildingModel.from_data(JSON.parse_string(JSON.stringify(m.to_data())))
	check(copy.is_locked(w), "locks save and load")


func _twists() -> void:
	var house := ContractGenerator.generate(31, "detached_house", 3)
	var ext := ContractTwists.apply(house, 3, ["extension"])
	check("extension" in ext.twists and not (ext.existing as Array).is_empty(), "an extension brief has a house on the plot")
	check(ContractTwists.apply(ContractGenerator.generate(31, "primary_school", 3), 3, ["extension"]).twists.is_empty(), "but not for a school")
	var start := BuildingModel.from_data(ContractTwists.starting_design(ext))
	check(start.locked_ids().size() == (ext.existing as Array).size() and start.rooms.size() == 2, "the design starts from the whole locked house with its two rooms")
	var a := ContractValidator.assess(ext, start)
	var keep := _item(a, "keep_existing")
	check(bool(keep.get("ok", false)) and str(keep.label).contains("existing house"), "keeping it passes: %s" % keep.get("detail", ""))
	var within := _item(a, "within_plot")
	check(bool(within.get("ok", false)), "and it stands inside the plot")
	var wire: Dictionary = JSON.parse_string(JSON.stringify(ext))
	check(bool(_item(ContractValidator.assess(wire, start), "keep_existing").get("ok", false)), "the check survives a save (JSON numbers)")
	var wall := ""
	for id in start.locked_ids():
		if str(start.entry(id).get("kind", "")) == "wall_loadbearing":
			wall = id
			break
	start.apply(C.set_fields(wall, {"locked": null}))
	start.apply(C.delete([wall]))
	var broken := _item(ContractValidator.assess(ext, start), "keep_existing")
	check(not bool(broken.get("ok", true)) and str(broken.detail).contains("changed"), "unlocking a wall to knock it down fails it: %s" % broken.get("detail", ""))
	check(ContractBriefing.text(ext).contains("Keep the existing house as it is"), "the briefing judges it")
	var shop := ContractGenerator.generate(32, "high_street_shop", 4) if ContractGenerator.TYPES.has("high_street_shop") else {}
	if shop.is_empty():
		for t: String in ContractGenerator.TYPES:
			if str(ContractGenerator.TYPES[t].category) == "retail":
				shop = ContractGenerator.generate(32, t, 4)
				break
	var front := ContractTwists.apply(shop, 4, ["keep_frontage"])
	check("keep_frontage" in front.twists, "a shop can keep its old frontage")
	var fm := BuildingModel.from_data(ContractTwists.starting_design(front))
	check(fm.parts_of_family("wall").size() == 1 and bool(_item(ContractValidator.assess(front, fm), "keep_existing").get("ok", false)),
			"one listed wall, kept")


func _accept() -> void:
	var bb := Modules.bus("building") as BuildingBus
	if bb == null:
		check(true, "no building bus here: accept is checked in the game")
		return
	var before := bb.model.to_data()
	var bus := ContractsBus.new()
	add_child(bus)
	var ext := ContractTwists.apply(ContractGenerator.generate(31, "detached_house", 3), 3, ["extension"])
	bus.board = [ext]
	bus.career.set_xp(ContractTiers.MAX_XP)
	bus.board = [ext]
	bus.accept(str(ext.id))
	check(bb.model.locked_ids().size() >= 10, "accepting an extension job loads the existing house into the design")
	bus.abandon()
	bus.queue_free()
	bb.sync.load_design(before)


func _item(a: Dictionary, kind: String) -> Dictionary:
	for it: Dictionary in a.items:
		if str(it.kind) == kind:
			return it
	return {}
