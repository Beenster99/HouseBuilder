extends ModuleTest
## The desync check's fingerprints: the same state hashes the same whatever order it was
## built in, any change shows, and the built-in sections follow the shared building.
##   tools/run_tests.sh perf


func run_tests() -> void:
	var a := {"x": 1.0, "y": [1, 2, {"q": "s", "p": 2.5}], "z": Vector3(1, 2, 3)}
	var b := {"z": Vector3(1, 2, 3), "y": [1, 2, {"q": "s", "p": 2.5}], "x": 1.0}
	check(PerfBus.hash_of(a) == PerfBus.hash_of(b), "key order doesn't matter")
	b.y[2].p = 2.6
	check(PerfBus.hash_of(a) != PerfBus.hash_of(b), "a changed value shows")
	var parts_a := {"p1": {"kind": "wall", "a": [0, 0, 0]}, "p2": {"kind": "slab"}}
	var parts_b := {"p2": {"kind": "slab"}, "p1": {"kind": "wall", "a": [0, 0, 0]}}
	check(PerfBus.hash_of({"parts": parts_a}) == PerfBus.hash_of({"parts": parts_b}), "tables in another order agree")
	parts_b.p1.a[1] = 1
	check(PerfBus.hash_of({"parts": parts_a}) != PerfBus.hash_of({"parts": parts_b}), "a change deep in an entry shows")
	check(PerfBus.hash_of([1, 2]) != PerfBus.hash_of([2, 1]), "list order matters")

	var perf := Modules.bus("perf") as PerfBus
	var building := Modules.bus("building") as BuildingBus
	check("building" in perf.digest_sections() and "demolition" in perf.digest_sections(), "built-in sections: %s" % perf.digest_sections())
	building.model.load_data(ScaleBuildings.data("house"))
	var before: int = perf.digests().building
	var copy := BuildingModel.new("", "", building.catalog)
	copy.load_data(building.model.to_data())
	building.model.load_data(copy.to_data())
	check(int(perf.digests().building) == before, "the building reloaded from its save has the same fingerprint")
	building.sync.edit(BuildingCommands.place_part("column", 0, {"at": [1.0, 0.0, 1.0]}, "steel"))
	check(int(perf.digests().building) != before, "an edit changes the fingerprint")

	var seen: Array = []
	perf.register_digest("test.thing", func() -> Variant: return {"n": seen.size()})
	check("test.thing" in perf.digest_sections(), "modules can add sections")
	perf.unregister_digest("test.thing")
	check(not "test.thing" in perf.digest_sections(), "and take them away")

	# Solo is a session of one: the check runs and matches.
	var ok_before := perf.checks_ok
	perf.send_digest()
	await frames(2)
	check(perf.checks_ok == ok_before + 1 and perf.desyncs.is_empty(), "solo digest matches")
	building.reset_data()

	# Cost: the check runs every few seconds on every peer, so it must fit in a frame.
	building.model.load_data(ScaleBuildings.data("terminal"))
	var t0 := Time.get_ticks_usec()
	perf.digests()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("digest of the terminal (%d parts): %.1f ms" % [building.model.parts.size(), ms])
	check(ms < PerfBudget.CLICK_MS / 2.0, "fingerprinting the biggest building takes %.1f ms (budget %.0f)" % [ms, PerfBudget.CLICK_MS / 2.0])
	building.reset_data()
