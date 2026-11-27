"""Second-pass depth: precast and framed structure, home details, and more specialist
fittings for schools, offices, police stations, hospitals and airports.
Origin: floor or ground centre, back to -Y."""
import math

import kit
from recipes.fixtures import chair, legs, table, task_chair
from recipes.furniture import carcass
from recipes.public import castors, monitor, trolley_bed
from registry import register


def reg(id, fn, label, *tags, **params):
	fam = "structure" if id.startswith("structure") else "fixture"
	register(id, fn, label, family=fam, tags=(id.split(".")[0],) + tags, **params)


# --- structure -----------------------------------------------------------------------------

def precast(what="hollowcore", w=1.2, d=0.2, l=1.0):
	if what == "hollowcore":
		kit.box((w, 1.0, d), (0, 0, d / 2), "concrete", "plank")
		n = int(w / 0.19)
		for i in range(n):
			kit.cyl(d * 0.33, 1.002, (-w / 2 + w * (i + 0.5) / n, 0, d / 2), "plastic_black", "core", axis="y", segs=10)
	elif what == "double_tee":
		kit.box((2.4, 1.0, 0.08), (0, 0, d - 0.04), "concrete", "flange")
		for s in (-1, 1):
			kit.prism([(-0.06, 0), (0.06, 0), (0.1, d - 0.08), (-0.1, d - 0.08)], 1.0, (s * 0.6, 0, 0), "concrete", "stem", axis="y")
	elif what == "wall_panel":
		kit.box((w, 0.2, l), (0, 0, l / 2), "concrete", "panel")
		for x in (-w / 4, w / 4):
			kit.sweep([(x - 0.05, 0, l), (x - 0.05, 0, l + 0.08), (x + 0.05, 0, l + 0.08), (x + 0.05, 0, l)], kit.circle(0.008, 6), "steel_galvanised", "lifting_loop", up=(0, 1, 0))
	elif what == "sandwich_panel":
		kit.box((w, 0.07, l), (0, 0.115, l / 2), "concrete", "outer_leaf")
		kit.box((w, 0.1, l), (0, 0.03, l / 2), "insulation", "insulation")
		kit.box((w, 0.15, l), (0, -0.095, l / 2), "concrete", "inner_leaf")
		kit.box((w * 0.4, 0.33, l * 0.4), (0, 0.01, l * 0.55), "glass", "window_opening")
	elif what == "stair_unit":
		n = 8
		pts = [(0, 0)]
		for i in range(n):
			pts += [(i * 0.25, (i + 1) * 0.1875), ((i + 1) * 0.25, (i + 1) * 0.1875)]
		pts += [(n * 0.25 + 1.0, n * 0.1875), (n * 0.25 + 1.0, n * 0.1875 - 0.2), (n * 0.25, n * 0.1875 - 0.2), (0.3, 0)]
		kit.prism(pts, w, (0, 0, 0), "concrete", "flight_and_landing", axis="x")
	elif what == "column":
		kit.box((w, w, l), (0, 0, l / 2), "concrete", "column")
		kit.box((w + 0.3, w / 1.5, 0.3), (0.15 + 0.0, 0, l - 0.5), "concrete", "corbel")
		for sx in (-1, 1):
			for sy in (-1, 1):
				kit.cyl(0.012, 0.5, (sx * w / 3, sy * w / 3, l + 0.25), "steel_painted", "starter_bar", segs=6)
	elif what == "beam_inverted_t":
		kit.prism([(-0.4, 0), (0.4, 0), (0.4, 0.25), (0.2, 0.25), (0.2, d), (-0.2, d), (-0.2, 0.25), (-0.4, 0.25)], 1.0, (0, 0, 0), "concrete", "beam", axis="y")
	elif what == "ground_beam":
		kit.box((w, 1.0, d), (0, 0, -d / 2), "concrete", "beam")
	elif what == "pad_cap":
		kit.box((w, w, d), (0, 0, -d / 2), "concrete", "base")
		kit.box((0.5, 0.5, 0.3), (0, 0, 0.15), "concrete", "plinth")
		for sx in (-1, 1):
			for sy in (-1, 1):
				kit.cyl(0.012, 0.2, (sx * 0.15, sy * 0.15, 0.38), "steel_galvanised", "holding_down_bolt", segs=6)
	elif what == "round_column":
		kit.cyl(w / 2, 1.0, (0, 0, 0.5), "concrete", "column", segs=24)
	elif what == "square_column":
		kit.box((w, w, 1.0), (0, 0, 0.5), "concrete", "column")
	elif what == "core_wall":
		with kit.hollow(0.4):
			for s in (-1, 1):
				kit.box((0.25, l, 1.0), (s * (w / 2 - 0.125), 0, 0.5), "concrete", "wall")
				kit.box((w, 0.25, 1.0), (0, s * (l / 2 - 0.125), 0.5), "concrete", "wall")


def framing(what="bay", w=6.0, d=6.0, h=3.6):
	if what in ("bay", "braced_bay"):
		with kit.stage("columns"):
			for x in (-w / 2, w / 2):
				for y in (-d / 2, d / 2):
					kit.i_section(0.2, 0.2, 0.012, 0.008, h, (x, y, h / 2), "steel_painted", "column", axis="z")
		with kit.stage("beams"):
			for y in (-d / 2, d / 2):
				kit.i_section(0.17, 0.36, 0.013, 0.008, w - 0.2, (0, y, h - 0.18), "steel_painted", "primary", axis="x")
			for i in range(int(w / 3) + 1):
				kit.i_section(0.13, 0.25, 0.01, 0.006, d - 0.2, (-w / 2 + i * w / int(w / 3), 0, h - 0.125), "steel_painted", "secondary", axis="y")
		if what == "braced_bay":
			with kit.stage("bracing"):
				for a, b in (((-w / 2, -d / 2, 0), (w / 2, -d / 2, h - 0.4)), ((w / 2, -d / 2, 0), (-w / 2, -d / 2, h - 0.4))):
					kit.rod(a, b, 0.04, "steel_painted", "brace")
	elif what == "timber_panel":
		for i in range(int(w / 0.6) + 1):
			kit.box((0.038, 0.14, h - 0.076), (-w / 2 + 0.019 + i * (w - 0.038) / int(w / 0.6), 0, h / 2), "softwood", "stud")
		for z in (0.019, h - 0.019):
			kit.box((w, 0.14, 0.038), (0, 0, z), "softwood", "plate")
		kit.box((w, 0.009, h), (0, 0.0745, h / 2), "plywood", "sheathing")
	elif what == "sip":
		kit.box((w, 0.142, h), (0, 0, h / 2), "insulation", "core")
		for s in (-1, 1):
			kit.box((w, 0.015, h), (0, s * 0.0785, h / 2), "plywood", "skin")
	elif what == "clt":
		for i in range(5):
			kit.box((w, 0.04, h), (0, -0.08 + i * 0.04, h / 2), "softwood" if i % 2 == 0 else "glulam", "lamella")
	elif what == "steel_stud":
		for i in range(int(w / 0.6) + 1):
			kit.prism([(-0.025, -0.045), (0.025, -0.045), (0.025, -0.043), (-0.023, -0.043), (-0.023, 0.043), (0.025, 0.043), (0.025, 0.045), (-0.025, 0.045)], h, (-w / 2 + 0.025 + i * (w - 0.05) / int(w / 0.6), 0, h / 2), "steel_galvanised", "stud", axis="z")
		for z in (0.02, h - 0.02):
			kit.box((w, 0.094, 0.04), (0, 0, z), "steel_galvanised", "track")
	elif what == "space_frame":
		n = int(w / 3)
		for i in range(n + 1):
			for j in range(n + 1):
				x, y = -w / 2 + i * 3, -w / 2 + j * 3
				kit.sphere(0.09, (x, y, h), "steel_painted", "node", segs=8)
				if i < n:
					kit.rod((x, y, h), (x + 3, y, h), 0.04, "steel_painted", "top_chord", segs=6)
				if j < n:
					kit.rod((x, y, h), (x, y + 3, h), 0.04, "steel_painted", "top_chord", segs=6)
				if i < n and j < n:
					c = (x + 1.5, y + 1.5, h - 2.0)
					kit.sphere(0.09, c, "steel_painted", "node", segs=8)
					for dx in (0, 3):
						for dy in (0, 3):
							kit.rod((x + dx, y + dy, h), c, 0.03, "steel_painted", "diagonal", segs=6)
					if i < n - 1:
						kit.rod(c, (c[0] + 3, c[1], c[2]), 0.04, "steel_painted", "bottom_chord", segs=6)
					if j < n - 1:
						kit.rod(c, (c[0], c[1] + 3, c[2]), 0.04, "steel_painted", "bottom_chord", segs=6)
	elif what == "transfer_truss":
		for z in (0.15, h - 0.15):
			kit.i_section(0.3, 0.3, 0.02, 0.012, w, (0, 0, z), "steel_painted", "chord", axis="x")
		n = int(w / h)
		for i in range(n):
			x0 = -w / 2 + i * w / n
			kit.strut((x0, 0, 0.15) if i % 2 == 0 else (x0, 0, h - 0.15), (x0 + w / n, 0, h - 0.15) if i % 2 == 0 else (x0 + w / n, 0, 0.15), 0.2, 0.2, "steel_painted", "diagonal")
			kit.box((0.2, 0.2, h - 0.3), (x0, 0, h / 2), "steel_painted", "post")
		kit.box((0.2, 0.2, h - 0.3), (w / 2, 0, h / 2), "steel_painted", "post")
	elif what == "cable_stay":
		kit.box((1.2, 1.2, h), (0, 0, h / 2), "concrete", "pylon")
		for i in range(1, 6):
			for s in (-1, 1):
				kit.rod((0, 0, h - i * 1.2), (s * i * w / 10, 0, 0.3), 0.03, "steel_galvanised", "stay", segs=6)
	elif what == "tensile_canopy":
		for sx in (-1, 1):
			for sy in (-1, 1):
				kit.rod((sx * w / 2, sy * w / 2, 0), (sx * w / 2 * 0.9, sy * w / 2 * 0.9, h if sx * sy > 0 else h * 0.6), 0.08, "steel_painted", "mast")
		for t in range(5):
			f = t / 4
			kit.sweep([(-w * 0.45, -w * 0.45 + f * w * 0.9, h * (1 - 0.4 * f)), (0, -w * 0.45 + f * w * 0.9, h * 0.72), (w * 0.45, -w * 0.45 + f * w * 0.9, h * (0.6 + 0.4 * f))], kit.rect(0.01, w * 0.24), "fabric_white", "membrane", up=(0, 1, 0))


