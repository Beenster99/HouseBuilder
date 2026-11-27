"""Fittings for public buildings: schools, offices, police stations and hospitals.
Origin: floor centre, back to -Y (wall-hung items: the wall face is at Y = 0, origin at
floor level below them)."""
import math

import kit
from recipes.fixtures import chair, legs, table, task_chair
from recipes.furniture import carcass
from registry import register


def reg(id, fn, label, *tags, **params):
	register(id, fn, label, family="fixture", tags=(id.split(".")[0],) + tags, **params)


def castors(w, d, r=0.04, z=None):
	for sx in (-1, 1):
		for sy in (-1, 1):
			kit.cyl(r, 0.025, (sx * (w / 2 - r), sy * (d / 2 - r), r if z is None else z), "rubber", "castor", axis="x", segs=12)


def monitor(at=(0, 0, 0.74), size=0.55, face=0.0):
	x, y, z = at
	kit.cyl(0.09, 0.012, (x, y, z + 0.006), "plastic_black", "stand_base", segs=16)
	kit.box((0.04, 0.02, 0.2), (x, y, z + 0.1), "plastic_black", "stand")
	kit.box((size, 0.025, size * 0.58), (x, y + 0.02, z + 0.12 + size * 0.29), "plastic_black", "monitor", rot=(0, 0, face))
	kit.box((size - 0.02, 0.004, size * 0.58 - 0.02), (x, y + 0.034, z + 0.12 + size * 0.29), "screen", "screen", rot=(0, 0, face))


def board(w, h, z0, face, trim="aluminium", tray=True):
	"""A wall board: whiteboard, pinboard, screen."""
	kit.box((w, 0.02, h), (0, 0.01, z0 + h / 2), trim, "frame")
	kit.box((w - 0.04, 0.004, h - 0.04), (0, 0.022, z0 + h / 2), face, "face")
	if tray:
		kit.box((w * 0.6, 0.06, 0.012), (0, 0.05, z0 - 0.006), trim, "pen_tray")


# --- school --------------------------------------------------------------------------------

def whiteboard(w=2.4, h=1.2, face="enamel"):
	board(w, h, 0.9, face)


def mobile_board(w=1.5, h=1.0):
	for s in (-1, 1):
		kit.rod((s * w / 2, 0, 0.08), (s * w / 2, 0, 1.9), 0.02, "aluminium", "post")
		kit.box((0.04, 0.55, 0.03), (s * w / 2, 0, 0.08), "aluminium", "foot")
		for y in (-0.25, 0.25):
			kit.cyl(0.035, 0.025, (s * w / 2, y, 0.035), "rubber", "castor", axis="x", segs=12)
	kit.box((w, 0.025, h), (0, 0, 1.35), "aluminium", "frame")
	for s in (-1, 1):
		kit.box((w - 0.04, 0.004, h - 0.04), (0, s * 0.014, 1.35), "enamel", "face")


def projector():
	kit.rod((0, 0, 2.7), (0, 0, 2.4), 0.015, "paint_white", "drop")
	kit.rounded_box((0.32, 0.26, 0.1), (0, 0, 2.35), "plastic_white", "body", radius=0.02)
	kit.cyl(0.035, 0.03, (0.08, 0.14, 2.35), "glass", "lens", axis="y", segs=16)


def coat_rail(w=1.8, hooks=12):
	kit.box((w, 0.02, 0.1), (0, 0.01, 1.2), "hardwood", "rail")
	for i in range(hooks):
		x = -w / 2 + w * (i + 0.5) / hooks
		kit.sweep([(x, 0.02, 1.2), (x, 0.07, 1.19), (x, 0.08, 1.23)], kit.circle(0.005, 6), "steel_stainless", "hook", up=(1, 0, 0))


def cloak_bench(w=1.5):
	for s in (-1, 1):
		kit.frame(0.36, 1.5, 0.03, 0.03, at=(s * (w / 2 - 0.02), 0, 0), slot="steel_painted", name="end", bottom=False)
	for y in (-0.12, 0, 0.12):
		kit.box((w, 0.09, 0.02), (0, y, 0.36), "hardwood", "seat_slat")
	kit.box((w, 0.02, 0.09), (0, 0, 1.45), "hardwood", "hook_rail")
	for i in range(8):
		x = -w / 2 + w * (i + 0.5) / 8
		for s in (-1, 1):
			kit.rod((x, s * 0.01, 1.45), (x, s * 0.07, 1.47), 0.005, "steel_stainless", "hook", segs=6)
	kit.grid_bars(w - 0.06, 0.3, (0, 0, 0.12), 12, 0, 0.004, "steel_painted", "shoe_rack", plane="xy")


def pupil_table(w=1.2, d=0.6, h=0.64, top="laminate_white"):
	kit.box((w, d, 0.025), (0, 0, h - 0.0125), top, "top")
	legs(w, d, h - 0.025, 0.03, "steel_painted", inset=0.05)


def pupil_set(w=1.2, d=0.6, h=0.64, seats=2):
	with kit.stage("table"):
		pupil_table(w, d, h)
	with kit.stage("chairs"):
		for i in range(seats):
			chair((-w / 2 + w * (i + 0.5) / seats, d / 2 + 0.1), 180, "plastic_blue", "steel_painted", sh=h - 0.26, s=0.36)


def science_bench(w=2.4, d=0.75, h=0.9):
	with kit.stage("bench"):
		carcass(w, d - 0.04, h - 0.03, "laminate_grey", doors=4, plinth=0.1)
		kit.box((w + 0.02, d, 0.03), (0, 0, h - 0.015), "worktop", "top")
	with kit.stage("services"):
		kit.rounded_box((0.4, 0.3, 0.015), (w / 2 - 0.35, 0, h + 0.002), "ceramic", "sink", radius=0.006)
		kit.sweep([(w / 2 - 0.35, -0.22, h), (w / 2 - 0.35, -0.22, h + 0.3), (w / 2 - 0.35, -0.08, h + 0.3)], kit.circle(0.011, 8), "brass", "tap", up=(1, 0, 0))
		for x in (-w / 4, 0):
			kit.cyl(0.02, 0.1, (x, 0, h + 0.05), "plastic_yellow", "gas_tap", segs=10)
			kit.box((0.09, 0.03, 0.09), (x + 0.2, 0, h + 0.045), "plastic_white", "socket")


def fume_cupboard(w=1.2, d=0.8, h=2.3):
	with kit.hollow(0.1):
		carcass(w, d, 0.9, "laminate_white", doors=2, plinth=0.1)
		kit.box((w, d, 0.03), (0, 0, 0.915), "worktop", "deck")
		for s in (-1, 1):
			kit.box((0.05, d, h - 0.93), (s * (w / 2 - 0.025), 0, 0.93 + (h - 0.93) / 2), "paint_white", "side")
		kit.box((w, 0.03, h - 0.93), (0, -d / 2 + 0.015, 0.93 + (h - 0.93) / 2), "paint_white", "back")
		kit.box((w, d, 0.35), (0, 0, h - 0.175), "paint_white", "head")
	kit.box((w - 0.1, 0.008, 0.55), (0, d / 2 - 0.03, 1.5), "glass", "sash")
	kit.box((w - 0.1, 0.03, 0.04), (0, d / 2 - 0.03, 1.22), "aluminium", "sash_handle")
	kit.cyl(0.125, 0.3, (0, -0.1, h + 0.15), "steel_galvanised", "extract", segs=16)


def easel():
	for s in (-1, 1):
		kit.strut((s * 0.3, 0.2, 0), (s * 0.05, 0, 1.7), 0.035, 0.02, "softwood", "leg")
	kit.strut((0, -0.5, 0), (0, 0, 1.65), 0.035, 0.02, "softwood", "back_leg")
	kit.box((0.6, 0.05, 0.03), (0, 0.16, 0.75), "softwood", "ledge")
	kit.box((0.6, 0.012, 0.8), (0, 0.12, 1.17), "plywood", "board", rot=(-7, 0, 0))


def library_shelf(w=1.0, h=1.8, double=True):
	d = 0.5 if double else 0.28
	with kit.hollow(0.2):
		for s in (-1, 1):
			kit.box((0.025, d, h), (s * (w / 2 - 0.0125), 0, h / 2), "hardwood", "end")
		kit.box((w - 0.05, 0.012, h), (0, 0 if double else -d / 2 + 0.006, h / 2), "hardwood", "spine")
		n = int(h / 0.33)
		for i in range(n + 1):
			z = 0.08 + i * (h - 0.1) / n
			kit.box((w - 0.05, d, 0.02), (0, 0, z), "hardwood", "shelf")
			if i < n:
				for sy in ((-1, 1) if double else (1,)):
					y = sy * d / 4 if double else 0.0
					for j, c in enumerate(("fabric_red", "fabric_blue", "fabric_green", "fabric_grey")):
						bw = (w - 0.1) / 4
						kit.box((bw - 0.02, d / 2 - 0.05 if double else d - 0.06, 0.22 + 0.02 * ((i + j) % 3)), (-w / 2 + 0.05 + bw * (j + 0.5), y, z + 0.13), c, "books")


def book_trolley():
	for s in (-1, 1):
		kit.box((0.02, 0.4, 0.9), (s * 0.4, 0, 0.55), "steel_painted", "end")
	for z, r in ((0.3, 12), (0.65, 12), (0.98, 0)):
		kit.box((0.8, 0.4, 0.02), (0, 0, z), "steel_painted", "shelf", rot=(r, 0, 0))
	castors(0.8, 0.4, 0.05)


