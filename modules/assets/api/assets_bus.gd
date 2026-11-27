class_name AssetsBus
extends Node
## The asset library's bus (Modules.bus("assets")). The library itself is the static
## AssetLibrary class; the bus only registers the gallery scene, where every asset can be
## looked over in either look (Graphics > Display > Look).

const GALLERY_SCENE := "assets.gallery"
const GALLERY_FLAG := "assets.gallery"


func register_module() -> void:
	Router.register_scene(GALLERY_SCENE, "res://modules/assets/internal/gallery/asset_gallery.tscn")
	Shots.register("assets_gallery", GALLERY_SCENE)
	if Flags.is_on(GALLERY_FLAG):
		Menu.register_entry(GALLERY_FLAG, "Asset gallery", GALLERY_SCENE, 90)


func unregister_module() -> void:
	Menu.unregister_entry(GALLERY_FLAG)
