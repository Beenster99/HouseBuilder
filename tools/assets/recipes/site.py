"""Construction plant, temporary works, stored materials and hand tools.
Origin: ground centre; machines face +Y."""
import math

import kit
from recipes.plant import tower_crane
from registry import register


def reg(id, fn, label, *tags, **params):
	register("plant." + id, fn, label, family="plant", tags=("plant", "outdoor") + tags, **params)


def tracks(gauge, l, h, w):
	for s in (-1, 1):
		with kit.hollow(0.5):
			kit.rounded_box((w, l, h), (s * gauge / 2, 0, h / 2), "rubber", "track", radius=min(h, w) * 0.45)
		for i in range(max(2, int(l / (h * 0.9)))):
			y = -l / 2 + h / 2 + i * (l - h) / max(1, int(l / (h * 0.9)) - 1)
			kit.cyl(h * 0.32, w + 0.02, (s * gauge / 2, y, h / 2), "steel_painted", "roller", axis="x", segs=10)


def cab(w, d, h, at, paint="plant_yellow"):
	x, y, z = at
	with kit.hollow(0.1):
		kit.box((w, d, h * 0.4), (x, y, z + h * 0.2), paint, "cab_base")
		kit.box((w, d, 0.06), (x, y, z + h - 0.03), paint, "cab_roof")
		for sx in (-1, 1):
			for sy in (-1, 1):
				kit.box((0.05, 0.05, h * 0.6), (x + sx * (w / 2 - 0.025), y + sy * (d / 2 - 0.025), z + h * 0.68), paint, "cab_post")
	kit.box((w - 0.06, d - 0.06, h * 0.56), (x, y, z + h * 0.68), "glass", "cab_glass")


def excavator(s=1.0, tool="bucket", reach=1.0, paint="plant_yellow"):
	"""A tracked excavator; `s` scales the machine (1.0 is about 20 t), `reach` lengthens the
	boom for high-reach demolition."""
	with kit.stage("undercarriage"):
		tracks(2.4 * s, 4.2 * s, 0.9 * s, 0.6 * s)
		kit.box((1.8 * s, 2.0 * s, 0.4 * s), (0, 0, 0.75 * s), "steel_painted", "car_body")
		kit.cyl(0.7 * s, 0.2 * s, (0, 0, 1.0 * s), "steel_painted", "slew_ring", segs=20)
	with kit.stage("house"):
		with kit.hollow(0.4):
			kit.rounded_box((2.6 * s, 3.6 * s, 1.1 * s), (0, -0.6 * s, 1.65 * s), paint, "house", radius=0.08 * s)
			kit.box((2.5 * s, 0.8 * s, 0.9 * s), (0, -2.2 * s, 1.6 * s), "steel_painted", "counterweight")
		cab(1.0 * s, 1.5 * s, 1.5 * s, (-0.75 * s, 0.5 * s, 2.0 * s), paint)
	with kit.stage("boom"):
		p0 = (0.3 * s, 0.8 * s, 2.0 * s)
		p1 = (0.3 * s, 0.8 * s + 2.6 * s * reach, 2.0 * s + 3.6 * s * reach)
		p2 = (0.3 * s, p1[1] + 2.8 * s * reach, p1[2] - 0.2 * s) if reach > 1 else (0.3 * s, p1[1] + 2.4 * s, p1[2] - 0.6 * s)
		p3 = (0.3 * s, p2[1] + 0.4 * s, max(0.6 * s, p2[2] - 2.9 * s * (1.6 if reach > 1 else 1.0)))
		kit.strut(p0, p1, 0.45 * s, 0.6 * s, paint, "boom")
		kit.strut(p1, p2, 0.4 * s, 0.5 * s, paint, "boom_fore")
		kit.strut(p2, p3, 0.32 * s, 0.4 * s, paint, "stick")
		kit.rod((0.3 * s, 1.4 * s, 1.9 * s), ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2 + 0.2 * s, (p0[2] + p1[2]) / 2 - 0.2 * s), 0.09 * s, "steel_stainless", "ram")
		kit.rod(((p1[0]), p1[1] - 0.2 * s, p1[2] + 0.4 * s), (p2[0], p2[1] - 0.2 * s, p2[2] + 0.45 * s), 0.08 * s, "steel_stainless", "ram")
	with kit.stage("tool"):
		x, y, z = p3
		if tool == "bucket":
			with kit.hollow(0.2):
				kit.prism([(y - 0.9 * s, z + 0.1 * s), (y - 1.1 * s, z - 0.5 * s), (y - 0.5 * s, z - 0.9 * s), (y + 0.2 * s, z - 0.5 * s), (y + 0.1 * s, z + 0.1 * s)], 1.1 * s, (x, 0, 0), "steel_painted", "bucket", axis="x")
		elif tool == "breaker":
			kit.box((0.35 * s, 0.4 * s, 1.3 * s), (x, y, z - 0.5 * s), "steel_painted", "breaker_body")
			kit.cyl(0.07 * s, 0.9 * s, (x, y, z - 1.5 * s), "steel_stainless", "chisel", segs=10, r2=0.02 * s)
		elif tool == "grapple":
			for sg in (-1, 1):
				kit.sweep([(x, y, z), (x, y + sg * 0.6 * s, z - 0.5 * s), (x, y + sg * 0.2 * s, z - 1.2 * s)], kit.rect(0.8 * s, 0.08 * s), "steel_painted", "grapple_jaw", up=(1, 0, 0))
		elif tool == "shears":
			kit.box((0.3 * s, 0.6 * s, 0.9 * s), (x, y, z - 0.35 * s), "steel_painted", "shear_body")
			for sg in (-1, 1):
				kit.prism([(y, z - 0.7 * s), (y + sg * 0.5 * s, z - 1.1 * s), (y + sg * 0.1 * s, z - 1.9 * s), (y, z - 1.5 * s)], 0.14 * s, (x, 0, 0), "hazard_red", "jaw", axis="x")
	kit.socket("tool", p3)
	kit.socket("cab", (-0.75 * s, 0.5 * s, 2.0 * s))


def bulldozer():
	tracks(2.0, 3.6, 1.0, 0.55)
	with kit.hollow(0.5):
		kit.box((1.5, 2.2, 0.9), (0, 0.4, 1.3), "plant_yellow", "engine")
	cab(1.4, 1.3, 1.5, (0, -0.9, 0.9))
	kit.sweep([(0, 2.5, 1.3), (0, 2.75, 0.7), (0, 2.5, 0.1)], kit.rect(3.4, 0.06), "steel_painted", "blade", up=(1, 0, 0))
	for s in (-1, 1):
		kit.strut((s * 1.3, 0, 0.6), (s * 1.3, 2.5, 0.5), 0.15, 0.2, "plant_yellow", "push_arm")
	kit.cyl(0.06, 0.7, (0.6, 0.6, 2.1), "steel_painted", "exhaust", segs=8)


