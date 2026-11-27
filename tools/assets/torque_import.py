"""Brings models from the owner's Torque Shed UE project into the asset library.

    python3 tools/assets/torque_import.py /path/to/torque-shed-ue [name filter ...]

Torque Shed's props are either .glb files (vertex colours carry the colour and, in alpha,
the surface; or plain named materials) or Blender scripts that assemble "units" of parts,
each with a surface and a colour. This reads both and writes one neutral .glb per asset to
tools/assets/vendor/torque_shed/ with one material per library slot, plus index.json (ids,
labels, the slots' PBR values and each piece's mass). recipes/torque.py then builds them like
any other asset, so the library builds without a Torque Shed checkout. Run again only to
refresh from Torque Shed. The table of what comes in is torque_catalog.py.
"""
import json
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "vendor", "torque_shed")
sys.path.insert(0, HERE)
import torque_catalog as C  # noqa: E402

# surface -> (roughness, metallic, kg per m2 of skin)
SURFACES = {
	"paint": (0.5, 0.1, 20), "timber": (0.8, 0.0, 25), "galv": (0.4, 0.9, 30), "concrete": (0.9, 0.0, 240),
	"glaze": (0.12, 0.0, 40), "lens": (0.08, 0.0, 10), "enamel": (0.3, 0.2, 20), "steel": (0.55, 0.85, 40),
	"brick": (0.9, 0.0, 380), "stone": (0.9, 0.0, 500), "render": (0.9, 0.0, 300), "slate": (0.7, 0.0, 45),
	"tile": (0.8, 0.0, 50), "clad": (0.45, 0.4, 12), "glass": (0.06, 0.0, 25), "rubber": (0.9, 0.0, 30),
	"chrome": (0.15, 1.0, 30), "light": (0.3, 0.0, 10), "foliage": (0.9, 0.0, 2), "fabric": (0.9, 0.0, 3),
}
STREET = ["paint", "timber", "galv", "concrete", "glaze", "lens", "enamel", "steel"]
ALIASES = {"cladding": "clad", "metal": "steel", "block": "concrete", "wood": "timber", "roof": "clad", "sign": "paint",
	"masonry": "stone", "plastic": "paint", "window": "glass", "rooflight": "lens", "tarmac": "concrete",
	"boarding": "timber", "weatherboard": "timber", "frame": "paint", "lamp": "light", "louvre": "paint", "pale": "galv",
	"panel_door": "paint", "plain": "paint", "shutter": "galv", "solar": "enamel", "straw": "fabric", "tin": "clad", "trailer": "paint", "flint": "stone", "thatch": "fabric"}
materials: dict = {}


def srgb(c: float) -> float:
	c = min(1.0, max(0.0, c))
	return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def slot_for(surface: str, rgb, alpha: float = 1.0) -> str:
	"""The library slot for a Torque Shed surface and linear colour (made on first use)."""
	surface = surface.lower()
	base = surface if surface in SURFACES else ALIASES.get(surface, "")
	if not base:
		for key in list(SURFACES) + list(ALIASES):
			if key in surface:
				base = key if key in SURFACES else ALIASES[key]
				break
	if not base:
		UNKNOWN.add(surface)
		base = "paint"
	if base == "glass" or (base == "lens" and max(rgb) < 0.2):
		name = "glass_dark"
		rgb, alpha, base = (0.03, 0.045, 0.06), 1.0, "glass"
	elif base == "rubber":
		name, rgb = "rubber", (0.04, 0.04, 0.04)
	else:
		q = [min(15, int(srgb(c) * 15 + 0.5)) for c in rgb]
		name = "%s_%x%x%x" % (base, q[0], q[1], q[2])
	if name not in materials:
		rough, metal, areal = SURFACES[base]
		materials[name] = {"rgb": [round(c, 4) for c in rgb], "rough": rough, "metal": metal, "alpha": alpha, "areal": areal}
	return name


UNKNOWN: set = set()
FLIPPED = [0]


def clear() -> None:
	bpy.ops.wm.read_factory_settings(use_empty=True)


def drop_back_faces(bm) -> int:
	"""The Dales buildings' shells carry every face twice, front and back (drawn two sided in
	Torque Shed). Keeps the one that faces out from the building. Returns how many it dropped."""
	n = max(1, len(bm.verts))
	cx, cy = sum(v.co.x for v in bm.verts) / n, sum(v.co.y for v in bm.verts) / n
	pairs: dict = {}
	for f in bm.faces:
		key = tuple(sorted((round(v.co.x, 3), round(v.co.y, 3), round(v.co.z, 3)) for v in f.verts))
		pairs.setdefault(key, []).append(f)
	drop = []
	for faces in pairs.values():
		if len(faces) < 2:
			continue
		c = faces[0].calc_center_median()
		out = (c.x - cx, c.y - cy)
		score = lambda f: f.normal.x * out[0] + f.normal.y * out[1] + f.normal.z * 0.5
		faces.sort(key=score, reverse=True)
		drop += faces[1:]
	if drop:
		bmesh.ops.delete(bm, geom=drop, context="FACES")
	return len(drop)


