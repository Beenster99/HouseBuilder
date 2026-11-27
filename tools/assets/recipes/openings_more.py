"""More doors, windows, stairs, ramps and lifts beyond the catalog kinds, in the sizes
buildings actually use. Openings: origin bottom centre of the opening, in the wall's plane,
X along the wall, Y through it (outside is +Y). Stairs climb along +Y from the origin."""
import math

import kit
from recipes.circulation import GOING, RISE, lift, stair
from recipes.openings import door, shutter, window
from registry import register


def reg(id, fn, label, *tags, **params):
	register(id, fn, label, family=id.split(".")[0], tags=(id.split(".")[0],) + tags, **params)


def sash_window(w, h):
	with kit.stage("frame"):
		kit.frame(w, h, 0.1, 0.14, slot="paint_white", name="box_frame")
		kit.box((w + 0.12, 0.22, 0.04), (0, 0.05, -0.02), "paint_white", "sill")
		for i, y in enumerate((0.025, -0.025)):
			z0 = 0.1 + i * (h - 0.2) / 2
			kit.frame(w - 0.2, (h - 0.2) / 2 + 0.03, 0.045, 0.04, at=(0, y, z0 - 0.015 * i), slot="paint_white", name="sash")
			kit.box((0.02, 0.04, (h - 0.2) / 2 - 0.06), (0, y, z0 + (h - 0.2) / 4), "paint_white", "glazing_bar")
	with kit.stage("glazing"):
		for i, y in enumerate((0.025, -0.025)):
			kit.box((w - 0.29, 0.006, (h - 0.2) / 2 - 0.06), (0, y, 0.1 + i * (h - 0.2) / 2 + (h - 0.2) / 4), "glass", "pane")
	kit.socket("wall", (0, 0, 0))


def fixed_window(w, h, slot="aluminium", round_=False, louvre=False):
	if round_:
		with kit.stage("frame"):
			kit.tube(w / 2, 0.1, (0, 0, w / 2), slot, "frame", axis="y", wall=0.05, segs=28)
		with kit.stage("glazing"):
			kit.cyl(w / 2 - 0.05, 0.02, (0, 0, w / 2), "glass", "pane", axis="y", segs=28)
	else:
		with kit.stage("frame"):
			kit.frame(w, h, 0.05, 0.1, slot=slot, name="frame")
			n = max(1, round(w / 1.5))
			for i in range(1, n):
				kit.box((0.05, 0.1, h - 0.1), (-w / 2 + w * i / n, 0, h / 2), slot, "mullion")
		with kit.stage("glazing"):
			if louvre:
				for i in range(int((h - 0.1) / 0.1)):
					kit.box((w - 0.1, 0.11, 0.006), (0, 0, 0.1 + i * 0.1), slot, "blade", rot=(35, 0, 0))
			else:
				kit.box((w - 0.1, 0.028, h - 0.1), (0, 0, h / 2), "glass", "pane")
	kit.socket("wall", (0, 0, 0))


def bay_window(w=2.4, h=1.5, d=0.6):
	pts = [(-w / 2, 0), (-w / 2 + d, d), (w / 2 - d, d), (w / 2, 0)]
	with kit.stage("frame"):
		for z in (0.035, h - 0.035):
			kit.sweep([(x, y, z) for x, y in pts], kit.rect(0.1, 0.07), "paint_white", "rail")
		for x, y in pts:
			kit.box((0.08, 0.08, h), (x, y, h / 2), "paint_white", "post")
		kit.sweep([(x, y * 1.15, -0.02) for x, y in pts], kit.rect(0.25, 0.04), "paint_white", "sill")
	with kit.stage("glazing"):
		kit.sweep([(x, y, h / 2) for x, y in pts], kit.rect(0.024, h - 0.14), "glass", "panes")
	with kit.stage("roof"):
		kit.prism([(-w / 2 - 0.05, 0), (-w / 2 + d, d + 0.08), (w / 2 - d, d + 0.08), (w / 2 + 0.05, 0)], 0.12, (0, 0, h + 0.06), "lead", "roof", axis="z")
	kit.socket("wall", (0, 0, 0))


def sliding_door(w, h, panels=2, bifold=False, slot="aluminium"):
	with kit.stage("frame"):
		kit.frame(w, h, 0.06, 0.16, slot=slot, name="frame", bottom=False)
		kit.box((w, 0.16, 0.02), (0, 0, 0.01), slot, "track")
	pw = (w - 0.12) / panels
	for i in range(panels):
		x = -w / 2 + 0.06 + pw * (i + 0.5)
		y = (0.03 if i % 2 else -0.03) if not bifold else 0.0
		with kit.stage("leaf"):
			kit.frame(pw, h - 0.09, 0.05 if not bifold else 0.07, 0.045, at=(x, y, 0.02), slot=slot, name="panel_frame")
		with kit.stage("glazing"):
			kit.box((pw - 0.1, 0.028, h - 0.2), (x, y, h / 2), "glass", "pane")
		with kit.stage("ironmongery"):
			kit.box((0.025, 0.03, 0.25), (x + (pw / 2 - 0.03) * (1 if i % 2 == 0 else -1), y + 0.035, 1.05), "steel_stainless", "handle")
	kit.socket("wall", (0, 0, 0))


