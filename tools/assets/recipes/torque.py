"""Models brought in from the owner's Torque Shed UE project (tools/assets/torque_import.py
writes them to tools/assets/vendor/torque_shed), plus what is put together from them here:
powerline spans and runs, and wind farm rows. Slots made for their colours are named
<surface>_<colour>, with their PBR values in the vendor index."""
import json
import math
import os

import bpy
import bmesh
from mathutils import Matrix

import kit
import materials
from registry import register

VENDOR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "vendor", "torque_shed")
INDEX = json.load(open(os.path.join(VENDOR, "index.json")))
for _name, _m in INDEX["materials"].items():
	if _name not in materials.MATERIALS:
		materials.MATERIALS[_name] = (tuple(_m["rgb"]), _m["rough"], _m["metal"], _m["alpha"], 1000.0)


def place(src, at=(0, 0, 0), turn=0.0, stage=None) -> dict:
	"""Adds the vendor model `src` as kit parts, one per slot. Returns {slot: object}."""
	before = set(bpy.data.objects)
	bpy.ops.import_scene.gltf(filepath=os.path.join(VENDOR, src + ".glb"))
	masses = INDEX["assets"][src]["mass"]
	m = Matrix.Translation(at) @ Matrix.Rotation(math.radians(turn), 4, "Z")
	out = {}
	for ob in [o for o in bpy.data.objects if o not in before]:
		if ob.type == "MESH":
			names = [mat.name.split(".")[0] for mat in ob.data.materials]
			for mat in list(ob.data.materials):  # (the file's own stand-ins must not shadow the library's)
				bpy.data.materials.remove(mat)
			src_bm = bmesh.new()
			src_bm.from_mesh(ob.data)
			src_bm.transform(m @ ob.matrix_world)
			for i, slot in enumerate(names):
				bm = src_bm.copy()
				bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index != i], context="FACES")
				if not bm.faces:
					bm.free()
					continue
				kit._count[0] += 1
				full = "%s.%s.%03d" % (stage or kit._stage[-1], src.split(".")[-1], kit._count[0])
				me = bpy.data.meshes.new(full)
				bm.to_mesh(me)
				bm.free()
				me.materials.append(materials.get(slot))
				part = bpy.data.objects.new(full, me)
				bpy.context.scene.collection.objects.link(part)
				part["slot"], part["stage"], part["mass"] = slot, stage or kit._stage[-1], masses.get(slot, 1.0)
				out[slot] = part
			src_bm.free()
		data = ob.data if ob.type == "MESH" else None
		bpy.data.objects.remove(ob, do_unlink=True)
		if data:
			bpy.data.meshes.remove(data)
	return out


def model(src=""):
	place(src)


def wire_points(parts: dict, top: bool) -> list:
	"""Where the conductors meet the insulators: the foot of each hanging string on a pylon,
	the head of each pin insulator on a pole."""
	cells: dict = {}
	for slot, ob in parts.items():
		if slot.startswith("glaze"):
			for v in ob.data.vertices:
				cells.setdefault((round(v.co.x / 0.5), round(v.co.y / 0.8)), []).append(v.co.copy())
	points = []
	for vs in cells.values():
		vs.sort(key=lambda c: c.z)
		run = [vs[0]]
		for c in vs[1:] + [None]:
			if c is None or c.z - run[-1].z > 0.8:
				x = sum(p.x for p in run) / len(run)
				points.append((round(x, 2), run[-1].z if top else run[0].z))
				run = []
			if c is not None:
				run.append(c)
	merged = []
	for x, z in sorted(set(points)):
		if not any(abs(x - mx) < 0.4 and abs(z - mz) < 0.6 for mx, mz in merged):
			merged.append((x, z))
	return merged


def wires(points, y0, y1, sag, r, steps=16):
	for x, z in points:
		path = [(x, y0 + (y1 - y0) * i / steps, z - sag * (1 - (2.0 * i / steps - 1) ** 2)) for i in range(steps + 1)]
		kit.sweep(path, kit.circle(r, 5), "aluminium", "conductor")


def line(support="", top=False, count=1, gap=1.0, sag=1.0, r=0.012, span_only=False):
	"""Supports along y with their conductors: one support, a span of wire one metre long to
	stretch between two, or a run of several."""
	parts = place(support)
	points = wire_points(parts, top)
	if span_only:
		for ob in parts.values():
			bpy.data.objects.remove(ob, do_unlink=True)
		with kit.stage("wires"):
			wires(points, -0.5, 0.5, sag, r)
		return
	for i in range(1, count):
		place(support, at=(0, i * gap, 0))
	with kit.stage("wires"):
		for i in range(count - 1):
			wires(points, i * gap, (i + 1) * gap, sag, r)


def wind_farm(count=3, gap=120.0):
	for i in range(count):
		place("energy.wind.turbine_45m", at=((i - (count - 1) / 2) * gap, (i % 2) * gap * 0.4, 0), turn=(i * 7) % 20 - 10)


for _id, _a in INDEX["assets"].items():
	register(_id, model, _a["label"], family=_a["family"], tags=tuple(_a["tags"]) + ("torque_shed",), src=_id)

_out = ("outdoor", "torque_shed")
register("energy.line.span_pylon", line, "Pylon conductors, per metre of span", family="fixture", tags=_out, stretch="z",
	support="energy.line.pylon_lattice", sag=7.0, r=0.02, span_only=True)
register("energy.line.span_pole", line, "Pole conductors, per metre of span", family="fixture", tags=_out, stretch="z",
	support="energy.line.pole_plain", top=True, sag=0.9, r=0.008, span_only=True)
register("energy.line.pylon_run_3", line, "Powerline: three pylons and conductors, 500 m", family="fixture", tags=_out,
	support="energy.line.pylon_lattice", count=3, gap=250.0, sag=7.0, r=0.02)
register("energy.line.pole_run_5", line, "Powerline: five timber poles and conductors, 200 m", family="fixture", tags=_out,
	support="energy.line.pole_plain", top=True, count=5, gap=50.0, sag=0.9, r=0.008)
register("energy.wind.farm_3", wind_farm, "Wind farm: three turbines", family="fixture", tags=_out, count=3)
register("energy.wind.farm_6", wind_farm, "Wind farm: six turbines", family="fixture", tags=_out, count=6)
# (the library's first pylon, pole and turbine were rough: their ids now give Torque Shed's)
register("street.utility.pylon", model, "Electricity pylon", family="fixture", tags=_out, src="energy.line.pylon_lattice")
register("street.utility.telegraph_pole", model, "Timber pole with cross arm", family="fixture", tags=_out, src="energy.line.pole_plain")
register("energy.plant.turbine", model, "Wind turbine, 45 m hub", family="fixture", tags=_out, src="energy.wind.turbine_45m")