def loader(telehandler=False, backhoe=False):
	with kit.hollow(0.5):
		kit.rounded_box((2.0, 4.5 if not telehandler else 4.2, 1.0), (0, 0, 1.2), "plant_yellow", "body", radius=0.08)
	for s in (-1, 1):
		for y in (-1.4, 1.4):
			kit.wheel(0.65, 0.5, (s * 1.0, y, 0.65))
	cab(1.3 if not telehandler else 0.9, 1.4, 1.6, (0 if not telehandler else -0.5, -0.3, 1.7))
	if telehandler:
		kit.strut((0.45, -1.8, 1.9), (0.45, 3.2, 3.6), 0.3, 0.35, "plant_yellow", "boom")
		kit.strut((0.45, 3.2, 3.6), (0.45, 4.6, 4.1), 0.22, 0.26, "steel_painted", "boom_inner")
		kit.box((1.2, 0.08, 1.0), (0.45, 4.6, 3.8), "steel_painted", "carriage")
		for s in (-1, 1):
			kit.box((0.12, 1.2, 0.05), (0.45 + s * 0.35, 5.2, 3.35), "steel_painted", "fork")
	else:
		for s in (-1, 1):
			kit.strut((s * 0.8, 0.6, 1.9), (s * 0.8, 3.0, 0.6), 0.18, 0.3, "plant_yellow", "lift_arm")
		with kit.hollow(0.2):
			kit.prism([(2.8, 1.1), (2.8, 0.2), (3.7, 0.05), (3.9, 0.25), (3.2, 1.1)], 2.5, (0, 0, 0), "steel_painted", "bucket", axis="x")
	if backhoe:
		kit.strut((0, -2.2, 1.4), (0, -3.6, 3.2), 0.25, 0.3, "plant_yellow", "backhoe_boom")
		kit.strut((0, -3.6, 3.2), (0, -4.6, 1.0), 0.2, 0.25, "plant_yellow", "backhoe_stick")
		kit.box((0.6, 0.5, 0.5), (0, -4.6, 0.75), "steel_painted", "backhoe_bucket")


def dumper(s=1.0, artic=False):
	if artic:
		with kit.hollow(0.4):
			kit.box((2.6, 2.6, 1.6), (0, 3.6, 1.9), "plant_yellow", "tractor")
			kit.prism([(-4.2, 2.0), (-3.6, 1.2), (1.6, 1.2), (2.2, 3.2), (1.9, 3.2), (-4.2, 3.0)], 2.9, (0, 0, 0), "plant_yellow", "skip_body", axis="x")
		cab(1.6, 1.4, 1.5, (0, 3.9, 2.3))
		for sx in (-1, 1):
			for y in (3.6, -0.6, -2.4):
				kit.wheel(0.85, 0.7, (sx * 1.15, y, 0.85))
		return
	with kit.hollow(0.4):
		kit.box((1.4 * s, 1.6 * s, 0.7 * s), (0, -0.9 * s, 0.9 * s), "plant_yellow", "engine")
		kit.prism([(-0.2 * s, 0.7 * s), (0.2 * s, 0.5 * s), (1.9 * s, 0.9 * s), (2.1 * s, 1.7 * s), (-0.2 * s, 1.7 * s)], 1.8 * s, (0, 0, 0), "plant_yellow", "skip", axis="x")
	for sx in (-1, 1):
		for y in (-1.0 * s, 1.0 * s):
			kit.wheel(0.45 * s, 0.35 * s, (sx * 0.85 * s, y, 0.45 * s))
	kit.rounded_box((0.5 * s, 0.5 * s, 0.1 * s), (0, -1.2 * s, 1.35 * s), "leather_black", "seat", radius=0.03 * s)
	kit.sweep([(-0.6 * s, -1.6 * s, 1.2 * s), (-0.6 * s, -1.6 * s, 2.4 * s), (0.6 * s, -1.6 * s, 2.4 * s), (0.6 * s, -1.6 * s, 1.2 * s)], kit.rect(0.07 * s, 0.07 * s), "steel_painted", "rops", up=(0, 1, 0))


def truck_base(l=8.0, paint="car_white"):
	with kit.hollow(0.2):
		kit.rounded_box((2.5, 2.2, 2.4), (0, l / 2 - 1.1, 1.9), paint, "cab", radius=0.1)
		kit.box((1.0, l - 2.0, 0.3), (0, -1.0, 0.95), "steel_painted", "chassis")
	kit.box((2.3, 0.02, 0.9), (0, l / 2 + 0.002, 2.4), "glass", "windscreen")
	for s in (-1, 1):
		for y in (l / 2 - 1.3, -l / 2 + 2.4, -l / 2 + 1.1):
			kit.wheel(0.52, 0.32, (s * 1.08, y, 0.52))


def tipper_truck():
	truck_base(8.0, "plant_yellow")
	with kit.hollow(0.08):
		kit.prism([(-4.0, 1.2), (1.6, 1.2), (1.6, 2.7), (2.4, 2.9), (2.4, 3.0), (-4.0, 2.6)], 2.5, (0, 0, 0), "steel_painted", "tipper_body", axis="x")


def mixer_truck():
	truck_base(8.5)
	with kit.hollow(0.05):
		kit.lathe([(0.5, 0), (1.15, 1.0), (1.2, 3.0), (0.55, 5.0)], (0, 2.0, 1.9), "paint_white", "drum", segs=24, rot=(-105, 0, 180))
	kit.strut((0, -3.3, 3.0), (0, -4.6, 1.6), 0.5, 0.15, "steel_painted", "chute")
	kit.box((1.2, 0.5, 1.6), (0, -3.5, 1.9), "steel_painted", "hopper_frame")


def concrete_pump():
	truck_base(10.0)
	kit.box((2.2, 6.5, 0.6), (0, -1.5, 1.4), "steel_painted", "pump_deck")
	pts = [(0, 1.2, 1.9), (0, 1.2, 4.0), (0, -4.5, 4.4), (0, -4.3, 4.9), (0, 2.5, 5.4), (0, 2.5, 5.8), (0, -3.0, 6.2)]
	for a, b in zip(pts, pts[1:]):
		kit.strut(a, b, 0.3, 0.35, "hazard_red", "boom")
	kit.rod((0, -3.0, 6.2), (0, -3.0, 4.2), 0.07, "rubber", "end_hose")
	for s in (-1, 1):
		for y in (1.5, -3.5):
			kit.strut((s * 1.0, y, 1.2), (s * 3.2, y, 0.9), 0.2, 0.2, "steel_painted", "outrigger")
			kit.cyl(0.08, 0.8, (s * 3.2, y, 0.45), "steel_stainless", "jack", segs=10)
			kit.box((0.6, 0.6, 0.05), (s * 3.2, y, 0.025), "softwood", "pad")


def low_loader():
	truck_base(6.5)
	kit.box((2.6, 9.0, 0.3), (0, -7.5, 0.9), "steel_painted", "deck")
	kit.prism([(-3.0, 1.05), (-1.5, 1.05), (-1.5, 1.6), (-2.0, 1.9), (-3.0, 1.9)], 2.5, (0, 0, 0), "steel_painted", "swan_neck", axis="x")
	for s in (-1, 1):
		for y in (-10.0, -11.2):
			kit.wheel(0.4, 0.5, (s * 1.0, y, 0.4))


