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
const HallChannels := preload("res://modules/design/internal/hall/hall_channels.gd")
const HallHoloTable := preload("res://modules/design/internal/hall/hall_holo_table.gd")
const T := preload("res://modules/ui/api/terminal_kit.gd")
const HallOffice := preload("res://modules/design/internal/hall/office/hall_office.gd")

## The hall's inside, m: 24 wide (x), 6 high, 18 deep (z).
const ROOM_SIZE := Vector3(24, 6, 18)
## Each wall: its middle, which way it faces into the room, its screen size, m, and what its
## panels show at first ([channel, share of the width]).
const WALLS := {
	"left": {"at": Vector3(-12, 3.0, 0), "turn": PI / 2.0, "size": Vector2(17, 5.0),
			"layout": [["plan", 0.5], ["3d", 0.5]]},
	"right": {"at": Vector3(12, 3.0, 0), "turn": -PI / 2.0, "size": Vector2(17, 5.0),
			"layout": [["channel:contracts.board", 0.4], ["cost", 0.3], ["panel:services.feasibility", 0.3]]},
	"back": {"at": Vector3(0, 3.0, 9), "turn": PI, "size": Vector2(23, 4.0),
			"layout": [["side", 0.2], ["bom", 0.2], ["panel:structure.live", 0.2], ["channel:sites.board", 0.4]]},
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
## The help bar along the bottom (keys here, what you are looking at), as in the designer.
var help: HelpBar
const HEADS := ["WALL SCREEN", "HOLOTABLE", "DESIGN OFFICE"]
var _cross: Control
var _bounds: DesignBounds
var _designer_opened := false


func _ready() -> void:
	set_meta("crew_avatars", true)
	net = Modules.bus("multiplayer") as MultiplayerBus
	building = Modules.bus("building") as BuildingBus
	model = building.model
	_bounds = DesignBounds.new(model)
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
		if id == "front" and has_node("Office"):
			continue  # the office's window wall
		_add_wall(id, WALLS[id])
	walker = HallWalker.new()
	add_child(walker)
	walker.position = Vector3(0, 0, 6.5)
	walker.call("look_at_point", Vector3(0, 1.2, 0))
	_build_hud()
	net.ping_received.connect(_on_ping)
	net.ping_removed.connect(_drop_ping)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	net.set_activity("In the design hall")


func _exit_tree() -> void:
	if net.ping_received.is_connected(_on_ping):
		net.ping_received.disconnect(_on_ping)
		net.ping_removed.disconnect(_drop_ping)
	HudSlots.release_pointer(DESIGNER_POINTER)
	HudSlots.release_pointer(FULL_POINTER)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- What the screens and the table read ------------------------------------------------

## The designer's world: the wall channels' cameras look into it.
func model_world() -> World3D:
	return designer_vp.find_world_3d()


## The building's extent (world m), for framing the drawings and fitting the table.
func bounds() -> AABB:
	return _bounds.box()


## The designer's whole copy of the design without shadows, for the plan and side screens.
func flat_source() -> DesignMiniWorld:
	return designer.hud.get("mini") as DesignMiniWorld


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
	return DesignMiniWorld.pointers_of(designer.session.presence, net)


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
	# The designer opens on the plan the first time; after that, as it was left.
	if not _designer_opened:
		_designer_opened = true
		if not bool(designer.camera.get("plan")):
			designer.call("toggle_plan")
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
	page.add_theme_stylebox_override("panel", T.box(Color(BsxTheme.PANEL, 0.98), T.EDGE, 0, 0.0))
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


# --- Pings ---------------------------------------------------------------------------------
# A middle-click pings what it is on, for everyone: a spot of the design (on a drawing on a
# wall, or on the table's model) shows in the designer, on the table and on every screen; a
# spot of the hall itself (a list on a wall, the floor) shows here as a ring with a label.

var _hall_pings: Dictionary = {}  # ping id -> {node, born}


## Pings a spot of the design (world m), as the designer's middle-click does.
func ping_at(at: Variant) -> void:
	if at is Vector3:
		designer.call("ping_here", at)


## A middle-click looking at something that isn't a screen: the table's model, or the hall.
func ping_look() -> void:
	var cam: Camera3D = walker.get("camera")
	var from: Vector3 = cam.global_position
	var dir: Vector3 = -cam.global_basis.z
	var lf: Vector3 = holo.to_local(from)
	var ld: Vector3 = holo.global_basis.inverse() * dir
	var top: float = HallHoloTable.TABLE_HEIGHT + 0.02
	if absf(ld.y) > 0.0001:
		var t: float = (top - lf.y) / ld.y
		var hit: Vector3 = lf + ld * t
		if t > 0.0 and t < 8.0 and bool(holo.call("over_table", hit)):
			ping_at(holo.call("from_table", hit))
			return
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 40.0)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		net.ping(r.position as Vector3, "hall:spot", r.normal as Vector3, "")


