class_name DemolitionBus
extends Node
## The demolition module's bus (Modules.bus("demolition")): the crew plans charges on a shared
## firing timeline, fires them, and Jolt brings the building down on the host, streamed to
## everyone. Every change is a host-validated event; the host alone decides what blasts, what
## breaks loose (DemolitionRules, and impacts reported by the host's view) and the score.
##
##   bus.start_demolition(parts, "Office block", {"neighbours": [AABB(...)]})
##   bus.start_from_model(model)          # the design room's "Demolish"
##   bus.request_charge("p12", 0.5)       # place, move to 0.5 s, or (same delay) remove
##   bus.request_charge("p12", 0, at, 2)  # a heavy charge at a point on the part
##   bus.request_plan(DemolitionRules.sequence(bus.parts, "implode"))  # the whole plan at once
##   bus.request_fire()                   # 3 s countdown, then each charge at its delay
##   bus.request_reset()                  # the building stands again, charges kept
##
## Parts are BuildingParts Dictionaries.

signal started(title: String)
signal charges_changed
signal fired(at: float)
signal blasted(part_id: String)
signal released(part_ids: PackedStringArray)
## Falling parts that broke up on impact (each fell as one piece until then).
signal fractured(part_ids: PackedStringArray)
signal reset
signal result_changed(result: Dictionary)

const VIEW_SCENE := "demolition.view"
const START := "demolition.start"
const CHARGE := "demolition.charge"
const FIRE := "demolition.fire"
const BLAST := "demolition.blast"
const RELEASE := "demolition.release"
const RESET := "demolition.reset"
const RESULT := "demolition.result"
const FRACTURE := "demolition.fracture"
const PLAN := "demolition.plan"
## Charge sizes: small, standard, heavy (how hard it blasts and how fine it shatters).
const SIZES := ["Small", "Standard", "Heavy"]
const SIZE_POWER := [0.6, 1.0, 1.6]
const DEMO_FLAG := "demolition.demo"
const MAX_CHARGES := 40
const MAX_DELAY := 10.0
const DELAY_STEP := 0.25
const COUNTDOWN := 3.0
const ZONE_MARGIN := 4.0
const MAX_PARTS := 3000

var parts: Array = []
var by_id: Dictionary = {}
var title := ""
var zone := Rect2()
var neighbours: Array = []  # AABB
var charges: Dictionary = {}  # part id -> delay, s
var charge_at: Dictionary = {}  # part id -> Vector3 (world) where it was placed, when given
var charge_size: Dictionary = {}  # part id -> 0 small, 1 standard, 2 heavy (1 when missing)
var fire_at := -1.0
var blasted_ids: Dictionary = {}
var released_ids: Dictionary = {}
var fractured_ids: Dictionary = {}
var result: Dictionary = {}
var net: MultiplayerBus
## The host's copy of the model a "Demolish" started from: what falls then comes from the
## structure module's progressive collapse check instead of DemolitionRules' stand-in.
var model: BuildingModel


func register_module() -> void:
	net = Modules.bus("multiplayer") as MultiplayerBus
	Router.register_scene(VIEW_SCENE, "res://modules/demolition/internal/demolition_view.tscn")
	Router.set_loading_title(VIEW_SCENE, "Demolition")
	if Flags.is_on(DEMO_FLAG):
		Menu.register_entry(DEMO_FLAG, "Demolition demo", VIEW_SCENE, 21, {"demo": true})
	net.register_event(START, _apply_start, _validate_start)
	net.register_event(CHARGE, _apply_charge, _validate_charge)
	net.register_event(FIRE, _apply_fire, _validate_fire)
	net.register_event(BLAST, _apply_blast, _host_only)
	net.register_event(RELEASE, _apply_release, _host_only)
	net.register_event(RESET, _apply_reset, _validate_reset)
	net.register_event(RESULT, _apply_result, _host_only)
	net.register_event(FRACTURE, _apply_fracture, _host_only)
	net.register_event(PLAN, _apply_plan, _validate_plan)
	net.register_snapshot_provider("demolition", self)
	net.session_ended.connect(func(_reason: String) -> void: _clear())
	_hook_design.call_deferred()


func unregister_module() -> void:
	Menu.unregister_entry(DEMO_FLAG)
	if net:
		for e in [START, CHARGE, FIRE, BLAST, RELEASE, RESET, RESULT, FRACTURE, PLAN]:
			net.unregister_event(e)
		net.unregister_snapshot_provider("demolition")