# --- home details --------------------------------------------------------------------------

def decor(what="picture", w=0.6, h=0.8, slot="hardwood"):
	if what == "picture":
		kit.box((w, 0.03, h), (0, 0.015, 1.5), slot, "frame")
		kit.box((w - 0.08, 0.004, h - 0.08), (0, 0.032, 1.5), ("fabric_blue", "fabric_green", "fabric_red", "fabric_white")[int(w * 10) % 4], "canvas")
	elif what == "tv":
		kit.box((w, 0.04, w * 0.57), (0, 0.03, 1.3), "plastic_black", "tv")
		kit.box((w - 0.02, 0.004, w * 0.57 - 0.02), (0, 0.052, 1.3), "screen", "screen")
	elif what == "lamp_table":
		kit.cyl(0.08, 0.02, (0, 0, 0.01), "brass", "base", segs=14)
		kit.cyl(0.012, 0.3, (0, 0, 0.17), "brass", "stem", segs=8)
		kit.cyl(0.14, 0.2, (0, 0, 0.4), "fabric_white", "shade", segs=16, r2=0.1)
	elif what == "pendant":
		kit.rod((0, 0, 2.4), (0, 0, 1.9), 0.004, "plastic_black", "flex", segs=5)
		kit.lathe([(0.03, 0.25), (0.2, 0.0), (0.21, 0.0), (0.04, 0.27)], (0, 0, 1.65), slot if slot != "hardwood" else "copper", "shade", segs=18)
		kit.sphere(0.04, (0, 0, 1.75), "light_emitter", "bulb", segs=8)
	elif what == "houseplant":
		kit.lathe([(0.1, 0), (0.14, 0.25)], (0, 0, 0), "clay_tile", "pot", segs=14)
		for i in range(7):
			a = math.radians(51 * i)
			kit.sweep([(0, 0, 0.25), (0.15 * h * math.cos(a), 0.15 * h * math.sin(a), 0.25 + 0.5 * h), (0.4 * h * math.cos(a), 0.4 * h * math.sin(a), 0.25 + 0.55 * h)], kit.rect(0.09 * h, 0.004), "foliage", "leaf")
	elif what == "books":
		for i, c in enumerate(("fabric_red", "fabric_blue", "fabric_green", "fabric_grey", "fabric_white", "leather_black")):
			kit.box((0.035, 0.16, 0.22 + 0.02 * (i % 3)), (-0.09 + i * 0.037, 0, 0.11 + 0.01 * (i % 3)), c, "book")
	elif what == "cushion":
		kit.rounded_box((0.45, 0.14, 0.45), (0, 0, 0.225), slot if slot != "hardwood" else "fabric_red", "cushion", radius=0.06)
	elif what == "speaker":
		kit.box((0.25, 0.3, 1.0), (0, 0, 0.5), "plastic_black", "cabinet")
		for z in (0.35, 0.65, 0.88):
			kit.cyl(0.08 if z < 0.8 else 0.03, 0.01, (0, 0.151, z), "plastic_grey", "driver", axis="y", segs=14)
	elif what == "console":
		kit.rounded_box((0.3, 0.26, 0.07), (0, 0, 0.035), "paint_white", "console", radius=0.015)
		kit.rounded_box((0.15, 0.1, 0.04), (0.3, 0, 0.02), "plastic_black", "controller", radius=0.015)
	elif what == "toy_box":
		with kit.hollow(0.1):
			kit.box((0.7, 0.4, 0.4), (0, 0, 0.2), "plastic_blue", "box")
		for i, c in enumerate(("plastic_red", "plastic_yellow", "plastic_green")):
			kit.box((0.1, 0.1, 0.1), (-0.2 + i * 0.2, 0.3, 0.05), c, "block", rot=(0, 0, 20 * i))
		kit.sphere(0.11, (0.5, 0.25, 0.11), "plastic_red", "ball", segs=12)
	elif what == "highchair":
		for sx in (-1, 1):
			for sy in (-1, 1):
				kit.rod((sx * 0.3, sy * 0.3, 0), (sx * 0.18, sy * 0.18, 0.6), 0.015, "hardwood", "leg")
		kit.rounded_box((0.34, 0.34, 0.25), (0, 0, 0.7), "plastic_white", "seat", radius=0.05)
		kit.box((0.45, 0.25, 0.02), (0, 0.25, 0.8), "plastic_white", "tray")
	elif what == "towel_rail":
		for s in (-1, 1):
			kit.rod((s * 0.24, 0.05, 0.6), (s * 0.24, 0.05, 1.6), 0.012, "steel_stainless", "rail")
		for i in range(8):
			kit.rod((-0.24, 0.05, 0.65 + i * 0.13), (0.24, 0.05, 0.65 + i * 0.13), 0.009, "steel_stainless", "bar", segs=6)
		kit.box((0.4, 0.03, 0.5), (0, 0.07, 1.2), "fabric_white", "towel")
	elif what == "shower_screen":
		kit.box((w, 0.008, 1.95), (0, 0, 0.975), "glass", "screen")
		kit.box((0.03, 0.03, 1.95), (-w / 2, 0, 0.975), "steel_stainless", "channel")
	elif what == "shower_enclosure":
		kit.rounded_box((w, w, 0.06), (0, 0, 0.03), "ceramic", "tray", radius=0.02)
		kit.box((w, 0.008, 1.9), (0, w / 2, 1.0), "glass", "door")
		kit.box((0.008, w, 1.9), (w / 2, 0, 1.0), "glass", "side")
		kit.rod((-w / 2 + 0.1, -w / 2 + 0.05, 1.0), (-w / 2 + 0.1, -w / 2 + 0.05, 2.1), 0.012, "steel_stainless", "riser")
		kit.cyl(0.1, 0.01, (-w / 2 + 0.25, -w / 2 + 0.2, 2.1), "steel_stainless", "head", segs=14)
	elif what == "bath_freestanding":
		with kit.hollow(0.2):
			kit.lathe([(0.25, 0), (0.33, 0.1), (0.38, 0.55), (0.4, 0.58)], (0, 0, 0.02), "ceramic", "bath", segs=24, scale=(1.0, 2.1, 1))
		kit.sweep([(0.45, 0, 0), (0.45, 0, 0.9), (0.3, 0, 0.95)], kit.circle(0.015, 8), "steel_stainless", "tap", up=(0, 1, 0))
	elif what == "bath_corner":
		with kit.hollow(0.25):
			kit.prism([(-0.7, -0.7), (0.7, -0.7), (0.7, 0.1), (0.1, 0.7), (-0.7, 0.7)], 0.55, (0, 0, 0.275), "ceramic", "bath", axis="z")
		kit.cyl(0.45, 0.01, (-0.1, -0.1, 0.551), "water", "water", segs=20)
	elif what == "toilet_roll":
		kit.rod((-0.08, 0.06, 0.75), (0.08, 0.06, 0.75), 0.006, "steel_stainless", "holder", segs=6)
		kit.cyl(0.055, 0.1, (0, 0.06, 0.75), "fabric_white", "roll", axis="x", segs=14)
	elif what == "water_cylinder":
		with kit.hollow(0.05):
			kit.lathe([(0.2, 0), (0.25, 0.05), (0.25, 1.4), (0.1, 1.5)], (0, 0, 0.1), "insulation", "cylinder", segs=18)
		for z in (0.3, 1.2):
			kit.rod((0.25, 0, z), (0.45, 0, z), 0.012, "copper", "pipe")
	elif what == "hot_tub":
		with kit.hollow(0.3):
			kit.rounded_box((2.1, 2.1, 0.9), (0, 0, 0.45), "hardwood", "cabinet", radius=0.1)
		kit.rounded_box((1.8, 1.8, 0.02), (0, 0, 0.88), "water", "water", radius=0.008)
	elif what == "decking":
		for i in range(7):
			kit.box((0.138, 1.0, 0.028), (-0.429 + i * 0.143, 0, 0.15), "softwood", "board")
		for x in (-0.3, 0.3):
			kit.box((0.047, 1.0, 0.125), (x, 0, 0.0725), "softwood", "joist")
	elif what == "paving":
		kit.box((1.0, 1.0, 0.05), (0, 0, 0.025), "paving", "slabs")
	elif what == "garden_set":
		table(1.5, 0.9, 0.74, "hardwood", "hardwood")
		for x in (-0.4, 0.4):
			chair((x, 0.75), 180, "hardwood", "hardwood")
			chair((x, -0.75), 0, "hardwood", "hardwood")
	elif what == "sun_lounger":
		kit.box((0.65, 1.4, 0.04), (0, 0.25, 0.3), "fabric_white", "bed")
		kit.box((0.65, 0.6, 0.04), (0, -0.7, 0.5), "fabric_white", "back", rot=(40, 0, 0))
		legs(0.65, 1.9, 0.28, 0.04, "hardwood")
	elif what == "shed":
		with kit.hollow(0.05):
			kit.box((w, h, 1.9), (0, 0, 0.95), "softwood", "walls")
		kit.prism([(-w / 2 - 0.1, 0), (w / 2 + 0.1, 0), (0, 0.5)], h + 0.2, (0, 0, 1.9), "roof_felt", "roof", axis="y")
		kit.box((0.8, 0.03, 1.7), (0, h / 2, 0.9), "softwood", "door")
	elif what == "bike_rack_wall":
		kit.box((0.05, 0.03, 1.2), (0, 0.015, 1.4), "steel_painted", "rail")
		kit.rod((0, 0.03, 1.9), (0, 0.3, 1.95), 0.012, "steel_painted", "hook")
	elif what == "car_lift":
		for s in (-1, 1):
			kit.box((0.25, 0.3, 3.6), (s * 1.6, 0, 1.8), "plastic_blue", "post")
			kit.box((0.5, 0.6, 0.02), (s * 1.6, 0, 0.01), "plastic_blue", "base_plate")
			for y in (-1, 1):
				kit.strut((s * 1.5, 0, 0.9), (s * 0.7, y * 0.9, 0.9), 0.1, 0.06, "plastic_black", "arm")
		kit.box((3.2, 0.15, 0.15), (0, 0, 3.6), "plastic_blue", "crossbeam")
	elif what == "dog_bed":
		kit.lathe([(0.35, 0), (0.4, 0.15), (0.3, 0.15), (0.28, 0.06), (0, 0.06)], (0, 0, 0), "fabric_grey", "bed", segs=16, scale=(1.3, 1, 1))
	elif what == "aquarium":
		carcass(1.2, 0.45, 0.7, "plastic_black", doors=2, plinth=0.05)
		kit.box((1.2, 0.45, 0.55), (0, 0, 0.975), "glass", "tank")
		kit.box((1.18, 0.43, 0.45), (0, 0, 0.93), "water", "water")
	elif what == "exercise_bike_home":
		kit.box((0.5, 1.0, 0.05), (0, 0, 0.025), "plastic_black", "base")
		kit.cyl(0.2, 0.06, (0, 0.3, 0.35), "plastic_black", "flywheel", axis="x", segs=18)
		kit.rod((0, -0.2, 0.05), (0, -0.25, 0.9), 0.03, "plastic_grey", "seat_post")
		kit.rounded_box((0.2, 0.26, 0.06), (0, -0.25, 0.93), "leather_black", "saddle", radius=0.025)
		kit.rod((0, 0.3, 0.35), (0, 0.4, 1.1), 0.03, "plastic_grey", "stem")
		kit.box((0.35, 0.03, 0.22), (0, 0.42, 1.25), "screen", "screen")
	elif what == "loft_ladder":
		for s in (-1, 1):
			kit.strut((s * 0.2, 0, 2.4), (s * 0.2, 1.0, 0), 0.03, 0.08, "aluminium", "stile")
		for i in range(1, 10):
			kit.box((0.4, 0.08, 0.025), (0, 1.0 * (1 - i / 10), 2.4 * i / 10), "aluminium", "tread")
		for s in (-1, 1):
			kit.box((0.04, 1.2, 0.1), (s * 0.3, 0.5, 2.45), "softwood", "hatch_frame")
			kit.box((0.64, 0.04, 0.1), (0, 0.5 + s * 0.6, 2.45), "softwood", "hatch_frame")
		kit.box((0.56, 1.16, 0.02), (0, 0.5, 2.5), "paint_white", "hatch")