def wall_bars(w=0.9, h=2.5):
	for s in (-1, 1):
		kit.box((0.04, 0.12, h), (s * w / 2, 0.06, h / 2), "hardwood", "upright")
	for i in range(14):
		kit.rod((-w / 2, 0.08, 0.2 + i * (h - 0.3) / 13), (w / 2, 0.08, 0.2 + i * (h - 0.3) / 13), 0.018, "hardwood", "bar", segs=10)


def gym_bench(w=2.7):
	kit.box((w, 0.25, 0.04), (0, 0, 0.31), "hardwood", "top")
	kit.box((w - 0.4, 0.1, 0.05), (0, 0, 0.08), "hardwood", "rail")
	for s in (-1, 1):
		kit.box((0.04, 0.3, 0.29), (s * (w / 2 - 0.25), 0, 0.145), "hardwood", "leg")


def vault_box():
	for i in range(4):
		w = 0.9 - i * 0.07
		kit.prism([(-w / 2, 0), (w / 2, 0), (w / 2 - 0.035, 0.26), (-w / 2 + 0.035, 0.26)], 1.3, (0, 0, i * 0.265), "softwood", "section", axis="y")
	kit.rounded_box((0.55, 1.3, 0.08), (0, 0, 1.1), "leather_black", "pad", radius=0.03)


def gym_mat(w=1.2, l=2.4):
	kit.rounded_box((w, l, 0.06), (0, 0, 0.03), "plastic_blue", "mat", radius=0.02)


def hoop(h=3.05, wall=True):
	if not wall:
		kit.box((1.0, 1.4, 0.3), (0, -1.6, 0.15), "plastic_black", "base")
		kit.strut((0, -1.6, 0.3), (0, -0.3, h + 0.2), 0.12, 0.12, "steel_painted", "arm")
	kit.box((1.8, 0.04, 1.05), (0, 0.02 if wall else -0.2, h + 0.4), "paint_white", "backboard")
	y0 = 0.04 if wall else -0.18
	kit.sweep([(0.225 * math.cos(math.radians(a)), y0 + 0.24 + 0.225 * math.sin(math.radians(a)), h) for a in range(0, 361, 20)], kit.circle(0.009, 6), "hazard_red", "ring")
	kit.cyl(0.225, 0.4, (0, y0 + 0.24, h - 0.2), "fabric_white", "net", segs=12, r2=0.14)


def goal(w=3.66, h=1.83, d=1.2):
	r = 0.035
	for s in (-1, 1):
		kit.rod((s * w / 2, 0, 0), (s * w / 2, 0, h), r, "paint_white", "post")
		kit.rod((s * w / 2, 0, h), (s * w / 2, -d, 0), 0.015, "paint_white", "stay")
		kit.rod((s * w / 2, 0, 0), (s * w / 2, -d, 0), 0.015, "paint_white", "ground_bar")
	kit.rod((-w / 2, 0, h), (w / 2, 0, h), r, "paint_white", "crossbar")
	kit.rod((-w / 2, -d, 0), (w / 2, -d, 0), 0.015, "paint_white", "back_bar")


def climbing_frame():
	r = 0.03
	for x in (-1, 1):
		for y in (-1, 1):
			kit.rod((x, y, 0), (x, y, 2.4), 0.05, "softwood", "post", segs=10)
	kit.box((2.0, 2.0, 0.05), (0, 0, 1.2), "softwood", "deck")
	for z in (1.6, 2.0):
		for s in (-1, 1):
			kit.rod((-1, s, z), (1, s, z), r, "plastic_red", "rail")
		kit.rod((-1, -1, z), (-1, 1, z), r, "plastic_red", "rail")
	for i in range(5):
		kit.rod((-1, -1.05, 0.2 + i * 0.22), (1, -1.05, 0.2 + i * 0.22), 0.02, "plastic_yellow", "rung")
	slide(at=(1.0, 0), top=1.2)
	kit.prism([(-1.1, 0), (1.1, 0), (0, 0.7)], 2.2, (0, 0, 2.4), "plastic_green", "roof", axis="y")


def slide(at=(0, 0), top=1.5, ladder=False):
	x, y = at
	run = top * 1.6
	kit.sweep([(x, y, top), (x + run * 0.75, y, top * 0.2), (x + run, y, 0.18), (x + run + 0.4, y, 0.18)], [(-0.25, 0.12), (-0.25, 0), (0.25, 0), (0.25, 0.12), (0.22, 0.12), (0.22, 0.03), (-0.22, 0.03), (-0.22, 0.12)], "plastic_yellow", "chute", up=(0, 0, 1))
	kit.rod((x + run, y, 0), (x + run, y, 0.18), 0.03, "steel_galvanised", "foot")
	if ladder:
		for s in (-1, 1):
			kit.rod((x - 0.7, y + s * 0.22, 0), (x, y + s * 0.22, top), 0.022, "steel_galvanised", "stile")
			kit.rod((x, y + s * 0.22, top), (x, y + s * 0.22, top + 0.6), 0.022, "steel_galvanised", "handrail")
		for i in range(1, 6):
			f = i / 6
			kit.rod((x - 0.7 * (1 - f), y - 0.22, top * f), (x - 0.7 * (1 - f), y + 0.22, top * f), 0.015, "steel_galvanised", "rung")


def swing(seats=2):
	w = 1.1 * seats + 0.6
	for s in (-1, 1):
		for sy in (-1, 1):
			kit.rod((s * w / 2, sy * 1.0, 0), (s * w / 2, 0, 2.3), 0.035, "steel_painted", "a_frame")
	kit.rod((-w / 2, 0, 2.3), (w / 2, 0, 2.3), 0.04, "steel_painted", "beam")
	for i in range(seats):
		x = -w / 2 + 0.3 + 1.1 * (i + 0.5)
		for s in (-1, 1):
			kit.rod((x + s * 0.2, 0, 2.3), (x + s * 0.2, 0, 0.5), 0.005, "steel_galvanised", "chain", segs=5)
		kit.box((0.45, 0.16, 0.03), (x, 0, 0.5), "rubber", "seat")


def seesaw():
	kit.cyl(0.06, 0.5, (0, 0, 0.25), "steel_painted", "pivot", segs=12)
	kit.box((3.0, 0.2, 0.05), (0, 0, 0.55), "softwood", "plank", rot=(0, 10, 0))
	for s in (-1, 1):
		z = 0.55 - s * 0.24
		kit.rod((s * 1.15, -0.15, z + 0.2), (s * 1.15, 0.15, z + 0.2), 0.015, "plastic_red", "handle")
		kit.rod((s * 1.15, 0, z), (s * 1.15, 0, z + 0.2), 0.015, "plastic_red", "handle_post")


def sandpit(w=3.0):
	for a in range(4):
		c, s = math.cos(a * math.pi / 2), math.sin(a * math.pi / 2)
		kit.box(((0.15, w, 0.3) if abs(c) > 0.5 else (w, 0.15, 0.3)), (c * w / 2, s * w / 2, 0.15), "softwood", "edge")
	kit.box((w - 0.1, w - 0.1, 0.2), (0, 0, 0.1), "render", "sand")


def cycle_shelter(w=4.0):
	for x in (-w / 2 + 0.1, w / 2 - 0.1):
		kit.sweep([(x, -1.0, 0), (x, -1.0, 1.8), (x, -0.6, 2.2), (x, 1.1, 2.1)], kit.circle(0.04, 10), "steel_galvanised", "hoop_frame", up=(1, 0, 0))
	kit.sweep([(0, -1.0, 1.8), (0, -0.6, 2.2), (0, 1.1, 2.1)], [(-w / 2, 0), (w / 2, 0), (w / 2, 0.006), (-w / 2, 0.006)], "glass", "canopy")
	kit.box((w, 0.006, 1.6), (0, -1.0, 1.0), "glass", "back_panel")
	for i in range(int(w / 0.8)):
		x = -w / 2 + 0.5 + i * 0.8
		kit.sweep([(x, -0.4, 0), (x, -0.4, 0.75), (x, 0.4, 0.75), (x, 0.4, 0)], kit.circle(0.024, 8), "steel_galvanised", "stand", up=(1, 0, 0))


def servery(w=3.0):
	with kit.stage("counter"):
		carcass(w, 0.7, 0.87, "steel_stainless", doors=int(w / 0.75), plinth=0.12)
		kit.box((w, 0.8, 0.03), (0, 0, 0.885), "steel_stainless", "top")
		kit.rod((-w / 2, 0.55, 0.85), (w / 2, 0.55, 0.85), 0.015, "steel_stainless", "tray_rail")
		kit.rod((-w / 2, 0.68, 0.85), (w / 2, 0.68, 0.85), 0.015, "steel_stainless", "tray_rail")
	with kit.stage("gantry"):
		for i in range(int(w / 0.75)):
			x = -w / 2 + 0.375 + i * 0.75
			kit.box((0.53, 0.33, 0.01), (x, 0, 0.902), "steel_galvanised", "bain_marie")
		for s in (-1, 1):
			kit.rod((s * (w / 2 - 0.05), 0.25, 0.9), (s * (w / 2 - 0.05), 0.25, 1.35), 0.012, "steel_stainless", "post")
		kit.box((w - 0.05, 0.4, 0.008), (0, 0.15, 1.35), "glass", "sneeze_screen")