def mobile_crane(crawler=False):
	if crawler:
		tracks(4.0, 6.5, 1.2, 0.9)
		kit.box((3.0, 3.0, 0.5), (0, 0, 1.1), "steel_painted", "car_body")
		z0 = 1.4
	else:
		with kit.hollow(0.4):
			kit.box((2.6, 11.0, 0.9), (0, 0, 1.4), "plant_yellow", "carrier")
			kit.rounded_box((2.6, 2.0, 1.4), (0, 5.0, 2.3), "plant_yellow", "carrier_cab", radius=0.1)
		for s in (-1, 1):
			for y in (4.0, 2.4, -2.0, -3.6):
				kit.wheel(0.65, 0.45, (s * 1.1, y, 0.65))
			for y in (1.0, -4.8):
				kit.strut((s * 1.2, y, 1.2), (s * 3.6, y, 1.0), 0.25, 0.25, "plant_yellow", "outrigger")
				kit.cyl(0.1, 1.0, (s * 3.6, y, 0.5), "steel_stainless", "jack", segs=10)
				kit.box((0.9, 0.9, 0.06), (s * 3.6, y, 0.03), "softwood", "pad")
		z0 = 1.85
	with kit.stage("superstructure"):
		with kit.hollow(0.4):
			kit.box((2.6, 4.2, 1.3), (0, -1.8, z0 + 0.75), "plant_yellow", "house")
			kit.box((2.6, 1.0, 1.0), (0, -4.2, z0 + 0.6), "steel_painted", "counterweight")
		cab(1.0, 1.6, 1.5, (-0.9, 0.8, z0 + 0.1))
	with kit.stage("boom"):
		tip = (0.3, 9.0, z0 + 24.0) if not crawler else (0.3, 12.0, z0 + 34.0)
		if crawler:
			foot = (0.3, 0.5, z0 + 0.6)
			n = 22
			def bp(i, sx, sn):
				f = i / n
				taper = min(1.0, 4 * f + 0.15, 4 * (1 - f) + 0.15)
				return (foot[0] + (tip[0] - foot[0]) * f + sx * 0.7 * taper, foot[1] + (tip[1] - foot[1]) * f - sn * 0.66 * taper, foot[2] + (tip[2] - foot[2]) * f + sn * 0.25 * taper)
			for i in range(n):
				for sx in (-1, 1):
					for sn in (-1, 1):
						kit.rod(bp(i, sx, sn), bp(i + 1, sx, sn), 0.05, "plant_yellow", "boom_chord", segs=6)
					kit.rod(bp(i, sx, -1 if i % 2 else 1), bp(i + 1, sx, 1 if i % 2 else -1), 0.025, "plant_yellow", "boom_lacing", segs=5)
				for sn in (-1, 1):
					kit.rod(bp(i, -1 if i % 2 else 1, sn), bp(i + 1, 1 if i % 2 else -1, sn), 0.025, "plant_yellow", "boom_lacing", segs=5)
			kit.rod((0.3, -3.5, z0 + 6.0), tip, 0.03, "steel_galvanised", "pendant", segs=6)
			kit.strut((0.3, -1.5, z0 + 1.3), (0.3, -3.5, z0 + 6.0), 0.2, 0.2, "plant_yellow", "gantry")
		else:
			mid = tuple(a + (b - a) * 0.45 for a, b in zip((0.3, -2.5, z0 + 1.6), tip))
			kit.strut((0.3, -2.5, z0 + 1.6), mid, 0.8, 0.9, "plant_yellow", "boom_base")
			kit.strut(mid, tip, 0.55, 0.65, "plant_yellow", "boom_tele")
			kit.rod((0.3, 0.5, z0 + 0.8), tuple(a + (b - a) * 0.25 for a, b in zip((0.3, -2.5, z0 + 1.6), tip)), 0.16, "steel_stainless", "luffing_ram")
		kit.rod(tip, (tip[0], tip[1] + 0.3, tip[2] - 10.0), 0.015, "steel_galvanised", "hoist_rope", segs=6)
		kit.box((0.4, 0.3, 0.7), (tip[0], tip[1] + 0.3, tip[2] - 10.3), "hazard_red", "hook_block")
	kit.socket("hook", (tip[0], tip[1] + 0.3, tip[2] - 10.7))


def forklift():
	with kit.hollow(0.5):
		kit.rounded_box((1.15, 2.2, 0.9), (0, -0.2, 0.75), "plant_yellow", "body", radius=0.08)
		kit.box((1.1, 0.5, 0.6), (0, -1.1, 1.3), "steel_painted", "counterweight")
	for s in (-1, 1):
		kit.wheel(0.33, 0.25, (s * 0.5, 0.6, 0.33))
		kit.wheel(0.27, 0.2, (s * 0.45, -0.9, 0.27))
		kit.box((0.1, 0.12, 2.3), (s * 0.35, 1.05, 1.2), "steel_painted", "mast")
		kit.box((0.12, 1.1, 0.045), (s * 0.3, 1.7, 0.1), "steel_painted", "fork")
		kit.rod((s * 0.5, 0.5, 1.2), (s * 0.5, 0.3, 2.15), 0.03, "steel_painted", "guard_post")
		kit.rod((s * 0.5, -0.9, 1.6), (s * 0.5, -0.7, 2.15), 0.03, "steel_painted", "guard_post")
	kit.box((1.1, 1.3, 0.05), (0, -0.2, 2.17), "steel_painted", "overhead_guard")
	kit.box((0.9, 0.06, 0.6), (0, 1.14, 0.5), "steel_painted", "carriage")
	kit.rounded_box((0.5, 0.5, 0.12), (0, -0.4, 1.26), "leather_black", "seat", radius=0.04)


def scissor_lift(h=6.0):
	with kit.hollow(0.5):
		kit.box((1.2, 2.4, 0.6), (0, 0, 0.6), "plastic_blue", "chassis")
	for s in (-1, 1):
		for y in (-0.9, 0.9):
			kit.wheel(0.2, 0.15, (s * 0.6, y, 0.2))
	n = max(2, int(h / 1.5))
	step = (h - 0.9) / n
	for i in range(n):
		z = 0.9 + i * step
		for s in (-1, 1):
			kit.strut((s * 0.4, -1.0, z), (s * 0.4, 1.0, z + step), 0.06, 0.1, "plastic_blue", "scissor")
			kit.strut((s * 0.45, 1.0, z), (s * 0.45, -1.0, z + step), 0.06, 0.1, "plastic_blue", "scissor")
	kit.box((1.2, 2.4, 0.08), (0, 0, h + 0.04), "steel_galvanised", "platform")
	for z in (h + 0.55, h + 1.1):
		kit.sweep([(-0.58, -1.18, z), (0.58, -1.18, z), (0.58, 1.18, z), (-0.58, 1.18, z), (-0.58, -1.18, z)], kit.rect(0.04, 0.04), "steel_galvanised", "guardrail")
	for x in (-0.58, 0.58):
		for y in (-1.18, 0, 1.18):
			kit.rod((x, y, h), (x, y, h + 1.1), 0.02, "steel_galvanised", "post")
	kit.socket("platform", (0, 0, h + 0.08))


def boom_lift(h=16.0):
	with kit.hollow(0.5):
		kit.box((2.2, 3.0, 0.7), (0, 0, 0.8), "plastic_blue", "chassis")
		kit.box((1.6, 2.2, 0.9), (0, -0.3, 1.6), "plastic_blue", "turret")
	for s in (-1, 1):
		for y in (-1.1, 1.1):
			kit.wheel(0.45, 0.35, (s * 1.1, y, 0.45))
	a, b, c = (0, -1.2, 2.0), (0, 2.0, h * 0.55), (0, 4.0, h - 1.2)
	kit.strut(a, b, 0.35, 0.4, "plastic_blue", "boom")
	kit.strut(b, c, 0.25, 0.3, "paint_white", "fly_boom")
	kit.box((1.5, 0.8, 0.06), (0, 4.5, h - 1.2), "steel_galvanised", "basket_floor")
	kit.frame(1.5, 1.1, 0.03, 0.8, at=(0, 4.5, h - 1.2), slot="steel_galvanised", name="basket")
	kit.socket("platform", (0, 4.5, h - 1.15))


def roller(pedestrian=False):
	if pedestrian:
		kit.cyl(0.2, 0.65, (0, 0.2, 0.2), "steel_stainless", "drum", axis="x", segs=20)
		kit.box((0.6, 0.6, 0.4), (0, 0.1, 0.55), "plant_yellow", "engine")
		kit.sweep([(0, -0.2, 0.6), (0, -1.0, 1.0), (0, -1.1, 1.0)], kit.circle(0.02, 8), "steel_painted", "handle")
		return
	for y in (-1.3, 1.3):
		kit.cyl(0.6, 1.5, (0, y, 0.6), "steel_stainless", "drum", axis="x", segs=28)
	with kit.hollow(0.5):
		kit.rounded_box((1.4, 2.6, 0.8), (0, 0, 1.3), "plant_yellow", "body", radius=0.08)
	kit.rounded_box((0.5, 0.5, 0.12), (0, -0.2, 1.76), "leather_black", "seat", radius=0.04)
	kit.sweep([(-0.6, -0.6, 1.7), (-0.6, -0.6, 2.8), (0.6, -0.6, 2.8), (0.6, -0.6, 1.7)], kit.rect(0.07, 0.07), "steel_painted", "rops", up=(0, 1, 0))


