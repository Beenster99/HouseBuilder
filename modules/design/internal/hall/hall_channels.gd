extends RefCounted
## The channels the hall's wall panels flip through (BSX's wall views, for buildings): the
## plan, the side elevation and the 3D view (cameras on the designer's own world, so every
## player's pointer, selection and drag shows on them as it does at the table), the bill of
## materials, the cost and checks, and every live window another module offers the designer
## (DesignBus.register_panel: the M&E consultant's cost and requirements, the contract, the
## structural engineer) as "panel:<id>".
##
##   var all := HallChannels.channels(hall)        # [{id, title}]
##   var c := HallChannels.make("plan", hall, 24)  # a Control for a panel

const T := preload("res://modules/ui/api/terminal_kit.gd")

const BASE: Array[Dictionary] = [
	{"id": "plan", "title": "PLAN"},
	{"id": "side", "title": "SIDE ELEVATION"},
	{"id": "3d", "title": "3D VIEW"},
	{"id": "bom", "title": "BILL OF MATERIALS"},
	{"id": "cost", "title": "COST AND CHECKS"},
]


static func channels(hall: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(BASE)
	var design := Modules.bus("design") as DesignBus
	for p: Dictionary in design.panel_list():
		out.append({"id": "panel:" + str(p.id), "title": str(p.title).to_upper()})
	return out


static func title_of(hall: Node, id: String) -> String:
	for c: Dictionary in channels(hall):
		if str(c.id) == id:
			return str(c.title)
	return "NOT AVAILABLE"


## A control showing channel `id`; font is the body text size, px.
static func make(id: String, hall: Node, font: int) -> Control:
	match id:
		"plan", "side", "3d":
			var v := ModelChannel.new()
			v.setup(hall, id)
			return v
		"bom":
			var b := BillChannel.new()
			b.setup(hall, font)
			return b
		"cost":
			var c := CostChannel.new()
			c.setup(hall, font)
			return c
	if id.begins_with("panel:"):
		var design := Modules.bus("design") as DesignBus
		var p: Dictionary = design.panels.get(id.trim_prefix("panel:"), {})
		if not p.is_empty() and (p.make as Callable).is_valid():
			var body: Variant = (p.make as Callable).call(hall.get("model"))
			if body is Control:
				var box := ScrollContainer.new()
				box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
				var c := body as Control
				c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				c.theme = _scaled_theme(font)
				box.add_child(c)
				return box
	var l := T.label("Not available", "body", font, T.DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## The game's theme with its text at `font` px (wall screens are read from across the room).
static func _scaled_theme(font: int) -> Theme:
	var th := BsxTheme.get_theme().duplicate() as Theme
	th.default_font_size = font
	return th


## A camera on the designer's world: the plan from above, the side elevation, or a 3D view
## turning slowly round the building. Drag to turn the 3D view, wheel to zoom. Where this
## player's pointer is on the drawing is their design pointer for everyone.
class ModelChannel extends SubViewportContainer:
	var hall: Node
	var mode := "plan"
	var vp: SubViewport
	var cam: Camera3D
	var zoom := 1.0
	var yaw := 0.6
	var pitch := -0.5
	var _drag := false
	var _hovered := false

	func setup(p_hall: Node, p_mode: String) -> void:
		hall = p_hall
		mode = p_mode
		stretch = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		vp = SubViewport.new()
		vp.world_3d = hall.call("model_world") as World3D
		vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		vp.handle_input_locally = false
		add_child(vp)
		cam = Camera3D.new()
		cam.current = true
		if mode != "3d":
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.far = 2000.0
		vp.add_child(cam)
		mouse_exited.connect(func() -> void:
			if _hovered:
				_hovered = false
				hall.call("set_pointer", null))

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var box: AABB = hall.call("bounds")
		var centre := box.get_center()
		var span := maxf(maxf(box.size.x, box.size.z), 8.0) * 1.15 / zoom
		var aspect := size.x / maxf(size.y, 1.0)
		match mode:
			"plan":
				cam.size = span / minf(aspect, 1.0) if aspect < 1.0 else span
				cam.global_transform = Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0.0, 0.0)),
						Vector3(centre.x, box.end.y + 50.0, centre.z))
			"side":
				var h := maxf(box.size.y, 6.0) * 1.3 / zoom
				cam.size = maxf(h, span / maxf(aspect, 0.1))
				cam.global_transform = Transform3D(Basis.IDENTITY, Vector3(centre.x, box.position.y + box.size.y * 0.5, box.end.z + 100.0))
			"3d":
				if not _drag:
					yaw += delta * 0.08
				var dist := span * 1.2
				var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
				cam.global_transform = Transform3D(basis, centre + basis.z * dist)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
				zoom = clampf(zoom * 1.15, 0.3, 8.0)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
				zoom = clampf(zoom / 1.15, 0.3, 8.0)
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				_drag = mb.pressed
			accept_event()
		elif event is InputEventMouseMotion:
			var mm := event as InputEventMouseMotion
			if _drag and mode == "3d":
				yaw -= mm.relative.x * 0.01
				pitch = clampf(pitch - mm.relative.y * 0.01, -1.4, -0.05)
			_hovered = true
			hall.call("set_pointer", floor_point(mm.position))
			accept_event()

	## Where a point on this drawing meets the working floor, or null.
	func floor_point(at: Vector2) -> Variant:
		if size.x < 1.0 or size.y < 1.0:
			return null
		var p := at * Vector2(vp.size) / size
		var from := cam.project_ray_origin(p)
		var dir := cam.project_ray_normal(p)
		var y := float(hall.call("floor_y"))
		if mode == "side":
			return Vector3(from.x, from.y, float((hall.call("bounds") as AABB).get_center().z))
		if absf(dir.y) < 0.0001:
			return null
		var t := (y - from.y) / dir.y
		return from + dir * t if t > 0.0 else null


