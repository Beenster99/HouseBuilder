class_name SitePool
extends RefCounted
## The curated pool of real sites: every *.sitepack.json in DIRS. Contracts draw a plot for
## a building type from here; the picker lists them all.
##
##   SitePool.list()                       # [{id, name, description, suited_to, rating, location,
##                                         #   plot_size, area_m2, constraints, soil, path, preview...}]
##   SitePool.for_building("school")       # the ones curated for schools
##   SitePool.pick("house", 42)            # one of them, the same for the same seed
##   SitePool.open("bath-hillside-garages")

const DIRS: PackedStringArray = ["res://tools/osm/samples"]
const SUFFIX := ".sitepack.json"

static var _summaries: Array = []


## Summaries of every pack in the pool, sorted by id (packs that fail to read are left out).
static func list() -> Array:
	if _summaries.is_empty():
		for dir in DIRS:
			for f in DirAccess.get_files_at(dir):
				if not f.ends_with(SUFFIX):
					continue
				var path := dir.path_join(f)
				var pack := SitePack.load_file(path)
				if not pack.ok():
					push_warning("sites: %s: %s" % [path, pack.error])
					continue
				var preview := path.trim_suffix(SUFFIX) + ".preview.png"
				_summaries.append({"id": pack.id(), "name": pack.title(), "description": pack.description(),
						"suited_to": Array(pack.suited_to()), "rating": pack.rating(),
						"cost_multiplier_hint": pack.cost_multiplier_hint(), "soil": pack.soil(),
						"location": pack.location_text(), "plot_size": pack.plot_size_text(),
						"area_m2": pack.plot_area(), "access": pack.access().size(),
						"constraints": pack.factors().map(func(f: Dictionary) -> String: return str(f.get("label", f.get("id", "")))),
						"path": path, "preview": preview if FileAccess.file_exists(preview) else ""})
		_summaries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return _summaries.duplicate(true)


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for s: Dictionary in list():
		out.append(s.id)
	return out


static func summary(site_id: String) -> Dictionary:
	for s: Dictionary in list():
		if s.id == site_id:
			return s
	return {}


## Packs curated for a building type ("house", "school", ...), easiest first.
static func for_building(building_type: String) -> Array:
	var out := list().filter(func(s: Dictionary) -> bool: return building_type in s.suited_to)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.rating < b.rating or (a.rating == b.rating and a.id < b.id))
	return out


## One site for a building type, chosen by seed (same seed, same site on every machine).
## max_rating limits the difficulty. "" when nothing fits.
static func pick(building_type: String, seed: int, max_rating: int = 5) -> String:
	var fits := for_building(building_type).filter(func(s: Dictionary) -> bool: return int(s.rating) <= max_rating)
	if fits.is_empty():
		return ""
	return str(fits[posmod(seed, fits.size())].id)


static func open(site_id: String) -> SitePack:
	var s := summary(site_id)
	if s.is_empty():
		var none := SitePack.new()
		none.error = "no site %s in the pool" % site_id
		return none
	return SitePack.load_file(s.path)


## The file text of a pool site ("" if unknown), as the host sends it.
static func text_of(site_id: String) -> String:
	var s := summary(site_id)
	return FileAccess.get_file_as_string(s.path) if not s.is_empty() else ""