def piling_rig():
	tracks(3.0, 5.0, 1.0, 0.7)
	with kit.hollow(0.4):
		kit.box((3.0, 4.5, 1.4), (0, -0.8, 1.8), "plant_yellow", "house")
	cab(1.0, 1.5, 1.5, (-0.9, 1.0, 1.2))
	kit.box((0.6, 0.7, 18.0), (0.3, 3.0, 9.3), "plant_yellow", "mast")
	kit.strut((0.3, -1.5, 2.5), (0.3, 2.8, 12.0), 0.25, 0.25, "plant_yellow", "backstay")
	kit.box((1.0, 0.9, 1.2), (0.3, 3.8, 14.0), "steel_painted", "rotary_head")
	kit.cyl(0.3, 12.0, (0.3, 3.8, 7.4), "steel_painted", "auger", segs=12)
	for i in range(20):
		kit.cyl(0.45, 0.04, (0.3, 3.8, 1.6 + i * 0.6), "steel_painted", "flight", segs=14)


def small_plant(what="mixer"):
	if what == "mixer":
		kit.frame(0.7, 0.7, 0.04, 0.9, at=(0, 0, 0), slot="plant_yellow", name="frame", bottom=False)
		with kit.hollow(0.05):
			kit.lathe([(0.2, 0), (0.33, 0.25), (0.3, 0.5), (0.2, 0.65)], (0, 0.2, 0.75), "hivis_orange", "drum", segs=18, rot=(-50, 0, 0))
		for s in (-1, 1):
			kit.wheel(0.15, 0.06, (s * 0.4, -0.4, 0.15))
		kit.box((0.3, 0.3, 0.3), (0, -0.4, 0.5), "plant_yellow", "motor")
	elif what in ("generator", "compressor", "pump"):
		with kit.hollow(0.5):
			kit.rounded_box((1.0, 2.0, 1.0), (0, 0, 0.85), "plant_yellow" if what != "pump" else "plastic_blue", "canopy", radius=0.06)
		for s in (-1, 1):
			kit.wheel(0.28, 0.16, (s * 0.6, -0.2, 0.28))
		kit.rod((0, 1.0, 0.45), (0, 1.9, 0.45), 0.025, "steel_galvanised", "drawbar")
		kit.rod((0, 1.6, 0), (0, 1.6, 0.45), 0.02, "steel_galvanised", "jockey")
		if what == "pump":
			kit.sweep([(0.5, 0, 0.6), (0.9, 0, 0.3), (1.2, 0.8, 0.08), (1.0, 2.0, 0.08)], kit.circle(0.06, 8), "plastic_green", "hose")
		else:
			kit.cyl(0.04, 0.3, (0.3, -0.6, 1.5), "steel_painted", "exhaust", segs=8)
	elif what == "lighting_tower":
		with kit.hollow(0.5):
			kit.rounded_box((1.0, 1.6, 0.8), (0, 0, 0.75), "plant_yellow", "base", radius=0.06)
		for s in (-1, 1):
			kit.wheel(0.28, 0.16, (s * 0.6, 0, 0.28))
		kit.cyl(0.05, 7.0, (0, 0, 4.6), "steel_galvanised", "mast", segs=10)
		for s in (-1, 1):
			for z in (7.6, 8.0):
				kit.box((0.5, 0.12, 0.3), (s * 0.3, 0.05, z), "aluminium", "lamp")
				kit.box((0.46, 0.01, 0.26), (s * 0.3, 0.112, z), "light_emitter", "lens")
	elif what == "plate":
		kit.box((0.45, 0.6, 0.03), (0, 0, 0.015), "steel_painted", "plate")
		kit.box((0.35, 0.4, 0.3), (0, 0, 0.2), "plant_yellow", "engine")
		kit.sweep([(-0.2, -0.2, 0.3), (-0.2, -0.7, 0.95), (0.2, -0.7, 0.95), (0.2, -0.2, 0.3)], kit.circle(0.015, 8), "steel_painted", "handle")
	elif what == "bowser":
		with kit.hollow(0.05):
			kit.lathe([(0.3, 0), (0.55, 0.15), (0.55, 1.65), (0.3, 1.8)], (0, -0.9, 1.0), "plastic_blue", "tank", segs=20, rot=(-90, 0, 0))
		kit.box((0.9, 2.0, 0.1), (0, 0, 0.45), "steel_galvanised", "chassis")
		for s in (-1, 1):
			kit.wheel(0.28, 0.16, (s * 0.65, -0.2, 0.28))
		kit.rod((0, 1.0, 0.45), (0, 1.9, 0.45), 0.025, "steel_galvanised", "drawbar")
	elif what == "fuel_tank":
		with kit.hollow(0.1):
			kit.box((1.2, 2.2, 1.2), (0, 0, 0.75), "plastic_green", "bunded_tank")
		for y in (-0.8, 0.8):
			kit.box((1.2, 0.15, 0.15), (0, y, 0.075), "steel_painted", "skid")
		kit.box((0.4, 0.3, 0.5), (0.3, 1.0, 1.1), "steel_painted", "pump_cabinet")


def welfare(what="toilet"):
	if what == "toilet":
		with kit.hollow(0.05):
			kit.box((1.1, 1.2, 2.2), (0, 0, 1.2), "plastic_blue", "cabin")
		kit.prism([(-0.6, 0), (0.6, 0), (0, 0.15)], 1.3, (0, 0, 2.3), "plastic_white", "roof", axis="y")
		kit.box((0.75, 0.03, 1.9), (0, 0.6, 1.15), "plastic_white", "door")
		kit.box((1.2, 1.3, 0.1), (0, 0, 0.05), "plastic_black", "skid")
	else:
		l = {"container_20": 6.06, "container_40": 12.19, "store": 6.06, "welfare": 7.3, "double": 9.6}[what]
		w, h = 2.44, 2.59
		paint = {"container_20": "car_blue", "container_40": "car_red", "store": "plastic_green", "welfare": "paint_white", "double": "plastic_grey"}[what]
		floors = 2 if what == "double" else 1
		for f in range(floors):
			z = f * h
			with kit.hollow(0.02):
				kit.box((w, l, h), (0, 0, z + h / 2), paint, "shell")
			for i in range(int(l / 0.3)):
				for s in (-1, 1):
					kit.box((0.03, 0.12, h - 0.4), (s * (w / 2 + 0.01), -l / 2 + 0.2 + i * 0.3, z + h / 2), paint, "corrugation")
			for sx in (-1, 1):
				for sy in (-1, 1):
					kit.box((0.18, 0.18, h + 0.02), (sx * (w / 2 - 0.08), sy * (l / 2 - 0.08), z + h / 2), "steel_painted", "corner_post")
			if what in ("welfare", "double"):
				kit.box((0.02, 0.9, 2.0), (w / 2 + 0.03, -l / 2 + 1.0, z + 1.05), "plant_yellow", "door")
				for y in (0.3, 2.0):
					kit.box((0.02, 1.1, 0.9), (w / 2 + 0.03, y, z + 1.55), "glass", "window")
			else:
				for s in (-1, 1):
					kit.box((w / 2 - 0.12, 0.04, h - 0.3), (s * (w / 4 - 0.03), l / 2 + 0.01, z + h / 2), paint, "door")
					kit.rod((s * 0.25, l / 2 + 0.05, z + 0.2), (s * 0.25, l / 2 + 0.05, z + h - 0.2), 0.015, "steel_galvanised", "lock_bar")
		if what == "double":
			n = 14
			for i in range(n):
				kit.box((0.9, 0.27, 0.04), (w / 2 + 0.5, -l / 2 + 1.0 + 0.9 + i * 0.27, (i + 1) * h / n), "steel_galvanised", "stair_tread")
			kit.strut((w / 2 + 0.95, -l / 2 + 1.9, 0), (w / 2 + 0.95, -l / 2 + 1.9 + n * 0.27, h), 0.04, 0.2, "steel_galvanised", "stringer")
			kit.strut((w / 2 + 0.95, -l / 2 + 1.9, 1.0), (w / 2 + 0.95, -l / 2 + 1.9 + n * 0.27, h + 1.0), 0.04, 0.04, "steel_galvanised", "handrail")


