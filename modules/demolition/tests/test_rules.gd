extends ModuleTest
## Demolition rules: what loses support, chunks, drop zone and score, on the demo office.
##   tools/run_tests.sh demolition

const DemoOffice := preload("res://modules/demolition/internal/demo_office.gd")


func run_tests() -> void:
	var parts := DemoOffice.parts()
	check(parts.size() == 12 + 5 * (12 + 9 + 8 + 6), "the office has its parts: %d" % parts.size())
	check(DemolitionRules.unsupported(parts, {}).is_empty(), "the intact building stands")

	var one := DemolitionRules.unsupported(parts, {"col_0_1_1": true})
	check(one.has("bx_0_0_1") and one.has("bx_0_1_1"), "beams on a lost column fall: %s" % str(one))
	check(one.has("col_1_1_1"), "the column above a lost column loses its support")
	check(not one.has("col_0_0_0"), "other columns stand")

	var ground: Dictionary = {}
	for i in 4:
		for k in 3:
			ground["col_0_%d_%d" % [i, k]] = true
	var all := DemolitionRules.unsupported(parts, ground)
	check(all.size() == parts.size() - 12 - 12, "lose every ground column and everything above comes down: %d" % all.size())

	var slab := {"id": "s", "family": "slab", "aabb": AABB(Vector3.ZERO, Vector3(10, 0.2, 5))}
	var cs := DemolitionRules.chunks(slab)
	var vol := 0.0
	for c in cs:
		vol += c.get_volume()
	check(cs.size() == 6 * 3 and is_equal_approx(vol, 10.0), "a 10 x 5 slab breaks into 18 pieces of the same volume: %d" % cs.size())
	var huge := {"id": "h", "family": "wall", "aabb": AABB(Vector3.ZERO, Vector3(60, 20, 1))}
	check(DemolitionRules.chunks(huge).size() <= DemolitionRules.MAX_CHUNKS_PER_PART, "chunks per part are capped")
	check(DemolitionRules.need({"family": "beam"}, 2) == 2 and DemolitionRules.need({"family": "column"}, 1) == 1
			and DemolitionRules.need({"family": "slab"}, 4) == 3, "support needs by family")
	check(DemolitionRules.strength({"family": "foundation"}) == INF, "foundations never break loose")

	var zone := DemolitionRules.drop_zone(parts, 4.0)
	check(zone.has_point(Vector2(7.5, 5.0)) and not zone.has_point(Vector2(-10, 5)), "the drop zone covers the footprint plus margin: %s" % zone)
	var clean := DemolitionRules.score(95.0, 100.0, 0.0, 120.0, 0, 12)
	var hit := DemolitionRules.score(95.0, 100.0, 0.0, 120.0, 1, 12)
	var half := DemolitionRules.score(50.0, 50.0, 60.0, 120.0, 0, 12)
	check(clean.score >= 90 and clean.grade == "Textbook", "a clean drop scores high: %s" % str(clean))
	check(hit.score < clean.score - 20 and hit.grade != "Textbook", "hitting a neighbour costs dearly")
	check(half.score < clean.score and half.grade == "Partial", "half standing is partial: %s" % str(half))

	# The measures a demolition job is judged on.
	var job := DemolitionRules.result(90.0, 100.0, 12.0, 120.0, 1, 9, 20.0)
	check(is_equal_approx(float(job.collapsed), 0.9) and is_equal_approx(float(job.debris_outside), 0.2)
			and is_equal_approx(float(job.debris_outside_m3), 20.0) and int(job.neighbours_hit) == 1 and int(job.charges_used) == 9,
			"a result carries share collapsed, debris off the plot, neighbours hit and charges used: %s" % str(job))
	check(DemolitionBus._plot_of([[0, 0], [10, 0], [10, 8]]).size() == 3 and DemolitionBus._plot_of([[0, 0]]).is_empty(),
			"a plot outline reads from [[x, z], ...]")