## "Demolish" on the design room's top bar, when the design module is loaded (optional).
func _hook_design() -> void:
	var design := Modules.bus("design")
	if design and design.has_method("register_action"):
		design.register_action("demolition.demolish", "Demolish", func(model: BuildingModel) -> void:
			start_from_model(model), 60)


# --- Asking ----------------------------------------------------------------------------

## Options: {"neighbours": [AABB, ...] protected buildings, "margin": drop zone margin m,
## "open": take every peer to the demolition view (default true)}.
func start_demolition(building_parts: Array, building_title: String, options: Dictionary = {}) -> void:
	net.request(START, {"parts": building_parts, "title": building_title, "options": options})


func start_from_model(from: BuildingModel, options: Dictionary = {}) -> void:
	var o := options.duplicate()
	o["from_model"] = true
	start_demolition(BuildingParts.from_model(from), from.name, o)


## Charges `part_id` to go off `delay` s after firing, at world point `at` on it (an inside
## face picked when walking in, say; the part's centre when null). Charging a part again at
## the same delay takes the charge off; at another delay or point it moves the charge.
func request_charge(part_id: String, delay: float, at: Variant = null, size := -1) -> void:
	var p := {"part": part_id, "delay": delay}
	if at is Vector3:
		p["at"] = at
	if size >= 0:
		p["size"] = size
	net.request(CHARGE, p)


## Replaces the whole charge plan at once: {part id: delay}, or {part id: {"delay", "at"?,
## "size"?}}. {} clears every charge. Used by the charge list, the timeline's group moves
## and the auto-sequence presets (DemolitionRules.sequence).
func request_plan(plan: Dictionary) -> void:
	net.request(PLAN, {"plan": plan})


## A charge's size (0 small, 1 standard, 2 heavy) and its blast power.
func size_of(id: String) -> int:
	return int(charge_size.get(id, 1))


func power_of(id: String) -> float:
	return float(SIZE_POWER[clampi(size_of(id), 0, SIZE_POWER.size() - 1)])


## Where part `id`'s charge sits (world): the point it was placed at, else the part's centre.
func charge_point(id: String) -> Vector3:
	if charge_at.has(id):
		return charge_at[id]
	var part: Dictionary = by_id.get(id, {})
	return (part.aabb as AABB).get_center() if part.has("aabb") else Vector3.ZERO


func request_fire() -> void:
	net.request(FIRE, {})


func request_reset() -> void:
	net.request(RESET, {})


# --- Host side, from the host's physics ------------------------------------------------

## The host's view reports parts knocked loose by impacts; they and whatever they held fall.
func host_release(part_ids: PackedStringArray) -> void:
	if not net.is_host() or part_ids.is_empty():
		return
	var gone := released_ids.duplicate()
	var fresh := PackedStringArray()
	for id in part_ids:
		if by_id.has(id) and not gone.has(id):
			gone[id] = true
			fresh.append(id)
	if fresh.is_empty():
		return
	fresh.append_array(_falls(gone))
	net.host_emit(RELEASE, {"ids": fresh})


## The host's view reports falling parts that broke up when they hit something.
func host_fracture(part_ids: PackedStringArray) -> void:
	if net.is_host() and not part_ids.is_empty():
		net.host_emit(FRACTURE, {"ids": part_ids})


func host_result(r: Dictionary) -> void:
	if net.is_host():
		net.host_emit(RESULT, r)


func _process(_delta: float) -> void:
	if fire_at < 0.0 or not net.is_host():
		return
	var now := net.server_time()
	var due: Array[String] = []
	for id: String in charges:
		if now >= fire_at + float(charges[id]) and not blasted_ids.has(id):
			due.append(id)
	if due.is_empty():
		return
	due.sort()
	for id in due:
		net.host_emit(BLAST, {"part": id})
	var gone := released_ids.duplicate()
	var fall := _falls(gone)
	if not fall.is_empty():
		net.host_emit(RELEASE, {"ids": fall})


# --- Reading ---------------------------------------------------------------------------

func is_active() -> bool:
	return not parts.is_empty()


func is_fired() -> bool:
	return fire_at >= 0.0


## Seconds until the first charge, negative once firing has begun (or before Fire).
func countdown() -> float:
	if fire_at < 0.0:
		return -1.0
	return fire_at - net.server_time()


## Volume of everything above the foundations (what a demolition has to bring down), m3.
func total_volume() -> float:
	var v := 0.0
	for p: Dictionary in parts:
		if str(p.get("family", "")) != "foundation":
			v += (p.aabb as AABB).get_volume()
	return v


## Part ids that would come down if the charges fired now (the preview).
func predicted() -> PackedStringArray:
	var gone := released_ids.duplicate()
	for id: String in charges:
		gone[id] = true
	return _falls(gone)



