extends Node
## Walk-inside mode (BSX Ltd's WalkInside, beenster 18 Nov, repurposed for FredDibnah): the
## open building built round you at full size (WalkBuild), to walk through with the mouse and
## keyboard and get a feel for it, and to design in: what you change in here goes through
## BuildingSync, so the designer, the holotable and the rest of the crew follow.
##
##   WASD walk, Shift run, Space jump, mouse look, Esc back to the designer.
##   Q flies: no gravity, through the walls, WASD where you look, Space up, C down; Q again
##     to walk.
##   V: the architectural model look (white, ink edges, shadows) or the realistic one.
##   Tab: fittings, doors and windows and columns to take in hand, undo and redo.
##   Aim at a part: click to pick it up and click again to put it down, R turns it, X removes
##     it, E edits it (its material, section and kind).
##   Aim at a wall: F puts a door in it; the mouse wheel pushes it away or pulls it towards
##     you by a grid step (the walls meeting it and the rooms and floors on it follow).
##   Aim at the ceiling: the mouse wheel raises or lowers it (the storey's height).
##   Ctrl+Z undo, Ctrl+Y or Ctrl+Shift+Z redo.
## A part in your hands shows green where it fits and amber where it hits something, with
## the reason under the crosshair.
##
## The crew: everyone walking is a figure in their colour with their name over it, and their
## pointer is a dot in their colour where they aim, with a faint line from their eyes.
##
## Built in a world of its own (a SubViewport with its own World3D, sky, sun and physics),
## drawn over the whole screen, so nothing of the room it was opened from lights or touches it.

const T := preload("res://modules/ui/api/terminal_kit.gd")
const WalkBuild := preload("res://modules/walk/internal/walk_build.gd")
const WalkEdits := preload("res://modules/walk/internal/walk_edits.gd")
const WalkGuides := preload("res://modules/walk/internal/walk_guides.gd")
const WalkPalette := preload("res://modules/walk/internal/walk_palette.gd")
const AssetLibrary := preload("res://modules/assets/api/asset_library.gd")
const C := preload("res://modules/building/api/building_commands.gd")

const LAYER := WalkBuild.LAYER
## How far you can reach to design, m; flying, m.
const REACH := 8.0
const FLY_REACH := 40.0
## Families you can pick up and carry (point parts).
const CARRY := ["fixture", "column"]

## Walking speed, m/s.
@export var walk_speed := 3.0
## Running speed (Shift), m/s.
@export var run_speed := 6.0
## Jump speed, m/s.
@export var jump_speed := 4.2
## Gravity, m/s2.
@export var gravity := 9.8
## Flying (Q): how fast, m/s (Shift twice as fast).
@export var fly_speed := 6.0
## Mouse look, radians per pixel.
@export var look_speed := 0.003

var bus: Node  # WalkBus
var model: BuildingModel
var sync: BuildingSync
var builder: WalkBuild
var viewport: SubViewport
var world: Node3D
var body: CharacterBody3D
var camera: Camera3D
var hud: CanvasLayer
var sun: DirectionalLight3D
## A part in your hands: {type, id ("" for a new one), rot, opening (a door or window)}.
var holding: Dictionary = {}
## Flying (Q): no gravity, through the walls.
var flying := false
## Where the part in your hands would go now: {ok, at (Vector3), wall?, why}.
var spot: Dictionary = {}
## The part the edit rows (E) show, "" for the parts list.
var edit_id := ""
## In Edit: the kind picked in the CHANGE TO list (previewed, not yet changed to).
var edit_pick := ""
var _edit_filter := ""
var _kind_list: VBoxContainer
var _edit_preview: VBoxContainer
## Kinds shown in the CHANGE TO list at once; type to narrow a longer one.
const KIND_LIST_MAX := 150
## Shift+R and the wheel turn a part this many degrees (Alt: 1°).
const FREE_TURN := 15.0
## Hold R and move the mouse: degrees per pixel, the snap (Alt: none), and how far the mouse
## moves before it counts as a turn rather than a tap.
const R_DEG_PER_PX := 0.25
const R_SNAP := 5.0
const R_DEAD_PX := 3.0
var _r_hold := {}
## What Ctrl+C kept: {kind, fields}. Shared by every walk-inside view, as BSX's plan clipboard is.
static var clipboard := {}
var _r_turns := 0
## The crew walking about in here too: peer id -> {figure, dot, ray}.
var crew: Dictionary = {}
var _ghost: Node3D
var _ghost_key := ""
## The smart guides the part in your hands lines up on (magenta, through everything).
var _guides: MeshInstance3D
var _guides_key := ""
var _title: Label
var _where: Label
var _look: Label
## The help bar along the bottom (ui's HelpBar, the same on every screen): what you're doing
## and its keys on the left, passing messages on the right.
var help: HelpBar
var _palette: PanelContainer
var _palette_list: VBoxContainer
## The Tab menu: "objects" or "rooms", the filter text, which groups are open, the item picked
## for its preview.
var palette_tab := "objects"
var palette_filter := ""
var picked: Dictionary = {}
var _open_groups: Dictionary = {}
var _search: LineEdit
var _preview_box: VBoxContainer
var _groups_box: VBoxContainer
var _pitch := 0.0
var _aim_node: Node3D
var _me := 1
var _push_group := ""
var _push_target := ""
var _push_at := 0
var _push_n := 0
var _lamp_t := 0.0


func setup(walk_bus: Node, building: BuildingModel, building_sync: BuildingSync, start: Dictionary = {}) -> void:
	bus = walk_bus
	model = building
	sync = building_sync
	name = "WalkInside"
	_add_view()
	_add_sky()
	_add_ground()
	builder = WalkBuild.new()
	world.add_child(builder)
	builder.bind(model)
	_add_player()
	_add_hud()
	model.changed.connect(_on_changed)
	var design := Modules.bus("design")
	if design and design.has_signal("palette_changed"):
		design.connect("palette_changed", _on_palette_changed)
	spawn(start)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_join_crew()


func _exit_tree() -> void:
	var design := Modules.bus("design")
	if design and design.has_signal("palette_changed") and design.is_connected("palette_changed", _on_palette_changed):
		design.disconnect("palette_changed", _on_palette_changed)
	if _search and is_instance_valid(_search) and not _search.is_inside_tree():
		_search.free()
	if model and model.changed.is_connected(_on_changed):
		model.changed.disconnect(_on_changed)
	_drop_holding()
	_leave_crew()


# Walking about together: this player's walk and pointer stream to the crew as movers under
# their own "player:<id>:" ids (so they always drive them); everyone else in walk-inside
# shows here as a figure in their colour, their name over it and their pointer where they aim.

func _join_crew() -> void:
	var net: MultiplayerBus = bus.call("net")
	_me = int(bus.call("local_peer"))
	if net:
		net.register_mover(WalkBusRef.BODY % _me, body)
		net.register_mover(WalkBusRef.AIM % _me, _aim_node)
	bus.connect("walkers_changed", _sync_crew)
	bus.call("set_state", true, flying)
	_sync_crew()


func _leave_crew() -> void:
	if bus == null:
		return
	if bus.is_connected("walkers_changed", _sync_crew):
		bus.disconnect("walkers_changed", _sync_crew)
	var net: MultiplayerBus = bus.call("net")
	if net:
		net.unregister_mover(WalkBusRef.BODY % _me)
		net.unregister_mover(WalkBusRef.AIM % _me)
	bus.call("set_state", false, false)
	crew.clear()


func _sync_crew() -> void:
	if world == null:
		return
	var walkers: Dictionary = bus.get("walkers")
	for peer: int in crew.keys():
		if not walkers.has(peer):
			for k: String in ["figure", "dot", "ray"]:
				(crew[peer][k] as Node).queue_free()
			crew.erase(peer)
	for peer: int in walkers:
		if peer == _me or crew.has(peer):
			continue
		var w: Dictionary = walkers[peer]
		var colour: Color = w.get("colour", Color.WHITE)
		var fig := crew_figure(str(w.get("name", "Player")), colour)
		fig.name = "Crew_%d" % peer
		world.add_child(fig)
		var dot := pointer_dot(colour)
		dot.name = "Pointer_%d" % peer
		dot.visible = false
		world.add_child(dot)
		var ray := MeshInstance3D.new()
		ray.name = "PointerRay_%d" % peer
		ray.mesh = ImmediateMesh.new()
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.albedo_color = Color(colour.r, colour.g, colour.b, 0.35)
		ray.material_override = rm
		ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(ray)
		crew[peer] = {"figure": fig, "dot": dot, "ray": ray}


