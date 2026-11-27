extends ModuleTest
## The firm's town: a passed handover is recorded with its building, a failed one is not;
## records place buildings on their own site and on neighbouring packs; the merged view and
## its plaque; the save round trip; two players finishing contracts on neighbouring sites and
## both seeing both buildings, a joiner included; the Our work screen and a visit.
##   tools/run_tests.sh town

const Samples := preload("res://modules/town/internal/town_samples.gd")
const PORT := 24597


func run_tests() -> void:
	_records_and_places()
	_view()
	_save_round_trip()
	_solo_handover()
	await _screen()
	await _two_players()


func _sample(i: int) -> Dictionary:
	return Samples.samples()[i]


func _fresh() -> TownBus:
	var t := TownBus.new()
	add_child(t)
	return t


func _records_and_places() -> void:
	var t := _fresh()
	var s := _sample(0)
	var rid := t.add_building(s.model, s.brief, s.settlement)
	var r := t.record(rid)
	check(not r.is_empty() and str(r.site_id) == "northstowe-meadow" and str(r.client) == "The Okafor family",
			"a record keeps its site and client: %s" % [r])
	check(t.has_model(rid) and t.model_of(rid).parts.size() == (s.model as BuildingModel).parts.size(), "and its building")
	check((r.plan.walls as Array).size() >= 4, "and a plan sketch of its ground floor")
	check("northstowe-meadow" in t.occupied_sites(), "its site counts as occupied")
	var meadow := SitePool.open("northstowe-meadow")
	var here := t.near(meadow)
	check(here.size() == 1 and bool(here[0].own) and (here[0].at as Vector3).distance_to(meadow.plot_origin()) < 0.01,
			"on its own site it stands on the plot's centre")
	check(t.near(SitePool.open("northstowe-powerline")).is_empty(), "the Northstowe pack 400 m off is past the edge of its terrain")
	check(t.near(SitePool.open("bath-hillside-garages")).is_empty(), "and not on a site 150 km away")
	var s2 := _sample(2)
	var rid2 := t.add_building(s2.model, s2.brief, s2.settlement)
	var infill := SitePool.open("ancoats-infill")
	var works := SitePool.open("ancoats-phoenix-ironworks")
	var next_door := t.near(works)
	check(next_door.size() == 1 and not bool(next_door[0].own) and str(next_door[0].record.id) == rid2,
			"offices on the Ancoats infill plot show on the ironworks pack next door")
	if next_door.size() == 1:
		# The two packs share an origin, so the offices stand on the infill plot's centre.
		var at: Vector3 = next_door[0].at
		var expect := infill.plot_origin()
		check(Vector2(at.x, at.z).distance_to(Vector2(expect.x, expect.z)) < 1.0 and absf(at.y - works.height_at(at.x, at.z)) < 0.01,
				"in the right place, on the ground: %s vs %s" % [at, expect])
	t.mark_demolished(rid)
	check(bool(t.record(rid).demolished) and t.near(meadow).is_empty() and not "northstowe-meadow" in t.occupied_sites(),
			"a demolished building stops standing and frees its site")
	t.queue_free()


func _view() -> void:
	var t := _fresh()
	var s := _sample(2)
	var rid := t.add_building(s.model, s.brief, s.settlement)
	var v := t.make_view(rid)
	check(v != null and int(v.call("mesh_count")) > 0 and int(v.call("mesh_count")) < 12,
			"the view merges the building into a few meshes (%d)" % (int(v.call("mesh_count")) if v else -1))
	check(v.find_children("*", "CollisionObject3D", true, false).is_empty(), "with no physics bodies")
	var b: AABB = v.call("bounds")
	check(b.size.y > 11.0 and b.size.x > 17.0, "the size of the offices: %s" % b)
	v.call("add_colliders")
	check(not v.find_children("*", "StaticBody3D", true, false).is_empty(), "colliders on demand for walking")
	v.free()
	var extras := t.make_site_extras(SitePool.open("ancoats-phoenix-ironworks"))
	check(extras != null and extras.find_children("TownBuilding_*", "", true, false).size() == 1,
			"the ironworks next door shows the offices built on the infill plot")
	check(extras != null and extras.find_children("Plaque", "", true, false).size() == 1, "with their plaque")
	if extras:
		var label := extras.find_children("Text", "Label3D", true, false)
		check(not label.is_empty() and "FOUR-STOREY OFFICES" in (label[0] as Label3D).text and "Ancoats Works" in (label[0] as Label3D).text,
				"the plaque names the brief and the client")
		extras.free()
	# The sites module draws them on any view of the site.
	var sites := Modules.bus("sites") as SitesBus
	var town := Modules.bus("town") as TownBus
	if sites != null and sites.has_method("make_view_of") and town != null:
		town.add_building(s.model, s.brief, s.settlement)
		var site_view := sites.make_view_of(SitePool.open("ancoats-infill"))
		check(site_view.find_children("TownBuilding_*", "", true, false).size() == 1,
				"a site view from the sites module shows the firm's building")
		site_view.free()
		town.load_data({}, 1)
	t.queue_free()


