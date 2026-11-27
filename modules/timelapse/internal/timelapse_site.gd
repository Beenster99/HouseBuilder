extends Node3D
## The work site around a timelapse build: hoarding and a gate, the site compound (cabins,
## toilet, skip, material stacks, generator, lights), scaffold that goes up with the walls
## and comes down once the roof is on, a crew walking between the stacks and the parts
## being built, and plant for each stage: a digger and tippers for the groundworks, a
## concrete mixer and pump for the foundations, a telehandler moving pallets and a scissor
## lift along the facade, and lorries bringing deliveries in through the gate.
##
## What is on site follows the shared build day (every player sees the same stage); the
## moving about is local and runs in real time, at walking and driving speeds, so it looks
## natural at any timelapse speed. Models come from the asset library (a plain box where
## one is missing).
##
##   site.setup(schedule, bounds)    # after the schedule is known
##   site.tick(day, delta)           # every frame

## Ids in the asset library (modules/assets). A missing one draws as a box of `size`.
const A := {
	"hoarding": "plant.fence.hoarding", "gate": "plant.fence.site_gate", "heras": "plant.fence.heras",
	"welfare": "plant.cabin.welfare", "office": "plant.cabin.site_office", "toilet": "plant.cabin.toilet",
	"store": "plant.cabin.store", "skip": "plant.skip.builders", "generator": "plant.small.generator",
	"lights": "plant.small.lighting_tower", "mixer_small": "plant.small.cement_mixer",
	"scaffold": "plant.scaffold.bay",
	"walker": "people.crew.operative_walking", "worker": "people.crew.labourer",
	"foreman": "people.crew.foreman", "banksman": "people.crew.banksman",
	"excavator": "plant.excavator.20t", "tipper": "plant.truck.tipper", "dumper": "plant.earthmoving.site_dumper",
	"mixer": "plant.truck.concrete_mixer", "pump": "plant.truck.concrete_pump_deployed",
	"telehandler": "plant.lifting.telehandler", "scissor": "plant.access.scissor_lift_6",
	"lorry": "vehicle.lorry.flatbed",
}
## Material stacks in the compound, by the stage that uses them.
const STACKS := [["plant.store.sand", "site"], ["plant.store.rebar", "foundation"],
		["plant.store.steel", "frame"], ["plant.store.blocks", "envelope"], ["plant.store.bricks", "envelope"],
		["plant.store.timber", "roof"], ["plant.store.pipes", "services"], ["plant.store.plasterboard", "fitout"],
		["plant.store.pallets", ""], ["plant.store.bags", ""]]
const MARGIN := 9.0          # hoarding this far outside the building
const COMPOUND := 14.0       # the compound's depth beside the plot
const SCAFFOLD_GAP := 0.9    # scaffold this far off the walls
const BAY := 2.6             # one scaffold bay's length, its lift's height below
const LIFT := 3.1
const MAX_WORKERS := 18
const WALK := 1.4            # m/s
const CLIMB := 0.6
const DRIVE := 6.0
const ROAD := 45.0           # lorries appear this far out from the gate
const DELIVERY_EVERY := 4.0  # days between deliveries while building

const PlantRig := preload("res://modules/timelapse/internal/plant_rig.gd")
## Tower cranes by size: [id, hook height above ground at rest, reach].
const TOWERS := [["plant.crane.tower", 30.0, 38.5], ["plant.crane.tower_45", 45.0, 48.5],
		["plant.crane.tower_60", 60.0, 58.5]]

var tasks: Array = []
var stages: Dictionary = {}
var total := 0.0
var bounds := AABB()
var plot := AABB()
var gate := Vector3.ZERO

var _root: Node3D
var _compound: Node3D
var _stacks: Array[Dictionary] = []    # {node, stage, at}
var _bays: Array[Dictionary] = []      # {node, row}
var _rows := 0
var _workers: Array[Dictionary] = []
var _plant: Dictionary = {}            # name -> {node, ...state}
var _lorry: Dictionary = {}
## The tower crane (a library model with a moving slew, trolley and hook), or null when
## the library has none and the view's own crane is shown instead.
var crane: Node3D
var _crane_rig: RefCounted
var _crane_yaw := 0.0
var _crane_reach := 20.0
var _active: Array = []                # tasks running now
var _stage_now: PackedStringArray = []
var _scan := 0.0
var _last_day := -1.0
var _next_delivery := 0.0
var _clock := 0.0


