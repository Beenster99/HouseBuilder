extends ModuleTest
## The Phase 0 site: crates are host-validated events (snapped, kept on the plot, capped),
## a join snapshot carries them, the site scene shows the local cursor and Jolt drops a crate
## onto the ground.
##   tools/run_tests.sh sandbox

var rejected: Array[String] = []


func run_tests() -> void:
	var bus := Modules.bus("sandbox") as SandboxBus
	check(bus != null, "sandbox bus loaded")
	if bus == null:
		return
	var start := Menu.start()
	check(int(start.get("priority", -1)) >= 10 and (start.get("scene", "") == SandboxBus.SITE_SCENE
			or int(start.get("priority", -1)) > 10), "Start goes to the sandbox site unless a higher start claims it")
	check(SandboxBus.snap(Vector3(1.13, 0.0, -2.38)) == Vector3(1.25, 0.0, -2.5), "cursor snaps to the 0.25 m grid")
	check(SandboxBus.cursor_id(2) == "player:2:cursor", "cursor ids are player movers")
	check(bus.net.mover_authority(SandboxBus.cursor_id(2)) == 2, "each player drives their own cursor")

	bus.net.request_rejected.connect(func(n, why): rejected.append("%s: %s" % [n, why]))
	bus.request_drop(Vector3(1.1, 0.0, 2.0))
	check(bus.crates.size() == 1, "a drop applies at once solo")
	check(bus.crates.get("crate:1") == Vector3(1.0, SandboxBus.DROP_HEIGHT, 2.0), "drop snapped and raised: %s" % str(bus.crates))
	bus.request_drop(Vector3(500, 0, 0))
	check(bus.crates.size() == 1 and rejected.size() == 1, "a drop off the plot is refused: %s" % str(rejected))

	var snap := bus.get_net_snapshot()
	bus.request_clear()
	check(bus.crates.is_empty(), "clear removes every crate")
	bus.apply_net_snapshot(snap)
	check(bus.crates.has("crate:1"), "a join snapshot brings the crates back")
	bus.request_drop(Vector3.ZERO)
	check(bus.crates.has("crate:2"), "ids keep counting after a snapshot")
	bus.request_clear()

	for i in SandboxBus.MAX_CRATES + 1:
		bus.request_drop(Vector3(i % 10, 0, -i / 10))
	check(bus.crates.size() == SandboxBus.MAX_CRATES, "crates capped at %d" % SandboxBus.MAX_CRATES)
	bus.request_clear()

	# The site scene: local cursor, and a crate that Jolt drops onto the ground.
	var site: Node3D = load("res://modules/sandbox/internal/site.tscn").instantiate()
	add_child(site)
	await frames(2)
	check(site.find_child("Cursor_1", true, false) != null, "the local player's cursor is on the site")
	check(site.find_child("SiteHud", true, false) != null, "the site HUD is up")
	bus.request_drop(Vector3(3, 0, 3))
	check(site.crate_count() == 1, "the site shows the new crate")
	var crate := site.find_child("crate_*", true, false) as RigidBody3D
	check(crate != null and not crate.freeze, "the host simulates its crates")
	check(ProjectSettings.get_setting("physics/3d/physics_engine") == "Jolt Physics", "Jolt is the 3D physics engine")
	for i in 240:
		await get_tree().physics_frame
	check(crate != null and crate.global_position.y < 1.0 and crate.global_position.y > 0.3,
			"the crate fell and came to rest on the ground: y=%.2f" % (crate.global_position.y if crate else -1.0))
	bus.request_clear()
	await frames(1)
	check(site.crate_count() == 0, "clear empties the site")
	site.queue_free()
	await frames(1)