## A crewmate in walk-inside (BSX crew_figure): a figure in their colour, a visor, their name
## over their head. Its origin is their feet.
static func crew_figure(player: String, colour: Color) -> Node3D:
	var fig := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.8
	mi.mesh = cap
	mi.position.y = 0.9
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.6
	mi.material_override = m
	fig.add_child(mi)
	var visor := MeshInstance3D.new()
	var vb := BoxMesh.new()
	vb.size = Vector3(0.34, 0.12, 0.08)
	visor.mesh = vb
	var vm := StandardMaterial3D.new()
	vm.albedo_color = Color(0.1, 0.12, 0.14)
	vm.emission_enabled = true
	vm.emission = colour * 0.6
	visor.material_override = vm
	visor.position = Vector3(0, 1.52, -0.27)
	fig.add_child(visor)
	var tag := Label3D.new()
	tag.name = "Name"
	tag.text = player
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.font_size = 40
	tag.pixel_size = 0.005
	tag.modulate = colour
	tag.outline_size = 8
	tag.position = Vector3(0, 2.1, 0)
	fig.add_child(tag)
	return fig


## Another player's pointer: a glowing dot in their colour, seen through walls.
static func pointer_dot(colour: Color) -> MeshInstance3D:
	var dot := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.06
	s.height = 0.12
	dot.mesh = s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	m.albedo_color = colour
	dot.material_override = m
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return dot


func _update_crew() -> void:
	for peer: int in crew:
		var c: Dictionary = crew[peer]
		var pb: Node3D = bus.call("proxy_body", peer)
		var pa: Node3D = bus.call("proxy_aim", peer)
		if pb == null:
			continue
		var fig: Node3D = c.figure
		fig.position = pb.position - Vector3(0, 0.9, 0)
		fig.rotation.y = pb.rotation.y
		var dot: MeshInstance3D = c.dot
		var ray: MeshInstance3D = c.ray
		var im: ImmediateMesh = ray.mesh
		im.clear_surfaces()
		var aiming := pa != null and pa.position.y > float(WalkBusRef.NO_AIM.y) * 0.5
		dot.visible = aiming
		if aiming:
			dot.position = pa.position
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			im.surface_add_vertex(pb.position + Vector3(0, 0.6, 0))
			im.surface_add_vertex(pa.position)
			im.surface_end()


## The crew's ids for the movers (kept in step with WalkBus).
class WalkBusRef:
	const BODY := "player:%d:walk"
	const AIM := "player:%d:walkaim"
	const NO_AIM := Vector3(0, -10000, 0)


# Where you are

## Puts you at start {at (feet), yaw}, else outside the front door facing in, else in the
## first room on the ground floor, else in front of the building.
func spawn(start: Dictionary = {}) -> void:
	var at := Vector3(0, 0, 6)
	var face := Vector3(0, 0, -1)
	if start.has("at"):
		at = start.at
		face = Vector3(-sin(float(start.get("yaw", 0.0))), 0, -cos(float(start.get("yaw", 0.0))))
	else:
		var found := false
		for pid in model.parts_of_family("opening"):
			var e: Dictionary = model.parts[pid]
			if str(e.kind) == "door_external" and model.level_of(pid) == 0:
				var pts := model.points_of(pid)
				var mid := (pts[0] + pts[1]) / 2.0
				var along := (pts[1] - pts[0]).normalized()
				var n := Vector3(-along.z, 0, along.x)
				var centre := _centre()
				if n.dot(mid - centre) < 0.0:
					n = -n
				at = mid + n * 2.0
				face = -n
				found = true
				break
		if not found and not model.rooms_on(0).is_empty():
			var r: Dictionary = model.rooms[model.rooms_on(0)[0]]
			var c := Vector2.ZERO
			for p: Array in r.outline:
				c += Vector2(float(p[0]), float(p[1]))
			c /= maxf(float((r.outline as Array).size()), 1.0)
			at = Vector3(c.x, 0.0, c.y)
			var mid2 := _centre()
			face = Vector3(mid2.x - c.x, 0, mid2.z - c.y)
			if face.length() < 0.1:
				face = Vector3(0, 0, -1)
			found = true
		if not found and not model.parts.is_empty():
			var box := _bounds()
			at = Vector3(box.get_center().x, 0.0, box.end.z + 5.0)
			face = Vector3(0, 0, -1)
	body.position = at + Vector3(0, 0.95, 0)
	body.velocity = Vector3.ZERO
	body.rotation.y = atan2(-face.x, -face.z)
	_pitch = 0.0
	camera.rotation.x = 0.0


func _bounds() -> AABB:
	var box := AABB()
	var first := true
	for pid: String in model.parts:
		var b := model.aabb_of(pid)
		if b.size == Vector3.ZERO and b.position == Vector3.ZERO:
			continue
		box = b if first else box.merge(b)
		first = false
	return box


func _centre() -> Vector3:
	var c := _bounds().get_center()
	return Vector3(c.x, 0, c.z)


## Your feet, world m (the crew's figures stand there).
func feet() -> Vector3:
	return body.position - Vector3(0, 0.9, 0)


func yaw() -> float:
	return body.rotation.y


## Where you aim, world m, or null for nothing in reach.
func aim_point() -> Variant:
	var a := aim()
	return a.point if not a.is_empty() else null


## The level you're on and the room you're in ("" outside).
func where() -> Dictionary:
	var level := WalkEdits.level_at(model, feet().y)
	return {"level": level, "room": WalkEdits.room_at(model, level, Vector2(body.position.x, body.position.z))}


func look(relative: Vector2) -> void:
	body.rotation.y -= relative.x * look_speed
	_pitch = clampf(_pitch - relative.y * look_speed, -1.45, 1.45)
	camera.rotation.x = _pitch


## What you're looking at within reach: {info (the "walk" meta), point, normal, collider},
## or {} for nothing.
func aim() -> Dictionary:
	if camera == null or not camera.is_inside_tree():
		return {}
	var from := camera.global_position
	var to := from - camera.global_basis.z * (FLY_REACH if flying else REACH)
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER, [body.get_rid()])
	var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not (hit.collider as Object).has_meta("walk"):
		return {}
	return {"info": (hit.collider as Object).get_meta("walk"), "point": hit.position as Vector3,
			"normal": hit.normal as Vector3, "collider": hit.collider}


## The part you're aiming at ("" for none, the ground or a room's stand-in floor).
func aimed_part() -> String:
	var a := aim()
	if a.is_empty() or str(a.info.kind) != "part":
		return ""
	return str(a.info.id)


# Designing from inside

func is_palette_open() -> bool:
	return _palette != null and _palette.visible


func toggle_palette() -> void:
	_palette.visible = not _palette.visible
	if not _palette.visible:
		edit_id = ""
	else:
		_fill_palette()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _palette.visible else Input.MOUSE_MODE_CAPTURED


## Takes a new part of `kind` in your hands (a door or window goes in the wall you aim at).
func take_new(kind: String) -> void:
	_drop_holding()
	holding = {"type": kind, "id": "", "rot": 0.0, "opening": model.catalog.family_of(kind) == "opening"}
	if is_palette_open():
		toggle_palette()


## Picks up a placed part to move it (others can't edit it while you hold it).
func pick_up(part_id: String) -> bool:
	var e: Dictionary = model.parts.get(part_id, {})
	if e.is_empty() or not model.catalog.family_of(str(e.kind)) in CARRY:
		return false
	var net: MultiplayerBus = bus.call("net")
	if net and net.claim_owner(part_id) != 0 and net.claim_owner(part_id) != _me:
		return false
	_drop_holding()
	holding = {"type": str(e.kind), "id": part_id, "rot": float(e.get("rot", 0.0)), "opening": false}
	if net:
		net.claim(part_id)
	return true


func _drop_holding() -> void:
	if holding.is_empty():
		return
	var id := str(holding.get("id", ""))
	holding = {}
	var net: MultiplayerBus = bus.call("net") if bus else null
	if id != "" and net:
		net.release(id)