func _save_round_trip() -> void:
	var t := _fresh()
	for s: Dictionary in Samples.samples():
		t.add_building(s.model, s.brief, s.settlement)
	var text := JSON.stringify(t.save_data())
	var u := _fresh()
	u.load_data(JSON.parse_string(text), TownBus.SAVE_VERSION)
	check(u.records().size() == 3, "three records come back from a save")
	var ok := true
	for r: Dictionary in t.records():
		var m := u.model_of(str(r.id))
		var orig := t.model_of(str(r.id))
		if m == null or m.parts.size() != orig.parts.size() or TownRecord.bounds(m) != TownRecord.bounds(orig) \
				or int(u.record(str(r.id)).handed_over) != int(r.handed_over):
			ok = false
	check(ok, "with every building as it was handed over")
	check(u.on_site("ancoats-infill").size() == 1, "on their sites")
	t.queue_free()
	u.queue_free()


class FakeContracts:
	extends Node
	signal active_changed
	signal settled(settlement: Dictionary)
	var active: Dictionary = {}


func _solo_handover() -> void:
	var t := _fresh()
	var c := FakeContracts.new()
	add_child(c)
	t.watch(c)
	var s := _sample(1)
	t.source_model = s.model
	c.active = s.brief
	c.active_changed.emit()
	c.active = {}
	c.active_changed.emit()
	var failed: Dictionary = s.settlement.duplicate()
	failed["passed"] = false
	c.settled.emit(failed)
	check(t.records().is_empty(), "a failed handover is not kept")
	c.settled.emit(s.settlement)
	check(t.records().size() == 1 and str(t.records()[0].type) == "apartment_block",
			"a passed one is, with the brief cached from when it was taken")
	var with_brief: Dictionary = _sample(0).settlement.duplicate()
	with_brief["brief"] = _sample(0).brief
	t.source_model = _sample(0).model
	c.settled.emit(with_brief)
	check(t.records().size() == 2 and str(t.records()[1].site_id) == "northstowe-meadow", "the settlement's own brief is used when it has one")
	var demo: Dictionary = _sample(2).settlement.duplicate()
	var demo_brief: Dictionary = _sample(2).brief.duplicate()
	demo_brief["mode"] = "demolish"
	demo["brief"] = demo_brief
	c.settled.emit(demo)
	check(t.records().size() == 2 and ContractDemolition.is_demolition(demo_brief), "a demolition job's handover adds nothing to the town")
	c.active = {"id": "redev", "mode": "demolish", "record_id": str(t.records()[0].id)}
	c.active_changed.emit()
	check(t.being_redeveloped() == str(t.records()[0].id), "a redevelopment job taken marks its building")
	t.unwatch()
	c.queue_free()
	t.queue_free()


func _screen() -> void:
	var town := Modules.bus("town") as TownBus
	check(town != null, "the town module loads")
	if town == null:
		return
	town.load_data({}, 1)
	town.add_samples()
	check(town.records().size() == 3, "the debug samples add three buildings")
	var screen: Node = load(TownBus.SCENE_PATH).instantiate()
	add_child(screen)
	await frames(3)
	check(int(screen.get("list").call("card_count")) == 3, "the list shows them")
	check(int(screen.get("map").call("pin_count")) == 2, "the map has a pin for each place (the Ancoats pair share one) (%d)" % int(screen.get("map").call("pin_count")))
	check(town.here.has(town.local_peer()), "this player is on the screen for the crew")
	var rid := str(town.on_site("ancoats-phoenix-ironworks")[0].id)
	screen.call("pick", rid)
	town.visit(rid)
	await frames(3)
	var v: Node = screen.get("visit_view")
	check(v != null, "Visit opens the site")
	if v:
		check(int(v.call("building_count")) == 2, "the apartments and the offices next door both stand there (%d)" % int(v.call("building_count")))
		v.call("set_mode", "walk")
		await frames(20)
		var body: CharacterBody3D = v.get("body")
		var g := float(v.call("ground_at", body.position.x, body.position.z))
		check(absf(body.position.y - g) < 1.5, "walking, the crew stands on the ground (%.2f vs %.2f)" % [body.position.y, g])
		v.call("set_mode", "fly")
		check(str(v.get("mode")) == "fly", "and can fly")
		var walk := Modules.bus("walk") as WalkBus
		if walk != null:
			var inside: Node = v.call("walk_inside", rid)
			await frames(3)
			check(inside != null and walk.is_open() and str(inside.get("mode")) == "view",
					"Walk inside opens the walk module's view-only mode on the building")
			if inside:
				var copy: BuildingModel = inside.get("model")
				check(copy != town.model_of(rid) and copy.parts.size() == town.model_of(rid).parts.size(),
						"on a copy of the stored building")
				var rev := copy.revision
				var stored_rev := town.model_of(rid).revision
				Input.parse_input_event(_key(KEY_X))
				await frames(2)
				check(copy.revision == rev and town.model_of(rid).revision == stored_rev, "and nothing in it can change")
			walk.close()
			await frames(2)
			check(not bool(v.call("is_walking_inside")) and screen.get("visit_view") == v, "Esc comes back to the visit")
	town.leave()
	await frames(2)
	check(screen.get("visit_view") == null, "Back to the map")
	screen.queue_free()
	await frames(2)
	check(not town.here.has(town.local_peer()), "leaving the screen leaves the crew's list")
	town.load_data({}, 1)


