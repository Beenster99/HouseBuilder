"""Statement furniture and feature lights for showpiece rooms (asked for by the design
office): generic designs, no maker's shape or name. The lit parts are in the slot "glow"."""
import math

import kit
from registry import register


def reg(id, fn, label, *tags, **params):
	register(id, fn, label, family="fixture", tags=("furniture", "office", "statement") + tags, **params)


def star_base(r, z, arms=5, slot="aluminium"):
	kit.cyl(0.03, z, (0, 0, z / 2 + 0.02), slot, "post", segs=12)
	for i in range(arms):
		a = math.radians(90 + i * 360 / arms)
		kit.strut((0, 0, 0.06), (r * math.cos(a), r * math.sin(a), 0.02), 0.05, 0.03, slot, "base_arm")
		kit.cyl(0.025, 0.02, (r * math.cos(a), r * math.sin(a), 0.01), "plastic_black", "glide", segs=8)


def lounge_chair():
	"""A moulded plywood shell lounge chair with leather cushions, and its ottoman in front."""
	with kit.stage("frame"):
		star_base(0.36, 0.3)
		kit.rounded_box((0.82, 0.62, 0.035), (0, 0.02, 0.36), "hardwood", "seat_shell", radius=0.015, rot=(-14, 0, 0))
		kit.rounded_box((0.80, 0.035, 0.48), (0, -0.37, 0.62), "hardwood", "back_shell", radius=0.015, rot=(-24, 0, 0))
		kit.rounded_box((0.56, 0.035, 0.26), (0, -0.56, 0.98), "hardwood", "head_shell", radius=0.015, rot=(-28, 0, 0))
		for s in (-1, 1):
			kit.strut((s * 0.3, -0.42, 0.42), (s * 0.3, -0.5, 0.9), 0.04, 0.012, "aluminium", "back_brace")
			kit.rounded_box((0.09, 0.5, 0.05), (s * 0.44, -0.05, 0.56), "leather_black", "arm_pad", radius=0.022, rot=(-8, 0, 0))
			kit.strut((s * 0.42, 0.12, 0.4), (s * 0.44, 0.1, 0.54), 0.04, 0.012, "aluminium", "arm_bracket")
	with kit.stage("cushions"), kit.hollow(0.3):
		kit.rounded_box((0.70, 0.56, 0.13), (0, 0.04, 0.45), "leather_black", "seat_cushion", radius=0.05, rot=(-14, 0, 0))
		kit.rounded_box((0.68, 0.12, 0.42), (0, -0.31, 0.66), "leather_black", "back_cushion", radius=0.05, rot=(-24, 0, 0))
		kit.rounded_box((0.5, 0.11, 0.22), (0, -0.5, 1.0), "leather_black", "head_cushion", radius=0.045, rot=(-28, 0, 0))
	with kit.stage("ottoman"):
		oy = 0.95
		kit.cyl(0.03, 0.26, (0, oy, 0.15), "aluminium", "ottoman_post", segs=12)
		for i in range(4):
			a = math.radians(45 + i * 90)
			kit.strut((0, oy, 0.06), (0.26 * math.cos(a), oy + 0.26 * math.sin(a), 0.02), 0.05, 0.03, "aluminium", "ottoman_arm")
		kit.rounded_box((0.62, 0.5, 0.035), (0, oy, 0.3), "hardwood", "ottoman_shell", radius=0.015)
		with kit.hollow(0.3):
			kit.rounded_box((0.56, 0.46, 0.13), (0, oy, 0.385), "leather_black", "ottoman_cushion", radius=0.05)
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
	"""An arched floor lamp: a marble block, a steel arc, a dome shade over the seat."""
	with kit.stage("base"):
		kit.rounded_box((0.2, 0.42, 0.42), (0, 0, 0.21), "marble", "base", radius=0.015)
	with kit.stage("arm"):
		kit.cyl(0.012, 0.75, (0, 0, 0.42 + 0.375), "steel_stainless", "stem", segs=10)
		rz = h - 1.17
		path = [(0, reach / 2 - (reach / 2) * math.cos(math.radians(a)), 1.17 + rz * math.sin(math.radians(a))) for a in range(0, 151, 6)]
		kit.sweep(path, kit.rect(0.035, 0.012), "steel_stainless", "arc", up=(1, 0, 0))
		tip = path[-1]
		kit.rod(tip, (tip[0], tip[1] + 0.03, tip[2] - 0.12), 0.006, "steel_stainless", "drop", segs=6)
	with kit.stage("shade"):
		sy, sz = tip[1] + 0.03, tip[2] - 0.12
		kit.lathe([(0.02, 0.0), (0.12, -0.04), (0.2, -0.13), (0.22, -0.22), (0.21, -0.22), (0.19, -0.135), (0.115, -0.05), (0.02, -0.012)], (0, sy, sz), "steel_stainless", "shade", segs=36)
		kit.sphere(0.06, (0, sy, sz - 0.14), "glow", "lamp", segs=14)
	kit.socket("light", (0, sy, sz - 0.2))


reg("furniture.statement.lounge_chair", lounge_chair, "Lounge chair and ottoman, plywood shell and leather")
reg("furniture.statement.curved_sofa", curved_sofa, "Curved velvet sofa, 3.6 m arc")
reg("furniture.statement.coffee_table", coffee_table, "Coffee table, round marble on oak drum")
reg("furniture.statement.coffee_table_slab", coffee_table, "Coffee table, oak slab on stone blocks", style="slab")
reg("furniture.light.ring_pendant", ring_pendant, "LED ring pendant, 1.8 m", "ceiling")
reg("furniture.light.ring_pendant_1500", ring_pendant, "LED ring pendant, 1.5 m", "ceiling", d=1.5, drop=1.0)
reg("furniture.light.arc_floor_lamp", arc_floor_lamp, "Arc floor lamp, marble base")