## Standing part ids that lose support once `gone` (id -> true) are down: the structure
## solver's collapse when this demolition came from a model, plus the support graph (which
## also covers stair and lift rooms the solver does not know).
func _falls(gone: Dictionary) -> PackedStringArray:
	var out := DemolitionRules.unsupported(parts, gone)
	if model == null:
		return out
	var seen: Dictionary = {}
	for id in out:
		seen[id] = true
	for id in StructureBuilding.collapse_after(model, PackedStringArray(gone.keys())):
		if by_id.has(id) and not gone.has(id) and not seen.has(id):
			seen[id] = true
			out.append(id)
	return out


# --- Events ----------------------------------------------------------------------------

func _host_only(_sender: int, _p: Dictionary) -> Variant:
	return "only the host decides that"


func _validate_start(_sender: int, p: Dictionary) -> Variant:
	var list: Variant = p.get("parts")
	if not list is Array or (list as Array).is_empty():
		return "nothing to demolish"
	if (list as Array).size() > MAX_PARTS:
		return "too many parts (%d, at most %d)" % [(list as Array).size(), MAX_PARTS]
	var options: Dictionary = p.get("options", {})
	return {"parts": list, "title": str(p.get("title", "Building")),
			"zone": DemolitionRules.drop_zone(list, float(options.get("margin", ZONE_MARGIN))),
			"neighbours": options.get("neighbours", []), "open": bool(options.get("open", true)),
				"from_model": bool(options.get("from_model", false))}


func _apply_start(p: Dictionary) -> void:
	parts = p.get("parts", [])
	by_id.clear()
	for part: Dictionary in parts:
		by_id[part.id] = part
	title = str(p.get("title", ""))
	zone = p.get("zone", Rect2())
	neighbours = p.get("neighbours", [])
	charges = (p.get("charges", {}) as Dictionary).duplicate()
	charge_at = (p.get("charge_at", {}) as Dictionary).duplicate()
	charge_size = (p.get("charge_size", {}) as Dictionary).duplicate()
	fire_at = float(p.get("fire_at", -1.0))
	blasted_ids = (p.get("blasted", {}) as Dictionary).duplicate()
	released_ids = (p.get("released", {}) as Dictionary).duplicate()
	fractured_ids = (p.get("fractured", {}) as Dictionary).duplicate()
	result = p.get("result", {})
	model = null
	if bool(p.get("from_model", false)) and net.is_host():
		var building := Modules.bus("building") as BuildingBus
		if building:
			model = building.model
	started.emit(title)
	if bool(p.get("open", true)) and Router.has_scene(VIEW_SCENE) and Router.current_id != VIEW_SCENE:
		Router.goto(VIEW_SCENE)


func _validate_charge(_sender: int, p: Dictionary) -> Variant:
	var id := str(p.get("part", ""))
	if not by_id.has(id):
		return "no such part"
	if is_fired():
		return "the charges have already fired; reset first"
	if released_ids.has(id):
		return "that part has already come down"
	if str(by_id[id].get("family", "")) == "foundation":
		return "charges go on the structure above ground"
	var delay := snappedf(clampf(float(p.get("delay", 0.0)), 0.0, MAX_DELAY), DELAY_STEP)
	var out := {"part": id, "delay": delay}
	if p.has("size"):
		out["size"] = clampi(int(p.size), 0, SIZES.size() - 1)
	var at: Variant = p.get("at")
	if at is Vector3:
		# On the part (a little outside its box at most).
		var box: AABB = (by_id[id].aabb as AABB).grow(0.5)
		out["at"] = (at as Vector3).clamp(box.position, box.end)
	if charges.has(id) and is_equal_approx(float(charges[id]), delay) \
			and (not out.has("size") or int(out.size) == size_of(id)) and (not out.has("at") or not charge_at.has(id) or (charge_at[id] as Vector3).distance_to(out.at) < 0.3):
		return {"part": id, "remove": true}
	if not charges.has(id) and charges.size() >= MAX_CHARGES:
		return "%d charges at most" % MAX_CHARGES
	return out


func _apply_charge(p: Dictionary) -> void:
	var id := str(p.get("part", ""))
	if bool(p.get("remove", false)):
		charges.erase(id)
		charge_at.erase(id)
		charge_size.erase(id)
	else:
		if p.has("size"):
			charge_size[id] = int(p.size)
		charges[id] = float(p.get("delay", 0.0))
		if p.get("at") is Vector3:
			charge_at[id] = p.at
		else:
			charge_at.erase(id)
	charges_changed.emit()