def stage_block(w=2.0, d=1.0, h=0.4):
	kit.box((w, d, 0.03), (0, 0, h - 0.015), "plywood", "deck")
	legs(w, d, h - 0.03, 0.04, "aluminium", inset=0.02)
	kit.frame(w, h - 0.03, 0.03, 0.03, at=(0, d / 2 - 0.03, 0), slot="aluminium", name="frame")


def lectern():
	kit.box((0.5, 0.4, 1.0), (0, 0, 0.5), "hardwood", "body")
	kit.box((0.6, 0.45, 0.025), (0, 0.02, 1.08), "hardwood", "top", rot=(18, 0, 0))
	kit.rod((0.15, -0.1, 1.05), (0.15, 0.0, 1.35), 0.005, "plastic_black", "mic")


def drinking_fountain():
	kit.rounded_box((0.35, 0.3, 0.75), (0, 0.15, 0.375), "steel_stainless", "body", radius=0.03)
	kit.lathe([(0.02, 0), (0.15, 0.03), (0.17, 0.07)], (0, 0.16, 0.75), "steel_stainless", "bowl")
	kit.sweep([(0.1, 0.1, 0.8), (0.1, 0.1, 0.9), (0.04, 0.14, 0.92)], kit.circle(0.008, 6), "steel_stainless", "spout")


def clock(r=0.15, z=2.2):
	kit.cyl(r, 0.04, (0, 0.02, z), "plastic_black", "rim", axis="y", segs=28)
	kit.cyl(r - 0.012, 0.004, (0, 0.041, z), "enamel", "face", axis="y", segs=28)
	kit.box((0.01, 0.003, r * 0.7), (0, 0.044, z + r * 0.3), "plastic_black", "hand")
	kit.box((r * 0.5, 0.003, 0.012), (r * 0.22, 0.044, z), "plastic_black", "hand")


def globe():
	kit.cyl(0.1, 0.02, (0, 0, 0.01), "hardwood", "base", segs=18)
	kit.rod((0, 0, 0.02), (0, 0, 0.1), 0.01, "brass", "stem")
	kit.sphere(0.15, (0, 0, 0.27), "plastic_blue", "globe", segs=24)
	kit.sweep([(0.17 * math.cos(math.radians(a)), 0, 0.27 + 0.17 * math.sin(math.radians(a))) for a in range(-90, 91, 15)], kit.rect(0.012, 0.004), "brass", "meridian", up=(0, 1, 0))


def music_stand():
	for i in range(3):
		a = math.radians(120 * i)
		kit.rod((0, 0, 0.25), (0.3 * math.cos(a), 0.3 * math.sin(a), 0), 0.008, "plastic_black", "leg", segs=6)
	kit.rod((0, 0, 0.2), (0, 0, 1.15), 0.01, "plastic_black", "stem")
	kit.box((0.48, 0.008, 0.33), (0, 0.03, 1.25), "plastic_black", "desk", rot=(-20, 0, 0))


def tiered_seating(w=4.0, rows=4):
	with kit.hollow(0.15):
		for i in range(rows):
			kit.box((w, 0.8, 0.4 * (i + 1)), (0, -i * 0.8, 0.2 * (i + 1)), "plywood", "tier")
			kit.rounded_box((w - 0.1, 0.4, 0.05), (0, -i * 0.8 - 0.15, 0.4 * (i + 1) + 0.025), "fabric_blue", "seat_pad", radius=0.02)


reg("school.board.whiteboard_2400", whiteboard, "Whiteboard, 2.4 m", "wall")
reg("school.board.whiteboard_1200", whiteboard, "Whiteboard, 1.2 m", "wall", "office", w=1.2, h=0.9)
reg("school.board.blackboard", whiteboard, "Chalkboard, 2.4 m", "wall", face="plastic_black")
reg("school.board.pinboard", whiteboard, "Pinboard, 1.8 m", "wall", "office", w=1.8, h=1.2, face="fabric_blue")
reg("school.board.smartboard", whiteboard, "Interactive screen, 86 inch", "wall", "office", w=1.95, h=1.15, face="screen")
reg("school.board.mobile", mobile_board, "Mobile whiteboard", "office")
reg("school.av.projector", projector, "Ceiling projector", "ceiling", "office")
reg("school.cloak.coat_rail", coat_rail, "Coat hook rail, 1.8 m", "wall")
reg("school.cloak.bench", cloak_bench, "Cloakroom bench with hooks")
reg("school.desk.table_double", pupil_table, "Pupil table, double")
reg("school.desk.table_single", pupil_table, "Pupil table, single", w=0.6)
reg("school.desk.set_double", pupil_set, "Pupil table and two chairs")
reg("school.desk.set_group", pupil_set, "Group table and three chairs", w=1.8, seats=3)
reg("school.desk.exam", pupil_set, "Exam desk and chair", w=0.6, d=0.6, h=0.72, seats=1)
reg("school.desk.nursery", pupil_set, "Nursery table and chairs", w=1.2, d=0.6, h=0.5, seats=2)
reg("school.lab.bench", science_bench, "Science bench with sink and gas")
reg("school.lab.fume_cupboard", fume_cupboard, "Fume cupboard", "hospital")
reg("school.art.easel", easel, "Art easel")
reg("school.library.shelf_double", library_shelf, "Library shelving, double sided", "office")
reg("school.library.shelf_wall", library_shelf, "Library shelving, wall", "office", double=False)
reg("school.library.shelf_low", library_shelf, "Library shelving, low", h=1.2)
reg("school.library.book_trolley", book_trolley, "Book trolley")
reg("school.gym.wall_bars", wall_bars, "Gym wall bars", "wall", "sport")
reg("school.gym.bench", gym_bench, "Gym bench", "sport")
reg("school.gym.vault_box", vault_box, "Vaulting box", "sport")
reg("school.gym.mat", gym_mat, "Gym mat", "sport")
reg("school.gym.hoop_wall", hoop, "Basketball hoop, wall", "wall", "sport")
reg("school.gym.hoop_post", hoop, "Basketball hoop, freestanding", "sport", "outdoor", wall=False)
reg("school.play.goal_junior", goal, "Football goal, junior", "sport", "outdoor")
reg("school.play.goal_full", goal, "Football goal, full size", "sport", "outdoor", w=7.32, h=2.44, d=2.0)
reg("school.play.climbing_frame", climbing_frame, "Climbing frame with slide", "outdoor")
reg("school.play.slide", slide, "Slide", "outdoor", ladder=True)
reg("school.play.swing_2", swing, "Swings, two seat", "outdoor")
reg("school.play.swing_4", swing, "Swings, four seat", "outdoor", seats=4)
reg("school.play.seesaw", seesaw, "Seesaw", "outdoor")
reg("school.play.sandpit", sandpit, "Sandpit", "outdoor")
reg("school.play.cycle_shelter", cycle_shelter, "Cycle shelter, 4 m", "outdoor", "office")
reg("school.canteen.servery", servery, "Canteen servery counter, 3 m", "hospital", "office")
reg("school.hall.stage_block", stage_block, "Stage block, 2 m by 1 m")
reg("school.hall.lectern", lectern, "Lectern", "office")
reg("school.hall.tiered_seating", tiered_seating, "Tiered seating, 4 rows")
reg("school.hall.music_stand", music_stand, "Music stand")
reg("school.misc.drinking_fountain", drinking_fountain, "Drinking fountain", "wall", "sport")
reg("school.misc.clock", clock, "Wall clock", "wall", "office", "hospital")
reg("school.misc.globe", globe, "Globe")


# --- office --------------------------------------------------------------------------------

def bench_desk(seats=4, w=1.4, d=0.8, h=0.74):
	n = seats // 2
	with kit.stage("desk"):
		kit.box((w * n, d * 2, 0.025), (0, 0, h - 0.0125), "laminate_white", "top")
		for i in range(n + 1):
			x = -w * n / 2 + i * w
			x = min(max(x, -w * n / 2 + 0.03), w * n / 2 - 0.03)
			kit.frame(0.06, h - 0.025, 0.05, d * 2 - 0.2, at=(x, 0, 0), slot="steel_painted", name="leg_frame", bottom=False)
		kit.box((w * n - 0.1, 0.03, 0.4), (0, 0, h + 0.2), "fabric_blue", "screen_divider")
	with kit.stage("kit"):
		for i in range(n):
			x = -w * n / 2 + w * (i + 0.5)
			for s in (-1, 1):
				monitor((x, s * 0.2, h), face=0 if s > 0 else 180)
				kit.box((0.44, 0.14, 0.02), (x, s * 0.5, h + 0.01), "plastic_black", "keyboard")
	with kit.stage("chairs"):
		for i in range(n):
			x = -w * n / 2 + w * (i + 0.5)
			task_chair((x, d + 0.25))
			task_chair((x, -d - 0.25))


def sit_stand(w=1.6, d=0.8, h=1.1):
	kit.box((w, d, 0.025), (0, 0, h - 0.0125), "laminate_white", "top")
	for s in (-1, 1):
		kit.box((0.08, 0.7, 0.03), (s * (w / 2 - 0.2), 0, 0.015), "steel_painted", "foot")
		kit.box((0.08, 0.06, h - 0.055), (s * (w / 2 - 0.2), 0, 0.03 + (h - 0.055) / 2), "steel_painted", "column")
	monitor((0, -0.2, h))