func _on_wall_middle(px: Vector2, wall_id: String) -> void:
	var board: Node = boards[wall_id]
	var i := int(board.call("panel_at", px))
	if i < 0:
		return
	var view := str((board.get("panels") as Array)[i].view)
	if view in ["plan", "side", "3d"]:
		return  # the drawing pings the design spot itself
	var screen: HallScreen = walls[wall_id]
	net.ping(screen.world_at(px), "hall:wall:%s" % view, screen.global_basis.z, HallChannels.title_of(self, view))


func _on_ping(p: Dictionary) -> void:
	var colour: Color = p.colour
	var hall := str(p.get("object_id", "")).begins_with("hall:")
	var root := Node3D.new()
	root.name = "Ping"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.12 if hall else 0.05
	torus.outer_radius = 0.17 if hall else 0.08
	ring.mesh = torus
	ring.material_override = mat
	var n: Vector3 = p.get("normal", Vector3.UP)
	if hall and absf(n.y) < 0.7:
		ring.rotation = Vector3(PI / 2.0, 0, 0)
		root.basis = Basis.looking_at(-n, Vector3.UP)
	root.add_child(ring)
	var label := Label3D.new()
	label.text = "%s%s" % [str(p.name), (": " + str(p.label)) if str(p.label) != "" else ""]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0012
	label.font_size = 28
	label.modulate = colour
	label.outline_size = 8
	label.position.y = 0.3 if hall else 0.15
	root.add_child(label)
	if hall:
		add_child(root)
		root.global_position = p.at as Vector3
	else:
		holo.add_child(root)
		root.position = holo.call("to_table", p.at as Vector3)
		root.set_meta("design_at", p.at)
	_hall_pings[int(p.id)] = {"node": root, "born": Time.get_ticks_msec() / 1000.0}


func _drop_ping(id: int) -> void:
	var p: Dictionary = _hall_pings.get(id, {})
	if not p.is_empty():
		(p.node as Node).queue_free()
		_hall_pings.erase(id)


func _tend_pings() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for id: int in _hall_pings.keys():
		var p: Dictionary = _hall_pings[id]
		if now - float(p.born) > MultiplayerBus.PING_LIFE:
			_drop_ping(id)
		elif (p.node as Node).has_meta("design_at"):
			# Keeps to its spot as the table turns and zooms.
			(p.node as Node3D).position = holo.call("to_table", (p.node as Node).get_meta("design_at") as Vector3)


func ping_count() -> int:
	return _hall_pings.size()


func _unhandled_input(event: InputEvent) -> void:
	if mode != "room" or HudSlots.pointer_claimed():
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Menu.open_pause()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_MIDDLE:
		ping_look()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_tend_pings()
	walker.set("enabled", mode == "room" and not HudSlots.pointer_claimed())
	var near := mode == "room" and at_table() and not HudSlots.pointer_claimed()
	if near and not Keys.typing():
		var spin := float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))
		var grow := float(Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_DOWN))
		var pan := Vector2(float(Input.is_physical_key_pressed(KEY_L)) - float(Input.is_physical_key_pressed(KEY_J)),
				float(Input.is_physical_key_pressed(KEY_K)) - float(Input.is_physical_key_pressed(KEY_I)))
		if spin != 0.0 or grow != 0.0 or pan != Vector2.ZERO:
			holo.call("nudge", spin * TURN_RATE * delta, pow(ZOOM_RATE, grow * delta), pan * PAN_RATE * delta)
	help.visible = mode == "room" and not HudSlots.pointer_claimed()
	_cross.visible = mode == "room"
	if mode == "room" and help.visible:
		var f := Keys.prompt(Keys.INTERACT)
		var wall := aimed_wall()
		if wall != "":
			help.set_help(HEADS[0], HelpBar.keys_text([["LMB", "< or > changes the panel"], [f, "full screen"],
					["MMB", "ping it"], ["Esc", "menu"]]))
			var board: Node = boards[wall]
			var i := int(board.call("panel_at", (walls[wall] as HallScreen).pointer_px))
			if i >= 0:
				var view := str((board.get("panels") as Array)[i].view)
				help.hover("Screen: %s · %s wall" % [HallChannels.title_of(self, view), wall])
		elif near:
			help.set_help(HEADS[1], HelpBar.keys_text([[f, "design at the holotable"], ["← →", "turn"], ["↑ ↓", "zoom"],
					["I J K L", "pan"], ["MMB", "ping"]]))
			help.hover("Holotable: the live model everyone shares")
		else:
			help.set_help(HEADS[2], HelpBar.keys_text([["WASD", "walk"], ["Shift", "run"], [f, "use"], ["MMB", "ping"],
					["Esc", "menu"]]))


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
	if Flags.is_on(HallOffice.FLAG):
		# The office: a window wall onto the vista, its sky, lights and furniture.
		var office := HallOffice.new()
		add_child(office)
		office.setup(self, env)
		return
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
	(designer.hud.get("mini") as DesignMiniWorld).pointer_sink = set_pointer


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
	screen.middle_clicked.connect(_on_wall_middle.bind(id))
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
	help = HelpBar.new()
	add_child(help)
	help.set_insets(200, 200)


## A small dot in the middle of the screen to aim with.
class Cross extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 3.0, Color(1, 1, 1, 0.85))
		draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 24, Color(0, 0, 0, 0.5), 1.5)
