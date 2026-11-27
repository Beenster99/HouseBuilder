class_name StructureScenario
extends RefCounted
## One stress test: factors on the characteristic loads, plus wind or ground shaking pushed
## sideways from each direction in turn (the result keeps the worst direction per member).
## The three standard tests are normal_use(), storm() and quake(). Harder ones for contract
## events and checks: heavy_snow(), ten_years() (ageing), heavy_use(), and any of them made
## harder with scaled(factor) or by_id(id, factor), e.g. a storm at 1.3 times the handover
## test's wind.

const NORMAL_USE := "normal_use"
const STORM := "storm"
const QUAKE := "quake"
const COLLAPSE := "collapse"
const HEAVY_SNOW := "heavy_snow"
const TEN_YEARS := "ten_years"
const HEAVY_USE := "heavy_use"
## Strength left after ten years, by material: timber dries, checks and rots at joints,
## exposed steel corrodes; masonry and concrete barely change.
const TEN_YEAR_CAPACITY := {"timber": 0.8, "glulam": 0.85, "steel": 0.9, "masonry": 0.97, "concrete": 0.97}
const COMPASS: Array[Vector3] = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]

var id := ""
var title := ""
## Factors on the dead, live and snow load cases.
var dead := 1.0
var live := 1.0
var snow := 0.0
## Design wind pressure (kPa, factor included) on each node's wind area.
var wind_kpa := 0.0
## Ground shaking: sideways force as a fraction of each node's weight (dead plus
## quake_live of the live load).
var quake_g := 0.0
var quake_live := 0.3
## Horizontal unit directions the sideways load is tried from.
var directions: Array[Vector3] = []
## Share of strength each material still has (material id -> 0..1); missing means all of it.
var capacity: Dictionary = {}
## How much harder than its base test this one is (1 = as at handover).
var factor := 1.0


static func make(scenario_id: String, scenario_title: String, factors: Dictionary) -> StructureScenario:
	var s := StructureScenario.new()
	s.id = scenario_id
	s.title = scenario_title
	s.dead = float(factors.get("dead", 1.0))
	s.live = float(factors.get("live", 1.0))
	s.snow = float(factors.get("snow", 0.0))
	s.wind_kpa = float(factors.get("wind_kpa", 0.0))
	s.quake_g = float(factors.get("quake_g", 0.0))
	s.quake_live = float(factors.get("quake_live", 0.3))
	if s.wind_kpa > 0.0 or s.quake_g > 0.0:
		s.directions = COMPASS.duplicate()
	s.capacity = (factors.get("capacity", {}) as Dictionary).duplicate()
	s.factor = float(factors.get("factor", 1.0))
	return s


## Everyday loads with safety factors: people and furniture, a little snow.
static func normal_use() -> StructureScenario:
	return make(NORMAL_USE, "Normal use", {"dead": 1.35, "live": 1.5, "snow": 0.75})


## A storm: strong wind from each side and a heavy snowfall, with fewer people inside.
static func storm() -> StructureScenario:
	return make(STORM, "Storm", {"dead": 1.2, "live": 0.5, "snow": 1.2, "wind_kpa": 1.5})


## An earthquake: the building shaken sideways at a quarter of its weight.
static func quake() -> StructureScenario:
	return make(QUAKE, "Earthquake", {"dead": 1.0, "live": 0.3, "quake_g": 0.25, "quake_live": 0.3})


## What is left standing has to carry: its own weight and a few people (demolition).
static func collapse() -> StructureScenario:
	return make(COLLAPSE, "Self weight", {"dead": 1.0, "live": 0.3, "snow": 0.0})


## A heavy snowfall: deep snow on every roof (worst on flat and low-pitch ones, which keep
## it), with the usual people inside.
static func heavy_snow() -> StructureScenario:
	return make(HEAVY_SNOW, "Heavy snow", {"dead": 1.35, "live": 1.0, "snow": 2.5})


## Ten years on: normal use on a building whose timber and steel have lost some strength.
static func ten_years() -> StructureScenario:
	return make(TEN_YEARS, "Ten years on", {"dead": 1.35, "live": 1.5, "snow": 0.75, "capacity": TEN_YEAR_CAPACITY})


## Heavy use: the rooms packed fuller than designed for (a party, a sale, a fire drill).
static func heavy_use() -> StructureScenario:
	return make(HEAVY_USE, "Heavy use", {"dead": 1.35, "live": 2.25, "snow": 0.5})


## This test made factor times harder: its people, snow, wind and shaking all scaled (the
## building's own weight is what it is). The title says how much, e.g. "Storm × 1.3".
func scaled(by: float) -> StructureScenario:
	var s := StructureScenario.from_dict(to_dict())
	if is_equal_approx(by, 1.0):
		return s
	s.live = live * by
	s.snow = snow * by
	s.wind_kpa = wind_kpa * by
	s.quake_g = quake_g * by
	s.factor = factor * by
	s.id = "%s*%s" % [id, String.num(by, 2)]
	s.title = "%s × %s" % [title, String.num(by, 2)]
	return s


static func standard() -> Array[StructureScenario]:
	return [normal_use(), storm(), quake()]


## A test by id, optionally made harder: by_id("storm", 1.3). An id written "storm*1.3"
## (as scaled() names them, and as they travel over the network) works too.
static func by_id(scenario_id: String, by: float = 1.0) -> StructureScenario:
	if scenario_id.contains("*"):
		var bits := scenario_id.split("*")
		return by_id(bits[0], by * float(bits[1])) if bits.size() == 2 and bits[1].is_valid_float() else null
	var base := _base(scenario_id)
	if base == null:
		return null
	return base.scaled(by) if not is_equal_approx(by, 1.0) else base


static func _base(scenario_id: String) -> StructureScenario:
	match scenario_id:
		NORMAL_USE:
			return normal_use()
		STORM:
			return storm()
		QUAKE:
			return quake()
		COLLAPSE:
			return collapse()
		HEAVY_SNOW:
			return heavy_snow()
		TEN_YEARS:
			return ten_years()
		HEAVY_USE:
			return heavy_use()
	return null


func to_dict() -> Dictionary:
	var dirs: Array = []
	for d in directions:
		dirs.append([d.x, d.y, d.z])
	return {"id": id, "title": title, "dead": dead, "live": live, "snow": snow,
			"wind_kpa": wind_kpa, "quake_g": quake_g, "quake_live": quake_live, "directions": dirs,
			"capacity": capacity.duplicate(), "factor": factor}


static func from_dict(data: Dictionary) -> StructureScenario:
	var s := make(str(data.get("id", "")), str(data.get("title", "")), data)
	if data.has("directions"):
		s.directions.clear()
		for d: Array in data.directions:
			s.directions.append(Vector3(d[0], d[1], d[2]))
	return s


## "from the east" style name for a direction the wind or shaking comes from.
static func direction_name(d: Vector3) -> String:
	if absf(d.x) >= absf(d.z):
		return "from the west" if d.x > 0.0 else "from the east"
	return "from the north" if d.z > 0.0 else "from the south"
