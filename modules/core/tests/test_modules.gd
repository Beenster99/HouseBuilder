extends ModuleTest
## Modules: manifests found, dependency order, flags and missing dependencies respected.
##   tools/run_tests.sh core


func run_tests() -> void:

	var manifests: Dictionary = Modules.read_manifests("res://modules")
	check(manifests.has("ui") and manifests.has("multiplayer"), "manifests found: %s" % str(manifests.keys()))
	check(not manifests.has("core"), "core is built in, not loaded from a manifest")
	for id in manifests:
		var m: ModuleManifest = manifests[id]
		for dep in m.depends_on:
			check(manifests.has(dep), "%s depends on known module %s" % [id, dep])

	var order: PackedStringArray = Modules.load_order(manifests)
	check(order.size() == manifests.size(), "every module ordered (no cycles)")
	for id in manifests:
		for dep in manifests[id].depends_on:
			check(order.find(dep) < order.find(id), "%s loads before %s" % [dep, id])

	var saved := Flags.all()
	Flags.use({"core": true, "ui": true, "multiplayer": true})
	Modules.load_all()
	check(Modules.is_loaded("multiplayer"), "multiplayer loads with its flag on")
	check(Modules.bus("multiplayer") is MultiplayerBus, "multiplayer bus reachable")

	Flags.use({"core": true, "ui": true, "multiplayer": false})
	Modules.load_all()
	check(not Modules.is_loaded("multiplayer"), "multiplayer off by flag")
	check(Modules.skipped_reason("multiplayer") == "flag off", "skip reason for a flag")

	Flags.use(saved)
	Modules.load_all()