def auto_entrance(w=2.0, h=2.3, revolving=False):
	if revolving:
		r = w / 2
		with kit.stage("frame"):
			kit.cyl(r + 0.05, 0.25, (0, 0, h + 0.125), "aluminium", "canopy", segs=28)
			kit.cyl(r + 0.05, 0.02, (0, 0, 0.01), "rubber", "mat", segs=28)
			for s in (-1, 1):
				kit.sweep([((r) * math.cos(math.radians(a)) , (r * math.sin(math.radians(a))) * 1, h / 2) for a in range(-50 if s > 0 else 130, 51 if s > 0 else 231, 10)], kit.rect(0.02, h), "glass", "drum_wall")
		with kit.stage("leaf"):
			kit.cyl(0.05, h, (0, 0, h / 2), "aluminium", "shaft", segs=12)
			for i in range(4):
				a = math.radians(45 + 90 * i)
				kit.box((r - 0.08, 0.012, h - 0.1), ((r / 2) * math.cos(a), (r / 2) * math.sin(a), h / 2), "glass", "wing", rot=(0, 0, 45 + 90 * i))
	else:
		with kit.stage("frame"):
			kit.frame(w * 2, h + 0.2, 0.06, 0.18, slot="aluminium", name="frame", bottom=False)
			kit.box((w * 2, 0.2, 0.2), (0, 0, h + 0.1), "aluminium", "operator")
			kit.box((0.2, 0.06, 0.06), (0, 0.13, h + 0.1), "plastic_black", "sensor")
		with kit.stage("leaf"):
			for s in (-1, 1):
				kit.box((w / 2 - 0.01, 0.012, h - 0.02), (s * w / 4, 0, h / 2), "glass", "leaf")
				kit.box((w / 2 - 0.02, 0.012, h - 0.02), (s * w * 0.75, 0.04, h / 2), "glass", "side_screen")
	kit.socket("wall", (0, 0, 0))


def garage_door(w=2.4, h=2.1, sectional=False):
	with kit.stage("frame"):
		kit.frame(w, h, 0.07, 0.07, slot="paint_white", name="frame", bottom=False)
	with kit.stage("leaf"):
		if sectional:
			for i in range(4):
				kit.box((w - 0.14, 0.04, h / 4 - 0.01), (0, 0, h / 8 + i * h / 4), "paint_white", "section")
		else:
			kit.box((w - 0.14, 0.03, h - 0.07), (0, 0, h / 2 - 0.035), "paint_white", "leaf")
			for i in range(1, 6):
				kit.box((0.02, 0.036, h - 0.2), (-w / 2 + w * i / 6, 0, h / 2), "paint_white", "rib")
	with kit.stage("ironmongery"):
		kit.box((0.12, 0.05, 0.04), (0, 0.02, 0.9), "steel_stainless", "handle")
	kit.socket("wall", (0, 0, 0))


def vehicle_roller(w=3.0, h=3.0, slot="steel_galvanised", powered=True):
	"""A roller shutter vehicle door: a curtain of curved laths in side guides, rolling up into
	a hood over the head inside. Fills the opening w by h; the inside is -y."""
	with kit.hollow(0.08):
		with kit.stage("frame"):
			for s in (-1, 1):
				kit.box((0.09, 0.08, h), (s * (w / 2 - 0.045), 0, h / 2), "steel_galvanised", "guide")
				kit.box((0.012, 0.32, 0.36), (s * (w / 2 - 0.006), -0.2, h - 0.18), "steel_galvanised", "end_plate")
			kit.cyl(0.15, w - 0.03, (0, -0.2, h - 0.18), "steel_galvanised", "barrel_hood", axis="x", segs=20)
			kit.box((w - 0.03, 0.03, 0.36), (0, -0.045, h - 0.18), "steel_galvanised", "fascia")
		with kit.stage("leaf"):
			lath = 0.075
			n = int((h - 0.36 - 0.1) / lath)
			for i in range(n):
				z = 0.1 + lath / 2 + i * lath
				kit.cyl(0.03, w - 0.2, (0, 0.012, z), slot, "lath", axis="x", segs=8, rot=(0, 0, 0))
				kit.box((w - 0.2, 0.012, lath), (0, 0, z), slot, "lath_web")
			kit.box((w - 0.2, 0.06, 0.1), (0, 0, 0.05), "plant_yellow", "bottom_rail")
			kit.box((w - 0.24, 0.07, 0.02), (0, 0, 0.005), "rubber", "seal")
		with kit.stage("ironmongery"):
			if powered:
				kit.cyl(0.09, 0.3, (w / 2 - 0.2, -0.2, h - 0.5), "plastic_grey", "motor", axis="x", segs=14)
				kit.box((0.12, 0.08, 0.2), (w / 2 - 0.12, -0.08, 1.3), "plastic_yellow", "control")
			else:
				kit.cyl(0.11, 0.03, (w / 2 - 0.03, -0.3, h - 0.18), "steel_galvanised", "chain_wheel", axis="x", segs=16)
				for dy in (-0.4, -0.2):
					kit.rod((w / 2 - 0.03, dy, h - 0.2), (w / 2 - 0.03, dy, 1.0), 0.005, "steel_galvanised", "hand_chain", segs=5)
			kit.box((0.2, 0.03, 0.05), (0, 0.035, 0.12), "steel_stainless", "lift_handle")
	kit.socket("wall", (0, 0, 0))