# --- public depth --------------------------------------------------------------------------

def special(what="helipad"):
	if what == "helipad":
		kit.cyl(13.0, 0.3, (0, 0, 0.15), "concrete", "pad", segs=40)
		kit.tube(11.0, 0.01, (0, 0, 0.305), "plastic_yellow", "circle", wall=0.5, segs=40)
		for s in (-1, 1):
			kit.box((0.6, 6.0, 0.01), (s * 1.8, 0, 0.306), "paint_white", "h_leg")
		kit.box((3.0, 0.6, 0.01), (0, 0, 0.306), "paint_white", "h_bar")
		for i in range(12):
			a = math.radians(30 * i)
			kit.cyl(0.08, 0.1, (12.5 * math.cos(a), 12.5 * math.sin(a), 0.35), "light_emitter", "light", segs=8)
	elif what == "helicopter":
		with kit.hollow(0.05):
			kit.lathe([(0.1, 0), (0.9, 1.0), (1.05, 2.5), (0.8, 4.5), (0.3, 5.5)], (0, -2.0, 1.8), "plastic_yellow", "cabin", segs=18, rot=(-90, 0, 180), scale=(1, 1, 1))
		kit.strut((0, -1.5, 2.0), (0, -8.0, 2.4), 0.3, 0.35, "plastic_yellow", "tail_boom")
		kit.prism([(-8.4, 2.2), (-7.6, 2.2), (-7.9, 3.6), (-8.5, 3.6)], 0.1, (0, 0, 0), "plastic_yellow", "fin", axis="x")
		kit.cyl(0.12, 0.6, (0, 0.5, 3.0), "steel_painted", "mast", segs=10)
		for i in range(4):
			kit.box((0.25, 5.5, 0.03), (2.75 * math.sin(math.radians(90 * i + 20)) * -1, 0.5 + 2.75 * math.cos(math.radians(90 * i + 20)), 3.3), "plastic_black", "blade", rot=(0, 0, 90 * i + 20))
		for s in (-1, 1):
			kit.rod((s * 1.1, -1.0, 0.1), (s * 1.1, 2.5, 0.1), 0.05, "steel_painted", "skid")
			for y in (-0.3, 1.8):
				kit.rod((s * 1.1, y, 0.1), (s * 0.6, y, 1.2), 0.04, "steel_painted", "strut")
		kit.box((1.5, 0.05, 0.9), (0, 3.0, 2.0), "glass", "windscreen", rot=(-35, 0, 0))
	elif what == "control_tower":
		with kit.hollow(0.1):
			kit.cyl(3.0, 30.0, (0, 0, 15.0), "concrete", "shaft", segs=20)
			kit.lathe([(3.0, 0), (5.5, 2.0), (6.0, 2.0), (6.0, 2.3), (3.0, 2.3)], (0, 0, 30.0), "concrete", "collar", segs=20)
			kit.lathe([(5.2, 0), (6.0, 3.0), (6.3, 3.0), (6.3, 3.4), (1.0, 4.0)], (0, 0, 32.3), "glass", "cab", segs=12)
		kit.cyl(0.05, 6.0, (0, 0, 39.0), "steel_galvanised", "antenna", segs=6)
		kit.box((2.5, 0.4, 1.0), (0, 0, 37.2), "plastic_white", "radar")
	elif what == "radar":
		kit.lattice(12.0, 3.0, 0.1, 0.05, at=(0, 0, 0), bays=5, slot="steel_galvanised", name="tower")
		kit.cyl(1.8, 0.6, (0, 0, 12.3), "steel_galvanised", "turning_gear", segs=18)
		kit.sweep([(-4.5 + i, 0.6 * (1 - (i - 4.5) ** 2 / 20.25) - 0.6, 14.0) for i in range(10)], kit.rect(0.05, 2.4), "hivis_orange", "antenna")
	elif what == "hangar":
		with kit.hollow(0.02):
			kit.prism([(-30, 0), (30, 0), (30, 14), (0, 19), (-30, 14)], 60.0, (0, 0, 0), "steel_painted", "shed", axis="y")
		for i in range(6):
			kit.box((9.5, 0.3, 13.0), (-25 + i * 10, 30.2 + (0.35 if i % 2 else 0), 6.5), "aluminium", "door_leaf")
	elif what == "papi":
		for i in range(4):
			kit.box((0.6, 0.9, 0.35), (i * 3.0 - 4.5, 0, 0.6), "hivis_orange", "unit")
			kit.box((0.5, 0.02, 0.15), (i * 3.0 - 4.5, 0.46, 0.62), "light_emitter", "lens")
			for s in (-1, 1):
				kit.rod((i * 3.0 - 4.5 + s * 0.2, 0, 0), (i * 3.0 - 4.5 + s * 0.2, 0, 0.45), 0.02, "steel_galvanised", "leg")
	elif what == "cargo_loader":
		with kit.hollow(0.4):
			kit.box((3.2, 8.0, 0.6), (0, 0, 0.7), "paint_white", "chassis")
		for s in (-1, 1):
			for y in (-3, 0, 3):
				kit.wheel(0.35, 0.3, (s * 1.5, y, 0.35))
			kit.strut((s * 1.3, -2.5, 1.0), (s * 1.3, 2.5, 3.2), 0.12, 0.2, "steel_painted", "scissor")
			kit.strut((s * 1.3, 2.5, 1.0), (s * 1.3, -2.5, 3.2), 0.12, 0.2, "steel_painted", "scissor")
		kit.box((3.2, 7.0, 0.25), (0, 0, 3.4), "steel_galvanised", "platform")
		kit.box((1.0, 1.2, 1.2), (-1.3, 4.0, 3.2), "paint_white", "cab")
	elif what in ("catering_truck", "deicer"):
		with kit.hollow(0.2):
			kit.rounded_box((2.4, 2.0, 2.2), (0, 3.2, 1.7), "paint_white", "cab", radius=0.1)
			kit.box((2.2, 7.5, 0.3), (0, 0, 0.95), "steel_painted", "chassis")
			if what == "catering_truck":
				kit.box((2.5, 5.0, 2.4), (0, -1.0, 4.4), "paint_white", "box_body")
		for s in (-1, 1):
			for y in (3.0, -2.5):
				kit.wheel(0.5, 0.3, (s * 1.05, y, 0.5))
			if what == "catering_truck":
				kit.strut((s * 0.9, -3.0, 1.2), (s * 0.9, 1.0, 3.2), 0.1, 0.2, "steel_painted", "scissor")
				kit.strut((s * 0.9, 1.0, 1.2), (s * 0.9, -3.0, 3.2), 0.1, 0.2, "steel_painted", "scissor")
		if what == "deicer":
			with kit.hollow(0.05):
				kit.box((2.3, 4.0, 1.4), (0, -1.0, 1.8), "hivis_orange", "tank")
			kit.strut((0, -2.5, 2.5), (0, 2.0, 7.0), 0.3, 0.3, "paint_white", "boom")
			kit.box((1.0, 1.0, 1.1), (0, 2.4, 7.3), "paint_white", "basket")
	elif what == "uld":
		with kit.hollow(0.05):
			kit.prism([(-0.78, 0), (0.78, 0), (0.78, 1.63), (0.3, 1.63), (-0.78, 1.0)], 1.5, (0, 0, 0), "aluminium", "container", axis="y")
	elif what == "cargo_pallet":
		kit.box((2.4, 3.2, 0.03), (0, 0, 0.015), "aluminium", "pallet")
		kit.rounded_box((2.2, 3.0, 1.5), (0, 0, 0.78), "plywood", "load", radius=0.1)
		kit.grid_bars(2.3, 3.1, (0, 0, 1.54), 8, 10, 0.004, "plastic_yellow", "net", plane="xy")
	elif what == "sorter_chute":
		kit.sweep([(0, -1.5, 2.2), (0, 0, 1.2), (0, 1.2, 0.8)], [(-0.5, 0), (0.5, 0), (0.5, 0.25), (0.47, 0.25), (0.47, 0.03), (-0.47, 0.03), (-0.47, 0.25), (-0.5, 0.25)], "steel_stainless", "chute")
		for y in (-1.3, 0.9):
			kit.rod((0, y, 0), (0, y, 2.0 if y < 0 else 0.8), 0.04, "steel_galvanised", "leg")
	elif what == "lounge_set":
		for i, (x, y, r) in enumerate(((-0.9, 0, 90), (0.9, 0, -90), (0, 0.9, 180), (0, -0.9, 0))):
			kit.rounded_box((0.7, 0.7, 0.4), (x, y, 0.22), "leather_black", "seat", radius=0.08)
			kit.rounded_box((0.7, 0.15, 0.4), (x + (-0.28 if r == 90 else 0.28 if r == -90 else 0), y + (0.28 if r == 180 else -0.28 if r == 0 else 0), 0.6), "leather_black", "back", radius=0.06, rot=(0, 0, r))
		kit.cyl(0.35, 0.03, (0, 0, 0.42), "glass", "table", segs=20)
		kit.cyl(0.03, 0.4, (0, 0, 0.2), "steel_stainless", "table_post", segs=8)
	elif what == "immigration_hall":
		for i in range(4):
			kit.box((1.4, 1.5, 1.1), (i * 2.6 - 3.9, 0, 0.55), "laminate_grey", "booth_base")
			kit.box((1.4, 1.5, 1.2), (i * 2.6 - 3.9, 0, 1.7), "glass", "booth_glass")
			kit.box((1.4, 1.5, 0.08), (i * 2.6 - 3.9, 0, 2.34), "laminate_grey", "booth_roof")
		kit.box((10.4, 0.1, 0.5), (0, 0, 3.0), "plastic_blue", "sign")
	elif what in ("icu_bed", "ward_bay", "dialysis", "ultrasound", "treatment_chair", "pharmacy_shelving", "resus_bay", "birth_pool", "waiting_row", "oxygen_tank", "ambulance_canopy", "bed_pan_washer", "physio_bars", "cot_hospital", "blood_trolley"):
		if what in ("icu_bed", "ward_bay", "resus_bay"):
			trolley_bed(0.95, 2.1, 0.75)
			kit.box((1.8, 0.07, 0.25), (0, -1.15, 1.5), "paint_white", "bedhead_trunking")
			if what != "ward_bay":
				kit.rod((0.8, -1.0, 2.7), (0.8, -1.0, 1.9), 0.04, "paint_white", "pendant_drop")
				kit.box((0.4, 0.4, 0.8), (0.8, -1.0, 1.5), "paint_white", "pendant")
				kit.box((0.36, 0.05, 0.28), (0.8, -0.78, 1.7), "screen", "monitor")
				kit.rod((-0.8, -0.9, 0.05), (-0.8, -0.9, 1.9), 0.012, "steel_stainless", "drip_stand")
				kit.rounded_box((0.3, 0.3, 0.45), (-1.0, -0.6, 1.0), "plastic_white", "ventilator", radius=0.03)
			else:
				kit.rounded_box((0.55, 0.5, 0.45), (0.9, -0.6, 0.45), "plastic_green", "chair", radius=0.08)
				carcass(0.45, 0.45, 0.85, "laminate_white", doors=1, drawers=1, plinth=0.08)
		elif what in ("dialysis", "treatment_chair"):
			kit.rounded_box((0.6, 0.6, 0.12), (0, 0.1, 0.5), "plastic_blue", "seat", radius=0.04)
			kit.rounded_box((0.6, 0.9, 0.1), (0, -0.55, 0.85), "plastic_blue", "back", radius=0.04, rot=(-35, 0, 0))
			kit.rounded_box((0.55, 0.6, 0.1), (0, 0.7, 0.4), "plastic_blue", "leg_rest", radius=0.04, rot=(-20, 0, 0))
			kit.box((0.5, 0.6, 0.4), (0, 0, 0.2), "plastic_grey", "base")
			for s in (-1, 1):
				kit.box((0.1, 0.5, 0.04), (s * 0.38, 0.1, 0.7), "plastic_grey", "arm")
			if what == "dialysis":
				kit.rounded_box((0.4, 0.4, 1.3), (0.8, -0.2, 0.75), "plastic_white", "machine", radius=0.04)
				kit.box((0.3, 0.004, 0.22), (0.8, 0.002, 1.2), "screen", "screen")
		elif what == "ultrasound":
			kit.rounded_box((0.5, 0.7, 0.8), (0, 0, 0.5), "plastic_white", "body", radius=0.05)
			castors(0.5, 0.7, 0.05)
			kit.box((0.5, 0.35, 0.04), (0, 0.2, 0.95), "plastic_grey", "console", rot=(15, 0, 0))
			monitor((0, -0.1, 0.95), 0.45)
		elif what == "pharmacy_shelving":
			carcass(1.0, 0.4, 2.1, "laminate_white", shelves=6, plinth=0.1, open_front=True)
			for i in range(6):
				for j in range(5):
					kit.box((0.15, 0.25, 0.18), (-0.38 + j * 0.19, 0.03, 0.22 + i * 0.285 + 0.09), ("paint_white", "plastic_blue", "plastic_green")[(i + j) % 3], "stock")
		elif what == "birth_pool":
			with kit.hollow(0.3):
				kit.lathe([(0.7, 0), (0.85, 0.1), (0.95, 0.75), (1.0, 0.78)], (0, 0, 0), "plastic_white", "pool", segs=24, scale=(1.2, 1, 1))
			kit.cyl(0.85, 0.01, (0, 0, 0.6), "water", "water", segs=24).scale = (1.2, 1, 1)
		elif what == "waiting_row":
			for i in range(6):
				kit.rounded_box((0.5, 0.48, 0.08), ((i - 2.5) * 0.56, 0.02, 0.44), "plastic_green", "seat", radius=0.03)
				kit.rounded_box((0.5, 0.06, 0.4), ((i - 2.5) * 0.56, -0.22, 0.72), "plastic_green", "back", radius=0.025)
			kit.box((3.4, 0.08, 0.06), (0, 0, 0.37), "steel_painted", "beam")
			for s in (-1, 1):
				kit.box((0.05, 0.5, 0.36), (s * 1.4, 0, 0.18), "steel_painted", "leg")
		elif what == "oxygen_tank":
			with kit.hollow(0.05):
				kit.lathe([(0.5, 0), (1.2, 0.5), (1.2, 7.0), (0.5, 7.6)], (0, 0, 0.6), "paint_white", "vessel", segs=20)
			for i in range(3):
				a = math.radians(120 * i)
				kit.box((0.2, 0.2, 0.9), (1.0 * math.cos(a), 1.0 * math.sin(a), 0.45), "steel_painted", "leg")
			for i in range(6):
				kit.box((0.05, 1.2, 2.0), (1.6 + i * 0.12, 0, 1.2), "aluminium", "vaporiser_fin")
			kit.grid_bars(5.0, 2.2, (0.5, 2.0, 1.1), 25, 2, 0.01, "steel_galvanised", "fence")
		elif what == "ambulance_canopy":
			for x in (-5, 5):
				for y in (-2.5, 2.5):
					kit.cyl(0.12, 4.2, (x, y, 2.1), "steel_painted", "column", segs=12)
			kit.box((11.5, 6.5, 0.3), (0, 0, 4.35), "aluminium", "canopy")
			kit.box((4.0, 0.08, 0.6), (0, 3.3, 4.35), "hazard_red", "sign")
		elif what == "bed_pan_washer":
			kit.rounded_box((0.6, 0.6, 1.5), (0, 0, 0.75), "steel_stainless", "body", radius=0.03)
			kit.box((0.45, 0.02, 0.5), (0, 0.31, 1.1), "steel_stainless", "door")
		elif what == "physio_bars":
			for s in (-1, 1):
				kit.rod((s * 0.3, -1.5, 0.9), (s * 0.3, 1.5, 0.9), 0.02, "steel_stainless", "bar")
				for y in (-1.4, 1.4):
					kit.rod((s * 0.3, y, 0), (s * 0.3, y, 0.9), 0.02, "steel_stainless", "post")
			kit.box((0.9, 3.2, 0.03), (0, 0, 0.015), "plywood", "base")
		elif what == "cot_hospital":
			kit.box((0.75, 1.5, 0.05), (0, 0, 0.75), "steel_painted", "deck")
			castors(0.75, 1.5, 0.05)
			legs(0.75, 1.5, 0.73, 0.03, "steel_stainless")
			for s in (-1, 1):
				kit.grid_bars(1.5, 0.6, (s * 0.37, 0, 1.08), 14, 1, 0.006, "steel_stainless", "side", plane="yz")
			kit.rounded_box((0.68, 1.4, 0.08), (0, 0, 0.82), "fabric_white", "mattress", radius=0.03)
		elif what == "blood_trolley":
			kit.box((0.5, 0.4, 0.03), (0, 0, 0.85), "steel_stainless", "top")
			kit.box((0.5, 0.4, 0.02), (0, 0, 0.3), "steel_stainless", "shelf")
			legs(0.5, 0.4, 0.84, 0.02, "steel_stainless", inset=0.0)
			castors(0.5, 0.4, 0.03)
			kit.rounded_box((0.2, 0.15, 0.12), (0, 0, 0.93), "plastic_yellow", "sharps_box", radius=0.02)
	elif what in ("locker_run", "computer_row", "reading_corner", "music_room", "nursery_kit", "science_stools", "lunch_bench", "bike_scooter_rack", "notice_case", "trophy_cabinet", "kiln", "drum_kit", "stage_curtain", "lab_gas_cage"):
		if what == "locker_run":
			for i in range(8):
				with kit.hollow(0.08):
					kit.box((0.298, 0.45, 1.8), ((i - 3.5) * 0.3, 0, 0.9), ("plastic_blue", "plastic_red", "plastic_yellow", "plastic_green")[i % 4], "locker")
				kit.box((0.02, 0.01, 0.1), ((i - 3.5) * 0.3 + 0.1, 0.23, 1.0), "steel_stainless", "handle")
		elif what == "computer_row":
			kit.box((4.8, 0.7, 0.025), (0, 0, 0.72), "laminate_white", "top")
			for x in (-2.35, -0.8, 0.8, 2.35):
				kit.box((0.04, 0.65, 0.71), (x, 0, 0.355), "steel_painted", "leg")
			for i in range(6):
				monitor(((i - 2.5) * 0.8, -0.15, 0.735), 0.5, 180)
				chair(((i - 2.5) * 0.8, 0.6), 180, "plastic_blue", "steel_painted")
		elif what == "reading_corner":
			kit.cyl(1.2, 0.02, (0, 0, 0.01), "carpet", "rug", segs=24)
			for i in range(4):
				a = math.radians(40 + 90 * i)
				kit.rounded_box((0.6, 0.6, 0.35), (0.8 * math.cos(a), 0.8 * math.sin(a), 0.18), ("fabric_red", "fabric_blue", "fabric_green", "plastic_yellow")[i], "bean_bag", radius=0.15)
			carcass(0.9, 0.3, 0.7, "hardwood", shelves=1, plinth=0.05, open_front=True)
		elif what == "music_room":
			kit.box((1.4, 0.45, 0.9), (0, 0, 0.5), "plastic_black", "keyboard_stand")
			kit.box((1.3, 0.3, 0.08), (0, 0.05, 0.98), "plastic_black", "keyboard")
			kit.box((1.2, 0.12, 0.01), (0, 0.12, 1.025), "fabric_white", "keys")
			chair((0, 0.6), 180, "leather_black", "steel_painted")
		elif what == "nursery_kit":
			kit.box((1.2, 0.6, 0.02), (0, 0, 0.45), "plastic_yellow", "play_table")
			legs(1.2, 0.6, 0.44, 0.04, "plastic_red")
			with kit.hollow(0.1):
				kit.box((0.6, 0.6, 0.6), (1.1, 0, 0.3), "plastic_green", "play_cube")
			kit.cyl(0.2, 0.6, (1.1, 0, 0.3), "plastic_black", "tunnel_hole", axis="y", segs=14)
		elif what == "science_stools":
			for i in range(4):
				x = (i - 1.5) * 0.5
				kit.cyl(0.16, 0.03, (x, 0, 0.6), "hardwood", "seat", segs=14)
				for j in range(4):
					a = math.radians(45 + 90 * j)
					kit.rod((x + 0.1 * math.cos(a), 0.1 * math.sin(a), 0.6), (x + 0.2 * math.cos(a), 0.2 * math.sin(a), 0), 0.011, "steel_painted", "leg", segs=6)
		elif what == "lunch_bench":
			kit.box((2.4, 0.7, 0.03), (0, 0, 0.72), "laminate_white", "top")
			for s in (-1, 1):
				kit.box((2.4, 0.28, 0.03), (0, s * 0.65, 0.42), "plastic_blue", "bench")
			for x in (-0.9, 0.9):
				kit.sweep([(x, -0.75, 0.4), (x, -0.75, 0.02), (x, 0.75, 0.02), (x, 0.75, 0.4)], kit.circle(0.02, 8), "steel_painted", "frame", up=(1, 0, 0))
				kit.rod((x, 0, 0.02), (x, 0, 0.7), 0.02, "steel_painted", "post")
		elif what == "bike_scooter_rack":
			kit.box((3.0, 0.06, 0.06), (0, 0, 0.03), "steel_galvanised", "base")
			for i in range(10):
				kit.sweep([((i - 4.5) * 0.3, 0, 0.03), ((i - 4.5) * 0.3, 0.02, 0.4), ((i - 4.5) * 0.3, 0.3, 0.03)], kit.circle(0.01, 6), "steel_galvanised", "hoop", up=(1, 0, 0))
		elif what == "notice_case":
			kit.box((1.2, 0.08, 0.9), (0, 0.04, 1.5), "aluminium", "case")
			kit.box((1.1, 0.01, 0.8), (0, 0.082, 1.5), "glass", "glass")
		elif what == "trophy_cabinet":
			carcass(1.2, 0.4, 2.0, "hardwood", doors=2, shelves=3, glass=True)
			for i in range(3):
				kit.lathe([(0.05, 0), (0.02, 0.08), (0.07, 0.2), (0.07, 0.22)], (-0.3 + i * 0.3, 0, 0.6 + i * 0.47), "brass", "trophy", segs=10)
		elif what == "kiln":
			with kit.hollow(0.4):
				kit.box((0.9, 0.9, 1.3), (0, 0, 0.85), "steel_stainless", "kiln")
			legs(0.9, 0.9, 0.2, 0.05, "steel_painted")
			kit.box((0.2, 0.05, 0.3), (0.55, 0.3, 1.0), "plastic_grey", "controller")
		elif what == "drum_kit":
			kit.cyl(0.28, 0.4, (0, 0, 0.3), "plastic_red", "bass_drum", axis="y", segs=18)
			for x, z, r in ((-0.4, 0.6, 0.18), (0.25, 0.75, 0.15), (-0.2, 0.78, 0.13), (0.5, 0.5, 0.2)):
				kit.cyl(r, 0.18, (x, -0.2, z), "plastic_red", "drum", segs=14)
			for x, z in ((-0.65, 1.1), (0.7, 1.2)):
				kit.rod((x, -0.3, 0), (x, -0.3, z), 0.01, "steel_stainless", "stand", segs=6)
				kit.cyl(0.2, 0.008, (x, -0.3, z), "brass", "cymbal", segs=16)
			kit.cyl(0.15, 0.06, (0, -0.7, 0.5), "leather_black", "stool", segs=12)
		elif what == "stage_curtain":
			for i in range(20):
				kit.cyl(0.11, 4.0, ((i - 9.5) * 0.2, 0.02 * (i % 2), 2.0), "fabric_red", "fold", segs=6)
			kit.box((4.2, 0.1, 0.1), (0, 0, 4.05), "plastic_black", "track")
		elif what == "lab_gas_cage":
			kit.grid_bars(1.2, 1.8, (0, 0.3, 0.9), 10, 6, 0.006, "steel_galvanised", "cage")
			for i in range(3):
				kit.lathe([(0.11, 0), (0.115, 0.03), (0.115, 1.2), (0.04, 1.4)], (-0.35 + i * 0.35, 0, 0), ("plastic_black", "plastic_grey", "hazard_red")[i], "cylinder", segs=12)
	elif what in ("server_row", "comms_rack", "hot_desk_lockers", "sofa_pod", "bike_store", "boardroom_credenza", "mail_room", "plan_chest", "plotter", "standing_meeting", "coat_lockers", "trading_desk"):
		if what in ("server_row", "comms_rack"):
			n = 6 if what == "server_row" else 1
			for i in range(n):
				with kit.hollow(0.3):
					kit.box((0.6, 1.07 if n > 1 else 0.6, 2.0), ((i - (n - 1) / 2) * 0.6, 0, 1.0), "plastic_black", "rack")
				kit.grid_bars(0.5, 1.9, ((i - (n - 1) / 2) * 0.6, (1.07 if n > 1 else 0.6) / 2 + 0.005, 1.0), 10, 20, 0.002, "plastic_grey", "mesh_door")
				for j in range(6):
					kit.box((0.02, 0.005, 0.01), ((i - (n - 1) / 2) * 0.6 + 0.15, (1.07 if n > 1 else 0.6) / 2 + 0.01, 0.4 + j * 0.25), "light_emitter", "led")
		elif what in ("hot_desk_lockers", "coat_lockers"):
			carcass(1.2, 0.45, 1.8 if what == "coat_lockers" else 1.2, "laminate_white", doors=4, plinth=0.1)
			if what == "hot_desk_lockers":
				carcass(1.2, 0.45, 0.6, "laminate_grey", doors=4, plinth=0.0)
		elif what == "sofa_pod":
			with kit.hollow(0.3):
				kit.rounded_box((2.0, 0.2, 1.4), (0, -0.4, 0.7), "fabric_blue", "high_back", radius=0.05)
				for s in (-1, 1):
					kit.rounded_box((0.2, 0.8, 1.4), (s * 0.9, 0, 0.7), "fabric_blue", "side", radius=0.05)
			kit.rounded_box((1.6, 0.6, 0.42), (0, 0, 0.21), "fabric_grey", "seat", radius=0.06)
		elif what == "bike_store":
			with kit.hollow(0.02):
				kit.box((6.0, 2.4, 2.2), (0, 0, 1.1), "steel_galvanised", "enclosure")
			kit.grid_bars(6.0, 2.2, (0, 1.21, 1.1), 40, 4, 0.006, "steel_galvanised", "mesh")
			kit.box((6.2, 2.8, 0.06), (0, 0, 2.25), "plastic_green", "green_roof")
		elif what == "boardroom_credenza":
			carcass(2.4, 0.5, 0.75, "hardwood", doors=4, plinth=0.08)
			kit.box((1.6, 0.05, 0.9), (0, -0.2, 1.5), "plastic_black", "display")
			kit.box((1.56, 0.004, 0.86), (0, -0.172, 1.5), "screen", "screen")
		elif what == "mail_room":
			carcass(1.8, 0.35, 1.8, "laminate_white", shelves=5, plinth=0.1, open_front=True)
			for i in range(1, 6):
				kit.box((0.018, 0.33, 1.6), (-0.9 + i * 0.3, 0, 0.95), "laminate_white", "divider")
		elif what == "plan_chest":
			carcass(1.3, 0.95, 0.9, "steel_painted", drawers=8, plinth=0.1)
		elif what == "plotter":
			kit.rounded_box((1.6, 0.4, 0.3), (0, 0, 1.0), "plastic_white", "body", radius=0.04)
			for s in (-1, 1):
				kit.box((0.06, 0.6, 0.85), (s * 0.7, 0, 0.425), "plastic_black", "leg")
			kit.box((1.1, 0.01, 0.5), (0, 0.22, 0.65), "paint_white", "paper")
		elif what == "standing_meeting":
			kit.box((1.8, 0.8, 0.04), (0, 0, 1.08), "hardwood", "top")
			for s in (-1, 1):
				kit.box((0.08, 0.7, 1.06), (s * 0.7, 0, 0.53), "steel_painted", "leg")
			monitor((0, -0.3, 1.1), 0.8)
		elif what == "trading_desk":
			kit.box((1.8, 0.9, 0.03), (0, 0, 0.74), "laminate_white", "top")
			legs(1.8, 0.9, 0.72, 0.05, "steel_painted")
			for i in range(3):
				for j in range(2):
					kit.box((0.55, 0.03, 0.33), ((i - 1) * 0.57, -0.3, 1.0 + j * 0.36), "plastic_black", "monitor", rot=(0, 0, (1 - i) * 12))
			task_chair((0, 0.7))
	elif what in ("interview_room", "evidence_shelving", "armoury_rack", "sally_port", "patrol_bike", "custody_cctv", "property_store", "drying_cabinet", "dog_van_cage", "speed_camera", "police_lamp", "front_counter"):
		if what == "interview_room":
			table(1.2, 0.8, 0.74, "laminate_grey", "steel_painted")
			for x, y, f in ((-0.3, 0.7, 180), (0.3, 0.7, 180), (-0.3, -0.7, 0), (0.3, -0.7, 0)):
				chair((x, y), f, "fabric_blue", "steel_painted")
			kit.box((0.3, 0.2, 0.1), (0.4, 0, 0.79), "plastic_black", "recorder")
			kit.box((0.2, 0.05, 0.1), (0, -1.2, 2.3), "plastic_white", "camera")
		elif what in ("evidence_shelving", "property_store"):
			from recipes.infra import racking
			racking(bays=2, h=2.4, levels=4, loaded=False, w=1.2, d=0.5)
			for i in range(2):
				for j in range(4):
					for k in range(3):
						kit.box((0.3, 0.4, 0.25), (-0.9 + i * 1.2 + k * 0.35 - 0.05, 0, 0.6 + j * 0.45 - 0.05), "plywood" if what == "property_store" else "fabric_white", "box")
		elif what == "armoury_rack":
			kit.box((1.5, 0.3, 0.1), (0, 0, 0.05), "steel_painted", "base")
			kit.box((1.5, 0.05, 1.3), (0, -0.12, 0.7), "steel_painted", "back")
			kit.box((1.5, 0.2, 0.04), (0, 0, 1.0), "steel_painted", "barrel_rest")
			for i in range(8):
				kit.box((0.05, 0.12, 0.9), (-0.6 + i * 0.17, 0.02, 0.6), "plastic_black", "carbine")
			kit.rod((-0.75, 0.1, 0.8), (0.75, 0.1, 0.8), 0.012, "steel_stainless", "lock_bar")
		elif what == "sally_port":
			for s in (-1, 1):
				kit.box((0.4, 0.4, 4.0), (s * 2.2, 0, 2.0), "concrete", "pier")
			kit.box((4.8, 0.4, 0.5), (0, 0, 4.25), "concrete", "lintel")
			kit.grid_bars(4.0, 3.9, (0, 0, 1.95), 30, 4, 0.015, "steel_painted", "gate")
		elif what == "patrol_bike":
			from recipes.vehicles import motorbike
			motorbike()
			kit.box((0.5, 0.3, 0.35), (0, -0.9, 0.9), "paint_white", "pannier_box")
			kit.cyl(0.05, 0.08, (0.2, -0.9, 1.15), "plastic_blue", "beacon", segs=8)
		elif what == "custody_cctv":
			kit.box((0.12, 0.1, 0.08), (0, 0.05, 2.5), "paint_white", "bracket")
			kit.lathe([(0.0, 0), (0.07, 0.03), (0.08, 0.1)], (0, 0.12, 2.38), "plastic_black", "dome", segs=14)
		elif what == "drying_cabinet":
			with kit.hollow(0.1):
				kit.box((1.2, 0.7, 2.0), (0, 0, 1.0), "steel_stainless", "cabinet")
			for s in (-1, 1):
				kit.box((0.58, 0.02, 1.9), (s * 0.3, 0.36, 1.0), "glass", "door")
		elif what == "dog_van_cage":
			kit.box((1.6, 1.2, 0.04), (0, 0, 0.02), "steel_galvanised", "floor")
			kit.grid_bars(1.6, 1.0, (0, 0.6, 0.52), 16, 2, 0.006, "steel_galvanised", "front")
			kit.grid_bars(1.6, 1.0, (0, -0.6, 0.52), 16, 2, 0.006, "steel_galvanised", "back")
			kit.box((0.02, 1.2, 1.0), (0, 0, 0.52), "steel_galvanised", "divider")
		elif what == "speed_camera":
			kit.cyl(0.08, 3.0, (0, 0, 1.5), "plastic_grey", "pole", segs=10)
			kit.box((0.5, 0.6, 0.7), (0, 0, 3.3), "plastic_yellow", "housing")
			kit.box((0.2, 0.01, 0.2), (0, 0.305, 3.35), "glass", "lens")
		elif what == "police_lamp":
			kit.box((0.06, 0.3, 0.06), (0, 0.15, 3.0), "plastic_black", "bracket")
			kit.lathe([(0.1, 0), (0.16, 0.25), (0.16, 0.3), (0.05, 0.38)], (0, 0.35, 2.75), "plastic_blue", "lamp", segs=6)
		elif what == "front_counter":
			with kit.hollow(0.2):
				kit.box((2.4, 0.7, 1.05), (0, 0, 0.525), "laminate_grey", "counter")
			kit.box((2.5, 0.8, 0.04), (0, 0, 1.07), "worktop", "top")
			kit.box((2.4, 0.03, 1.1), (0, 0.1, 1.65), "glass", "security_screen")
			monitor((-0.5, -0.2, 1.09), 0.5, 180)