def silo():
	for x in (-1, 1):
		for y in (-1, 1):
			kit.rod((x, y, 0), (x * 0.95, y * 0.95, 4.0), 0.08, "steel_galvanised", "leg")
			kit.rod((x, y, 0.5), (-x if y > 0 else x, y if y > 0 else -y, 2.5), 0.03, "steel_galvanised", "brace")
	with kit.hollow(0.03):
		kit.lathe([(0.15, 1.5), (1.4, 4.0), (1.4, 9.0), (0.3, 9.6)], (0, 0, 0), "paint_white", "silo", segs=24)
	kit.rod((1.45, 0, 0), (1.45, 0, 9.4), 0.04, "steel_galvanised", "fill_pipe")


def hoarding(l=1.0, h=2.4):
	kit.box((l, 0.018, h), (0, 0, h / 2), "plywood", "sheet")
	for z in (0.3, h - 0.3):
		kit.box((l, 0.05, 0.1), (0, -0.034, z), "softwood", "rail")


def hoarding_post(h=2.4):
	kit.box((0.1, 0.1, h), (0, -0.06, h / 2), "softwood", "post")
	kit.strut((0, -0.1, h * 0.7), (0, -1.4, 0), 0.05, 0.1, "softwood", "raker")
	kit.rounded_box((0.4, 0.5, 0.25), (0, -1.4, 0.125), "concrete", "kentledge", radius=0.03)


def site_gate(w=6.0):
	for s in (-1, 1):
		kit.box((0.15, 0.15, 2.4), (s * w / 2, 0, 1.2), "steel_painted", "post")
		kit.frame(w / 2 - 0.1, 2.1, 0.05, 0.05, at=(s * (w / 4), 0, 0.15), slot="steel_galvanised", name="leaf")
		kit.box((w / 2 - 0.2, 0.01, 2.0), (s * (w / 4), 0, 1.2), "plastic_green", "sheet")
	kit.box((1.2, 0.02, 0.8), (-w / 4, 0.02, 1.5), "paint_white", "site_sign")
	kit.socket("hinge_left", (-w / 2, 0, 0))
	kit.socket("hinge_right", (w / 2, 0, 0))


def barrier(what="water"):
	if what == "water":
		with kit.hollow(0.05):
			kit.prism([(-0.25, 0), (0.25, 0), (0.25, 0.15), (0.08, 0.35), (0.08, 0.8), (-0.08, 0.8), (-0.08, 0.35), (-0.25, 0.15)], 1.5, (0, 0, 0), "hazard_red", "barrier", axis="x", rot=(0, 0, 0))
	elif what == "concrete":
		kit.prism([(-0.3, 0), (0.3, 0), (0.3, 0.08), (0.12, 0.3), (0.08, 0.8), (-0.08, 0.8), (-0.12, 0.3), (-0.3, 0.08)], 3.0, (0, 0, 0), "concrete", "barrier", axis="x")
	elif what == "pedestrian":
		kit.frame(2.0, 1.0, 0.03, 0.03, at=(0, 0, 0.05), slot="hivis_orange", name="frame")
		kit.grid_bars(1.94, 0.9, (0, 0, 0.55), 14, 0, 0.008, "hivis_orange", "bars")
		for s in (-1, 1):
			kit.box((0.05, 0.5, 0.05), (s * 0.9, 0, 0.025), "plastic_black", "foot")
	elif what == "edge":
		for s in (-1, 1):
			kit.rod((s * 1.2, 0, 0), (s * 1.2, 0, 1.2), 0.024, "steel_galvanised", "post")
		for z in (0.55, 1.1):
			kit.rod((-1.3, 0, z), (1.3, 0, z), 0.024, "steel_galvanised", "rail")
		kit.box((2.6, 0.03, 0.15), (0, 0.03, 0.075), "softwood", "toe_board")
	elif what == "debris_net":
		kit.box((2.4, 0.005, 2.0), (0, 0, 1.0), "plastic_green", "netting")
	elif what == "sign":
		kit.frame(0.6, 0.9, 0.025, 0.5, at=(0, 0, 0), slot="steel_galvanised", name="frame", bottom=True)
		kit.prism([(-0.35, 0), (0.35, 0), (0, 0.6)], 0.01, (0, 0.2, 0.45), "hazard_red", "sign", axis="y")
		kit.prism([(-0.25, 0.06), (0.25, 0.06), (0, 0.49)], 0.012, (0, 0.2, 0.45), "paint_white", "sign_face", axis="y")
		kit.rounded_box((0.5, 0.3, 0.1), (0, 0, 0.05), "fabric_grey", "sandbag", radius=0.04)