def vehicle_up_and_over(w=3.0, h=3.0, slot="paint_white", ribs="vertical"):
	"""A one-piece up-and-over vehicle door: a pressed steel panel in a frame, on pivot arms
	and springs, with tracks running back under the ceiling inside (-y)."""
	fr = 0.07
	with kit.stage("frame"):
		kit.frame(w, h, fr, 0.08, slot="steel_galvanised", name="frame", bottom=False)
		for s in (-1, 1):
			kit.box((0.05, 0.9 * h, 0.04), (s * (w / 2 - fr - 0.03), -0.45 * h - 0.04, h - 0.12), "steel_galvanised", "track")
			kit.strut((s * (w / 2 - fr - 0.03), -0.9 * h - 0.04, h - 0.12), (s * (w / 2 - fr - 0.03), -0.9 * h - 0.04, h + 0.05), 0.04, 0.04, "steel_galvanised", "track_hanger")
		kit.box((w - 2 * fr, 0.04, 0.04), (0, -0.9 * h - 0.04, h - 0.12), "steel_galvanised", "track_tie")
	with kit.stage("leaf"), kit.hollow(0.1):
		pw, ph = w - 2 * fr - 0.02, h - fr - 0.02
		kit.box((pw, 0.02, ph), (0, 0, ph / 2 + 0.005), slot, "panel")
		for s in (-1, 1):
			kit.box((0.04, 0.045, ph), (s * (pw / 2 - 0.02), -0.005, ph / 2 + 0.005), slot, "stile")
			kit.box((pw, 0.045, 0.04), (0, -0.005, ph / 2 + 0.005 + s * (ph / 2 - 0.02)), slot, "rail")
		if ribs == "vertical":
			n = max(4, int(pw / 0.2))
			for i in range(1, n):
				kit.box((0.035, 0.034, ph - 0.12), (-pw / 2 + pw * i / n, 0.004, ph / 2 + 0.005), slot, "rib")
		else:
			n = max(4, int(ph / 0.22))
			for i in range(1, n):
				kit.box((pw - 0.12, 0.034, 0.035), (0, 0.004, 0.005 + ph * i / n), slot, "rib")
		kit.box((pw, 0.03, 0.03), (0, -0.03, ph * 0.45), "steel_galvanised", "brace")
	with kit.stage("ironmongery"):
		kit.cyl(0.035, 0.03, (0, 0.03, min(1.0, h * 0.4)), "steel_stainless", "lock_handle", axis="y", segs=12)
		kit.box((0.1, 0.012, 0.03), (0, 0.045, min(1.0, h * 0.4)), "steel_stainless", "handle_bar")
		for s in (-1, 1):
			x = s * (w / 2 - fr - 0.03)
			kit.strut((x, -0.03, h * 0.5), (x, -0.5, h - 0.14), 0.03, 0.008, "steel_galvanised", "pivot_arm")
			kit.cyl(0.02, 0.55, (x, -0.06, h * 0.5 + 0.35), "steel_galvanised", "spring", segs=8)
			kit.cyl(0.025, 0.03, (x, -0.02, h - 0.1), "plastic_black", "roller", axis="x", segs=10)
	kit.socket("wall", (0, 0, 0))


def fire_exit(w=1.0, h=2.1, double=False):
	door(w * (2 if double else 1), h, "steel", "flush")
	with kit.stage("ironmongery"):
		kit.rod((-w * (1 if double else 0.5) + 0.1, -0.07, 1.0), (w * (1 if double else 0.5) - 0.1, -0.07, 1.0), 0.015, "plastic_green", "panic_bar")
		kit.box((0.4, 0.03, 0.15), (0, -0.02, h + 0.15), "plastic_green", "exit_sign")


def dock_door(w=3.0, h=3.0):
	shutter(w, h)
	with kit.stage("dock"):
		for s in (-1, 1):
			kit.box((0.5, 0.6, h), (s * (w / 2 + 0.25), 0.36, h / 2), "rubber", "dock_seal")
			kit.box((0.25, 0.12, 0.5), (s * (w / 2 - 0.3), 0.12, -0.3), "rubber", "bumper")
		kit.box((w + 1.0, 0.6, 0.5), (0, 0.36, h + 0.25), "rubber", "head_seal")
		kit.box((2.0, 2.4, 0.06), (0, -1.2, -0.03), "steel_galvanised", "leveller")


def curtain_wall(h=3.6):
	"""A 1.5 m module, scaled along X in whole modules."""
	with kit.stage("frame"):
		for s in (-1, 1):
			kit.box((0.03, 0.15, h), (s * 0.735, -0.05, h / 2), "aluminium", "mullion")
		for z in (0.03, 1.0, h - 0.03):
			kit.box((1.5, 0.15, 0.06), (0, -0.05, z), "aluminium", "transom")
	with kit.stage("glazing"):
		kit.box((1.44, 0.03, h - 1.06), (0, 0.01, 1.03 + (h - 1.06) / 2), "glass", "vision")
		kit.box((1.44, 0.03, 0.94), (0, 0.01, 0.53), "aluminium", "spandrel")