_PRECAST = [("hollowcore_150", "Hollowcore plank, 150", dict(d=0.15), "z"), ("hollowcore_200", "Hollowcore plank, 200", dict(), "z"), ("hollowcore_300", "Hollowcore plank, 300", dict(d=0.3), "z"), ("hollowcore_400", "Hollowcore plank, 400", dict(d=0.4), "z"),
	("double_tee_600", "Double tee unit, 600", dict(what="double_tee", d=0.6), "z"), ("double_tee_900", "Double tee unit, 900", dict(what="double_tee", d=0.9), "z"),
	("inverted_t_600", "Inverted tee beam, 600", dict(what="beam_inverted_t", d=0.6), "z"), ("inverted_t_900", "Inverted tee beam, 900", dict(what="beam_inverted_t", d=0.9), "z"),
	("ground_beam_450", "Ground beam, 450 by 600", dict(what="ground_beam", w=0.45, d=0.6), "z"), ("ground_beam_600", "Ground beam, 600 by 900", dict(what="ground_beam", w=0.6, d=0.9), "z"),
	("wall_panel_3000", "Precast wall panel, 3 m", dict(what="wall_panel", w=3.0, l=3.0), ""), ("wall_panel_6000", "Precast wall panel, 6 m", dict(what="wall_panel", w=6.0, l=3.0), ""),
	("sandwich_panel", "Insulated sandwich panel with window", dict(what="sandwich_panel", w=3.6, l=3.0), ""), ("stair_unit", "Precast stair flight with landing", dict(what="stair_unit", w=1.2), ""),
	("column_400", "Precast column with corbel, 400", dict(what="column", w=0.4, l=3.6), ""), ("column_600", "Precast column with corbel, 600", dict(what="column", w=0.6, l=4.5), ""),
	("pad_with_plinth", "Pad foundation with plinth and bolts", dict(what="pad_cap", w=1.8, d=0.6), ""), ("core_3x3", "Lift core walls, 3 m square", dict(what="core_wall", w=3.0, l=3.0), "y"), ("core_6x3", "Stair and lift core walls, 6 by 3 m", dict(what="core_wall", w=6.0, l=3.0), "y")]