def temp_works(what="acrow"):
	if what == "acrow":
		kit.box((0.15, 0.15, 0.006), (0, 0, 0.003), "hazard_red", "base_plate")
		kit.tube(0.03, 1.7, (0, 0, 0.85), "hazard_red", "outer")
		kit.tube(0.024, 1.3, (0, 0, 2.0), "hazard_red", "inner")
		kit.cyl(0.04, 0.08, (0, 0, 1.7), "steel_galvanised", "collar", segs=10)
		kit.rod((-0.1, 0, 1.7), (0.1, 0, 1.7), 0.008, "steel_galvanised", "handle", segs=6)
		kit.box((0.15, 0.15, 0.006), (0, 0, 2.65), "hazard_red", "head_plate")
		kit.socket("head", (0, 0, 2.653))
	elif what == "trench_box":
		for s in (-1, 1):
			with kit.hollow(0.2):
				kit.box((0.1, 3.0, 2.0), (s * 0.6, 0, 1.0), "steel_painted", "panel")
		for y in (-1.1, 1.1):
			for z in (0.5, 1.5):
				kit.rod((-0.55, y, z), (0.55, y, z), 0.05, "plant_yellow", "strut")
	elif what == "formwork":
		kit.box((1.2, 0.018, 2.7), (0, 0, 1.35), "plywood", "face")
		kit.frame(1.2, 2.7, 0.06, 0.1, at=(0, -0.059, 0), slot="plant_yellow", name="frame")
		for z in (0.7, 1.35, 2.0):
			kit.box((1.2, 0.1, 0.06), (0, -0.059, z), "plant_yellow", "waler")
		kit.strut((0, -0.1, 2.0), (0, -1.5, 0), 0.05, 0.05, "steel_galvanised", "push_pull_prop")
	elif what == "table_form":
		kit.box((2.4, 4.8, 0.02), (0, 0, 2.6), "plywood", "deck")
		for y in (-1.8, -0.6, 0.6, 1.8):
			kit.box((2.4, 0.08, 0.2), (0, y, 2.49), "softwood", "joist")
		for x in (-0.9, 0.9):
			kit.box((0.1, 4.8, 0.16), (x, 0, 2.31), "aluminium", "primary")
			for y in (-1.8, 1.8):
				kit.rod((x, y, 0), (x, y, 2.23), 0.035, "steel_galvanised", "prop")
	elif what == "tower":
		for x in (-0.65, 0.65):
			for y in (-0.9, 0.9):
				kit.rod((x, y, 0.15), (x, y, 5.2), 0.025, "aluminium", "standard")
				kit.cyl(0.1, 0.05, (x, y, 0.1), "rubber", "castor", axis="x", segs=10)
		for z in range(1, 10):
			for y in (-0.9, 0.9):
				kit.rod((-0.65, y, z * 0.5), (0.65, y, z * 0.5), 0.02, "aluminium", "rung")
		for z in (2.0, 4.0):
			kit.box((1.3, 1.8, 0.04), (0, 0, z), "plywood", "platform")
		for s in (-1, 1):
			kit.rod((s * 0.65, -0.9, 0.5), (s * 0.65, 0.9, 2.0), 0.015, "aluminium", "brace")
			kit.rod((s * 0.65, -0.9, 4.5), (s * 0.65, 0.9, 4.5), 0.02, "aluminium", "guardrail")
			kit.rod((s * 0.65, -0.9, 5.0), (s * 0.65, 0.9, 5.0), 0.02, "aluminium", "guardrail")
	elif what == "chute":
		for i in range(8):
			with kit.hollow(0.05):
				kit.lathe([(0.2, 0), (0.28, 1.1)], (0, 0, i * 1.0), "plant_yellow", "section", segs=14)
		kit.frame(0.8, 0.4, 0.04, 0.04, at=(0, -0.3, 8.0), slot="steel_galvanised", name="hanger")
	elif what == "hoist":
		kit.lattice(12.0, 0.6, 0.05, 0.025, at=(0, 0, 0), bays=16, slot="steel_galvanised", name="mast")
		with kit.hollow(0.05):
			kit.box((1.5, 1.6, 2.2), (0, 1.15, 5.0), "plant_yellow", "cage")
		kit.grid_bars(1.5, 2.2, (0, 1.96, 5.0), 10, 6, 0.006, "steel_galvanised", "cage_mesh")
		kit.box((2.0, 2.4, 0.3), (0, 0.8, 0.15), "steel_painted", "base")
	elif what == "ladder":
		for s in (-1, 1):
			kit.strut((s * 0.2, 0, 0), (s * 0.2, -1.2, 4.5), 0.025, 0.07, "aluminium", "stile")
		for i in range(1, 16):
			f = i / 16
			kit.rod((-0.2, -1.2 * f, 4.5 * f), (0.2, -1.2 * f, 4.5 * f), 0.014, "aluminium", "rung", segs=6)
	elif what == "steps":
		for s in (-1, 1):
			kit.strut((s * 0.28, 0.5, 0), (s * 0.2, 0, 1.8), 0.025, 0.07, "aluminium", "stile")
			kit.strut((s * 0.28, -0.6, 0), (s * 0.2, 0, 1.8), 0.025, 0.04, "aluminium", "back_leg")
		for i in range(1, 7):
			f = i / 7
			kit.box((0.42 + 0.12 * (1 - f), 0.09, 0.025), (0, 0.5 * (1 - f), 1.8 * f), "aluminium", "tread")
		kit.box((0.42, 0.25, 0.03), (0, 0, 1.8), "plastic_yellow", "top")
	elif what == "needle":
		kit.i_section(0.15, 0.2, 0.012, 0.008, 2.4, (0, 0, 2.5), "steel_painted", "needle_beam", axis="y")
		for y in (-0.9, 0.9):
			kit.tube(0.03, 2.4, (0, y, 1.2), "hazard_red", "prop")
			kit.box((0.2, 0.2, 0.01), (0, y, 0.005), "hazard_red", "base")
	elif what == "raking_shore":
		kit.box((0.25, 0.08, 4.5), (0, 0.04, 2.25), "softwood", "wall_plate")
		for z in (4.0, 2.6):
			kit.strut((0, 0.08, z), (0, 2.6, 0.2), 0.2, 0.2, "softwood", "raker")
		kit.box((0.3, 1.2, 0.2), (0, 2.6, 0.1), "softwood", "sole_plate")
		kit.strut((0, 0.1, 0.5), (0, 1.6, 1.0), 0.05, 0.2, "softwood", "tie")