## Puts the part in your hands down where you're aiming. Returns true if it went down.
func put_down() -> bool:
	_update_spot()
	if holding.is_empty() or not spot.has("at"):
		return false
	var op := {}
	if holding.has("module"):
		var kits := Modules.bus("kits")
		var at: Vector3 = spot.at
		var level := WalkEdits.level_at(model, at.y)
		var ops: Variant = kits.call("place_ops", model, str(holding.module), level, Vector3(at.x, 0.0, at.z), float(holding.rot)) if kits else []
		if not ops is Array or (ops as Array).is_empty():
			return false
		sync.edit(C.batch(ops))
		_drop_holding()
		return true
	if bool(holding.opening):
		op = WalkEdits.opening_at(model, str(spot.get("wall", "")), spot.at, str(holding.type))
	elif str(holding.id) == "":
		op = WalkEdits.place(model, str(holding.type), spot.at, float(holding.rot), false)
	else:
		op = WalkEdits.move_to(model, str(holding.id), spot.at, float(holding.rot), false)
	if op.is_empty():
		return false
	if holding.has("copy") and op.has("entry"):
		for f: String in holding.copy:
			if f != "rot":
				op.entry[f] = holding.copy[f]
	sync.edit(op)
	_drop_holding()
	return true


## Ctrl+C: the part you're editing or aim at (its kind, size, angle, material and section) is
## kept to paste. False if nothing.
func copy_aimed() -> bool:
	var id := edit_id if edit_id != "" and is_palette_open() else aimed_part()
	var e: Dictionary = model.parts.get(id, {})
	var fam := model.catalog.family_of(str(e.get("kind", "")))
	if e.is_empty() or not (e.has("at") or fam == "opening"):
		_status("Aim at a fitting, column, door or window to copy it")
		return false
	var keep := {}
	for f: String in ["material", "section", "w", "d", "height", "h", "sill", "rot"]:
		if e.has(f):
			keep[f] = e[f]
	clipboard = {"kind": str(e.kind), "fields": keep}
	_status("Copied the %s: Ctrl+V puts one in your hands" % str(model.catalog.kind(str(e.kind)).get("label", "part")).to_lower())
	return true


## Ctrl+V: a copy of what you copied in your hands, the same size, angle and material, to put
## down with the guides like any part. Each Ctrl+V another.
func paste() -> bool:
	if clipboard.is_empty() or not model.catalog.has_kind(str(clipboard.kind)):
		_status("Nothing copied: aim at a part and press Ctrl+C")
		return false
	take_new(str(clipboard.kind))
	holding["copy"] = (clipboard.fields as Dictionary).duplicate()
	holding.rot = float(clipboard.fields.get("rot", 0.0))
	return true


## The part in your hands as an entry: the one you picked up, a copy's fields, else {}.
func _held_entry() -> Dictionary:
	if holding.has("copy"):
		return holding.copy
	return model.parts.get(str(holding.get("id", "")), {})


## R: turns the part in your hands, else the one you aim at, a quarter (or `by` degrees:
## Shift+R and the wheel 15°, with Alt 1°).
func turn(by := 90.0) -> void:
	if not holding.is_empty():
		holding.rot = snappedf(fposmod(float(holding.rot) + by, 360.0), 0.001)
		return
	var op := WalkEdits.turn(model, aimed_part(), by)
	if not op.is_empty():
		sync.edit(op)


## R down: a tap (let go without moving the mouse) turns a quarter; held, moving the mouse
## sideways turns what you hold or aim at, R_DEG_PER_PX, snapped to R_SNAP unless Alt is held
## (as the designer does). The aimed part's turn is one undo step.
func r_press() -> void:
	var id := "" if not holding.is_empty() else aimed_part()
	var start := float(holding.rot) if not holding.is_empty() else float(model.parts.get(id, {}).get("rot", 0.0))
	if holding.is_empty() and (id == "" or not model.parts[id].has("at")):
		_r_hold = {}
		return
	_r_turns += 1
	_r_hold = {"id": id, "start": start, "px": 0.0, "dragged": false, "group": "walk.rturn.%d" % _r_turns}


## Mouse moved `dx` px with R held.
func r_drag(dx: float, free: bool) -> void:
	if _r_hold.is_empty():
		return
	_r_hold.px = float(_r_hold.px) + dx
	if not bool(_r_hold.dragged) and absf(float(_r_hold.px)) < R_DEAD_PX:
		return
	_r_hold.dragged = true
	var rot := float(_r_hold.start) + float(_r_hold.px) * R_DEG_PER_PX
	if not free:
		rot = snappedf(rot, R_SNAP)
	rot = snappedf(fposmod(rot, 360.0), 0.001)
	if str(_r_hold.id) == "":
		if not holding.is_empty():
			holding.rot = rot
		return
	if not model.parts.has(str(_r_hold.id)) or is_equal_approx(float(model.parts[str(_r_hold.id)].get("rot", 0.0)), rot):
		return
	sync.edit(WalkEdits.resize(model, str(_r_hold.id), "rot", rot), str(_r_hold.group))


## R up: a quarter turn if the mouse didn't move.
func r_release() -> void:
	var was := _r_hold
	_r_hold = {}
	if was.is_empty() or bool(was.dragged):
		return
	turn(90.0)


## Whether R is held for a mouse turn (the help bar says so).
func r_turning() -> bool:
	return not _r_hold.is_empty() and bool(_r_hold.dragged)


## The free turn step: 15°, or 1° with Alt.
static func _fine_step(alt: bool) -> float:
	return 1.0 if alt else FREE_TURN


## X: removes the part you aim at.
func remove_aimed() -> bool:
	var id := aimed_part()
	if id == "":
		return false
	sync.edit(C.delete([id]))
	return true


## F: a door in the wall you're aiming at. Returns true if it asked for one.
func door_here(kind := "door_internal") -> bool:
	var a := aim()
	if a.is_empty() or str(a.info.kind) != "part" or str(a.info.family) != "wall":
		return false
	var op := WalkEdits.opening_at(model, str(a.info.id), a.point, kind)
	if op.is_empty():
		return false
	sync.edit(op)
	return true


## The mouse wheel: pushes the wall you aim at away from you (steps > 0) or pulls it towards
## you by grid steps; on a ceiling, raises or lowers it. Returns true if it asked for a change.
func push(steps: int) -> bool:
	var a := aim()
	if a.is_empty() or str(a.info.kind) != "part":
		return false
	var id := str(a.info.id)
	var fam := str(a.info.family)
	var by := WalkEdits.grid(model) * steps
	var op := {}
	if fam == "wall":
		op = WalkEdits.push_wall(model, id, camera.global_position, by)
	elif fam in ["slab", "roof"] and (a.normal as Vector3).y < -0.5:
		# A ceiling over you: the storey under it (a floor slab is its level's floor, so the
		# storey below; a roof covers its own level).
		var level := maxi(model.level_of(id) - 1, 0) if fam == "slab" else model.level_of(id)
		id = "level:%d" % level
		op = WalkEdits.push_ceiling(model, level, by)
	if op.is_empty():
		return false
	# A run of wheel steps on the same thing is one undo.
	var now := Time.get_ticks_msec()
	if id != _push_target or now - _push_at > 1500:
		_push_n += 1
		_push_target = id
		_push_group = "walk-push-%d-%d" % [_me, _push_n]
	_push_at = now
	sync.edit(op, _push_group)
	return true


## E: the edit rows for the part you aim at.
func edit_aimed() -> bool:
	var id := aimed_part()
	if id == "":
		return false
	edit_id = id
	edit_pick = ""
	_edit_filter = ""
	if not is_palette_open():
		toggle_palette()
		edit_id = id
	_fill_palette()
	return true


## V: the architectural model look or the realistic one (the Graphics "Look" option).
func toggle_look() -> void:
	GraphicsOptions.set_value("art_style", ArtStyle.MODEL if ArtStyle.realistic() else ArtStyle.REALISTIC)
	GraphicsOptions.save_settings()
	var g := get_node_or_null("/root/Graphics")
	if g:
		g.call("apply_all")
	_apply_look()


func toggle_fly() -> void:
	flying = not flying
	body.collision_mask = 0 if flying else LAYER
	body.velocity = Vector3.ZERO
	bus.call("set_state", true, flying)


