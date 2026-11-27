"""The kit: the small shapes every asset is assembled from.

Blender axes: X width, Y depth, Z up, metres. Every function adds one object to the scene
with its transform baked in, a material slot (materials.py) and the current build stage, and
returns it. Curved faces are smooth and creases sharp, so the game's sketch look outlines a
pipe's silhouette and not its facets.
"""
import math
from contextlib import contextmanager

import bpy  # first: it provides bmesh and mathutils
import bmesh
from mathutils import Euler, Matrix, Vector
from mathutils.geometry import tessellate_polygon

import materials

SHARP = math.radians(35.0)
_stage = ["main"]
_count = [0]
_fill = [1.0]


@contextmanager
def stage(name: str):
	"""Parts made inside belong to this build stage (the timelapse builds stage by stage)."""
	_stage.append(name)
	try:
		yield
	finally:
		_stage.pop()


@contextmanager
def hollow(fill: float):
	"""Parts made inside are shells: only `fill` of their volume counts toward mass."""
	_fill.append(fill)
	try:
		yield
	finally:
		_fill.pop()


def _place(at, rot) -> Matrix:
	m = Matrix.Translation(Vector(at))
	if rot != (0, 0, 0):
		m = m @ Euler([math.radians(a) for a in rot]).to_matrix().to_4x4()
	return m


def _obj(name: str, bm: bmesh.types.BMesh, slot: str, matrix: Matrix) -> bpy.types.Object:
	bm.transform(matrix)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
	for f in bm.faces:
		f.smooth = True
	for e in bm.edges:
		if len(e.link_faces) != 2 or e.calc_face_angle(0.0) > SHARP:
			e.smooth = False
	volume = abs(bm.calc_volume())
	_count[0] += 1
	full = "%s.%s.%03d" % (_stage[-1], name, _count[0])
	me = bpy.data.meshes.new(full)
	bm.to_mesh(me)
	bm.free()
	me.materials.append(materials.get(slot))
	ob = bpy.data.objects.new(full, me)
	bpy.context.scene.collection.objects.link(ob)
	ob["slot"] = slot
	ob["stage"] = _stage[-1]
	ob["mass"] = round(volume * materials.density(slot) * _fill[-1], 3)
	return ob


def socket(name: str, at) -> bpy.types.Object:
	"""A named attachment point (an empty), exported with the asset."""
	e = bpy.data.objects.new("socket." + name, None)
	e.location = Vector(at)
	bpy.context.scene.collection.objects.link(e)
	return e


# --- solids -------------------------------------------------------------------------------

def box(size, at=(0, 0, 0), slot="steel_painted", name="box", rot=(0, 0, 0)):
	"""A box centred on `at`."""
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts[:])
	return _obj(name, bm, slot, _place(at, rot))


def rounded_box(size, at=(0, 0, 0), slot="fabric_grey", name="rbox", radius=0.03, rot=(0, 0, 0), segments=3):
	"""A box with rounded edges (cushions, sanitaryware, appliances)."""
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts[:])
	r = min(radius, min(size) * 0.45)
	bmesh.ops.bevel(bm, geom=bm.edges[:], offset=r, segments=segments, profile=0.5, affect="EDGES")
	return _obj(name, bm, slot, _place(at, rot))


def cyl(r, h, at=(0, 0, 0), slot="steel_painted", name="cyl", axis="z", segs=20, r2=None, rot=(0, 0, 0)):
	"""A cylinder (or cone when r2 differs) centred on `at`, along `axis`."""
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r if r2 is None else r2, depth=h)
	m = _place(at, rot)
	if axis == "x":
		m = m @ Matrix.Rotation(math.radians(90), 4, "Y")
	elif axis == "y":
		m = m @ Matrix.Rotation(math.radians(-90), 4, "X")
	return _obj(name, bm, slot, m)


