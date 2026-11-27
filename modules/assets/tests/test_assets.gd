extends ModuleTest
## The asset library: the manifest matches the model files, every asset loads with the
## nodes the manifest promises, and both looks and the fallback box work.
##   tools/run_tests.sh assets


func run_tests() -> void:
	var ids := AssetLibrary.ids()
	check(ids.size() >= 1950, "the manifest lists the library: %d assets" % ids.size())
	var catalog := BuildingCatalog.default_catalog()
	for kind: String in catalog.kinds_in("opening") + catalog.kinds_in("fixture"):
		check(AssetLibrary.id_for_kind(kind) != "", "catalog kind %s has an asset" % kind)
	check(AssetLibrary.id_for_kind("office.desk.bench_4") == "office.desk.bench_4" and AssetLibrary.id_for_kind("no.such.asset") == "", "an asset id used as a kind draws that asset")
	check(AssetLibrary.has("energy.line.pylon_lattice") and AssetLibrary.has("vehicle.lorry.trailer_white") and AssetLibrary.has("furniture.light.ring_pendant"), "Torque Shed models and the statement pieces are in the library")
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
	var wall := AssetLibrary.make("structure.cladding.render", {"length": 4.0, "height": 2.7})
	check(is_equal_approx(wall.scale.z, 4.0) and is_equal_approx(wall.scale.y, 2.7), "walls and cladding stretch along and up")
	wall.free()
	var lawn := AssetLibrary.make("landscape.ground.lawn", {"width": 5.0, "length": 8.0})
	check(is_equal_approx(lawn.scale.x, 5.0) and is_equal_approx(lawn.scale.z, 8.0), "floors and ground stretch both ways on plan")
	lawn.free()
	var fence := AssetLibrary.make("boundary.closeboard.h1800", {"length": 12.0})
	check(is_equal_approx(fence.scale.x, 12.0), "boundaries stretch along x")
	fence.free()

	# "lod": the real model close up, a box of its size far off. "fit": fill a given box.
	var far := AssetLibrary.make("opening.window.medium", {"lod": 40.0})
	var proxy := far.get_node_or_null("lod_box") as MeshInstance3D
	check(proxy != null and is_equal_approx(proxy.visibility_range_begin, 40.0), "lod adds a far box")
	if proxy:
		check((proxy.mesh as BoxMesh).size.is_equal_approx(AssetLibrary.bounds("opening.window.medium").size), "the far box is the model's size")
	for c in far.get_children():
		if c is MeshInstance3D and c != proxy:
			check(is_equal_approx((c as MeshInstance3D).visibility_range_end, 40.0), "lod hides the model beyond its distance: %s" % c.name)
	far.free()
	var own := AssetLibrary.bounds("opening.window.medium").size
	var fitted := AssetLibrary.make("opening.window.medium", {"fit": Vector3(own.x * 2.0, 0.0, 0.0)})
	check(is_equal_approx(fitted.scale.x, 2.0) and is_equal_approx(fitted.scale.y, 1.0), "fit scales only the axes it names")
	fitted.free()
	check(AssetLibrary.make_kind("no_such_kind", {"size": Vector3.ONE, "lod": 40.0}).get_node_or_null("lod_box") == null, "a fallback box needs no far box")

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
	var textured := Flags.is_on(AssetMaterials.FLAG)
	Flags.set_flag(AssetMaterials.FLAG, false)
	AssetLibrary.apply_look(win)
	check(glass.material_override == null and glass.mesh.surface_get_material(0) != null, "realistic without textures keeps the model's own PBR materials")
	Flags.set_flag(AssetMaterials.FLAG, true)
	AssetLibrary.apply_look(win)
	check(glass.material_override is StandardMaterial3D and (glass.material_override as StandardMaterial3D).albedo_color.a < 1.0, "realistic with textures gives glass its see-through slot material")
	var rendered := AssetLibrary.make("structure.cladding.render", {"length": 4.0, "height": 2.5})
	var skin := (rendered.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
	check(skin != null and skin.albedo_texture != null and skin.normal_texture != null and skin.uv1_triplanar, "a rendered wall gets a tiling surface texture and normal map")
	check(skin != null and is_equal_approx(skin.uv1_scale.z / skin.uv1_scale.x, 4.0), "a stretched piece keeps its texture at true size: %s" % str(skin.uv1_scale if skin else Vector3.ZERO))
	rendered.free()
	var bad_slots := 0
	for id in AssetLibrary.ids():
		for p: Dictionary in AssetLibrary.info(id).pieces:
			if not AssetMaterials.has(str(p.slot)):
				bad_slots += 1
	check(bad_slots == 0, "every piece's slot has a realistic material (%d missing)" % bad_slots)
	for name: String in AssetMaterials.table():
		var pat := AssetMaterials.pattern(name)
		if pat != "" and not ResourceLoader.exists(AssetMaterials.TEXTURES + pat + "_a.png"):
			bad_slots += 1
	check(bad_slots == 0, "every surface pattern has its texture")
	Flags.set_flag(AssetMaterials.FLAG, textured)
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
