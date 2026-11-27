"""Room contents for pubs, restaurants, hotels, theatres, cinemas, courts, prisons, stations,
shops, warehouses, lodges and mansions (the contract building types added 2026-11-27).
Origin: floor centre, back to -Y, front to +Y."""
import math

import kit
from recipes.fixtures import chair, legs, table
from recipes.furniture import carcass
from registry import register

OAK, DARK, BRASS, STEEL, BLACK, WHITE = "hardwood", "glulam", "brass", "steel_stainless", "plastic_black", "paint_white"
RED, GREEN, LEATHER = "fabric_red", "fabric_green", "leather_black"


def reg(id, fn, label, *tags, **params):
	register(id, fn, label, family="fixture", tags=(id.split(".")[0],) + tags, **params)


# --- shared parts ---------------------------------------------------------------------------

def counter(w, d=0.6, h=1.1, front=OAK, top=DARK, at=(0, 0), kick=True, name="counter"):
	"""A solid serving counter with an overhanging top."""
	x, y = at
	with kit.hollow(0.2):
		kit.box((w, d, h - 0.04), (x, y, (h - 0.04) / 2), front, name)
	kit.box((w + 0.04, d + 0.12, 0.04), (x, y + 0.03, h - 0.02), top, name + "_top")
	if kick:
		kit.box((w, 0.02, 0.1), (x, y + d / 2 + 0.006, 0.05), BLACK, "kick_plate")
	n = max(1, int(w / 0.6))
	for i in range(n):
		kit.box((w / n - 0.08, 0.012, h - 0.3), (x - w / 2 + w * (i + 0.5) / n, y + d / 2 + 0.006, (h + 0.1) / 2), front, "panel")


def bottles(x0, x1, y, z, n, h=0.28):
	for i in range(n):
		x = x0 + (x1 - x0) * (i + 0.5) / n
		slot = ("glass", "plastic_green", "glass_dark", "brass")[i % 4]
		kit.cyl(0.035, h * 0.65, (x, y, z + h * 0.325), slot, "bottle", segs=8)
		kit.cyl(0.013, h * 0.35, (x, y, z + h * 0.82), slot, "bottle_neck", segs=6)


def tip_seat(at=(0, 0), slot=RED, w=0.55, arms=True, down=False, left=True):
	"""One theatre or cinema seat: upholstered back, tip-up squab, arms."""
	x, y = at
	kit.rounded_box((w - 0.08, 0.1, 0.55), (x, y - 0.22, 0.72), slot, "seat_back", radius=0.04, rot=(-8, 0, 0), segments=2)
	if down:
		kit.rounded_box((w - 0.08, 0.45, 0.09), (x, y + 0.02, 0.43), slot, "squab", radius=0.035, segments=2)
	else:
		kit.rounded_box((w - 0.08, 0.09, 0.42), (x, y - 0.1, 0.56), slot, "squab", radius=0.035, rot=(12, 0, 0), segments=2)
	if arms:
		for sx in ((-1, 1) if left else (1,)):
			kit.box((0.05, 0.42, 0.6), (x + sx * w / 2, y - 0.05, 0.3), BLACK, "seat_standard")
			kit.box((0.07, 0.36, 0.035), (x + sx * w / 2, y - 0.03, 0.6175), DARK, "arm")


def seat_row(n, slot=RED, w=0.55, z=0.0, y=0.0, down=False):
	for i in range(n):
		tip_seat((-(n - 1) * w / 2 + i * w, y), slot, w, True, down, i == 0)


def lamp_shade(at, r=0.14, h=0.2, slot="fabric_white"):
	kit.lathe([(r * 0.6, h), (r, 0.0)], at, slot, "shade", segs=14)
	kit.sphere(0.04, (at[0], at[1], at[2] + h * 0.4), "glow", "bulb", segs=8)


def rope_post(at=(0, 0), h=0.95):
	kit.cyl(0.16, 0.03, (at[0], at[1], 0.015), BRASS, "post_base", segs=18)
	kit.rod((at[0], at[1], 0.03), (at[0], at[1], h), 0.022, BRASS, "post", segs=10)
	kit.sphere(0.04, (at[0], at[1], h + 0.02), BRASS, "post_ball", segs=10)


def rope(a, b, sag=0.18, slot=RED):
	pts = []
	for i in range(9):
		t = i / 8
		pts.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] - sag * 4 * t * (1 - t)))
	kit.sweep(pts, kit.circle(0.018, 8), slot, "rope")


def turned_leg(at, h, r=0.045, slot=DARK):
	kit.lathe([(r * 0.7, 0), (r, h * 0.1), (r * 0.55, h * 0.3), (r, h * 0.6), (r * 0.8, h * 0.85), (r, h)], at, slot, "turned_leg", segs=10)


# --- pub and bar ----------------------------------------------------------------------------