for _d in (0.3, 0.45, 0.6, 0.9):
	_PRECAST.append(("round_column_%d" % (_d * 1000), "Round concrete column, %d" % (_d * 1000), dict(what="round_column", w=_d), "y"))
for _d in (0.3, 0.45, 0.6):
	_PRECAST.append(("square_column_%d" % (_d * 1000), "Square concrete column, %d" % (_d * 1000), dict(what="square_column", w=_d), "y"))
for _n, _l, _kw, _st in _PRECAST:
	register("structure.precast." + _n, precast, _l, family="structure", tags=("structure", "concrete"), stretch=_st, **_kw)
_FRAMING = (("steel_bay_6x6", "Steel frame bay, 6 by 6 m", dict()), ("steel_bay_9x6", "Steel frame bay, 9 by 6 m", dict(w=9.0)), ("steel_bay_9x9", "Steel frame bay, 9 by 9 m", dict(w=9.0, d=9.0, h=4.2)), ("steel_bay_braced", "Braced steel frame bay", dict(what="braced_bay")),
	("timber_panel_2400", "Timber frame wall panel, 2.4 m", dict(what="timber_panel", w=2.4, h=2.4)), ("timber_panel_4800", "Timber frame wall panel, 4.8 m", dict(what="timber_panel", w=4.8, h=2.4)),
	("sip_panel", "Structural insulated panel, 1.2 by 2.4 m", dict(what="sip", w=1.2, h=2.4)), ("clt_wall", "Cross-laminated timber wall panel, 3 by 3 m", dict(what="clt", w=3.0, h=3.0)), ("clt_wall_long", "Cross-laminated timber wall panel, 9 by 3 m", dict(what="clt", w=9.0, h=3.0)),
	("steel_stud_3000", "Light steel stud wall frame, 3 m", dict(what="steel_stud", w=3.0, h=2.7)), ("space_frame_12", "Space frame roof module, 12 m", dict(what="space_frame", w=12.0, h=6.0)), ("space_frame_24", "Space frame roof module, 24 m", dict(what="space_frame", w=24.0, h=8.0)),
	("transfer_truss_18", "Storey-height transfer truss, 18 m", dict(what="transfer_truss", w=18.0, h=3.6)), ("transfer_truss_30", "Storey-height transfer truss, 30 m", dict(what="transfer_truss", w=30.0, h=4.2)),
	("cable_stay_mast", "Cable-stay mast with stays", dict(what="cable_stay", w=40.0, h=20.0)), ("tensile_canopy", "Tensile fabric canopy, 10 m", dict(what="tensile_canopy", w=10.0, h=6.0)))
