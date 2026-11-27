extends ModuleTest
## Mover groups: debris packed 12 bytes a body, only what moved, played back interpolated.
##   tools/run_tests.sh multiplayer


func run_tests() -> void:
	var worst := 0.0
	for k in 200:
		var q := Quaternion(Vector3(sin(k), cos(k * 1.3), 0.4).normalized(), k * 0.37)
		var back := NetMoverGroups._unpack_quat(NetMoverGroups._pack_quat(q))
		worst = maxf(worst, q.angle_to(back))
	check(worst < 0.01, "rotations survive packing to within half a degree: %.4f rad" % worst)

	var host := NetMoverGroups.new()
	var peer := NetMoverGroups.new()
	var origin := Vector3(100, 0, -50)
	host.register("d", origin)
	peer.register("d", origin)
	var a := Node3D.new()
	var b := Node3D.new()
	var pa := Node3D.new()
	var pb := Node3D.new()
	for n in [a, b, pa, pb]:
		add_child(n)
	host.set_node("d", 3, a)
	host.set_node("d", 700, b)
	peer.set_node("d", 3, pa)
	peer.set_node("d", 700, pb)
	a.global_transform = Transform3D(Basis(Vector3.UP, 0.5), origin + Vector3(1.234, 5.0, -2.0))
	b.global_position = origin + Vector3(-3, 0.5, 9)
	var out := host.outgoing()
	check(out.has("d") and (out.d as Array).size() == 1 and (out.d[0] as PackedByteArray).size() == 2 + 2 * 12,
			"a batch is 12 bytes a body")
	peer.receive("d", 1.0, out.d[0])
	check(host.outgoing().is_empty(), "nothing is sent again while nothing moves")
	a.global_position += Vector3(1, 0, 0)
	var moved := host.outgoing()
	check(moved.has("d") and (moved.d[0] as PackedByteArray).size() == 2 + 12, "only the body that moved is sent")
	peer.receive("d", 2.0, moved.d[0])
	peer.play_back(1.5)
	check(pa.global_position.distance_to(origin + Vector3(1.734, 5.0, -2.0)) < 0.02, "played back half way between samples")
	peer.play_back(3.0)
	check(pa.global_position.distance_to(a.global_position) < 0.01 and pb.global_position.distance_to(b.global_position) < 0.01,
			"and held at the last one")
	check(absf(pa.global_transform.basis.get_euler().y - 0.5) < 0.01, "with its rotation")
	for n in [a, b, pa, pb]:
		n.queue_free()