func _two_players() -> void:
	var saved := Flags.all()
	Flags.set_flag(MultiplayerBus.ONLINE_FLAG, true)
	var na := _net("TownA", "Ana")
	var nb := _net("TownB", "Ben")
	var ta := _fresh()
	var tb := _fresh()
	ta.bind(na)
	tb.bind(nb)
	check(na.host(PORT) == OK, "host starts")
	nb.join("127.0.0.1", PORT)
	check(await _until(func() -> bool: return nb.is_online() and na.peers().size() == 2), "Ben joins")
	# Two contracts handed over on the neighbouring Ancoats plots, by the host.
	for i in [1, 2]:
		var s := _sample(i)
		ta.add_building(s.model, s.brief, s.settlement)
	check(await _until(func() -> bool: return tb.records().size() == 2), "both buildings reach Ben")
	check(tb.has_model(str(tb.records()[0].id)), "with their buildings")
	var crew: Array = ta.records()[0].crew
	# (Both players share one settings file in this process, so their names can match.)
	check(crew.size() == 2, "both of the crew's names are on the record: %s" % [crew])
	# A third player joins later: headers in the snapshot, buildings with the visit.
	var nc := _net("TownC", "Cat")
	var tc := _fresh()
	tc.bind(nc)
	nc.join("127.0.0.1", PORT)
	check(await _until(func() -> bool: return tc.records().size() == 2), "a joiner gets the town's records")
	check(not tc.has_model(str(tc.records()[0].id)), "but not the buildings until they are needed")
	tc.visit(str(tc.records()[1].id))
	check(await _until(func() -> bool: return ta.visiting != "" and tc.visiting == ta.visiting and tb.visiting == ta.visiting),
			"Cat asks to visit and the whole crew goes")
	check(tc.has_model(str(tc.records()[0].id)) and tc.has_model(str(tc.records()[1].id)),
			"with both neighbouring buildings sent along")
	var pack := SitePool.open(str(tc.records()[1].site_id))
	var ea := ta.make_site_extras(pack)
	var ec := tc.make_site_extras(pack)
	check(ea != null and ec != null and ea.get_child_count() == 2 and ec.get_child_count() == 2,
			"both peers see both buildings standing on the site")
	if ea:
		ea.free()
	if ec:
		ec.free()
	# Saved by the host and loaded again: still there for everyone who joins.
	var data: Dictionary = JSON.parse_string(JSON.stringify(ta.save_data()))
	ta.load_data(data, 1)
	check(ta.records().size() == 2 and ta.model_of(str(ta.records()[0].id)) != null, "the host's save brings both back")
	tc.set_here(true)
	check(await _until(func() -> bool: return ta.here.has(nc.local_peer_id()) and ta.proxy_body(nc.local_peer_id()) != null),
			"a player on the Our work screen shows to the others")
	for t: TownBus in [ta, tb, tc]:
		t.unbind()
		t.queue_free()
	nc.leave()
	nb.leave()
	na.leave()
	Flags.use(saved)


func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.pressed = true
	return k


func _net(node_name: String, player: String) -> MultiplayerBus:
	var bus := MultiplayerBus.new()
	bus.name = node_name
	add_child(bus)
	bus.register_module()
	Settings.set_value("multiplayer", "player_name", player)
	bus._refresh_identity()
	return bus


func _until(cond: Callable, timeout := 5.0) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()