def shopfront(w=4.0, h=3.0):
	with kit.stage("frame"):
		kit.frame(w, h, 0.06, 0.1, slot="aluminium", name="frame")
		kit.box((w, 0.3, 0.4), (0, 0.1, h + 0.2), "plastic_black", "fascia")
		for x in (-0.5, 0.5):
			kit.box((0.06, 0.1, h - 0.1), (x, 0, h / 2), "aluminium", "door_post")
		kit.box((1.0, 0.1, 0.06), (0, 0, 2.15), "aluminium", "door_head")
	with kit.stage("glazing"):
		for s in (-1, 1):
			kit.box((w / 2 - 0.6, 0.024, h - 0.1), (s * (w / 4 + 0.25), 0, h / 2), "glass", "window")
		kit.box((0.9, 0.012, 2.1), (0, 0, 1.06), "glass", "door")
		kit.box((0.9, 0.024, h - 2.25), (0, 0, 2.18 + (h - 2.25) / 2), "glass", "fanlight")
	kit.socket("wall", (0, 0, 0))


def extras(what="sill", w=1.2):
	if what == "sill":
		kit.prism([(-0.02, 0), (0.18, 0), (0.18, 0.04), (-0.02, 0.07)], 1.0, (0, 0, -0.07), "concrete", "sill", axis="x")
	elif what == "shutters":
		for s in (-1, 1):
			kit.frame(0.45, 1.2, 0.05, 0.03, at=(s * (w / 2 + 0.25), 0.03, 0), slot="plastic_green", name="shutter")
			for i in range(14):
				kit.box((0.36, 0.035, 0.012), (s * (w / 2 + 0.25), 0.03, 0.09 + i * 0.078), "plastic_green", "louvre", rot=(30, 0, 0))
	elif what == "awning":
		kit.box((w, 0.15, 0.15), (0, 0.08, 2.5), "aluminium", "cassette")
		kit.box((w - 0.05, 1.8, 0.01), (0, 0.98, 2.25), "fabric_red", "fabric", rot=(-14, 0, 0))
		for s in (-1, 1):
			kit.rod((s * (w / 2 - 0.1), 0.1, 2.45), (s * (w / 2 - 0.1), 1.85, 2.02), 0.015, "aluminium", "arm")
	elif what == "canopy":
		kit.box((w, 1.2, 0.012), (0, 0.6, 2.4), "glass", "glass", rot=(-4, 0, 0))
		for s in (-1, 1):
			kit.rod((s * (w / 2 - 0.15), 0, 2.9), (s * (w / 2 - 0.15), 1.0, 2.38), 0.012, "steel_stainless", "tie")
			kit.box((0.08, 0.02, 0.2), (s * (w / 2 - 0.15), 0.01, 2.9), "steel_stainless", "bracket")
	elif what == "porch":
		for s in (-1, 1):
			kit.box((0.1, 0.1, 2.3), (s * (w / 2 - 0.05), 1.0, 1.15), "softwood", "post")
		kit.prism([(-w / 2 - 0.15, 0), (w / 2 + 0.15, 0), (0, 0.6)], 1.25, (0, 0.6, 2.3), "clay_tile", "roof", axis="y")
	elif what == "letterbox":
		kit.box((0.26, 0.02, 0.07), (0, 0.03, 1.0), "brass", "letter_plate")
	elif what == "security_grille":
		kit.grid_bars(w, 1.2, (0, 0.05, 0.6), int(w / 0.12), 3, 0.008, "steel_painted", "grille")
	elif what == "roller_blind_box":
		kit.box((w, 0.2, 0.2), (0, 0.1, 2.2), "aluminium", "box")


def spiral(rise=3.0, r=0.9):
	n = round(rise / 0.2)
	with kit.stage("flight"):
		kit.cyl(0.06, rise + 1.0, (0, 0, (rise + 1.0) / 2), "steel_painted", "column", segs=14)
		for i in range(n):
			a = math.radians(i * 28)
			kit.prism([(0.05, -0.03), (r, -0.18), (r, 0.18), (0.05, 0.03)], 0.03, (0, 0, (i + 1) * rise / n - 0.015), "steel_galvanised", "tread", axis="z", rot=(0, 0, i * 28))
	with kit.stage("balustrade"):
		pts = [(r * math.cos(math.radians(i * 28)), r * math.sin(math.radians(i * 28)), (i + 1) * rise / n + 0.9) for i in range(n)]
		kit.sweep(pts, kit.circle(0.02, 8), "steel_painted", "handrail")
		for i in range(n):
			kit.rod((pts[i][0], pts[i][1], pts[i][2] - 0.9), pts[i], 0.008, "steel_painted", "baluster", segs=6)
	kit.socket("head", (pts[-1][0], pts[-1][1], rise))


