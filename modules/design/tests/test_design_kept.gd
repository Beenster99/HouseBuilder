extends ModuleTest
## An existing building a brief keeps (locked entries in the model): the design room draws
## it tinted, says "Existing building: kept as it is", and its tools leave it alone (drag,
## delete, turn, flip, a door in its wall) rather than silently failing. Copies are the
## player's own.
##   tools/run_tests.sh design

const C := preload("res://modules/building/api/building_commands.gd")


func run_tests() -> void:
	var building := Modules.bus("building") as BuildingBus
	building.reset_data()
	var s := DesignSession.new()
	add_child(s)
	s.setup(Modules.bus("multiplayer") as MultiplayerBus, building.model, building.sync)
	var m := building.model
	s.sync.edit(C.place_room("bedroom", 0, C.rect(0, 0, 5, 4)))
	s.sync.edit(C.place_part("wall_loadbearing", 0, {"a": [0, 0, 0], "b": [5, 0, 0]}, "masonry"))
	await frames(2)
	var rid := str(m.rooms.keys()[0])
	var wid := str(m.parts.keys()[0])
	s.sync.edit(C.batch([C.set_fields(rid, {"locked": true}), C.set_fields(wid, {"locked": true})]))
	await frames(2)
	check(s.is_kept(rid) and s.is_kept(wid), "the room and wall are kept")
	var said: Array = [""]
	s.status.connect(func(text: String, _bad: bool) -> void: said[0] = text)
	var outline := str(m.rooms[rid].outline)
	s.presence.select(PackedStringArray([rid, wid]))
	s.delete_selection()
	await frames(2)
	check(m.rooms.has(rid) and m.parts.has(wid) and str(said[0]) == DesignSession.KEPT, "Delete leaves them and says why: %s" % said[0])
	said[0] = ""
	s.rotate_selection(90.0)
	s.mirror_selection(0, false)
	await frames(2)
	check(str(m.rooms[rid].outline) == outline and str(said[0]) == DesignSession.KEPT, "turning and flipping leave them too")
	# Dragging it.
	s.set_tool("select")
	s.presence.select(PackedStringArray())
	said[0] = ""
	s.press(Vector3(2.5, 0, 2))
	s.hover(Vector3(6.5, 0, 2))
	s.release(Vector3(6.5, 0, 2))
	await frames(2)
	check(str(m.rooms[rid].outline) == outline and str(said[0]) == DesignSession.KEPT, "a drag doesn't move it: %s" % said[0])
	# No new door in its wall.
	var n := m.parts.size()
	s.set_tool("door")
	s.press(Vector3(2.5, 0, 0))
	await frames(2)
	check(m.parts.size() == n, "no door goes into a kept wall")
	# A mirror copy is the player's own.
	s.set_tool("select")
	s.presence.select(PackedStringArray([rid]))
	var rooms_before := m.rooms.size()
	s.mirror_selection(0, true)
	await frames(2)
	var copies := Array(m.rooms.keys()).filter(func(r: String) -> bool: return r != rid)
	check(m.rooms.size() == rooms_before + 1 and not s.is_kept(str(copies[0])), "a mirror copy is new and not kept")
	s.teardown()
	s.queue_free()
	building.reset_data()
