extends RefCounted
## Sample finished buildings for testing the town without playing contracts through
## (Settings > Debug > Town, and the screenshot tour): a house on the Northstowe meadow, and
## riverside apartments and offices on the two neighbouring Ancoats plots (the old ironworks
## and the infill plot next to it). Each is a plain shell in the middle of its plot (the
## middle of the plot's bounding box: the plot frame's origin is the mean of its corners,
## which an uneven outline pulls off-centre): footings, walls, slabs, a roof, doors and windows.

const C := preload("res://modules/building/api/building_commands.gd")


## [{model, brief, settlement}] for TownBus.add_building.
static func samples() -> Array:
	return [
		_sample("northstowe-meadow", "Northstowe meadow", "Three-bed detached house", "The Okafor family",
				"detached_house", 2, shell(10.0, 8.0, 2, "roof_pitched", _middle("northstowe-meadow")), 182000.0, 164500.0, 61),
		_sample("ancoats-phoenix-ironworks", "Phoenix Ironworks, Ancoats", "Riverside apartments",
				"Rochdale Canal Homes", "apartment_block", 5, shell(30.0, 14.0, 5, "roof_flat", _middle("ancoats-phoenix-ironworks")), 2650000.0, 2410000.0, 240),
		_sample("ancoats-infill", "Ancoats city infill", "Four-storey offices", "Ancoats Works Ltd",
				"office_block", 5, shell(18.0, 14.0, 4, "roof_flat", _middle("ancoats-infill")), 1450000.0, 1302000.0, 196),
	]


static func _sample(site_id: String, site_name: String, title: String, client: String, type: String, tier: int,
		model: BuildingModel, fee: float, cost: float, days: int) -> Dictionary:
	model.name = title
	var bid := "sample_" + site_id
	return {
		"model": model,
		"brief": {"id": bid, "title": title, "client": client, "type": type, "tier": tier, "fee": fee,
				"site": {"id": site_id, "name": site_name}},
		"settlement": {"brief_id": bid, "title": title, "tier": tier, "passed": true, "fee": fee,
				"cost": cost, "profit": fee - cost, "days": days},
	}


## The middle of a site's plot in the plot frame (building model coordinates).
static func _middle(site_id: String) -> Vector2:
	var pack := SitePool.open(site_id)
	if pack == null or not pack.ok():
		return Vector2.ZERO
	var c := pack.plot_bounds_local().get_center()
	return Vector2(snappedf(c.x, 0.5), snappedf(c.y, 0.5))


## A w x d shell of `storeys` centred on `at`, with an entrance on the south side.
static func shell(w: float, d: float, storeys: int, roof: String, at := Vector2.ZERO) -> BuildingModel:
	var m := BuildingModel.new("", "Building")
	for i in storeys - 1:
		m.apply(C.add_level(3.0, "Level %d" % (i + 1)))
	var x0 := at.x - w * 0.5
	var z0 := at.y - d * 0.5
	var corners := [[x0, 0.0, z0], [x0 + w, 0.0, z0], [x0 + w, 0.0, z0 + d], [x0, 0.0, z0 + d]]
	for lv in storeys:
		var walls: Array = []
		for side in 4:
			var a: Array = corners[side]
			var b: Array = corners[(side + 1) % 4]
			if lv == 0:
				m.apply(C.place_part("strip_footing", 0, {"a": a, "b": b}))
			var r := m.apply(C.place_part("wall_loadbearing", lv, {"a": a, "b": b}, "masonry"))
			walls.append(str(r.do.entry.id))
		m.apply(C.place_part("slab", lv, {"outline": C.rect(x0, z0, w, d)}, "concrete"))
		for side in 4:
			var length := w if side % 2 == 0 else d
			var n := maxi(1, int(length / 3.5))
			for k in n:
				var t := length * float(k + 1) / float(n + 1)
				if lv == 0 and side == 2 and absf(t - w * 0.5) < 1.6:
					continue
				m.apply(C.place_opening("window_medium", walls[side], t))
		if lv == 0:
			m.apply(C.place_opening("door_external", walls[2], w * 0.5))
	var top := {"outline": C.rect(x0, z0, w, d), "y": 3.0}
	if roof == "roof_pitched":
		top["pitch"] = 35.0
	m.apply(C.place_part(roof, storeys - 1, top, "" if roof == "roof_pitched" else "concrete"))
	return m