func setup(schedule: Dictionary, building: AABB) -> void:
	for c in get_children():
		c.queue_free()
	_stacks.clear()
	_bays.clear()
	_workers.clear()
	_plant.clear()
	tasks = schedule.get("tasks", [])
	stages = schedule.get("stages", {})
	total = float(schedule.get("days", 0.0))
	bounds = building
	plot = AABB(Vector3(bounds.position.x - MARGIN, 0, bounds.position.z - MARGIN),
			Vector3(bounds.size.x + MARGIN * 2.0, 0, bounds.size.z + MARGIN * 2.0))
	# The compound sits along the -x side; the gate is in the front (+z) hoarding.
	plot.position.x -= COMPOUND
	plot.size.x += COMPOUND
	gate = Vector3(bounds.get_center().x, 0, plot.end.z)
	_root = Node3D.new()
	_root.name = "Site"
	add_child(_root)
	_compound = Node3D.new()
	_compound.name = "Compound"
	_root.add_child(_compound)
	_build_hoarding()
	_build_compound()
	_build_scaffold()
	_build_crew()
	_build_plant()
	_build_crane()
	_last_day = -1.0
	_next_delivery = _stage_start("foundation")


## Moves everything on for build day `day`; `delta` is real seconds since the last frame.
func tick(day: float, delta: float) -> void:
	if _root == null:
		return
	_clock += delta
	_scan -= delta
	if _scan <= 0.0 or absf(day - _last_day) > 0.5:
		_scan = 0.2
		_scan_active(day)
	var built := day >= total
	var cleared := built or day >= _stage_start("landscape")
	_compound.visible = not cleared
	_update_scaffold(day)
	_update_workers(day, delta, cleared)
	_update_plant(day, delta, cleared)
	_update_lorry(day, delta, cleared)
	_update_crane(delta, cleared)
	_animate(delta)
	_last_day = day


# --- Setup ----------------------------------------------------------------------------