def gather_glb(path: str, suffix_surface: str = "") -> list:
	"""[(bmesh in world space, per face slot names)] for one Torque Shed .glb."""
	before = set(bpy.data.objects)
	bpy.ops.import_scene.gltf(filepath=path)
	out = []
	for ob in [o for o in bpy.data.objects if o not in before and o.type == "MESH"]:
		me = ob.data
		bm = bmesh.new()
		bm.from_mesh(me)
		bm.transform(ob.matrix_world)
		if "SM_Bld_" in path:
			FLIPPED[0] += drop_back_faces(bm)
		# (read through the mesh's attribute: its .color is linear whatever the storage)
		attr = me.color_attributes[0] if me.color_attributes else None
		colours = [tuple(d.color) for d in attr.data] if attr else []
		corner = bool(attr) and attr.domain == "CORNER"
		mats = []
		for m in me.materials:
			rgb, rough, metal, alpha, emit = (0.5, 0.5, 0.5), 0.5, 0.0, 1.0, 0.0
			bsdf = m.node_tree.nodes.get("Principled BSDF") if m and m.node_tree else None
			if bsdf:
				rgb = tuple(bsdf.inputs["Base Color"].default_value[:3])
				rough = bsdf.inputs["Roughness"].default_value
				metal = bsdf.inputs["Metallic"].default_value
				alpha = bsdf.inputs["Alpha"].default_value
				emit = bsdf.inputs["Emission Strength"].default_value if max(bsdf.inputs["Emission Color"].default_value[:3]) > 0.01 else 0.0
				if emit > 0.0:
					rgb = tuple(bsdf.inputs["Emission Color"].default_value[:3])
			mats.append((m.name if m else "", rgb, rough, metal, alpha, emit))
		slots = []
		fixed = ""
		if suffix_surface.startswith("fix:"):
			_f, surface, rgb = suffix_surface.split(":")
			fixed = slot_for(surface, tuple(float(x) for x in rgb.split(",")))
		for f in bm.faces:
			c = colours[f.loops[0].index if corner else f.verts[0].index] if attr else (0.5, 0.5, 0.5, 1.0)
			rgb = (c[0], c[1], c[2])
			if suffix_surface == "dales_stone":  # (one file holds the stone slates and the dressed stone)
				slots.append(slot_for("slate", (0.15, 0.145, 0.14)) if f.normal.z > 0.35 else slot_for("stone", (0.40, 0.35, 0.27)))
			elif fixed:
				slots.append(fixed)
			elif suffix_surface != "named" and attr:
				surface = suffix_surface[3:] if suffix_surface.startswith("vc:") else STREET[min(7, int(c[3] * 255 / 32))]
				if surface in ("paint", "enamel") and max(rgb) < 0.035:
					slots.append(slot_for("rubber", (0.02, 0.02, 0.02)))
				else:
					slots.append(slot_for(surface, rgb))
			else:
				name, rgb, rough, metal, alpha, emit = mats[f.material_index] if mats else ("", (0.5, 0.5, 0.5), 0.5, 0, 1, 0)
				low = name.lower()
				if emit > 0.0 or "lamp" in low or "lens" in low or "neon" in low or "lit" in low.split("_"):
					surface = "light"
				elif alpha < 0.95 or "glass" in low or "window" in low:
					surface = "glass"
				elif "rubber" in low or "tyre" in low:
					surface = "rubber"
				elif "chrome" in low:
					surface = "chrome"
				elif metal > 0.5:
					surface = "galv" if rough < 0.5 else "steel"
				elif "wood" in low or "timber" in low or "plank" in low:
					surface = "timber"
				elif "concrete" in low:
					surface = "concrete"
				elif "brick" in low:
					surface = "brick"
				else:
					surface = "paint"
				slots.append(slot_for(surface, rgb))
		out.append((bm, slots))
	return out


def gather_unit(U) -> list:
	"""The same for a unit assembled by a Torque Shed kit script."""
	dg = bpy.context.evaluated_depsgraph_get()
	out = []
	for p in U.parts:
		ev = p.obj.evaluated_get(dg)
		me = ev.to_mesh()
		bm = bmesh.new()
		bm.from_mesh(me)
		bm.transform(p.obj.matrix_world)
		ev.to_mesh_clear()
		out.append((bm, [slot_for(p.surface, p.rgb)] * len(bm.faces)))
	return out