def dogleg(rise=3.0, w=1.0, material="concrete"):
	n = round(rise / RISE) // 2
	run = (n - 1) * GOING
	slot = "concrete" if material == "concrete" else "steel_painted"
	with kit.stage("flight"):
		for f in range(2):
			z0 = f * rise / 2
			x = (-1 if f == 0 else 1) * (w / 2 + 0.05)
			for i in range(n):
				y = i * GOING if f == 0 else run - i * GOING
				kit.box((w, GOING, RISE if material == "concrete" else 0.04), (x, y, z0 + (i + 1) * RISE - (RISE / 2 if material == "concrete" else 0.02)), slot if material == "concrete" else "steel_galvanised", "step")
			if material == "concrete":
				kit.strut((x, 0 if f == 0 else run, z0 + (0 if f == 0 else 0)), (x, run if f == 0 else 0, z0 + rise / 2 - RISE), w, 0.15, "concrete", "waist")
			else:
				for s in (-1, 1):
					kit.strut((x + s * w / 2, 0 if f == 0 else run, z0), (x + s * w / 2, run if f == 0 else 0, z0 + rise / 2), 0.012, 0.25, slot, "stringer")
		kit.box((2 * w + 0.1, w, 0.18 if material == "concrete" else 0.04), (0, run + w / 2 + GOING / 2, rise / 2 - 0.09), slot, "landing")
	with kit.stage("balustrade"):
		for f in range(2):
			x = (-1 if f == 0 else 1) * 0.05
			z0 = f * rise / 2
			a, b = (x, 0 if f == 0 else run, z0 + 1.0 + (0 if f == 0 else 0)), (x, run if f == 0 else 0, z0 + rise / 2 + 0.9)
			kit.rod(a, b, 0.021, "steel_painted", "handrail")
			for t in (0, 0.33, 0.66, 1):
				p = tuple(a[k] + (b[k] - a[k]) * t for k in range(3))
				kit.rod((p[0], p[1], p[2] - 0.95), p, 0.012, "steel_painted", "post")
	kit.socket("foot", (-(w / 2 + 0.05), 0, 0))
	kit.socket("head", (w / 2 + 0.05, 0, rise))


def fire_escape(storeys=3, h=3.0):
	for f in range(storeys):
		z = f * h
		with kit.stage("flight_%d" % (f + 1)):
			n = round(h / 0.2)
			for s in (-1, 1):
				kit.strut((s * 0.45, 0, z), (s * 0.45, 3.2, z + h), 0.01, 0.22, "steel_galvanised", "stringer")
				kit.rod((s * 0.45, 0, z + 1.0), (s * 0.45, 3.2, z + h + 1.0), 0.02, "steel_galvanised", "handrail")
			for i in range(n):
				kit.box((0.9, 0.25, 0.03), (0, 3.2 * (i + 0.5) / n, z + h * (i + 1) / n), "steel_galvanised", "tread")
			kit.box((2.2, 1.1, 0.04), (0.65, 3.75, z + h), "steel_galvanised", "landing")
			kit.grid_bars(2.2, 1.0, (0.65, 4.3, z + h + 0.55), 16, 2, 0.008, "steel_galvanised", "guard")
			for x in (-0.45, 1.75):
				kit.box((0.1, 0.1, h), (x, 4.25, z + h / 2), "steel_galvanised", "column")
	kit.socket("head", (0.65, 3.2, storeys * h))


def ramp(rise=0.6, w=1.5, gradient=12.0, rails=True):
	run = rise * gradient
	with kit.stage("ramp"):
		kit.prism([(0, 0), (run, 0), (run, rise), (0, 0.0)], w, (0, 0, 0), "concrete", "ramp", axis="x")
		kit.box((w, 1.5, rise), (0, run + 0.75, rise / 2), "concrete", "landing")
	if rails:
		with kit.stage("balustrade"):
			for s in (-1, 1):
				for hgt in (0.6, 0.95):
					kit.rod((s * (w / 2 - 0.05), 0, hgt), (s * (w / 2 - 0.05), run, rise + hgt), 0.02, "steel_stainless", "handrail")
				for i in range(int(run / 1.5) + 1):
					y = i * run / max(1, int(run / 1.5))
					kit.rod((s * (w / 2 - 0.05), y, rise * y / run), (s * (w / 2 - 0.05), y, rise * y / run + 0.95), 0.02, "steel_stainless", "post")
	kit.socket("head", (0, run, rise))


def steps(n=3, w=1.2, slot="concrete"):
	for i in range(n):
		kit.box((w, 0.3 * (n - i), 0.17), (0, 0.15 * (n - i) + 0.3 * i, 0.085 + i * 0.17), slot, "step")
	kit.socket("head", (0, 0.3 * n, 0.17 * n))


def cat_ladder(h=6.0, cage=True):
	for s in (-1, 1):
		kit.box((0.06, 0.012, h + 1.1), (s * 0.2, 0.2, (h + 1.1) / 2), "steel_galvanised", "stile")
		for z in (0.5, h * 0.5, h - 0.2):
			kit.rod((s * 0.2, 0, z), (s * 0.2, 0.2, z), 0.012, "steel_galvanised", "stand_off")
	for i in range(int(h / 0.25)):
		kit.rod((-0.2, 0.2, 0.25 + i * 0.25), (0.2, 0.2, 0.25 + i * 0.25), 0.01, "steel_galvanised", "rung", segs=6)
	if cage:
		for i in range(int((h - 2.2) / 0.9) + 1):
			z = 2.5 + i * 0.9
			kit.sweep([(0.35 * math.cos(math.radians(a)), 0.2 + 0.4 + 0.4 * math.sin(math.radians(a)) - 0.4 * 0 , z) for a in range(-90 - 135, -90 + 136, 27)], kit.rect(0.04, 0.006), "steel_galvanised", "hoop")
		for a in (-200, -145, -90, -35, 20):
			x, y = 0.35 * math.cos(math.radians(a)), 0.6 + 0.4 * math.sin(math.radians(a))
			kit.box((0.04, 0.006, h - 1.4), (x, y, 2.5 + (h - 2.5) / 2 + 0.5), "steel_galvanised", "cage_strap")
	kit.socket("head", (0, 0, h))


