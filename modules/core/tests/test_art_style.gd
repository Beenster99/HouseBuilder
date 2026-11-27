extends ModuleTest
## The two looks: the clean model colour codes families, realistic picks a material per part.
##   tools/run_tests.sh core


func run_tests() -> void:
	var was: Variant = GraphicsOptions.get_value("art_style")
	GraphicsOptions.set_value("art_style", ArtStyle.MODEL)
	check(not ArtStyle.realistic(), "the architectural model is the default look")
	var wall := ArtStyle.material("masonry", "wall")
	check(wall == ArtStyle.material("masonry", "wall"), "materials are shared, not made per part")
	check(wall.albedo_color.is_equal_approx(ArtStyle.MODEL_WHITE) and ArtStyle.material("steel", "beam") == wall,
			"in the model look every solid part is the same white")
	check(ArtStyle.material("", "opening").transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "openings are see-through")
	GraphicsOptions.set_value("art_style", ArtStyle.REALISTIC)
	check(ArtStyle.realistic(), "Look switches to realistic")
	var brick := ArtStyle.material("masonry", "wall")
	check(brick != wall and brick.albedo_color.is_equal_approx(ArtStyle.REAL.masonry[0]), "a realistic wall is brick")
	check(ArtStyle.material("", "beam").metallic > 0.5, "a beam with no material is steel")
	check(ArtStyle.material("timber", "slab").albedo_color.is_equal_approx(ArtStyle.REAL.timber[0]), "the part's own material wins")
	check(ArtStyle.material("", "opening").albedo_color.a < 1.0, "realistic windows are glass")
	check(brick.uv1_world_triplanar, "realistic surfaces map in world space")
	check(ArtStyle.ground() != ArtStyle.material("", "slab"), "the ground has its own material")
	# An asset library's material: itself when realistic, white or pale glass in the model look.
	var oak := StandardMaterial3D.new()
	oak.albedo_color = Color(0.5, 0.3, 0.1)
	var pane := StandardMaterial3D.new()
	pane.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ArtStyle.register_material("test_oak", oak)
	ArtStyle.register_material("test_pane", pane)
	check(ArtStyle.material("test_oak", "") == oak and ArtStyle.has_material("test_oak"), "a registered material shows as itself when realistic")
	GraphicsOptions.set_value("art_style", ArtStyle.MODEL)
	check(ArtStyle.material("test_oak", "").albedo_color.is_equal_approx(ArtStyle.MODEL_WHITE), "and white in the model look")
	check(ArtStyle.material("test_pane", "").albedo_color.is_equal_approx(ArtStyle.MODEL_GLASS), "see-through ones are pale glass")
	ArtStyle.unregister_material("test_oak")
	ArtStyle.unregister_material("test_pane")
	# The edge-line pass goes on cameras in the model look and comes off in realistic.
	var cam := Camera3D.new()
	add_child(cam)
	ArtStyle.apply_to_camera(cam)
	check(cam.get_node_or_null(ArtStyle.OUTLINE_NODE) != null, "model look: the camera draws edge lines")
	GraphicsOptions.set_value("art_style", ArtStyle.REALISTIC)
	ArtStyle.apply_to_camera(cam)
	await frames(1)
	check(cam.get_node_or_null(ArtStyle.OUTLINE_NODE) == null, "realistic: no edge lines")
	cam.queue_free()
	GraphicsOptions.set_value("art_style", was)