for _n, _l, _kw in _FRAMING:
	reg("structure.assembly." + _n, framing, _l, **_kw)

_DECOR = [("art.picture_small", "Picture, small", dict(w=0.4, h=0.5), "wall"), ("art.picture_medium", "Picture, medium", dict(), "wall"), ("art.picture_large", "Picture, large", dict(w=1.2, h=0.9, slot="plastic_black"), "wall"), ("art.poster", "Poster frame", dict(w=0.6, h=0.9, slot="aluminium"), "wall"),
	("av.tv_32", "Television, 32 inch, wall", dict(what="tv", w=0.72), "wall"), ("av.tv_43", "Television, 43 inch, wall", dict(what="tv", w=0.96), "wall"), ("av.tv_65", "Television, 65 inch, wall", dict(what="tv", w=1.45), "wall"), ("av.tv_85", "Television, 85 inch, wall", dict(what="tv", w=1.9), "wall"),
	("av.speaker", "Floor speaker", dict(what="speaker")), ("av.console", "Games console", dict(what="console")), ("light.table_lamp", "Table lamp", dict(what="lamp_table")), ("light.pendant_copper", "Pendant light, copper", dict(what="pendant"), "ceiling"),
	("light.pendant_white", "Pendant light, white", dict(what="pendant", slot="paint_white"), "ceiling"), ("plant.small", "House plant, small", dict(what="houseplant", h=0.6)), ("plant.medium", "House plant, medium", dict(what="houseplant", h=1.0)), ("plant.large", "House plant, large", dict(what="houseplant", h=1.6)),
	("soft.books", "Row of books", dict(what="books")), ("soft.cushion_red", "Cushion, red", dict(what="cushion")), ("soft.cushion_blue", "Cushion, blue", dict(what="cushion", slot="fabric_blue")), ("child.toy_box", "Toy box", dict(what="toy_box")), ("child.highchair", "High chair", dict(what="highchair")),
	("bath.towel_rail", "Heated towel rail", dict(what="towel_rail"), "wall"), ("bath.shower_screen_900", "Shower screen, 900", dict(what="shower_screen", w=0.9)), ("bath.shower_screen_1200", "Shower screen, 1200", dict(what="shower_screen", w=1.2)),
	("bath.shower_enclosure_800", "Shower enclosure, 800", dict(what="shower_enclosure", w=0.8)), ("bath.shower_enclosure_1000", "Shower enclosure, 1000", dict(what="shower_enclosure", w=1.0)), ("bath.freestanding", "Freestanding bath", dict(what="bath_freestanding")),
	("bath.corner", "Corner bath", dict(what="bath_corner")), ("bath.toilet_roll", "Toilet roll holder", dict(what="toilet_roll"), "wall"), ("utility.water_cylinder", "Hot water cylinder", dict(what="water_cylinder")), ("utility.loft_ladder", "Loft ladder and hatch", dict(what="loft_ladder")),
	("utility.exercise_bike", "Exercise bike with screen", dict(what="exercise_bike_home")), ("utility.aquarium", "Aquarium on cabinet", dict(what="aquarium")), ("utility.dog_bed", "Dog bed", dict(what="dog_bed")),
	("garden.hot_tub", "Hot tub", dict(what="hot_tub"), "outdoor"), ("garden.dining_set", "Garden table and four chairs", dict(what="garden_set"), "outdoor"), ("garden.sun_lounger", "Sun lounger", dict(what="sun_lounger"), "outdoor"),
	("garden.shed_small", "Shed, 1.8 by 1.2 m", dict(what="shed", w=1.8, h=1.2), "outdoor"), ("garden.shed_large", "Shed, 3 by 2.4 m", dict(what="shed", w=3.0, h=2.4), "outdoor"), ("garden.summer_house", "Summer house, 4 by 3 m", dict(what="shed", w=4.0, h=3.0), "outdoor"),
	("garage.bike_hook", "Wall bike hook", dict(what="bike_rack_wall"), "wall"), ("garage.car_lift", "Two-post car lift", dict(what="car_lift"), "industrial")]