def pedestal():
	carcass(0.42, 0.56, 0.56, "steel_painted", drawers=3, plinth=0.0)
	castors(0.42, 0.56, 0.025, -0.0)


def screen_partition(w=1.6, h=1.6, slot="fabric_blue"):
	kit.box((w, 0.05, h - 0.05), (0, 0, 0.05 + (h - 0.05) / 2), slot, "panel")
	kit.frame(w, h, 0.03, 0.055, at=(0, 0, 0), slot="aluminium", name="trim")
	for s in (-1, 1):
		kit.box((0.05, 0.45, 0.02), (s * (w / 2 - 0.1), 0, 0.01), "aluminium", "foot")


def phone_booth(w=1.1, d=1.0, h=2.2):
	with kit.hollow(0.08):
		for s in (-1, 1):
			kit.box((0.06, d, h), (s * (w / 2 - 0.03), 0, h / 2), "fabric_grey", "side")
		kit.box((w, 0.06, h), (0, -d / 2 + 0.03, h / 2), "fabric_grey", "back")
		kit.box((w, d, 0.08), (0, 0, h - 0.04), "laminate_white", "roof")
		kit.box((w, d, 0.04), (0, 0, 0.02), "carpet", "floor")
	kit.box((w - 0.12, 0.012, h - 0.12), (0, d / 2 - 0.02, h / 2), "glass", "door")
	kit.box((0.6, 0.3, 0.03), (0, -d / 2 + 0.22, 1.0), "laminate_white", "shelf")
	kit.rounded_box((0.4, 0.35, 0.08), (0, -0.1, 0.5), "fabric_blue", "stool", radius=0.03)
	kit.cyl(0.03, 0.46, (0, -0.1, 0.23), "steel_stainless", "stool_post", segs=10)


def meeting_pod(w=2.2, d=1.6, h=1.4):
	for s in (-1, 1):
		with kit.hollow(0.3):
			kit.rounded_box((w * 0.28, d, h), (s * (w / 2 - w * 0.14), 0, h / 2), "fabric_grey", "booth_back", radius=0.05)
		kit.rounded_box((0.5, d - 0.1, 0.14), (s * (w / 2 - w * 0.28 - 0.25), 0, 0.42), "fabric_blue", "seat", radius=0.04)
		kit.box((0.48, d - 0.12, 0.35), (s * (w / 2 - w * 0.28 - 0.25), 0, 0.175), "fabric_grey", "seat_base")
	table(0.6, d - 0.4, 0.74, "laminate_white", "steel_painted")


def pc_tower():
	kit.rounded_box((0.18, 0.42, 0.4), (0, 0, 0.2), "plastic_black", "case", radius=0.01)
	kit.box((0.14, 0.004, 0.1), (0, 0.211, 0.3), "plastic_grey", "bays")


def laptop():
	kit.box((0.32, 0.22, 0.015), (0, 0, 0.0075), "aluminium", "base")
	kit.box((0.32, 0.012, 0.21), (0, -0.13, 0.11), "aluminium", "lid", rot=(-18, 0, 0))
	kit.box((0.3, 0.004, 0.19), (0, -0.123, 0.112), "screen", "screen", rot=(-18, 0, 0))


def monitor_asset(size=0.6):
	monitor((0, 0, 0), size)


def printer():
	kit.rounded_box((0.45, 0.4, 0.3), (0, 0, 0.15), "plastic_white", "body", radius=0.02)
	kit.box((0.3, 0.2, 0.01), (0, 0.25, 0.1), "plastic_grey", "tray")
	kit.box((0.12, 0.004, 0.06), (0.12, 0.2, 0.27), "screen", "panel", rot=(-30, 0, 0))


def shredder():
	kit.rounded_box((0.38, 0.28, 0.55), (0, 0, 0.275), "plastic_grey", "bin", radius=0.02)
	kit.rounded_box((0.4, 0.3, 0.12), (0, 0, 0.61), "plastic_black", "head", radius=0.02)


def recycling(bins=3):
	cols = ("plastic_green", "plastic_blue", "plastic_grey", "plastic_red")
	for i in range(bins):
		x = (i - (bins - 1) / 2) * 0.42
		with kit.hollow(0.08):
			kit.rounded_box((0.4, 0.4, 0.8), (x, 0, 0.4), "steel_painted", "bin", radius=0.02)
		kit.box((0.4, 0.4, 0.08), (x, 0, 0.84), cols[i % 4], "lid")
		kit.box((0.2, 0.01, 0.09), (x, 0.2, 0.7), "plastic_black", "slot")


def planter(w=1.0, d=0.4, h=0.7, round_=False):
	with kit.hollow(0.3):
		if round_:
			kit.lathe([(w * 0.35, 0), (w / 2, h)], (0, 0, 0), "ceramic", "pot")
		else:
			kit.box((w, d, h), (0, 0, h / 2), "laminate_white", "trough")
	n = 1 if round_ else max(1, int(w / 0.35))
	for i in range(n):
		x = 0 if round_ else -w / 2 + w * (i + 0.5) / n
		kit.sphere(0.22 if not round_ else w * 0.5, (x, 0, h + (0.2 if not round_ else w * 0.5)), "foliage", "plant", segs=10)
		kit.rod((x, 0, h - 0.05), (x, 0, h + 0.15), 0.015, "bark", "stem", segs=6)


def tea_point(w=2.4):
	carcass(w, 0.58, 0.87, "laminate_grey", doors=int(w / 0.6), plinth=0.1)
	kit.box((w, 0.62, 0.03), (0, 0, 0.885), "worktop", "top")
	kit.rounded_box((0.45, 0.38, 0.015), (-w / 2 + 0.4, 0, 0.902), "steel_stainless", "sink", radius=0.006)
	kit.sweep([(-w / 2 + 0.4, -0.23, 0.9), (-w / 2 + 0.4, -0.23, 1.15), (-w / 2 + 0.4, -0.1, 1.15)], kit.circle(0.011, 8), "steel_stainless", "tap", up=(1, 0, 0))
	kit.rounded_box((0.3, 0.4, 0.4), (w / 2 - 0.3, -0.05, 1.1), "plastic_black", "coffee_machine", radius=0.02)
	for i in range(int(w / 0.6)):
		kit.box((0.596, 0.32, 0.7), (-w / 2 + 0.3 + i * 0.6, -0.13, 1.8), "laminate_grey", "wall_unit")


def speed_gate(lanes=1):
	for i in range(lanes + 1):
		x = (i - lanes / 2) * 0.9
		kit.rounded_box((0.2, 1.4, 1.0), (x, 0, 0.5), "steel_stainless", "pedestal", radius=0.04)
		kit.box((0.1, 0.1, 0.005), (x, 0.5, 1.003), "screen", "reader")
	for i in range(lanes):
		x = (i - lanes / 2 + 0.5) * 0.9
		for s in (-1, 1):
			kit.box((0.3, 0.012, 0.8), (x + s * 0.2, 0, 0.55), "glass", "wing")


def safe():
	with kit.hollow(0.5):
		kit.box((0.6, 0.55, 0.9), (0, 0, 0.45), "steel_painted", "body")
	kit.box((0.52, 0.03, 0.82), (0, 0.29, 0.45), "steel_painted", "door")
	kit.cyl(0.05, 0.03, (0.05, 0.32, 0.5), "steel_stainless", "dial", axis="y", segs=18)
	kit.rod((-0.12, 0.32, 0.42), (-0.12, 0.32, 0.58), 0.012, "steel_stainless", "handle")


def post_trolley():
	kit.frame(0.5, 0.95, 0.025, 0.025, at=(0, -0.3, 0), slot="steel_galvanised", name="handle_frame")
	for z in (0.2, 0.6):
		with kit.hollow(0.1):
			kit.box((0.5, 0.6, 0.25), (0, 0, z + 0.125), "plastic_red", "tray")
	castors(0.5, 0.6, 0.05)


def projection_screen(w=2.4, h=1.5):
	kit.cyl(0.04, w + 0.1, (0, 0.05, 2.5), "paint_white", "case", axis="x", segs=12)
	kit.box((w, 0.003, h), (0, 0.05, 2.5 - h / 2), "fabric_white", "screen")
	kit.box((w, 0.02, 0.03), (0, 0.05, 2.5 - h), "plastic_black", "bar")


def umbrella_stand():
	with kit.hollow(0.1):
		kit.tube(0.13, 0.5, (0, 0, 0.25), "steel_stainless", "stand", wall=0.01)
	kit.rod((0.03, 0.02, 0.05), (0.08, 0.05, 0.85), 0.012, "plastic_black", "umbrella")


def conference_phone():
	kit.prism([(0.14 * math.cos(math.radians(a)), 0.14 * math.sin(math.radians(a))) for a in (90, 210, 330)], 0.04, (0, 0, 0.02), "plastic_black", "phone", axis="z")


def reception_sofa(w=1.8):
	kit.rounded_box((w, 0.7, 0.3), (0, 0, 0.3), "leather_black", "seat", radius=0.05)
	kit.rounded_box((w, 0.15, 0.4), (0, -0.28, 0.6), "leather_black", "back", radius=0.05)
	legs(w, 0.7, 0.15, 0.03, "steel_stainless", inset=0.05)


