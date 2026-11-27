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
const ScaledBox := preload("res://modules/design/internal/hall/hall_scaled_box.gd")
## The text size other modules' panels are made at, px.
const PANEL_FONT := 12.0

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
	for c: Dictionary in design.channel_list():
		out.append({"id": "channel:" + str(c.id), "title": str(c.title).to_upper()})
	for p: Dictionary in design.panel_list():
		out.append({"id": "panel:" + str(p.id), "title": str(p.title).to_upper()})
	return out


static func title_of(hall: Node, id: String) -> String:
	for c: Dictionary in channels(hall):
		if str(c.id) == id:
			return str(c.title)
	return "NOT AVAILABLE"


## A control showing channel `id`; font is the body text size, px.
## Built in the classic screen look (a wall screen is a TV, not the game's own UI).
static func make(id: String, hall: Node, font: int) -> Control:
	return BsxTheme.as_screen(func() -> Control: return _make(id, hall, font))


static func _make(id: String, hall: Node, font: int) -> Control:
	match id:
		"plan", "side", "3d":
			var v := ModelChannel.new()
			# The drawings look at the designer's whole, shadow-free copy of the design; the 3D
			# view at the designer's own world, shadows, crew cursors and all.
			v.setup(hall.call("flat_source") if id != "3d" and hall.has_method("flat_source") else hall, id)
			return v
		"bom":
			var b := BillChannel.new()
			b.setup(hall, font)
			return b
		"cost":
			var c := CostChannel.new()
			c.setup(hall, font)
			return c
	if id.begins_with("channel:"):
		var design := Modules.bus("design") as DesignBus
		var ch: Dictionary = design.channels.get(id.trim_prefix("channel:"), {})
		if not ch.is_empty() and (ch.make as Callable).is_valid():
			var page: Variant = (ch.make as Callable).call(hall.get("model"))
			if page is Control:
				# Laid out for a big page: drawn scaled to the screen's text, or smaller where
				# the page is wider than the panel, so it always fits across.
				var scaled := FitBox.new()
				scaled.base = float(font) / PANEL_FONT
				var c := page as Control
				c.theme = _scaled_theme(int(PANEL_FONT))
				scaled.add_child(c)
				return scaled
	if id.begins_with("panel:"):
		var design := Modules.bus("design") as DesignBus
		var p: Dictionary = design.panels.get(id.trim_prefix("panel:"), {})
		if not p.is_empty() and (p.make as Callable).is_valid():
			var body: Variant = (p.make as Callable).call(hall.get("model"))
			if body is Control:
				# Panels are made for the designer's side dock (text about PANEL_FONT px), so the
				# whole panel is drawn bigger, its own font sizes and all.
				var scaled: Container = ScaledBox.new(float(font) / PANEL_FONT)
				var box := ScrollContainer.new()
				box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
				scaled.add_child(box)
				var c := body as Control
				c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				c.theme = _scaled_theme(int(PANEL_FONT))
				box.add_child(c)
				return scaled
	var l := T.label("Not available", "body", font, T.DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## The game's theme with its text at `font` px (wall screens are read from across the room).
static func _scaled_theme(font: int) -> Theme:
	var th := BsxTheme.screen_theme().duplicate() as Theme
	th.default_font_size = font
	return th


## A camera on a world with the design in it: the plan from above, the side elevation, a
## section (looking along -z from a cut through the building), or a 3D view turning slowly
## round it. Drag to turn the 3D view, wheel to zoom, Shift+wheel to move the section's cut.
## Where this player's pointer is on the drawing is their design pointer for everyone.
## `hall` is whatever gives the world: model_world(), bounds(), floor_y(), set_pointer(at)
## (the hall, or the designer's DesignMiniWorld).
class ModelChannel extends SubViewportContainer:
	var hall: Node
	var mode := "plan"
	var vp: SubViewport
	var cam: Camera3D
	var zoom := 1.0
	var yaw := 0.6
	var pitch := -0.5
	## The section's cut, m from the building's middle along z.
	var cut := 0.0
	## How far the 3D view stands off, in building spans.
	var distance := 1.2
	var _drag := false
	var _hovered := false
	var _note: Label

	func setup(p_hall: Node, p_mode: String) -> void:
		hall = p_hall
		mode = p_mode
		mouse_filter = Control.MOUSE_FILTER_STOP
		vp = SubViewport.new()
		vp.world_3d = hall.call("model_world") as World3D
		vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		vp.handle_input_locally = false
		vp.size = Vector2i(2, 2)
		# Not a direct child, so the container doesn't size it to the layout: it is drawn at
		# the screen's real sharpness (a wall screen at 4K has several pixels per layout pixel).
		var holder := Node.new()
		holder.name = "Render"
		add_child(holder)
		holder.add_child(vp)
		cam = Camera3D.new()
		cam.current = true
		if mode != "3d":
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.far = 2000.0
		vp.add_child(cam)
		if mode == "section":
			_note = Label.new()
			_note.add_theme_font_size_override("font_size", 12)
			_note.modulate = Color(0.1, 0.12, 0.15, 0.8)
			_note.position = Vector2(8, 4)
			_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_note)
		mouse_exited.connect(func() -> void:
			if _hovered:
				_hovered = false
				hall.call("set_pointer", null))

	## Picture pixels per layout pixel where this view is drawn.
	func sharpness() -> float:
		var t := get_viewport().get_final_transform() * get_global_transform_with_canvas()
		return clampf(t.get_scale().x, 1.0, 4.0)

	func _draw() -> void:
		if vp:
			draw_texture_rect(vp.get_texture(), Rect2(Vector2.ZERO, size), false)

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var want := Vector2i((size * sharpness()).round()).max(Vector2i(2, 2))
		if vp.size != want:
			vp.size = want
			queue_redraw()
		if hall.has_method("watch"):
			hall.call("watch")
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
			"section":
				cut = clampf(cut, -box.size.z * 0.5, box.size.z * 0.5)
				var h := maxf(box.size.y, 6.0) * 1.3 / zoom
				cam.size = maxf(h, span / maxf(aspect, 0.1))
				cam.near = 0.02
				cam.global_transform = Transform3D(Basis.IDENTITY, Vector3(centre.x, box.position.y + box.size.y * 0.5, centre.z + cut))
				if _note:
					_note.text = "SECTION  z = %.1f m   ·   Shift+wheel moves the cut" % (centre.z + cut)
			"3d":
				if not _drag:
					yaw += delta * 0.08
				var dist := span * distance
				var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
				cam.global_transform = Transform3D(basis, centre + basis.z * dist)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mode == "section" and mb.shift_pressed and mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				cut += 0.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -0.25
			elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
				zoom = clampf(zoom * 1.15, 0.3, 8.0)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
				zoom = clampf(zoom / 1.15, 0.3, 8.0)
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				_drag = mb.pressed
			elif mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed and hall.has_method("ping_at"):
				# A middle-click pings that spot of the design for everyone.
				var at: Variant = floor_point(mb.position)
				if at != null:
					hall.call("ping_at", at)
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
		if mode == "section":
			return Vector3(from.x, from.y, from.z)
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
			t = "[color=#%s]Nothing placed yet.[/color]" % BsxTheme.col(self, "MUTED").to_html(false)
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
		var sum := book.summary()
		_text.text = BsxTheme.as_screen(func() -> String: return DesignCosts.bbcode(sum, 40, font * 2)) \
				if BsxTheme.on_screen(self) else DesignCosts.bbcode(sum, 40, font * 2)


## Shows its one child scaled by `base`, or less if the child's own width wouldn't fit at that
## scale; clicks still land. A page asks for no more room than the panel has.
class FitBox extends Container:
	var base := 1.0
	var factor := 1.0

	func _init() -> void:
		clip_contents = true

	func _get_minimum_size() -> Vector2:
		return Vector2.ZERO

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			for c in get_children():
				if c is Control:
					var ctl := c as Control
					var want := ctl.get_combined_minimum_size()
					factor = base
					if want.x > 1.0:
						factor = minf(base, size.x / want.x)
					factor = maxf(factor, 0.25)
					fit_child_in_rect(ctl, Rect2(Vector2.ZERO, size / factor))
					ctl.scale = Vector2(factor, factor)