def balustrade(style="glass", h=1.1):
	"""A 1 m run; scale along X."""
	if style == "glass":
		kit.box((1.0, 0.018, h - 0.05), (0, 0, h / 2), "glass", "pane")
		kit.box((1.0, 0.06, 0.1), (0, 0, 0.05), "aluminium", "shoe")
		kit.rod((-0.5, 0, h), (0.5, 0, h), 0.022, "steel_stainless", "handrail")
	elif style == "steel":
		for z in (0.1, h):
			kit.rod((-0.5, 0, z), (0.5, 0, z), 0.021 if z > 0.5 else 0.012, "steel_painted", "rail")
		for i in range(9):
			kit.rod((-0.444 + i * 0.111, 0, 0.1), (-0.444 + i * 0.111, 0, h), 0.007, "steel_painted", "baluster", segs=6)
	elif style == "timber":
		kit.box((1.0, 0.07, 0.045), (0, 0, h - 0.02), "hardwood", "handrail")
		kit.box((1.0, 0.045, 0.03), (0, 0, 0.1), "softwood", "base_rail")
		for i in range(9):
			kit.box((0.032, 0.032, h - 0.15), (-0.444 + i * 0.111, 0, 0.1 + (h - 0.15) / 2), "paint_white", "spindle")
	elif style == "wire":
		kit.rod((-0.5, 0, h), (0.5, 0, h), 0.021, "steel_stainless", "handrail")
		for i in range(1, 8):
			kit.rod((-0.5, 0, i * h / 8), (0.5, 0, i * h / 8), 0.003, "steel_stainless", "wire", segs=4)
	elif style == "wall_rail":
		kit.rod((-0.5, 0.07, 0.9), (0.5, 0.07, 0.9), 0.021, "hardwood", "handrail")
		kit.rod((0, 0, 0.86), (0, 0.07, 0.88), 0.008, "brass", "bracket", segs=6)
	elif style == "parapet":
		kit.box((1.0, 0.3, h), (0, 0, h / 2), "brick", "parapet")
		kit.box((1.0, 0.36, 0.05), (0, 0, h + 0.025), "aluminium", "coping")


def newel(style="timber", h=1.1):
	if style == "timber":
		kit.box((0.09, 0.09, h + 0.1), (0, 0, (h + 0.1) / 2), "hardwood", "newel")
		kit.sphere(0.055, (0, 0, h + 0.14), "hardwood", "cap", segs=10)
	else:
		kit.cyl(0.024, h, (0, 0, h / 2), "steel_stainless", "post", segs=12)
		kit.cyl(0.05, 0.01, (0, 0, 0.005), "steel_stainless", "base", segs=14)


def lift_variant(what="goods"):
	if what == "goods":
		lift(3.0, 3.5, 2.6)
	elif what == "bed":
		lift(2.4, 3.2, 2.4)
	elif what == "small":
		lift(1.6, 1.8, 2.2)
	elif what == "platform":
		kit.box((1.1, 1.5, 0.06), (0, 0, 0.03), "steel_painted", "platform")
		kit.box((0.25, 1.5, 3.4), (-0.7, 0, 1.7), "aluminium", "mast")
		for s in (-1, 1):
			kit.box((1.1, 0.02, 1.1), (0, s * 0.75, 0.6), "glass", "gate")
		kit.box((0.02, 1.5, 1.1), (0.55, 0, 0.6), "glass", "side")
	elif what == "stairlift":
		kit.strut((0, 0, 0.2), (0, 3.0, 2.6), 0.08, 0.06, "aluminium", "rail")
		kit.rounded_box((0.45, 0.45, 0.08), (0.3, 1.0, 1.55), "fabric_grey", "seat", radius=0.03)
		kit.rounded_box((0.08, 0.45, 0.45), (0.08, 1.0, 1.85), "fabric_grey", "back", radius=0.03)
		kit.box((0.3, 0.3, 0.5), (0.2, 1.0, 1.25), "plastic_white", "carriage")
	elif what == "dumb_waiter":
		with kit.hollow(0.1):
			kit.box((0.8, 0.8, 1.0), (0, -0.4, 1.3), "steel_stainless", "car")
		kit.frame(0.8, 1.0, 0.05, 0.1, at=(0, 0, 0.8), slot="steel_stainless", name="hatch_frame")
	elif what == "shaft":
		with kit.hollow(0.05):
			for s in (-1, 1):
				kit.box((0.2, 2.4, 3.0), (s * 1.1, 0, 1.5), "concrete", "shaft_wall")
			kit.box((2.4, 0.2, 3.0), (0, -1.1, 1.5), "concrete", "shaft_wall")
	elif what == "motor_room":
		kit.box((0.9, 0.7, 0.6), (0, 0, 0.5), "steel_painted", "machine")
		kit.cyl(0.35, 0.15, (0.55, 0, 0.5), "steel_painted", "sheave", axis="x", segs=20)
		kit.box((0.6, 0.3, 1.8), (-1.2, 0, 0.9), "steel_painted", "controller")
		kit.box((1.6, 1.0, 0.2), (0.1, 0, 0.1), "steel_painted", "bed_frame")


for _w, _h in ((0.6, 0.9), (0.6, 1.2), (0.9, 1.2), (1.2, 1.2), (1.2, 1.5), (1.8, 1.2), (1.8, 1.5), (2.4, 1.5), (0.9, 2.1), (1.2, 2.1)):
	reg("opening.window.casement_%dx%d" % (_w * 1000, _h * 1000), window, "Casement window, %d by %d" % (_w * 1000, _h * 1000), "window", w=_w, h=_h)