## A left click: put down what you hold, or pick up the part you aim at.
func click() -> void:
	if not holding.is_empty():
		put_down()
		return
	pick_up(aimed_part())


# Input and frames

func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_R and not (event as InputEventKey).pressed \
			and not _r_hold.is_empty():
		r_release()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and not _r_hold.is_empty():
		r_drag((event as InputEventMouseMotion).relative.x, Input.is_key_pressed(KEY_ALT) or (event as InputEventMouseMotion).alt_pressed)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		if not is_palette_open() and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless"):
			look((event as InputEventMouseMotion).relative)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if is_palette_open():
			return  # the palette's buttons take it
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				if DisplayServer.get_name() != "headless":
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				click()
			MOUSE_BUTTON_RIGHT:
				_drop_holding()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				var up := (event as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_UP
				# Holding a part, or Shift on one you aim at: the wheel turns it.
				if (not holding.is_empty() and not bool(holding.opening)) or (event as InputEventMouseButton).shift_pressed:
					turn(_fine_step((event as InputEventMouseButton).alt_pressed) * (1.0 if up else -1.0))
				else:
					push(1 if up else -1)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and not Keys.typing():
		var k := event as InputEventKey
		var vp := get_viewport()
		var handled := true
		match k.physical_keycode:
			KEY_TAB:
				toggle_palette()
			KEY_ESCAPE:
				if is_palette_open():
					toggle_palette()
				elif not holding.is_empty():
					_drop_holding()
				else:
					bus.call("close")
			KEY_R:
				if k.shift_pressed:
					turn(_fine_step(k.alt_pressed))
				else:
					r_press()
			KEY_X, KEY_DELETE:
				remove_aimed()
			KEY_F:
				door_here()
			KEY_E:
				edit_aimed()
			KEY_Q:
				toggle_fly()
			KEY_C when k.ctrl_pressed:
				copy_aimed()
			KEY_V when k.ctrl_pressed:
				paste()
			KEY_V:
				toggle_look()
			KEY_Z:
				if k.ctrl_pressed:
					sync.redo() if k.shift_pressed else sync.undo()
				else:
					handled = false
			KEY_Y:
				if k.ctrl_pressed:
					sync.redo()
				else:
					handled = false
			_:
				handled = false
		if handled and vp:
			vp.set_input_as_handled()


func _physics_process(delta: float) -> void:
	if body == null:
		return
	var move := Vector2.ZERO if is_palette_open() else _axis(Keys.LEFT, Keys.RIGHT, Keys.FORWARD, Keys.BACK)
	var running := InputMap.has_action(Keys.RUN) and Input.is_action_pressed(Keys.RUN)
	if flying:
		_fly(move, running)
		return
	var dir := body.global_basis * Vector3(move.x, 0, move.y)
	dir.y = 0.0
	dir = dir.normalized() * minf(move.length(), 1.0)
	var speed := run_speed if running else walk_speed
	body.velocity.x = dir.x * speed
	body.velocity.z = dir.z * speed
	if body.is_on_floor():
		body.velocity.y = 0.0
		if InputMap.has_action(Keys.JUMP) and Input.is_action_just_pressed(Keys.JUMP) and not is_palette_open():
			body.velocity.y = jump_speed
	else:
		body.velocity.y -= gravity * delta
	body.move_and_slide()
	if body.position.y < -30.0:
		spawn()


## Flying: where you look, Space up and C down, through the walls.
func _fly(move: Vector2, running: bool) -> void:
	var dir := camera.global_basis * Vector3(move.x, 0, move.y)
	var up := 0.0
	if not is_palette_open():
		if InputMap.has_action(Keys.JUMP) and Input.is_action_pressed(Keys.JUMP):
			up += 1.0
		if Input.is_physical_key_pressed(KEY_C):
			up -= 1.0
	dir += Vector3.UP * up
	if dir.length() > 1.0:
		dir = dir.normalized()
	body.velocity = dir * fly_speed * (2.0 if running else 1.0)
	body.move_and_slide()


func _process(delta: float) -> void:
	if body == null:
		return
	var near: Array[Vector3] = [feet()]
	var walkers: Dictionary = bus.get("walkers")
	for peer: int in crew:
		var pb: Node3D = bus.call("proxy_body", peer)
		if pb:
			near.append(pb.position - Vector3(0, 0.9, 0))
	builder.update_doors(near, delta)
	_lamp_t -= delta
	if _lamp_t <= 0.0:
		_lamp_t = 0.25
		builder.update_lamps(camera.global_position)
	_update_spot()
	_update_ghost()
	_update_crew()
	var ap: Variant = aim_point()
	_aim_node.position = ap if ap is Vector3 else WalkBusRef.NO_AIM
	if _where == null:
		return
	var w := where()
	var room_name := "Outside"
	if str(w.room) != "":
		room_name = _room_name(str(w.room))
	_title.text = "WALK-INSIDE   %s" % model.name.to_upper()
	var lv: Dictionary = model.levels[clampi(int(w.level), 0, model.level_count() - 1)]
	_where.text = "%s   %s%s" % [str(lv.get("name", "Level %d" % int(w.level))).to_upper(), room_name.to_upper(),
			"   FLYING" if flying else ""]
	_show_help(_aim_text())
	if walkers.size() > 1:
		_where.text += "   %d WALKING" % walkers.size()


func _aim_text() -> String:
	if r_turning():
		var r := float(holding.rot) if str(_r_hold.id) == "" else float(model.parts.get(str(_r_hold.id), {}).get("rot", 0.0))
		return "Turning  %.1f°\n[b]Move the mouse[/b] to turn   [b]Alt[/b] free (no 5° snap)   let go of [b]R[/b] to set it" % r
	if is_palette_open() and edit_id != "":
		return "Editing %s\n[b]-[/b] [b]+[/b] or type a size and [b]Enter[/b]   pick from [b]Change to[/b] to swap it   [b]Ctrl+Z[/b] undo   [b]Esc[/b] close" % str(model.catalog.kind(str(model.parts.get(edit_id, {}).get("kind", ""))).get("label", "part"))
	if is_palette_open():
		return "Parts menu\n[b]Type[/b] to filter   [b]Click[/b] a group to open it, an item to see it, [b]Take[/b] to hold it   [b]Tab[/b] or [b]Esc[/b] close"
	if not holding.is_empty():
		var label := str(holding.get("label", model.catalog.kind(str(holding.type)).get("label", holding.type)))
		return "%s: %s\n[b]Click[/b] put down   [b]R[/b] quarter turn, hold [b]R[/b] + mouse to turn   [b]Wheel[/b] 15° ([b]Alt[/b] 1°, no guides)   [b]Right-click[/b] or [b]Esc[/b] drop" % [label, str(spot.get("why", "Aim at a floor"))]
	var a := aim()
	if a.is_empty():
		return "Flying\n[b]WASD[/b] move   [b]Space[/b] up   [b]C[/b] down   [b]Q[/b] walk   [b]Tab[/b] parts" if flying else "Walking\n[b]WASD[/b] walk   [b]Shift[/b] run   [b]Space[/b] jump   [b]Q[/b] fly   [b]Tab[/b] parts   [b]Esc[/b] back to the designer"
	if str(a.info.kind) != "part":
		return "Floor\n[b]Tab[/b] parts to place   [b]Q[/b] fly   [b]V[/b] model or real look"
	var id := str(a.info.id)
	var e: Dictionary = model.parts.get(id, {})
	var label2 := str(model.catalog.kind(str(e.get("kind", ""))).get("label", e.get("kind", "Part")))
	var fam := str(a.info.family)
	var net: MultiplayerBus = bus.call("net")
	var owner := net.claim_owner(id) if net else 0
	var held := "   (%s has it)" % net.player_name(owner) if owner != 0 and owner != _me else ""
	match fam:
		"wall":
			return "%s%s\n[b]Wheel[/b] push it away or pull it towards you   [b]F[/b] door here   [b]E[/b] edit   [b]X[/b] remove" % [label2, held]
		"fixture", "column":
			return "%s%s\n[b]Click[/b] pick up   [b]R[/b] turn (hold + mouse)   [b]Shift+wheel[/b] 15°   [b]E[/b] edit   [b]Ctrl+C[/b] copy   [b]X[/b] remove" % [label2, held]
		"slab", "roof":
			if (a.normal as Vector3).y < -0.5:
				return "Ceiling (%.2f m storey)\n[b]Wheel[/b] raise or lower it   [b]E[/b] edit" % model.level_height(maxi(model.level_of(id) - (1 if fam == "slab" else 0), 0))
			return "%s\n[b]Tab[/b] parts   [b]E[/b] edit" % label2
	return "%s%s\n[b]E[/b] edit   [b]X[/b] remove" % [label2, held]


static func _axis(neg_x: String, pos_x: String, neg_y: String, pos_y: String) -> Vector2:
	for a in [neg_x, pos_x, neg_y, pos_y]:
		if not InputMap.has_action(a):
			return Vector2.ZERO
	return Input.get_vector(neg_x, pos_x, neg_y, pos_y)


func _on_palette_changed() -> void:
	if is_palette_open() and edit_id == "":
		_fill_list()


func _on_changed(_op: Dictionary) -> void:
	if not holding.is_empty() and str(holding.id) != "" and not model.parts.has(str(holding.id)):
		_drop_holding()
	if is_palette_open():
		_fill_palette()


func _room_name(rid: String) -> String:
	var r: Dictionary = model.rooms[rid]
	if str(r.get("name", "")) != "":
		return str(r.name)
	return str(model.catalog.room_type(str(r.type)).get("label", r.type))


## Where the part in your hands would go: on the floor you aim at (a door or window in the
## wall), and whether it hits anything.
func _update_spot() -> void:
	spot = {}
	if holding.is_empty():
		return
	var a := aim()
	if a.is_empty():
		spot = {"why": "Aim at a wall" if bool(holding.opening) else "Aim at a floor"}
		return
	var p: Vector3 = a.point
	if bool(holding.opening):
		if str(a.info.kind) != "part" or str(a.info.family) != "wall":
			spot = {"why": "Aim at a wall"}
			return
		var op := WalkEdits.opening_at(model, str(a.info.id), p, str(holding.type))
		spot = {"at": p, "wall": str(a.info.id), "ok": not op.is_empty(),
				"why": "Fits" if not op.is_empty() else "No room in this wall"}
		if not op.is_empty():
			spot["t"] = float(op.entry.t)
		return
	if (a.normal as Vector3).y < 0.7:
		spot = {"why": "Aim at a floor"}
		return
	var g := WalkEdits.grid(model)
	var at := Vector3(WalkEdits.snap(p.x, g), p.y, WalkEdits.snap(p.z, g))
	spot = {"at": at, "ok": true, "why": "Fits"}
	if holding.has("module"):
		return
	var held_size := WalkEdits.size_of(model, str(holding.type), _held_entry())
	var hw := held_size.x * 0.5
	var hd := held_size.z * 0.5
	var half := WalkEdits.turned_half(hw * 2.0, hd * 2.0, float(holding.rot))
	hw = half.x
	hd = half.y
	var level := WalkEdits.level_at(model, at.y)
	# Smart guides (BSX): edges and middles line up with the parts and walls round it.
	if not Input.is_key_pressed(KEY_ALT):
		var al := WalkGuides.align_at(model, level, at, Vector2(hw * 2.0, hd * 2.0), str(holding.id))
		at += Vector3(al.offset.x, 0, al.offset.y)
		spot.at = at
		spot["guides"] = al.guides
	var box := AABB(at + Vector3(-hw, 0.02, -hd), Vector3(hw * 2.0, maxf(held_size.y - 0.04, 0.1), hd * 2.0)).grow(-0.02)
	for pid in model.parts_on(level):
		if pid == str(holding.id):
			continue
		var fam := model.catalog.family_of(str(model.parts[pid].kind))
		if not fam in ["fixture", "column", "wall"]:
			continue
		if fam == "wall" and not _wall_hits(pid, box):
			continue
		if fam != "wall" and not model.aabb_of(pid).intersects(box):
			continue
		spot.ok = false
		spot.why = "Hits the %s" % str(model.catalog.kind(str(model.parts[pid].kind)).get("label", "part")).to_lower()
		return


## Whether a wall (as a thick line in plan) runs through a box.
func _wall_hits(wall_id: String, box: AABB) -> bool:
	var e: Dictionary = model.parts[wall_id]
	var a := Vector2(float(e.a[0]), float(e.a[2]))
	var b := Vector2(float(e.b[0]), float(e.b[2]))
	var half := float(model.catalog.section(str(e.get("section", ""))).get("d", 0.2)) * 0.5
	var c := Vector2(box.get_center().x, box.get_center().z)
	var q := Geometry2D.get_closest_point_to_segment(c, a, b)
	var r := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z)).grow(half)
	return r.has_point(q)


