#!/usr/bin/env python3
"""Builds the asset library: runs every recipe in Blender (headless, the `bpy` Python
package), exports one .glb per asset and writes the manifest the game reads.

  pip install bpy
  python3 tools/assets/build.py                 # everything
  python3 tools/assets/build.py opening fixture.sofa   # ids starting with these
  python3 tools/assets/build.py --blend plant.crane.tower   # also save a .blend to open

Output: modules/assets/internal/models/<category>/<id>.glb and
modules/assets/internal/manifest.json. Each .glb holds one mesh per build stage and
material slot, named "<stage>__<slot>". Game axes in the
manifest: x right, y up, -z forward (Blender's +Y).
"""
import importlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # first: it provides bmesh and mathutils
import bmesh
from mathutils import Vector

import kit
import materials
import registry

OUT = os.path.join(registry.ROOT, "modules", "assets", "internal")
RECIPES = ["structure", "openings", "circulation", "fixtures", "plant", "services", "envelope", "furniture", "public", "airport", "vehicles", "site", "outdoors", "openings_more", "leisure", "infra", "depth", "statement", "torque"]
TRI_BUDGET = 60000


def game(v) -> list:
	return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


def build_scene(a: dict) -> dict:
	"""Runs one recipe in an empty scene, merges its parts per stage and slot, and returns
	the manifest entry (without the file)."""
	bpy.ops.wm.read_factory_settings(use_empty=True)
	kit._count[0] = 0
	a["fn"](**a["params"])
	groups: dict = {}
	stages: list = []
	for ob in list(bpy.context.scene.objects):
		if ob.type != "MESH":
			continue
		key = (ob["stage"], ob["slot"])
		groups.setdefault(key, []).append(ob)
		if ob["stage"] not in stages:
			stages.append(ob["stage"])
	lo, hi = Vector((1e9, 1e9, 1e9)), Vector((-1e9, -1e9, -1e9))
	pieces, tris = [], 0
	for (stage, slot), obs in groups.items():
		bm = bmesh.new()
		mass = 0.0
		for ob in obs:
			bm.from_mesh(ob.data)
			mass += ob["mass"]
		for v in bm.verts:
			for i in range(3):
				lo[i] = min(lo[i], v.co[i])
				hi[i] = max(hi[i], v.co[i])
		tris += sum(len(f.verts) - 2 for f in bm.faces)
		name = "%s__%s" % (stage, slot)
		me = bpy.data.meshes.new(name)
		bm.to_mesh(me)
		bm.free()
		me.materials.append(obs[0].data.materials[0])
		merged = bpy.data.objects.new(name, me)
		bpy.context.scene.collection.objects.link(merged)
		for ob in obs:
			bpy.data.objects.remove(ob, do_unlink=True)
		pieces.append({"node": name, "stage": stage, "slot": slot, "mass": max(0.001, round(mass, 3))})
	sockets = {ob.name[7:]: game(ob.location) for ob in bpy.context.scene.objects if ob.name.startswith("socket.")}
	g_lo, g_hi = game(lo), game(hi)
	return {
		"label": a["label"], "category": a["category"], "family": a["family"], "kind": a["kind"],
		"tags": a["tags"], "stretch": a["stretch"],
		"aabb": [[g_lo[0], g_lo[1], g_hi[2]], [g_hi[0], g_hi[1], g_lo[2]]],
		"stages": stages, "pieces": pieces, "sockets": sockets, "tris": tris,
		"mass": round(sum(p["mass"] for p in pieces), 1),
	}


def write_materials() -> None:
	"""The slots' PBR values and surface pattern, for the game's textured realistic look."""
	import textures
	table = {}
	for name, (rgb, rough, metal, alpha, _density) in sorted(materials.MATERIALS.items()):
		pattern = textures.pattern_for(name) if alpha >= 1.0 else ""
		table[name] = {"rgb": [round(c, 4) for c in rgb], "rough": rough, "metal": metal, "alpha": alpha,
			"pattern": pattern, "size": textures.SIZE.get(pattern, 1.0), "glow": name in ("glow", "light_emitter") or name.startswith("light_")}
	with open(os.path.join(OUT, "materials.json"), "w") as f:
		json.dump(table, f, indent="\t", sort_keys=True)


def main(argv: list) -> int:
	save_blend = "--blend" in argv
	filters = [x for x in argv if not x.startswith("--")]
	for name in RECIPES:
		importlib.import_module("recipes." + name)
	path = os.path.join(OUT, "manifest.json")
	manifest = json.load(open(path)) if filters and os.path.exists(path) else {}
	problems = []
	for id in sorted(registry.ASSETS):
		if filters and not any(id.startswith(f) for f in filters):
			continue
		a = registry.ASSETS[id]
		entry = build_scene(a)
		folder = os.path.join(OUT, "models", a["category"])
		os.makedirs(folder, exist_ok=True)
		entry["file"] = "models/%s/%s.glb" % (a["category"], id)
		bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, entry["file"]), export_format="GLB", export_yup=True,
			export_extras=False, export_apply=False, export_animations=False)
		if save_blend:
			bpy.ops.wm.save_as_mainfile(filepath=os.path.join(registry.ROOT, "tools", "assets", "out", id + ".blend"))
		manifest[id] = entry
		if entry["tris"] > TRI_BUDGET:
			problems.append("%s: %d triangles is over the %d budget" % (id, entry["tris"], TRI_BUDGET))
		if not entry["pieces"]:
			problems.append("%s: recipe made no geometry" % id)
		size = [round(entry["aabb"][1][i] - entry["aabb"][0][i], 3) for i in range(3)]
		print("%-44s %6d tris  %s m  %s kg" % (id, entry["tris"], size, entry["mass"]))
	with open(path, "w", encoding="utf-8") as f:
		json.dump(manifest, f, indent="\t", sort_keys=True)
		f.write("\n")
	write_materials()
	print("%d assets in the manifest" % len(manifest))
	for p in problems:
		print("PROBLEM: " + p)
	return 1 if problems else 0


if __name__ == "__main__":
	sys.exit(main(sys.argv[1:]))