func _make(key: String, at: Vector3, yaw := 0.0, opts := {}) -> Node3D:
	var id: String = A.get(key, key)
	var n := AssetLibrary.make(id, opts)
	n.position = at
	n.rotation.y = yaw
	for m in n.find_children("*", "GeometryInstance3D", true, false):
		# Small site clutter doesn't need to cast sun shadows on a big site.
		if (m as GeometryInstance3D).get_aabb().size.length() < 1.5:
			(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


func _build_hoarding() -> void:
	var a := plot.position
	var b := plot.end
	var gate_w := 6.2
	var runs := [[Vector3(a.x, 0, a.z), Vector3(b.x, 0, a.z)], [Vector3(b.x, 0, a.z), Vector3(b.x, 0, b.z)],
			[Vector3(a.x, 0, b.z), Vector3(gate.x - gate_w / 2.0, 0, b.z)],
			[Vector3(gate.x + gate_w / 2.0, 0, b.z), Vector3(b.x, 0, b.z)], [Vector3(a.x, 0, a.z), Vector3(a.x, 0, b.z)]]
	for r: Array in runs:
		var p: Vector3 = r[0]
		var q: Vector3 = r[1]
		var length := p.distance_to(q)
		if length < 0.5:
			continue
		var run := _make("hoarding", (p + q) / 2.0, 0.0, {"length": length, "size": Vector3(length, 2.4, 0.06)})
		run.basis = Basis(Vector3.UP, atan2(-(q - p).z, (q - p).x)) * run.basis
		_compound.add_child(run)
	_compound.add_child(_make("gate", gate))


func _build_compound() -> void:
	# Cabins along the back of the compound, stacks in front of them, skip by the gate.
	var x0 := plot.position.x + 3.0
	var z := plot.position.z + 6.0
	for k in ["welfare", "office", "store", "toilet"]:
		var c := _make(k, Vector3(x0, 0, z), PI / 2.0)
		_compound.add_child(c)
		z += 8.0 if k != "toilet" else 3.0
		if z > plot.end.z - 10.0:
			break
	_compound.add_child(_make("generator", Vector3(x0 + 4.5, 0, plot.position.z + 3.0)))
	_compound.add_child(_make("lights", Vector3(bounds.position.x - 3.0, 0, plot.end.z - 3.0), PI * 0.75))
	_compound.add_child(_make("lights", Vector3(bounds.end.x + 3.0, 0, bounds.position.z - 4.0), -PI * 0.25))
	_compound.add_child(_make("skip", Vector3(gate.x + 6.0, 0, plot.end.z - 3.0), PI / 2.0))
	_compound.add_child(_make("mixer_small", Vector3(x0 + 7.5, 0, plot.position.z + 6.0)))
	var sx := plot.position.x + COMPOUND - 3.5
	var sz := plot.position.z + 4.0
	for s: Array in STACKS:
		var at := Vector3(sx, 0, sz)
		var n := _make(str(s[0]), at, 0.0, {"size": Vector3(1.2, 1.0, 1.0)})
		_compound.add_child(n)
		_stacks.append({"node": n, "stage": str(s[1]), "at": at + Vector3(1.2, 0, 0)})
		sz += 2.4
		if sz > plot.end.z - 4.0:
			sz = plot.position.z + 4.0
			sx -= 2.6


## Bays on all four faces, a lift at a time up to just over the building.
func _build_scaffold() -> void:
	var lo := Vector2(bounds.position.x - SCAFFOLD_GAP - 0.75, bounds.position.z - SCAFFOLD_GAP - 0.75)
	var hi := Vector2(bounds.end.x + SCAFFOLD_GAP + 0.75, bounds.end.z + SCAFFOLD_GAP + 0.75)
	_rows = maxi(1, ceili((bounds.end.y + 1.0) / LIFT))
	# Very large buildings: the facades only to keep the node count down.
	var faces := [[Vector2(lo.x, lo.y), Vector2(hi.x, lo.y)], [Vector2(hi.x, lo.y), Vector2(hi.x, hi.y)],
			[Vector2(hi.x, hi.y), Vector2(lo.x, hi.y)], [Vector2(lo.x, hi.y), Vector2(lo.x, lo.y)]]
	var perimeter := 2.0 * ((hi.x - lo.x) + (hi.y - lo.y))
	if perimeter / BAY * _rows > 900.0:
		_rows = ceili(900.0 * BAY / perimeter)
	for f: Array in faces:
		var p: Vector2 = f[0]
		var q: Vector2 = f[1]
		var n := maxi(1, floori(p.distance_to(q) / BAY))
		var dir := (q - p).normalized()
		var yaw := atan2(-dir.y, dir.x)
		for i in n:
			var c := p + dir * BAY * (i + 0.5)
			for row in _rows:
				var bay := _make("scaffold", Vector3(c.x, row * LIFT, c.y), yaw, {"size": Vector3(BAY, LIFT, 1.5)})
				bay.visible = false
				_root.add_child(bay)
				_bays.append({"node": bay, "row": row})


func _build_crew() -> void:
	for i in MAX_WORKERS:
		var w := Node3D.new()
		w.name = "Worker%d" % i
		var walking := _make("foreman" if i == 0 else "walker", Vector3.ZERO)
		walking.name = "Walking"
		w.add_child(walking)
		var working := _make("banksman" if i == 1 else "worker", Vector3.ZERO)
		working.name = "Working"
		w.add_child(working)
		_root.add_child(w)
		w.visible = false
		var home := _stack_point(i)
		w.position = home
		_workers.append({"node": w, "walk": walking, "work": working, "at": home, "to": home,
				"climb": 0.0, "state": "idle", "wait": randf_range(0.0, 3.0), "seed": i})


func _build_plant() -> void:
	for k in ["excavator", "tipper", "dumper", "mixer", "pump", "telehandler", "scissor"]:
		var n := _make(k, Vector3.ZERO)
		n.visible = false
		_root.add_child(n)
		_plant[k] = {"node": n, "phase": randf() * TAU, "t": 0.0, "leg": 0, "rig": PlantRig.new(n)}
	var lorry := _make("lorry", Vector3.ZERO)
	lorry.visible = false
	_root.add_child(lorry)
	_lorry = {"node": lorry, "state": "away", "t": 0.0}


## A tower crane tall enough to clear the building, at the corner behind it.
func _build_crane() -> void:
	crane = null
	var pick: Array = TOWERS[0]
	for t: Array in TOWERS:
		pick = t
		if float(t[1]) >= bounds.end.y + 12.0:
			break
	if not AssetLibrary.has(str(pick[0])):
		return
	var n := AssetLibrary.make(str(pick[0]))
	var rig := PlantRig.new(n)
	if not rig.has_stages(["slew", "trolley", "hook"]):
		n.free()
		return
	n.name = "TowerCrane"
	n.position = Vector3(bounds.end.x + 4.0, 0.0, bounds.position.z - 4.0)
	_root.add_child(n)
	crane = n
	_crane_rig = rig
	var local := bounds.get_center() - n.position
	_crane_yaw = atan2(-local.x, -local.z)
	_crane_reach = (rig.socket("trolley").z) * -1.0


# --- Each frame -----------------------------------------------------------------------

func _scan_active(day: float) -> void:
	_active.clear()
	for t: Dictionary in tasks:
		if float(t.start) > day:
			break
		if day < float(t.end):
			_active.append(t)
	_stage_now = PackedStringArray()
	for s: String in stages:
		if day >= float(stages[s][0]) and day < float(stages[s][1]):
			_stage_now.append(s)


func _stage_start(s: String) -> float:
	return float(stages[s][0]) if stages.has(s) else INF


func _stage_end(s: String) -> float:
	return float(stages[s][1]) if stages.has(s) else -INF


## The scaffold rises a lift at a time just ahead of the walls and frame, and comes down
## from the top once the roof (or the walls) are finished.
func _update_scaffold(day: float) -> void:
	var up := _stage_start("frame")
	up = minf(up, _stage_start("envelope"))
	var done := maxf(_stage_end("roof"), _stage_end("envelope"))
	if done == -INF:
		done = total
	var strike := 3.0  # days to take it down
	var top := bounds.end.y
	var built := 0.0
	if day >= up:
		for t: Dictionary in tasks:
			if float(t.start) > day:
				break
			if t.stage in ["frame", "floor", "envelope", "roof"]:
				built = maxf(built, (t.aabb as AABB).end.y if day >= float(t.end) else (t.aabb as AABB).position.y + 0.1)
	var rows_up := 0
	if day >= up and day < done + strike:
		rows_up = mini(_rows, ceili((built + 1.5) / LIFT))
		if day >= done:
			rows_up = mini(rows_up, ceili(_rows * (1.0 - (day - done) / strike)))
	if top <= 0.0:
		rows_up = 0
	for b: Dictionary in _bays:
		(b.node as Node3D).visible = int(b.row) < rows_up


func _update_workers(day: float, delta: float, cleared: bool) -> void:
	var want := 0 if cleared or day < 0.0 else clampi(3 + _active.size() * 2, 4, MAX_WORKERS)
	for i in _workers.size():
		var w: Dictionary = _workers[i]
		var node: Node3D = w.node
		node.visible = i < want
		if not node.visible:
			continue
		match str(w.state):
			"idle", "working":
				w.wait = float(w.wait) - delta
				if float(w.wait) <= 0.0:
					_next_job(w, i)
			"walking":
				var at: Vector3 = node.position
				var to: Vector3 = w.to
				var flat := Vector3(to.x, at.y, to.z)
				if at.y > 0.05 and Vector2(at.x, at.z).distance_to(Vector2(to.x, to.z)) > 0.3:
					# Down the scaffold first.
					node.position.y = maxf(0.0, at.y - CLIMB * delta)
				elif at.distance_to(flat) > 0.15:
					var step := (flat - at).normalized() * WALK * delta
					node.position = at + step if step.length() < at.distance_to(flat) else flat
					node.rotation.y = atan2(-(flat - at).x, -(flat - at).z)
				elif absf(at.y - to.y) > 0.05:
					node.position.y = move_toward(at.y, to.y, CLIMB * delta)
				else:
					w.state = "working"
					w.wait = randf_range(4.0, 9.0)
					if w.has("face"):
						node.rotation.y = float(w.face)
		var moving := str(w.state) == "walking"
		(w.walk as Node3D).visible = moving
		(w.work as Node3D).visible = not moving
		if moving:
			# A little bob in the stride.
			(w.walk as Node3D).position.y = absf(sin(_clock * 7.0 + float(w.seed))) * 0.04


## Off to a part being built (on the scaffold if it's up a storey), or back to a stack.
func _next_job(w: Dictionary, i: int) -> void:
	var node: Node3D = w.node
	var on_job := node.position.distance_to(_stack_point(i)) > 4.0
	if _active.is_empty() or on_job:
		w.to = _stack_point(i + int(_clock))
		w.erase("face")
	else:
		var t: Dictionary = _active[(i * 7 + int(_clock / 9.0)) % _active.size()]
		var box: AABB = t.aabb
		var spot := _edge_point(box, i)
		w.to = spot
		var c := box.get_center()
		w.face = atan2(-(c.x - spot.x), -(c.z - spot.z))
	w.state = "walking"


## A point on the ground beside stack `i`.
func _stack_point(i: int) -> Vector3:
	if _stacks.is_empty():
		return gate
	var s: Dictionary = _stacks[posmod(i, _stacks.size())]
	return (s.at as Vector3) + Vector3(0.6 * float(i % 3), 0, 0.5 * float(i % 2))


## Where to stand to work on `box`: inside it on the ground floor, else on the scaffold
## outside the nearest face at its height.
func _edge_point(box: AABB, i: int) -> Vector3:
	var c := box.get_center()
	var y := maxf(box.position.y, 0.0)
	var jitter := Vector3(float(i % 3) - 1.0, 0, float((i / 3) % 3) - 1.0) * 0.7
	if y < 0.5:
		var p := c + jitter
		p.y = 0.0
		return p
	var lo := bounds.position
	var hi := bounds.end
	var d := [c.x - lo.x, hi.x - c.x, c.z - lo.z, hi.z - c.z]
	var k := 0
	for j in 4:
		if d[j] < d[k]:
			k = j
	var out := SCAFFOLD_GAP
	var p := Vector3(clampf(c.x + jitter.x, lo.x, hi.x), y, clampf(c.z + jitter.z, lo.z, hi.z))
	match k:
		0: p.x = lo.x - out
		1: p.x = hi.x + out
		2: p.z = lo.z - out
		3: p.z = hi.z + out
	return p


func _update_plant(day: float, delta: float, cleared: bool) -> void:
	var s := _stage_now
	var digging := not cleared and ("site" in s or ("foundation" in s and day < _stage_start("foundation") + 1.0))
	var pouring := not cleared and ("foundation" in s or ("floor" in s and bounds.end.y < 4.0))
	var lifting := not cleared and ("frame" in s or "envelope" in s or "roof" in s or "floor" in s)
	var facade := not cleared and ("envelope" in s or "services" in s or "fitout" in s)
	# Digger: at the front of the plot, swinging between the dig and the tipper.
	var ex: Dictionary = _plant.excavator
	var exn: Node3D = ex.node
	exn.visible = digging
	if digging:
		exn.position = Vector3(bounds.get_center().x - 2.0, 0, bounds.end.z + 4.5)
		exn.rotation.y = PI
	var tip: Dictionary = _plant.tipper
	(tip.node as Node3D).visible = digging
	if digging:
		_shuttle(tip, gate + Vector3(0, 0, ROAD * 0.5), exn.position + Vector3(5.0, 0, 1.0), 14.0, delta)
	var dump: Dictionary = _plant.dumper
	(dump.node as Node3D).visible = digging or pouring
	if (dump.node as Node3D).visible:
		_shuttle(dump, _stack_point(0) + Vector3(2.5, 0, 0), Vector3(bounds.position.x - 3.0, 0, bounds.get_center().z), 6.0, delta)
	# Concrete: the mixer backed up to the pump beside the building.
	var pump: Node3D = _plant.pump.node
	var mixer: Node3D = _plant.mixer.node
	pump.visible = pouring
	mixer.visible = pouring
	if pouring:
		# Along the front, inside the hoarding; the mixer backs its chute up to the pump's hopper.
		pump.position = Vector3(bounds.end.x - 2.0, 0, bounds.end.z + 5.0)
		pump.rotation.y = -PI / 2.0
		mixer.position = pump.position + Vector3(-9.8, 0, 0)
		mixer.rotation.y = PI / 2.0
	# Telehandler: pallets from the stacks to the foot of the scaffold.
	var tele: Dictionary = _plant.telehandler
	(tele.node as Node3D).visible = lifting
	if lifting:
		var target := Vector3(bounds.position.x - 3.5, 0, bounds.position.z + bounds.size.z * (0.3 + 0.4 * sin(_clock * 0.05) * 0.5))
		_shuttle(tele, _stack_point(3) + Vector3(3.0, 0, 0), target, 5.0, delta)
	# Scissor lift: creeping along the front for the windows, cladding and services.
	var sc: Node3D = _plant.scissor.node
	sc.visible = facade and bounds.end.y > 2.0
	if sc.visible:
		var along := (sin(_clock * 0.03 + float(_plant.scissor.phase)) * 0.5 + 0.5) * bounds.size.x
		sc.position = Vector3(bounds.position.x + along, 0, bounds.end.z + SCAFFOLD_GAP + 3.0)
		sc.rotation.y = PI / 2.0


## The crane slews round to the parts being built and runs its trolley out over them.
func _update_crane(delta: float, cleared: bool) -> void:
	if crane == null:
		return
	crane.visible = not cleared
	var rig: RefCounted = _crane_rig
	var target := Vector3.ZERO
	var n := 0
	for t: Dictionary in _active:
		if t.stage in ["frame", "floor", "envelope", "roof"]:
			target += (t.aabb as AABB).get_center()
			n += 1
	if n == 0:
		# Nothing to lift: park over the material stacks.
		target = _stack_point(2)
	else:
		target /= n
	var local := crane.to_local(target)
	var want_yaw := atan2(-local.x, -local.z)
	var want_reach := clampf(Vector2(local.x, local.z).length(), -rig.socket("trolley_min").z, -rig.socket("trolley_max").z)
	_crane_yaw = lerp_angle(_crane_yaw, want_yaw, minf(1.0, delta * 0.6))
	_crane_reach = move_toward(_crane_reach, want_reach, delta * 2.5)
	var slew := PlantRig.turn(rig.socket("slew"), Vector3.UP, _crane_yaw)
	var run := PlantRig.shift(Vector3(0, 0, -_crane_reach - rig.socket("trolley").z))
	# The hook rises and falls a little as loads go up.
	var bob := PlantRig.shift(Vector3(0, sin(_clock * 0.4) * 1.5, 0))
	rig.pose({"slew": slew, "trolley": slew * run, "hook": slew * run * bob})


## The working parts: the digger's dig cycle, the mixer drum, the pump boom, the lift.
func _animate(delta: float) -> void:
	var ex: Dictionary = _plant.excavator
	if (ex.node as Node3D).visible:
		var r: RefCounted = ex.rig
		var c := _clock * 0.7 + float(ex.phase)
		var swing := PlantRig.turn(r.socket("slew"), Vector3.UP, sin(c * 0.5) * 1.1)
		var boom := swing * PlantRig.turn(r.socket("boom_pivot"), Vector3.RIGHT, 0.15 + sin(c) * 0.25)
		var stick := boom * PlantRig.turn(r.socket("stick_pivot"), Vector3.RIGHT, -0.2 + cos(c) * 0.45)
		var bucket := stick * PlantRig.turn(r.socket("bucket_pivot"), Vector3.RIGHT, sin(c + 1.0) * 0.8)
		r.pose({"upper": swing, "boom": boom, "stick": stick, "bucket": bucket})
		(ex.node as Node3D).rotation.y = PI
	var mx: Dictionary = _plant.mixer
	if (mx.node as Node3D).visible:
		var r: RefCounted = mx.rig
		var axis: Vector3 = r.socket("drum_axis") - r.socket("drum")
		if axis.length() > 0.01:
			r.pose({"drum": PlantRig.turn(r.socket("drum"), axis, _clock * 1.6)})
	var pm: Dictionary = _plant.pump
	if (pm.node as Node3D).visible:
		var r: RefCounted = pm.rig
		r.pose({"boom": PlantRig.turn(r.socket("slew"), Vector3.UP, sin(_clock * 0.2 + float(pm.phase)) * 0.35)})
	var sc: Dictionary = _plant.scissor
	if (sc.node as Node3D).visible:
		var r: RefCounted = sc.rig
		var top: float = r.socket("platform").y
		if top > 1.5:
			var h := lerpf(1.6, top, 0.5 + 0.5 * sin(_clock * 0.15 + float(sc.phase)))
			r.pose({"platform": PlantRig.shift(Vector3(0, h - top, 0)),
					"scissors": PlantRig.stretch_y(0.9, (h - 0.9) / (top - 0.9))})


## Drives `p` from `a` to `b`, waits, and back, over and over, facing where it goes.
func _shuttle(p: Dictionary, a: Vector3, b: Vector3, wait: float, delta: float) -> void:
	var n: Node3D = p.node
	var leg := int(p.leg)
	if not n.has_meta("placed"):
		n.position = a
		n.set_meta("placed", true)
	var to := b if leg == 0 else a
	var d := n.position.distance_to(to)
	if d > 0.2:
		var speed := DRIVE * 0.6
		var step := minf(speed * delta, d)
		var dir := (to - n.position).normalized()
		n.position += dir * step
		# Lorries and plant face -z: reverse into place on the way in, drive out forwards.
		var face := dir if leg == 1 else -dir
		n.rotation.y = atan2(-face.x, -face.z)
		p.t = 0.0
	else:
		p.t = float(p.t) + delta
		if float(p.t) >= wait:
			p.leg = 1 - leg
			p.t = 0.0


## A delivery every few build days while the building goes up: a lorry comes in from the
## road, through the gate to the stacks, waits to be unloaded, and drives away.
func _update_lorry(day: float, delta: float, cleared: bool) -> void:
	var n: Node3D = _lorry.node
	var road := gate + Vector3(0, 0, ROAD)
	var drop := Vector3(plot.position.x + COMPOUND + 3.0, 0, gate.z - 6.0)
	if day < _next_delivery - DELIVERY_EVERY * 2.0:
		_next_delivery = maxf(_stage_start("foundation"), day)
	match str(_lorry.state):
		"away":
			n.visible = false
			if not cleared and day >= _next_delivery and day < _stage_end("fitout"):
				_lorry.state = "in"
				_lorry.leg = 0
				n.position = road
				n.visible = true
				_next_delivery = day + DELIVERY_EVERY
		"in":
			if _drive(n, [road, gate, drop], int(_lorry.leg), delta):
				_lorry.leg = int(_lorry.leg) + 1
				if int(_lorry.leg) >= 2:
					_lorry.state = "unloading"
					_lorry.t = 0.0
		"unloading":
			_lorry.t = float(_lorry.t) + delta
			if float(_lorry.t) > 6.0:
				_lorry.state = "out"
				_lorry.leg = 0
		"out":
			if _drive(n, [drop, gate, road], int(_lorry.leg), delta):
				_lorry.leg = int(_lorry.leg) + 1
				if int(_lorry.leg) >= 2:
					_lorry.state = "away"


## One leg of a route; true when it reaches the end of that leg.
func _drive(n: Node3D, route: Array, leg: int, delta: float) -> bool:
	var to: Vector3 = route[mini(leg + 1, route.size() - 1)]
	var d := n.position.distance_to(to)
	if d < 0.3:
		return true
	var dir := (to - n.position).normalized()
	n.position += dir * minf(DRIVE * delta, d)
	n.rotation.y = atan2(-dir.x, -dir.z)
	return false


## What is on site now, for tests: {"workers": n, "scaffold": bays up, "plant": [names],
## "lorry": state, "compound": shown}.
func state() -> Dictionary:
	var workers := 0
	for w: Dictionary in _workers:
		if (w.node as Node3D).visible:
			workers += 1
	var bays := 0
	for b: Dictionary in _bays:
		if (b.node as Node3D).visible:
			bays += 1
	var plant: PackedStringArray = []
	for k: String in _plant:
		if (_plant[k].node as Node3D).visible:
			plant.append(k)
	return {"workers": workers, "scaffold": bays, "plant": plant, "lorry": str(_lorry.get("state", "")),
			"compound": _compound != null and _compound.visible}
