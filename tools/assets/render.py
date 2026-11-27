#!/usr/bin/env python3
"""Renders a contact sheet of assets in both looks, for review.

  python3 tools/assets/render.py out.png [id prefix ...]

Writes <out>_realistic.png (PBR materials) and <out>_sketch.png (plain white, hidden line,
shadow). The sketch render uses Blender's Freestyle lines as a stand-in for the game's
edge pass.
"""
import importlib
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # first: it provides mathutils
from mathutils import Vector

import build
import kit
import registry


def main(argv: list) -> None:
	out = os.path.abspath(argv[0])
	filters = argv[1:]
	for name in build.RECIPES:
		importlib.import_module("recipes." + name)
	ids = [i for i in sorted(registry.ASSETS) if not filters or any(i.startswith(f) for f in filters)]
	bpy.ops.wm.read_factory_settings(use_empty=True)
	scene = bpy.context.scene
	x = 0.0
	row_depth, y = 0.0, 0.0
	width_limit = max(8.0, math.sqrt(len(ids)) * 3.0)
	for id in ids:
		before = set(scene.objects)
		a = registry.ASSETS[id]
		a["fn"](**a["params"])
		new = [o for o in scene.objects if o not in before and o.type == "MESH"]
		lo, hi = Vector((1e9, 1e9, 1e9)), Vector((-1e9, -1e9, -1e9))
		for o in new:
			for v in o.data.vertices:
				for k in range(3):
					lo[k] = min(lo[k], v.co[k])
					hi[k] = max(hi[k], v.co[k])
		if x + (hi.x - lo.x) > width_limit:
			x, y, row_depth = 0.0, y - row_depth - 1.0, 0.0
		for o in new:
			o.location = Vector((x - lo.x, y - hi.y, -min(lo.z, 0.0) if a["stretch"] != "y" else -lo.z))
		x += (hi.x - lo.x) + 0.6
		row_depth = max(row_depth, hi.y - lo.y)
	lo, hi = Vector((1e9, 1e9, 1e9)), Vector((-1e9, -1e9, -1e9))
	for o in scene.objects:
		if o.type == "MESH":
			for v in o.data.vertices:
				w = v.co + o.location
				for k in range(3):
					lo[k] = min(lo[k], w[k])
					hi[k] = max(hi[k], w[k])
	centre = (lo + hi) / 2
	span = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)
	bpy.ops.mesh.primitive_plane_add(size=span * 20, location=(centre.x, centre.y, 0))
	ground = bpy.context.object
	gm = bpy.data.materials.new("ground")
	gm.diffuse_color = (0.55, 0.55, 0.55, 1)
	gm.use_nodes = True
	gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.55, 0.55, 0.55, 1)
	ground.data.materials.append(gm)
	sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
	sun.data.energy = 4.0
	sun.data.angle = math.radians(1.5)
	sun.rotation_euler = (math.radians(50), 0, math.radians(35))
	scene.collection.objects.link(sun)
	world = bpy.data.worlds.new("world")
	world.use_nodes = True
	world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.45, 0.68, 0.95, 1)
	world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
	scene.world = world
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
	scene.collection.objects.link(cam)
	scene.camera = cam
	cam.data.lens = 50
	direction = Vector((0.55, 1.0, 0.5)).normalized()
	cam.location = centre + direction * span * 1.55
	cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
	cam.data.clip_end = span * 10
	scene.render.engine = "CYCLES"
	scene.cycles.samples = 48
	scene.cycles.use_denoising = True
	scene.render.resolution_x, scene.render.resolution_y = 1920, 1080
	scene.view_settings.view_transform = "Standard"
	scene.render.filepath = out + "_realistic.png"
	bpy.ops.render.render(write_still=True)
	white = bpy.data.materials.new("sketch_white")
	white.use_nodes = True
	white.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (1, 1, 1, 1)
	white.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
	for o in scene.objects:
		if o.type == "MESH" and o is not ground:
			o.data.materials.clear()
			o.data.materials.append(white)
	scene.render.use_freestyle = True
	scene.render.line_thickness = 1.1
	ls = bpy.context.view_layer.freestyle_settings.linesets.new("edges")
	ls.select_silhouette = ls.select_border = ls.select_crease = True
	bpy.context.view_layer.freestyle_settings.crease_angle = math.radians(140)
	scene.render.filepath = out + "_sketch.png"
	bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
	main(sys.argv[1:])