for _w, _h in ((0.6, 1.2), (0.9, 1.5), (0.9, 1.8), (1.2, 1.8)):
	reg("opening.window.sash_%dx%d" % (_w * 1000, _h * 1000), sash_window, "Sash window, %d by %d" % (_w * 1000, _h * 1000), "window", w=_w, h=_h)
for _w, _h in ((1.5, 1.5), (3.0, 1.5), (3.0, 2.7), (6.0, 2.7), (1.5, 0.6)):
	reg("opening.window.fixed_%dx%d" % (_w * 1000, _h * 1000), fixed_window, "Fixed glazing, %d by %d" % (_w * 1000, _h * 1000), "window", w=_w, h=_h)
reg("opening.window.round_600", fixed_window, "Round window, 600", "window", w=0.6, h=0.6, round_=True)
reg("opening.window.round_1200", fixed_window, "Round window, 1200", "window", w=1.2, h=1.2, round_=True)
reg("opening.window.louvre_600", fixed_window, "Louvre vent, 600 square", "window", "services", w=0.6, h=0.6, louvre=True)
reg("opening.window.louvre_1500", fixed_window, "Plant room louvre, 1500 by 1200", "window", "services", w=1.5, h=1.2, louvre=True)
reg("opening.window.bay", bay_window, "Bay window, 2.4 m", "window")
reg("opening.window.bay_large", bay_window, "Bay window, 3.6 m", "window", w=3.6, h=1.8, d=0.8)
for _w in (0.626, 0.726, 0.826, 0.926):
	reg("opening.door.internal_%d" % round(_w * 1000), door, "Internal door, %d" % round(_w * 1000), "door", w=_w + 0.064, h=2.04, material="timber", style="panel")
	reg("opening.door.flush_%d" % round(_w * 1000), door, "Flush door with vision panel, %d" % round(_w * 1000), "door", w=_w + 0.064, h=2.04, material="timber", style="flush")
reg("opening.door.glazed_single", door, "Glazed door, single", "door", w=0.99, h=2.1, material="glass", style="glazed")
reg("opening.door.glazed_double", door, "Glazed doors, double", "door", w=1.8, h=2.1, material="glass", style="glazed")
reg("opening.door.steel_double", door, "Steel doors, double", "door", w=1.8, h=2.1, material="steel", style="secure")
reg("opening.door.plant_room", door, "Plant room door, steel", "door", "services", w=1.0, h=2.1, material="steel", style="flush")
reg("opening.door.front_wide", door, "Front door, wide", "door", w=1.0, h=2.1, material="timber", style="external")
for _w, _n in ((1.8, 2), (2.4, 2), (3.0, 3), (4.0, 4)):
	reg("opening.door.sliding_%d" % (_w * 1000), sliding_door, "Sliding patio door, %.1f m" % _w, "door", w=_w, h=2.1, panels=_n)
for _w, _n in ((2.4, 3), (3.6, 4), (4.8, 5)):
	reg("opening.door.bifold_%d" % (_w * 1000), sliding_door, "Bifold doors, %.1f m" % _w, "door", w=_w, h=2.1, panels=_n, bifold=True, slot="plastic_grey")
reg("opening.door.auto_sliding", auto_entrance, "Automatic sliding entrance", "door", "office", "hospital", "airport")
reg("opening.door.auto_sliding_wide", auto_entrance, "Automatic sliding entrance, wide", "door", "airport", "hospital", w=3.0)
reg("opening.door.revolving", auto_entrance, "Revolving door", "door", "office", "airport", w=2.4, revolving=True)
reg("opening.door.revolving_large", auto_entrance, "Revolving door, large", "door", "airport", w=3.6, h=2.5, revolving=True)
reg("opening.door.garage_single", garage_door, "Garage door, up and over", "door", "home")
reg("opening.door.garage_double", garage_door, "Garage door, double, sectional", "door", "home", w=4.8, sectional=True)
# (the two types of vehicle door; the 3 m ones are the building catalog's kinds)
register("opening.door.vehicle_roller", vehicle_roller, "Vehicle door, roller shutter", family="opening", kind="door_vehicle_roller", tags=("opening", "door", "vehicle_door"))
register("opening.door.vehicle_up_over", vehicle_up_and_over, "Vehicle door, up and over", family="opening", kind="door_vehicle_up_over", tags=("opening", "door", "vehicle_door"))
for _w, _h, _n in ((2.4, 2.1, "garage"), (4.8, 2.1, "garage_double"), (4.0, 4.5, "industrial"), (5.0, 5.0, "industrial_large")):
	reg("opening.door.vehicle_roller_" + _n, vehicle_roller, "Roller vehicle door, %g by %g m" % (_w, _h), "door", "vehicle_door", w=_w, h=_h,
		slot="paint_white" if _h < 2.5 else "steel_galvanised", powered=_h >= 2.5 or _w > 3)
for _w, _h, _n in ((2.4, 2.1, "garage"), (4.8, 2.1, "garage_double"), (3.0, 2.4, "tall")):
	reg("opening.door.vehicle_up_over_" + _n, vehicle_up_and_over, "Up and over vehicle door, %g by %g m" % (_w, _h), "door", "vehicle_door", w=_w, h=_h,
		ribs="horizontal" if _w > 3 else "vertical")