reg("office.desk.bench_4", bench_desk, "Bench desk, four person")
reg("office.desk.bench_6", bench_desk, "Bench desk, six person", seats=6)
reg("office.desk.bench_8", bench_desk, "Bench desk, eight person", seats=8)
reg("office.desk.sit_stand", sit_stand, "Sit-stand desk")
reg("office.desk.pedestal", pedestal, "Desk pedestal")
reg("office.screen.partition_1600", screen_partition, "Screen partition, 1.6 m")
reg("office.screen.partition_low", screen_partition, "Screen partition, low", h=1.2, w=1.2)
reg("office.screen.acoustic", screen_partition, "Acoustic screen, 1.8 m", w=1.8, h=1.8, slot="fabric_grey")
reg("office.pod.phone_booth", phone_booth, "Phone booth", "airport")
reg("office.pod.meeting", meeting_pod, "Meeting pod, four seat", "airport")
reg("office.it.pc_tower", pc_tower, "Desktop computer", "school")
reg("office.it.laptop", laptop, "Laptop", "school", "home")
reg("office.it.monitor_24", monitor_asset, "Monitor, 24 inch", "school", size=0.55)
reg("office.it.monitor_32", monitor_asset, "Monitor, 32 inch", size=0.72)
reg("office.it.printer", printer, "Desktop printer", "school", "home")
reg("office.it.shredder", shredder, "Shredder")
reg("office.it.conference_phone", conference_phone, "Conference phone")
reg("office.it.projection_screen", projection_screen, "Projection screen", "wall", "school")
reg("office.waste.recycling_3", recycling, "Recycling bins, three", "school", "airport")
reg("office.waste.recycling_2", recycling, "Recycling bins, two", "school", bins=2)
reg("office.waste.bin", recycling, "Waste bin", "school", "hospital", bins=1)
reg("office.planter.trough", planter, "Planter trough", "airport", "hospital")
reg("office.planter.long", planter, "Planter trough, 2 m", "airport", w=2.0)
reg("office.planter.round", planter, "Planter, round", "airport", "home", w=0.5, h=0.5, round_=True)
reg("office.kitchen.tea_point", tea_point, "Tea point, 2.4 m", "school", "hospital", "police")
reg("office.entrance.speed_gate_1", speed_gate, "Speed gate, one lane", "airport")
reg("office.entrance.speed_gate_3", speed_gate, "Speed gates, three lanes", "airport", lanes=3)
reg("office.entrance.umbrella_stand", umbrella_stand, "Umbrella stand")
reg("office.entrance.reception_sofa", reception_sofa, "Reception sofa", "hospital")
reg("office.misc.safe", safe, "Safe", "police")
reg("office.misc.post_trolley", post_trolley, "Post trolley")


# --- police --------------------------------------------------------------------------------

def custody_desk(w=3.6):
	with kit.hollow(0.2):
		kit.box((w, 0.9, 1.25), (0, 0, 0.625), "laminate_grey", "plinth")
		kit.box((w + 0.1, 1.0, 0.05), (0, 0, 1.275), "worktop", "counter")
	for i in range(int(w / 1.2)):
		x = -w / 2 + 0.6 + i * 1.2
		kit.box((1.1, 0.012, 0.7), (x, 0.3, 1.65), "glass", "screen")
		monitor((x, -0.2, 1.0), 0.5, 180)
	kit.box((w, 1.4, 0.3), (0, -1.1, 0.15), "vinyl_floor", "raised_floor")


def cell_wc():
	with kit.hollow(0.2):
		kit.lathe([(0.14, 0), (0.15, 0.3), (0.2, 0.42)], (0, 0.28, 0), "steel_stainless", "pan", scale=(1, 1.2, 1))
		kit.box((0.4, 0.12, 0.9), (0, 0.06, 0.45), "steel_stainless", "back_panel")
	kit.lathe([(0.02, 0), (0.14, 0.05)], (0, 0.14, 0.9), "steel_stainless", "basin")
	kit.cyl(0.015, 0.01, (0.1, 0.125, 0.75), "steel_stainless", "push_button", axis="y", segs=10)


def cell_bed(w=2.0, d=0.75):
	with kit.hollow(0.6):
		kit.box((w, d, 0.4), (0, 0, 0.2), "concrete", "plinth")
	kit.rounded_box((w - 0.06, d - 0.06, 0.1), (0, 0, 0.45), "plastic_blue", "mattress", radius=0.03)


def cell_door(w=0.95, h=2.05):
	kit.frame(w + 0.16, h + 0.08, 0.08, 0.14, at=(0, 0, 0), slot="steel_painted", name="frame", bottom=False)
	with kit.stage("leaf"):
		kit.box((w, 0.06, h), (0, 0, h / 2), "steel_painted", "leaf")
		kit.box((0.25, 0.065, 0.2), (0, 0, 1.5), "glass", "viewer")
		kit.box((0.35, 0.07, 0.12), (0, 0, 1.0), "steel_stainless", "hatch")
		kit.box((0.1, 0.09, 0.25), (w / 2 - 0.1, 0, 1.05), "steel_stainless", "lock")
	kit.socket("hinge", (-w / 2, 0, 0))


def bars(w=2.4, h=2.4):
	for z in (0.1, h / 2, h - 0.1):
		kit.box((w, 0.05, 0.012), (0, 0, z), "steel_painted", "flat")
	for i in range(int(w / 0.12) + 1):
		kit.rod((-w / 2 + i * w / int(w / 0.12), 0, 0), (-w / 2 + i * w / int(w / 0.12), 0, h), 0.011, "steel_painted", "bar", segs=8)


def fingerprint_station():
	carcass(0.7, 0.6, 1.0, "steel_painted", doors=1, plinth=0.05)
	kit.box((0.3, 0.3, 0.08), (0, 0.05, 1.04), "plastic_grey", "scanner")
	kit.box((0.2, 0.15, 0.004), (0, 0.05, 1.082), "glass", "platen")
	monitor((0, -0.2, 1.0), 0.45)


def gun_cabinet():
	with kit.hollow(0.4):
		kit.box((0.6, 0.35, 1.5), (0, 0.175, 0.75), "steel_painted", "body")
	kit.box((0.56, 0.02, 1.46), (0, 0.36, 0.75), "steel_painted", "door")
	for z in (0.5, 1.0):
		kit.cyl(0.02, 0.02, (0.2, 0.38, z), "brass", "lock", axis="y", segs=10)


def shield_rack(n=6):
	kit.frame(n * 0.2 + 0.1, 1.2, 0.03, 0.5, at=(0, 0, 0), slot="steel_painted", name="rack")
	for i in range(n):
		kit.sweep([(-(n - 1) * 0.1 + i * 0.2 + 0.05 * math.sin(math.pi * t / 6), -0.28 + 0.56 * t / 6, 0.6) for t in range(7)], kit.rect(0.006, 1.0), "glass", "shield")


def cctv_wall(cols=4, rows=2):
	for i in range(cols):
		for j in range(rows):
			x, z = (i - (cols - 1) / 2) * 1.0, 1.2 + j * 0.6
			kit.box((0.98, 0.05, 0.58), (x, 0.025, z), "plastic_black", "monitor")
			kit.box((0.95, 0.004, 0.55), (x, 0.052, z), "screen", "screen")


def control_desk(w=3.0):
	kit.sweep([(-w / 2, 0.3, 0.74), (-w / 4, 0, 0.74), (w / 4, 0, 0.74), (w / 2, 0.3, 0.74)], kit.rect(0.9, 0.03), "laminate_grey", "top", up=(0, 0, 1))
	for x, y in ((-w / 2 + 0.1, 0.3), (-w / 4, 0), (w / 4, 0), (w / 2 - 0.1, 0.3)):
		kit.box((0.06, 0.7, 0.72), (x, y, 0.36), "steel_painted", "leg")
	for x in (-w / 3, 0, w / 3):
		monitor((x, -0.15 + abs(x) * 0.25, 0.755), 0.6, 180)
		task_chair((x, 0.75 + abs(x) * 0.25))


def height_chart():
	kit.box((1.2, 0.01, 2.1), (0, 0.005, 1.05), "paint_white", "chart")
	for i in range(8):
		kit.box((1.2, 0.012, 0.012), (0, 0.006, 1.2 + i * 0.1), "plastic_black", "line")


def kennel(w=1.5, d=2.4, h=1.9):
	with kit.hollow(0.1):
		kit.box((w, 0.9, h), (0, -d / 2 + 0.45, h / 2), "blockwork", "sleeping_box")
	kit.grid_bars(w, h, (0, d / 2, h / 2), int(w / 0.08), 2, 0.006, "steel_galvanised", "front_mesh")
	for s in (-1, 1):
		kit.grid_bars(d - 0.9, h, (s * w / 2, 0.45, h / 2), int((d - 0.9) / 0.08), 2, 0.006, "steel_galvanised", "side_mesh", plane="yz")
	kit.box((w, d, 0.05), (0, 0, h + 0.025), "steel_galvanised", "roof")


def radio_mast(h=15.0):
	kit.box((1.5, 1.5, 0.4), (0, 0, 0.2), "concrete", "base")
	kit.lattice(h, 0.6, 0.05, 0.025, at=(0, 0, 0.4), bays=int(h / 0.8), slot="steel_galvanised", name="mast")
	for z, a in ((h - 1, 0), (h - 2, 120), (h - 3, 240)):
		kit.box((0.15, 0.08, 1.2), (0.42 * math.cos(math.radians(a)), 0.42 * math.sin(math.radians(a)), z), "plastic_white", "antenna")
	kit.cyl(0.3, 0.1, (0.4, 0, h - 5), "plastic_white", "dish", axis="x", segs=20)