## The part in your hands, where it would go: green for a good spot, amber if not.
func _update_ghost() -> void:
	_update_guides()
	var state := "hand" if not spot.has("at") else str(spot.get("ok", false))
	var key := "" if holding.is_empty() else "%s/%s/%s" % [holding.type, holding.get("module", ""), state]
	if key != _ghost_key:
		_ghost_key = key
		if _ghost:
			_ghost.queue_free()
			_ghost = null
		if key != "":
			_ghost = _make_ghost(state)
	if _ghost == null:
		return
	_ghost.visible = true
	if not spot.has("at"):
		_hold_in_view()
		return
	_ghost.scale = Vector3.ONE
	if bool(holding.opening):
		var wall: Dictionary = model.parts.get(str(spot.wall), {})
		if wall.is_empty() or not spot.has("t"):
			_hold_in_view()
			return
		var a := Vector3(float(wall.a[0]), 0, float(wall.a[2]))
		var b := Vector3(float(wall.b[0]), 0, float(wall.b[2]))
		var dir := (b - a).normalized()
		var spec := model.catalog.kind(str(holding.type))
		var at := a + dir * float(spot.t) + Vector3(0, model.level_elevation(int(wall.level)) + float(spec.get("sill", 0.0)), 0)
		_ghost.position = at
		_ghost.rotation = Vector3(0, -Vector2(dir.x, dir.z).angle(), 0)
		return
	_ghost.position = spot.at
	_ghost.rotation = Vector3(0, deg_to_rad(float(holding.rot)), 0)


## Draws the spot's smart guides (rebuilt only when they change).
func _update_guides() -> void:
	var guides: Array = spot.get("guides", [])
	var key := str(guides) if spot.has("at") else ""
	if key == _guides_key:
		return
	_guides_key = key
	if _guides == null:
		_guides = MeshInstance3D.new()
		_guides.name = "Guides"
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.render_priority = 9
		m.albedo_color = WalkGuides.COLOUR
		_guides.material_override = m
		_guides.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(_guides)
	_guides.mesh = WalkGuides.mesh(guides, float((spot.get("at", Vector3.ZERO) as Vector3).y) + 0.02) if key != "" else null


## How many guides show now (for tests).
func guide_count() -> int:
	return (spot.get("guides", []) as Array).size() if spot.has("at") else 0


## Nothing to put it on: the part is held up in front of you, small, turned as it would go
## down (R turns it), so you can always see what you hold and which way it faces.
func _hold_in_view() -> void:
	var basis := camera.global_basis
	var size: Vector3 = _ghost.get_meta("size", Vector3.ONE)
	var fit := clampf(0.6 / maxf(maxf(size.x, size.z), size.y), 0.15, 1.0)
	_ghost.scale = Vector3.ONE * fit
	# Low and ahead in the view whichever way you look, as if carried in front of you.
	_ghost.position = camera.global_position - basis.z * 1.3 - basis.y * 0.3 - Vector3(0, size.y * fit * 0.5, 0)
	# Turned as you'd put it down, relative to where you look.
	_ghost.rotation = Vector3(0, body.rotation.y + deg_to_rad(float(holding.rot)), 0)


