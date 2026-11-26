class_name StructureScenario
extends RefCounted
## One stress test: factors on the characteristic loads, plus wind or ground shaking pushed
## sideways from each direction in turn (the result keeps the worst direction per member).
## The three standard tests are normal_use(), storm() and quake().

const NORMAL_USE := "normal_use"
const STORM := "storm"
const QUAKE := "quake"
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


static func standard() -> Array[StructureScenario]:
	return [normal_use(), storm(), quake()]


static func by_id(scenario_id: String) -> StructureScenario:
	match scenario_id:
		NORMAL_USE:
			return normal_use()
		STORM:
			return storm()
		QUAKE:
			return quake()
	return null


func to_dict() -> Dictionary:
	var dirs: Array = []
	for d in directions:
		dirs.append([d.x, d.y, d.z])
	return {"id": id, "title": title, "dead": dead, "live": live, "snow": snow,
			"wind_kpa": wind_kpa, "quake_g": quake_g, "quake_live": quake_live, "directions": dirs}


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
