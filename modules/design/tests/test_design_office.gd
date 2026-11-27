extends ModuleTest
## The design office (flag design.office): the hall's window wall onto a shared vista, its
## lights and furniture, the Vista console, and turning any picture into the sky.

const HallScene := preload("res://modules/design/internal/hall/design_hall.tscn")
const VistaImage := preload("res://modules/design/internal/hall/office/vista_image.gd")


func run_tests() -> void:
	if not Flags.is_on("design.office"):
		check(true, "the office is off")
		return
	_pictures()
	var vista: Node = Modules.bus("design").get_node_or_null("Vista")
	check(vista != null, "the design bus keeps the shared vista")
	(Modules.bus("building") as BuildingBus).reset_data()
	var hall: Node3D = HallScene.instantiate()
	add_child(hall)
	await frames(3)
	var office: Node3D = hall.get_node_or_null("Office")
	check(office != null, "the hall is an office")
	check(not (hall.get("walls") as Dictionary).has("front"), "its front wall is glass, not screens")
	check(office.get_node_or_null("Glass") != null and office.get_node_or_null("WindowWall") != null, "glass you can't walk through")
	var env: Environment = office.get("env")
	check(env.background_mode == Environment.BG_SKY and env.sky.sky_material is PanoramaSkyMaterial, "the vista is the sky")
	var placed: Array = office.get("placed")
	check(placed.size() >= 10, "a lounge's worth of furniture: %d pieces" % placed.size())
	check(placed.any(func(p: Dictionary) -> bool: return str(p.id).contains("sofa")), "including a sofa")
	check(office.get_node_or_null("HaloRing") != null, "a ring of light over the holotable")

	# A picture shared offline (a session of one) becomes everyone's sky.
	var src := Image.create_empty(400, 300, false, Image.FORMAT_RGB8)
	src.fill(Color(0.8, 0.2, 0.1))
	var bytes := VistaImage.encode(VistaImage.to_panorama(src, 1024))
	vista.call("share_bytes", bytes)
	await frames(2)
	check(not bool(vista.call("is_default")), "a shared picture replaces the default")
	var sky := env.sky.sky_material as PanoramaSkyMaterial
	check(sky.panorama == vista.call("texture"), "and the sky shows it")
	var shown := (sky.panorama as Texture2D).get_image()
	check(shown.get_pixel(shown.get_width() / 2, shown.get_height() / 2).r > 0.6, "straight out of the window")
	check(FileAccess.file_exists("user://design/vista.webp"), "the host keeps it for next time")
	var snap: Dictionary = vista.call("get_net_snapshot")
	check((snap.data as PackedByteArray).size() == bytes.size(), "and sends it to players who join")

	# The console's panel.
	office.call("open_panel")
	await frames(1)
	check(office.get("panel") != null and HudSlots.pointer_claimed(), "F at the console opens the view panel")
	(office.get("panel") as Control).find_child("Default", true, false).emit_signal("pressed")
	await frames(2)
	check(bool(vista.call("is_default")), "Default view puts the mountains back")
	check(not FileAccess.file_exists("user://design/vista.webp"), "for next time too")
	office.call("close_panel")
	await frames(1)
	check(office.get("panel") == null and not HudSlots.pointer_claimed(), "and it closes")
	hall.queue_free()
	await frames(2)


func _pictures() -> void:
	var pano := Image.create_empty(800, 400, false, Image.FORMAT_RGB8)
	check(VistaImage.is_panorama(pano), "a 2:1 picture is a panorama")
	var out := VistaImage.to_panorama(pano, 1024)
	check(out.get_width() == 1024 and out.get_height() == 512, "kept whole at the vista's size")
	var photo := Image.create_empty(640, 480, false, Image.FORMAT_RGB8)
	photo.fill(Color(0.1, 0.6, 0.2))
	photo.fill_rect(Rect2i(0, 0, 640, 40), Color(0.3, 0.5, 0.9))
	out = VistaImage.to_panorama(photo, 1024)
	check(out.get_width() == 1024 and out.get_height() == 512, "a photo becomes a 2:1 panorama")
	check(out.get_pixel(512, 256).g > 0.5, "with the photo straight ahead")
	check(out.get_pixel(5, 256).g > 0.5, "mirrored round the back")
	check(out.get_pixel(512, 2).b > 0.4, "its sky carried up overhead")
	var bytes := VistaImage.encode(out)
	check(not bytes.is_empty() and bytes.size() <= VistaImage.MAX_BYTES, "small enough to share: %d bytes" % bytes.size())
	check(VistaImage.texture_from(bytes) != null, "and readable at the other end")
	check(VistaImage.texture_from(PackedByteArray([1, 2, 3])) == null, "junk isn't a picture")
	check(not VistaImage.is_picture("notes.txt") and VistaImage.is_picture("view.JPG"), "only picture files are taken")