def pub(what="bar_counter", w=2.4):
	if what == "bar_counter":
		with kit.stage("counter"):
			counter(w, 0.65, 1.1)
			kit.rod((-w / 2 + 0.05, 0.42, 0.2), (w / 2 - 0.05, 0.42, 0.2), 0.02, BRASS, "foot_rail", segs=8)
			for i in range(max(2, int(w / 1.1) + 1)):
				x = -w / 2 + 0.1 + (w - 0.2) * i / max(1, int(w / 1.1))
				kit.rod((x, 0.33, 0.2), (x, 0.42, 0.2), 0.012, BRASS, "rail_bracket", segs=6)
		with kit.stage("fittings"):
			for i in range(max(1, int(w / 1.2))):
				x = -w / 2 + w * (i + 0.5) / max(1, int(w / 1.2))
				kit.box((0.5, 0.16, 0.03), (x, -0.1, 1.115), DARK, "pump_base")
				for k in (-1, 0, 1):
					kit.lathe([(0.02, 0), (0.028, 0.1), (0.018, 0.2), (0.03, 0.36)], (x + k * 0.16, -0.1, 1.13), ("hardwood", "ceramic", "plastic_black")[k + 1], "hand_pull", segs=10, rot=(-12, 0, 0))
					kit.box((0.08, 0.01, 0.11), (x + k * 0.16, -0.01, 1.2), ("plastic_red", "plastic_green", "plastic_yellow")[k + 1], "pump_clip")
				kit.box((0.6, 0.22, 0.012), (x, 0.2, 1.106), "rubber", "bar_mat")
	elif what == "back_bar":
		with kit.stage("carcass"):
			carcass(w, 0.5, 0.95, DARK, doors=max(2, int(w / 0.6)))
			kit.box((w, 0.3, 0.04), (0, -0.1, 2.3), DARK, "pelmet")
			for sx in (-1, 1):
				kit.box((0.06, 0.3, 1.35), (sx * (w / 2 - 0.03), -0.1, 1.625), DARK, "upright")
			kit.box((w - 0.12, 0.012, 1.3), (0, -0.24, 1.62), "mirror", "back_mirror")
		with kit.stage("stock"):
			for z in (1.35, 1.75):
				kit.box((w - 0.12, 0.2, 0.025), (0, -0.12, z), "glass", "shelf")
				bottles(-w / 2 + 0.1, w / 2 - 0.1, -0.12, z + 0.013, int(w / 0.11))
			bottles(-w / 2 + 0.1, w / 2 - 0.1, -0.1, 0.955, int(w / 0.14), 0.3)
			for i in range(max(2, int(w / 0.5))):
				x = -w / 2 + 0.3 + i * 0.45
				if x < w / 2 - 0.2:
					kit.cyl(0.03, 0.09, (x, 0.12, 2.2), "glass", "optic", segs=8)
	elif what == "bottle_fridge":
		with kit.stage("main"):
			with kit.hollow(0.3):
				kit.box((0.9, 0.5, 0.88), (0, 0, 0.44), BLACK, "cabinet")
			for sx in (-1, 1):
				kit.box((0.42, 0.015, 0.74), (sx * 0.22, 0.255, 0.47), "glass", "door")
				kit.box((0.02, 0.03, 0.4), (sx * 0.04, 0.27, 0.5), STEEL, "handle")
			for z in (0.2, 0.5):
				bottles(-0.4, 0.4, 0.12, z, 8, 0.22)
	elif what in ("keg", "cask"):
		with kit.stage("main"), kit.hollow(0.9):
			if what == "keg":
				kit.lathe([(0.19, 0), (0.2, 0.02), (0.2, 0.2), (0.21, 0.22), (0.2, 0.24), (0.2, 0.42), (0.21, 0.44), (0.2, 0.46), (0.2, 0.6), (0.17, 0.62)], (0, 0, 0), "aluminium", "keg", segs=18)
			else:
				kit.lathe([(0.19, -0.33), (0.24, -0.15), (0.26, 0), (0.24, 0.15), (0.19, 0.33)], (0, 0, 0.3), OAK, "cask", segs=18, rot=(-90, 0, 0))
				for y in (-0.22, 0.22):
					kit.tube(0.232, 0.04, (0, y, 0.3), "cast_iron", "hoop", axis="y", wall=0.006, segs=18)
				for sx in (-1, 1):
					kit.prism([(0, 0), (0.3, 0), (0.2, 0.1), (0.1, 0.1)], 0.5, (sx * 0.1 - 0.15, 0, 0), OAK, "stillage", axis="y")
	elif what == "table":
		with kit.stage("main"):
			kit.cyl(0.38, 0.035, (0, 0, 0.735), DARK, "top", segs=24)
			kit.lathe([(0.24, 0), (0.2, 0.03), (0.05, 0.08), (0.04, 0.68), (0.12, 0.72)], (0, 0, 0), "cast_iron", "pedestal", segs=14)
	elif what == "stool":
		with kit.stage("main"):
			kit.cyl(0.17, 0.06, (0, 0, 0.45), RED, "pad", segs=16)
			kit.cyl(0.18, 0.02, (0, 0, 0.41), DARK, "seat", segs=16)
			for a in (45, 135, 225, 315):
				c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
				kit.rod((0.1 * c, 0.1 * s, 0.4), (0.17 * c, 0.17 * s, 0), 0.016, DARK, "leg", segs=6)
			kit.tube(0.13, 0.015, (0, 0, 0.18), DARK, "stretcher", wall=0.012, segs=14)
	elif what == "booth":
		with kit.stage("seats"):
			for sy in (-1, 1):
				with kit.hollow(0.3):
					kit.box((1.3, 0.5, 0.42), (0, sy * 0.72, 0.21), DARK, "seat_base")
					kit.box((1.3, 0.1, 1.2), (0, sy * 1.02, 0.6), DARK, "back_panel")
				kit.rounded_box((1.26, 0.48, 0.1), (0, sy * 0.72, 0.47), RED, "squab", radius=0.04)
				kit.rounded_box((1.26, 0.1, 0.6), (0, sy * 0.93, 0.82), RED, "back_pad", radius=0.04)
		with kit.stage("table"):
			kit.box((1.2, 0.7, 0.04), (0, 0, 0.74), DARK, "top")
			kit.lathe([(0.22, 0), (0.05, 0.06), (0.04, 0.7), (0.1, 0.72)], (0, 0, 0), "cast_iron", "pedestal", segs=12)
	elif what == "fruit_machine":
		with kit.stage("main"):
			with kit.hollow(0.3):
				kit.box((0.65, 0.6, 1.0), (0, 0, 0.5), BLACK, "base")
				kit.prism([(-0.3, 1.0), (0.3, 1.0), (0.3, 1.2), (0.1, 1.85), (-0.3, 1.85)], 0.65, (0, 0, 0), BLACK, "head", axis="x")
			kit.box((0.55, 0.012, 0.5), (0, 0.19, 1.52), "screen", "reels", rot=(-17, 0, 0))
			kit.box((0.55, 0.01, 0.2), (0, 0.302, 1.1), "glow", "buttons_panel")
			kit.box((0.55, 0.01, 0.4), (0, 0.302, 0.6), "plastic_red", "art_panel")
			kit.box((0.2, 0.05, 0.06), (0, 0.31, 0.25), STEEL, "coin_tray")
	elif what == "dartboard":
		with kit.stage("main"):
			kit.box((0.9, 0.06, 0.9), (0, 0, 1.73), DARK, "cabinet")
			kit.cyl(0.225, 0.04, (0, 0.04, 1.73), BLACK, "board", axis="y", segs=24)
			kit.tube(0.17, 0.045, (0, 0.04, 1.73), "plastic_red", "treble_ring", axis="y", wall=0.01, segs=24)
			kit.cyl(0.02, 0.05, (0, 0.04, 1.73), "plastic_red", "bull", axis="y", segs=8)
			for sx in (-1, 1):
				kit.box((0.44, 0.03, 0.9), (sx * 0.67, 0.0, 1.73), DARK, "door")
				kit.box((0.36, 0.006, 0.6), (sx * 0.67, 0.018, 1.75), "slate", "scoreboard")
	elif what in ("pool_table", "snooker_table"):
		l, wd = (2.1, 1.2) if what == "pool_table" else (3.8, 2.0)
		with kit.stage("main"):
			with kit.hollow(0.5):
				kit.box((wd, l, 0.28), (0, 0, 0.7), DARK, "body")
			kit.box((wd - 0.2, l - 0.2, 0.012), (0, 0, 0.846), "fabric_green" if what == "snooker_table" else "fabric_blue", "cloth")
			for sx in (-1, 1):
				kit.box((0.1, l, 0.06), (sx * (wd / 2 - 0.05), 0, 0.86), DARK, "rail")
				kit.box((wd, 0.1, 0.06), (0, sx * (l / 2 - 0.05), 0.86), DARK, "rail")
				for sy in (-1, 0, 1):
					kit.cyl(0.055, 0.02, (sx * (wd / 2 - 0.1), sy * (l / 2 - 0.1), 0.882), BLACK, "pocket", segs=10)
				for sy in (-1, 1):
					turned_leg((sx * (wd / 2 - 0.15), sy * (l / 2 - 0.15), 0), 0.56, 0.07)
			for i in range(6):
				kit.sphere(0.028, (-0.1 + 0.05 * (i % 3), l * 0.2 + 0.05 * (i // 3), 0.88), ("plastic_red", "plastic_yellow")[i % 2], "ball", segs=8)
			kit.rod((0.2, -l * 0.3, 0.866), (0.35, l * 0.25, 0.866), 0.012, OAK, "cue", segs=6)
	elif what == "jukebox":
		with kit.stage("main"):
			with kit.hollow(0.3):
				kit.prism([(-0.4, 0), (0.4, 0), (0.4, 1.0)] + [(0.4 * math.cos(math.radians(a)), 1.0 + 0.4 * math.sin(math.radians(a))) for a in range(15, 180, 15)] + [(-0.4, 1.0)], 0.55, (0, 0, 0), DARK, "cabinet", axis="y")
			kit.box((0.62, 0.012, 0.4), (0, 0.276, 1.05), "glow", "window")
			kit.box((0.62, 0.012, 0.45), (0, 0.276, 0.45), BRASS, "grille")
			for sx in (-1, 1):
				kit.box((0.05, 0.02, 1.0), (sx * 0.35, 0.28, 0.55), "plastic_red", "light_tube")
	elif what == "fireplace":
		with kit.stage("main"):
			with kit.hollow(0.6):
				kit.box((1.8, 0.45, 1.25), (0, 0, 0.625), "brick", "breast")
			kit.box((0.9, 0.2, 0.8), (0, 0.14, 0.4), BLACK, "opening")
			kit.box((2.0, 0.3, 0.07), (0, 0.1, 1.28), DARK, "mantel")
			kit.box((1.6, 0.5, 0.05), (0, 0.4, 0.025), "slate", "hearth")
			for i in range(3):
				kit.rod((-0.3, 0.15 + i * 0.03, 0.12 + i * 0.07), (0.3, 0.2 - i * 0.03, 0.12 + i * 0.07), 0.05, "bark", "log", segs=8)
			kit.box((0.5, 0.06, 0.22), (0, 0.16, 0.3), "glow", "embers")
	elif what == "sign":
		with kit.stage("main"):
			kit.box((0.14, 0.14, 4.2), (0, 0, 2.1), DARK, "post")
			kit.box((1.3, 0.1, 0.1), (0.6, 0, 4.0), DARK, "arm")
			kit.strut((0.1, 0, 3.3), (0.9, 0, 3.95), 0.06, 0.06, DARK, "brace")
			kit.box((0.95, 0.06, 1.2), (0.75, 0, 3.25), "plastic_green", "sign_board")
			kit.box((0.8, 0.07, 0.75), (0.75, 0, 3.35), "paint_white", "sign_picture")
			kit.box((0.8, 0.07, 0.2), (0.75, 0, 2.8), BRASS, "sign_name")
			for dx in (0.4, 1.1):
				kit.rod((dx, 0, 3.95), (dx, 0, 3.85), 0.01, "cast_iron", "hook", segs=5)
	elif what == "picnic_bench":
		with kit.stage("main"):
			for i in range(5):
				kit.box((1.8, 0.14, 0.04), (0, -0.3 + i * 0.15, 0.74), "softwood", "top_board")
			for sy in (-1, 1):
				for i in range(2):
					kit.box((1.8, 0.13, 0.04), (0, sy * (0.7 + i * 0.14), 0.44), "softwood", "seat_board")
			for sx in (-1, 1):
				kit.box((0.05, 1.7, 0.09), (sx * 0.7, 0, 0.39), "softwood", "seat_bearer")
				kit.box((0.05, 0.75, 0.09), (sx * 0.7, 0, 0.675), "softwood", "top_bearer")
				for sy in (-1, 1):
					kit.strut((sx * 0.7, sy * 0.6, 0), (sx * 0.7, sy * 0.25, 0.72), 0.05, 0.09, "softwood", "leg")


# --- restaurant and function room -----------------------------------------------------------

def place_setting(x, y, z, face=0.0):
	kit.cyl(0.13, 0.012, (x, y, z + 0.006), "ceramic", "plate", segs=14)
	c, s = math.cos(math.radians(face)), math.sin(math.radians(face))
	kit.cyl(0.035, 0.12, (x + 0.16 * c - 0.1 * s, y + 0.16 * s + 0.1 * c, z + 0.06), "glass", "glass", segs=8)


def dining(what="laid_table_4"):
	if what.startswith("laid_table_"):
		n = int(what.rsplit("_", 1)[1])
		w = {2: 0.75, 4: 1.25, 6: 1.9, 8: 2.5}[n]
		with kit.stage("table"):
			kit.box((w + 0.3, 1.1, 0.01), (0, 0, 0.752), "fabric_white", "cloth")
			for sy in (-1, 1):
				kit.box((w + 0.3, 0.01, 0.25), (0, sy * 0.55, 0.63), "fabric_white", "cloth_drop")
			for sx in (-1, 1):
				kit.box((0.01, 1.1, 0.25), (sx * (w / 2 + 0.15), 0, 0.63), "fabric_white", "cloth_drop")
			kit.box((w, 0.8, 0.03), (0, 0, 0.732), OAK, "top")
			legs(w, 0.8, 0.717, 0.05, OAK, inset=0.03)
		with kit.stage("chairs"):
			per = n // 2
			for i in range(per):
				x = -w / 2 + w * (i + 0.5) / per
				chair((x, 0.68), 180, RED, DARK)
				chair((x, -0.68), 0, RED, DARK)
		with kit.stage("setting"):
			per = n // 2
			for i in range(per):
				x = -w / 2 + w * (i + 0.5) / per
				place_setting(x, 0.33, 0.757, 180)
				place_setting(x, -0.33, 0.757, 0)
			kit.cyl(0.03, 0.2, (0, 0, 0.857), "glass", "vase", segs=8)
			kit.sphere(0.05, (0, 0, 0.99), "plastic_red", "flowers", segs=8)
	elif what == "banquet_round":
		with kit.stage("table"):
			kit.cyl(0.95, 0.03, (0, 0, 0.735), "plywood", "top", segs=32)
			kit.lathe([(0.96, 0.752), (0.98, 0.74), (1.0, 0.1)], (0, 0, 0), "fabric_white", "cloth", segs=32)
			kit.cyl(0.955, 0.008, (0, 0, 0.754), "fabric_white", "cloth_top", segs=32)
		with kit.stage("chairs"):
			for i in range(10):
				a = i * 36
				c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
				chair((1.3 * c, 1.3 * s), a + 90, "fabric_white", BRASS)
		with kit.stage("setting"):
			for i in range(10):
				a = i * 36
				place_setting(0.72 * math.cos(math.radians(a)), 0.72 * math.sin(math.radians(a)), 0.759, a + 90)
			kit.cyl(0.05, 0.45, (0, 0, 0.985), "glass", "centrepiece", segs=10)
			kit.sphere(0.16, (0, 0, 1.3), "foliage", "flowers", segs=10)
	elif what == "banquette":
		with kit.stage("main"):
			with kit.hollow(0.3):
				kit.box((2.4, 0.55, 0.42), (0, 0, 0.21), DARK, "base")
				kit.box((2.4, 0.08, 1.05), (0, -0.24, 0.525), DARK, "back_panel")
			kit.rounded_box((2.36, 0.5, 0.1), (0, 0.02, 0.47), LEATHER, "squab", radius=0.04)
			for i in range(4):
				kit.rounded_box((0.57, 0.1, 0.5), (-0.885 + i * 0.59, -0.16, 0.78), LEATHER, "back_pad", radius=0.04)
	elif what == "host_stand":
		with kit.stage("main"):
			with kit.hollow(0.2):
				kit.box((0.6, 0.45, 1.1), (0, 0, 0.55), DARK, "stand")
			kit.box((0.66, 0.5, 0.03), (0, 0.0, 1.13), DARK, "top", rot=(12, 0, 0))
			kit.box((0.3, 0.22, 0.02), (0, 0, 1.16), "paint_white", "book", rot=(12, 0, 0))
			kit.rod((0.2, -0.15, 1.1), (0.2, -0.15, 1.45), 0.008, BRASS, "lamp_stem", segs=6)
			kit.cyl(0.06, 0.05, (0.2, -0.1, 1.45), BRASS, "lamp_head", segs=10, rot=(40, 0, 0))
	elif what == "waiter_station":
		with kit.stage("main"):
			carcass(1.0, 0.5, 0.95, DARK, doors=2, drawers=0)
			kit.box((1.0, 0.25, 0.4), (0, -0.12, 1.17), DARK, "gallery")
			for i in range(3):
				kit.cyl(0.09, 0.14, (-0.3 + i * 0.3, 0.05, 1.02), ("ceramic", "steel_stainless", "ceramic")[i], "stack", segs=12)
			kit.box((0.3, 0.02, 0.24), (0.25, -0.2, 1.5), "screen", "till_screen")
	elif what == "buffet":
		with kit.stage("main"):
			counter(2.4, 0.75, 0.9, "laminate_white", STEEL, kick=False)
			for i in range(4):
				x = -0.9 + i * 0.6
				kit.box((0.5, 0.32, 0.12), (x, 0.0, 0.96), STEEL, "chafing_dish")
				kit.lathe([(0.25, 0), (0.2, 0.1), (0.05, 0.14)], (x, 0.0, 1.02), STEEL, "dish_lid", segs=12, scale=(1, 0.64, 1))
			kit.box((2.4, 0.3, 0.012), (0, 0.1, 1.38), "glass", "sneeze_guard", rot=(25, 0, 0))
			for sx in (-1, 1):
				kit.rod((sx * 1.15, -0.1, 0.9), (sx * 1.15, -0.02, 1.4), 0.012, STEEL, "guard_post", segs=6)
	elif what == "high_chair":
		with kit.stage("main"):
			for sx in (-1, 1):
				for sy in (-1, 1):
					kit.rod((sx * 0.27, sy * 0.27, 0), (sx * 0.17, sy * 0.17, 0.75), 0.016, OAK, "leg", segs=6)
			kit.box((0.36, 0.34, 0.03), (0, 0, 0.55), OAK, "seat")
			kit.box((0.36, 0.03, 0.3), (0, -0.16, 0.72), OAK, "back")
			kit.box((0.42, 0.22, 0.02), (0, 0.2, 0.75), "paint_white", "tray")
	elif what == "wine_rack":
		with kit.stage("main"):
			kit.frame(1.0, 1.9, 0.04, 0.32, (0, 0, 0), DARK, "frame")
			for r in range(8):
				for c in range(6):
					kit.cyl(0.04, 0.3, (-0.4 + c * 0.16, 0, 0.18 + r * 0.22), "glass_dark" if (r + c) % 3 else "plastic_green", "wine_bottle", axis="y", segs=8)
				kit.box((0.92, 0.3, 0.012), (0, 0, 0.12 + r * 0.22), DARK, "rack_shelf")
	elif what == "banquet_chair":
		with kit.stage("main"):
			chair((0, 0), 0, RED, BRASS)
	elif what == "chair_stack":
		with kit.stage("main"):
			for i in range(8):
				kit.box((0.42, 0.42, 0.05), (0, i * 0.012, 0.45 + i * 0.1), RED, "seat")
				kit.box((0.42, 0.03, 0.35), (0, -0.2 + i * 0.012, 0.7 + i * 0.1), RED, "back")
			for sx in (-1, 1):
				for sy in (-1, 1):
					kit.rod((sx * 0.19, sy * 0.19, 0), (sx * 0.19, sy * 0.19 + 0.09, 1.2), 0.012, BRASS, "frame", segs=6)
	elif what == "lectern":
		with kit.stage("main"):
			with kit.hollow(0.2):
				kit.box((0.5, 0.35, 1.05), (0, 0, 0.525), DARK, "column")
			kit.box((0.6, 0.45, 0.03), (0, 0, 1.1), DARK, "desk", rot=(18, 0, 0))
			kit.rod((0.15, -0.1, 1.1), (0.15, 0.05, 1.38), 0.006, BLACK, "microphone", segs=5)
	elif what == "dance_floor":
		with kit.stage("main"):
			for i in range(4):
				for j in range(4):
					kit.box((0.99, 0.99, 0.03), (-1.5 + i, -1.5 + j, 0.015), OAK if (i + j) % 2 else "glulam", "panel")
			for sx in (-1, 1):
				kit.box((0.05, 4.1, 0.02), (sx * 2.025, 0, 0.01), BRASS, "edge")
				kit.box((4.0, 0.05, 0.02), (0, sx * 2.025, 0.01), BRASS, "edge")
	elif what == "mobile_bar":
		with kit.stage("main"):
			counter(1.8, 0.6, 1.1, "laminate_white", BLACK)
			bottles(-0.7, 0.7, -0.15, 1.1, 9)
			kit.box((0.45, 0.3, 0.2), (0.5, 0.1, 1.2), STEEL, "ice_well")
	elif what == "dj_booth":
		with kit.stage("main"):
			with kit.hollow(0.2):
				kit.box((1.8, 0.7, 1.0), (0, 0, 0.5), BLACK, "booth")
			kit.box((1.7, 0.012, 0.8), (0, 0.357, 0.5), "glow", "front_panel")
			for sx in (-1, 1):
				kit.cyl(0.16, 0.04, (sx * 0.5, 0, 1.03), BLACK, "deck", segs=18)
				kit.cyl(0.14, 0.006, (sx * 0.5, 0, 1.053), STEEL, "platter", segs=18)
			kit.box((0.35, 0.4, 0.07), (0, 0, 1.035), STEEL, "mixer")
			kit.box((0.36, 0.02, 0.25), (0, -0.25, 1.2), "screen", "laptop")
	elif what == "pa_speaker":
		with kit.stage("main"):
			for a in (0, 120, 240):
				c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
				kit.rod((0, 0, 0.75), (0.5 * c, 0.5 * s, 0), 0.015, BLACK, "tripod", segs=6)
			kit.rod((0, 0, 0.4), (0, 0, 1.5), 0.02, BLACK, "pole", segs=8)
			with kit.hollow(0.3):
				kit.prism([(-0.2, -0.18), (0.2, -0.18), (0.15, 0.18), (-0.15, 0.18)], 0.65, (0, 0, 1.82), BLACK, "cabinet", axis="z")
			kit.cyl(0.14, 0.02, (0, 0.185, 1.7), "plastic_grey", "woofer", axis="y", segs=14)
			kit.box((0.2, 0.02, 0.1), (0, 0.185, 2.0), "plastic_grey", "horn")
	elif what == "chandelier":
		with kit.stage("main"):
			kit.rod((0, 0, 0), (0, 0, -0.9), 0.012, BRASS, "chain", segs=6)
			kit.lathe([(0.02, -1.5), (0.09, -1.35), (0.04, -1.2), (0.07, -1.0), (0.03, -0.9)], (0, 0, 0), BRASS, "stem", segs=12)
			for i in range(8):
				a = math.radians(i * 45)
				c, s = math.cos(a), math.sin(a)
				kit.sweep([(0.05 * c, 0.05 * s, -1.3), (0.3 * c, 0.3 * s, -1.42), (0.5 * c, 0.5 * s, -1.3), (0.52 * c, 0.52 * s, -1.2)], kit.circle(0.01, 6), BRASS, "arm")
				kit.cyl(0.03, 0.01, (0.52 * c, 0.52 * s, -1.19), BRASS, "drip_pan", segs=8)
				kit.cyl(0.012, 0.1, (0.52 * c, 0.52 * s, -1.13), "paint_white", "candle", segs=6)
				kit.sphere(0.022, (0.52 * c, 0.52 * s, -1.06), "glow", "flame", segs=6)
				kit.sphere(0.025, (0.3 * c, 0.3 * s, -1.5), "glass", "crystal", segs=6)
		kit.socket("ceiling", (0, 0, 0))


# --- hotel ----------------------------------------------------------------------------------

def hotel(what="bed_king"):
	if what in ("bed_king", "bed_twin"):
		w = 1.8 if what == "bed_king" else 0.95
		xs = (0,) if what == "bed_king" else (-0.75, 0.75)
		with kit.stage("bed"):
			span = w if what == "bed_king" else 2.45
			with kit.hollow(0.3):
				kit.box((span + 1.3, 0.08, 1.3), (0, -1.04, 0.65), DARK, "headboard")
			kit.rounded_box((span + 0.9, 0.06, 0.7), (0, -0.98, 0.9), "fabric_grey", "headboard_pad", radius=0.03)
			for x in xs:
				with kit.hollow(0.3):
					kit.box((w, 2.0, 0.3), (x, 0, 0.17), "fabric_grey", "divan")
				kit.rounded_box((w, 2.0, 0.24), (x, 0, 0.44), "fabric_white", "mattress", radius=0.06)
				kit.rounded_box((w + 0.04, 1.45, 0.08), (x, 0.28, 0.58), "fabric_white", "duvet", radius=0.035)
				kit.rounded_box((w + 0.05, 0.5, 0.03), (x, 0.7, 0.63), "velvet_teal", "runner", radius=0.012)
				for sx in ((-1, 1) if what == "bed_king" else (0,)):
					kit.rounded_box((0.7, 0.42, 0.14), (x + sx * 0.42, -0.72, 0.64), "fabric_white", "pillow", radius=0.06)
		with kit.stage("bedside"):
			for sx in (-1, 1):
				bx = sx * (span / 2 + 0.33)
				with kit.hollow(0.2):
					kit.box((0.45, 0.4, 0.5), (bx, -0.78, 0.25), DARK, "bedside")
				kit.box((0.4, 0.012, 0.18), (bx, -0.575, 0.36), DARK, "drawer")
				kit.cyl(0.06, 0.25, (bx, -0.8, 0.625), "ceramic", "lamp_base", segs=10)
				lamp_shade((bx, -0.8, 0.75))
	elif what == "desk":
		with kit.stage("main"):
			kit.box((1.3, 0.5, 0.04), (0, 0, 0.74), DARK, "top")
			for sx in (-1, 1):
				kit.box((0.04, 0.5, 0.72), (sx * 0.63, 0, 0.36), DARK, "end")
			kit.box((1.22, 0.02, 0.3), (0, -0.23, 0.55), DARK, "modesty")
			kit.box((0.7, 0.03, 0.85), (0, -0.24, 1.3), "mirror", "mirror")
			kit.box((0.25, 0.2, 0.2), (0.45, -0.1, 0.86), STEEL, "kettle_tray")
		with kit.stage("chair"):
			chair((0, 0.45), 180, "velvet_teal", DARK)
	elif what == "wardrobe":
		with kit.stage("main"):
			kit.frame(1.0, 2.0, 0.04, 0.6, (0, 0, 0), DARK, "frame")
			kit.box((1.0, 0.02, 2.0), (0, -0.29, 1.0), DARK, "back")
			kit.rod((-0.46, 0, 1.75), (0.46, 0, 1.75), 0.012, STEEL, "rail", segs=8)
			for i in range(5):
				kit.box((0.012, 0.4, 0.2), (-0.3 + i * 0.12, 0, 1.63), OAK, "hanger")
			kit.box((0.92, 0.55, 0.03), (0, 0, 0.5), DARK, "shelf")
			with kit.hollow(0.5):
				kit.box((0.4, 0.4, 0.25), (-0.2, 0, 0.17), "plastic_grey", "safe")
			kit.box((0.45, 0.35, 0.1), (0.2, 0, 0.57), "fabric_white", "spare_pillow")
	elif what == "tv_console":
		with kit.stage("main"):
			carcass(1.4, 0.45, 0.6, DARK, doors=2)
			kit.box((1.1, 0.04, 0.63), (0, -0.1, 1.2), "screen", "television")
			kit.box((0.3, 0.2, 0.25), (0, -0.1, 0.75), BLACK, "tv_stand")
	elif what == "housekeeping_trolley":
		with kit.stage("main"):
			with kit.hollow(0.2):
				kit.box((0.9, 0.5, 0.9), (0, 0, 0.6), "plastic_grey", "cabinet")
			for z in (0.45, 0.75, 1.02):
				kit.box((0.84, 0.46, 0.14), (0, 0.0, z + 0.07), "fabric_white", "linen")
			for sx in (-1, 1):
				with kit.hollow(0.05):
					kit.box((0.4, 0.5, 0.75), (sx * 0.67, 0, 0.6), "fabric_blue" if sx < 0 else "fabric_grey", "bag")
				kit.frame(0.44, 0.9, 0.02, 0.5, (sx * 0.67, 0, 0.15), STEEL, "bag_frame")
			for sx in (-1, 1):
				for sy in (-1, 1):
					kit.cyl(0.05, 0.03, (sx * 0.8, sy * 0.2, 0.05), "rubber", "castor", axis="x", segs=10)
	elif what == "luggage_cart":
		with kit.stage("main"):
			kit.box((1.1, 0.6, 0.05), (0, 0, 0.2), RED, "deck")
			for sx in (-1, 1):
				kit.sweep([(sx * 0.5, -0.25, 0.22), (sx * 0.5, -0.25, 1.5), (sx * 0.5, -0.1, 1.72), (sx * 0.5, 0.1, 1.72), (sx * 0.5, 0.25, 1.5), (sx * 0.5, 0.25, 0.22)], kit.circle(0.018, 8), BRASS, "hoop")
				for sy in (-1, 1):
					kit.cyl(0.07, 0.04, (sx * 0.45, sy * 0.22, 0.07), "rubber", "castor", axis="x", segs=10)
			kit.rod((-0.5, 0, 1.72), (0.5, 0, 1.72), 0.014, BRASS, "hanging_rail", segs=8)
			kit.rounded_box((0.5, 0.35, 0.6), (-0.2, 0, 0.53), "leather_black", "suitcase", radius=0.04)
			kit.rounded_box((0.4, 0.3, 0.3), (0.3, 0, 0.38), "fabric_blue", "holdall", radius=0.08)
	elif what == "reception":
		with kit.stage("main"):
			counter(3.6, 0.7, 1.1, DARK, "marble")
			kit.box((3.6, 0.5, 0.03), (0, -0.25, 0.74), DARK, "work_surface")
			for x in (-1.0, 1.0):
				kit.box((0.45, 0.03, 0.3), (x, -0.25, 0.93), "screen", "monitor")
			kit.cyl(0.05, 0.03, (0.4, 0.2, 1.115), BRASS, "bell", segs=10)
		with kit.stage("back"):
			kit.box((3.0, 0.08, 1.4), (0, -1.2, 1.5), DARK, "key_board")
			for r in range(4):
				for c in range(10):
					kit.box((0.2, 0.09, 0.2), (-1.26 + c * 0.28, -1.19, 1.0 + r * 0.3), OAK, "pigeon_hole")
	elif what == "ironing_station":
		with kit.stage("main"):
			kit.box((1.2, 0.35, 0.03), (0, 0, 0.88), "fabric_grey", "board")
			for s in (-1, 1):
				kit.rod((s * 0.4, -0.14, 0), (-s * 0.4, 0.14, 0.87), 0.012, STEEL, "leg", segs=6)
			kit.rounded_box((0.26, 0.12, 0.14), (0.4, 0, 0.97), "plastic_white", "iron", radius=0.04)
	elif what == "minibar_unit":
		with kit.stage("main"):
			carcass(0.6, 0.5, 0.85, DARK, doors=1)
			kit.cyl(0.08, 0.2, (-0.12, 0, 0.95), STEEL, "kettle", segs=10)
			for i in range(2):
				kit.cyl(0.04, 0.09, (0.1 + i * 0.12, 0.05, 0.895), "ceramic", "cup", segs=8)


# --- theatre and cinema ---------------------------------------------------------------------

def theatre(what="seats_4", n=4, rows=1, slot=RED):
	if what == "seats":
		with kit.stage("main"):
			for r in range(rows):
				before = None
				y = -r * 0.9
				z = r * 0.3
				if r:
					with kit.hollow(0.3):
						kit.box((n * 0.55 + 0.1, 0.9, z), (0, y, z / 2), "carpet", "step")
				_row_at(n, y, z, slot)
	elif what == "balcony_front":
		with kit.stage("main"):
			with kit.hollow(0.3):
				kit.box((3.0, 0.3, 0.8), (0, 0, 0.4), "paint_white", "front")
			kit.box((3.0, 0.32, 0.08), (0, 0, 0.84), BRASS, "rail_cap")
			for i in range(5):
				kit.box((0.4, 0.02, 0.45), (-1.2 + i * 0.6, 0.16, 0.42), BRASS, "panel_moulding")
			kit.rod((-1.5, 0.05, 1.0), (1.5, 0.05, 1.0), 0.02, BRASS, "safety_rail", segs=8)
			for i in range(4):
				kit.rod((-1.5 + i * 1.0, 0.05, 0.88), (-1.5 + i * 1.0, 0.05, 1.0), 0.012, BRASS, "rail_post", segs=6)
	elif what == "stage_deck":
		with kit.stage("main"):
			kit.box((2.0, 1.0, 0.04), (0, 0, 0.98), BLACK, "deck")
			for sx in (-1, 1):
				for sy in (-1, 1):
					kit.box((0.05, 0.05, 0.96), (sx * 0.95, sy * 0.45, 0.48), "aluminium", "leg")
				kit.box((0.04, 0.9, 0.08), (sx * 0.97, 0, 0.92), "aluminium", "side_rail")
			for sy in (-1, 1):
				kit.box((1.9, 0.04, 0.08), (0, sy * 0.47, 0.92), "aluminium", "long_rail")
			kit.box((2.0, 0.01, 0.94), (0, 0.5, 0.47), "fabric_grey", "skirt")
	elif what == "proscenium":
		w, h = 12.0, 7.0
		with kit.stage("main"):
			with kit.hollow(0.15):
				for sx in (-1, 1):
					kit.box((1.2, 0.6, h), (sx * (w / 2 + 0.6), 0, h / 2), "paint_white", "pier")
					kit.box((0.3, 0.7, h), (sx * (w / 2 + 0.05), 0, h / 2), BRASS, "gilt_column")
				kit.box((w + 2.4, 0.6, 1.5), (0, 0, h + 0.75), "paint_white", "header")
			kit.box((w + 0.4, 0.7, 0.25), (0, 0, h + 0.1), BRASS, "gilt_frieze")
			kit.cyl(0.6, 0.72, (0, 0, h + 0.85), BRASS, "cartouche", axis="y", segs=16)
		with kit.stage("curtain"):
			for sx in (-1, 1):
				n = 14
				for i in range(n):
					x = sx * (w / 2 - 0.2 - i * 0.2)
					kit.cyl(0.11, h - 0.4, (x, -0.25 + 0.04 * (i % 2), (h - 0.4) / 2 + 0.05), "fabric_red", "curtain_fold", segs=8)
			kit.box((w, 0.25, 0.9), (0, -0.2, h - 0.45), "fabric_red", "pelmet")
			for i in range(12):
				kit.cyl(0.25, 0.3, (-w / 2 + 0.5 + i * (w - 1.0) / 11, -0.05, h - 0.9), "fabric_red", "swag", axis="y", segs=10)
	elif what == "lighting_truss":
		l = 8.0
		with kit.stage("main"):
			for dx, dz in ((-0.15, 0), (0.15, 0), (0, 0.26)):
				kit.rod((-l / 2, dx, dz), (l / 2, dx, dz), 0.025, "aluminium", "chord", segs=8)
			n = 16
			for i in range(n):
				x0, x1 = -l / 2 + l * i / n, -l / 2 + l * (i + 1) / n
				kit.rod((x0, -0.15, 0), (x1, 0, 0.26), 0.012, "aluminium", "web", segs=5)
				kit.rod((x1, 0, 0.26), (x1, 0.15, 0), 0.012, "aluminium", "web", segs=5)
				kit.rod((x0, 0.15, 0), (x1, -0.15, 0), 0.012, "aluminium", "web", segs=5)
		with kit.stage("lanterns"):
			for i in range(8):
				x = -l / 2 + 0.5 + i * 1.0
				kit.box((0.06, 0.06, 0.12), (x, 0, -0.07), BLACK, "clamp")
				kit.cyl(0.11, 0.3, (x, 0.08, -0.26), BLACK, "lantern", axis="y", segs=12, rot=(-35, 0, 0))
				kit.cyl(0.1, 0.02, (x, 0.2, -0.345), ("glow", "plastic_red", "plastic_blue", "glow")[i % 4], "lens", axis="y", segs=12, rot=(-35, 0, 0))
		kit.socket("hang_left", (-l / 2 + 0.5, 0, 0.26))
		kit.socket("hang_right", (l / 2 - 0.5, 0, 0.26))
	elif what == "follow_spot":
		with kit.stage("main"):
			for a in (90, 210, 330):
				c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
				kit.rod((0, 0, 0.9), (0.55 * c, 0.55 * s, 0), 0.018, BLACK, "tripod", segs=6)
			kit.rod((0, 0, 0.5), (0, 0, 1.35), 0.025, BLACK, "column", segs=8)
			kit.cyl(0.16, 1.0, (0, 0.1, 1.5), BLACK, "lamp_house", axis="y", segs=14, rot=(-8, 0, 0))
			kit.cyl(0.13, 0.03, (0, 0.6, 1.43), "glow", "lens", axis="y", segs=14, rot=(-8, 0, 0))
			kit.box((0.12, 0.2, 0.12), (0, -0.2, 1.72), BLACK, "vent")
	elif what == "grand_piano":
		with kit.stage("main"):
			outline = [(-0.75, 0.0), (0.75, 0.0), (0.75, -0.9), (0.6, -1.5), (0.25, -2.0), (-0.2, -2.15), (-0.6, -1.95), (-0.75, -1.4)]
			with kit.hollow(0.35):
				kit.prism(outline, 0.32, (0, 0, 0.86), BLACK, "case", axis="z")
			kit.prism(outline, 0.02, (0, 0, 1.04), BLACK, "lid", axis="z")
			kit.prism(outline[1:6], 0.02, (0.05, 0, 1.4), BLACK, "lid_raised", axis="z", rot=(0, -28, 0))
			kit.rod((0.5, -0.9, 1.05), (0.42, -0.9, 1.55), 0.01, BLACK, "lid_prop", segs=5)
			kit.box((1.4, 0.16, 0.03), (0, 0.1, 0.74), "paint_white", "keys")
			kit.box((1.4, 0.07, 0.035), (0, 0.065, 0.76), BLACK, "black_keys")
			kit.box((1.5, 0.3, 0.05), (0, 0.12, 0.7), BLACK, "key_bed")
			for x, y in ((-0.65, -0.1), (0.65, -0.1), (-0.1, -1.9)):
				turned_leg((x, y, 0), 0.7, 0.05, BLACK)
			kit.box((0.25, 0.06, 0.03), (0, -0.05, 0.12), BRASS, "pedals")
			kit.rod((0, -0.05, 0.14), (0, -0.05, 0.7), 0.015, BLACK, "pedal_rod", segs=5)
		with kit.stage("stool"):
			kit.rounded_box((0.6, 0.35, 0.08), (0, 0.55, 0.5), LEATHER, "stool_pad", radius=0.03)
			legs(0.6, 0.35, 0.46, 0.04, BLACK, inset=0.02, at=(0, 0.55))
	elif what == "flight_case":
		with kit.stage("main"):
			with kit.hollow(0.3):
				kit.box((1.2, 0.6, 0.7), (0, 0, 0.47), BLACK, "case")
			kit.frame(1.2, 0.7, 0.03, 0.62, (0, 0, 0.12), "aluminium", "edging")
			for sx in (-1, 1):
				kit.box((0.12, 0.02, 0.08), (sx * 0.35, 0.31, 0.5), STEEL, "latch")
				for sy in (-1, 1):
					kit.cyl(0.05, 0.04, (sx * 0.5, sy * 0.22, 0.06), "plastic_blue", "castor", axis="x", segs=10)
	elif what == "mixing_desk":
		with kit.stage("main"):
			table(1.8, 0.8, 0.75, BLACK, BLACK)
			kit.box((1.5, 0.6, 0.1), (0, 0, 0.82), "plastic_grey", "console", rot=(10, 0, 0))
			for i in range(24):
				kit.box((0.02, 0.06, 0.02), (-0.69 + i * 0.06, 0.1 + 0.05 * ((i * 7) % 3 - 1), 0.89), "paint_white", "fader")
			kit.box((0.5, 0.03, 0.3), (0.4, -0.3, 1.1), "screen", "screen")
	elif what == "backdrop_flat":
		with kit.stage("main"):
			kit.box((2.4, 0.03, 4.8), (0, 0, 2.4), "plywood", "flat")
			kit.box((2.38, 0.006, 4.78), (0, 0.018, 2.4), "fabric_blue", "canvas")
			for sx in (-1, 1):
				kit.strut((sx * 0.9, -0.02, 2.6), (sx * 0.9, -1.2, 0.03), 0.04, 0.06, "softwood", "brace")
				kit.box((0.3, 0.3, 0.12), (sx * 0.9, -1.2, 0.06), "cast_iron", "stage_weight")
	elif what == "cinema_screen":
		w, h = 12.0, 5.2
		with kit.stage("main"):
			kit.frame(w + 0.3, h + 0.3, 0.15, 0.2, (0, 0, 1.2), BLACK, "masking")
			kit.box((w, 0.03, h), (0, 0, 1.35 + h / 2), "paint_white", "screen")
			for sx in (-1, 0, 1):
				with kit.hollow(0.3):
					kit.box((1.0, 0.6, 1.8), (sx * w * 0.33, -0.5, 2.6), BLACK, "screen_speaker")
			for sx in (-1, 1):
				kit.box((0.8, 0.3, 1.2), (sx * (w / 2 + 0.7), 0, 0.6), "fabric_red", "drape_base")
				for i in range(4):
					kit.cyl(0.12, h + 1.4, (sx * (w / 2 + 0.4 + i * 0.2), 0.05 * (i % 2), (h + 1.4) / 2), "fabric_red", "drape", segs=8)
	elif what == "projector":
		with kit.stage("main"):
			with kit.hollow(0.4):
				kit.box((0.6, 0.6, 1.1), (0, 0, 0.55), "plastic_grey", "pedestal")
				kit.box((0.7, 1.2, 0.55), (0, 0, 1.4), BLACK, "projector")
			kit.cyl(0.12, 0.3, (0, 0.72, 1.4), BLACK, "lens_barrel", axis="y", segs=14)
			kit.cyl(0.1, 0.02, (0, 0.88, 1.4), "glass", "lens", axis="y", segs=14)
			kit.cyl(0.1, 0.5, (0.1, -0.2, 1.9), "aluminium", "exhaust", segs=10)
			kit.box((0.25, 0.02, 0.2), (-0.36, 0.2, 1.4), "screen", "touch_panel", rot=(0, 0, 90))
	elif what == "surround_speaker":
		with kit.stage("main"):
			with kit.hollow(0.3):
				kit.prism([(-0.2, 0), (0.2, 0), (0.2, 0.2), (-0.2, 0.32)], 0.5, (0, 0.0, 2.6), BLACK, "cabinet", axis="x", rot=(0, 0, 90))
	elif what == "box_office":
		with kit.stage("main"):
			counter(2.4, 0.6, 1.05, DARK, "marble")
			kit.box((2.4, 0.03, 1.1), (0, 0.25, 1.62), "glass", "screen")
			for x in (-0.6, 0.6):
				kit.cyl(0.09, 0.035, (x, 0.25, 1.5), BRASS, "speak_grille", axis="y", segs=12)
				kit.box((0.3, 0.2, 0.012), (x, 0.3, 1.075), BRASS, "ticket_tray")
			kit.box((2.5, 0.2, 0.3), (0, 0.2, 2.32), DARK, "header")
			kit.box((1.6, 0.02, 0.2), (0, 0.31, 2.32), "glow", "sign")
	elif what == "concession":
		with kit.stage("main"):
			counter(3.0, 0.7, 1.0, "plastic_red", STEEL)
			with kit.hollow(0.1):
				kit.box((0.7, 0.5, 0.8), (-1.0, 0, 1.42), "glass", "popcorn_case")
			kit.box((0.6, 0.4, 0.3), (-1.0, 0, 1.17), "plastic_yellow", "popcorn")
			kit.cyl(0.14, 0.18, (-1.0, 0, 1.68), STEEL, "kettle", segs=12)
			kit.box((0.74, 0.54, 0.06), (-1.0, 0, 1.85), "plastic_red", "case_top")
			for i in range(3):
				kit.box((0.2, 0.3, 0.6), (0.1 + i * 0.26, -0.1, 1.32), BLACK, "drinks_tower")
				kit.box((0.16, 0.01, 0.2), (0.1 + i * 0.26, 0.055, 1.45), ("plastic_red", "plastic_green", "plastic_yellow")[i], "drinks_badge")
			with kit.hollow(0.1):
				kit.box((0.6, 0.4, 0.4), (1.1, 0, 1.22), "glass", "sweets_case")
			kit.box((3.0, 0.1, 0.5), (0, -0.3, 2.45), "glow", "menu_board")
			for sx in (-1, 1):
				kit.rod((sx * 1.45, -0.3, 1.02), (sx * 1.45, -0.3, 2.2), 0.02, STEEL, "menu_post", segs=6)
	elif what == "poster_case":
		with kit.stage("main"):
			kit.frame(0.8, 1.15, 0.05, 0.07, (0, 0, 1.0), BRASS, "frame")
			kit.box((0.7, 0.02, 1.05), (0, 0, 1.575), "plastic_blue", "poster")
			kit.box((0.7, 0.008, 1.05), (0, 0.022, 1.575), "glass", "glazing")
	elif what == "rope_barrier":
		with kit.stage("main"):
			rope_post((-0.9, 0))
			rope_post((0.9, 0))
			rope((-0.9, 0, 0.9), (0.9, 0, 0.9))
	elif what == "ticket_kiosk":
		with kit.stage("main"):
			with kit.hollow(0.3):
				kit.box((0.55, 0.4, 1.3), (0, 0, 0.65), "plastic_grey", "body")
			kit.box((0.4, 0.02, 0.32), (0, 0.19, 1.25), "screen", "touch_screen", rot=(-25, 0, 0))
			kit.box((0.2, 0.02, 0.05), (0, 0.205, 0.8), BLACK, "ticket_slot")
			kit.box((0.12, 0.03, 0.14), (0.15, 0.2, 0.98), BLACK, "card_reader")
	elif what == "dressing_table":
		with kit.stage("main"):
			kit.box((1.2, 0.5, 0.04), (0, 0, 0.75), "laminate_white", "top")
			for sx in (-1, 1):
				kit.box((0.04, 0.5, 0.73), (sx * 0.58, 0, 0.365), "laminate_white", "end")
			kit.box((1.0, 0.03, 0.8), (0, -0.23, 1.3), "mirror", "mirror")
			kit.frame(1.12, 0.92, 0.06, 0.05, (0, -0.22, 0.84), "paint_white", "mirror_frame")
			for i in range(6):
				for sx in (-1, 1):
					kit.sphere(0.03, (sx * 0.53, -0.19, 0.95 + i * 0.14), "glow", "bulb", segs=6)
			for i in range(7):
				kit.sphere(0.03, (-0.45 + i * 0.15, -0.19, 1.73), "glow", "bulb", segs=6)
		with kit.stage("chair"):
			chair((0, 0.4), 180, LEATHER, STEEL)
	elif what == "costume_rail":
		with kit.stage("main"):
			for sx in (-1, 1):
				kit.rod((sx * 0.75, 0, 0.1), (sx * 0.75, 0, 1.7), 0.015, STEEL, "upright", segs=6)
				kit.rod((sx * 0.75, -0.25, 0.1), (sx * 0.75, 0.25, 0.1), 0.015, STEEL, "foot", segs=6)
				for sy in (-1, 1):
					kit.cyl(0.04, 0.03, (sx * 0.75, sy * 0.25, 0.04), "rubber", "castor", axis="x", segs=8)
			kit.rod((-0.75, 0, 1.7), (0.75, 0, 1.7), 0.015, STEEL, "rail", segs=6)
			for i in range(9):
				slot = (RED, "fabric_blue", "fabric_white", "velvet_teal", GREEN, "leather_black")[i % 6]
				kit.box((0.06, 0.42, 1.1 - 0.1 * (i % 3)), (-0.6 + i * 0.15, 0, 1.6 - (1.1 - 0.1 * (i % 3)) / 2), slot, "costume")


def _row_at(n, y, z, slot):
	"""A row of tip-up seats standing on a tier at height z."""
	w = 0.55
	for i in range(n):
		x = -(n - 1) * w / 2 + i * w
		kit.rounded_box((w - 0.08, 0.1, 0.55), (x, y - 0.22, z + 0.72), slot, "seat_back", radius=0.04, rot=(-8, 0, 0), segments=2)
		kit.rounded_box((w - 0.08, 0.09, 0.42), (x, y - 0.1, z + 0.56), slot, "squab", radius=0.035, rot=(12, 0, 0), segments=2)
	for i in range(n + 1):
		x = -n * w / 2 + i * w
		kit.box((0.05, 0.42, 0.6), (x, y - 0.05, z + 0.3), BLACK, "seat_standard")
		kit.rounded_box((0.07, 0.36, 0.035), (x, y - 0.03, z + 0.62), DARK, "arm", radius=0.012)


# --- courts and prison ----------------------------------------------------------------------

def panelled(w, d, h, at=(0, 0, 0), slot=DARK, name="panelled"):
	"""A panelled timber box (benches, docks, witness boxes)."""
	x, y, z = at
	with kit.hollow(0.15):
		kit.box((w, d, h), (x, y, z + h / 2), slot, name)
	kit.box((w + 0.06, d + 0.06, 0.04), (x, y, z + h + 0.02), slot, name + "_cap")
	n = max(1, int(w / 0.6))
	for i in range(n):
		kit.box((w / n - 0.1, 0.012, h - 0.2), (x - w / 2 + w * (i + 0.5) / n, y + d / 2 + 0.006, z + h / 2), OAK, "panel")


def court(what="judges_bench"):
	if what == "judges_bench":
		with kit.stage("dais"):
			with kit.hollow(0.2):
				kit.box((5.0, 2.2, 0.6), (0, -0.4, 0.3), "carpet", "dais")
			panelled(4.6, 0.7, 1.15, (0, 0.2, 0.6))
			kit.box((4.6, 0.5, 0.04), (0, -0.05, 1.38), DARK, "desk_top")
		with kit.stage("seats"):
			for x in (-1.4, 0, 1.4):
				with kit.hollow(0.3):
					kit.rounded_box((0.7, 0.12, 1.5), (x, -0.95, 1.35), "leather_black" if x else RED, "high_back", radius=0.05)
					kit.rounded_box((0.65, 0.6, 0.14), (x, -0.65, 1.1), "leather_black" if x else RED, "seat", radius=0.05)
				kit.cyl(0.04, 0.45, (x, -0.65, 0.82), BLACK, "seat_column", segs=8)
		with kit.stage("crest"):
			kit.box((1.2, 0.06, 1.2), (0, -1.45, 3.3), BRASS, "crest_shield")
			kit.cyl(0.75, 0.05, (0, -1.46, 3.3), DARK, "crest_plaque", axis="y", segs=24)
			kit.box((5.0, 0.1, 3.6), (0, -1.5, 2.4), OAK, "back_panelling")
	elif what == "witness_box":
		with kit.stage("main"):
			with kit.hollow(0.3):
				kit.box((1.3, 1.3, 0.3), (0, 0, 0.15), "carpet", "step")
			panelled(1.3, 0.12, 1.0, (0, 0.6, 0.3))
			for sx in (-1, 1):
				with kit.hollow(0.2):
					kit.box((0.1, 1.2, 1.0), (sx * 0.6, 0, 0.8), DARK, "side")
			kit.box((1.1, 0.25, 0.03), (0, 0.45, 1.25), DARK, "ledge")
			kit.rod((0.3, 0.45, 1.27), (0.3, 0.38, 1.55), 0.006, BLACK, "microphone", segs=5)
			chair((0, -0.15), 0, "fabric_blue", DARK)
	elif what == "dock":
		with kit.stage("main"):
			panelled(3.0, 0.12, 1.1, (0, 0.7, 0))
			for sx in (-1, 1):
				with kit.hollow(0.2):
					kit.box((0.1, 1.5, 1.1), (sx * 1.5, 0, 0.55), DARK, "side")
			with kit.hollow(0.2):
				kit.box((3.0, 0.1, 1.1), (0, -0.75, 0.55), DARK, "back")
			kit.box((3.0, 0.02, 1.1), (0, 0.7, 1.68), "glass", "screen")
			for sx in (-1, 1):
				kit.box((0.02, 1.5, 1.1), (sx * 1.5, 0, 1.68), "glass", "side_screen")
			kit.box((3.1, 0.06, 0.06), (0, 0.7, 2.26), STEEL, "screen_rail")
			with kit.hollow(0.3):
				kit.box((2.7, 0.45, 0.45), (0, -0.45, 0.225), DARK, "bench")
	elif what == "jury_box":
		with kit.stage("main"):
			with kit.hollow(0.3):
				kit.box((4.4, 1.1, 0.35), (0, -1.0, 0.175), "carpet", "tier")
			panelled(4.4, 0.1, 1.0, (0, 0.6, 0))
			for sx in (-1, 1):
				with kit.hollow(0.2):
					kit.box((0.1, 2.2, 1.0), (sx * 2.2, -0.45, 0.5), DARK, "side")
			kit.box((4.3, 0.3, 0.03), (0, 0.4, 0.85), DARK, "ledge")
		with kit.stage("seats"):
			for r in range(2):
				for i in range(6):
					x = -1.75 + i * 0.7
					z = r * 0.35
					y = -0.1 - r * 1.0
					kit.rounded_box((0.55, 0.5, 0.1), (x, y, z + 0.45), "fabric_green", "seat", radius=0.04)
					kit.rounded_box((0.55, 0.09, 0.5), (x, y - 0.25, z + 0.75), "fabric_green", "back", radius=0.04)
					kit.box((0.5, 0.45, 0.4), (x, y, z + 0.2), DARK, "seat_base")
	elif what == "counsel_table":
		with kit.stage("main"):
			table(2.4, 0.8, 0.75, DARK, DARK)
			kit.box((2.4, 0.03, 0.3), (0, 0.38, 0.9), DARK, "upstand")
			for x in (-0.7, 0.2):
				kit.box((0.3, 0.22, 0.12 if x < 0 else 0.05), (x, 0, 0.81 if x < 0 else 0.775), ("paint_white", "plastic_red")[x > 0], "bundle")
			kit.box((0.34, 0.02, 0.22), (0.8, 0.1, 0.87), "screen", "laptop")
		with kit.stage("chairs"):
			for x in (-0.8, 0, 0.8):
				chair((x, -0.65), 0, "fabric_blue", DARK)
	elif what == "clerk_desk":
		with kit.stage("main"):
			panelled(2.6, 0.7, 0.95, (0, 0, 0))
			kit.box((0.45, 0.03, 0.3), (-0.6, -0.1, 1.15), "screen", "monitor")
			kit.box((0.4, 0.25, 0.3), (0.6, 0, 1.12), BLACK, "recorder")
		with kit.stage("chairs"):
			chair((-0.5, -0.7), 0, "fabric_blue", BLACK)
			chair((0.5, -0.7), 0, "fabric_blue", BLACK)
	elif what == "public_bench":
		with kit.stage("main"):
			kit.box((2.6, 0.42, 0.05), (0, 0, 0.44), OAK, "seat")
			kit.box((2.6, 0.05, 0.5), (0, -0.2, 0.7), OAK, "back", rot=(-6, 0, 0))
			for x in (-1.25, 0, 1.25):
				kit.prism([(-0.25, 0), (0.22, 0), (0.22, 0.42), (-0.18, 0.42), (-0.25, 0.95), (-0.3, 0.95)], 0.05, (x, 0, 0), DARK, "bench_end", axis="x")
	elif what == "bar_rail":
		with kit.stage("main"):
			for i in range(9):
				turned_leg((-1.2 + i * 0.3, 0, 0.05), 0.75, 0.03)
			kit.box((2.5, 0.1, 0.05), (0, 0, 0.025), DARK, "plinth")
			kit.box((2.5, 0.1, 0.06), (0, 0, 0.83), DARK, "rail")
	elif what == "jury_table":
		with kit.stage("table"):
			kit.rounded_box((4.2, 1.4, 0.05), (0, 0, 0.73), DARK, "top", radius=0.02)
			for x in (-1.5, 1.5):
				with kit.hollow(0.3):
					kit.box((0.7, 0.9, 0.7), (x, 0, 0.35), DARK, "pedestal")
			kit.cyl(0.08, 0.25, (0, 0, 0.88), "glass", "water_jug", segs=10)
		with kit.stage("chairs"):
			for i in range(5):
				x = -1.6 + i * 0.8
				chair((x, 1.0), 180, "fabric_blue", BLACK)
				chair((x, -1.0), 0, "fabric_blue", BLACK)
			chair((2.4, 0), 90, "fabric_blue", BLACK)
			chair((-2.4, 0), -90, "fabric_blue", BLACK)
	elif what == "judges_desk":
		with kit.stage("main"):
			with kit.hollow(0.2):
				for sx in (-1, 1):
					kit.box((0.55, 0.85, 0.72), (sx * 0.7, 0, 0.36), DARK, "pedestal")
			kit.box((2.0, 0.95, 0.05), (0, 0, 0.745), DARK, "top")
			kit.box((1.5, 0.6, 0.006), (0, 0, 0.773), "leather_black", "leather_inlay")
			for sx in (-1, 1):
				for k in range(3):
					kit.box((0.45, 0.012, 0.18), (sx * 0.7, 0.431, 0.15 + k * 0.22), OAK, "drawer")
					kit.cyl(0.015, 0.02, (sx * 0.7, 0.445, 0.15 + k * 0.22), BRASS, "knob", axis="y", segs=6)
			kit.cyl(0.07, 0.3, (0.7, 0.2, 0.92), BRASS, "desk_lamp", segs=8)
			kit.box((0.3, 0.1, 0.06), (0.7, 0.2, 1.1), "plastic_green", "lamp_shade")
		with kit.stage("chair"):
			with kit.hollow(0.3):
				kit.rounded_box((0.65, 0.12, 0.9), (0, -0.95, 0.95), LEATHER, "chair_back", radius=0.05)
				kit.rounded_box((0.62, 0.6, 0.14), (0, -0.65, 0.5), LEATHER, "chair_seat", radius=0.05)
			kit.cyl(0.04, 0.4, (0, -0.65, 0.23), BLACK, "chair_column", segs=8)
			kit.cyl(0.3, 0.04, (0, -0.65, 0.03), BLACK, "chair_base", segs=5)
	elif what == "law_bookcase":
		with kit.stage("main"):
			kit.frame(1.2, 2.3, 0.04, 0.35, (0, 0, 0), DARK, "frame")
			kit.box((1.2, 0.02, 2.3), (0, -0.165, 1.15), DARK, "back")
			for r in range(6):
				z = 0.12 + r * 0.36
				kit.box((1.12, 0.33, 0.025), (0, 0, z), DARK, "shelf")
				for i in range(16):
					kit.box((0.06, 0.24, 0.27 + 0.02 * (i % 3)), (-0.5 + i * 0.066, -0.02, z + 0.15 + 0.01 * (i % 3)), ("fabric_red", "fabric_green", "leather_black", "glulam")[(i // 4 + r) % 4], "law_book")


def prison(what="bunk"):
	if what in ("bunk", "bed"):
		tiers = 2 if what == "bunk" else 1
		with kit.stage("main"):
			for sx in (-1, 1):
				for sy in (-1, 1):
					kit.box((0.05, 0.05, 0.45 + (tiers - 1) * 1.1 + 0.25), (sx * 0.4, sy * 0.98, (0.7 + (tiers - 1) * 1.1) / 2), "steel_painted", "post")
			for t in range(tiers):
				z = 0.4 + t * 1.1
				kit.box((0.8, 2.0, 0.04), (0, 0, z), "steel_painted", "bed_pan")
				kit.rounded_box((0.74, 1.9, 0.1), (0, 0, z + 0.07), "fabric_green", "mattress", radius=0.03)
				kit.rounded_box((0.5, 0.3, 0.08), (0, -0.75, z + 0.16), "fabric_white", "pillow", radius=0.03)
				kit.box((0.76, 1.1, 0.03), (0, 0.35, z + 0.135), "fabric_grey", "blanket")
			if tiers == 2:
				for k in range(4):
					kit.rod((0.42, 0.7, 0.3 + k * 0.3), (0.42, 0.98, 0.3 + k * 0.3), 0.012, "steel_painted", "ladder_rung", segs=5)
				kit.rod((0.42, 0.7, 0), (0.42, 0.7, 1.7), 0.015, "steel_painted", "ladder_stile", segs=6)
	elif what == "wc_basin":
		with kit.stage("main"):
			with kit.hollow(0.2):
				kit.box((0.45, 0.35, 0.95), (0, -0.2, 0.475), STEEL, "pedestal")
				kit.lathe([(0.14, 0), (0.19, 0.3), (0.2, 0.4), (0.17, 0.4), (0.12, 0.15)], (0, 0.15, 0), STEEL, "pan", segs=14)
			kit.lathe([(0.16, 0.86), (0.18, 0.95), (0.15, 0.95), (0.05, 0.88)], (0, -0.16, 0.02), STEEL, "basin", segs=12)
			kit.cyl(0.02, 0.02, (0.12, -0.3, 0.98), STEEL, "push_tap", segs=6)
	elif what == "desk":
		with kit.stage("main"):
			kit.box((0.9, 0.45, 0.04), (0, 0, 0.74), "laminate_grey", "top")
			kit.box((0.04, 0.4, 0.72), (-0.4, 0, 0.36), "steel_painted", "support")
			kit.strut((0.4, -0.2, 0.3), (0.4, 0.15, 0.72), 0.04, 0.04, "steel_painted", "bracket")
			kit.cyl(0.16, 0.04, (0, 0.55, 0.45), "laminate_grey", "stool_seat", segs=14)
			kit.cyl(0.04, 0.43, (0, 0.55, 0.215), "steel_painted", "stool_post", segs=8)
			kit.box((0.4, 0.3, 0.3), (0.2, -0.05, 1.45), "plastic_grey", "tv")
			kit.box((0.45, 0.32, 0.03), (0.2, -0.05, 1.28), "steel_painted", "tv_shelf")
	elif what == "cell_door":
		with kit.stage("frame"):
			kit.frame(1.0, 2.1, 0.08, 0.2, (0, 0, 0), "steel_painted", "frame")
		with kit.stage("leaf"):
			kit.box((0.84, 0.06, 2.0), (0, 0, 1.02), "plastic_blue", "leaf")
			kit.box((0.25, 0.07, 0.12), (0, 0, 1.55), "glass_dark", "observation_panel")
			kit.box((0.4, 0.075, 0.14), (0, 0, 1.0), STEEL, "hatch")
			kit.box((0.12, 0.09, 0.2), (0.33, 0, 1.05), STEEL, "lock_case")
			for z in (0.3, 1.0, 1.75):
				kit.cyl(0.03, 0.14, (-0.44, 0.03, z), STEEL, "hinge", segs=8)
		kit.socket("wall", (0, 0, 0))
	elif what == "window":
		with kit.stage("main"):
			kit.frame(1.0, 0.9, 0.08, 0.3, (0, 0, 0), "concrete", "reveal")
			kit.box((0.84, 0.03, 0.74), (0, -0.05, 0.45), "glass", "glazing")
			for i in range(6):
				kit.rod((-0.35 + i * 0.14, 0.08, 0.08), (-0.35 + i * 0.14, 0.08, 0.82), 0.014, "steel_painted", "bar", segs=6)
			for z in (0.3, 0.6):
				kit.box((0.84, 0.03, 0.03), (0, 0.08, z), "steel_painted", "cross_bar")
		kit.socket("wall", (0, 0, 0))
	elif what == "visit_table":
		with kit.stage("main"):
			kit.cyl(0.45, 0.04, (0, 0, 0.72), "laminate_grey", "top", segs=20)
			kit.cyl(0.06, 0.7, (0, 0, 0.35), "steel_painted", "column", segs=10)
			kit.cyl(0.3, 0.02, (0, 0, 0.01), "steel_painted", "floor_plate", segs=16)
			for i, a in enumerate((0, 90, 180, 270)):
				c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
				kit.rod((0, 0, 0.2), (0.85 * c, 0.85 * s, 0.2), 0.025, "steel_painted", "arm", segs=6)
				kit.rod((0.85 * c, 0.85 * s, 0.2), (0.85 * c, 0.85 * s, 0.42), 0.025, "steel_painted", "seat_post", segs=6)
				kit.cyl(0.17, 0.04, (0.85 * c, 0.85 * s, 0.44), "plastic_red" if i == 0 else "plastic_blue", "seat", segs=14)
	elif what == "officer_podium":
		with kit.stage("main"):
			with kit.hollow(0.2):
				kit.box((1.6, 1.4, 0.3), (0, 0, 0.15), "plastic_grey", "plinth")
			counter(1.4, 0.6, 1.1, "laminate_grey", "laminate_grey", at=(0, 0.3), kick=False)
			kit.box((0.4, 0.03, 0.28), (0, 0.25, 1.26), "screen", "monitor")
			chair((0, -0.25), 0, "fabric_blue", BLACK, sh=0.75)
	elif what == "turnstile":
		with kit.stage("frame"):
			kit.frame(1.5, 2.3, 0.08, 1.3, (0, 0, 0), "steel_galvanised", "portal")
			for sx in (-1, 1):
				for i in range(7):
					kit.rod((sx * 0.7, -0.6 + i * 0.2, 0.05), (sx * 0.7, -0.6 + i * 0.2, 2.2), 0.015, "steel_galvanised", "cage_bar", segs=5)
		with kit.stage("rotor"):
			kit.rod((0, 0, 0.05), (0, 0, 2.2), 0.04, "steel_galvanised", "rotor_shaft", segs=8)
			for a in (30, 150, 270):
				c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
				for k in range(9):
					kit.rod((0, 0, 0.25 + k * 0.22), (0.62 * c, 0.62 * s, 0.25 + k * 0.22), 0.016, "steel_galvanised", "rotor_arm", segs=5)
		kit.socket("rotor", (0, 0, 0))
	elif what == "fence":
		with kit.stage("main"):
			for sx in (-1, 1):
				kit.box((0.1, 0.1, 5.2), (sx * 1.5, 0, 2.6), "steel_galvanised", "post")
			kit.grid_bars(2.9, 5.0, (0, 0, 2.6), 28, 12, 0.004, "steel_galvanised", "weld_mesh")
			kit.sweep([(-1.5, 0, 5.2), (-1.5, 0.3, 5.6)], kit.rect(0.06, 0.06), "steel_galvanised", "crank")
			kit.sweep([(1.5, 0, 5.2), (1.5, 0.3, 5.6)], kit.rect(0.06, 0.06), "steel_galvanised", "crank")
			pts = []
			for i in range(49):
				t = i / 48
				a = t * 2 * math.pi * 8
				pts.append((-1.5 + 3.0 * t, 0.3 + 0.22 * math.cos(a), 5.75 + 0.22 * math.sin(a)))
			kit.sweep(pts, kit.circle(0.006, 4), "steel_galvanised", "razor_coil")
		kit.socket("next", (3.0, 0, 0))
	elif what == "wall":
		with kit.stage("main"):
			with kit.hollow(0.9):
				kit.box((4.0, 0.4, 5.2), (0, 0, 2.6), "concrete", "wall")
			kit.cyl(0.45, 4.0, (0, 0, 5.3), "concrete", "anti_climb_beak", axis="x", segs=16)
		kit.socket("next", (4.0, 0, 0))
	elif what == "watch_tower":
		with kit.stage("main"):
			with kit.hollow(0.3):
				kit.box((2.6, 2.6, 8.0), (0, 0, 4.0), "concrete", "shaft")
				kit.box((4.0, 4.0, 0.3), (0, 0, 8.15), "concrete", "deck")
				kit.box((3.6, 3.6, 0.9), (0, 0, 8.75), "concrete", "upstand")
				kit.box((4.4, 4.4, 0.25), (0, 0, 11.0), "concrete", "roof")
			for sx in (-1, 1):
				kit.box((3.5, 0.03, 1.6), (0, sx * 1.78, 10.0), "glass", "glazing")
				kit.box((0.03, 3.5, 1.6), (sx * 1.78, 0, 10.0), "glass", "glazing")
				for sy in (-1, 1):
					kit.box((0.12, 0.12, 1.7), (sx * 1.78, sy * 1.78, 10.05), "steel_painted", "corner_post")
			kit.box((0.9, 0.05, 2.0), (0, 1.32, 1.0), "plastic_blue", "door")
			kit.cyl(0.18, 0.3, (1.7, 1.7, 11.3), BLACK, "searchlight", segs=10)
	elif what == "sally_gate":
		with kit.stage("frame"):
			for sx in (-1, 1):
				kit.box((0.25, 0.25, 5.4), (sx * 2.6, 0, 2.7), "steel_painted", "gate_post")
			kit.box((5.45, 0.25, 0.3), (0, 0, 5.25), "steel_painted", "header")
		with kit.stage("leaf"):
			kit.frame(4.9, 4.9, 0.1, 0.08, (0, 0, 0.1), "plastic_blue", "leaf_frame")
			kit.box((4.7, 0.04, 4.7), (0, 0, 2.55), "plastic_blue", "sheeting")
			for z in (1.2, 2.5, 3.8):
				kit.box((4.7, 0.09, 0.1), (0, 0, z), "plastic_blue", "leaf_rail")
		kit.socket("leaf", (0, 0, 0))


# --- stations -------------------------------------------------------------------------------

def station(what="bench"):
	if what == "bench":
		with kit.stage("main"):
			for i in range(4):
				x = -0.9 + i * 0.6
				kit.rounded_box((0.52, 0.45, 0.04), (x, 0.02, 0.44), "steel_stainless", "seat", radius=0.015)
				kit.rounded_box((0.52, 0.04, 0.4), (x, -0.22, 0.68), "steel_stainless", "back", radius=0.015, rot=(-10, 0, 0))
			kit.box((2.4, 0.1, 0.06), (0, 0, 0.39), "steel_painted", "beam")
			for sx in (-1, 1):
				kit.box((0.06, 0.06, 0.36), (sx * 0.95, 0, 0.18), "steel_painted", "leg")
				kit.box((0.08, 0.5, 0.03), (sx * 0.95, 0, 0.015), "steel_painted", "foot")
				kit.box((0.04, 0.4, 0.2), (sx * 1.2, 0.02, 0.55), "steel_painted", "arm")
	elif what == "canopy_bay":
		with kit.stage("frame"):
			kit.i_section(0.2, 0.25, 0.02, 0.012, 4.2, (0, 0, 2.1), "steel_painted", "column", axis="z")
			for sy in (-1, 1):
				kit.strut((0, 0, 4.2), (0, sy * 3.0, 4.6), 0.15, 0.25, "steel_painted", "cantilever")
				kit.rod((0, 0, 3.0), (0, sy * 1.6, 4.35), 0.03, "steel_painted", "strut", segs=6)
			kit.box((0.5, 0.5, 0.03), (0, 0, 0.015), "steel_painted", "base_plate")
		with kit.stage("roof"):
			for sy in (-1, 1):
				kit.prism([(sy * 0.0, 4.36), (sy * 3.1, 4.77), (sy * 3.1, 4.81), (sy * 0.0, 4.4)] if sy > 0 else [(-3.1, 4.77), (0, 4.36), (0, 4.4), (-3.1, 4.81)], 6.0, (0, 0, 0), "glass", "glazing", axis="x")
				kit.box((6.0, 0.12, 0.12), (0, sy * 3.1, 4.72), "steel_painted", "gutter_beam")
			kit.box((6.0, 0.3, 0.1), (0, 0, 4.3), "steel_painted", "valley_gutter")
		kit.socket("next", (6.0, 0, 0))
	elif what == "departure_board":
		with kit.stage("main"):
			for sx in (-1, 1):
				kit.rod((sx * 0.8, 0, 3.6), (sx * 0.8, 0, 2.95), 0.02, "steel_painted", "hanger", segs=6)
			with kit.hollow(0.2):
				kit.box((2.2, 0.16, 0.75), (0, 0, 2.6), BLACK, "case")
			for sy in (-1, 1):
				kit.box((2.1, 0.01, 0.65), (0, sy * 0.082, 2.6), "screen", "display")
				for r in range(4):
					kit.box((1.9, 0.004, 0.06), (0, sy * 0.089, 2.82 - r * 0.14), "hivis_orange", "text_row")
		kit.socket("ceiling", (0, 0, 3.6))
	elif what == "ticket_machine":
		with kit.stage("main"):
			with kit.hollow(0.3):
				kit.box((0.75, 0.5, 1.85), (0, 0, 0.925), "plastic_grey", "body")
			kit.box((0.6, 0.012, 0.45), (0, 0.253, 1.35), "screen", "touch_screen")
			kit.box((0.75, 0.02, 0.25), (0, 0.255, 1.72), "plastic_red", "header")
			kit.box((0.14, 0.04, 0.2), (0.2, 0.26, 0.95), BLACK, "card_reader")
			kit.box((0.4, 0.06, 0.12), (-0.1, 0.25, 0.65), BLACK, "ticket_tray")
	elif what == "ticket_office":
		with kit.stage("main"):
			counter(3.0, 0.6, 1.0, "laminate_grey", "laminate_white")
			kit.box((3.0, 0.03, 1.2), (0, 0.2, 1.6), "glass", "screen")
			for x in (-0.75, 0.75):
				kit.box((0.5, 0.25, 0.012), (x, 0.3, 1.03), STEEL, "tray")
				kit.box((0.45, 0.03, 0.3), (x, -0.2, 1.2), "screen", "monitor")
			kit.box((0.06, 0.06, 1.2), (0, 0.2, 1.6), STEEL, "mullion")
			kit.box((3.0, 0.15, 0.3), (0, 0.2, 2.35), "plastic_blue", "sign")
	elif what == "shelter":
		with kit.stage("main"):
			for sx in (-1, 1):
				for sy in (-1, 1):
					kit.box((0.08, 0.08, 2.4), (sx * 1.9, sy * 0.7, 1.2), "steel_painted", "post")
				kit.box((0.02, 1.3, 1.9), (sx * 1.9, 0, 1.15), "glass", "end_screen")
			kit.box((3.7, 0.02, 1.9), (0, -0.7, 1.15), "glass", "back_screen")
			kit.prism([(-0.9, 2.4), (0.9, 2.5), (0.9, 2.56), (-0.9, 2.46)], 4.1, (0, 0, 0), "aluminium", "roof", axis="x")
			kit.box((3.0, 0.4, 0.04), (0, -0.4, 0.45), OAK, "perch_seat")
			for x in (-1.2, 0, 1.2):
				kit.box((0.05, 0.3, 0.43), (x, -0.4, 0.215), "steel_painted", "seat_leg")
	elif what == "clock":
		with kit.stage("main"):
			kit.rod((0, 0, 0), (0, 0, -0.5), 0.02, "steel_painted", "drop_rod", segs=6)
			kit.cyl(0.4, 0.2, (0, 0, -0.9), BLACK, "case", axis="y", segs=24)
			for sy in (-1, 1):
				kit.cyl(0.36, 0.012, (0, sy * 0.1, -0.9), "paint_white", "face", axis="y", segs=24)
				kit.box((0.02, 0.008, 0.26), (0.0, sy * 0.108, -0.78), BLACK, "minute_hand")
				kit.box((0.16, 0.008, 0.025), (0.08, sy * 0.108, -0.9), BLACK, "hour_hand")
		kit.socket("ceiling", (0, 0, 0))
	elif what == "totem":
		with kit.stage("main"):
			with kit.hollow(0.2):
				kit.box((0.9, 0.2, 3.6), (0, 0, 1.8), "plastic_blue", "totem")
			kit.box((0.7, 0.21, 0.7), (0, 0, 3.1), "plastic_red", "logo")
			kit.box((0.8, 0.21, 1.2), (0, 0, 1.6), "paint_white", "map_panel")
	elif what == "help_point":
		with kit.stage("main"):
			with kit.hollow(0.3):
				kit.box((0.4, 0.2, 1.7), (0, 0, 0.85), "plastic_blue", "post")
			kit.cyl(0.05, 0.02, (0, 0.105, 1.2), "plastic_green", "info_button", axis="y", segs=10)
			kit.cyl(0.05, 0.02, (0, 0.105, 1.4), "plastic_red", "emergency_button", axis="y", segs=10)
			kit.box((0.2, 0.01, 0.1), (0, 0.103, 1.57), BLACK, "speaker")
	elif what == "buffer_stop":
		with kit.stage("main"):
			for sx in (-1, 1):
				kit.strut((sx * 0.72, -1.4, 0.15), (sx * 0.72, 0, 1.1), 0.12, 0.15, "plastic_red", "raker")
				kit.box((0.12, 0.15, 1.1), (sx * 0.72, 0, 0.55), "plastic_red", "upright")
				kit.cyl(0.2, 0.25, (sx * 0.72, 0.2, 1.0), BLACK, "buffer", axis="y", segs=12)
			kit.box((2.4, 0.2, 0.3), (0, 0, 1.0), "paint_white", "beam")
			kit.cyl(0.08, 0.1, (0, 0.12, 1.3), "plastic_red", "stop_lamp", axis="y", segs=10)
	elif what == "info_desk":
		with kit.stage("main"):
			pts = [(1.4 * math.cos(math.radians(a)), 1.4 * math.sin(math.radians(a))) for a in range(0, 181, 20)]
			inner = [(0.9 * math.cos(math.radians(a)), 0.9 * math.sin(math.radians(a))) for a in range(180, -1, -20)]
			with kit.hollow(0.2):
				kit.prism(pts + inner, 1.05, (0, 0, 0.525), "laminate_white", "desk", axis="z")
			kit.prism([(p[0] * 1.03, p[1] * 1.03) for p in pts] + [(p[0] * 0.97, p[1] * 0.97) for p in inner], 0.04, (0, 0, 1.07), "plastic_blue", "top", axis="z")
			kit.cyl(0.03, 1.4, (0, 0.2, 1.7), STEEL, "sign_post", segs=8)
			kit.cyl(0.3, 0.08, (0, 0.2, 2.6), "plastic_blue", "info_sign", axis="y", segs=20)
			kit.box((0.06, 0.09, 0.3), (0, 0.2, 2.57), "paint_white", "info_letter")
	elif what == "kiosk":
		with kit.stage("main"):
			with kit.hollow(0.1):
				kit.box((3.0, 2.2, 1.0), (0, 0, 0.5), "plastic_green", "base")
				kit.box((3.2, 2.4, 0.25), (0, 0, 2.6), "plastic_green", "fascia")
			for sx in (-1, 1):
				for sy in (-1, 1):
					kit.box((0.1, 0.1, 1.5), (sx * 1.45, sy * 1.05, 1.75), STEEL, "post")
			kit.box((3.0, 0.5, 0.04), (0, 1.0, 1.02), STEEL, "serving_shelf")
			kit.box((1.2, 0.5, 0.7), (-0.6, -0.6, 1.35), STEEL, "coffee_machine")
			with kit.hollow(0.1):
				kit.box((1.0, 0.45, 0.4), (0.8, 0.85, 1.24), "glass", "pastry_case")
			kit.box((2.4, 0.03, 0.2), (0, 1.21, 2.6), "glow", "sign")
	elif what == "atm":
		with kit.stage("main"):
			with kit.hollow(0.4):
				kit.box((0.6, 0.6, 1.6), (0, 0, 0.8), "plastic_blue", "body")
			kit.box((0.36, 0.02, 0.3), (0, 0.3, 1.25), "screen", "screen", rot=(-15, 0, 0))
			kit.box((0.3, 0.14, 0.02), (0, 0.33, 0.98), STEEL, "keypad", rot=(-20, 0, 0))
			kit.box((0.24, 0.02, 0.03), (0, 0.305, 0.8), BLACK, "cash_slot")
	elif what == "bus_shelter":
		with kit.stage("main"):
			for sx in (-1, 1):
				kit.box((0.1, 0.1, 2.6), (sx * 1.9, -0.6, 1.3), "steel_painted", "post")
				kit.box((0.02, 1.2, 2.0), (sx * 1.95, 0, 1.2), "glass", "end_screen")
			kit.box((3.8, 0.02, 2.0), (0, -0.62, 1.2), "glass", "back_screen")
			kit.prism([(-0.8, 2.55), (1.2, 2.7), (1.2, 2.78), (-0.8, 2.63)], 4.2, (0, 0, 0), "aluminium", "roof", axis="x")
			kit.box((2.6, 0.3, 0.05), (0, -0.4, 0.5), "plastic_red", "perch")
			kit.box((1.2, 0.04, 1.8), (1.2, -0.58, 1.2), "paint_white", "timetable_case")
			kit.box((4.0, 0.12, 0.2), (0, 1.15, 2.7), "plastic_red", "fascia")
	elif what == "bus_stand":
		with kit.stage("main"):
			kit.rod((0, 0, 0), (0, 0, 3.0), 0.04, "steel_galvanised", "pole", segs=8)
			kit.box((0.5, 0.04, 0.5), (0.27, 0, 2.7), "plastic_red", "flag")
			kit.box((0.4, 0.045, 0.2), (0.27, 0, 2.3), "paint_white", "stand_letter")
			kit.box((0.35, 0.06, 0.5), (0, 0.05, 1.5), "paint_white", "timetable")
	elif what == "stand_display":
		with kit.stage("main"):
			kit.rod((0, 0, 0), (0, 0, 2.6), 0.05, "steel_painted", "pole", segs=8)
			with kit.hollow(0.2):
				kit.box((1.0, 0.14, 0.5), (0, 0, 2.85), BLACK, "case")
			kit.box((0.9, 0.01, 0.4), (0, 0.072, 2.85), "screen", "display")
			for r in range(3):
				kit.box((0.8, 0.004, 0.05), (0, 0.078, 2.97 - r * 0.12), "hivis_orange", "text_row")
	elif what == "queue_rail":
		with kit.stage("main"):
			for x in (-1.2, 0, 1.2):
				kit.rod((x, 0, 0), (x, 0, 1.05), 0.025, "steel_stainless", "post", segs=8)
			for z in (0.55, 1.05):
				kit.rod((-1.2, 0, z), (1.2, 0, z), 0.022, "steel_stainless", "rail", segs=8)
	elif what == "drive_through_bay":
		with kit.stage("main"):
			kit.prism([(0, 0), (4.0, 0), (4.0, 0.15), (0, 0.15)], 12.0, (0, 0, 0), "paving", "island", axis="y", rot=(0, 0, 0))
			for y in (-5.5, 5.5):
				kit.cyl(0.08, 0.9, (0.3, y, 0.6), "plastic_yellow", "bollard", segs=10)
		kit.socket("next", (4.0, 0, 0))


# --- shops ----------------------------------------------------------------------------------

def shop(what="counter"):
	if what == "counter":
		with kit.stage("main"):
			counter(2.0, 0.6, 0.95, "laminate_white", "laminate_grey")
			kit.box((0.4, 0.4, 0.3), (-0.6, 0, 1.1), BLACK, "till")
			kit.box((0.3, 0.02, 0.22), (-0.6, -0.15, 1.36), "screen", "till_screen")
			kit.box((0.5, 0.3, 0.3), (0.5, 0.1, 1.1), "plastic_yellow", "sweets_stand")
		with kit.stage("gantry"):
			with kit.hollow(0.2):
				kit.box((2.0, 0.35, 1.3), (0, -1.0, 1.55), "plastic_grey", "gantry")
			kit.box((1.9, 0.012, 1.2), (0, -0.82, 1.55), "plastic_grey", "gantry_shutters")
			kit.box((2.0, 0.45, 0.9), (0, -1.0, 0.45), "laminate_white", "back_unit")
	elif what == "chiller":
		with kit.stage("main"):
			with kit.hollow(0.2):
				kit.box((1.9, 0.75, 2.0), (0, -0.1, 1.0), "paint_white", "case")
			kit.box((1.8, 0.5, 1.5), (0, 0.06, 1.1), BLACK, "well")
			for r in range(4):
				z = 0.45 + r * 0.38
				kit.box((1.76, 0.45, 0.02), (0, 0.1, z), "paint_white", "shelf")
				for i in range(12):
					kit.box((0.11, 0.3, 0.22), (-0.8 + i * 0.145, 0.12, z + 0.12), ("plastic_white", "plastic_red", "plastic_blue", "plastic_green", "plastic_yellow")[(i + r) % 5], "pack")
			kit.box((1.9, 0.76, 0.2), (0, -0.1, 1.9), "plastic_blue", "canopy")
			kit.box((1.8, 0.03, 0.05), (0, 0.27, 1.82), "glow", "strip_light")
	elif what == "freezer":
		with kit.stage("main"):
			with kit.hollow(0.3):
				kit.box((1.8, 0.85, 0.85), (0, 0, 0.425), "paint_white", "chest")
			for sx in (-1, 1):
				kit.box((0.88, 0.8, 0.012), (sx * 0.45, 0, 0.862), "glass", "lid")
			kit.box((1.82, 0.87, 0.05), (0, 0, 0.845), "plastic_blue", "rim")
	elif what == "newspaper_stand":
		with kit.stage("main"):
			with kit.hollow(0.1):
				kit.prism([(-0.25, 0), (0.25, 0), (0.25, 0.3), (-0.2, 1.4), (-0.25, 1.4)], 1.2, (0, 0, 0), "steel_painted", "stand", axis="x")
			for r in range(4):
				for i in range(4):
					kit.box((0.26, 0.02, 0.3), (-0.45 + i * 0.3, 0.2 - r * 0.105, 0.3 + r * 0.28), ("paint_white", "plastic_red", "paint_white", "plastic_blue")[(i + r) % 4], "paper", rot=(-22, 0, 0))
	elif what == "post_office":
		with kit.stage("main"):
			counter(1.8, 0.6, 1.0, "plastic_red", "laminate_grey")
			kit.box((1.8, 0.03, 1.1), (0, 0.2, 1.57), "glass", "screen")
			kit.box((0.4, 0.3, 0.1), (0, 0.32, 1.05), STEEL, "parcel_hatch")
			kit.box((0.35, 0.35, 0.08), (-0.5, -0.05, 1.05), STEEL, "scales")
			kit.box((1.8, 0.15, 0.3), (0, 0.2, 2.27), "plastic_red", "sign")
	elif what == "lottery_stand":
		with kit.stage("main"):
			with kit.hollow(0.2):
				kit.box((0.6, 0.45, 1.1), (0, 0, 0.55), "plastic_blue", "stand")
			kit.box((0.6, 0.5, 0.03), (0, 0, 1.13), "plastic_blue", "write_shelf", rot=(15, 0, 0))
			kit.box((0.6, 0.04, 0.5), (0, -0.2, 1.5), "plastic_yellow", "header")
	elif what == "awning":
		with kit.stage("main"):
			kit.prism([(0, 0), (1.5, -0.5), (1.5, -0.7), (1.47, -0.7), (1.47, -0.52), (0, -0.03)], 4.0, (0, 0, 0), "fabric_green", "awning", axis="x")
			for sx in (-1, 1):
				kit.rod((sx * 1.95, 0, -0.9), (sx * 1.95, 1.47, -0.52), 0.015, STEEL, "arm", segs=6)
		kit.socket("wall", (0, 0, 0))
	elif what == "trolley_bay":
		with kit.stage("main"):
			for sx in (-1, 1):
				kit.sweep([(sx * 1.2, -2.4, 0), (sx * 1.2, -2.4, 1.0), (sx * 1.2, 2.4, 1.0), (sx * 1.2, 2.4, 0)], kit.circle(0.03, 8), "steel_galvanised", "rail")
			kit.prism([(-1.4, 2.2), (1.4, 2.2), (1.4, 2.26), (0, 2.6), (-1.4, 2.26)], 5.0, (0, 0, 0), "glass", "canopy", axis="y")
			for sx in (-1, 1):
				for y in (-2.4, 2.4):
					kit.rod((sx * 1.35, y, 0), (sx * 1.35, y, 2.2), 0.04, "steel_galvanised", "post", segs=8)
			for i in range(6):
				y = -1.8 + i * 0.35
				kit.grid_bars(0.5, 0.5, (0, y, 0.75), 5, 4, 0.006, "steel_galvanised", "trolley_basket")
				kit.rod((-0.25, y - 0.1, 1.02), (0.25, y - 0.1, 1.02), 0.015, "plastic_red", "trolley_handle", segs=6)
	elif what == "bulk_rack":
		with kit.stage("frame"):
			for sx in (-1, 1):
				for sy in (-1, 1):
					kit.box((0.09, 0.07, 5.0), (sx * 1.4, sy * 0.5, 2.5), "plastic_blue", "upright")
			for z in (0.15, 1.8, 3.4):
				for sy in (-1, 1):
					kit.box((2.8, 0.05, 0.12), (0, sy * 0.5, z), "hivis_orange", "beam")
		with kit.stage("stock"):
			for k, z in enumerate((0.21, 1.86, 3.46)):
				for sx in (-1, 1):
					kit.box((1.2, 1.0, 0.12), (sx * 0.68, 0, z + 0.06), "softwood", "pallet")
					with kit.hollow(0.5):
						kit.box((1.1, 0.95, 1.1 if k < 2 else 0.8), (sx * 0.68, 0, z + 0.12 + (1.1 if k < 2 else 0.8) / 2), ("plywood", "softwood", "plastic_white")[(k + (sx > 0)) % 3], "stock")
	elif what == "timber_rack":
		with kit.stage("frame"):
			for x in (-1.5, 0, 1.5):
				kit.box((0.1, 0.1, 3.0), (x, -0.5, 1.5), "plastic_blue", "upright")
				kit.box((0.1, 1.2, 0.1), (x, 0, 0.05), "plastic_blue", "foot")
				for z in (0.6, 1.4, 2.2):
					kit.strut((x, -0.5, z), (x, 0.5, z + 0.1), 0.06, 0.08, "plastic_blue", "arm")
		with kit.stage("stock"):
			for k, z in enumerate((0.7, 1.5, 2.3)):
				for i in range(6):
					kit.box((3.6 + 0.2 * (i % 2), 0.14, 0.045), (0, -0.3 + i * 0.15, z + 0.05 + 0.047 * (i % 3)), ("softwood", "plywood", "glulam")[k], "board")


# --- warehouse and loading ------------------------------------------------------------------

def depot(what="dock_shelter"):
	if what == "dock_shelter":
		with kit.stage("main"):
			kit.frame(3.4, 3.6, 0.3, 0.6, (0, 0.3, 0.9), BLACK, "shelter_frame")
			for sx in (-1, 1):
				kit.box((0.6, 0.03, 3.0), (sx * 1.15, 0.6, 2.7), "rubber", "side_curtain")
			kit.box((2.9, 0.03, 0.9), (0, 0.6, 3.9), "rubber", "head_curtain")
			for sx in (-1, 1):
				kit.box((0.04, 0.035, 2.6), (sx * 1.25, 0.615, 2.6), "hivis_yellow", "guide_stripe")
				with kit.hollow(0.6):
					kit.box((0.25, 0.15, 0.5), (sx * 1.1, 0.08, 0.95), "rubber", "bumper")
		kit.socket("wall", (0, 0, 0))
	elif what == "dock_light":
		with kit.stage("main"):
			kit.box((0.15, 0.06, 0.25), (0, 0.03, 0), "plastic_yellow", "bracket")
			kit.rod((0, 0.06, 0), (0.5, 0.35, 0.1), 0.02, "plastic_yellow", "arm", segs=6)
			kit.rod((0.5, 0.35, 0.1), (0.9, 0.9, -0.05), 0.02, "plastic_yellow", "arm", segs=6)
			kit.cyl(0.11, 0.2, (0.95, 0.98, -0.07), "plastic_yellow", "lamp", axis="y", segs=12)
			kit.cyl(0.09, 0.02, (0.95, 1.09, -0.07), "glow", "lens", axis="y", segs=12)
		kit.socket("wall", (0, 0, 0))
	elif what == "dock_signal":
		with kit.stage("main"):
			with kit.hollow(0.3):
				kit.box((0.2, 0.15, 0.42), (0, 0.075, 0), BLACK, "housing")
			kit.cyl(0.07, 0.02, (0, 0.155, 0.1), "plastic_red", "red_lamp", axis="y", segs=12)
			kit.cyl(0.07, 0.02, (0, 0.155, -0.1), "plastic_green", "green_lamp", axis="y", segs=12)
		kit.socket("wall", (0, 0, 0))
	elif what == "wheel_chock":
		with kit.stage("main"):
			kit.prism([(-0.12, 0), (0.12, 0), (0.12, 0.05), (-0.08, 0.2), (-0.12, 0.2)], 0.2, (0, 0, 0), "rubber", "chock", axis="x")
			kit.box((0.04, 0.26, 0.03), (0, 0, 0.1), "hivis_yellow", "stripe")
	elif what == "dock_platform":
		with kit.stage("main"):
			with kit.hollow(0.5):
				kit.box((6.0, 3.0, 1.2), (0, 0, 0.6), "concrete", "platform")
			kit.box((6.0, 0.12, 0.12), (0, 1.5, 1.14), "plastic_yellow", "edge_angle")
			for x in (-2.0, 0, 2.0):
				with kit.hollow(0.6):
					kit.box((0.3, 0.12, 0.5), (x, 1.56, 0.9), "rubber", "bumper")
			for i in range(6):
				kit.box((0.8, 0.3, 0.2), (3.4, 1.2 - i * 0.3, 1.1 - i * 0.2), "concrete", "step")
	elif what == "strip_curtain":
		with kit.stage("main"):
			kit.box((3.0, 0.08, 0.1), (0, 0, 3.45), "steel_galvanised", "rail")
			for i in range(15):
				kit.box((0.22, 0.004 + 0.0, 3.4), (-1.4 + i * 0.2, 0.012 * (i % 2), 1.7), "glass", "strip")
		kit.socket("wall", (0, 0, 0))
	elif what == "roll_cage":
		with kit.stage("main"):
			kit.box((0.8, 0.7, 0.04), (0, 0, 0.17), "steel_galvanised", "base")
			for sx in (-1, 1):
				kit.grid_bars(0.7, 1.5, (sx * 0.4, 0, 0.95), 4, 8, 0.008, "steel_galvanised", "side", plane="yz")
			kit.grid_bars(0.8, 1.5, (0, -0.35, 0.95), 5, 8, 0.008, "steel_galvanised", "back")
			for sx in (-1, 1):
				for sy in (-1, 1):
					kit.cyl(0.06, 0.04, (sx * 0.33, sy * 0.28, 0.06), "rubber", "castor", axis="x", segs=10)
			for k in range(3):
				with kit.hollow(0.4):
					kit.box((0.7, 0.6, 0.35), (0, 0, 0.37 + k * 0.36), ("plywood", "softwood", "plastic_white")[k], "carton")
	elif what == "conveyor":
		with kit.stage("main"):
			for sx in (-1, 1):
				kit.box((0.05, 3.0, 0.12), (sx * 0.35, 0, 0.75), "steel_galvanised", "side_rail")
				for y in (-1.3, 1.3):
					kit.box((0.05, 0.05, 0.7), (sx * 0.35, y, 0.35), "steel_galvanised", "leg")
			for i in range(24):
				kit.cyl(0.025, 0.64, (0, -1.44 + i * 0.125, 0.78), "steel_stainless", "roller", axis="x", segs=8)
			with kit.hollow(0.3):
				kit.box((0.5, 0.4, 0.3), (0, -0.4, 0.955), "plywood", "carton")
				kit.box((0.4, 0.5, 0.25), (0, 0.6, 0.93), "softwood", "carton")
		kit.socket("next", (0, 3.0, 0))
	elif what == "packing_bench":
		with kit.stage("main"):
			table(1.8, 0.8, 0.9, "plywood", "steel_painted")
			kit.box((1.8, 0.3, 0.03), (0, -0.25, 1.5), "plywood", "top_shelf")
			for sx in (-1, 1):
				kit.box((0.04, 0.04, 0.9), (sx * 0.86, -0.36, 1.35), "steel_painted", "shelf_post")
			kit.cyl(0.12, 0.5, (0.5, -0.25, 1.64), "softwood", "paper_roll", axis="x", segs=12)
			kit.box((0.4, 0.3, 0.25), (-0.4, 0, 1.025), "plywood", "carton")
			kit.cyl(0.06, 0.05, (0.2, 0.2, 0.925), "softwood", "tape", segs=10)
	elif what == "charger":
		with kit.stage("main"):
			with kit.hollow(0.5):
				kit.box((0.6, 0.4, 0.9), (0, 0, 1.0), "plastic_yellow", "charger")
			kit.box((0.3, 0.01, 0.15), (0, 0.205, 1.25), "screen", "display")
			kit.sweep([(0.2, 0.2, 0.7), (0.3, 0.5, 0.3), (0.5, 0.8, 0.1), (0.9, 0.9, 0.08)], kit.circle(0.02, 6), BLACK, "cable")
			kit.box((0.5, 0.05, 0.08), (0, -0.18, 0.5), "steel_painted", "wall_bracket")
	elif what == "mezzanine":
		with kit.stage("frame"):
			for sx in (-1, 1):
				for sy in (-1, 1):
					kit.box((0.15, 0.15, 3.0), (sx * 2.9, sy * 1.9, 1.5), "plastic_blue", "column")
				kit.i_section(0.15, 0.3, 0.015, 0.01, 4.0, (sx * 2.9, 0, 2.85), "plastic_blue", "beam", axis="y")
			for i in range(7):
				kit.i_section(0.1, 0.2, 0.012, 0.008, 5.8, (0, -1.8 + i * 0.6, 2.9), "steel_galvanised", "joist", axis="x")
		with kit.stage("deck"):
			kit.box((6.0, 4.0, 0.04), (0, 0, 3.02), "plywood", "deck")
			for sy in (-1, 1):
				for z in (3.55, 4.1):
					kit.rod((-3.0, sy * 1.97, z), (3.0, sy * 1.97, z), 0.02, "plastic_yellow", "handrail", segs=6)
				for i in range(5):
					kit.rod((-3.0 + i * 1.5, sy * 1.97, 3.04), (-3.0 + i * 1.5, sy * 1.97, 4.1), 0.02, "plastic_yellow", "rail_post", segs=6)
				kit.box((6.0, 0.02, 0.12), (0, sy * 1.97, 3.1), "plastic_yellow", "kick_board")
		with kit.stage("stair"):
			for i in range(15):
				kit.box((0.9, 0.26, 0.03), (3.5, 1.7 - i * 0.26, 3.0 - i * 0.2), "steel_galvanised", "tread")
			for sx in (-1, 1):
				kit.strut((3.5 + sx * 0.46, 1.8, 3.0), (3.5 + sx * 0.46, -2.0, 0.08), 0.03, 0.2, "plastic_blue", "stringer")
		kit.socket("deck", (0, 0, 3.04))


# --- lodge, retreat and mansion -------------------------------------------------------------

def lodge(what="hot_tub"):
	if what == "hot_tub":
		with kit.stage("main"):
			with kit.hollow(0.2):
				kit.rounded_box((2.1, 2.1, 0.9), (0, 0, 0.45), "softwood", "cabinet", radius=0.08)
			for sx in (-1, 1):
				kit.box((0.2, 2.12, 0.08), (sx * 0.96, 0, 0.9), "plastic_white", "rim")
				kit.box((1.72, 0.2, 0.08), (0, sx * 0.96, 0.9), "plastic_white", "rim")
			kit.box((1.72, 1.72, 0.02), (0, 0, 0.87), "water", "water")
			for sx in (-1, 1):
				for sy in (-1, 1):
					kit.cyl(0.03, 0.02, (sx * 0.6, sy * 0.6, 0.875), "steel_stainless", "jet", segs=8)
			kit.box((0.8, 0.5, 0.2), (0, 1.3, 0.1), "softwood", "step")
	elif what == "log_burner":
		with kit.stage("main"):
			kit.box((0.9, 0.9, 0.03), (0, 0, 0.015), "slate", "hearth")
			with kit.hollow(0.5):
				kit.box((0.5, 0.4, 0.6), (0, 0, 0.42), "cast_iron", "stove")
			kit.box((0.36, 0.012, 0.36), (0, 0.203, 0.44), "glow", "door_glass")
			kit.frame(0.42, 0.42, 0.03, 0.02, (0, 0.21, 0.23), "cast_iron", "door_frame")
			for sx in (-1, 1):
				for sy in (-1, 1):
					kit.box((0.04, 0.04, 0.12), (sx * 0.2, sy * 0.15, 0.06), "cast_iron", "foot")
			kit.cyl(0.075, 2.0, (0, -0.05, 1.72), "cast_iron", "flue", segs=12)
			for i in range(5):
				kit.rod((0.5, -0.2 + 0.0, 0.08 + i * 0.1), (0.5, 0.2, 0.08 + i * 0.1), 0.05, "bark", "log", segs=8)
	elif what == "decking":
		with kit.stage("main"):
			for i in range(20):
				kit.box((3.0, 0.14, 0.03), (0, -1.425 + i * 0.15, 0.285), "softwood", "board")
			for x in (-1.4, -0.7, 0, 0.7, 1.4):
				kit.box((0.05, 3.0, 0.15), (x, 0, 0.195), "softwood", "joist")
			for sx in (-1, 1):
				for sy in (-1, 1):
					kit.box((0.1, 0.1, 0.12), (sx * 1.4, sy * 1.4, 0.06), "concrete", "pad")
		kit.socket("next", (3.0, 0, 0))
	elif what == "deck_rail":
		with kit.stage("main"):
			for sx in (-1, 1):
				kit.box((0.09, 0.09, 1.1), (sx * 1.45, 0, 0.55), "softwood", "post")
			kit.box((3.0, 0.07, 0.04), (0, 0, 1.05), "softwood", "handrail")
			kit.box((2.8, 0.04, 0.07), (0, 0, 0.15), "softwood", "bottom_rail")
			for i in range(22):
				kit.box((0.035, 0.035, 0.85), (-1.33 + i * 0.127, 0, 0.6), "softwood", "baluster")
	elif what == "sauna":
		with kit.stage("main"):
			with kit.hollow(0.12):
				kit.box((2.2, 2.0, 2.1), (0, 0, 1.05), "softwood", "cabin")
			for i in range(13):
				kit.box((0.012, 2.02, 2.1), (-1.1 + i * 0.183, 0, 1.05), "glulam", "board_joint")
			kit.box((0.7, 0.03, 1.9), (-0.4, 1.0, 1.0), "glass", "door")
			kit.box((0.04, 0.06, 0.4), (-0.1, 1.03, 1.0), "softwood", "door_handle")
			kit.box((0.6, 0.02, 0.6), (0.55, 1.0, 1.3), "glass", "window")
			kit.box((2.3, 2.1, 0.08), (0, 0, 2.14), "softwood", "roof")
	elif what == "massage_table":
		with kit.stage("main"):
			kit.rounded_box((0.72, 1.9, 0.09), (0, 0, 0.72), "fabric_white", "pad", radius=0.035)
			kit.rounded_box((0.3, 0.3, 0.07), (0, 1.08, 0.72), "fabric_white", "face_cradle", radius=0.03)
			for sx in (-1, 1):
				for sy in (-1, 1):
					kit.rod((sx * 0.3, sy * 0.8, 0.68), (sx * 0.33, sy * 0.85, 0), 0.02, OAK, "leg", segs=6)
			kit.rounded_box((0.74, 0.9, 0.02), (0, -0.3, 0.775), "velvet_teal", "towel", radius=0.008)
	elif what == "yoga_mats":
		with kit.stage("main"):
			for i in range(4):
				kit.rounded_box((0.62, 1.75, 0.008), (-1.35 + i * 0.9, 0, 0.004), ("velvet_teal", "fabric_red", "fabric_blue", "fabric_green")[i], "mat", radius=0.003)
				kit.rounded_box((0.35, 0.2, 0.12), (-1.35 + i * 0.9, -0.6, 0.068), "fabric_grey", "bolster", radius=0.05)
	elif what == "fire_pit":
		with kit.stage("main"):
			kit.tube(0.6, 0.35, (0, 0, 0.175), "brick", "ring", wall=0.15, segs=18)
			kit.cyl(0.45, 0.1, (0, 0, 0.05), "soil", "ash", segs=14)
			for a in (0, 60, 120):
				c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
				kit.rod((-0.3 * c, -0.3 * s, 0.12), (0.3 * c, 0.3 * s, 0.3), 0.05, "bark", "log", segs=8)
			kit.sphere(0.12, (0, 0, 0.25), "glow", "embers", segs=8)
	elif what == "four_poster":
		with kit.stage("main"):
			with kit.hollow(0.3):
				kit.box((1.9, 2.1, 0.35), (0, 0, 0.3), DARK, "bed_frame")
				kit.box((1.9, 0.08, 1.3), (0, -1.05, 0.9), DARK, "headboard")
			kit.rounded_box((1.8, 2.0, 0.25), (0, 0, 0.6), "fabric_white", "mattress", radius=0.06)
			kit.rounded_box((1.84, 1.4, 0.08), (0, 0.32, 0.74), "fabric_red", "cover", radius=0.03)
			for sx in (-1, 1):
				kit.rounded_box((0.7, 0.42, 0.15), (sx * 0.45, -0.72, 0.8), "fabric_white", "pillow", radius=0.06)
				for sy in (-1, 1):
					turned_leg((sx * 0.92, sy * 1.02, 0), 2.3, 0.05)
					kit.cyl(0.07, 2.0 if sy < 0 else 0.6, (sx * 0.9, sy * 0.95, 1.25 if sy < 0 else 1.95), "fabric_red", "drape", segs=8)
				kit.box((0.06, 2.1, 0.08), (sx * 0.92, 0, 2.3), DARK, "tester_rail")
			for sy in (-1, 1):
				kit.box((1.9, 0.06, 0.08), (0, sy * 1.02, 2.3), DARK, "tester_rail")
			kit.box((1.95, 2.15, 0.25), (0, 0, 2.2), "fabric_red", "valance")
	elif what == "banquet_table":
		with kit.stage("table"):
			kit.rounded_box((4.8, 1.2, 0.06), (0, 0, 0.73), DARK, "top", radius=0.02)
			for x in (-1.7, 0, 1.7):
				turned_leg((x, 0, 0.03), 0.67, 0.11)
				kit.box((0.2, 1.0, 0.06), (x, 0, 0.03), DARK, "foot")
			for x in (-1.2, 1.2):
				kit.lathe([(0.07, 0), (0.02, 0.05), (0.02, 0.3), (0.09, 0.34)], (x, 0, 0.76), "steel_stainless", "candelabra", segs=10)
				for k in (-1, 0, 1):
					kit.cyl(0.012, 0.18, (x + k * 0.07, 0, 1.19), "paint_white", "candle", segs=6)
		with kit.stage("chairs"):
			for i in range(6):
				x = -2.0 + i * 0.8
				chair((x, 0.9), 180, RED, DARK)
				chair((x, -0.9), 0, RED, DARK)
			chair((2.75, 0), 90, RED, DARK)
			chair((-2.75, 0), -90, RED, DARK)
	elif what == "marble_fireplace":
		with kit.stage("main"):
			with kit.hollow(0.5):
				for sx in (-1, 1):
					kit.box((0.3, 0.3, 1.3), (sx * 0.85, 0, 0.65), "marble", "jamb")
				kit.box((2.0, 0.32, 0.3), (0, 0, 1.45), "marble", "frieze")
			kit.box((2.3, 0.45, 0.07), (0, 0.04, 1.635), "marble", "mantel")
			kit.box((1.4, 0.2, 1.3), (0, -0.05, 0.65), BLACK, "firebox")
			kit.box((2.2, 0.6, 0.04), (0, 0.35, 0.02), "marble", "hearth")
			kit.box((0.7, 0.3, 0.25), (0, 0.0, 0.2), "cast_iron", "grate")
			kit.box((0.5, 0.2, 0.12), (0, 0.0, 0.36), "glow", "fire")
			kit.box((1.4, 0.05, 1.6), (0, -0.12, 2.6), "mirror", "overmantel_mirror")
			kit.frame(1.6, 1.8, 0.1, 0.08, (0, -0.1, 1.7), BRASS, "gilt_frame")
	elif what == "chesterfield":
		with kit.stage("main"):
			with kit.hollow(0.3):
				kit.rounded_box((2.2, 0.9, 0.4), (0, 0, 0.3), LEATHER, "base", radius=0.06)
				kit.rounded_box((2.2, 0.25, 0.55), (0, -0.35, 0.6), LEATHER, "back", radius=0.11)
				for sx in (-1, 1):
					kit.rounded_box((0.25, 0.9, 0.55), (sx * 0.98, 0, 0.6), LEATHER, "arm", radius=0.11)
			for i in range(3):
				kit.rounded_box((0.56, 0.6, 0.14), (-0.57 + i * 0.57, 0.1, 0.54), LEATHER, "cushion", radius=0.05)
			for i in range(8):
				for k in range(2):
					kit.sphere(0.015, (-0.84 + i * 0.24, -0.225, 0.55 + k * 0.18), BRASS, "button", segs=5)
			for sx in (-1, 1):
				for sy in (-1, 1):
					kit.cyl(0.035, 0.1, (sx * 0.95, sy * 0.35, 0.05), DARK, "foot", segs=8)
	elif what == "grandfather_clock":
		with kit.stage("main"):
			with kit.hollow(0.3):
				kit.box((0.5, 0.3, 0.45), (0, 0, 0.225), DARK, "base")
				kit.box((0.36, 0.24, 1.1), (0, 0, 1.0), DARK, "trunk")
				kit.box((0.5, 0.3, 0.55), (0, 0, 1.825), DARK, "hood")
			kit.prism([(-0.28, 0), (0.28, 0), (0.2, 0.12), (0, 0.2), (-0.2, 0.12)], 0.32, (0, 0, 2.1), DARK, "pediment", axis="y")
			kit.cyl(0.18, 0.012, (0, 0.156, 1.85), "paint_white", "dial", axis="y", segs=20)
			kit.box((0.015, 0.006, 0.14), (0, 0.164, 1.91), BLACK, "hand")
			kit.box((0.22, 0.01, 0.8), (0, 0.122, 1.0), "glass", "trunk_door")
			kit.rod((0, 0.06, 1.4), (0, 0.06, 0.75), 0.006, BRASS, "pendulum_rod", segs=5)
			kit.cyl(0.07, 0.015, (0, 0.06, 0.72), BRASS, "pendulum_bob", axis="y", segs=12)
	elif what == "bust":
		with kit.stage("main"):
			with kit.hollow(0.5):
				kit.box((0.4, 0.4, 1.1), (0, 0, 0.55), "marble", "plinth")
			kit.box((0.5, 0.5, 0.06), (0, 0, 1.13), "marble", "plinth_cap")
			kit.lathe([(0.12, 0), (0.2, 0.1), (0.22, 0.25), (0.08, 0.32), (0.07, 0.4)], (0, 0, 1.16), "marble", "shoulders", segs=12, scale=(1, 0.6, 1))
			kit.sphere(0.11, (0, 0, 1.66), "marble", "head", segs=12)
	elif what == "fountain":
		with kit.stage("main"):
			kit.tube(1.8, 0.5, (0, 0, 0.25), "paving", "basin_wall", wall=0.25, segs=28)
			kit.cyl(1.6, 0.06, (0, 0, 0.36), "water", "water", segs=28)
			kit.cyl(1.6, 0.1, (0, 0, 0.05), "paving", "basin_floor", segs=28)
			kit.lathe([(0.3, 0), (0.22, 0.1), (0.12, 0.3), (0.1, 1.1), (0.2, 1.2), (0.75, 1.35), (0.78, 1.45), (0.7, 1.45), (0.15, 1.35), (0.08, 1.5), (0.07, 2.0), (0.35, 2.12), (0.36, 2.2), (0.05, 2.15)], (0, 0, 0.1), "marble", "fountain", segs=20)
			kit.cyl(0.68, 0.02, (0, 0, 1.53), "water", "bowl_water", segs=20)
	elif what == "library_wall":
		with kit.stage("main"):
			kit.frame(3.6, 3.2, 0.06, 0.4, (0, 0, 0), DARK, "frame")
			kit.box((3.6, 0.02, 3.2), (0, -0.19, 1.6), DARK, "back")
			for x in (-0.6, 0.6):
				kit.box((0.05, 0.38, 3.1), (x, 0, 1.6), DARK, "division")
			for r in range(8):
				z = 0.15 + r * 0.38
				kit.box((3.5, 0.36, 0.03), (0, 0, z), DARK, "shelf")
				for i in range(44):
					if i % 15 == 14:
						continue
					kit.box((0.065, 0.25, 0.26 + 0.03 * ((i * 5 + r) % 3)), (-1.7 + i * 0.078, -0.02, z + 0.145 + 0.015 * ((i * 5 + r) % 3)), ("fabric_red", "fabric_green", "leather_black", "glulam", "fabric_blue")[(i // 3 + r) % 5], "book")
			kit.box((3.7, 0.45, 0.12), (0, 0, 3.26), DARK, "cornice")
		with kit.stage("ladder"):
			for sx in (-1, 1):
				kit.rod((1.0 + sx * 0.2, 0.9, 0.05), (1.0 + sx * 0.2, 0.25, 2.9), 0.02, OAK, "ladder_stile", segs=6)
			for k in range(9):
				t = (k + 1) / 10
				kit.rod((0.8, 0.9 - 0.65 * t, 0.05 + 2.85 * t), (1.2, 0.9 - 0.65 * t, 0.05 + 2.85 * t), 0.014, OAK, "rung", segs=5)
			kit.rod((-1.8, 0.24, 2.9), (1.8, 0.24, 2.9), 0.015, BRASS, "ladder_rail", segs=6)


# --- council chamber ------------------------------------------------------------------------

def council(what="horseshoe"):
	if what == "horseshoe":
		with kit.stage("desk"):
			outer = [(4.0 * math.cos(math.radians(a)), 4.0 * math.sin(math.radians(a))) for a in range(-20, 201, 10)]
			inner = [(3.3 * math.cos(math.radians(a)), 3.3 * math.sin(math.radians(a))) for a in range(200, -21, -10)]
			kit.prism(outer + inner, 0.05, (0, 0, 0.74), DARK, "desk_top", axis="z")
			with kit.hollow(0.2):
				kit.prism([(3.35 * math.cos(math.radians(a)), 3.35 * math.sin(math.radians(a))) for a in range(-20, 201, 10)] + [(3.3 * math.cos(math.radians(a)), 3.3 * math.sin(math.radians(a))) for a in range(200, -21, -10)], 0.72, (0, 0, 0.36), DARK, "modesty", axis="z")
		with kit.stage("seats"):
			for i in range(12):
				a = -12 + i * 204 / 11
				c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
				chair((4.45 * c, 4.45 * s), a + 90, LEATHER, DARK)
				kit.rod((3.75 * c, 3.75 * s, 0.77), (3.6 * c, 3.6 * s, 1.0), 0.006, BLACK, "microphone", segs=5)
				kit.box((0.1, 0.1, 0.03), (3.75 * c, 3.75 * s, 0.78), BLACK, "mic_base")
	elif what == "dais":
		with kit.stage("main"):
			with kit.hollow(0.3):
				kit.box((4.0, 2.0, 0.4), (0, -0.3, 0.2), "carpet", "dais")
			panelled(3.6, 0.7, 1.0, (0, 0.2, 0.4))
			for x in (-1.1, 0, 1.1):
				with kit.hollow(0.3):
					kit.rounded_box((0.7, 0.12, 1.3 if x else 1.7), (x, -0.9, 1.05 if x else 1.25), RED, "chair_back", radius=0.05)
					kit.rounded_box((0.66, 0.6, 0.14), (x, -0.6, 0.9), RED, "chair_seat", radius=0.05)
					kit.box((0.6, 0.55, 0.43), (x, -0.6, 0.615), DARK, "chair_base")
			kit.cyl(0.35, 0.06, (0, -0.96, 2.05), BRASS, "crest", axis="y", segs=20)
	elif what == "gallery_seats":
		with kit.stage("main"):
			for r in range(3):
				if r:
					with kit.hollow(0.3):
						kit.box((4.5, 0.9, r * 0.25), (0, -r * 0.9, r * 0.125), "carpet", "step")
				_row_at(8, -r * 0.9, r * 0.25, "fabric_blue")
	elif what == "vote_display":
		with kit.stage("main"):
			with kit.hollow(0.2):
				kit.box((2.4, 0.12, 1.4), (0, 0.06, 0), BLACK, "case")
			kit.box((2.3, 0.01, 1.3), (0, 0.125, 0), "screen", "display")
			for i in range(3):
				kit.box((0.5, 0.006, 0.9 - i * 0.25), (-0.7 + i * 0.7, 0.13, -0.6 + (0.9 - i * 0.25) / 2 + 0.05), ("plastic_green", "plastic_red", "plastic_yellow")[i], "bar")
		kit.socket("wall", (0, 0, 0))


# --- registration ---------------------------------------------------------------------------

for _w, _l, _kw in (("bar_counter", "Pub bar counter with hand pulls, 2.4 m", {}), ("bar_counter_long", "Pub bar counter, 4.8 m", {"w": 4.8}), ("back_bar", "Back bar with mirror and optics, 2.4 m", {}),
		("back_bar_long", "Back bar, 4.8 m", {"w": 4.8}), ("bottle_fridge", "Bottle fridge", {}), ("keg", "Beer keg", {}), ("cask", "Cask on a stillage", {}),
		("table", "Pub table, round", {}), ("stool", "Pub stool", {}), ("booth", "Booth with table", {}), ("fruit_machine", "Fruit machine", {}),
		("dartboard", "Dartboard cabinet", {}), ("pool_table", "Pool table", {}), ("snooker_table", "Snooker table, full size", {}), ("jukebox", "Jukebox", {}),
		("fireplace", "Brick fireplace with fire", {}), ("sign", "Hanging pub sign", {}), ("picnic_bench", "Beer garden picnic bench", {})):
	reg("hospitality.pub." + _w, pub, _l, "pub", "bar", what=_w.replace("_long", ""), **_kw)
for _w, _l in (("laid_table_2", "Laid restaurant table for two"), ("laid_table_4", "Laid restaurant table for four"), ("laid_table_6", "Laid restaurant table for six"),
		("laid_table_8", "Laid restaurant table for eight"), ("banquette", "Banquette seating"), ("host_stand", "Host stand"), ("waiter_station", "Waiter station"),
		("buffet", "Buffet counter with chafing dishes"), ("high_chair", "High chair"), ("wine_rack", "Wine rack")):
	reg("hospitality.restaurant." + _w, dining, _l, "restaurant", what=_w)
for _w, _l in (("banquet_round", "Banquet table for ten"), ("banquet_chair", "Banquet chair"), ("chair_stack", "Stack of banquet chairs"), ("lectern", "Lectern"),
		("dance_floor", "Dance floor, 4 m"), ("mobile_bar", "Mobile bar"), ("dj_booth", "DJ booth"), ("pa_speaker", "PA speaker on a stand"), ("chandelier", "Chandelier")):
	reg("hospitality.function." + _w, dining, _l, "function_room", what=_w)
for _w, _l in (("bed_king", "Hotel king bed with bedsides"), ("bed_twin", "Hotel twin beds with bedsides"), ("desk", "Hotel desk with mirror"), ("wardrobe", "Open hotel wardrobe with safe"),
		("tv_console", "Television console"), ("housekeeping_trolley", "Housekeeping trolley"), ("luggage_cart", "Luggage cart"), ("reception", "Hotel reception desk"),
		("ironing_station", "Ironing board"), ("minibar_unit", "Tea and minibar unit")):
	reg("hospitality.hotel." + _w, hotel, _l, "hotel", what=_w)

for _n in (4, 6, 8, 12):
	reg("venue.seat.row_%d" % _n, theatre, "Theatre seats, row of %d" % _n, "theatre", "cinema", what="seats", n=_n)
reg("venue.seat.block_8x5", theatre, "Raked seating, five rows of eight", "theatre", "cinema", what="seats", n=8, rows=5)
reg("venue.seat.block_12x8", theatre, "Raked seating, eight rows of twelve", "theatre", "cinema", what="seats", n=12, rows=8)
reg("venue.seat.cinema_row_8", theatre, "Cinema seats, row of eight", "cinema", what="seats", n=8, slot="velvet_teal")
reg("venue.seat.cinema_block_10x6", theatre, "Cinema seating, six rows of ten", "cinema", what="seats", n=10, rows=6, slot="velvet_teal")
for _w, _l, _t in (("balcony_front", "Balcony front, 3 m", "auditorium"), ("stage_deck", "Stage deck, 2 x 1 m", "stage"), ("proscenium", "Proscenium arch with curtains", "stage"),
		("lighting_truss", "Lighting truss with lanterns, 8 m", "stage"), ("follow_spot", "Follow spot", "stage"), ("grand_piano", "Grand piano", "stage"),
		("flight_case", "Flight case", "stage"), ("mixing_desk", "Sound and lighting desk", "stage"), ("backdrop_flat", "Scenery flat with braces", "stage"),
		("cinema_screen", "Cinema screen with speakers, 12 m", "cinema"), ("projector", "Cinema projector", "projection"), ("surround_speaker", "Surround speaker", "cinema"),
		("box_office", "Box office counter", "foyer"), ("concession", "Concession stand with popcorn", "foyer"), ("poster_case", "Poster case", "foyer"),
		("rope_barrier", "Rope barrier", "foyer"), ("ticket_kiosk", "Ticket kiosk", "foyer"), ("dressing_table", "Dressing table with mirror lights", "dressing_room"),
		("costume_rail", "Costume rail", "dressing_room")):
	reg("venue.%s.%s" % ({"stage": "stage", "foyer": "foyer", "dressing_room": "backstage", "projection": "cinema", "cinema": "cinema", "auditorium": "seat"}[_t], _w), theatre, _l, "theatre", _t, what=_w)

for _w, _l in (("judges_bench", "Judges' bench on a dais"), ("witness_box", "Witness box"), ("dock", "Secure dock"), ("jury_box", "Jury box, twelve seats"),
		("counsel_table", "Counsel table"), ("clerk_desk", "Clerk's desk"), ("public_bench", "Public gallery bench"), ("bar_rail", "Court rail"),
		("jury_table", "Jury room table for twelve"), ("judges_desk", "Judge's desk and chair"), ("law_bookcase", "Law bookcase")):
	reg("justice.court." + _w, court, _l, "court", what=_w)
for _w, _l in (("bunk", "Cell bunk bed"), ("bed", "Cell bed"), ("wc_basin", "Cell WC and basin unit"), ("desk", "Cell desk, stool and television"), ("cell_door", "Cell door with hatch"),
		("window", "Barred cell window"), ("visit_table", "Visits table with fixed seats"), ("officer_podium", "Officers' podium"), ("turnstile", "Full height turnstile"),
		("fence", "Secure fence with razor coil, 3 m"), ("wall", "Perimeter wall, 4 m"), ("watch_tower", "Watch tower"), ("sally_gate", "Vehicle lock gate")):
	reg("justice.prison." + _w, prison, _l, "prison", what=_w)

for _w, _l in (("bench", "Platform bench"), ("canopy_bay", "Platform canopy bay, 6 m"), ("departure_board", "Departure board"), ("ticket_machine", "Ticket machine"),
		("ticket_office", "Ticket office counter"), ("shelter", "Platform waiting shelter"), ("clock", "Station clock"), ("totem", "Station totem sign"),
		("help_point", "Help point"), ("buffer_stop", "Buffer stop"), ("info_desk", "Information desk"), ("kiosk", "Coffee kiosk"), ("atm", "Cash machine"),
		("bus_shelter", "Bus shelter"), ("bus_stand", "Bus stand flag"), ("stand_display", "Bus stand display"), ("queue_rail", "Queue rail"), ("drive_through_bay", "Bus bay island")):
	reg("station.%s.%s" % ("bus" if _w.startswith(("bus_", "stand_", "queue_", "drive_")) else "rail", _w), station, _l, "station", what=_w)

for _w, _l in (("counter", "Shop counter with gantry"), ("chiller", "Open chiller cabinet"), ("freezer", "Chest freezer"), ("newspaper_stand", "Newspaper stand"),
		("post_office", "Post office counter"), ("lottery_stand", "Lottery stand"), ("awning", "Shop awning"), ("trolley_bay", "Trolley bay"),
		("bulk_rack", "Retail warehouse racking"), ("timber_rack", "Timber rack")):
	reg("retail.store." + _w, shop, _l, "shop", what=_w)
for _w, _l in (("dock_shelter", "Dock shelter"), ("dock_light", "Dock light"), ("dock_signal", "Dock traffic signal"), ("wheel_chock", "Wheel chock"),
		("dock_platform", "Loading platform with steps"), ("strip_curtain", "Strip curtain"), ("roll_cage", "Roll cage"), ("conveyor", "Roller conveyor, 3 m"),
		("packing_bench", "Packing bench"), ("charger", "Forklift charger"), ("mezzanine", "Mezzanine floor, 6 x 4 m")):
	reg("industrial.depot." + _w, depot, _l, "warehouse", "loading_bay", what=_w)
for _w, _l in (("hot_tub", "Hot tub"), ("log_burner", "Log burner with flue"), ("decking", "Timber decking, 3 m"), ("deck_rail", "Decking balustrade, 3 m"), ("sauna", "Sauna cabin"),
		("massage_table", "Massage table"), ("yoga_mats", "Yoga mats and bolsters"), ("fire_pit", "Fire pit")):
	reg("home.lodge." + _w, lodge, _l, "lodge", "retreat", what=_w)
for _w, _l in (("four_poster", "Four-poster bed"), ("banquet_table", "Dining table for fourteen"), ("marble_fireplace", "Marble fireplace with mirror"), ("chesterfield", "Chesterfield sofa"),
		("grandfather_clock", "Longcase clock"), ("bust", "Bust on a plinth"), ("fountain", "Garden fountain"), ("library_wall", "Library wall with ladder")):
	reg("home.mansion." + _w, lodge, _l, "mansion", what=_w)
for _w, _l in (("horseshoe", "Council chamber horseshoe desk"), ("dais", "Chair's dais"), ("gallery_seats", "Public gallery seating"), ("vote_display", "Voting display")):
	reg("office.council." + _w, council, _l, "council", what=_w)