def sphere(r, at=(0, 0, 0), slot="cast_iron", name="sphere", segs=20):
	bm = bmesh.new()
	bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=segs // 2, radius=r)
	return _obj(name, bm, slot, _place(at, (0, 0, 0)))


def lathe(profile, at=(0, 0, 0), slot="ceramic", name="lathe", segs=24, scale=(1, 1, 1), rot=(0, 0, 0)):
	"""Spin (radius, z) points round Z: bowls, pans, tanks. `scale` squashes it to an oval;
	`rot` (-90, 0, 0) lays its axis along +Y (fuselages, drums, tanks on their side)."""
	bm = bmesh.new()
	rings = []
	for r, z in profile:
		rings.append([bm.verts.new((r * math.cos(2 * math.pi * i / segs), r * math.sin(2 * math.pi * i / segs), z)) for i in range(segs)])
	for a, b in zip(rings, rings[1:]):
		for i in range(segs):
			j = (i + 1) % segs
			bm.faces.new((a[i], a[j], b[j], b[i]))
	bm.faces.new(rings[0][::-1])
	bm.faces.new(rings[-1])
	bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts[:])
	return _obj(name, bm, slot, _place(at, rot))


# --- profiles (a cross-section run along a length) ------------------------------------------

def prism(points, length, at=(0, 0, 0), slot="steel_painted", name="prism", axis="y", rot=(0, 0, 0)):
	"""Extrude a 2D outline `length` along `axis`, centred on `at`. The outline is (x, z) for
	axis y, (y, z) for axis x and (x, y) for axis z."""
	bm = bmesh.new()
	h = length / 2.0
	def v(u, w, t):
		return {"y": (u, t, w), "x": (t, u, w), "z": (u, w, t)}[axis]
	a = [bm.verts.new(v(u, w, -h)) for u, w in points]
	b = [bm.verts.new(v(u, w, h)) for u, w in points]
	n = len(points)
	# Caps are tessellated by hand: outlines are often concave (I-sections, stair flights).
	for i, j, k in tessellate_polygon([[Vector((u, w, 0.0)) for u, w in points]]):
		bm.faces.new((a[i], a[j], a[k]))
		bm.faces.new((b[k], b[j], b[i]))
	for i in range(n):
		j = (i + 1) % n
		bm.faces.new((a[i], b[i], b[j], a[j]))
	return _obj(name, bm, slot, _place(at, rot))


def i_points(w, d, tf, tw):
	"""An I-section outline, centred, flanges top and bottom."""
	x, z, t = w / 2, d / 2, tw / 2
	return [(-x, -z), (x, -z), (x, -z + tf), (t, -z + tf), (t, z - tf), (x, z - tf), (x, z), (-x, z), (-x, z - tf), (-t, z - tf), (-t, -z + tf), (-x, -z + tf)]


def i_section(w, d, tf, tw, length, at=(0, 0, 0), slot="steel_painted", name="i_section", axis="y", rot=(0, 0, 0)):
	return prism(i_points(w, d, tf, tw), length, at, slot, name, axis, rot)


def angle(leg, t, length, at=(0, 0, 0), slot="steel_painted", name="angle", axis="y", rot=(0, 0, 0)):
	return prism([(0, 0), (leg, 0), (leg, t), (t, t), (t, leg), (0, leg)], length, at, slot, name, axis, rot)


