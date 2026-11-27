extends Control
## The firm's map: a pencil outline of Great Britain with every real site in the pool as a
## small ring, and a pin on each site that holds one of the firm's buildings (with how many).
## Buildings on no real site stand in the firm's yard, drawn in the sea off the east coast.
## Click a pin to pick that site's newest building.

signal picked(record_id: String)

## Great Britain's coast, roughly (lon, lat), clockwise from Cape Wrath.
const COAST := [
	[-5.0, 58.62], [-3.37, 58.67], [-3.07, 58.64], [-3.09, 58.44], [-3.65, 58.12], [-3.77, 57.86],
	[-4.2, 57.5], [-3.28, 57.72], [-2.0, 57.69], [-1.78, 57.5], [-2.08, 57.15], [-2.47, 56.71],
	[-2.97, 56.46], [-2.58, 56.28], [-3.19, 56.02], [-2.51, 56.0], [-2.0, 55.77], [-1.42, 55.02],
	[-1.2, 54.69], [-0.61, 54.49], [-0.08, 54.12], [0.11, 53.58], [0.34, 53.14], [0.2, 52.87],
	[0.49, 52.95], [1.3, 52.93], [1.73, 52.6], [1.75, 52.48], [1.35, 51.96], [1.15, 51.79],
	[0.71, 51.54], [1.39, 51.39], [1.31, 51.12], [0.97, 50.91], [0.25, 50.73], [-0.14, 50.82],
	[-1.09, 50.79], [-1.88, 50.72], [-2.45, 50.6], [-3.4, 50.62], [-3.64, 50.22], [-4.14, 50.36],
	[-5.2, 49.96], [-5.71, 50.07], [-5.08, 50.42], [-4.53, 51.02], [-3.47, 51.21], [-2.7, 51.5],
	[-3.17, 51.45], [-3.94, 51.6], [-5.31, 51.9], [-4.66, 52.1], [-4.08, 52.41], [-4.77, 52.8],
	[-4.27, 53.14], [-4.63, 53.31], [-3.83, 53.33], [-3.02, 53.43], [-3.05, 53.82], [-2.87, 54.07],
	[-3.23, 54.11], [-3.64, 54.49], [-3.55, 54.64], [-3.2, 54.95], [-4.06, 54.83], [-4.86, 54.64],
	[-5.03, 54.9], [-4.63, 55.46], [-4.75, 55.95], [-5.8, 55.3], [-5.47, 56.41], [-6.22, 56.73],
	[-5.83, 57.0], [-5.71, 57.28], [-5.16, 57.9],
]
const LON := Vector2(-6.8, 2.6)
const LAT := Vector2(49.7, 58.9)
## Where the firm's yard (buildings with no real site) is drawn.
const YARD := Vector2(2.1, 56.6)

var bus: TownBus
var selected := ""
## site id -> Vector2(lon, lat), from the pool's summaries.
var _sites: Dictionary = {}
## Pins drawn last frame: [{at: Vector2 px, record}].
var _pins: Array = []


func bind(town: TownBus) -> void:
	bus = town
	mouse_filter = Control.MOUSE_FILTER_STOP
	for s: Dictionary in SitePool.list():
		var ll: Variant = parse_location(str(s.get("location", "")))
		if ll != null:
			_sites[str(s.id)] = ll
	bus.records_changed.connect(queue_redraw)
	resized.connect(queue_redraw)


func _exit_tree() -> void:
	if bus and bus.records_changed.is_connected(queue_redraw):
		bus.records_changed.disconnect(queue_redraw)


## Vector2(lon, lat) from "51.3812° N, 2.3590° W", or null.
static func parse_location(text: String) -> Variant:
	var parts := text.split(",")
	if parts.size() != 2:
		return null
	var lat := parts[0].strip_edges()
	var lon := parts[1].strip_edges()
	var la := lat.to_float() * (-1.0 if lat.ends_with("S") else 1.0)
	var lo := lon.to_float() * (-1.0 if lon.ends_with("W") else 1.0)
	return Vector2(lo, la)


func select(rid: String) -> void:
	selected = rid
	queue_redraw()