## What you hold, drawn where it would go (or in your hands): the part's own model (the
## asset library's, a box until there is one) tinted green where it fits, amber where it hits
## something, its outline, and an arrow and FRONT on the floor on the side it faces.
func _make_ghost(state: String) -> Node3D:
	var spec := model.catalog.kind(str(holding.type))
	var g := Node3D.new()
	g.name = "Ghost"
	world.add_child(g)
	# Strong colours: pale ones vanish on the white model look.
	var col := Color(0.1, 0.72, 0.3) if state == "true" else (Color(0.15, 0.5, 0.95) if state == "hand" else Color(0.95, 0.45, 0.08))
	var size := WalkEdits.size_of(model, str(holding.type), _held_entry())
	var body_node: Node3D = null
	if holding.has("module"):
		var kits := Modules.bus("kits")
		var made: Variant = kits.call("make_ghost", str(holding.module)) if kits and kits.has_method("make_ghost") else null
		if made is Node3D:
			body_node = made as Node3D
			size = _bounds_of(body_node)
	elif bool(holding.opening):
		size = Vector3(float(spec.get("w", 0.9)), float(spec.get("h", 2.0)), 0.3)
	elif model.catalog.family_of(str(holding.type)) == "column":
		var secs := model.catalog.sections_for(str(holding.type), "")
		var sec := model.catalog.section(str(secs[0]) if not secs.is_empty() else "")
		size = Vector3(float(sec.get("w", 0.3)), model.level_height(where().level), float(sec.get("d", sec.get("w", 0.3))))
	else:
		body_node = AssetLibrary.make_kind(str(holding.type), {"size": size, "family": "fixture"})
	g.set_meta("size", size)
	var tint := StandardMaterial3D.new()
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tint.albedo_color = Color(col.r, col.g, col.b, 0.7)
	tint.emission_enabled = true
	tint.emission = col * 0.25
	tint.cull_mode = BaseMaterial3D.CULL_DISABLED
	if body_node == null:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.position.y = size.y * 0.5
		body_node = mi
	g.add_child(body_node)
	for mi: MeshInstance3D in body_node.find_children("*", "MeshInstance3D", true, false) + ([body_node] if body_node is MeshInstance3D else []):
		mi.material_override = tint
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(_outline_box(size, col))
	if not model.catalog.family_of(str(holding.type)) in ["column"]:
		_front_marker(g, size, col)
	return g


## The box's twelve edges as thin bars, drawn through walls so you see it behind things.
static func _outline_box(size: Vector3, col: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Outline"
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	m.albedo_color = col.darkened(0.25)
	var t := 0.025
	var h := size * 0.5
	for axis in 3:
		for p: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			var at := Vector3.ZERO
			match axis:
				0:
					bm.size = Vector3(size.x + t, t, t)
					at = Vector3(0, h.y + h.y * p.x, h.z * p.y)
				1:
					bm.size = Vector3(t, size.y + t, t)
					at = Vector3(h.x * p.x, h.y, h.z * p.y)
				_:
					bm.size = Vector3(t, t, size.z + t)
					at = Vector3(h.x * p.x, h.y + h.y * p.y, 0)
			mi.mesh = bm
			mi.position = at
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
	return root


## An arrow on the floor out from the front face (-z: the side a fitting faces), and FRONT.
static func _front_marker(g: Node3D, size: Vector3, col: Color) -> void:
	var z0 := -size.z * 0.5 - 0.05
	var w := clampf(size.x * 0.6, 0.35, 0.8)
	var ln := clampf(size.z * 0.8, 0.45, 0.8)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for v: Vector3 in [Vector3(-w * 0.5, 0.03, z0), Vector3(w * 0.5, 0.03, z0), Vector3(0, 0.03, z0 - ln)]:
		im.surface_add_vertex(v)
	im.surface_end()
	var arrow := MeshInstance3D.new()
	arrow.name = "FrontArrow"
	arrow.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	# Drawn after the see-through body, so it's never hidden under it.
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.render_priority = 10
	m.albedo_color = col
	arrow.material_override = m
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(arrow)
	# The front face itself, solid, so the side it faces reads even with the arrow hidden.
	var face := MeshInstance3D.new()
	face.name = "FrontFace"
	var qm := QuadMesh.new()
	qm.size = Vector2(size.x, size.y)
	face.mesh = qm
	face.position = Vector3(0, size.y * 0.5, -size.z * 0.5 - 0.01)
	face.rotation.y = PI
	var fm := m.duplicate() as StandardMaterial3D
	fm.no_depth_test = false
	fm.render_priority = 0
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_color = Color(col, 0.6)
	face.material_override = fm
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(face)
	var tag := Label3D.new()
	tag.name = "FrontTag"
	tag.text = "FRONT"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.font_size = 48
	tag.pixel_size = 0.004
	tag.modulate = col.darkened(0.15)
	tag.render_priority = 11
	tag.outline_render_priority = 10
	tag.outline_modulate = Color(1, 1, 1, 0.9)
	tag.outline_size = 12
	tag.position = Vector3(0, 0.15, z0 - ln - 0.1)
	g.add_child(tag)


static func _bounds_of(n: Node3D) -> Vector3:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var b := mi.transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box.size if not first else Vector3.ONE


# The world and you

func _add_view() -> void:
	var layer := CanvasLayer.new()
	layer.name = "WalkView"
	layer.layer = 5
	add_child(layer)
	var box := SubViewportContainer.new()
	box.name = "View"
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(box)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.world_3d = World3D.new()
	viewport.handle_input_locally = false
	viewport.msaa_3d = get_viewport().msaa_3d if get_viewport() else Viewport.MSAA_DISABLED
	box.add_child(viewport)
	world = Node3D.new()
	world.name = "World"
	viewport.add_child(world)


## A daylight sky and a sun with shadows (the model look's shadows are its depth).
func _add_sky() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.4, 0.58, 0.86)
	sky_mat.sky_horizon_color = Color(0.8, 0.85, 0.9)
	sky_mat.ground_horizon_color = Color(0.62, 0.64, 0.6)
	sky_mat.ground_bottom_color = Color(0.45, 0.47, 0.42)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	# Haze so the far ground melts into the horizon rather than ending in a hard band.
	env.fog_enabled = true
	env.fog_light_color = sky_mat.sky_horizon_color
	env.fog_density = 0.004
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	world.add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.4
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.shadow_enabled = true
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.directional_shadow_max_distance = 120.0
	world.add_child(sun)


func _add_ground() -> void:
	var g := StaticBody3D.new()
	g.name = "Ground"
	g.collision_layer = LAYER
	g.collision_mask = 0
	g.set_meta("walk", {"kind": "ground", "id": "", "family": "ground", "level": 0})
	var s := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	plane.plane = Plane(Vector3.UP, -0.02)
	s.shape = plane
	g.add_child(s)
	var mi := MeshInstance3D.new()
	mi.name = "GroundMesh"
	var pm := PlaneMesh.new()
	pm.size = Vector2(2400, 2400)  # past the camera's far plane: no edge in view
	mi.mesh = pm
	mi.position.y = -0.02
	mi.material_override = ArtStyle.ground()
	g.add_child(mi)
	world.add_child(g)


func _apply_look() -> void:
	var gm := world.get_node_or_null("Ground/GroundMesh") as MeshInstance3D
	if gm:
		gm.material_override = ArtStyle.ground()
	if _look:
		_look.text = "%s LOOK  (V)" % ("REALISTIC" if ArtStyle.realistic() else "MODEL")


func _add_player() -> void:
	body = CharacterBody3D.new()
	body.name = "Walker"
	body.collision_layer = 0
	body.collision_mask = LAYER
	body.floor_max_angle = deg_to_rad(50.0)
	body.floor_snap_length = 0.3
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	shape.shape = cap
	body.add_child(shape)
	camera = Camera3D.new()
	camera.name = "WalkCamera"
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 900.0
	camera.position.y = 0.7
	body.add_child(camera)
	world.add_child(body)
	camera.current = true
	# Your own light, so a corner is never pitch black.
	var lamp := OmniLight3D.new()
	lamp.light_energy = 0.3
	lamp.omni_range = 5.0
	lamp.position.y = 0.6
	body.add_child(lamp)
	_aim_node = Node3D.new()
	_aim_node.name = "Aim"
	_aim_node.position = WalkBusRef.NO_AIM
	world.add_child(_aim_node)


