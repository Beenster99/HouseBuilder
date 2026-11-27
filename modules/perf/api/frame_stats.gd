class_name FrameStats
extends RefCounted
## A rolling window of frame times (ms) with the numbers the 60 fps target is judged on:
## the mean, percentiles, the share of frames over budget and hitches (long single frames,
## which players feel even when the mean is fine).
##
##   var fs := FrameStats.new(600)
##   fs.add(delta * 1000.0)          # every frame
##   fs.summary()                    # {fps, mean_ms, p50_ms, p95_ms, p99_ms, worst_ms, over_budget, hitches, frames}
##   fs.meets(PerfBudget.TARGET)     # "" when it does, else why not

var capacity := 600
var _ring := PackedFloat32Array()
var _next := 0
var _count := 0


func _init(window_frames: int = 600) -> void:
	capacity = maxi(1, window_frames)
	_ring.resize(capacity)


func add(frame_ms: float) -> void:
	_ring[_next] = frame_ms
	_next = (_next + 1) % capacity
	_count = mini(_count + 1, capacity)


func clear() -> void:
	_next = 0
	_count = 0


func size() -> int:
	return _count


func values() -> PackedFloat32Array:
	if _count < capacity:
		return _ring.slice(0, _count)
	return _ring.slice(_next) + _ring.slice(0, _next)


## The q-th percentile (0..1) of the window, nearest rank.
func percentile(q: float) -> float:
	if _count == 0:
		return 0.0
	var v := values()
	v.sort()
	return v[clampi(ceili(q * _count) - 1, 0, _count - 1)]


func summary(budget_ms: float = PerfBudget.FRAME_MS) -> Dictionary:
	if _count == 0:
		return {"frames": 0, "fps": 0.0, "mean_ms": 0.0, "p50_ms": 0.0, "p95_ms": 0.0, "p99_ms": 0.0,
				"worst_ms": 0.0, "over_budget": 0.0, "hitches": 0}
	var v := values()
	v.sort()
	var total := 0.0
	var over := 0
	var hitches := 0
	for f in v:
		total += f
		if f > budget_ms * PerfBudget.SLACK:
			over += 1
		if f > PerfBudget.HITCH_MS:
			hitches += 1
	var mean := total / _count
	return {
		"frames": _count,
		"fps": 1000.0 / mean if mean > 0.0 else 0.0,
		"mean_ms": mean,
		"p50_ms": v[clampi(ceili(0.5 * _count) - 1, 0, _count - 1)],
		"p95_ms": v[clampi(ceili(0.95 * _count) - 1, 0, _count - 1)],
		"p99_ms": v[clampi(ceili(0.99 * _count) - 1, 0, _count - 1)],
		"worst_ms": v[_count - 1],
		"over_budget": float(over) / _count,
		"hitches": hitches,
	}


## "" when the window meets the target (see PerfBudget), else the first reason it doesn't.
func meets(target: Dictionary = PerfBudget.TARGET) -> String:
	var s := summary(float(target.frame_ms))
	if int(s.frames) == 0:
		return "no frames recorded"
	if float(s.mean_ms) > float(target.frame_ms):
		return "mean frame %.1f ms (%.0f fps) is over %.1f ms" % [s.mean_ms, s.fps, target.frame_ms]
	if float(s.p95_ms) > float(target.p95_ms):
		return "95th percentile frame %.1f ms is over %.1f ms" % [s.p95_ms, target.p95_ms]
	if float(s.over_budget) > float(target.max_over_budget):
		return "%.0f%% of frames over budget (allowed %.0f%%)" % [float(s.over_budget) * 100.0, float(target.max_over_budget) * 100.0]
	if int(s.hitches) > int(target.max_hitches):
		return "%d hitches over %.0f ms (allowed %d)" % [s.hitches, PerfBudget.HITCH_MS, target.max_hitches]
	return ""
