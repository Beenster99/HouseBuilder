extends CanvasLayer
## The profiler overlay (F3): a small see-through panel in the top-left corner, refreshed
## four times a second from PerfBus.snapshot(). Green while the last 10 s meet the 60 fps
## target, amber when they don't, red on a desync.

const REFRESH := 0.25
const GOOD := Color(0.55, 0.95, 0.55)
const WARN := Color(1.0, 0.78, 0.3)
const BAD := Color(1.0, 0.4, 0.35)

var bus: Node
var _label: Label
var _wait := 0.0


func bind(perf_bus: Node) -> void:
	bus = perf_bus


func _ready() -> void:
	layer = 120
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(8, 8)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.6)
	sb.set_content_margin_all(8)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 13)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["monospace", "Consolas", "Menlo", "DejaVu Sans Mono"])
	_label.add_theme_font_override("font", mono)
	panel.add_child(_label)
	add_child(panel)
	_refresh()


func _process(delta: float) -> void:
	_wait -= delta
	if _wait <= 0.0:
		_wait = REFRESH
		_refresh()


func _refresh() -> void:
	if bus == null:
		return
	var s: Dictionary = bus.call("snapshot")
	_label.text = text_for(s, _custom_monitors())
	var colour := GOOD
	if str(s.verdict) != "":
		colour = WARN
	if int(s.desyncs) > 0:
		colour = BAD
	_label.add_theme_color_override("font_color", colour)


static func text_for(s: Dictionary, custom: Array = []) -> String:
	var lines: PackedStringArray = []
	lines.append("%3.0f fps   %5.1f ms   p95 %5.1f   p99 %5.1f   worst %5.1f" % [s.fps, s.mean_ms, s.p95_ms, s.p99_ms, s.worst_ms])
	lines.append("over budget %4.1f%%   hitches %d   target %d fps: %s" % [float(s.over_budget) * 100.0, s.hitches,
			PerfBudget.TARGET_FPS, "OK" if str(s.verdict) == "" else str(s.verdict)])
	lines.append("CPU script %4.1f ms   physics %4.1f ms" % [s.script_ms, s.physics_ms])
	lines.append("draw calls %d   objects %d   triangles %s   nodes %d" % [s.draw_calls, s.objects, _big(int(s.primitives)), s.nodes])
	lines.append("memory %.0f MB   video %.0f MB" % [s.memory_mb, s.video_mb])
	if bool(s.online):
		lines.append("%s, %d players   round trip %.0f ms   sync %s (%d checks)" % ["host" if bool(s.host) else "joined",
				s.players, s.rtt_ms, _sync_text(s), s.sync_checks])
		lines.append("up %s/s   down %s/s   movers %d   view delay %.0f ms" % [_bytes(float(s.get("sent_bps", 0.0))),
				_bytes(float(s.get("recv_bps", 0.0))), int(s.get("movers", 0)), float(s.get("view_delay_ms", 0.0))])
	else:
		lines.append("offline")
	for row: Array in custom:
		lines.append("%s  %s" % [row[0], row[1]])
	return "\n".join(lines)


static func _sync_text(s: Dictionary) -> String:
	if int(s.desyncs) == 0:
		return "OK"
	return "%d DESYNCS%s" % [s.desyncs, "" if bool(s.get("in_sync", true)) else ", out of sync now"]


static func _bytes(b: float) -> String:
	if b >= 1048576.0:
		return "%.1f MB" % (b / 1048576.0)
	if b >= 1024.0:
		return "%.0f KB" % (b / 1024.0)
	return "%.0f B" % b


static func _big(n: int) -> String:
	if n >= 1000000:
		return "%.1fM" % (n / 1000000.0)
	if n >= 1000:
		return "%.0fk" % (n / 1000.0)
	return str(n)


static func _custom_monitors() -> Array:
	var out: Array = []
	for m: StringName in Performance.get_custom_monitor_names():
		var v: Variant = Performance.get_custom_monitor(m)
		out.append([str(m).trim_prefix("fred/"), ("%.2f" % v) if v is float else str(v)])
	return out
