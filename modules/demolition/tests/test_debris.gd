extends ModuleTest
## Finer breakage: a charge throws off fragments finest round its point, each material breaks
## its own way, they land and settle, and charges can sit at a point on a part.
##   tools/run_tests.sh demolition

const Debris := preload("res://modules/demolition/internal/debris.gd")
const DemoOffice := preload("res://modules/demolition/internal/demo_office.gd")


func run_tests() -> void:
	var d: Node3D = Debris.new()
	add_child(d)
	var box := AABB(Vector3(0, 0, 0), Vector3(4, 3, 0.3))
	var centre := Vector3(0.5, 1.0, 0.15)
	var n: int = d.burst(box, centre, "concrete", StandardMaterial3D.new(), 1.0, "w1")
	check(n >= 12 and d.live() == n, "a charge throws off fragments: %d" % n)
	var b: Dictionary = d.bursts()[0]
	var near_sizes := 0.0
	var far_sizes := 0.0
	var near_n := 0
	var far_n := 0
	for i in (b.pos as PackedVector3Array).size():
		var dist: float = (b.pos[i] as Vector3).distance_to(centre)
		var size: float = (b.scale[i] as Vector3).length()
		if dist < 1.0:
			near_sizes += size
			near_n += 1
		elif dist > 2.0:
			far_sizes += size
			far_n += 1
	check(near_n > far_n, "most fragments come from round the charge: %d near, %d far" % [near_n, far_n])
	check(near_n > 0 and far_n > 0 and near_sizes / near_n < far_sizes / far_n,
			"finer near the charge than far from it")

	# Each material breaks its own way.
	d.burst(AABB(Vector3(10, 0, 0), Vector3(0.2, 3, 0.2)), Vector3(10.1, 1.5, 0.1), "timber", StandardMaterial3D.new(), 1.0, "t")
	d.burst(AABB(Vector3(20, 0, 0), Vector3(0.2, 3, 0.2)), Vector3(20.1, 1.5, 0.1), "steel", StandardMaterial3D.new(), 1.0, "s")
	var timber: Dictionary = d.bursts()[1]
	var steel: Dictionary = d.bursts()[2]
	var long_thin := true
	for s: Vector3 in timber.scale:
		long_thin = long_thin and s.z > s.x * 4.0
	check(long_thin, "timber splinters, long and thin")
	var flat := true
	for s: Vector3 in steel.scale:
		flat = flat and s.y < s.x * 0.2
	check(flat and (steel.mmi as MultiMeshInstance3D).multimesh.mesh != (b.mmi as MultiMeshInstance3D).multimesh.mesh,
			"steel tears into thin shards and bent lengths")

	# They fall, land and settle on the ground.
	await get_tree().create_timer(5.0).timeout
	var above := 0
	for p: Vector3 in b.pos:
		if p.y < -0.01:
			above += 1
	check(above == 0, "nothing falls through the ground")
	check(d.moving() < d.live() / 4, "most have settled: %d of %d moving" % [d.moving(), d.live()])
	d.clear()
	check(d.live() == 0, "cleared")
	d.queue_free()

	# Charges at a point on a part.
	var bus := Modules.bus("demolition") as DemolitionBus
	bus.start_demolition(DemoOffice.parts(), "Office", {"open": false})
	var col: Dictionary = bus.by_id["col_0_0_0"]
	var at := (col.aabb as AABB).position + Vector3(0.1, 0.5, 0.1)
	bus.request_charge("col_0_0_0", 0.0, at)
	check(bus.charges.has("col_0_0_0") and bus.charge_point("col_0_0_0").distance_to(at) < 0.01, "a charge sits where it was placed")
	bus.request_charge("col_0_0_0", 0.0, at + Vector3(0, 100, 0))
	check((col.aabb as AABB).grow(0.51).has_point(bus.charge_point("col_0_0_0")), "kept on its part")
	bus.request_charge("col_0_0_0", 0.0, bus.charge_point("col_0_0_0"))
	check(not bus.charges.has("col_0_0_0") and not bus.charge_at.has("col_0_0_0"), "the same again takes it off")
	bus.request_charge("col_0_0_0", 0.0)
	check(bus.charge_point("col_0_0_0").distance_to((col.aabb as AABB).get_center()) < 0.01, "no point given: the part's centre")
	bus.apply_net_snapshot({})
