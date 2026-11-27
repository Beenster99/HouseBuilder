extends ModuleTest
## The 3D library's assets as placeable parts: the catalog takes them in with cost, services
## and capacity, the model places, costs, saves and loads them, and a room counts them.
##   tools/run_tests.sh building

const C := preload("res://modules/building/api/building_commands.gd")


func run_tests() -> void:
	var cat := BuildingCatalog.from_data(BuildingCatalog.DATA_SCRIPT.DATA)
	var before := cat.kinds_in("fixture").size()
	var added := cat.add_library(AssetLibrary.manifest())
	check(added >= 600 and cat.library_kinds().size() == added, "the catalog takes in the library's placeable assets (%d)" % added)
	check(cat.kinds_in("fixture").size() == before + added, "as fixtures")
	check(cat.problems().is_empty(), "with no catalog problems: %s" % [cat.problems().slice(0, 5)])
	check(not cat.has_kind("structure.section.ub_305x165x40") and not cat.has_kind("services.pipe.elbow_15")
			and not cat.has_kind("people." + "x"), "structure, pipe fittings and people stay out")
	var all_ok := true
	for k in cat.library_kinds():
		var spec := cat.kind(k)
		if str(spec.asset) != k or str(spec.group) == "" or float(spec.w) <= 0.0 or float(spec.h) <= 0.0 \
				or cat.rate(k, cat.materials_for(k)[0]).is_empty() or not cat.services_of(k).has("power_w"):
			all_ok = false
	check(all_ok, "every one has its asset, a group, a size, a price and services")
	var desk := cat.kind("office.desk.bench_4")
	check(int((desk.capacity as Dictionary).get("workstations", 0)) == 4 and cat.services_of("office.desk.bench_4").data,
			"a bench of four desks seats four workstations and needs data")
	var sink := cat.services_of("furniture.kitchen.sink_1000")
	check(sink.cold and sink.hot and sink.drain and not sink.gas, "a kitchen sink needs hot and cold water and a drain")
	check(cat.services_of("hospital.imaging.mri").power_w >= 50000, "an MRI scanner draws a lot of power")
	check(cat.services_of("services.radiator.double_1000").heating and cat.services_of("services.radiator.double_1000").heat_w > 0,
			"a radiator is on the heating and gives heat")
	check(cat.services_of("wc").cold and cat.services_of("wc").drain, "the catalog's own fixtures have services too")
	check(bool(cat.kind("vehicle.car.city_blue").loose) and cat.rate("vehicle.car.city_blue", cat.materials_for("vehicle.car.city_blue")[0]).rate == 0.0,
			"a parked car is not part of the build and costs nothing")
	check(cat.group_of("hospital.imaging.mri") == "Healthcare" and cat.group_of("sofa") == "Fittings", "kinds have palette groups")
	check(BuildingCatalog.library_rule("hospital.theatre.scrub_sink_3").cap.basin == 3, "longer rule prefixes override shorter ones")

	# In a model.
	var m := BuildingModel.new("lib", "Library test", cat)
	var room := str(m.apply(C.place_room("office", 0, C.rect(0, 0, 8, 6), "Open plan")).do.entry.id)
	var r := m.apply(C.place_part("office.desk.bench_4", 0, {"at": [3.0, 0.0, 3.0], "rot": 90.0}))
	check(not r.is_empty() and str(r.do.entry.kind) == "office.desk.bench_4", "a library desk is placed")
	m.apply(C.place_part("furniture.kitchen.sink_1000", 0, {"at": [7.0, 0.0, 5.0]}))
	check(BuildingQuantities.room(m, room).capacity == 4, "and counts four workstations in the room")
	var t := BuildingQuantities.totals(m)
	check(is_equal_approx(float((t.by_family as Dictionary).get("fixture", 0.0)), 2400.0 + 800.0), "and is costed (%s)" % t.by_family)
	var copy := BuildingModel.from_data(m.to_data(), cat)
	check(copy != null and copy.to_data() == m.to_data(), "library parts save and load")
	var plain := BuildingModel.from_data(m.to_data(), BuildingCatalog.from_data(BuildingCatalog.DATA_SCRIPT.DATA))
	check(plain != null and plain.parts.size() == 0, "a catalog without the library drops them on load, it does not fail")
