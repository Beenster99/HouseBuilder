"""Statement furniture and feature lights for showpiece rooms (asked for by the design
office): generic designs, no maker's shape or name. The lit parts are in the slot "glow"."""
import math

import kit
from registry import register


def reg(id, fn, label, *tags, **params):
	register(id, fn, label, family="fixture", tags=("furniture", "office", "statement") + tags, **params)


def spline(pts, per=6):
	"""A smooth Catmull-Rom curve through 2D points."""
	out = []
	q = [pts[0]] + list(pts) + [pts[-1]]
	for i in range(1, len(q) - 2):
		p0, p1, p2, p3 = q[i - 1], q[i], q[i + 1], q[i + 2]
		for k in range(per):
			t = k / per
			out.append(tuple(0.5 * (2 * p1[j] + (p2[j] - p0[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t * t + (3 * p1[j] - p0[j] - 3 * p2[j] + p3[j]) * t ** 3) for j in (0, 1)))
	out.append(tuple(pts[-1]))
	return out


def loft(profile, outline_at, slot, name, x=0.0):
	"""Runs an outline (out from the sitter's side of the curve, across the chair) along a
	side profile of (y, z) points. outline_at(u) gives the outline at u = 0..1 along it, so
	shells can narrow and cushions can round off at their ends."""
	import bpy
	import bmesh
	from mathutils import Matrix, Vector
	bm = bmesh.new()
	pts = [Vector((x, y, z)) for y, z in profile]
	rings = []
	for i, p in enumerate(pts):
		t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
		side = t.cross(Vector((1, 0, 0))).normalized()
		rings.append([bm.verts.new(p + side * n + Vector((1, 0, 0)) * ax) for n, ax in outline_at(i / (len(pts) - 1))])
	n = len(rings[0])
	for r0, r1 in zip(rings, rings[1:]):
		for i in range(n):
			j = (i + 1) % n
			bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
	bm.faces.new(rings[0][::-1])
	bm.faces.new(rings[-1])
	return kit._obj(name, bm, slot, Matrix.Identity(4))


def dish(w, t, lift, n0=0.0, steps=12):
	"""A shell cross-section: w wide, t thick, its sides curling `lift` toward the sitter."""
	top, bottom = [], []
	for i in range(steps + 1):
		ax = -w / 2 + w * i / steps
		up = lift * abs(2 * ax / w) ** 2.6
		bottom.append((n0 + up, ax))
		top.append((n0 + up + t, ax))
	return bottom + top[::-1]


def pad(w, t, lift, n0, r=0.035, steps=12):
	"""A cushion cross-section sitting in a dish: rounded at its sides."""
	top, bottom = [], []
	for i in range(steps + 1):
		ax = -w / 2 + w * i / steps
		edge = min(1.0, (w / 2 - abs(ax)) / r)
		rnd = t / 2 * (1 - math.sqrt(max(0.0, 1 - (1 - edge) ** 2))) if edge < 1 else 0.0
		up = lift * abs(2 * ax / w) ** 2.6
		bottom.append((n0 + up + rnd * 0.4, ax))
		top.append((n0 + up + t - rnd, ax))
	return bottom + top[::-1]


def swivel_base(y, top, r=0.34, arms=5):
	"""A polished five-star swivel base: a hub, swept arms that curve down to glides, a
	column and a mounting plate under the shell."""
	kit.lathe([(0, 0.075), (0.05, 0.075), (0.058, 0.09), (0.05, 0.125), (0.032, 0.14), (0.028, top - 0.03), (0.11, top - 0.02), (0.12, top - 0.012), (0.12, top), (0, top)], (0, y, 0), "aluminium", "column", segs=24)
	for i in range(arms):
		a = math.radians(90 + i * 360 / arms)
		c, s = math.cos(a), math.sin(a)
		path = [(d * c, y + d * s, 0.105 - 0.075 * (d / r) ** 2) for d in [0.03 + (r - 0.03) * k / 8 for k in range(9)]]
		kit.sweep(path, [(-0.022, -0.012), (0.022, -0.012), (0.016, 0.014), (-0.016, 0.014)], "aluminium", "base_arm")
		kit.cyl(0.022, 0.018, (r * c, y + r * s, 0.009), "plastic_black", "glide", segs=10)


def lounge_chair():
	"""A reclined lounge chair: one moulded plywood shell sweeping from the seat lip up to
	the headrest, a continuous leather pad seated in it, padded arms that join the seat to
	the back, and a five-star swivel base. Its ottoman, built the same way, stands in front."""
	side = spline([(0.46, 0.385), (0.4, 0.41), (0.2, 0.395), (-0.05, 0.36), (-0.24, 0.35), (-0.36, 0.41), (-0.44, 0.56), (-0.53, 0.8), (-0.62, 1.02), (-0.66, 1.14)], per=5)
	n = len(side)
	def taper(u):
		return 1.0 - 0.22 * max(0.0, (u - 0.55) / 0.45) ** 1.5
	with kit.stage("frame"):
		swivel_base(-0.1, 0.345)
		loft(side, lambda u: dish(0.8 * taper(u), 0.022, 0.07), "hardwood", "shell")
		for s in (-1, 1):
			arm = spline([(0.3, 0.44), (0.3, 0.55), (0.2, 0.615), (-0.1, 0.62), (-0.34, 0.6), (-0.455, 0.57)], per=5)
			def arm_at(u, s=s):
				end = min(u, 1 - u) / 0.12
				k = 0.6 + 0.4 * (math.sqrt(max(0.0, 1 - (1 - end) ** 2)) if end < 1 else 1.0)
				return [(0.028 * k * math.cos(2 * math.pi * i / 12), 0.045 * k * math.sin(2 * math.pi * i / 12)) for i in range(12)]
			with kit.hollow(0.4):
				loft(arm, arm_at, "leather_black", "arm", x=s * 0.4)
	with kit.stage("cushions"), kit.hollow(0.3):
		def cushion(u):
			end = min(u, 1 - u) / 0.06
			k = math.sqrt(max(0.0, 1 - (1 - end) ** 2)) if end < 1 else 1.0
			# two shallow tucks divide the pad into seat, back and headrest
			tuck = min(abs(u - 0.47), abs(u - 0.8)) / 0.03
			k *= 0.72 + 0.28 * min(1.0, tuck)
			return pad(0.72 * taper(u) * (0.92 + 0.08 * k), 0.1 * (0.2 + 0.8 * k), 0.07, 0.022)
		loft(side[2:n - 1], cushion, "leather_black", "pad")
	with kit.stage("ottoman"):
		oy = 1.05
		swivel_base(oy, 0.335, r=0.27, arms=4)
		top = spline([(oy + 0.27, 0.385), (oy + 0.15, 0.365), (oy, 0.357), (oy - 0.15, 0.365), (oy - 0.27, 0.385)], per=4)
		loft(top, lambda u: dish(0.62, 0.022, 0.05), "hardwood", "ottoman_shell")
		def opad(u):
			end = min(u, 1 - u) / 0.14
			k = math.sqrt(max(0.0, 1 - (1 - end) ** 2)) if end < 1 else 1.0
			return pad(0.56 * (0.92 + 0.08 * k), 0.1 * (0.2 + 0.8 * k), 0.05, 0.022)
		with kit.hollow(0.3):
			loft(top[1:-1], opad, "leather_black", "ottoman_pad")
	kit.socket("seat", (0, 0, 0.5))


def curved_sofa(arc_len=3.6, radius=2.6):
	"""A sculptural sofa on an arc: a deep rounded seat, a low wrapping back, a recessed plinth."""
	half = math.degrees(arc_len / radius) / 2
	a0, a1 = 90 - half, 90 + half
	c = (0, -radius, 0)
	with kit.stage("frame"):
		kit.sweep(kit.arc((c[0], c[1], 0.05), radius, a0 + 1, a1 - 1, 24), kit.rect(0.8, 0.1), "brass", "plinth")
	with kit.stage("upholstery"), kit.hollow(0.25):
		seat = [(-0.5, -0.12), (-0.44, -0.17), (0.44, -0.17), (0.5, -0.12), (0.5, 0.1), (0.42, 0.17), (-0.42, 0.17), (-0.5, 0.1)]
		kit.sweep(kit.arc((c[0], c[1], 0.27), radius, a0, a1, 28), seat, "velvet_teal", "seat")
		back = [(-0.13, -0.3), (0.13, -0.3), (0.15, 0.22), (0.08, 0.32), (-0.08, 0.32), (-0.15, 0.22)]
		kit.sweep(kit.arc((c[0], c[1], 0.62), radius + 0.4, a0 + 2, a1 - 2, 28), back, "velvet_teal", "back")
		for a in (a0, a1):
			x, y = radius * math.cos(math.radians(a)), -radius + radius * math.sin(math.radians(a))
			kit.cyl(0.5, 0.34, (x, y, 0.27), "velvet_teal", "end", segs=24)
	kit.socket("seat", (0, 0, 0.45))


def coffee_table(style="marble"):
	if style == "marble":
		kit.cyl(0.26, 0.3, (0, 0, 0.15), "glulam", "drum", segs=32)
		for i in range(16):
			a = math.radians(i * 22.5)
			kit.cyl(0.03, 0.3, (0.25 * math.cos(a), 0.25 * math.sin(a), 0.15), "glulam", "flute", segs=8)
		kit.lathe([(0, 0.3), (0.6, 0.3), (0.615, 0.315), (0.615, 0.335), (0.6, 0.35), (0, 0.35)], (0, 0, 0), "marble", "top", segs=48)
		kit.lathe([(0, 0.0), (0.36, 0.0), (0.37, 0.01), (0.37, 0.03), (0.36, 0.04), (0, 0.04)], (0.5, 0.25, 0.2), "marble", "side_top", segs=36)
		kit.cyl(0.12, 0.2, (0.5, 0.25, 0.1), "brass", "side_stem", segs=20)
	else:
		kit.rounded_box((1.5, 0.75, 0.09), (0, 0, 0.31), "glulam", "oak_slab", radius=0.02)
		for s in (-1, 1):
			kit.rounded_box((0.14, 0.6, 0.27), (s * 0.5, 0, 0.135), "marble", "stone_block", radius=0.015)
	kit.socket("top", (0, 0, 0.36))


def ring_pendant(d=1.8, drop=1.2):
	"""A suspended LED ring. Origin at the ceiling: it hangs down from z = 0."""
	r = d / 2
	with kit.stage("fixings"):
		kit.cyl(0.07, 0.03, (0, 0, -0.015), "plastic_black", "ceiling_rose", segs=20)
		for i in range(3):
			a = math.radians(90 + i * 120)
			kit.rod((0.03 * math.cos(a), 0.03 * math.sin(a), -0.03), (r * math.cos(a), r * math.sin(a), -drop + 0.03), 0.002, "steel_stainless", "cable", segs=5)
	with kit.stage("ring"):
		kit.sweep(kit.arc((0, 0, -drop), r, 0, 360, 64), kit.rect(0.05, 0.06), "plastic_black", "housing")
		kit.sweep(kit.arc((0, 0, -drop - 0.034), r, 0, 360, 64), kit.rect(0.04, 0.012), "glow", "diffuser")
		kit.sweep(kit.arc((0, 0, -drop), r - 0.028, 0, 360, 64), kit.rect(0.008, 0.04), "glow", "inner_diffuser")
	kit.socket("light", (0, 0, -drop))


def arc_floor_lamp(reach=1.7, h=2.05):
	"""An arched floor lamp: a round marble drum, one polished tube rising and sweeping over
	in a single arc, and a spun dome shade on a swivel over the seat."""
	with kit.stage("base"):
		kit.lathe([(0, 0), (0.15, 0), (0.165, 0.012), (0.165, 0.2), (0.15, 0.215), (0, 0.215)], (0, 0, 0), "marble", "base", segs=48)
		kit.lathe([(0, 0.215), (0.03, 0.215), (0.03, 0.225), (0.02, 0.26), (0, 0.26)], (0, 0, 0), "steel_stainless", "collar", segs=20)
	with kit.stage("arm"):
		rz = h - 1.1
		path = [(0, 0, 0.22), (0, 0, 0.7)]
		path += [(0, reach / 2 - (reach / 2) * math.cos(math.radians(a)), 1.1 + rz * math.sin(math.radians(a))) for a in range(0, 157, 4)]
		kit.sweep(path, kit.circle(0.013, 12), "steel_stainless", "arc", up=(1, 0, 0))
		tip, before = path[-1], path[-2]
		d = [tip[i] - before[i] for i in range(3)]
		ln = math.sqrt(sum(c * c for c in d))
		neck = tuple(tip[i] + d[i] / ln * 0.05 for i in range(3))
		kit.sphere(0.024, neck, "steel_stainless", "swivel", segs=16)
	with kit.stage("shade"):
		sy, sz = neck[1], neck[2] - 0.015
		outer = [(0.26 * math.sin(math.radians(a)), -0.2 * (1 - math.cos(math.radians(a)))) for a in range(0, 91, 9)]
		inner = [(max(r - 0.006, 0.0), z - 0.006) for r, z in outer][::-1]
		kit.lathe([(0.0, 0.0)] + outer[1:] + inner[:-1] + [(0.0, -0.006)], (0, sy, sz), "steel_stainless", "shade", segs=48)
		kit.lathe([(0, -0.02), (0.03, -0.02), (0.03, -0.07), (0, -0.07)], (0, sy, sz), "plastic_black", "lamp_holder", segs=16)
		kit.sphere(0.055, (0, sy, sz - 0.115), "glow", "lamp", segs=18)
	kit.socket("light", (0, sy, sz - 0.2))


reg("furniture.statement.lounge_chair", lounge_chair, "Lounge chair and ottoman, plywood shell and leather")
reg("furniture.statement.curved_sofa", curved_sofa, "Curved velvet sofa, 3.6 m arc")
reg("furniture.statement.coffee_table", coffee_table, "Coffee table, round marble on oak drum")
reg("furniture.statement.coffee_table_slab", coffee_table, "Coffee table, oak slab on stone blocks", style="slab")
reg("furniture.light.ring_pendant", ring_pendant, "LED ring pendant, 1.8 m", "ceiling")
reg("furniture.light.ring_pendant_1500", ring_pendant, "LED ring pendant, 1.5 m", "ceiling", d=1.5, drop=1.0)
reg("furniture.light.arc_floor_lamp", arc_floor_lamp, "Arc floor lamp, marble base")