def stack(what="bricks"):
	def pallet(z=0.0):
		for y in (-0.45, 0, 0.45):
			kit.box((1.2, 0.1, 0.1), (0, y, z + 0.05), "softwood", "bearer")
		for i in range(7):
			kit.box((0.1, 1.0, 0.022), (-0.55 + i * 0.183, 0, z + 0.111), "softwood", "board")
	if what == "pallet":
		pallet()
	elif what == "pallets":
		for i in range(8):
			pallet(i * 0.125)
	elif what in ("bricks", "blocks"):
		pallet()
		slot = "brick" if what == "bricks" else "blockwork"
		n = 6 if what == "bricks" else 4
		for i in range(n):
			kit.box((1.1 - 0.01 * (i % 2), 0.95, 1.0 / n - 0.01), (0, 0, 0.13 + (i + 0.5) / n), slot, "pack")
		for x in (-0.3, 0.3):
			kit.box((0.02, 0.96, 1.01), (x, 0, 0.63), "plastic_blue", "band")
	elif what == "bags":
		pallet()
		for i in range(6):
			for j in range(2):
				for k in range(2 if i % 2 else 3):
					if i % 2:
						kit.rounded_box((0.55, 0.45, 0.12), (-0.28 + j * 0.56, -0.23 + k * 0.46, 0.2 + i * 0.125), "fabric_grey", "bag", radius=0.04)
					else:
						kit.rounded_box((0.38, 0.47, 0.12), (-0.4 + k * 0.4, -0.24 + j * 0.48, 0.2 + i * 0.125), "fabric_grey", "bag", radius=0.04)
	elif what == "bulk_bag":
		kit.rounded_box((0.9, 0.9, 0.9), (0, 0, 0.45), "fabric_white", "bag", radius=0.08)
		kit.box((0.75, 0.75, 0.02), (0, 0, 0.9), "render", "sand")
		for sx in (-1, 1):
			for sy in (-1, 1):
				kit.sweep([(sx * 0.4, sy * 0.4, 0.88), (sx * 0.42, sy * 0.42, 1.1), (sx * 0.3, sy * 0.3, 1.0)], kit.rect(0.05, 0.005), "fabric_white", "loop")
	elif what == "timber":
		for y in (-1.5, 0, 1.5):
			kit.box((1.1, 0.075, 0.075), (0, y, 0.0375), "softwood", "bearer")
		for i in range(5):
			for j in range(6):
				kit.box((0.17, 4.8, 0.045), (-0.45 + j * 0.18, 0, 0.1 + i * 0.05), "softwood", "plank")
	elif what == "sheets":
		for y in (-0.9, 0, 0.9):
			kit.box((1.2, 0.075, 0.075), (0, y, 0.0375), "softwood", "bearer")
		kit.box((1.22, 2.44, 0.6), (0, 0, 0.375), "plywood", "sheets")
	elif what == "plasterboard":
		for y in (-0.9, 0, 0.9):
			kit.box((1.2, 0.075, 0.075), (0, y, 0.0375), "softwood", "bearer")
		kit.box((1.2, 2.4, 0.75), (0, 0, 0.45), "plasterboard", "boards")
	elif what in ("pipes", "rebar", "tubes"):
		r = {"pipes": 0.08, "rebar": 0.012, "tubes": 0.024}[what]
		slot = {"pipes": "plastic_grey", "rebar": "steel_painted", "tubes": "steel_galvanised"}[what]
		l = 6.0
		rows = {"pipes": 3, "rebar": 4, "tubes": 5}[what]
		for y in (-l / 3, l / 3):
			kit.box((rows * r * 2.6 + 0.2, 0.075, 0.075), (0, y, 0.0375), "softwood", "bearer")
		for i in range(rows):
			for j in range(rows + 2 - i):
				kit.cyl(r, l, ((j - (rows + 1 - i) / 2) * r * 2.05, 0, 0.075 + r + i * r * 1.78), slot, "length", axis="y", segs=8 if what != "pipes" else 14)
	elif what == "steel":
		for y in (-2.0, 2.0):
			kit.box((1.2, 0.1, 0.1), (0, y, 0.05), "softwood", "bearer")
		for i in range(2):
			for j in range(3):
				kit.i_section(0.17, 0.36, 0.013, 0.008, 6.0, (-0.4 + j * 0.4, 0, 0.28 + i * 0.46), "steel_painted", "beam", axis="y")
			if i == 0:
				for y in (-2.0, 2.0):
					kit.box((1.2, 0.1, 0.1), (0, y, 0.51), "softwood", "bearer")
	elif what == "cable_drum":
		for s in (-1, 1):
			kit.cyl(0.6, 0.05, (s * 0.35, 0, 0.6), "softwood", "flange", axis="x", segs=24)
		kit.cyl(0.4, 0.65, (0, 0, 0.6), "plastic_black", "cable", axis="x", segs=20)
	elif what == "gas_bottles":
		with kit.hollow(0.05):
			for i, c in enumerate(("hazard_red", "plastic_black", "hazard_red", "plastic_blue")):
				kit.lathe([(0.11, 0), (0.115, 0.03), (0.115, 1.2), (0.04, 1.35), (0.04, 1.42)], ((i % 2) * 0.25 - 0.125, (i // 2) * 0.25 - 0.125, 0.05), c, "cylinder", segs=14)
		kit.frame(0.6, 1.0, 0.03, 0.6, at=(0, 0, 0), slot="steel_galvanised", name="cage")
	elif what == "spoil":
		kit.lathe([(2.4, 0), (1.6, 0.7), (0.6, 1.3), (0.05, 1.5)], (0, 0, 0), "soil", "heap", segs=14, scale=(1, 0.8, 1))
	elif what == "sand":
		kit.lathe([(1.6, 0), (1.0, 0.5), (0.3, 0.9), (0.03, 1.0)], (0, 0, 0), "render", "heap", segs=14)
	elif what == "gravel":
		kit.lathe([(2.0, 0), (1.3, 0.6), (0.4, 1.1), (0.04, 1.2)], (0, 0, 0), "concrete", "heap", segs=14)


def tool(what="wheelbarrow"):
	if what == "wheelbarrow":
		with kit.hollow(0.05):
			kit.prism([(-0.3, 0.3), (0.3, 0.3), (0.45, 0.6), (-0.45, 0.6)], 0.6, (0, 0.1, 0), "plastic_green", "tray", axis="y")
		kit.wheel(0.18, 0.08, (0, 0.6, 0.18))
		for s in (-1, 1):
			kit.rod((s * 0.08, 0.6, 0.18), (s * 0.3, -0.9, 0.55), 0.015, "steel_galvanised", "handle")
			kit.rod((s * 0.25, -0.3, 0.32), (s * 0.25, -0.3, 0), 0.012, "steel_galvanised", "leg")
	elif what == "breaker":
		kit.rounded_box((0.14, 0.14, 0.5), (0, 0, 0.75), "plant_yellow", "body", radius=0.03)
		kit.rod((-0.2, 0, 1.0), (0.2, 0, 1.0), 0.018, "plastic_black", "handles")
		kit.cyl(0.018, 0.5, (0, 0, 0.25), "steel_stainless", "chisel", segs=8, r2=0.006)
	elif what == "saw":
		kit.rounded_box((0.25, 0.4, 0.25), (0, -0.2, 0.2), "hivis_orange", "engine", radius=0.04)
		kit.cyl(0.175, 0.006, (0.06, 0.25, 0.2), "steel_stainless", "disc", axis="x", segs=24)
		kit.sweep([(0, -0.35, 0.3), (0, -0.2, 0.4), (0, 0.0, 0.35)], kit.circle(0.015, 6), "plastic_black", "handle")
	elif what == "drill":
		kit.rounded_box((0.07, 0.25, 0.08), (0, 0, 0.2), "plastic_blue", "body", radius=0.02)
		kit.box((0.05, 0.06, 0.16), (0, -0.07, 0.1), "plastic_black", "grip")
		kit.box((0.08, 0.12, 0.05), (0, -0.07, 0.025), "plastic_black", "battery")
		kit.cyl(0.006, 0.12, (0, 0.18, 0.2), "steel_stainless", "bit", axis="y", segs=6)
	elif what in ("shovel", "pick", "sledge", "broom"):
		kit.rod((0, 0, 0.1), (0, 0, 1.2 if what != "broom" else 1.4), 0.018, "softwood", "shaft", segs=8)
		if what == "shovel":
			kit.box((0.22, 0.01, 0.3), (0, 0, 0.0), "steel_painted", "blade", rot=(8, 0, 0))
		elif what == "pick":
			kit.sweep([(-0.3, 0, 1.1), (0, 0, 1.2), (0.3, 0, 1.1)], kit.rect(0.03, 0.03), "steel_painted", "head", up=(0, 1, 0))
		elif what == "sledge":
			kit.box((0.18, 0.07, 0.07), (0, 0, 1.2), "steel_painted", "head")
		else:
			kit.box((0.6, 0.07, 0.05), (0, 0, 0.1), "softwood", "head")
			kit.box((0.58, 0.05, 0.08), (0, 0, 0.04), "plastic_red", "bristles")
	elif what == "toolbox":
		kit.rounded_box((0.55, 0.25, 0.25), (0, 0, 0.125), "plastic_red", "box", radius=0.02)
		kit.sweep([(-0.12, 0, 0.25), (-0.12, 0, 0.3), (0.12, 0, 0.3), (0.12, 0, 0.25)], kit.circle(0.008, 6), "plastic_black", "handle", up=(0, 1, 0))
	elif what == "bucket":
		with kit.hollow(0.05):
			kit.lathe([(0.11, 0), (0.15, 0.28)], (0, 0, 0), "plastic_black", "bucket", segs=16)
	elif what == "hard_hat":
		kit.lathe([(0.13, 0), (0.125, 0.06), (0.09, 0.12), (0.02, 0.15)], (0, 0, 0), "plastic_yellow", "shell", segs=16, scale=(0.85, 1, 1))
		kit.box((0.2, 0.06, 0.01), (0, 0.14, 0.005), "plastic_yellow", "peak")
	elif what == "level":
		kit.box((1.2, 0.025, 0.06), (0, 0, 0.03), "plastic_yellow", "level")
	elif what == "trestles":
		for y in (-0.8, 0.8):
			for s in (-1, 1):
				kit.strut((s * 0.35, y - 0.2, 0), (s * 0.3, y, 0.75), 0.04, 0.04, "softwood", "leg")
				kit.strut((s * 0.35, y + 0.2, 0), (s * 0.3, y, 0.75), 0.04, 0.04, "softwood", "leg")
			kit.box((0.8, 0.07, 0.07), (0, y, 0.75), "softwood", "top_rail")
		kit.box((0.7, 2.4, 0.04), (0, 0, 0.81), "softwood", "boards")
	elif what == "theodolite":
		for i in range(3):
			a = math.radians(120 * i + 90)
			kit.rod((0.5 * math.cos(a), 0.5 * math.sin(a), 0), (0, 0, 1.4), 0.015, "softwood", "leg", segs=6)
		kit.rounded_box((0.16, 0.14, 0.22), (0, 0, 1.52), "plastic_yellow", "instrument", radius=0.02)
		kit.cyl(0.025, 0.16, (0, 0, 1.55), "plastic_black", "telescope", axis="y", segs=10)


def crane_luffing(height=45.0):
	tower_crane(height=height, jib=30.0, counter=8.0)


_ITEMS = [
	("excavator.mini", excavator, "Mini excavator, 1.5 t", dict(s=0.4)),
	("excavator.midi", excavator, "Excavator, 8 t", dict(s=0.7)),
	("excavator.20t", excavator, "Excavator, 20 t", dict()),
	("excavator.45t", excavator, "Excavator, 45 t", dict(s=1.35)),
	("excavator.breaker", excavator, "Excavator with breaker", dict(tool="breaker"), "demolition"),
	("excavator.grapple", excavator, "Excavator with sorting grapple", dict(tool="grapple"), "demolition"),
	("excavator.shears", excavator, "Excavator with demolition shears", dict(tool="shears"), "demolition"),
	("excavator.high_reach", excavator, "High-reach demolition excavator", dict(s=1.35, tool="shears", reach=2.2), "demolition"),
	("earthmoving.bulldozer", bulldozer, "Bulldozer", dict()),
	("earthmoving.wheel_loader", loader, "Wheel loader", dict()),
	("earthmoving.backhoe_loader", loader, "Backhoe loader", dict(backhoe=True)),
	("earthmoving.site_dumper", dumper, "Site dumper, 6 t", dict()),
	("earthmoving.small_dumper", dumper, "Site dumper, 1 t", dict(s=0.6)),
	("earthmoving.artic_dumper", dumper, "Articulated dump truck", dict(artic=True)),
	("earthmoving.roller", roller, "Tandem roller", dict()),
	("earthmoving.pedestrian_roller", roller, "Pedestrian roller", dict(pedestrian=True)),
	("lifting.telehandler", loader, "Telehandler", dict(telehandler=True)),
	("lifting.forklift", forklift, "Forklift", dict()),
	("lifting.mobile_crane", mobile_crane, "Mobile crane, 60 t", dict()),
	("lifting.crawler_crane", mobile_crane, "Crawler crane with lattice boom", dict(crawler=True)),
	("lifting.goods_hoist", temp_works, "Goods hoist, 12 m", dict(what="hoist")),
	("access.scissor_lift_6", scissor_lift, "Scissor lift, 6 m", dict()),
	("access.scissor_lift_10", scissor_lift, "Scissor lift, 10 m", dict(h=10.0)),
	("access.boom_lift_16", boom_lift, "Boom lift, 16 m", dict()),
	("access.boom_lift_26", boom_lift, "Boom lift, 26 m", dict(h=26.0)),
	("access.tower", temp_works, "Mobile access tower", dict(what="tower")),
	("access.ladder", temp_works, "Extension ladder", dict(what="ladder")),
	("access.step_ladder", temp_works, "Step ladder", dict(what="steps")),
	("access.trestles", tool, "Trestles and boards", dict(what="trestles")),
	("truck.tipper", tipper_truck, "Tipper lorry", dict()),
	("truck.concrete_mixer", mixer_truck, "Concrete mixer lorry", dict()),
	("truck.concrete_pump", concrete_pump, "Concrete pump with boom", dict()),
	("truck.low_loader", low_loader, "Low loader", dict()),
	("piling.rig", piling_rig, "Piling rig, continuous flight auger", dict()),
	("small.cement_mixer", small_plant, "Cement mixer", dict(what="mixer")),
	("small.generator", small_plant, "Towable generator", dict(what="generator")),
	("small.compressor", small_plant, "Towable compressor", dict(what="compressor")),
	("small.pump", small_plant, "Dewatering pump", dict(what="pump")),
	("small.lighting_tower", small_plant, "Lighting tower", dict(what="lighting_tower")),
	("small.plate_compactor", small_plant, "Plate compactor", dict(what="plate")),
	("small.water_bowser", small_plant, "Water bowser", dict(what="bowser")),
	("small.fuel_tank", small_plant, "Bunded fuel tank", dict(what="fuel_tank")),
	("cabin.toilet", welfare, "Portable toilet", dict()),
	("cabin.welfare", welfare, "Welfare cabin", dict(what="welfare")),
	("cabin.double_stack", welfare, "Site offices, double stacked with stair", dict(what="double")),
	("cabin.store", welfare, "Secure store container", dict(what="store")),
	("cabin.container_20", welfare, "Shipping container, 20 ft", dict(what="container_20")),
	("cabin.container_40", welfare, "Shipping container, 40 ft", dict(what="container_40")),
	("cabin.silo", silo, "Mortar silo", dict()),
	("fence.hoarding_post", hoarding_post, "Hoarding post with raker", dict(), "temporary"),
	("fence.site_gate", site_gate, "Site gates, 6 m", dict(), "temporary"),
	("fence.water_barrier", barrier, "Water-filled barrier", dict(), "temporary"),
	("fence.concrete_barrier", barrier, "Concrete barrier, 3 m", dict(what="concrete"), "temporary"),
	("fence.pedestrian_barrier", barrier, "Pedestrian barrier", dict(what="pedestrian"), "temporary"),
	("fence.edge_protection", barrier, "Edge protection bay", dict(what="edge"), "temporary"),
	("fence.debris_net", barrier, "Debris netting panel", dict(what="debris_net"), "temporary"),
	("fence.road_sign", barrier, "Road works sign", dict(what="sign"), "temporary"),
	("temporary.acrow_prop", temp_works, "Adjustable steel prop", dict(what="acrow"), "temporary"),
	("temporary.needle_and_props", temp_works, "Needle beam on props", dict(what="needle"), "temporary"),
	("temporary.raking_shore", temp_works, "Raking shore", dict(what="raking_shore"), "temporary"),
	("temporary.trench_box", temp_works, "Trench box", dict(what="trench_box"), "temporary"),
	("temporary.formwork_panel", temp_works, "Wall formwork panel", dict(what="formwork"), "temporary"),
	("temporary.table_form", temp_works, "Slab table form", dict(what="table_form"), "temporary"),
	("temporary.rubble_chute", temp_works, "Rubble chute, 8 m", dict(what="chute"), "temporary", "demolition"),
	("crane.tower_45", tower_crane, "Tower crane, 45 m mast, 50 m jib", dict(height=45.0, jib=50.0, counter=15.0), "crane"),
	("crane.tower_60", tower_crane, "Tower crane, 60 m mast, 60 m jib", dict(height=60.0, jib=60.0, counter=18.0), "crane"),
	("crane.tower_city", crane_luffing, "Tower crane, 45 m mast, short jib", dict(), "crane"),
]
for _w in ("pallet", "pallets", "bricks", "blocks", "bags", "bulk_bag", "timber", "sheets", "plasterboard", "pipes", "rebar", "tubes", "steel", "cable_drum", "gas_bottles", "spoil", "sand", "gravel"):
	_ITEMS.append(("store." + _w, stack, {"pallet": "Pallet", "pallets": "Pallet stack", "bricks": "Brick pack", "blocks": "Block pack", "bags": "Cement bags on pallet",
		"bulk_bag": "Bulk bag of sand", "timber": "Timber stack", "sheets": "Plywood sheet stack", "plasterboard": "Plasterboard stack", "pipes": "Drainage pipe stack",
		"rebar": "Rebar bundle", "tubes": "Scaffold tube stack", "steel": "Steel beam stack", "cable_drum": "Cable drum", "gas_bottles": "Gas bottle cage",
		"spoil": "Spoil heap", "sand": "Sand heap", "gravel": "Gravel heap"}[_w], dict(what=_w), "materials"))
for _w, _l in (("wheelbarrow", "Wheelbarrow"), ("breaker", "Hand breaker"), ("saw", "Cut-off saw"), ("drill", "Cordless drill"), ("shovel", "Shovel"), ("pick", "Pickaxe"),
	("sledge", "Sledgehammer"), ("broom", "Broom"), ("toolbox", "Toolbox"), ("bucket", "Bucket"), ("hard_hat", "Hard hat"), ("level", "Spirit level"), ("theodolite", "Total station on tripod")):
	_ITEMS.append(("tool." + _w, tool, _l, dict(what=_w), "tools"))
for _it in _ITEMS:
	reg(_it[0], _it[1], _it[2], *_it[4:], **_it[3])
register("plant.fence.hoarding", hoarding, "Timber hoarding, per metre", family="plant", tags=("plant", "outdoor", "temporary"), stretch="x")
