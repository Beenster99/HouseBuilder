class_name Warmup
extends RefCounted
## What the splash screen loads and draws once before the main menu, so play never stalls on
## a scene load or a shader compile. Every scene registered with the Router is preloaded and
## kept, and every material here is drawn in a hidden view (both looks' ArtStyle materials
## are always included). Modules add their own from register_module():
##
##   Warmup.add_materials([my_glow, my_dust])   # code-made materials, drawn once
##   Warmup.add_mesh(preload("res://.../crane.tres"))   # drawn once with its own materials
##   Warmup.add_scene("res://modules/x/internal/big.tscn")   # loaded and kept, not opened
##   Warmup.add_step("Baking the site", func() -> void: ..., 0.2)   # own work, weight 0..1
##
## The splash is core/internal/boot.gd.

## The splash's picture (a SketchUp-look office coming down).
const SPLASH_IMAGE := "res://modules/core/api/splash.jpg"

static var materials: Array[Material] = []
static var meshes: Array[Mesh] = []
static var scenes: PackedStringArray = []
## [{label, run: Callable, weight}], run in order after loading, before the shaders.
static var steps: Array[Dictionary] = []
## Everything the splash loaded, held so later loads come from the cache.
static var loaded: Array[Resource] = []


static func add_materials(list: Array) -> void:
	for m: Variant in list:
		if m is Material and not materials.has(m):
			materials.append(m)


static func add_mesh(mesh: Mesh) -> void:
	if mesh and not meshes.has(mesh):
		meshes.append(mesh)


static func add_scene(path: String) -> void:
	if not scenes.has(path):
		scenes.append(path)


static func add_step(label: String, run: Callable, weight: float = 0.1) -> void:
	steps.append({"label": label, "run": run, "weight": clampf(weight, 0.01, 1.0)})


## Scenes to preload: every Router scene, then the extra ones.
static func scene_list() -> PackedStringArray:
	var out := PackedStringArray()
	var paths: Dictionary = Router.scene_paths()
	for id: String in paths:
		if not out.has(str(paths[id])):
			out.append(str(paths[id]))
	for p in scenes:
		if not out.has(p):
			out.append(p)
	return out


## Materials to draw once: both looks' ArtStyle materials and every one added.
static func material_list() -> Array[Material]:
	var out := ArtStyle.warm_materials()
	for m in materials:
		if not out.has(m):
			out.append(m)
	return out