func _validate_plan(_sender: int, p: Dictionary) -> Variant:
	if not is_active():
		return "nothing to demolish"
	if is_fired():
		return "the charges have already fired; reset first"
	var plan: Variant = p.get("plan")
	if not plan is Dictionary:
		return "no plan"
	var out := {}
	for id: Variant in plan:
		var key := str(id)
		if not by_id.has(key) or released_ids.has(key) or str(by_id[key].get("family", "")) == "foundation":
			continue
		var v: Variant = plan[id]
		var entry: Dictionary = v if v is Dictionary else {"delay": v}
		var e := {"delay": snappedf(clampf(float(entry.get("delay", 0.0)), 0.0, MAX_DELAY), DELAY_STEP)}
		if entry.get("at") is Vector3:
			var box: AABB = (by_id[key].aabb as AABB).grow(0.5)
			e["at"] = (entry.at as Vector3).clamp(box.position, box.end)
		if entry.has("size"):
			e["size"] = clampi(int(entry.size), 0, SIZES.size() - 1)
		out[key] = e
		if out.size() >= MAX_CHARGES:
			break
	return {"plan": out}


func _apply_plan(p: Dictionary) -> void:
	charges.clear()
	charge_at.clear()
	charge_size.clear()
	var plan: Dictionary = p.get("plan", {})
	for id: String in plan:
		var e: Dictionary = plan[id]
		charges[id] = float(e.delay)
		if e.get("at") is Vector3:
			charge_at[id] = e.at
		if e.has("size"):
			charge_size[id] = int(e.size)
	charges_changed.emit()


## The plan now in request_plan's form: {part id: {"delay", "at"?, "size"?}}.
func plan() -> Dictionary:
	var out := {}
	for id: String in charges:
		var e := {"delay": float(charges[id])}
		if charge_at.has(id):
			e["at"] = charge_at[id]
		if charge_size.has(id):
			e["size"] = charge_size[id]
		out[id] = e
	return out


func _validate_fire(_sender: int, _p: Dictionary) -> Variant:
	if not is_active():
		return "nothing to demolish"
	if is_fired():
		return "already fired"
	if charges.is_empty():
		return "place some charges first"
	return {"at": net.server_time() + COUNTDOWN}


func _apply_fire(p: Dictionary) -> void:
	fire_at = float(p.get("at", net.server_time()))
	result = {}
	fired.emit(fire_at)


func _apply_blast(p: Dictionary) -> void:
	var id := str(p.get("part", ""))
	if blasted_ids.has(id):
		return
	blasted_ids[id] = true
	released_ids[id] = true
	blasted.emit(id)


func _apply_release(p: Dictionary) -> void:
	var fresh := PackedStringArray()
	for id: Variant in p.get("ids", []):
		if not released_ids.has(str(id)):
			released_ids[str(id)] = true
			fresh.append(str(id))
	if not fresh.is_empty():
		released.emit(fresh)


func _apply_fracture(p: Dictionary) -> void:
	var fresh := PackedStringArray()
	for id: Variant in p.get("ids", []):
		if released_ids.has(str(id)) and not fractured_ids.has(str(id)):
			fractured_ids[str(id)] = true
			fresh.append(str(id))
	if not fresh.is_empty():
		fractured.emit(fresh)


func _validate_reset(_sender: int, _p: Dictionary) -> Variant:
	return {} if is_active() else "nothing to reset"


func _apply_reset(_p: Dictionary) -> void:
	fire_at = -1.0
	blasted_ids.clear()
	released_ids.clear()
	fractured_ids.clear()
	result = {}
	reset.emit()


func _apply_result(p: Dictionary) -> void:
	result = p.duplicate()
	result_changed.emit(result)


func _clear() -> void:
	model = null
	fractured_ids.clear()
	parts = []
	by_id.clear()
	charges.clear()
	charge_at.clear()
	charge_size.clear()
	fire_at = -1.0
	blasted_ids.clear()
	released_ids.clear()
	result = {}


func get_net_snapshot() -> Dictionary:
	if not is_active():
		return {}
	return {"parts": parts, "title": title, "zone": zone, "neighbours": neighbours,
			"charges": charges.duplicate(), "charge_at": charge_at.duplicate(), "charge_size": charge_size.duplicate(), "fire_at": fire_at, "blasted": blasted_ids.duplicate(),
			"released": released_ids.duplicate(), "fractured": fractured_ids.duplicate(), "result": result.duplicate(), "open": false}


func apply_net_snapshot(data: Dictionary) -> void:
	if data.is_empty():
		_clear()
		return
	_apply_start(data)