def tube(r, length, at=(0, 0, 0), slot="steel_galvanised", name="tube", axis="z", wall=0.0, segs=16, rot=(0, 0, 0)):
	"""A round tube. With `wall` it is hollow (the bore shows at the ends)."""
	if wall <= 0.0 or wall >= r:
		return cyl(r, length, at, slot, name, axis, segs, rot=rot)
	bm = bmesh.new()
	h = length / 2.0
	rings = {}
	for key, rad, z in (("ob", r, -h), ("ot", r, h), ("ib", r - wall, -h), ("it", r - wall, h)):
		rings[key] = [bm.verts.new((rad * math.cos(2 * math.pi * i / segs), rad * math.sin(2 * math.pi * i / segs), z)) for i in range(segs)]
	for i in range(segs):
		j = (i + 1) % segs
		bm.faces.new((rings["ob"][i], rings["ob"][j], rings["ot"][j], rings["ot"][i]))
		bm.faces.new((rings["ib"][j], rings["ib"][i], rings["it"][i], rings["it"][j]))
		bm.faces.new((rings["ot"][i], rings["ot"][j], rings["it"][j], rings["it"][i]))
		bm.faces.new((rings["ob"][j], rings["ob"][i], rings["ib"][i], rings["ib"][j]))
	m = _place(at, rot)
	if axis == "x":
		m = m @ Matrix.Rotation(math.radians(90), 4, "Y")
	elif axis == "y":
		m = m @ Matrix.Rotation(math.radians(-90), 4, "X")
	return _obj(name, bm, slot, m)


def _between(a, b) -> tuple:
	a, b = Vector(a), Vector(b)
	d = b - a
	m = Matrix.Translation((a + b) / 2) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
	return m, d.length


def strut(a, b, w, d=None, slot="steel_painted", name="strut"):
	"""A rectangular bar from point a to point b."""
	m, length = _between(a, b)
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	bmesh.ops.scale(bm, vec=Vector((w, d or w, length)), verts=bm.verts[:])
	return _obj(name, bm, slot, m)


def rod(a, b, r, slot="steel_galvanised", name="rod", segs=12):
	"""A round bar or pipe from point a to point b."""
	m, length = _between(a, b)
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=length)
	return _obj(name, bm, slot, m)


# --- panels and frames --------------------------------------------------------------------

def frame(w, h, section, depth, at=(0, 0, 0), slot="paint_white", name="frame", bottom=True):
	"""A rectangular frame in the XZ plane, `at` its bottom centre: two jambs, a head and
	(optionally) a sill member."""
	x, y, z = at
	s = section
	parts = [
		box((s, depth, h), (x - w / 2 + s / 2, y, z + h / 2), slot, name + "_jamb"),
		box((s, depth, h), (x + w / 2 - s / 2, y, z + h / 2), slot, name + "_jamb"),
		box((w - 2 * s, depth, s), (x, y, z + h - s / 2), slot, name + "_head"),
	]
	if bottom:
		parts.append(box((w - 2 * s, depth, s), (x, y, z + s / 2), slot, name + "_sill"))
	return parts


def lattice(length, w, chord, web, at=(0, 0, 0), bays=None, slot="plant_yellow", name="lattice", axis="z"):
	"""A square lattice bay run (crane mast or jib): four corner chords with zigzag bracing
	on each face. `at` is the centre of its start end."""
	bays = bays or max(1, round(length / w))
	step = length / bays
	h = w / 2 - chord / 2
	def p(u, v, t):
		q = {"z": (u, v, t), "x": (t, u, v), "y": (u, t, v)}[axis]
		return (at[0] + q[0], at[1] + q[1], at[2] + q[2])
	corners = [(-h, -h), (h, -h), (h, h), (-h, h)]
	for u, v in corners:
		strut(p(u, v, 0), p(u, v, length), chord, slot=slot, name=name + "_chord")
	for i in range(bays):
		t0, t1 = i * step, (i + 1) * step
		for k in range(4):
			a, b = corners[k], corners[(k + 1) % 4]
			if i % 2:
				a, b = b, a
			strut(p(a[0], a[1], t0), p(b[0], b[1], t1), web, slot=slot, name=name + "_web")
			strut(p(a[0], a[1], t1), p(b[0], b[1], t1), web, slot=slot, name=name + "_tie")


# --- sweeps, wheels and other shared shapes ---------------------------------------------------

def circle(r, segs=16):
	"""A round outline for sweep()."""
	return [(r * math.cos(2 * math.pi * i / segs), r * math.sin(2 * math.pi * i / segs)) for i in range(segs)]