func _add_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "WalkHud"
	hud.layer = 6
	add_child(hud)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", T.plate(10.0, true))
	box.position = Vector2(20, 20)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(box)
	var col := VBoxContainer.new()
	box.add_child(col)
	_title = T.label("WALK-INSIDE", "display_bold", 22, T.CYAN)
	col.add_child(_title)
	_where = T.label("", "mono_bold", 18, T.TEXT)
	_where.name = "Where"
	col.add_child(_where)
	_look = T.label("", "mono_bold", 15, T.AMBER)
	_look.name = "Look"
	col.add_child(_look)
	help = HelpBar.new()
	add_child(help)
	var dot := ColorRect.new()
	dot.name = "Crosshair"
	dot.color = Color(0.7, 0.95, 1.0, 0.8)
	dot.size = Vector2(4, 4)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.position -= Vector2(2, 2)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(dot)
	_palette = PanelContainer.new()
	_palette.name = "Palette"
	_palette.add_theme_stylebox_override("panel", T.plate(12.0))
	_palette.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_palette.custom_minimum_size.x = 380
	_palette.offset_left = -400
	_palette.offset_right = -20
	_palette.offset_top = 20
	_palette.offset_bottom = -20
	_palette.visible = false
	hud.add_child(_palette)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_palette.add_child(scroll)
	_palette_list = VBoxContainer.new()
	_palette_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palette_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_palette_list)
	_apply_look()


func _fill_palette() -> void:
	for c in _palette_list.get_children():
		_palette_list.remove_child(c)
		if c != _search:
			c.queue_free()
	if edit_id != "" and model.parts.has(edit_id):
		_fill_edit()
	else:
		edit_id = ""
		_fill_groups()
	var row := HBoxContainer.new()
	for spec: Array in [["UNDO", func() -> void: sync.undo()], ["REDO", func() -> void: sync.redo()]]:
		var b := T.button(str(spec[0]), false, 16)
		b.pressed.connect(spec[1])
		row.add_child(b)
	_palette_list.add_child(row)
	_palette_list.add_child(T.label("Aim at a part: click to move it, R to turn it, E to edit it, X to remove it.\n"
			+ "Aim at a wall: F for a door, the mouse wheel to push it away or pull it to you.\n"
			+ "Aim at the ceiling: the mouse wheel raises or lowers it.", "body", 14, T.DIM))


## The Tab menu's lists: OBJECTS or ROOMS, a filter, and the groups (the designer's, when it
## has them: WalkPalette), each folding open or shut; the preview of the picked item on top,
## and the sections other modules add (WalkBus.register_tab_section).
func _fill_groups() -> void:
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	for t: Array in [["objects", "OBJECTS"], ["rooms", "ROOMS"]]:
		var b := T.button(str(t[1]), palette_tab == t[0], 16, palette_tab == t[0])
		b.name = "Tab_" + str(t[0])
		var which: String = t[0]
		b.pressed.connect(func() -> void:
			palette_tab = which
			picked = {}
			_fill_palette())
		tabs.add_child(b)
	_palette_list.add_child(tabs)
	if _search == null:
		_search = T.search("Filter: bed, door, kitchen...", func(text: String) -> void:
			palette_filter = text
			_fill_list())
		_search.name = "Filter"
	_palette_list.add_child(_search)
	_preview_box = VBoxContainer.new()
	_preview_box.name = "Preview"
	_palette_list.add_child(_preview_box)
	_groups_box = VBoxContainer.new()
	_groups_box.name = "Groups"
	_groups_box.add_theme_constant_override("separation", 4)
	_palette_list.add_child(_groups_box)
	for sec: Dictionary in bus.call("tab_sections"):
		var made: Variant = (sec.make as Callable).call(self)
		if made is Control:
			_palette_list.add_child(T.label(str(sec.title).to_upper(), "display_bold", 18, T.ORANGE))
			_palette_list.add_child(made)
	_fill_preview()
	_fill_list()


## The groups as they stand for the tab and the filter.
func palette_groups() -> Array:
	return WalkPalette.filtered(WalkPalette.groups(model.catalog, palette_tab), palette_filter)


func _fill_list() -> void:
	if _groups_box == null:
		return
	for c in _groups_box.get_children():
		_groups_box.remove_child(c)
		c.queue_free()
	var all := palette_groups()
	if all.is_empty():
		_groups_box.add_child(T.label("Nothing matches \"%s\"." % palette_filter, "body", 14, T.DIM))
	var here := str(where().room)
	for g: Dictionary in all:
		var key := "%s:%s" % [palette_tab, g.id]
		# Open by default while filtering, else as the player left it (shut at first).
		var open := palette_filter.strip_edges() != "" or bool(_open_groups.get(key, false))
		var head := T.button("%s %s   (%d)" % ["▾" if open else "▸", str(g.title).to_upper(), (g.items as Array).size()], false, 16)
		head.name = "Group_" + str(g.id)
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		head.pressed.connect(func() -> void:
			_open_groups[key] = not open
			_fill_list())
		_groups_box.add_child(head)
		if not open:
			continue
		for it: Dictionary in g.items:
			var label := str(it.label)
			if palette_tab == "rooms" and here != "" and str(model.rooms[here].type) == str(it.id):
				label += "   (this room)"
			var b := T.button("    " + label, false, 15, str(picked.get("id", "")) == str(it.id))
			b.name = "Item_" + str(it.id)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var item: Dictionary = it.duplicate()
			item["source"] = str(g.get("source", ""))
			b.pressed.connect(func() -> void: pick_item(item))
			_groups_box.add_child(b)


## A click on an item: with a preview (WalkBus.set_preview_maker) it shows first, with TAKE;
## without one it is taken straight away (an object in hand, a room type for this room).
func pick_item(item: Dictionary) -> void:
	if bus.call("has_preview") and str(picked.get("id", "")) != str(item.id):
		picked = item
		_fill_preview()
		_fill_list()
		return
	use_item(item)


## An object in your hands, or the room you're standing in made this type.
func use_item(item: Dictionary) -> bool:
	picked = {}
	var id := str(item.id)
	if bool(bus.call("take_item", self, item)):
		return true
	var source := str(item.get("source", ""))
	if source != "":
		return _use_extra(item, source)
	if palette_tab == "rooms" or model.catalog.has_room_type(id) and not model.catalog.has_kind(id):
		var rid := str(where().room)
		if rid == "" or not model.catalog.has_room_type(id):
			_status("Stand in a room to make it a %s." % str(item.label).to_lower())
			return false
		sync.edit(C.retag(rid, id))
		_fill_palette()
		return true
	if not model.catalog.has_kind(id):
		return false
	take_new(id)
	return true


## An item from a group another module added to the designer's palette (a saved room
## module): carried and put down here when that module gives place_ops (kits), else handed
## to the group's own pick.
func _use_extra(item: Dictionary, source: String) -> bool:
	var id := str(item.id)
	var kits := Modules.bus("kits")
	if kits and kits.has_method("place_ops") and kits.has_method("has_module") and bool(kits.call("has_module", id)):
		_drop_holding()
		holding = {"type": "", "module": id, "label": str(item.get("label", id)), "id": "", "rot": 0.0, "opening": false}
		if is_palette_open():
			toggle_palette()
		return true
	var design := Modules.bus("design")
	var extra: Dictionary = design.get("palette_extra").get("%s:%s" % [palette_tab, source], {}) if design and "palette_extra" in design else {}
	if extra.has("pick") and (extra.pick as Callable).is_valid():
		(extra.pick as Callable).call(id)
		if is_palette_open():
			toggle_palette()
		return true
	return false