def breath_machine():
	kit.rounded_box((0.45, 0.35, 0.25), (0, 0, 0.125), "plastic_grey", "body", radius=0.02)
	kit.box((0.2, 0.004, 0.12), (-0.08, 0.176, 0.15), "screen", "display")
	kit.rod((0.15, 0.17, 0.15), (0.25, 0.3, 0.05), 0.008, "plastic_black", "tube", segs=6)


def id_parade_window(w=2.4, h=1.2):
	kit.frame(w, h, 0.06, 0.12, at=(0, 0, 0.9), slot="steel_painted", name="frame")
	kit.box((w - 0.1, 0.02, h - 0.1), (0, 0, 0.9 + h / 2), "mirror", "one_way_glass")


reg("police.custody.desk", custody_desk, "Custody desk, three position")
reg("police.custody.desk_small", custody_desk, "Custody desk, single", w=1.4)
reg("police.cell.wc", cell_wc, "Cell toilet and basin, stainless", "wall")
reg("police.cell.bed", cell_bed, "Cell bed plinth with mattress")
reg("police.cell.door", cell_door, "Cell door with hatch", "opening")
reg("police.cell.bars_2400", bars, "Cell bars, 2.4 m")
reg("police.cell.bars_1200", bars, "Cell bars, 1.2 m", w=1.2)
reg("police.id.fingerprint", fingerprint_station, "Fingerprint station")
reg("police.id.height_chart", height_chart, "Height chart", "wall")
reg("police.id.breath_machine", breath_machine, "Breath test machine")
reg("police.id.parade_window", id_parade_window, "Observation window, one way", "wall")
reg("police.store.gun_cabinet", gun_cabinet, "Firearms cabinet", "wall")
reg("police.store.shield_rack", shield_rack, "Riot shield rack")
reg("police.control.cctv_wall", cctv_wall, "CCTV monitor wall, 4 by 2", "wall", "airport")
reg("police.control.cctv_wall_small", cctv_wall, "CCTV monitor wall, 2 by 2", "wall", "office", cols=2)
reg("police.control.desk", control_desk, "Control room desk, three position", "airport")
reg("police.yard.kennel", kennel, "Dog kennel and run", "outdoor")
reg("police.yard.radio_mast", radio_mast, "Radio mast, 15 m", "outdoor", "airport")


# --- hospital ------------------------------------------------------------------------------

def trolley_bed(w=0.7, l=2.0, h=0.8, rails=True):
	with kit.stage("frame"):
		kit.box((w - 0.1, l - 0.3, 0.05), (0, 0, 0.2), "steel_painted", "base")
		for y in (-l / 4, l / 4):
			kit.box((0.08, 0.08, h - 0.3), (0, y, 0.2 + (h - 0.3) / 2), "steel_stainless", "column")
		kit.box((w, l, 0.04), (0, 0, h - 0.08), "steel_painted", "deck")
		castors(w, l - 0.2, 0.075)
	with kit.stage("soft"):
		kit.rounded_box((w - 0.04, l - 0.04, 0.1), (0, 0, h), "plastic_blue", "mattress", radius=0.03)
		kit.rounded_box((w - 0.2, 0.3, 0.06), (0, -l / 2 + 0.25, h + 0.08), "fabric_white", "pillow", radius=0.025)
	if rails:
		for s in (-1, 1):
			kit.sweep([(s * w / 2, -l / 4, h - 0.05), (s * w / 2, -l / 4, h + 0.3), (s * w / 2, l / 4, h + 0.3), (s * w / 2, l / 4, h - 0.05)], kit.circle(0.012, 8), "steel_stainless", "side_rail", up=(1, 0, 0))


def exam_couch():
	kit.rounded_box((0.65, 1.9, 0.08), (0, 0, 0.7), "leather_black", "pad", radius=0.03)
	kit.rounded_box((0.65, 0.5, 0.08), (0, -0.85, 0.82), "leather_black", "head_pad", radius=0.03, rot=(25, 0, 0))
	legs(0.65, 1.9, 0.66, 0.04, "steel_painted")
	kit.cyl(0.05, 0.6, (0, -1.0, 0.55), "fabric_white", "paper_roll", axis="x", segs=14)


def operating_table():
	kit.box((0.6, 0.9, 0.08), (0, 0, 0.04), "steel_stainless", "base")
	kit.box((0.25, 0.3, 0.75), (0, 0, 0.45), "steel_stainless", "column")
	for y, l in ((-0.7, 0.45), (-0.05, 0.8), (0.7, 0.65)):
		kit.rounded_box((0.52, l, 0.08), (0, y, 0.88), "leather_black", "pad", radius=0.03)
	for s in (-1, 1):
		kit.rod((s * 0.27, -0.4, 0.84), (s * 0.27, 0.9, 0.84), 0.008, "steel_stainless", "side_rail", segs=6)


def theatre_light(heads=2):
	kit.cyl(0.12, 0.05, (0, 0, 2.975), "paint_white", "rose", segs=18)
	kit.rod((0, 0, 2.95), (0, 0, 2.5), 0.03, "paint_white", "drop")
	for i in range(heads):
		s = 1 if i == 0 else -1
		kit.sweep([(0, 0, 2.5 - i * 0.08), (s * 0.7, 0, 2.5 - i * 0.08), (s * 0.9, 0.3, 2.2), (s * 0.6, 0.5, 1.95)], kit.circle(0.025, 8), "paint_white", "arm")
		kit.cyl(0.33, 0.08, (s * 0.6, 0.5, 1.92), "paint_white", "head", segs=24)
		kit.cyl(0.3, 0.01, (s * 0.6, 0.5, 1.875), "light_emitter", "lens", segs=24)


def anaesthetic_machine():
	kit.box((0.6, 0.6, 0.12), (0, 0, 0.16), "plastic_grey", "base")
	castors(0.6, 0.6, 0.05)
	carcass(0.55, 0.5, 0.75, "plastic_white", drawers=3, plinth=0.0)
	kit.box((0.55, 0.45, 0.5), (0, -0.05, 1.05), "plastic_white", "upper")
	monitor((0, 0.0, 1.3), 0.4)
	for x in (-0.18, 0.18):
		kit.cyl(0.04, 0.3, (x, 0.2, 1.0), "plastic_blue" if x < 0 else "plastic_yellow", "vaporiser", segs=10)
	kit.sweep([(0.2, 0.25, 0.9), (0.4, 0.5, 0.8), (0.3, 0.7, 1.0)], kit.circle(0.012, 8), "plastic_white", "breathing_hose")


def drip_stand():
	for i in range(5):
		a = math.radians(72 * i)
		kit.rod((0, 0, 0.08), (0.25 * math.cos(a), 0.25 * math.sin(a), 0.05), 0.012, "steel_stainless", "base", segs=6)
		kit.cyl(0.025, 0.02, (0.25 * math.cos(a), 0.25 * math.sin(a), 0.025), "rubber", "castor", axis="x", segs=8)
	kit.rod((0, 0, 0.06), (0, 0, 1.9), 0.012, "steel_stainless", "pole")
	for s in (-1, 1):
		kit.rod((0, 0, 1.9), (s * 0.12, 0, 1.95), 0.004, "steel_stainless", "hook", segs=5)
	kit.rounded_box((0.11, 0.03, 0.2), (0.12, 0, 1.8), "plastic_white", "bag", radius=0.012)
	kit.rounded_box((0.14, 0.12, 0.2), (0, 0.07, 1.2), "plastic_grey", "pump", radius=0.01)


def patient_monitor():
	for i in range(5):
		a = math.radians(72 * i)
		kit.rod((0, 0, 0.08), (0.25 * math.cos(a), 0.25 * math.sin(a), 0.05), 0.012, "steel_stainless", "base", segs=6)
	kit.rod((0, 0, 0.06), (0, 0, 1.2), 0.015, "steel_stainless", "pole")
	kit.rounded_box((0.36, 0.14, 0.28), (0, 0, 1.3), "plastic_white", "monitor", radius=0.02)
	kit.box((0.3, 0.004, 0.2), (0, 0.072, 1.31), "screen", "screen")
	with kit.hollow(0.1):
		kit.box((0.25, 0.2, 0.12), (0, 0, 0.8), "steel_galvanised", "basket")


def crash_cart(slot="plastic_red"):
	carcass(0.65, 0.5, 0.95, slot, drawers=5, plinth=0.12)
	castors(0.65, 0.5, 0.05)
	kit.box((0.67, 0.52, 0.03), (0, 0, 0.965), "plastic_grey", "top")
	kit.rounded_box((0.3, 0.25, 0.2), (0, 0, 1.08), "plastic_yellow", "defibrillator", radius=0.02)
	kit.rod((0.36, -0.2, 0.9), (0.36, 0.2, 0.9), 0.012, "steel_stainless", "push_handle")