def rect(w, h):
	"""A rectangular outline for sweep(): w across, h up."""
	return [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]


def arc(centre, radius, a0, a1, steps=8, plane="xy"):
	"""Points on an arc from angle a0 to a1 (degrees) for sweep(): pipe and duct bends."""
	out = []
	for i in range(steps + 1):
		a = math.radians(a0 + (a1 - a0) * i / steps)
		u, v = radius * math.cos(a), radius * math.sin(a)
		q = {"xy": (u, v, 0), "xz": (u, 0, v), "yz": (0, u, v)}[plane]
		out.append((centre[0] + q[0], centre[1] + q[1], centre[2] + q[2]))
	return out


def sweep(path, outline, slot="steel_galvanised", name="sweep", up=(0, 0, 1)):
	"""Runs a 2D outline (across, up) along a path of points: bends, handrails, cables.
	`up` must not be parallel to the path."""
	bm = bmesh.new()
	pts = [Vector(p) for p in path]
	upv = Vector(up)
	rings = []
	for i, p in enumerate(pts):
		a = pts[max(i - 1, 0)]
		b = pts[min(i + 1, len(pts) - 1)]
		t = (b - a).normalized()
		side = t.cross(upv)
		if side.length < 1e-6:
			side = t.cross(Vector((1, 0, 0)))
		side.normalize()
		u = side.cross(t).normalized()
		rings.append([bm.verts.new(p + side * x + u * y) for x, y in outline])
	n = len(outline)
	for r0, r1 in zip(rings, rings[1:]):
		for i in range(n):
			j = (i + 1) % n
			bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
	bm.faces.new(rings[0][::-1])
	bm.faces.new(rings[-1])
	return _obj(name, bm, slot, Matrix.Identity(4))


def wheel(r, w, at, axis="x", tyre="rubber", hub="steel_painted"):
	"""A tyred wheel centred on `at`, its axle along `axis`."""
	cyl(r, w, at, tyre, "tyre", axis=axis, segs=22)
	cyl(r * 0.55, w + 0.02, at, hub, "hub", axis=axis, segs=14)


def grid_bars(w, h, at, nx, nz, r=0.004, slot="steel_galvanised", name="mesh", plane="xz"):
	"""Thin bars forming a mesh panel centred on `at` (fences, grilles, cages). `plane` is
	xz (upright, facing Y), yz (upright, facing X) or xy (flat)."""
	x, y, z = at
	def p(u, v):
		if plane == "xz":
			return (x + u, y, z + v)
		if plane == "yz":
			return (x, y + u, z + v)
		return (x + u, y + v, z)
	for i in range(nx + 1 if nx else 0):
		u = -w / 2 + w * i / nx
		rod(p(u, -h / 2), p(u, h / 2), r, slot, name, segs=4)
	for i in range(nz + 1 if nz else 0):
		v = -h / 2 + h * i / nz
		rod(p(-w / 2, v), p(w / 2, v), r, slot, name, segs=4)


def chunk(size, at=(0, 0, 0), slot="concrete", name="chunk", seed=1, points=14, rot=(0, 0, 0)):
	"""A broken lump: the convex hull of random points inside a box of `size` centred on
	`at`. The same seed always gives the same lump (rubble, boulders, broken masonry)."""
	import random
	rng = random.Random(seed)
	bm = bmesh.new()
	for _ in range(points):
		bm.verts.new(((rng.random() - 0.5) * size[0], (rng.random() - 0.5) * size[1], (rng.random() - 0.5) * size[2]))
	out = bmesh.ops.convex_hull(bm, input=bm.verts[:])
	junk = list({e for e in out.get("geom_interior", []) + out.get("geom_unused", []) if isinstance(e, bmesh.types.BMVert)})
	if junk:
		bmesh.ops.delete(bm, geom=junk, context="VERTS")
	return _obj(name, bm, slot, _place(at, rot))
