extends Node3D
## The design hall (BSX's design room, for buildings): a big room the crew walk round in first
## person, each seeing the others' avatars. Its walls are huge screens, each split into panels
## that anyone can flip between channels with < and > (the plan, the side view, the 3D view,
## the bill of materials, the cost and checks, and the consultants' live windows: the M&E
## engineer's cost and requirements, the contract, the structural engineer); F at a panel
## shows it full screen. In the middle stands the holotable with a live scale model of the
## design that anyone near it can turn, zoom and pan. F at the table opens the designer
## (DesignRoom, drawn full screen from its own world); Esc there comes back to the hall.
## Every player's pointer shows on every screen, in the designer and on the table's model.
##
## Keys in the hall: WASD walk, Shift run, mouse look, F use, Esc pause. At the table: arrows
## turn and zoom the model, I J K L pan it.

const DesignRoomScene := preload("res://modules/design/internal/room/design_room.tscn")
const HallScreens := preload("res://modules/design/internal/hall/hall_screens.gd")
const HallWalker := preload("res://modules/design/internal/hall/hall_walker.gd")
const HallWallBoard := preload("res://modules/design/internal/hall/hall_wall_board.gd")
const HallHoloTable := preload("res://modules/design/internal/hall/hall_holo_table.gd")
const T := preload("res://modules/ui/api/terminal_kit.gd")

## The hall's inside, m: 24 wide (x), 6 high, 18 deep (z).
const ROOM_SIZE := Vector3(24, 6, 18)
## Each wall: its middle, which way it faces into the room, its screen size, m, and what its
## panels show at first ([channel, share of the width]).
const WALLS := {
	"left": {"at": Vector3(-12, 3.0, 0), "turn": PI / 2.0, "size": Vector2(17, 5.0),
			"layout": [["plan", 0.5], ["3d", 0.5]]},
	"right": {"at": Vector3(12, 3.0, 0), "turn": -PI / 2.0, "size": Vector2(17, 5.0),
			"layout": [["cost", 0.5], ["panel:services.feasibility", 0.5]]},
	"back": {"at": Vector3(0, 3.0, 9), "turn": PI, "size": Vector2(23, 4.0),
			"layout": [["side", 0.25], ["bom", 0.25], ["panel:structure.live", 0.25], ["panel:contracts.brief", 0.25]]},
	"front": {"at": Vector3(0, 3.0, -9), "turn": 0.0, "size": Vector2(23, 4.0),
			"layout": [["3d", 0.34], ["bom", 0.33], ["plan", 0.33]]},
}
## Pixels per metre on the walls (a 17 m wall is 2,040 px across).
const WALL_PX_PER_M := 120.0
## Pixels per metre a panel is drawn at full screen.
const FULL_PX_PER_M := 110.0
## How far from a wall its screen can be used, m (the hall is 24 m across).
const WALL_REACH := 14.0
## How near the table's middle (across the floor) F opens the designer and the keys move the
## model, m.
const TABLE_REACH := 4.8
const TURN_RATE := 1.4
const ZOOM_RATE := 1.8
## Model metres a second the I J K L keys pan by at zoom 1 (scaled by the table's fit).
const PAN_RATE := 1.2
## Pointer claims (HudSlots) while the designer or a full-screen panel has the mouse.
const DESIGNER_POINTER := "design.hall.designer"
const FULL_POINTER := "design.hall.fullscreen"

signal mode_changed(mode: String)

var net: MultiplayerBus
var building: BuildingBus
var model: BuildingModel
var screens: Node
var walker: CharacterBody3D
var holo: Node3D
## The designer (a DesignRoom) and the screen it's drawn on.
var designer: Node3D
var designer_view: SubViewportContainer
var designer_vp: SubViewport
var walls: Dictionary = {}  # wall id -> HallScreen
var boards: Dictionary = {}  # wall id -> HallWallBoard
## "room" (walking), "designer" or "full" (a wall panel full screen).
var mode := "room"
var fullscreen: Control
var full_from := {}
var _hint: Label
var _cross: Control
var _bounds := AABB(Vector3(-10, 0, -10), Vector3(20, 6, 20))
var _bounds_rev := -1
var _bounds_age := 1.0