def bedhead_trunking(w=1.8):
	kit.box((w, 0.07, 0.25), (0, 0.035, 1.5), "paint_white", "trunking")
	for i, c in enumerate(("plastic_white", "plastic_black", "plastic_yellow")):
		kit.cyl(0.022, 0.02, (-w / 2 + 0.2 + i * 0.12, 0.08, 1.52), c, "gas_outlet", axis="y", segs=10)
	for i in range(4):
		kit.box((0.085, 0.01, 0.085), (0.1 + i * 0.12, 0.075, 1.5), "plastic_white", "socket")
	kit.box((w * 0.5, 0.05, 0.03), (0, 0.06, 1.64), "light_emitter", "reading_light")


def bed_curtain(w=2.4, d=2.2):
	path = [(-w / 2, 0, 2.2), (-w / 2, d - 0.3, 2.2), (-w / 2 + 0.3, d, 2.2), (w / 2 - 0.3, d, 2.2), (w / 2, d - 0.3, 2.2), (w / 2, 0, 2.2)]
	kit.sweep(path, kit.rect(0.02, 0.03), "aluminium", "track", up=(0, 0, 1))
	for x in (-w / 2, w / 2):
		kit.rod((x, d - 0.1, 2.2), (x, d - 0.1, 2.7), 0.008, "aluminium", "hanger", segs=6)
	n = 16
	pts = [(-w / 2 + 0.03 * math.sin(i * 2.2), i * (d - 0.4) / n, 1.25) for i in range(n + 1)]
	kit.sweep(pts, kit.rect(0.004, 1.85), "fabric_blue", "curtain", up=(0, 0, 1))


def nurse_station(w=3.0):
	with kit.hollow(0.2):
		kit.box((w, 0.12, 1.1), (0, 0.4, 0.55), "laminate_white", "front")
		kit.box((w + 0.05, 0.3, 0.04), (0, 0.4, 1.12), "worktop", "upstand_top")
		for s in (-1, 1):
			kit.box((0.12, 0.9, 1.1), (s * (w / 2 - 0.06), 0, 0.55), "laminate_white", "return")
	kit.box((w - 0.24, 0.75, 0.03), (0, -0.02, 0.74), "laminate_white", "desk")
	for x in (-w / 4, w / 4):
		monitor((x, 0.15, 0.755), 0.5, 180)
		task_chair((x, -0.75))


def commode():
	chair((0, 0), 0, "plastic_white", "steel_stainless", sh=0.5, s=0.48)
	castors(0.5, 0.5, 0.04)
	with kit.hollow(0.1):
		kit.cyl(0.15, 0.15, (0, 0, 0.38), "plastic_grey", "pan", segs=16)


def hoist():
	for s in (-1, 1):
		kit.box((0.06, 1.1, 0.06), (s * 0.3, 0.1, 0.1), "steel_painted", "leg")
	castors(0.66, 1.1, 0.05)
	kit.box((0.66, 0.1, 0.1), (0, -0.4, 0.12), "steel_painted", "base")
	kit.rod((0, -0.4, 0.15), (0, -0.4, 1.4), 0.035, "steel_painted", "mast")
	kit.rod((0, -0.4, 1.4), (0, 0.5, 1.8), 0.03, "steel_painted", "boom")
	kit.rod((-0.25, 0.5, 1.6), (0.25, 0.5, 1.6), 0.012, "steel_stainless", "spreader")
	kit.rod((0, 0.5, 1.8), (0, 0.5, 1.6), 0.006, "steel_stainless", "link", segs=6)


def xray_machine():
	kit.box((0.4, 2.4, 0.06), (0, 0, 2.95), "paint_white", "ceiling_rail")
	kit.box((0.3, 0.3, 1.0), (0, 0.3, 2.4), "paint_white", "column")
	kit.rounded_box((0.35, 0.4, 0.35), (0, 0.3, 1.75), "plastic_white", "tube_head", radius=0.04)
	kit.box((0.2, 0.2, 0.1), (0, 0.3, 1.52), "plastic_grey", "collimator")
	kit.box((0.75, 2.1, 0.08), (0, 0.3, 0.8), "laminate_white", "table_top")
	kit.box((0.5, 1.2, 0.76), (0, 0.3, 0.38), "paint_white", "table_base")
	kit.box((0.6, 0.1, 1.9), (0, -1.6, 0.95), "paint_white", "wall_stand")
	kit.box((0.5, 0.06, 0.5), (0, -1.52, 1.4), "plastic_grey", "detector")


def scanner(mri=False):
	r, bore, d = (1.1, 0.35, 1.7) if mri else (1.0, 0.4, 0.9)
	prof = [(bore, -d / 2), (r * 0.9, -d / 2), (r, -d / 2 + 0.15), (r, d / 2 - 0.15), (r * 0.9, d / 2), (bore, d / 2)]
	with kit.hollow(0.5 if mri else 0.25):
		kit.lathe([(a, b + d / 2) for a, b in prof], (0, -d / 2, r + 0.05), "plastic_white", "gantry", segs=40, rot=(-90, 0, 0))
		kit.box((r * 1.8, d, 0.3), (0, -0.0, 0.15), "plastic_white", "plinth")
	kit.box((0.5, 2.2, 0.55), (0, d / 2 + 1.1, 0.4), "plastic_white", "couch_base")
	kit.rounded_box((0.5, 2.4, 0.08), (0, d / 2 + 0.9, r + 0.05 - bore + 0.12), "plastic_grey", "couch", radius=0.03)


def dental_chair():
	kit.rounded_box((0.5, 0.6, 0.35), (0, 0, 0.175), "plastic_white", "base", radius=0.05)
	kit.rounded_box((0.55, 0.6, 0.1), (0, 0.05, 0.5), "plastic_green", "seat", radius=0.04)
	kit.rounded_box((0.5, 0.85, 0.09), (0, -0.6, 0.65), "plastic_green", "back", radius=0.04, rot=(-25, 0, 0))
	kit.rounded_box((0.45, 0.6, 0.08), (0, 0.6, 0.42), "plastic_green", "leg_rest", radius=0.03, rot=(-15, 0, 0))
	kit.rod((0.45, -0.2, 0), (0.45, -0.2, 1.9), 0.03, "plastic_white", "post")
	kit.rod((0.45, -0.2, 1.9), (0.0, -0.3, 1.7), 0.02, "plastic_white", "lamp_arm")
	kit.rounded_box((0.25, 0.12, 0.1), (0, -0.3, 1.66), "light_emitter", "lamp", radius=0.03)
	kit.box((0.35, 0.25, 0.04), (0.35, 0.3, 0.9), "plastic_white", "instrument_tray")
	kit.rod((0.45, -0.2, 0.88), (0.35, 0.3, 0.88), 0.015, "plastic_white", "tray_arm")


def incubator():
	carcass(0.6, 0.5, 0.85, "plastic_white", doors=1, plinth=0.15)
	castors(0.6, 0.5, 0.05)
	kit.rounded_box((0.9, 0.5, 0.42), (0, 0, 1.1), "glass", "hood", radius=0.06)
	kit.rounded_box((0.8, 0.42, 0.05), (0, 0, 0.93), "fabric_white", "mattress", radius=0.02)
	for x in (-0.2, 0.2):
		kit.cyl(0.07, 0.01, (x, 0.251, 1.08), "plastic_blue", "port", axis="y", segs=16)


def scrub_sink(w=1.6):
	with kit.hollow(0.15):
		kit.prism([(0, 0), (0.5, 0.15), (0.5, 0.45), (0, 0.45)], w, (0, 0, 0.6), "steel_stainless", "trough", axis="x")
	kit.box((w, 0.02, 0.5), (0, 0.01, 1.3), "steel_stainless", "splashback")
	for i in range(int(w / 0.8)):
		x = -w / 2 + 0.4 + i * 0.8
		kit.sweep([(x, 0.02, 1.25), (x, 0.2, 1.3), (x, 0.26, 1.22)], kit.circle(0.012, 8), "steel_stainless", "tap")


def bin_pedal(slot="plastic_yellow", h=0.7):
	with kit.hollow(0.08):
		kit.rounded_box((0.4, 0.38, h), (0, 0, h / 2), "paint_white", "body", radius=0.02)
	kit.rounded_box((0.42, 0.4, 0.05), (0, 0, h + 0.025), slot, "lid", radius=0.02)
	kit.box((0.12, 0.08, 0.02), (0, 0.22, 0.03), "plastic_black", "pedal")


def sharps_bin():
	kit.rounded_box((0.2, 0.15, 0.3), (0, 0.09, 1.25), "plastic_yellow", "bin", radius=0.02)
	kit.box((0.18, 0.13, 0.04), (0, 0.09, 1.42), "plastic_red", "lid")


def linen_trolley():
	kit.frame(0.6, 0.95, 0.025, 0.5, at=(0, 0, 0.1), slot="steel_stainless", name="frame")
	with kit.hollow(0.05):
		kit.box((0.55, 0.45, 0.75), (0, 0, 0.55), "fabric_white", "bag")
	castors(0.6, 0.5, 0.05)


def medicine_trolley():
	carcass(0.75, 0.5, 1.0, "plastic_blue", drawers=6, plinth=0.12)
	castors(0.75, 0.5, 0.05)
	laptop_z = 1.0
	kit.box((0.32, 0.22, 0.015), (0, 0, laptop_z + 0.008), "aluminium", "laptop")
	kit.box((0.32, 0.012, 0.2), (0, -0.12, laptop_z + 0.1), "aluminium", "laptop_lid", rot=(-15, 0, 0))