## A (lon, lat) on the map in pixels, keeping the map's shape (degrees of longitude shrunk by
## cos 54°).
func to_px(ll: Vector2) -> Vector2:
	var k := cos(deg_to_rad(54.0))
	var w := (LON.y - LON.x) * k
	var h := LAT.y - LAT.x
	var s := minf(size.x / w, size.y / h) * 0.95
	var off := (size - Vector2(w, h) * s) * 0.5
	return off + Vector2((ll.x - LON.x) * k, LAT.y - ll.y) * s


## Where a record's pin goes (lon, lat).
func place_of(rec: Dictionary) -> Vector2:
	var o: Dictionary = rec.get("site_origin", {})
	if o.has("lat"):
		return Vector2(float(o.lon), float(o.lat))
	if _sites.has(str(rec.site_id)):
		return _sites[str(rec.site_id)]
	return YARD


func pin_count() -> int:
	return _pins.size()


func _draw() -> void:
	var ink := BsxTheme.col(self, "TEXT")
	var accent := BsxTheme.col(self, "ACCENT")
	var coast := PackedVector2Array()
	for p: Array in COAST:
		coast.append(to_px(Vector2(p[0], p[1])))
	draw_colored_polygon(coast, Color(ink, 0.04))
	coast.append(coast[0])
	draw_polyline(coast, Color(ink, 0.55), 1.6, true)
	# A light graticule every two degrees.
	for lo in range(-6, 3, 2):
		draw_line(to_px(Vector2(lo, LAT.x)), to_px(Vector2(lo, LAT.y)), Color(ink, 0.06), 1.0)
	for la in range(50, 59, 2):
		draw_line(to_px(Vector2(LON.x, la)), to_px(Vector2(LON.y, la)), Color(ink, 0.06), 1.0)
	var font := get_theme_default_font()
	for id: String in _sites:
		draw_arc(to_px(_sites[id]), 3.5, 0, TAU, 16, Color(ink, 0.35), 1.2, true)
	# Pins: one per place, the newest building there on top, with a count.
	var by_place: Dictionary = {}
	for r: Dictionary in bus.records():
		var key := place_of(r)
		if not by_place.has(key):
			by_place[key] = []
		by_place[key].append(r)
	_pins.clear()
	var yard_drawn := false
	for key: Vector2 in by_place:
		var list: Array = by_place[key]
		var at := to_px(key)
		var newest: Dictionary = list[list.size() - 1]
		var sel := false
		for r: Dictionary in list:
			if str(r.id) == selected:
				sel = true
				newest = r
		var standing := list.filter(func(r: Dictionary) -> bool: return not bool(r.get("demolished", false))).size()
		var col := accent if standing > 0 else Color(ink, 0.5)
		if key == YARD:
			yard_drawn = true
		draw_line(at, at + Vector2(0, -16), Color(ink, 0.8), 1.5)
		draw_circle(at + Vector2(0, -20), 9.0 if sel else 7.0, col)
		draw_arc(at + Vector2(0, -20), 9.0 if sel else 7.0, 0, TAU, 20, ink, 1.4, true)
		if list.size() > 1:
			draw_string(font, at + Vector2(-4, -16), str(list.size()), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
		var label := str(newest.get("site_name", "")) if str(newest.get("site_name", "")) != "" else "The firm's yard"
		draw_string(font, at + Vector2(12, -16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13 if sel else 12, Color(ink, 0.95 if sel else 0.7))
		_pins.append({"at": at + Vector2(0, -20), "record": newest})
	if yard_drawn:
		draw_string(font, to_px(YARD) + Vector2(-40, 14), "(no real site)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(ink, 0.5))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var at := (event as InputEventMouseButton).position
		for p: Dictionary in _pins:
			if (p.at as Vector2).distance_to(at) < 14.0:
				select(str(p.record.id))
				picked.emit(str(p.record.id))
				accept_event()
				return
	elif event is InputEventMouseMotion:
		var at := (event as InputEventMouseMotion).position
		tooltip_text = ""
		for p: Dictionary in _pins:
			if (p.at as Vector2).distance_to(at) < 14.0:
				tooltip_text = "%s · %s" % [str(p.record.title), TownRecord.summary_text(p.record)]