func _ready() -> void:
	set_meta("crew_avatars", true)
	net = Modules.bus("multiplayer") as MultiplayerBus
	building = Modules.bus("building") as BuildingBus
	model = building.model
	screens = HallScreens.new()
	screens.name = "Screens"
	add_child(screens)
	screens.call("bind", net)
	_build_shell()
	_build_designer()
	holo = HallHoloTable.new()
	add_child(holo)
	holo.call("setup", self, model)
	for id: String in WALLS:
		_add_wall(id, WALLS[id])
	walker = HallWalker.new()
	add_child(walker)
	walker.position = Vector3(0, 0, 6.5)
	walker.call("look_at_point", Vector3(0, 1.2, 0))
	_build_hud()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	net.set_activity("In the design hall")


func _exit_tree() -> void:
	HudSlots.release_pointer(DESIGNER_POINTER)
	HudSlots.release_pointer(FULL_POINTER)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- What the screens and the table read ------------------------------------------------

## The designer's world: the wall channels' cameras look into it.
func model_world() -> World3D:
	return designer_vp.find_world_3d()


## The building's extent (world m), for framing the drawings and fitting the table.
func bounds() -> AABB:
	if model.revision != _bounds_rev and _bounds_age > 0.5:
		_bounds_rev = model.revision
		_bounds_age = 0.0
		var first := true
		var box := AABB()
		for id: String in model.parts:
			var b: AABB = model.aabb_of(id)
			box = b if first else box.merge(b)
			first = false
		for id: String in model.rooms:
			for p: Variant in model.rooms[id].outline:
				var v := Vector3(float(p[0]), model.level_elevation(int(model.rooms[id].level)), float(p[1]))
				box = AABB(v, Vector3.ZERO) if first else box.expand(v)
				first = false
		_bounds = box if not first else AABB(Vector3(-10, 0, -10), Vector3(20, 6, 20))
		_bounds.size.y = maxf(_bounds.size.y, 3.0)
	return _bounds


func floor_y() -> float:
	return designer.session.floor_y()


func cost_book() -> DesignCostBook:
	return designer.hud.get("_book") as DesignCostBook


## This player's pointer from a wall screen's drawing (a world point, or null to hide it).
func set_pointer(at: Variant) -> void:
	if mode != "designer":
		designer.session.presence.set_cursor(at)


## Every player's pointer now: peer -> {at, colour, name}. This player's own, the others'
## (from the designer's presence) and anyone walking inside the design (WalkBus, if there).
func pointers() -> Dictionary:
	var out := {}
	var pres: DesignPresence = designer.session.presence
	var me := net.local_peer_id()
	var mine: Variant = pres.my_cursor.position if pres.my_cursor.position.y > DesignPresence.HIDDEN_Y + 1.0 else null
	if mine != null:
		out[me] = {"at": mine, "colour": net.player_colour(me), "name": net.player_name(me)}
	var others := pres.others()
	for peer: int in others:
		if others[peer].cursor != null:
			out[peer] = {"at": others[peer].cursor, "colour": net.player_colour(peer), "name": net.player_name(peer)}
	var walk := Modules.bus("walk")
	if walk and "walkers" in walk:
		var walkers: Dictionary = walk.get("walkers")
		for peer: int in walkers:
			var w: Dictionary = walkers[peer]
			if w.has("pos"):
				out[peer] = {"at": w.pos, "colour": net.player_colour(peer), "name": net.player_name(peer)}
	return out


# --- Modes ------------------------------------------------------------------------------

## True when this player stands at the table.
func at_table() -> bool:
	var d := holo.to_local(walker.global_position)
	return Vector2(d.x, d.z).length() <= TABLE_REACH


## F at the table: the designer, full screen; the hall's walls and table carry on behind it.
func open_designer() -> void:
	if mode == "designer":
		return
	if mode == "full":
		close_fullscreen()
	mode = "designer"
	designer_view.visible = true
	designer_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	designer.call("set_active", true)
	HudSlots.claim_pointer(DESIGNER_POINTER)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	net.set_activity("At the holotable")
	_refresh_mode()


## Back to the hall from the designer.
func close_designer() -> void:
	if mode != "designer":
		return
	mode = "room"
	designer.call("set_active", false)
	designer_view.visible = false
	designer_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	HudSlots.release_pointer(DESIGNER_POINTER)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	net.set_activity("In the design hall")
	_refresh_mode()


## The wall the view is on, "" for none.
func aimed_wall() -> String:
	var cur := HallScreen.current()
	for id: String in walls:
		if walls[id] == cur:
			return id
	return ""