def write(entry: dict, parts: list) -> dict:
	"""Joins the parts, turns and centres them as the entry asks, and writes its .glb."""
	names: list = []
	joined = bmesh.new()
	layer = joined.faces.layers.int.new("slot")
	for bm, slots in parts:
		me = bpy.data.meshes.new("tmp")
		bm.faces.ensure_lookup_table()
		tag = bm.faces.layers.int.new("slot")
		for f, s in zip(bm.faces, slots):
			if s not in names:
				names.append(s)
			f[tag] = names.index(s)
		bm.to_mesh(me)
		bm.free()
		joined.from_mesh(me)
		bpy.data.meshes.remove(me)
	layer = joined.faces.layers.int["slot"]
	joined.transform(Matrix.Rotation(math.radians(entry.get("rot", 0)), 4, "Z"))
	xs = [v.co.x for v in joined.verts]
	ys = [v.co.y for v in joined.verts]
	if entry.get("long_y") and max(xs) - min(xs) > max(ys) - min(ys):
		joined.transform(Matrix.Rotation(math.radians(90), 4, "Z"))
	if entry.get("size_label"):
		entry["label"] += ", %d x %d m" % (round(max(xs) - min(xs)), round(max(ys) - min(ys)))
	if entry.get("centre"):
		xs = [v.co.x for v in joined.verts]
		ys = [v.co.y for v in joined.verts]
		joined.transform(Matrix.Translation((-(min(xs) + max(xs)) / 2, -(min(ys) + max(ys)) / 2, 0)))
	if entry.get("ground"):
		joined.transform(Matrix.Translation((0, 0, -min(v.co.z for v in joined.verts))))
	area: dict = {}
	for f in joined.faces:
		f.material_index = f[layer]
		area[names[f[layer]]] = area.get(names[f[layer]], 0.0) + f.calc_area()
	clear_scene()
	me = bpy.data.meshes.new(entry["id"])
	joined.to_mesh(me)
	tris = sum(len(f.verts) - 2 for f in joined.faces)
	joined.free()
	for n in names:
		mat = bpy.data.materials.new(n)
		mat.use_nodes = True
		me.materials.append(mat)
	ob = bpy.data.objects.new(entry["id"], me)
	bpy.context.scene.collection.objects.link(ob)
	bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, entry["id"] + ".glb"), export_format="GLB", export_yup=True,
		export_apply=False, export_materials="EXPORT", export_normals=True, export_texcoords=False, export_vertex_color="NONE")
	masses = {n: round(max(0.01, area[n] * materials[n]["areal"]), 2) for n in names}
	return {"label": entry["label"], "tags": entry.get("tags", []), "family": entry.get("family", "fixture"),
		"stage": entry.get("stage", {}), "mass": masses, "tris": tris, "source": entry["source"]}


def clear_scene() -> None:
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob, do_unlink=True)
	for block in (bpy.data.meshes, bpy.data.materials):
		for b in list(block):
			block.remove(b)


def main(argv: list) -> int:
	root = argv[0]
	filters = argv[1:]
	os.makedirs(OUT, exist_ok=True)
	index_path = os.path.join(OUT, "index.json")
	index = {"assets": {}, "materials": {}}
	if filters and os.path.exists(index_path):
		index = json.load(open(index_path))
		for name, m in index["materials"].items():
			materials[name] = m
	wanted = lambda id: not filters or any(id.startswith(f) for f in filters)
	clear()
	n = 0
	for entry in C.glb_entries(root):
		if not wanted(entry["id"]):
			continue
		parts = []
		for path, surface in entry["files"]:
			got = gather_glb(os.path.join(root, path), surface)
			if entry.get("rotor") and "rotor" in path:
				for bm, _s in got:  # (the hub: 3.6 m out along +x at 45 m)
					bm.transform(Matrix.Translation((3.6, 0.0, 45.0)))
			parts += got
		entry["source"] = [p for p, _s in entry["files"]]
		index["assets"][entry["id"]] = write(entry, parts)
		n += 1
	sys.path.insert(0, os.path.join(root, "Tools"))
	for made in C.unit_entries(root, wanted):
		gathered = [(entry, gather_unit(U)) for entry, U in made]
		for entry, parts in gathered:
			index["assets"][entry["id"]] = write(entry, parts)
			n += 1
	index["materials"] = dict(sorted(materials.items()))
	index["assets"] = dict(sorted(index["assets"].items()))
	json.dump(index, open(index_path, "w"), indent="\t", sort_keys=True)
	print("torque_import: wrote %d assets, %d slots; doubled faces dropped: %d; unknown surfaces: %s" % (n, len(materials), FLIPPED[0], sorted(UNKNOWN)))
	return 0


if __name__ == "__main__":
	sys.exit(main(sys.argv[1:]))