reg("opening.door.fire_exit", fire_exit, "Fire exit door with panic bar", "door")
reg("opening.door.fire_exit_double", fire_exit, "Fire exit doors, double", "door", double=True)
for _w, _h in ((2.4, 2.4), (3.0, 3.0), (4.0, 4.5), (5.0, 5.0), (8.0, 6.0)):
	reg("opening.door.shutter_%dx%d" % (_w * 1000, _h * 1000), shutter, "Roller shutter, %.1f by %.1f m" % (_w, _h), "door", "industrial", w=_w, h=_h)
reg("opening.door.loading_dock", dock_door, "Loading dock door with seal and leveller", "door", "industrial")
reg("opening.shopfront.w4000", shopfront, "Shopfront, 4 m", "door", "retail")
reg("opening.shopfront.w6000", shopfront, "Shopfront, 6 m", "door", "retail", w=6.0)
for _h in (3.0, 3.6, 4.2):
	register("opening.curtain_wall.h%d" % (_h * 1000), curtain_wall, "Curtain wall module, %.1f m storey" % _h, family="opening", tags=("opening", "window", "office"), stretch="x", h=_h)
register("opening.extra.sill", extras, "Window sill, per metre", family="opening", tags=("opening",), stretch="x")
for _w, _l in (("shutters", "Window shutters, pair"), ("awning", "Awning"), ("canopy", "Glass door canopy"), ("porch", "Open porch"), ("letterbox", "Letter plate"), ("security_grille", "Window security grille"), ("roller_blind_box", "External blind box")):
	reg("opening.extra." + _w, extras, _l, what=_w, w=1.2 if _w not in ("awning",) else 3.0)

for _m in ("concrete", "timber", "steel"):
	for _w in (0.8, 1.2, 1.8):
		reg("circulation.stair.%s_%d" % (_m, _w * 1000), stair, "%s stair flight, %.1f m wide" % (_m.capitalize(), _w), "stair", material=_m, w=_w)
	for _r in (2.6, 3.6, 4.2):
		reg("circulation.stair.%s_rise_%d" % (_m, _r * 1000), stair, "%s stair flight, %.1f m rise" % (_m.capitalize(), _r), "stair", material=_m, rise=_r)
reg("circulation.stair.spiral", spiral, "Spiral stair, 1.8 m diameter", "stair")
reg("circulation.stair.spiral_wide", spiral, "Spiral stair, 2.4 m diameter", "stair", r=1.2)
reg("circulation.stair.dogleg_concrete", dogleg, "Dog-leg stair with half landing, concrete", "stair")
reg("circulation.stair.dogleg_steel", dogleg, "Dog-leg stair with half landing, steel", "stair", material="steel")
reg("circulation.stair.dogleg_wide", dogleg, "Dog-leg stair, 1.5 m wide, 3.6 m rise", "stair", rise=3.6, w=1.5)
for _n in (2, 3, 4):
	reg("circulation.stair.fire_escape_%d" % _n, fire_escape, "External fire escape, %d storeys" % _n, "stair", "outdoor", storeys=_n)
for _r, _g in ((0.3, 12.0), (0.6, 12.0), (1.0, 15.0), (0.15, 8.0)):
	reg("circulation.ramp.rise_%d" % (_r * 1000), ramp, "Access ramp, %d mm rise" % (_r * 1000), "ramp", "outdoor", rise=_r, gradient=_g, rails=_r > 0.2)
reg("circulation.ramp.vehicle", ramp, "Vehicle ramp, 3 m rise", "ramp", rise=3.0, w=3.5, gradient=8.0, rails=False)
for _n in (2, 3, 5):
	reg("circulation.steps.concrete_%d" % _n, steps, "Entrance steps, %d risers" % _n, "stair", "outdoor", n=_n)
reg("circulation.steps.stone_wide", steps, "Wide stone steps, 4 risers", "stair", "outdoor", n=4, w=3.0, slot="paving")
reg("circulation.ladder.cat_6m", cat_ladder, "Fixed ladder with cage, 6 m", "ladder")
reg("circulation.ladder.cat_3m", cat_ladder, "Fixed ladder, 3 m", "ladder", h=3.0, cage=False)
reg("circulation.ladder.cat_12m", cat_ladder, "Fixed ladder with cage, 12 m", "ladder", h=12.0)
for _s, _l in (("glass", "Glass balustrade"), ("steel", "Steel balustrade"), ("timber", "Timber balustrade"), ("wire", "Wire balustrade"), ("wall_rail", "Wall handrail"), ("parapet", "Brick parapet")):
	register("circulation.balustrade." + _s, balustrade, _l + ", per metre", family="circulation", tags=("circulation", "balustrade"), stretch="x", style=_s)
reg("circulation.balustrade.newel_timber", newel, "Timber newel post", "balustrade")
reg("circulation.balustrade.post_steel", newel, "Stainless balustrade post", "balustrade", style="steel")
for _w, _l in (("goods", "Goods lift"), ("bed", "Hospital bed lift"), ("small", "Passenger lift, 6 person"), ("platform", "Platform lift"), ("stairlift", "Stairlift"), ("dumb_waiter", "Service lift hatch"), ("shaft", "Lift shaft, one storey"), ("motor_room", "Lift machine")):
	reg("circulation.lift." + _w, lift_variant, _l, "lift", what=_w)