## F at a wall: the panel under the pointer fills the screen, its < and > working and what it
## changes shared as on the wall. F or Esc puts it back.
func open_fullscreen(wall_id: String, panel := -1) -> bool:
	if mode != "room" or not boards.has(wall_id):
		return false
	var board: Node = boards[wall_id]
	var i := panel
	if i < 0:
		i = int(board.call("panel_at", (walls[wall_id] as HallScreen).pointer_px))
	if i < 0:
		i = 0
	var page := PanelContainer.new()
	page.name = "WallFullScreen"
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.theme = BsxTheme.get_theme()
	page.add_theme_stylebox_override("panel", T.box(Color(0.02, 0.05, 0.09, 0.97), T.EDGE, 0, 0.0))
	var col := VBoxContainer.new()
	page.add_child(col)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	col.add_child(bar)
	bar.add_child(T.label("WALL SCREEN, FULL", "display_bold", 18, T.ORANGE))
	var tip := T.label("%s or Esc to go back" % Keys.prompt(Keys.INTERACT), "body", 15, T.DIM)
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(tip)
	var back := T.button("BACK", false, 16)
	back.name = "Back"
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(close_fullscreen)
	bar.add_child(back)
	var panels: Array = board.get("panels")
	var full := HallWallBoard.new()
	full.local = true
	full.size_flags_vertical = Control.SIZE_EXPAND_FILL
	full.setup(self, wall_id + "_full", [[str(panels[i].view), 1.0]], FULL_PX_PER_M)
	col.add_child(full)
	var layer := CanvasLayer.new()
	layer.name = "FullScreenLayer"
	layer.layer = 6
	layer.add_child(page)
	add_child(layer)
	fullscreen = page
	full_from = {"wall": wall_id, "panel": i, "board": full}
	mode = "full"
	HudSlots.claim_pointer(FULL_POINTER)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_mode()
	return true


## Back from full screen to the hall; the wall panel takes the channel it was left on.
func close_fullscreen() -> void:
	if fullscreen == null:
		return
	var full: Node = full_from.get("board")
	if full and boards.has(str(full_from.wall)):
		var view := str((full.get("panels") as Array)[0].view)
		var board: Node = boards[str(full_from.wall)]
		var i := int(full_from.panel)
		if i < (board.get("panels") as Array).size() and str((board.get("panels") as Array)[i].view) != view:
			board.call("set_view", i, view)
	fullscreen.get_parent().queue_free()
	fullscreen = null
	full_from = {}
	mode = "room"
	HudSlots.release_pointer(FULL_POINTER)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_refresh_mode()


func _refresh_mode() -> void:
	mode_changed.emit(mode)


# --- Input and frame --------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var esc := event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE
	match mode:
		"full":
			if esc or event.is_action_pressed(Keys.INTERACT):
				close_fullscreen()
				get_viewport().set_input_as_handled()
		"room":
			if HudSlots.pointer_claimed():
				return
			if event.is_action_pressed(Keys.INTERACT) and not Keys.typing():
				var wall := aimed_wall()
				if wall != "":
					open_fullscreen(wall)
				elif at_table():
					open_designer()
				else:
					return
				get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if mode != "room" or HudSlots.pointer_claimed():
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Menu.open_pause()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_bounds_age += delta
	walker.set("enabled", mode == "room" and not HudSlots.pointer_claimed())
	var near := mode == "room" and at_table() and not HudSlots.pointer_claimed()
	if near and not Keys.typing():
		var spin := float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))
		var grow := float(Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_DOWN))
		var pan := Vector2(float(Input.is_physical_key_pressed(KEY_L)) - float(Input.is_physical_key_pressed(KEY_J)),
				float(Input.is_physical_key_pressed(KEY_K)) - float(Input.is_physical_key_pressed(KEY_I)))
		if spin != 0.0 or grow != 0.0 or pan != Vector2.ZERO:
			holo.call("nudge", spin * TURN_RATE * delta, pow(ZOOM_RATE, grow * delta), pan * PAN_RATE * delta)
	_hint.visible = mode == "room"
	_cross.visible = mode == "room"
	if mode == "room":
		var wall := aimed_wall()
		if wall != "":
			_hint.text = "LMB  press < or > to change a panel      %s  full screen" % Keys.prompt(Keys.INTERACT)
		elif near:
			_hint.text = "%s  Design at the holotable      ← →  turn   ↑ ↓  zoom   I J K L  pan" % Keys.prompt(Keys.INTERACT)
		else:
			_hint.text = "WASD walk   Shift run   %s use   Esc menu" % Keys.prompt(Keys.INTERACT)


