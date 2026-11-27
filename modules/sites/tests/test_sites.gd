extends ModuleTest
## Site packs: reading and checking a pack, terrain sampling, the plot and its problems,
## the curated pool, the 3D view with neighbour colliders, and the host sending the pack to
## every player (and joiners) with the soil reaching the shared building.
##   tools/run_tests.sh sites

const BATH := "bath-hillside-garages"


class FakeNet:
	## Two-peer stand-in: requests validated on the host, payloads through var_to_bytes.
	var peers: Array = []
	var peer_id := 1
	var host_flag := true
	var events := {}
	var snapshots := {}
	var rejected: Array[String] = []

	func is_host() -> bool:
		return host_flag

	func register_event(n: String, apply: Callable, validate := Callable()) -> void:
		events[n] = {"apply": apply, "validate": validate}

	func unregister_event(n: String) -> void:
		events.erase(n)

	func register_snapshot_provider(section: String, provider: Object) -> void:
		snapshots[section] = provider

	func unregister_snapshot_provider(section: String) -> void:
		snapshots.erase(section)

	func request(n: String, payload: Dictionary = {}) -> void:
		var host: FakeNet = peers[0]
		var entry: Dictionary = host.events[n]
		var out: Variant = bytes_to_var(var_to_bytes(payload))
		if entry.validate.is_valid():
			out = entry.validate.call(peer_id, out)
		if out is String:
			rejected.append(out)
			return
		var bytes := var_to_bytes(out)
		for p: FakeNet in peers:
			p.events[n].apply.call(bytes_to_var(bytes))


func run_tests() -> void:
	_pack()
	_plot_frame()
	_pool()
	_view()
	_solo_bus()
	_peers()


func _plot_frame() -> void:
	var pack := SitePool.open(BATH)
	var local := pack.plot_outline_local()
	check(local.size() == pack.plot_outline().size() and local.size() >= 3, "plot outline in building coordinates")
	var c := Vector2.ZERO
	for p: Array in local:
		c += Vector2(p[0], p[1])
	c /= local.size()
	check(c.length() < 0.01, "centred on the building's origin: %s" % c)
	check(pack.plot_contains_local(0.0, 0.0), "the origin is on the plot")
	var b := pack.plot_bounds_local()
	check(not pack.plot_contains_local(b.end.x + 5.0, 0.0), "outside the box is off the plot")
	var p3 := Vector3(3.0, 1.0, -2.0)
	check(pack.to_plot(pack.from_plot(p3)).is_equal_approx(p3), "to_plot undoes from_plot")
	var world := pack.from_plot(Vector3(1.0, 0.0, 2.0))
	check(is_equal_approx(pack.ground_at_local(1.0, 2.0), pack.height_at(world.x, world.z)), "ground height in building coordinates")
	check(pack.plot_area() > 10.0, "plot area: %.0f m²" % pack.plot_area())


func _pack() -> void:
	var pack := SitePool.open(BATH)
	check(pack.ok(), "the Bath pack reads: %s" % pack.error)
	check(pack.id() == BATH and pack.title() != "", "id and name")
	var t := pack.terrain_grid()
	var size: Vector2i = t.size
	var heights: PackedFloat32Array = t.heights
	check(heights.size() == size.x * size.y and size.x > 10, "terrain grid decoded: %s" % size)
	var o: Vector2 = t.origin
	var step: float = t.spacing
	check(is_equal_approx(pack.height_at(o.x + 3 * step, o.y + 5 * step), heights[5 * size.x + 3]), "height at a grid point is the sample")
	var mid := pack.height_at(o.x + 3.5 * step, o.y + 5 * step)
	check(is_equal_approx(mid, (heights[5 * size.x + 3] + heights[5 * size.x + 4]) * 0.5), "halfway is the average")
	check(is_equal_approx(pack.height_at(-1e6, -1e6), heights[0]), "clamped at the edge")
	check(pack.plot_outline().size() >= 3, "the plot has an outline")
	check(pack.soil() == "made_ground" and pack.structure_soil() == "made_ground", "soil read and mapped for foundations")
	check(pack.rating() == 5 and is_equal_approx(pack.cost_multiplier_hint(), 1.6), "difficulty and cost hint")
	check(pack.has_factor("slope") and pack.has_factor("access"), "problem factors")
	check(pack.notes_text().contains("Sloping site") and pack.notes_text().contains("Difficulty 5 of 5"), "notes for players: %s" % pack.notes_text().left(120))
	check(pack.existing_buildings().size() == 1, "one building on the plot to clear")
	check(pack.neighbours().size() == pack.buildings().size() - 1, "the rest are neighbours")
	check(pack.attribution().size() > 0 and pack.attribution()[0].contains("OpenStreetMap"), "attribution lines")
	var bad := SitePack.from_text('{"format": "housebuilder.sitepack", "version": 2}')
	check(not bad.ok() and bad.error.contains("newer"), "a newer version is refused: %s" % bad.error)
	check(not SitePack.from_text("nope").ok(), "junk is refused")
	check(not SitePack.from_text('{"format": "other"}').ok(), "another format is refused")


