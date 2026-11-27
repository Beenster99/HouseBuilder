extends ModuleTest
## The two looks: the clean model colour codes families, realistic picks a material per part.
##   tools/run_tests.sh core


func run_tests() -> void:
	var was: Variant = GraphicsOptions.get_value("art_style")
	GraphicsOptions.set_value("art_style", ArtStyle.MODEL)
	check(not ArtStyle.realistic(), "the architectural model is the default look")
	var wall := ArtStyle.material("masonry", "wall")
	check(wall == ArtStyle.material("masonry", "wall"), "materials are shared, not made per part")
	check(wall.albedo_color.is_equal_approx(ArtStyle.MODEL_COLOURS.wall), "a model wall is the model's wall colour")
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
	GraphicsOptions.set_value("art_style", was)