for _it in _DECOR:
	reg("home." + _it[0], decor, _it[1], "home", *_it[3:], **_it[2])
register("home.garden.decking", decor, "Timber decking, per square metre", family="fixture", tags=("home", "outdoor"), stretch="xz", what="decking")
register("home.garden.paving", decor, "Patio paving, per square metre", family="fixture", tags=("home", "outdoor"), stretch="xz", what="paving")

_SPECIAL = (("airport.airside.helipad", "helipad", "Helipad", "hospital", "outdoor"), ("airport.aircraft.helicopter", "helicopter", "Helicopter, air ambulance", "hospital", "outdoor"), ("airport.airside.control_tower", "control_tower", "Control tower, 36 m", "outdoor"),
	("airport.airside.radar", "radar", "Surveillance radar on tower", "outdoor"), ("airport.airside.hangar", "hangar", "Aircraft hangar, 60 m", "outdoor"), ("airport.airside.papi", "papi", "Approach slope indicator lights", "outdoor"),
	("airport.airside.cargo_loader", "cargo_loader", "Cargo high loader", "outdoor"), ("airport.airside.catering_truck", "catering_truck", "Catering truck", "outdoor"), ("airport.airside.deicer", "deicer", "De-icing truck", "outdoor"),
	("airport.cargo.uld", "uld", "Cargo container"), ("airport.cargo.pallet", "cargo_pallet", "Cargo pallet with net"), ("airport.reclaim.sorter_chute", "sorter_chute", "Baggage sorter chute"), ("airport.gate.lounge_set", "lounge_set", "Lounge armchairs and table", "office"),
	("airport.security.immigration_hall", "immigration_hall", "Passport control, bank of four booths"),
	("hospital.bed.icu", "icu_bed", "Intensive care bed with pendant"), ("hospital.bed.ward_bay", "ward_bay", "Ward bed bay with locker and chair"), ("hospital.bed.resus_bay", "resus_bay", "Resuscitation bay"), ("hospital.bed.cot", "cot_hospital", "Hospital cot"),
	("hospital.treatment.dialysis", "dialysis", "Dialysis chair and machine"), ("hospital.treatment.chair", "treatment_chair", "Treatment chair"), ("hospital.treatment.birth_pool", "birth_pool", "Birthing pool"), ("hospital.treatment.physio_bars", "physio_bars", "Physiotherapy parallel bars"),
	("hospital.imaging.ultrasound", "ultrasound", "Ultrasound machine"), ("hospital.lab.pharmacy_shelving", "pharmacy_shelving", "Pharmacy shelving"), ("hospital.ward.waiting_row", "waiting_row", "Waiting seats, row of six"), ("hospital.ward.bed_pan_washer", "bed_pan_washer", "Bed pan washer"),
	("hospital.ward.blood_trolley", "blood_trolley", "Phlebotomy trolley"), ("hospital.site.oxygen_tank", "oxygen_tank", "Bulk oxygen tank compound", "outdoor"), ("hospital.site.ambulance_canopy", "ambulance_canopy", "Ambulance bay canopy", "outdoor"),
	("school.cloak.locker_run", "locker_run", "Pupil lockers, run of eight"), ("school.desk.computer_row", "computer_row", "Computer bench, six places", "office"), ("school.library.reading_corner", "reading_corner", "Reading corner"), ("school.hall.keyboard", "music_room", "Keyboard and stool"),
	("school.play.nursery_kit", "nursery_kit", "Nursery play table and cube"), ("school.lab.stools", "science_stools", "Lab stools, four"), ("school.canteen.lunch_bench", "lunch_bench", "Folding lunch table with benches"), ("school.play.scooter_rack", "bike_scooter_rack", "Scooter rack", "outdoor"),
	("school.board.notice_case", "notice_case", "Lockable notice case", "wall"), ("school.hall.trophy_cabinet", "trophy_cabinet", "Trophy cabinet"), ("school.art.kiln", "kiln", "Pottery kiln"), ("school.hall.drum_kit", "drum_kit", "Drum kit"), ("school.hall.stage_curtain", "stage_curtain", "Stage curtain, 4 m"),
	("school.lab.gas_cage", "lab_gas_cage", "Gas cylinder cage", "outdoor"),
	("office.it.server_row", "server_row", "Server racks, row of six"), ("office.it.comms_rack", "comms_rack", "Comms rack"), ("office.storage.hot_desk_lockers", "hot_desk_lockers", "Hot desk lockers"), ("office.storage.coat_lockers", "coat_lockers", "Staff lockers, four door", "school", "hospital", "police"),
	("office.pod.sofa", "sofa_pod", "High-back sofa pod"), ("office.entrance.bike_store", "bike_store", "Secure cycle store, 6 m", "outdoor"), ("office.storage.credenza", "boardroom_credenza", "Boardroom credenza and display"), ("office.storage.mail_sorter", "mail_room", "Mail sorting unit"),
	("office.storage.plan_chest", "plan_chest", "Plan chest"), ("office.it.plotter", "plotter", "Large format plotter"), ("office.desk.standing_meeting", "standing_meeting", "Standing meeting table with screen"), ("office.desk.trading", "trading_desk", "Six screen desk"),
	("police.custody.interview_room", "interview_room", "Interview room set"), ("police.store.evidence_shelving", "evidence_shelving", "Evidence shelving"), ("police.store.property_store", "property_store", "Property store shelving"), ("police.store.armoury_rack", "armoury_rack", "Armoury rack"),
	("police.yard.sally_port", "sally_port", "Vehicle sally port gate", "outdoor"), ("police.yard.patrol_bike", "patrol_bike", "Police motorbike", "outdoor", "vehicle"), ("police.control.cctv_dome", "custody_cctv", "CCTV dome camera", "wall"), ("police.store.drying_cabinet", "drying_cabinet", "Evidence drying cabinet"),
	("police.yard.dog_cage", "dog_van_cage", "Dog transport cage"), ("police.yard.speed_camera", "speed_camera", "Speed camera", "outdoor"), ("police.yard.blue_lamp", "police_lamp", "Blue lamp", "wall", "outdoor"), ("police.custody.front_counter", "front_counter", "Public front counter with screen"))
for _it in _SPECIAL:
	reg(_it[0], special, _it[2], *_it[3:], what=_it[1])
