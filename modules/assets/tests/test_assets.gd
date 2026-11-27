extends ModuleTest
## The asset library: the manifest matches the model files, every asset loads with the
## nodes the manifest promises, and both looks and the fallback box work.
##   tools/run_tests.sh assets


func run_tests() -> void:
	var ids := AssetLibrary.ids()
	check(ids.size() >= 80, "the manifest lists the library: %d assets" % ids.size())
	var catalog := BuildingCatalog.default_catalog()
	for kind: String in catalog.kinds_in("opening") + catalog.kinds_in("fixture"):
		check(AssetLibrary.id_for_kind(kind) != "", "catalog kind %s has an asset" % kind)
	check(AssetLibrary.id_for_kind("ub_305x165x40") == "structure.section.ub_305x165x40", "steel sections are found by catalog section id")

	var bad := 0
	for id in ids:
		var e := AssetLibrary.info(id)
		var node := AssetLibrary.make(id)
		var names := {}
		for c in node.get_children():
			names[str(c.name)] = c
		var ok := not node.has_meta("asset_fallback") and int(e.tris) > 0 and int(e.tris) <= 60000
		for p: Dictionary in e.pieces:
			ok = ok and names.has(p.node) and names[p.node] is MeshInstance3D and float(p.mass) > 0.0
		var b := AssetLibrary.bounds(id)
		ok = ok and b.size.x > 0.0 and b.size.y > 0.0 and b.size.z > 0.0
		if not ok:
			bad += 1
			printerr("  asset fails its checks: ", id)
		node.free()
	check(bad == 0, "every asset loads with its pieces, a size and a triangle count in budget (%d bad)" % bad)

	var bed := AssetLibrary.bounds("fixture.bed_double")
	check(is_equal_approx(bed.size.x, 1.35) and is_equal_approx(bed.size.z, 2.0), "a double bed fills its catalog footprint: %s" % str(bed.size))
	var door := AssetLibrary.bounds("opening.door.fire")
	check(is_equal_approx(door.size.x, 0.926) and is_equal_approx(door.size.y, 2.04) and is_zero_approx(door.position.y), "a fire door fills its catalog opening from the floor")
	var ub := AssetLibrary.info("structure.section.ub_406x178x60")
	check(absf(float(ub.mass) - 60.1) < 1.0, "a 1 m length of UB 406x178x60 weighs its 60 kg: %.1f" % float(ub.mass))

	var beam := AssetLibrary.make("structure.section.ub_305x165x40", {"length": 6.0})
	check(is_equal_approx(beam.scale.z, 6.0) and is_equal_approx(beam.scale.x, 1.0), "sections stretch along their length")
	beam.free()

	var win := AssetLibrary.make("opening.window.medium")
	check(AssetLibrary.stages("opening.window.medium") == PackedStringArray(["frame", "glazing", "ironmongery"]), "a window builds frame, glazing, ironmongery")
	AssetLibrary.show_stages(win, ["frame"])
	var shown := 0
	for c in win.get_children():
		if c is MeshInstance3D and c.visible:
			shown += 1
			check(str(c.name).begins_with("frame__"), "only the frame stage shows: %s" % c.name)
	check(shown >= 1, "the frame stage has meshes")
	var was := int(GraphicsOptions.get_value("art_style"))
	var glass := win.get_node("glazing__glass") as MeshInstance3D
	GraphicsOptions.set_value("art_style", ArtStyle.REALISTIC)
	AssetLibrary.apply_look(win)
	check(glass.material_override == null and glass.mesh.surface_get_material(0) != null, "realistic keeps the model's own PBR materials")
	GraphicsOptions.set_value("art_style", ArtStyle.MODEL)
	AssetLibrary.apply_look(win)
	check(glass.material_override != null, "the sketch look overrides them with ArtStyle's")
	GraphicsOptions.set_value("art_style", was)
	win.free()

	var missing := AssetLibrary.make_kind("no_such_kind", {"size": Vector3(1, 2, 3)})
	var box := missing.get_child(0) as MeshInstance3D
	check(missing.has_meta("asset_fallback") and (box.mesh as BoxMesh).size == Vector3(1, 2, 3), "an unknown kind gives a plain box of the asked size")
	missing.free()
	AssetLibrary.clear_cache()