# --- The room ---------------------------------------------------------------------------

func _build_shell() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.68)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.22, 0.24, 0.27)
	floor_mat.roughness = 0.35
	floor_mat.metallic = 0.2
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.12, 0.13, 0.15)
	wall_mat.roughness = 0.8
	var half := ROOM_SIZE * 0.5
	_slab("Floor", Vector3(ROOM_SIZE.x, 0.2, ROOM_SIZE.z), Vector3(0, -0.1, 0), floor_mat)
	_slab("Ceiling", Vector3(ROOM_SIZE.x, 0.2, ROOM_SIZE.z), Vector3(0, ROOM_SIZE.y + 0.1, 0), wall_mat)
	_slab("WallLeft", Vector3(0.3, ROOM_SIZE.y, ROOM_SIZE.z), Vector3(-half.x - 0.15, half.y, 0), wall_mat)
	_slab("WallRight", Vector3(0.3, ROOM_SIZE.y, ROOM_SIZE.z), Vector3(half.x + 0.15, half.y, 0), wall_mat)
	_slab("WallBack", Vector3(ROOM_SIZE.x, ROOM_SIZE.y, 0.3), Vector3(0, half.y, half.z + 0.15), wall_mat)
	_slab("WallFront", Vector3(ROOM_SIZE.x, ROOM_SIZE.y, 0.3), Vector3(0, half.y, -half.z - 0.15), wall_mat)
	for x: float in [-7.0, 0.0, 7.0]:
		for z: float in [-4.5, 4.5]:
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(x, ROOM_SIZE.y - 0.4, z)
			lamp.omni_range = 11.0
			lamp.light_energy = 0.9
			lamp.light_color = Color(0.92, 0.95, 1.0)
			add_child(lamp)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-60.0), deg_to_rad(-25.0), 0.0)
	key.light_energy = 0.35
	key.shadow_enabled = true
	add_child(key)


func _slab(id: String, sz: Vector3, at: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.name = id
	body.position = at
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = sz
	shape.shape = box
	body.add_child(shape)
	add_child(body)


## The designer, in its own world on a full-screen layer, put away until F at the table.
func _build_designer() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DesignerLayer"
	layer.layer = 4
	add_child(layer)
	designer_view = SubViewportContainer.new()
	designer_view.name = "Designer"
	designer_view.stretch = true
	designer_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	designer_view.visible = false
	layer.add_child(designer_view)
	designer_vp = SubViewport.new()
	designer_vp.own_world_3d = true
	designer_vp.handle_input_locally = false
	designer_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	designer_view.add_child(designer_vp)
	designer = DesignRoomScene.instantiate()
	designer.set("embedded", true)
	designer_vp.add_child(designer)
	designer.call("set_active", false)
	designer.connect("leave_requested", close_designer)


## One screen over a wall. A HallScreen faces its +Z; it stands 10 cm off the wall's face.
func _add_wall(id: String, w: Dictionary) -> void:
	var sz: Vector2 = w.size
	var px := Vector2i(int(sz.x * WALL_PX_PER_M), int(sz.y * WALL_PX_PER_M))
	var board := HallWallBoard.new()
	board.setup(self, id, w.layout, WALL_PX_PER_M)
	var screen := HallScreen.new(board, px, sz)
	screen.name = "Wall_" + id
	screen.reach = WALL_REACH
	var basis := Basis(Vector3.UP, float(w.turn))
	var at: Vector3 = w.at
	screen.transform = Transform3D(basis, at + basis.z * 0.1)
	add_child(screen)
	walls[id] = screen
	boards[id] = board


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HallHud"
	layer.layer = 3
	add_child(layer)
	_cross = Cross.new()
	_cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	layer.add_child(_cross)
	_hint = T.label("", "body", 17, T.TEXT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_top = -60
	_hint.offset_bottom = -24
	_hint.offset_left = -500
	_hint.offset_right = 500
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hint.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hint)


## A small dot in the middle of the screen to aim with.
class Cross extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 3.0, Color(1, 1, 1, 0.85))
		draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 24, Color(0, 0, 0, 0.5), 1.5)