def defib_cabinet():
	kit.rounded_box((0.4, 0.2, 0.45), (0, 0.1, 1.4), "plastic_green", "cabinet", radius=0.02)
	kit.box((0.3, 0.005, 0.3), (0, 0.202, 1.4), "glass", "window")


def gel_dispenser():
	kit.rounded_box((0.11, 0.1, 0.25), (0, 0.05, 1.2), "plastic_white", "dispenser", radius=0.02)
	kit.box((0.09, 0.03, 0.02), (0, 0.1, 1.07), "plastic_grey", "lever")


def ward_screen(panels=3):
	for i in range(panels):
		x = (i - (panels - 1) / 2) * 0.9
		rot = 15 * (1 if i % 2 else -1)
		kit.box((0.86, 0.01, 1.4), (x, 0, 1.05), "fabric_blue", "panel", rot=(0, 0, rot))
		kit.rod((x - 0.44, 0, 0), (x - 0.44, 0, 1.8), 0.012, "steel_stainless", "post")
	kit.rod(((panels / 2) * 0.9 - 0.01, 0, 0), ((panels / 2) * 0.9 - 0.01, 0, 1.8), 0.012, "steel_stainless", "post")


def autoclave():
	kit.rounded_box((0.6, 0.65, 0.5), (0, 0, 0.25), "steel_stainless", "body", radius=0.03)
	kit.cyl(0.2, 0.04, (0, 0.33, 0.25), "steel_stainless", "door", axis="y", segs=24)
	kit.box((0.12, 0.004, 0.05), (0.2, 0.327, 0.44), "screen", "display")


def microscope():
	kit.box((0.16, 0.2, 0.025), (0, 0, 0.0125), "plastic_white", "base")
	kit.sweep([(0, -0.08, 0.02), (0, -0.09, 0.2), (0, -0.02, 0.3)], kit.rect(0.04, 0.04), "plastic_white", "arm", up=(1, 0, 0))
	kit.box((0.12, 0.12, 0.01), (0, 0.01, 0.12), "plastic_black", "stage")
	kit.cyl(0.015, 0.08, (0, 0.01, 0.2), "steel_stainless", "objective", segs=10)
	kit.cyl(0.014, 0.1, (0, 0.03, 0.34), "plastic_black", "eyepiece", segs=10, rot=(-35, 0, 0))


def centrifuge():
	kit.rounded_box((0.4, 0.45, 0.3), (0, 0, 0.15), "plastic_white", "body", radius=0.04)
	kit.cyl(0.16, 0.03, (0, -0.02, 0.31), "plastic_blue", "lid", segs=24)


def lab_fridge(h=1.9, slot="paint_white", glass=True):
	with kit.hollow(0.15):
		kit.box((0.7, 0.7, h), (0, 0, h / 2), slot, "body")
	kit.box((0.62, 0.02, h - 0.4), (0, 0.36, h / 2 - 0.05), "glass" if glass else slot, "door")
	kit.box((0.2, 0.004, 0.06), (0, 0.352, h - 0.12), "screen", "display")
	kit.rod((0.25, 0.39, h / 2 - 0.2), (0.25, 0.39, h / 2 + 0.2), 0.01, "steel_stainless", "handle")


def mortuary_fridge(bays=2):
	w = bays * 0.9
	with kit.hollow(0.1):
		kit.box((w, 2.4, 2.0), (0, 0, 1.0), "steel_stainless", "body")
	for i in range(bays):
		for j in range(3):
			x, z = -w / 2 + 0.45 + i * 0.9, 0.38 + j * 0.62
			kit.box((0.8, 0.03, 0.55), (x, 1.215, z), "steel_stainless", "door")
			kit.rod((x + 0.3, 1.25, z - 0.1), (x + 0.3, 1.25, z + 0.1), 0.01, "plastic_black", "handle")


def visitor_chair():
	kit.rounded_box((0.55, 0.5, 0.1), (0, 0.02, 0.43), "plastic_green", "seat", radius=0.04)
	kit.rounded_box((0.55, 0.08, 0.6), (0, -0.25, 0.75), "plastic_green", "back", radius=0.035, rot=(-8, 0, 0))
	for s in (-1, 1):
		kit.sweep([(s * 0.3, 0.25, 0), (s * 0.3, 0.25, 0.62), (s * 0.3, -0.28, 0.62), (s * 0.3, -0.28, 0)], kit.rect(0.03, 0.05), "hardwood", "arm_frame", up=(1, 0, 0))


def bed_locker():
	carcass(0.45, 0.45, 0.85, "laminate_white", doors=1, drawers=1, plinth=0.08)
	castors(0.45, 0.45, 0.03)


def baby_change():
	kit.box((0.9, 0.1, 0.55), (0, 0.05, 1.05), "plastic_grey", "wall_unit")
	kit.rounded_box((0.86, 0.55, 0.06), (0, 0.33, 0.85), "plastic_grey", "table", radius=0.02)


def grab_rail(l=0.6, drop=False):
	if drop:
		kit.sweep([(0, 0.02, 0.8), (0, 0.75, 0.8), (0, 0.75, 0.6), (0, 0.02, 0.6)], kit.circle(0.017, 10), "plastic_white", "rail", up=(1, 0, 0))
		kit.box((0.1, 0.02, 0.3), (0, 0.01, 0.7), "plastic_white", "plate")
	else:
		kit.sweep([(-l / 2, 0, 0.9), (-l / 2, 0.07, 0.9), (l / 2, 0.07, 0.9), (l / 2, 0, 0.9)], kit.circle(0.017, 10), "plastic_white", "rail")


def reg_h(id, fn, label, *tags, **params):
	reg("hospital." + id, fn, label, *tags, **params)


reg_h("bed.trolley", trolley_bed, "Patient trolley")
reg_h("bed.stretcher", trolley_bed, "Ambulance stretcher", w=0.58, l=1.95, h=0.6, rails=False)
reg_h("bed.exam_couch", exam_couch, "Examination couch")
reg_h("bed.locker", bed_locker, "Bedside locker")
reg_h("bed.trunking", bedhead_trunking, "Bedhead services trunking", "wall")
reg_h("bed.curtain", bed_curtain, "Bed bay curtain and track")
reg_h("bed.screen", ward_screen, "Folding ward screen")
reg_h("bed.visitor_chair", visitor_chair, "Patient armchair")
reg_h("bed.commode", commode, "Commode chair")
reg_h("bed.hoist", hoist, "Patient hoist")
reg_h("bed.incubator", incubator, "Neonatal incubator")
reg_h("theatre.table", operating_table, "Operating table")
reg_h("theatre.light_twin", theatre_light, "Theatre light, twin head", "ceiling")
reg_h("theatre.light_single", theatre_light, "Examination light, ceiling", "ceiling", heads=1)
reg_h("theatre.anaesthetic", anaesthetic_machine, "Anaesthetic machine")
reg_h("theatre.scrub_sink", scrub_sink, "Scrub sink, two position", "wall")
reg_h("theatre.scrub_sink_3", scrub_sink, "Scrub sink, three position", "wall", w=2.4)
reg_h("theatre.autoclave", autoclave, "Benchtop autoclave")
reg_h("ward.drip_stand", drip_stand, "Drip stand with pump")
reg_h("ward.monitor", patient_monitor, "Patient monitor on stand")
reg_h("ward.crash_cart", crash_cart, "Resuscitation trolley")
reg_h("ward.dressing_trolley", crash_cart, "Procedure trolley", slot="plastic_blue")
reg_h("ward.medicine_trolley", medicine_trolley, "Medicine trolley")
reg_h("ward.linen_trolley", linen_trolley, "Linen trolley")
reg_h("ward.nurse_station", nurse_station, "Nurse station, 3 m")
reg_h("ward.nurse_station_long", nurse_station, "Nurse station, 4.8 m", w=4.8)
reg_h("ward.clinical_bin", bin_pedal, "Clinical waste bin")
reg_h("ward.general_bin", bin_pedal, "Pedal bin", "office", "home", slot="plastic_black")
reg_h("ward.sharps_bin", sharps_bin, "Sharps bin", "wall")
reg_h("ward.defib_cabinet", defib_cabinet, "Defibrillator cabinet", "wall", "airport", "school", "office")
reg_h("ward.gel_dispenser", gel_dispenser, "Hand gel dispenser", "wall", "airport")
reg_h("ward.baby_change", baby_change, "Baby changing table", "wall", "airport")
reg_h("ward.grab_rail", grab_rail, "Grab rail, 600", "wall", "home")
reg_h("ward.drop_rail", grab_rail, "Drop-down support rail", "wall", "home", drop=True)
reg_h("imaging.xray", xray_machine, "X-ray room set")
reg_h("imaging.ct", scanner, "CT scanner")
reg_h("imaging.mri", scanner, "MRI scanner", mri=True)
reg_h("dental.chair", dental_chair, "Dental chair and light")
reg_h("lab.microscope", microscope, "Microscope", "school")
reg_h("lab.centrifuge", centrifuge, "Centrifuge", "school")
reg_h("lab.fridge", lab_fridge, "Pharmacy fridge")
reg_h("lab.blood_fridge", lab_fridge, "Blood bank fridge", slot="steel_stainless")
reg_h("lab.freezer", lab_fridge, "Laboratory freezer", glass=False)
reg_h("mortuary.fridge_6", mortuary_fridge, "Mortuary fridge, six body")
reg_h("mortuary.fridge_9", mortuary_fridge, "Mortuary fridge, nine body", bays=3)