## One size row: name, - and + a grid step, and the value to type (Enter sets it).
func _dim_row(id: String, d: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Dim_%s" % str(d.field)
	var name_l := T.label(str(d.label).to_upper(), "mono_bold", 14, T.TEXT)
	name_l.custom_minimum_size.x = 80
	row.add_child(name_l)
	var angle := str(d.get("unit", "m")) == "°"
	var step := float(d.get("step", maxf(WalkEdits.grid(model), 0.05)))
	var box := SpinBox.new()
	box.name = "Value"
	box.min_value = -360.0 if angle else (0.0 if str(d.field) == "sill" else 0.05)
	box.max_value = 360.0 if angle else 200.0
	box.step = 0.1 if angle else 0.01
	box.suffix = str(d.get("unit", "m"))
	box.custom_arrow_step = step
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.set_value_no_signal(float(d.value))
	box.tooltip_text = ("Type an angle and press Enter, or turn it %d° at a time" % int(step)) if angle \
			else "Type a size and press Enter, or step it %.2f m at a time" % step
	var field := str(d.field)
	var apply := func(v: float) -> void:
		var op := WalkEdits.resize(model, id, field, v)
		if op.is_empty():
			_status("%s can't be %.2f %s" % [str(d.label), v, str(d.get("unit", "m"))])
		else:
			sync.edit(op)
	box.value_changed.connect(apply)
	for spec: Array in [["-", -step], ["+", step]]:
		var b := T.button(str(spec[0]), false, 16)
		b.name = "Down" if spec[0] == "-" else "Up"
		b.custom_minimum_size.x = 34
		var by: float = spec[1]
		b.pressed.connect(func() -> void: apply.call(snappedf(float(d.value) + by, 0.001)))
		if spec[0] == "-":
			row.add_child(b)
			row.add_child(box)
		else:
			row.add_child(b)
	return row


## CHANGE TO: the kinds this part could be, a filter to narrow them, and the picked one's
## preview with a button to change to it.
func _fill_change_to() -> void:
	var kinds := WalkEdits.kinds_like(model, edit_id)
	if kinds.size() < 2:
		return
	_palette_list.add_child(T.label("CHANGE TO  (%d)" % (kinds.size() - 1), "mono_bold", 14, T.DIM))
	var filter := LineEdit.new()
	filter.name = "KindFilter"
	filter.placeholder_text = "Filter (e.g. oak, double, shower)"
	filter.text = _edit_filter
	filter.clear_button_enabled = true
	filter.text_changed.connect(func(t: String) -> void:
		_edit_filter = t
		_fill_kind_list())
	_palette_list.add_child(filter)
	var scroll := ScrollContainer.new()
	scroll.name = "KindScroll"
	scroll.custom_minimum_size.y = 220
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_palette_list.add_child(scroll)
	_kind_list = VBoxContainer.new()
	_kind_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_kind_list)
	_edit_preview = VBoxContainer.new()
	_edit_preview.name = "EditPreview"
	_palette_list.add_child(_edit_preview)
	_fill_kind_list()
	_fill_edit_preview()


## The CHANGE TO list as filtered: every word in the label, id or group.
func _fill_kind_list() -> void:
	if _kind_list == null or not is_instance_valid(_kind_list) or not model.parts.has(edit_id):
		return
	for c in _kind_list.get_children():
		c.queue_free()
	var now := str(model.parts[edit_id].kind)
	var words := _edit_filter.strip_edges().to_lower().split(" ", false)
	var shown := 0
	var more := 0
	for k in WalkEdits.kinds_like(model, edit_id):
		var spec := model.catalog.kind(k)
		var hay := ("%s %s %s" % [spec.get("label", k), k, spec.get("group", "")]).to_lower()
		var ok := true
		for w in words:
			ok = ok and hay.contains(w)
		if not ok:
			continue
		if shown >= KIND_LIST_MAX:
			more += 1
			continue
		shown += 1
		var b := T.button(str(spec.get("label", k)) + ("  (now)" if k == now else ""), k == edit_pick, 14)
		b.name = "Kind_" + k
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = k == now
		b.pressed.connect(func() -> void: pick_kind(k))
		_kind_list.add_child(b)
	if more > 0:
		_kind_list.add_child(T.label("%d more: type to narrow" % more, "body", 13, T.DIM))


## Picks a kind in CHANGE TO: previewed, with a button to change to it.
func pick_kind(k: String) -> void:
	edit_pick = k
	_fill_kind_list()
	_fill_edit_preview()


## Changes the part you're editing to the picked kind (one undo step).
func change_to_pick() -> bool:
	var op := WalkEdits.change_kind(model, edit_id, edit_pick)
	if op.is_empty():
		return false
	sync.edit(op)
	edit_pick = ""
	return true


func _fill_edit_preview() -> void:
	if _edit_preview == null or not is_instance_valid(_edit_preview):
		return
	for c in _edit_preview.get_children():
		c.queue_free()
	if edit_pick == "" or not model.catalog.has_kind(edit_pick):
		return
	var spec := model.catalog.kind(edit_pick)
	# The button first, so it shows without scrolling; the preview under it.
	var b := T.button("CHANGE TO  %s" % str(spec.get("label", edit_pick)).to_upper(), true, 16)
	b.name = "ChangeKind"
	b.pressed.connect(func() -> void: change_to_pick())
	_edit_preview.add_child(b)
	var view: Variant = bus.call("make_preview", {"id": edit_pick, "label": str(spec.get("label", edit_pick)), "tags": PackedStringArray()})
	if view is Control:
		_edit_preview.add_child(view)


func _fill_preview() -> void:
	if _preview_box == null:
		return
	for c in _preview_box.get_children():
		_preview_box.remove_child(c)
		c.queue_free()
	if picked.is_empty():
		return
	var view: Variant = bus.call("make_preview", picked)
	if view is Control:
		_preview_box.add_child(view)
	var take := T.button("TAKE  %s" % str(picked.label).to_upper() if palette_tab == "objects" else "MAKE THIS ROOM A %s" % str(picked.label).to_upper(), true, 16)
	take.name = "Take"
	var item := picked
	take.pressed.connect(func() -> void: use_item(item))
	_preview_box.add_child(take)


func _status(text: String) -> void:
	if help:
		help.say(text)


## The bottom help bar from "What you're doing\nkeys", the keys in [b] (shown in the accent
## colour, like every screen's). Green or amber while you hold a part that fits or not.
func _show_help(text: String) -> void:
	if help == null:
		return
	var lines := text.split("\n", true, 1)
	var how := lines[1] if lines.size() > 1 else ""
	var accent := BsxTheme.ACCENT.to_html(false)
	how = how.replace("[b]", "[color=#%s][b]" % accent).replace("[/b]", "[/b][/color]").replace("   ", "  ·  ")
	var col := Color(0, 0, 0, 0)
	if not holding.is_empty() and not is_palette_open():
		col = T.GOOD if bool(spot.get("ok", false)) else T.AMBER
	help.set_help(lines[0].to_upper(), how, col)


## The help bar's text, plain (for tests).
func help_text() -> String:
	if help == null:
		return ""
	var re := RegEx.create_from_string("\\[[^\\]]*\\]")
	return re.sub(" ".join(help.shown()), "", true).strip_edges()


## E: the aimed part's sizes (steps or typed), its material, section and turn, and a list of
## what it could be changed to, with a preview.
func _fill_edit() -> void:
	var e: Dictionary = model.parts[edit_id]
	var kind := str(e.kind)
	var spec := model.catalog.kind(kind)
	_palette_list.add_child(T.label(str(spec.get("label", kind)).to_upper(), "display_bold", 18, T.ORANGE))
	var dims := WalkEdits.dims(model, edit_id)
	if not dims.is_empty():
		_palette_list.add_child(T.label("SIZE AND ANGLE", "mono_bold", 14, T.DIM))
		for d: Dictionary in dims:
			_palette_list.add_child(_dim_row(edit_id, d))
	var rows: Array = []
	if model.catalog.materials_for(kind).size() > 1:
		rows.append(["MATERIAL  %s" % str(e.get("material", "")).to_upper(), WalkEdits.cycle(model, edit_id, "material"), "EditMaterial"])
	if model.catalog.sections_for(kind, str(e.get("material", ""))).size() > 1:
		rows.append(["SECTION  %s" % str(e.get("section", "")).to_upper(), WalkEdits.cycle(model, edit_id, "section"), "EditSection"])
	if e.has("at"):
		rows.append(["TURN 90°", WalkEdits.turn(model, edit_id), "EditTurn"])
	for r: Array in rows:
		var b := T.button(str(r[0]), false, 16)
		b.name = str(r[2])
		var op: Dictionary = r[1]
		b.disabled = op.is_empty()
		b.pressed.connect(func() -> void: sync.edit(op))
		_palette_list.add_child(b)
	_fill_change_to()
	var rm := T.button("REMOVE", false, 16)
	rm.name = "EditRemove"
	var id := edit_id
	rm.pressed.connect(func() -> void:
		sync.edit(C.delete([id]))
		edit_id = ""
		_fill_palette())
	_palette_list.add_child(rm)
	var back := T.button("ALL PARTS", false, 16)
	back.pressed.connect(func() -> void:
		edit_id = ""
		_fill_palette())
	_palette_list.add_child(back)
