extends Node
## First scene: the splash. Shows the game's picture with a progress bar while it waits for
## the modules, preloads every registered scene, runs the modules' own warm-up steps and
## draws every material once in a hidden view so the shaders are compiled (Warmup). Then it
## hands over to the main menu (registered by the UI module) by id, so Core never references
## UI, and tells Modules the boot is done (dev --host/--join launches wait for that).

const FIRST_SCENE := "main_menu"
## The splash stays at least this long, s, so it never just flickers.
const MIN_TIME := 2.0
## Materials drawn per frame while warming up.
const BATCH := 12

var _bar: ProgressBar
var _status: Label
var _layer: CanvasLayer
var _shown := 0.0
var _target := 0.0
## Phase -> ms, for the log line the benchmark reads (and steps by their labels).
var timings: Dictionary = {}
var _phase_at := 0
var _started := 0


func _ready() -> void:
	_started = Time.get_ticks_msec()
	_build()
	await get_tree().process_frame
	_progress(0.02, "Starting up")
	if not Modules.ready_done:
		await Modules.modules_ready
	_mark("modules")
	_progress(0.08, "Loading the modules")
	await _load_scenes(0.08, 0.55)
	_mark("scenes")
	await _run_steps(0.55, 0.7)
	if DisplayServer.get_name() != "headless":
		_progress(0.7, "Preparing graphics")
		await _warm_shaders(0.7, 0.98)
		_mark("shaders")
	_progress(1.0, "Ready")
	_report()
	while Time.get_ticks_msec() - _started < MIN_TIME * 1000.0:
		await get_tree().process_frame
	Modules.finish_boot()
	if Router.has_scene(FIRST_SCENE):
		# A dev launch (--host / --join) may already have opened the game itself.
		if Router.current_id == "":
			Router.goto(FIRST_SCENE)
	else:
		push_error("Boot: nothing registered '%s'; is the ui flag on?" % FIRST_SCENE)


func _mark(phase: String) -> void:
	var now := Time.get_ticks_msec()
	timings[phase] = now - (_phase_at if _phase_at > 0 else _started)
	_phase_at = now


## One line in the log: "[boot] 2310 ms (slowest: shaders 1200 ms) modules=.. scenes=.. ...".
func _report() -> void:
	var slow := ""
	for k: String in timings:
		if slow == "" or int(timings[k]) > int(timings[slow]):
			slow = k
	var parts := PackedStringArray()
	for k: String in timings:
		parts.append("%s=%d" % [k, int(timings[k])])
	print("[boot] %d ms (slowest: %s %d ms) %s" % [Time.get_ticks_msec() - _started, slow,
			int(timings.get(slow, 0)), " ".join(parts)])


func _process(delta: float) -> void:
	if _bar:
		_shown = move_toward(_shown, _target, delta * 1.5)
		_bar.value = _shown



func _progress(fraction: float, text: String) -> void:
	_target = clampf(fraction, 0.0, 1.0)
	if _status:
		_status.text = text


func _load_scenes(from: float, to: float) -> void:
	var paths := Warmup.scene_list()
	if paths.is_empty():
		return
	for p in paths:
		ResourceLoader.load_threaded_request(p, "", true)
	var pending := Array(paths)
	while not pending.is_empty():
		var total := 0.0
		for p: String in paths:
			if not pending.has(p):
				total += 1.0
				continue
			var progress := []
			var st := ResourceLoader.load_threaded_get_status(p, progress)
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				var res := ResourceLoader.load_threaded_get(p)
				if res:
					Warmup.loaded.append(res)
				pending.erase(p)
				total += 1.0
			elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_warning("Boot: could not preload %s" % p)
				pending.erase(p)
				total += 1.0
			else:
				total += float(progress[0]) if not progress.is_empty() else 0.0
		_progress(lerpf(from, to, total / paths.size()), "Loading scenes  %d / %d" % [paths.size() - pending.size(), paths.size()])
		await get_tree().process_frame


func _run_steps(from: float, to: float) -> void:
	var weight := 0.0
	for s: Dictionary in Warmup.steps:
		weight += float(s.weight)
	var done := 0.0
	for s: Dictionary in Warmup.steps:
		_progress(lerpf(from, to, done / maxf(weight, 0.001)), str(s.label))
		await get_tree().process_frame
		var r: Variant = (s.run as Callable).call()
		if r is Signal:
			await r
		_mark("step:" + str(s.label))
		done += float(s.weight)
	_progress(to, "")


## Draws every material (and mesh) once in a small hidden view, under a shadowed sun, with
## the edge pass on, so their shader variants compile now rather than mid-game.
func _warm_shaders(from: float, to: float) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(256, 144)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = sky
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50, 30, 0)
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 6)
	vp.add_child(cam)
	cam.make_current()
	var outline := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	outline.mesh = quad
	outline.material_override = ArtStyle.outline_material()
	outline.extra_cull_margin = 16384.0
	outline.position.z = -1.0
	cam.add_child(outline)
	var mats := Warmup.material_list()
	var shapes: Array[Mesh] = [BoxMesh.new(), SphereMesh.new()]
	var total := mats.size() + Warmup.meshes.size()
	var i := 0
	while i < total:
		var batch: Array[Node] = []
		for k in BATCH:
			if i >= total:
				break
			var mi := MeshInstance3D.new()
			if i < mats.size():
				mi.mesh = shapes[i % shapes.size()]
				mi.material_override = mats[i]
			else:
				mi.mesh = Warmup.meshes[i - mats.size()]
			mi.position = Vector3((k % 4) - 1.5, (k / 4) - 1.0, 0.0) * 1.4
			vp.add_child(mi)
			batch.append(mi)
			i += 1
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		for n in batch:
			n.queue_free()
		_progress(lerpf(from, to, float(i) / total), "Preparing graphics  %d / %d" % [i, total])
	vp.queue_free()


func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var pic := TextureRect.new()
	pic.texture = load(Warmup.SPLASH_IMAGE)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(pic)
	# A dark band along the bottom for the title and the bar.
	var shade := TextureRect.new()
	var grad := GradientTexture2D.new()
	grad.gradient = Gradient.new()
	grad.gradient.set_color(0, Color(0.03, 0.04, 0.06, 0.0))
	grad.gradient.set_color(1, Color(0.03, 0.04, 0.06, 0.92))
	grad.fill_from = Vector2(0, 0)
	grad.fill_to = Vector2(0, 1)
	shade.texture = grad
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	shade.offset_top = -320
	root.add_child(shade)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = 64
	box.offset_right = -64
	box.offset_top = -230
	box.offset_bottom = -48
	box.add_theme_constant_override("separation", 10)
	root.add_child(box)
	var title := Label.new()
	title.text = "FREDDIBNAH"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(0.98, 0.97, 0.93))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Design it together.  Build it.  Bring it down."
	sub.add_theme_font_size_override("font_size", 24)
	sub.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
	box.add_child(sub)
	_bar = ProgressBar.new()
	_bar.name = "Progress"
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = 10
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.78, 0.2)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.15)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)
	box.add_child(_bar)
	var row := HBoxContainer.new()
	box.add_child(row)
	_status = Label.new()
	_status.name = "Status"
	_status.add_theme_color_override("font_color", Color(0.8, 0.82, 0.86))
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status)
	var ver := Label.new()
	ver.text = BuildInfo.label()
	ver.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
	row.add_child(ver)
