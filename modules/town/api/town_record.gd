class_name TownRecord
extends RefCounted
## One building the firm has handed over, as plain data (so the host can send it and a save
## can hold it). TownBus keeps them; this class makes them and places them on the map.
##
##   {id, brief_id, title, client, type, tier, site_id ("" for no real site), site_name,
##    site_origin: {lat, lon, elevation_m} of its site pack ({} for none),
##    plot_origin: [x, z] where the building's origin sits in its pack's coordinates,
##    handed_over (unix s), days, cost, fee, profit, crew: [names], checksum,
##    size: [w, d, h] m, parts (count), demolished (bool), demolished_at (unix s, 0),
##    plan: {walls: [[x1, z1, x2, z2], ...], rooms: [[[x, z], ...], ...]} the ground floor in
##    brief, for thumbnails on peers that have not been sent the building}
##
## The building itself (BuildingModel.to_data()) is kept beside the record, not in it, so the
## list of headers stays small enough for the join snapshot.

## Metres per degree of latitude, and of longitude at the equator (WGS84, near enough for
## sites a few kilometres apart).
const M_PER_DEG_LAT := 110540.0
const M_PER_DEG_LON := 111320.0


## A record for a passed handover. brief: the contract's brief; settlement: ContractPayout's;
## model: the handed-over building; pack: its real site (null for none).
static func make(record_id: String, brief: Dictionary, settlement: Dictionary, model: BuildingModel,
		crew: PackedStringArray, pack: SitePack = null, when: int = 0) -> Dictionary:
	var site: Dictionary = brief.get("site", {}) if brief.get("site") is Dictionary else {}
	var site_id := str(site.get("id", ""))
	var origin := {}
	var plot := [0.0, 0.0]
	var site_name := str(site.get("name", ""))
	if pack != null and pack.ok():
		site_id = pack.id()
		site_name = pack.title()
		origin = pack.location().duplicate()
		var o := pack.plot_origin()
		plot = [o.x, o.z]
	var box := bounds(model)
	return {
		"id": record_id,
		"brief_id": str(settlement.get("brief_id", brief.get("id", ""))),
		"title": str(settlement.get("title", brief.get("title", model.name if model else "Building"))),
		"client": str(brief.get("client", "")),
		"type": str(brief.get("type", "")),
		"tier": int(settlement.get("tier", brief.get("tier", 1))),
		"site_id": site_id,
		"site_name": site_name,
		"site_origin": origin,
		"plot_origin": plot,
		"handed_over": when if when > 0 else int(Time.get_unix_time_from_system()),
		"days": int(settlement.get("days", 0)),
		"cost": float(settlement.get("cost", 0.0)),
		"fee": float(settlement.get("fee", brief.get("fee", 0.0))),
		"profit": float(settlement.get("profit", 0.0)),
		"crew": Array(crew),
		"checksum": str(model.checksum()) if model else "",
		"size": [box.size.x, box.size.z, box.end.y],
		"parts": model.parts.size() if model else 0,
		"demolished": false,
		"demolished_at": 0,
		"plan": plan_of(model),
	}


## The ground floor in brief: wall centre lines and room outlines (at most PLAN_MAX of each),
## rounded to 10 cm.
const PLAN_MAX := 400


static func plan_of(model: BuildingModel) -> Dictionary:
	var walls: Array = []
	var rooms: Array = []
	if model == null:
		return {"walls": walls, "rooms": rooms}
	for pid: String in BuildingModel.sort_ids(model.parts.keys()):
		var e: Dictionary = model.parts[pid]
		if walls.size() >= PLAN_MAX or int(e.get("level", 0)) != 0 or not e.has("a") or not e.has("b"):
			continue
		if model.catalog.family_of(str(e.kind)) != "wall":
			continue
		walls.append([snappedf(float(e.a[0]), 0.1), snappedf(float(e.a[2]), 0.1), snappedf(float(e.b[0]), 0.1), snappedf(float(e.b[2]), 0.1)])
	for rid: String in BuildingModel.sort_ids(model.rooms.keys()):
		var r: Dictionary = model.rooms[rid]
		if rooms.size() >= PLAN_MAX or int(r.get("level", 0)) != 0:
			continue
		var o: Array = []
		for pt: Variant in r.get("outline", []):
			o.append([snappedf(float(pt[0]), 0.1), snappedf(float(pt[1]), 0.1)])
		rooms.append(o)
	return {"walls": walls, "rooms": rooms}


## The building's extent in its own coordinates (parts only; rooms have no height).
static func bounds(model: BuildingModel) -> AABB:
	var box := AABB()
	var first := true
	if model == null:
		return box
	for pid: String in model.parts:
		var b := model.aabb_of(pid)
		box = b if first else box.merge(b)
		first = false
	return box


## Where a record's building origin sits in another site pack's coordinates (metres, x east,
## z south), from the two packs' places on Earth. null when either has no location.
static func offset_in(rec: Dictionary, lat: float, lon: float) -> Variant:
	var o: Dictionary = rec.get("site_origin", {})
	if not o.has("lat") or not o.has("lon"):
		return null
	var dx := (float(o.lon) - lon) * M_PER_DEG_LON * cos(deg_to_rad((float(o.lat) + lat) * 0.5))
	var dz := -(float(o.lat) - lat) * M_PER_DEG_LAT
	var p: Array = rec.get("plot_origin", [0.0, 0.0])
	return Vector2(dx + float(p[0]), dz + float(p[1]))


## "£182,400" for a list or plaque.
static func money(v: float) -> String:
	var neg := v < 0.0
	var s := str(int(roundf(absf(v))))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-£" if neg else "£") + s + out


## "27 Nov 2026" from a unix time.
static func date_text(unix: int) -> String:
	var d := Time.get_date_dict_from_unix_time(unix)
	const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%d %s %d" % [int(d.day), MONTHS[clampi(int(d.month) - 1, 0, 11)], int(d.year)]


## The plaque's words: the brief title, the client, when, and who was in the crew.
static func plaque_text(rec: Dictionary) -> String:
	var lines := PackedStringArray([str(rec.get("title", "Building")).to_upper()])
	if str(rec.get("client", "")) != "":
		lines.append("For %s" % str(rec.client))
	lines.append("Handed over %s, built in %d days" % [date_text(int(rec.get("handed_over", 0))), int(rec.get("days", 0))])
	var crew: Array = rec.get("crew", [])
	if not crew.is_empty():
		lines.append("Built by " + ", ".join(PackedStringArray(crew)))
	if bool(rec.get("demolished", false)):
		lines.append("Demolished %s" % date_text(int(rec.get("demolished_at", 0))))
	return "\n".join(lines)


## One line for a list: "Detached house · Bath · 27 Nov 2026 · profit £12,400".
static func summary_text(rec: Dictionary) -> String:
	var bits := PackedStringArray()
	if str(rec.get("site_name", "")) != "":
		bits.append(str(rec.site_name))
	else:
		bits.append("the firm's yard")
	bits.append(date_text(int(rec.get("handed_over", 0))))
	bits.append("cost %s" % money(float(rec.get("cost", 0.0))))
	bits.append("profit %s" % money(float(rec.get("profit", 0.0))))
	return " · ".join(bits)