func _pool() -> void:
	var all := SitePool.list()
	check(all.size() >= 9, "at least nine curated sites: %d" % all.size())
	for s: Dictionary in all:
		check(SitePool.open(s.id).ok(), "%s reads" % s.id)
	var schools := SitePool.for_building("school")
	check(not schools.is_empty(), "sites suit schools")
	for s: Dictionary in schools:
		check("school" in s.suited_to, "%s suits schools" % s.id)
	check(SitePool.pick("school", 7) == SitePool.pick("school", 7), "same seed, same site")
	var picked := {}
	for seed in 20:
		picked[SitePool.pick("school", seed)] = true
	check(picked.size() == schools.size(), "seeds cover the school sites")
	check(SitePool.pick("house", 1, 0) == "", "nothing that easy")
	check(SitePool.pick("castle", 1) == "", "nothing for unknown types")
	check(not SitePool.open("nowhere").ok(), "unknown id refused")


func _view() -> void:
	var sites := Modules.bus("sites") as SitesBus
	check(sites != null, "sites bus loaded")
	var pack := SitePool.open(BATH)
	var view: Node3D = SitesBus.SiteView.new()
	view.build(pack)
	add_child(view)
	check(view.get_node_or_null("Terrain") is MeshInstance3D, "terrain mesh")
	check(view.get_node_or_null("TerrainBody") is StaticBody3D, "terrain collider")
	check(view.get_node_or_null("BuildingWalls") is MeshInstance3D and view.get_node_or_null("Roads") is MeshInstance3D, "buildings and roads drawn")
	check(view.get_node_or_null("PlotOutline") is MeshInstance3D, "plot outlined")
	var neighbours := get_tree().get_nodes_in_group(SitesBus.SiteView.NEIGHBOUR_GROUP)
	check(neighbours.size() == pack.neighbours().size(), "a collider per neighbour: %d" % neighbours.size())
	var on_plot := get_tree().get_nodes_in_group(SitesBus.SiteView.PLOT_GROUP)
	check(on_plot.size() == 1 and str(on_plot[0].get_meta("site_building")) == str(pack.existing_buildings()[0].id), "the building on the plot is marked")
	var prot := 0
	for n: Node in neighbours:
		if n.get_meta("protected"):
			prot += 1
	check(prot == pack.protected_ids().size(), "protected neighbours flagged: %d" % prot)
	# A ray down onto the plot centre hits the ground near the terrain height.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var c := pack.plot_centre()
	var space := view.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(c.x, 200, c.y), Vector3(c.x, -200, c.y)))
	check(not hit.is_empty(), "something solid under the plot centre")
	view.queue_free()


func _solo_bus() -> void:
	var sites := Modules.bus("sites") as SitesBus
	var building := Modules.bus("building") as BuildingBus
	var net := Modules.bus("multiplayer") as MultiplayerBus
	var got: Array = []
	sites.site_changed.connect(func(p: SitePack) -> void: got.append(p))
	var rejected: Array[String] = []
	net.request_rejected.connect(func(_n: String, why: String) -> void: rejected.append(why))
	sites.load_site("atlantis")
	check(rejected.size() == 1 and rejected[0].contains("atlantis"), "unknown site refused: %s" % str(rejected))
	sites.load_site("tewkesbury-floodplain")
	check(got.size() == 1 and sites.current().id() == "tewkesbury-floodplain", "solo load is immediate")
	check(sites.current().digest == SitePool.open("tewkesbury-floodplain").digest, "the same file")
	check(str(building.model.meta.get("soil", "")) == sites.current().structure_soil(), "the building knows the soil: %s" % building.model.meta.get("soil"))
	check(str(building.model.meta.get("site", "")) == "tewkesbury-floodplain", "and the site")
	var view := sites.make_view()
	check(view != null, "a view of the current site")
	view.free()
	sites.clear_site()
	check(sites.current() == null and got.back() == null, "cleared")
	check(sites.make_view() == null, "no view without a site")


func _peers() -> void:
	var nets: Array = []
	var buses: Array[SitesBus] = []
	for i in 2:
		var n := FakeNet.new()
		n.peer_id = i + 1
		n.host_flag = i == 0
		nets.append(n)
	for i in 2:
		nets[i].peers = nets
		var b := SitesBus.new()
		add_child(b)
		b.attach(nets[i])
		buses.append(b)
	buses[1].load_site(BATH)
	check(buses[0].current() != null and buses[1].current() != null, "both players have the site")
	check(buses[0].current().digest == buses[1].current().digest, "the identical pack on both")
	check(is_equal_approx(buses[1].current().height_at(-80, -10), SitePool.open(BATH).height_at(-80, -10)), "same ground on the client")
	var snap: Dictionary = buses[0].get_net_snapshot()
	var raw := SitePool.text_of(BATH).to_utf8_buffer().size()
	check((snap.zip as PackedByteArray).size() < raw / 2, "sent compressed: %d of %d bytes" % [(snap.zip as PackedByteArray).size(), raw])
	var late := SitesBus.new()
	add_child(late)
	late.apply_net_snapshot(bytes_to_var(var_to_bytes(snap)))
	check(late.current() != null and late.current().digest == buses[0].current().digest, "a joiner gets it in the snapshot")
	var broken := snap.duplicate()
	broken.digest = "0"
	check(not SitesBus.unpack_payload(broken).ok(), "a damaged pack is refused")
	for b in buses:
		b.queue_free()
	late.queue_free()
	for n: FakeNet in nets:
		n.peers = []