## The bill of materials: each kind and material with how many, how much and what it costs.
class BillChannel extends PanelContainer:
	var hall: Node
	var font := 20
	var _text: RichTextLabel
	var _rev := -1
	var _age := 10.0

	func setup(p_hall: Node, p_font: int) -> void:
		hall = p_hall
		font = p_font
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		_text = RichTextLabel.new()
		_text.bbcode_enabled = true
		_text.scroll_active = true
		_text.add_theme_font_size_override("normal_font_size", font)
		_text.add_theme_font_size_override("bold_font_size", font)
		add_child(_text)

	func _process(delta: float) -> void:
		_age += delta
		var book: DesignCostBook = hall.call("cost_book")
		if book == null or not is_visible_in_tree() or (book.revision == _rev and _age < 2.0) or _age < 0.5:
			return
		_age = 0.0
		_rev = book.revision
		var rows := book.bill()
		var cur := str(book.model.catalog.currency)
		var t := "[table=5][cell][b]Item[/b][/cell][cell][b]Material[/b][/cell][cell][right][b]No.[/b][/right][/cell][cell][right][b]Quantity[/b][/right][/cell][cell][right][b]Cost[/b][/right][/cell]"
		var total := 0.0
		for r: Dictionary in rows:
			total += float(r.cost)
			t += "[cell]%s[/cell][cell]%s[/cell][cell][right]%d[/right][/cell][cell][right]%s[/right][/cell][cell][right]%s[/right][/cell]" % [
					r.label, r.material_label, int(r.count), _qty(float(r.qty), str(r.unit)), DesignCosts.money(float(r.cost), cur)]
		t += "[/table]\n[b]%d lines, %s[/b]" % [rows.size(), DesignCosts.money(total, cur)]
		if rows.is_empty():
			t = "[color=#%s]Nothing placed yet.[/color]" % BsxTheme.MUTED.to_html(false)
		_text.text = t

	static func _qty(q: float, unit: String) -> String:
		match unit:
			"m3": return "%.1f m³" % q
			"m2": return "%.1f m²" % q
			"m": return "%.1f m" % q
			"t": return "%.2f t" % q
			"": return "-"
		return "%d" % int(round(q))


## The live cost and the checks on the design (the designer's cost column, bigger).
class CostChannel extends PanelContainer:
	var hall: Node
	var font := 20
	var _text: RichTextLabel
	var _rev := -1
	var _age := 10.0

	func setup(p_hall: Node, p_font: int) -> void:
		hall = p_hall
		font = p_font
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		_text = RichTextLabel.new()
		_text.bbcode_enabled = true
		_text.scroll_active = true
		_text.add_theme_font_size_override("normal_font_size", font)
		_text.add_theme_font_size_override("bold_font_size", font)
		add_child(_text)

	func _process(delta: float) -> void:
		_age += delta
		var book: DesignCostBook = hall.call("cost_book")
		if book == null or not is_visible_in_tree() or (book.revision == _rev and _age < 2.0) or _age < 0.5:
			return
		_age = 0.0
		_rev = book.revision
		_text.text = DesignCosts.bbcode(book.summary(), 40, font * 2)
