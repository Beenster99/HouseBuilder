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
import math
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
RECIPES = ["structure", "openings", "circulation", "fixtures", "plant", "services", "envelope", "furniture", "public", "airport", "vehicles", "site", "outdoors", "openings_more", "leisure", "infra", "depth", "statement", "torque", "siteplant", "siteyard", "venues", "landmarks"]
TRI_BUDGET = 60000


def game(v) -> list:
	return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


def settle(bms: dict) -> int:
	"""Faces of different materials that lie in one plane, face the same way and overlap
	flicker in game (z-fighting). The smaller face of each such pair is stood off, with the
	flat patch it belongs to, by the smallest step that leaves it clear.
	bms: {(stage, slot): bmesh}. Returns how many patches moved."""
	GAP, STEPS = 0.0035, (0.004, 0.007, 0.011, 0.016, 0.023)
	table = {}
	def entry(f):
		n = f.normal
		cs = [v.co for v in f.verts]
		lo, hi = [min(c[k] for c in cs) for k in range(3)], [max(c[k] for c in cs) for k in range(3)]
		return (n.copy(), n.dot(cs[0]), lo, hi, [c.copy() for c in cs], max(hi[k] - lo[k] for k in range(3)) > 3.0)
	def home(n, d):
		return (round(n.x * 4), round(n.y * 4), round(n.z * 4), int(math.floor(d / 0.01)))
	def keys(n, d):
		base = home(n, d)
		for dx in (-1, 0, 1):
			for dy in (-1, 0, 1):
				for dz in (-1, 0, 1):
					for dq in (-1, 0, 1):
						yield (base[0] + dx, base[1] + dy, base[2] + dz, base[3] + dq)
	faces = []
	item_of = {}
	large = {}  # (big faces a touch out of parallel share no distance bucket: looked up by direction)
	def file(item):
		e = item[3]
		table.setdefault(home(e[0], e[1]), []).append(item)
		if e[5]:
			large.setdefault(home(e[0], 0.0)[:3], []).append(item)
	def unfile(item):
		e = item[3]
		for group in (table.get(home(e[0], e[1])), large.get(home(e[0], 0.0)[:3])):
			if group and item in group:
				group.remove(item)
	def near(n, d):
		for key in keys(n, d):
			yield from table.get(key, ())
			if key[3] == home(n, d)[3]:
				yield from large.get(key[:3], ())
	for (stage, slot), bm in bms.items():
		bm.normal_update()
		for f in bm.faces:
			area = f.calc_area()
			if area < 1e-6:
				continue
			e = entry(f)
			item = [slot, f, area, e]
			faces.append(item)
			item_of[f] = item
			file(item)
	def clash(item, strict):
		n, d, lo, hi, cs, _big = item[3]
		for other in near(n, d):
			if other is item or other[0] == item[0]:
				continue
			n2, d2, lo2, hi2, cs2, _big2 = other[3]
			if n.dot(n2) < 0.9995:
				continue
			if not all(lo[k] < hi2[k] - 0.0005 and lo2[k] < hi[k] - 0.0005 for k in range(3) if abs(n[k]) < 0.9):
				continue
			if min(abs(n.dot(c) - d) for c in cs2) > GAP and min(abs(n2.dot(c) - d2) for c in cs) > GAP:
				continue
			# (at rest only the smaller of a pair is the one to move)
			if strict or other[2] > item[2] or (other[2] == item[2] and other[0] < item[0]):
				return True
		return False
	def refresh(item):
		unfile(item)
		item[1].normal_update()
		item[3] = entry(item[1])
		file(item)
	moved = 0
	for _pass in range(4):
		before = moved
		for item in sorted(faces, key=lambda i: i[2]):
			if not clash(item, False):
				continue
			f = item[1]
			normal = f.normal.copy()
			patch, edge = {f}, [f]
			while edge:
				g = edge.pop()
				for e2 in g.edges:
					for h in e2.link_faces:
						if h not in patch and h.normal.dot(normal) > 0.9995:
							patch.add(h)
							edge.append(h)
			verts = {v for g in patch for v in g.verts}
			touched = [item_of[h] for h in {h for v in verts for h in v.link_faces} if h in item_of]
			mine = [item_of[h] for h in patch if h in item_of]
			# (side faces stretch with the patch: they must not run into anything new either)
			sides = [i for i in touched if i[1] not in patch and not clash(i, True)]
			for shift in STEPS:
				for v in verts:
					v.co += normal * shift
				for i in touched:
					refresh(i)
				if not any(clash(i, True) for i in mine) and not any(clash(i, True) for i in sides):
					moved += 1
					break
				for v in verts:
					v.co -= normal * shift
				for i in touched:
					refresh(i)
		if moved == before:
			break
	if os.environ.get("SETTLE_DEBUG"):
		left = [i for i in faces if clash(i, False)]
		print("settle: moved %d, still clashing %d" % (moved, len(left)))
		for i in left[:6]:
			print("   ", i[0], round(i[2], 4), [round(x, 3) for x in i[3][0]], round(i[3][1], 4), [round(x, 2) for x in i[3][2]], [round(x, 2) for x in i[3][3]])
	return moved


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
	merged_bms = {}
	for (stage, slot), obs in groups.items():
		bm = bmesh.new()
		for ob in obs:
			bm.from_mesh(ob.data)
		merged_bms[(stage, slot)] = bm
	settle(merged_bms)
	for (stage, slot), obs in groups.items():
		bm = merged_bms[(stage, slot)]
		mass = sum(ob["mass"] for ob in obs)
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
