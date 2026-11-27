"""Site equipment and stored materials rebuilt to the person's reference sheets: cabins,
scaffold, formwork, generators, traffic kit, fences, barriers, stacks, tanks, pallets and
skips. Origin: ground centre. Ids that the timelapse already places keep their footprint
and facing."""
import math

import bpy
from mathutils import Matrix

import kit
from recipes.siteplant import reg, names, wheel, rails, Y, K, G, D, W

GAL, BLUE, PLY, TIMBER = "steel_galvanised", "container_blue", "ply_brown", "softwood"


def turn_since(before):
	"""Turns everything made since `before` a quarter turn, so its length runs along X."""
	m = Matrix.Rotation(math.radians(-90), 4, "Z")
	for ob in bpy.context.scene.collection.objects:
		if ob.name in before:
			continue
		if ob.type == "MESH":
			ob.data.transform(m)
		else:
			ob.location = m @ ob.location


# --- cabins ---------------------------------------------------------------------------------

def container(l=6.06, use="office", paint=BLUE, along="y", w=2.44, h=2.59):
	"""A corrugated steel cabin on a container frame, long side along Y. `use` is office
	(door and windows on the +X side), welfare (two doors and high windows) or store (plain,
	with double doors at the +Y end)."""
	before = names()
	with kit.stage("frame"):
		for sx in (-1, 1):
			for sy in (-1, 1):
				kit.box((0.16, 0.16, h), (sx * (w / 2 - 0.08), sy * (l / 2 - 0.08), h / 2), paint, "corner_post")
				for z in (0.06, h - 0.06):
					kit.box((0.18, 0.18, 0.12), (sx * (w / 2 - 0.08), sy * (l / 2 - 0.08), z), D, "corner_casting")
			for z in (0.08, h - 0.08):
				kit.box((0.12, l - 0.32, 0.16), (sx * (w / 2 - 0.06), 0, z), paint, "side_rail")
		for sy in (-1, 1):
			for z in (0.08, h - 0.08):
				kit.box((w - 0.32, 0.12, 0.16), (0, sy * (l / 2 - 0.06), z), paint, "end_rail")
		with kit.hollow(0.1):
			kit.box((w - 0.1, l - 0.1, 0.14), (0, 0, 0.09), D, "floor")
	with kit.stage("main"):
		with kit.hollow(0.03):
			kit.box((w - 0.14, l - 0.14, h - 0.2), (0, 0, h / 2), paint, "walls")
			kit.box((w - 0.1, l - 0.1, 0.05), (0, 0, h - 0.04), paint if use == "store" else W, "roof")
		# Openings first, so the corrugation can leave them clear.
		gaps = []
		xs = w / 2 - 0.05
		def window(y, ww, wh, z):
			gaps.append((y - ww / 2 - 0.1, y + ww / 2 + 0.1))
			side_frame(ww, wh, (xs, y, z))
			kit.box((0.02, ww - 0.1, wh - 0.1), (xs, y, z + wh / 2), "glass_dark", "window_glass")
			kit.box((0.05, 0.04, wh - 0.1), (xs + 0.01, y, z + wh / 2), W, "window_mullion")
		def door(y):
			gaps.append((y - 0.6, y + 0.6))
			kit.box((0.05, 0.95, 2.05), (xs + 0.01, y, 0.2 + 1.025), W, "door")
			kit.box((0.03, 0.5, 0.6), (xs + 0.03, y, 1.75), "glass_dark", "door_glass")
			kit.box((0.05, 0.04, 0.14), (xs + 0.05, y - 0.36, 1.2), D, "door_handle")
			for dy in (-0.52, 0.52):
				kit.box((0.07, 0.07, 2.1), (xs + 0.01, y + dy, 0.2 + 1.05), W, "door_frame")
			kit.box((0.07, 1.11, 0.07), (xs + 0.01, y, 2.3), W, "door_frame")
		if use == "office":
			if l < 4.0:
				door(-l / 2 + 0.95)
				window(l / 2 - 1.05, 0.95, 1.1, 1.0)
			else:
				door(-l / 2 + 1.0)
				n = max(1, int((l - 2.6) / 2.0))
				for i in range(n):
					window(-l / 2 + 2.1 + (l - 2.9) * (i + 0.5) / n, 1.5, 1.1, 1.0)
		elif use == "welfare":
			door(-l / 2 + 1.0)
			door(l / 2 - 1.0)
			window(0, 1.2, 0.6, 1.55)
		pitch = 0.28
		n = int((l - 0.4) / pitch)
		for sx in (-1, 1):
			for i in range(n):
				y = -l / 2 + 0.2 + pitch * (i + 0.5) * (l - 0.4) / (n * pitch)
				if sx > 0 and any(a < y < b for a, b in gaps):
					continue
				kit.prism([(-0.09, 0), (0.09, 0), (0.04, 0.035), (-0.04, 0.035)], h - 0.36, (sx * (w / 2 - 0.07), y, h / 2), paint, "corrugation", axis="z", rot=(0, 0, -90 * sx))
		ne = int((w - 0.4) / pitch)
		for sy in (-1, 1):
			if use == "store" and sy > 0:
				for sx in (-1, 1):
					kit.box((w / 2 - 0.2, 0.05, h - 0.4), (sx * (w / 4 - 0.08), l / 2 - 0.04, h / 2), paint, "store_door")
					for dx in (0.25, 0.75):
						kit.rod((sx * (w / 2 - 0.2) * dx, l / 2, 0.2), (sx * (w / 2 - 0.2) * dx, l / 2, h - 0.2), 0.02, GAL, "lock_rod", segs=6)
				continue
			for i in range(ne):
				x = -w / 2 + 0.2 + (w - 0.4) * (i + 0.5) / ne
				kit.prism([(-0.09, 0), (0.09, 0), (0.04, 0.035), (-0.04, 0.035)], h - 0.36, (x, sy * (l / 2 - 0.07), h / 2), paint, "corrugation", axis="z", rot=(0, 0, 0 if sy > 0 else 180))
	if along == "x":
		turn_since(before)


def side_frame(ww, wh, at):
	"""A window frame lying in the YZ plane (facing X)."""
	x, y, z = at
	for dy in (-1, 1):
		kit.box((0.06, 0.06, wh), (x, y + dy * (ww / 2 - 0.03), z + wh / 2), W, "window_frame")
	for dz in (0.03, wh - 0.03):
		kit.box((0.06, ww, 0.06), (x, y, z + dz), W, "window_frame")


def toilet(paint=BLUE):
	"""A portable toilet: moulded cabin, white barrel roof, door and vent."""
	with kit.stage("main"):
		kit.box((1.2, 1.3, 0.12), (0, 0, 0.06), K, "skid")
		with kit.hollow(0.06):
			kit.box((1.12, 1.2, 2.0), (0, 0, 1.12), paint, "cabin")
			kit.prism([(-0.6, 0), (0.6, 0), (0.56, 0.13), (0.4, 0.24), (0.2, 0.31), (0, 0.33), (-0.2, 0.31), (-0.4, 0.24), (-0.56, 0.13)], 1.3, (0, 0, 2.12), W, "roof")
		for sx in (-1, 1):
			kit.box((0.1, 0.06, 2.0), (sx * 0.51, 0.61, 1.12), paint, "door_post")
			for z in (0.5, 1.1, 1.7):
				kit.box((0.03, 1.0, 0.25), (sx * 0.565, 0, z), paint, "side_rib")
		kit.box((0.92, 0.04, 1.9), (0, 0.62, 1.1), paint, "door")
		kit.box((0.8, 0.02, 0.5), (0, 0.645, 1.6), paint, "door_panel")
		kit.box((0.8, 0.02, 0.7), (0, 0.645, 0.75), paint, "door_panel")
		kit.box((0.04, 0.05, 0.16), (0.36, 0.66, 1.15), W, "door_latch")
		kit.box((0.5, 0.02, 0.12), (0, 0.645, 1.98), K, "door_vent")
		kit.rod((0.4, -0.45, 2.1), (0.4, -0.45, 2.62), 0.045, W, "vent_pipe", segs=8)


def silo(h=9.6, r=1.3):
	"""A cement silo on four legs with a cone hopper, ladder and fill pipe."""
	with kit.stage("frame"):
		leg = r * 0.78
		top = h * 0.42
		for sx in (-1, 1):
			for sy in (-1, 1):
				kit.box((0.16, 0.16, top), (sx * leg, sy * leg, top / 2), G, "leg")
				kit.box((0.4, 0.4, 0.03), (sx * leg, sy * leg, 0.015), D, "foot")
			for z in (top * 0.3, top * 0.75):
				kit.box((0.08, 2 * leg, 0.08), (sx * leg, 0, z), G, "tie")
				kit.box((2 * leg, 0.08, 0.08), (0, sx * leg, z), G, "tie")
			kit.strut((sx * leg, -leg, top * 0.3), (sx * leg, leg, top * 0.75), 0.05, 0.05, G, "brace")
			kit.strut((-leg, sx * leg, top * 0.3), (leg, sx * leg, top * 0.75), 0.05, 0.05, G, "brace")
	with kit.stage("main"):
		with kit.hollow(0.04):
			kit.lathe([(0.18, h * 0.16), (r, h * 0.38), (r, h - 0.5), (r * 0.8, h - 0.22), (r * 0.25, h - 0.14)], (0, 0, 0), W, "silo", segs=28)
		for z in (h * 0.38, h * 0.62, h - 0.5):
			kit.tube(r + 0.02, 0.08, (0, 0, z), G, "band", wall=0.03, segs=28)
		kit.cyl(0.18, 0.3, (0, 0, h * 0.16 - 0.12), D, "outlet", segs=12)
		kit.box((0.5, 0.35, 0.3), (0, 0, h * 0.16 - 0.4), Y, "screw_feed")
		kit.rod((0, 0, h * 0.16 - 0.4), (0, 2.2, 1.2), 0.11, D, "screw_conveyor", segs=10)
		kit.rod((r + 0.1, -0.3, 0.6), (r + 0.1, -0.3, h - 0.3), 0.05, GAL, "fill_pipe", segs=8)
		kit.rod((r + 0.1, -0.3, h - 0.3), (0.2, -0.1, h - 0.08), 0.05, GAL, "fill_pipe", segs=8)
		kit.cyl(0.25, 0.35, (-0.4, 0.2, h + 0.02), G, "filter", segs=12)
	with kit.stage("access"):
		x = -r - 0.12
		for dy in (-0.2, 0.2):
			kit.rod((x, dy, 0.3), (x, dy, h - 0.2), 0.02, Y, "ladder_stile", segs=6)
		z = 0.5
		while z < h - 0.3:
			kit.rod((x, -0.2, z), (x, 0.2, z), 0.012, Y, "rung", segs=5)
			z += 0.3
		z = 2.5
		while z < h - 0.4:
			kit.tube(0.36, 0.03, (x - 0.3, 0, z), Y, "cage_hoop", wall=0.02, segs=12)
			z += 0.9
		ring = [(r * 0.78 * math.cos(math.radians(a)), r * 0.78 * math.sin(math.radians(a)), h - 0.3) for a in range(0, 361, 45)]
		rails(ring, 1.0, 0.018, Y, "top_rail")


# --- scaffold and formwork ------------------------------------------------------------------

def stair_tower(levels=3, w=1.6, l=3.0, lift=2.0):
	"""A scaffold access tower: standards, ledgers, braces, boarded platforms with hatches
	and a ladder up through each."""
	with kit.stage("frame"):
		top = levels * lift + 1.1
		for sx in (-1, 1):
			for sy in (-1, 1):
				x, y = sx * w / 2, sy * l / 2
				kit.rod((x, y, 0.05), (x, y, top), 0.024, GAL, "standard", segs=8)
				kit.box((0.15, 0.15, 0.01), (x, y, 0.005), GAL, "base_plate")
				kit.box((0.22, 0.45, 0.04), (x, y, -0.0 + 0.03), TIMBER, "sole_board")
		for i in range(levels + 1):
			z = max(0.25, i * lift)
			for sx in (-1, 1):
				kit.rod((sx * w / 2, -l / 2, z), (sx * w / 2, l / 2, z), 0.024, GAL, "ledger", segs=6)
				kit.rod((-w / 2, sx * l / 2, z), (w / 2, sx * l / 2, z), 0.024, GAL, "transom", segs=6)
				if i > 0:
					for dz in (0.5, 1.0):
						kit.rod((sx * w / 2, -l / 2, z + dz), (sx * w / 2, l / 2, z + dz), 0.02, GAL, "guard_rail", segs=6)
						kit.rod((-w / 2, sx * l / 2, z + dz), (w / 2, sx * l / 2, z + dz), 0.02, GAL, "guard_rail", segs=6)
		for i in range(levels):
			z0, z1 = max(0.25, i * lift), (i + 1) * lift
			s = 1 if i % 2 == 0 else -1
			kit.rod((-w / 2, -s * l / 2, z0), (-w / 2, s * l / 2, z1), 0.02, GAL, "brace", segs=6)
			kit.rod((w / 2, s * l / 2, z0), (w / 2, -s * l / 2, z1), 0.02, GAL, "brace", segs=6)
	with kit.stage("decks"):
		for i in range(1, levels + 1):
			z = i * lift + 0.045
			s = 1 if i % 2 == 0 else -1
			hy = s * (l / 2 - 0.5)
			# Boards, leaving a hatch at one end.
			for k in range(6):
				x = -w / 2 + 0.05 + (w - 0.1) * (k + 0.5) / 6
				if k < 3:
					ln = l - 1.0
					kit.box((0.235, ln, 0.04), (x, -s * 0.5, z), TIMBER, "board")
				else:
					kit.box((0.235, l - 0.04, 0.04), (x, 0, z), TIMBER, "board")
			kit.box((0.72, 0.9, 0.03), (-w / 2 + 0.05 + (w - 0.1) * 0.25, hy, z + 0.035), PLY, "hatch")
			for sx in (-1, 1):
				kit.box((0.03, l, 0.15), (sx * (w / 2 - 0.03), 0, z + 0.095), TIMBER, "toe_board")
				kit.box((w, 0.03, 0.15), (0, sx * (l / 2 - 0.03), z + 0.095), TIMBER, "toe_board")
	with kit.stage("ladders"):
		for i in range(levels):
			s = 1 if i % 2 == 1 else -1
			z0, z1 = i * lift, (i + 1) * lift + 1.0
			x = -w / 2 + 0.05 + (w - 0.1) * 0.25
			ya, yb = s * (l / 2 - 1.3), s * (l / 2 - 0.55)
			for dx in (-0.2, 0.2):
				kit.rod((x + dx, ya, z0), (x + dx, yb, z1), 0.022, "aluminium", "ladder_stile", segs=6)
			n = int((z1 - z0) / 0.28)
			for k in range(1, n):
				t = k / n
				kit.rod((x - 0.2, ya + (yb - ya) * t, z0 + (z1 - z0) * t), (x + 0.2, ya + (yb - ya) * t, z0 + (z1 - z0) * t), 0.013, "aluminium", "rung", segs=5)
	kit.socket("up", (0, 0, levels * lift))


def table_form(w=2.4, l=4.8, h=2.6):
	"""A slab formwork table: ply deck on yellow beams and props, with brown guard boards
	along two edges."""
	with kit.stage("props"):
		for sx in (-1, 1):
			for y in (-l / 2 + 0.5, 0, l / 2 - 0.5):
				x = sx * (w / 2 - 0.4)
				kit.rod((x, y, 0.02), (x, y, h * 0.55), 0.04, G, "prop_outer", segs=10)
				kit.rod((x, y, h * 0.55), (x, y, h - 0.37), 0.03, GAL, "prop_inner", segs=10)
				kit.cyl(0.055, 0.08, (x, y, h * 0.55), Y, "prop_collar", segs=10)
				kit.box((0.2, 0.2, 0.012), (x, y, 0.006), G, "prop_foot")
				kit.box((0.18, 0.18, 0.012), (x, y, h - 0.365), G, "prop_head")
				for a in (0, 120, 240):
					c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
					kit.rod((x, y, 0.75), (x + 0.5 * c, y + 0.5 * s, 0.02), 0.014, G, "tripod", segs=5)
	with kit.stage("main"):
		for sx in (-1, 1):
			kit.i_section(0.08, 0.2, 0.03, 0.03, l - 0.1, (sx * (w / 2 - 0.4), 0, h - 0.26), Y, "primary_beam", axis="y")
		n = int(l / 0.5)
		for i in range(n + 1):
			kit.i_section(0.08, 0.14, 0.03, 0.03, w - 0.05, (0, -l / 2 + 0.1 + (l - 0.2) * i / n, h - 0.09), Y, "secondary_beam", axis="x")
		kit.box((w, l, 0.021), (0, 0, h - 0.0105), "plywood", "deck")
	with kit.stage("edge"):
		for i in range(4):
			y = -l / 2 + 0.1 + (l - 0.2) * i / 3
			kit.box((0.05, 0.05, 1.3), (w / 2 + 0.03, y, h + 0.45), Y, "guard_post")
		for i in range(3):
			x = -w / 2 + 0.1 + (w - 0.2) * i / 2
			kit.box((0.05, 0.05, 1.3), (x, l / 2 + 0.03, h + 0.45), Y, "guard_post")
		for z in (0.12, 0.55, 1.0):
			kit.box((0.025, l, 0.15), (w / 2 - 0.01, 0, h + z), PLY, "guard_board")
			kit.box((w, 0.025, 0.15), (0, l / 2 - 0.01, h + z), PLY, "guard_board")


# --- small plant and traffic ----------------------------------------------------------------

def generator(s=1.0, paint=Y):
	"""A towed generator: canopy on a single axle trailer with drawbar and jockey wheel.
	`s` scales the canopy (1 is about 60 kVA)."""
	w, l, h = 1.05 * s ** 0.5, 2.1 * s, 1.15 * s ** 0.6
	r = 0.3
	z0 = r + 0.12
	with kit.stage("wheels"):
		ys = (0,) if s < 1.5 else (-0.4, 0.4)
		for sx in (-1, 1):
			for y in ys:
				wheel(r, 0.2, (sx * (w / 2 + 0.13), y, r))
				kit.prism([(-r - 0.08, 0), (-r * 0.7, r * 0.75), (r * 0.7, r * 0.75), (r + 0.08, 0), (r + 0.04, 0), (r * 0.65, r * 0.7), (-r * 0.65, r * 0.7), (-r - 0.04, 0)], 0.24, (sx * (w / 2 + 0.13), y, r + 0.08), K, "mudguard", axis="x")
	with kit.stage("main"):
		kit.box((w, l + 0.1, 0.1), (0, 0, z0 - 0.05), D, "chassis")
		kit.strut((-w / 2 + 0.1, l / 2, z0 - 0.05), (0, l / 2 + 0.95, z0 - 0.05), 0.06, 0.08, D, "drawbar")
		kit.strut((w / 2 - 0.1, l / 2, z0 - 0.05), (0, l / 2 + 0.95, z0 - 0.05), 0.06, 0.08, D, "drawbar")
		kit.box((0.1, 0.25, 0.1), (0, l / 2 + 1.05, z0 - 0.05), D, "hitch")
		kit.rod((0.12, l / 2 + 0.8, z0), (0.12, l / 2 + 0.8, 0.16), 0.022, GAL, "jockey_leg", segs=6)
		kit.cyl(0.1, 0.06, (0.12, l / 2 + 0.8, 0.1), K, "jockey_wheel", axis="x", segs=12)
		for sx in (-1, 1):
			kit.rod((sx * (w / 2 - 0.08), -l / 2 + 0.05, z0), (sx * (w / 2 - 0.08), -l / 2 + 0.05, 0.03), 0.02, GAL, "prop_stand", segs=6)
		with kit.hollow(0.3):
			kit.rounded_box((w, l, h), (0, 0, z0 + h / 2), paint, "canopy", radius=0.05)
		for sx in (-1, 1):
			kit.box((0.012, l * 0.36, h * 0.7), (sx * (w / 2 + 0.004), -l * 0.24, z0 + h * 0.5), paint, "service_door")
			kit.box((0.012, l * 0.36, h * 0.7), (sx * (w / 2 + 0.004), l * 0.2, z0 + h * 0.5), paint, "service_door")
			for k in range(5):
				kit.box((0.02, l * 0.28, 0.025), (sx * (w / 2 + 0.012), l * 0.2, z0 + h * (0.3 + 0.1 * k)), K, "louvre")
			kit.box((0.03, 0.1, 0.03), (sx * (w / 2 + 0.02), -l * 0.08, z0 + h * 0.5), D, "door_handle")
		kit.box((w * 0.55, 0.02, h * 0.4), (0, -l / 2 - 0.006, z0 + h * 0.6), K, "control_panel")
		kit.box((0.1, 0.03, 0.1), (w * 0.15, -l / 2 - 0.02, z0 + h * 0.7), "hazard_red", "stop_button")
		kit.rod((w * 0.25, l * 0.3, z0 + h), (w * 0.25, l * 0.3, z0 + h + 0.3), 0.04, D, "exhaust", segs=8)
		kit.box((0.2, 0.08, 0.03), (0, 0, z0 + h + 0.03), D, "lifting_eye")
	kit.socket("hitch", (0, l / 2 + 1.1, z0 - 0.05))


def traffic_light():
	"""A portable traffic signal on a wheeled battery base."""
	with kit.stage("main"):
		with kit.hollow(0.5):
			kit.rounded_box((0.6, 0.85, 0.5), (0, 0, 0.42), Y, "battery_box", radius=0.04)
		kit.box((0.5, 0.75, 0.04), (0, 0, 0.69), K, "lid")
		for sx in (-1, 1):
			kit.cyl(0.15, 0.08, (sx * 0.35, -0.25, 0.15), "rubber", "wheel", axis="x", segs=14)
			kit.box((0.06, 0.06, 0.17), (sx * 0.25, 0.35, 0.085), D, "foot")
		kit.rod((0, -0.3, 0.6), (0, -0.3, 2.3), 0.035, Y, "pole", segs=10)
		kit.rod((-0.25, -0.5, 1.0), (0.25, -0.5, 1.0), 0.02, D, "handle", segs=6)
		for sx in (-1, 1):
			kit.rod((sx * 0.25, -0.5, 1.0), (sx * 0.25, -0.38, 0.6), 0.02, D, "handle", segs=6)
		with kit.hollow(0.2):
			kit.rounded_box((0.34, 0.2, 0.95), (0, -0.3, 2.65), K, "signal_head", radius=0.03)
		kit.box((0.5, 0.02, 1.15), (0, -0.4, 2.65), K, "backboard")
		for z, slot in ((2.95, "plastic_red"), (2.65, "hivis_orange"), (2.35, "plastic_green")):
			kit.cyl(0.1, 0.03, (0, -0.19, z), slot, "lens", axis="y", segs=16)
			kit.prism([(-0.12, 0), (-0.1, 0.1), (0.1, 0.1), (0.12, 0), (0.1, 0.012), (-0.1, 0.012)], 0.14, (0, -0.14, z + 0.1), K, "hood", axis="y")


def cone(h=0.5, lamp=False):
	"""A traffic cone with a white sleeve; `lamp` adds a road lamp on top."""
	s = h / 0.5
	with kit.stage("main"):
		kit.rounded_box((0.3 * s, 0.3 * s, 0.03 * s), (0, 0, 0.015 * s), K if h > 0.6 else "hivis_orange", "base", radius=0.01)
		r0, r1 = 0.105 * s, 0.025 * s
		kit.lathe([(r0 + 0.012 * s, 0.03 * s), (r0, 0.05 * s), (r1, h), (r1 * 0.6, h + 0.004)], (0, 0, 0), "hivis_orange", "cone", segs=18)
		def rad(z):
			return r0 + (r1 - r0) * (z - 0.05 * s) / (h - 0.05 * s) + 0.003
		kit.lathe([(rad(h * 0.45), h * 0.45), (rad(h * 0.72), h * 0.72)], (0, 0, 0), W, "sleeve", segs=18)
		if lamp:
			kit.box((0.07, 0.07, 0.1), (0, 0, h + 0.05), K, "lamp_body")
			kit.cyl(0.085, 0.07, (0, 0, h + 0.19), "plastic_yellow", "lamp_lens", axis="y", segs=14)
			kit.cyl(0.095, 0.05, (0, 0, h + 0.19), K, "lamp_rim", axis="y", segs=14)


def fence_panel(n=1, w=3.5, h=2.0):
	"""Mobile mesh fence panels on concrete feet; `n` panels in a run along X."""
	with kit.stage("main"):
		x0 = -(n * w) / 2
		for i in range(n):
			cx = x0 + w * (i + 0.5)
			a, b = cx - w / 2 + 0.06, cx + w / 2 - 0.06
			for x in (a, b):
				kit.rod((x, 0, 0.1), (x, 0, h), 0.021, GAL, "fence_post", segs=8)
			for z in (0.22, h * 0.55, h - 0.02):
				kit.rod((a, 0, z), (b, 0, z), 0.016, GAL, "fence_rail", segs=6)
			kit.grid_bars(b - a, h - 0.24, (cx, 0, 0.22 + (h - 0.24) / 2), 22, 7, 0.004, GAL, "fence_mesh")
		for i in range(n + 1):
			x = x0 + w * i
			with kit.hollow(0.9):
				kit.prism([(-0.11, 0), (0.11, 0), (0.09, 0.13), (-0.09, 0.13)], 0.68, (x, 0, 0), "concrete", "fence_foot", axis="y")
			if 0 < i < n:
				kit.box((0.14, 0.05, 0.04), (x, 0, h - 0.3), GAL, "coupler")
	kit.socket("next", (x0 + n * w, 0, 0))


def jersey(l=3.0, h=0.8, slot="concrete"):
	"""A concrete jersey barrier along X."""
	s = h / 0.8
	b, t = 0.3 * s, 0.075 * s
	with kit.stage("main"):
		pts = [(-b, 0), (b, 0), (b, 0.07 * s), (b * 0.6, 0.25 * s), (t, h), (-t, h), (-b * 0.6, 0.25 * s), (-b, 0.07 * s)]
		kit.prism(pts, l, (0, 0, 0), slot, "barrier", axis="x")
		for sx in (-1, 1):
			kit.box((0.25, 2 * b + 0.01, 0.05), (sx * l * 0.3, 0, 0.022), D, "fork_slot")
			kit.tube(0.03, 0.05, (sx * (l / 2 - 0.25), 0, h + 0.02), GAL, "lifting_eye", axis="y", wall=0.01, segs=10)
	kit.socket("next", (l, 0, 0))


# --- stored materials -----------------------------------------------------------------------

def pallet_at(z=0.0, w=1.2, d=1.0, style="block", slot=TIMBER, at=(0, 0)):
	"""A timber pallet with its top at z + 0.144."""
	x0, y0 = at
	if style == "plastic":
		kit.box((w, d, 0.04), (x0, y0, z + 0.13), slot, "pallet_deck")
		for i in range(3):
			for j in range(3):
				kit.rounded_box((0.16, 0.16, 0.11), (x0 + (i - 1) * (w / 2 - 0.09), y0 + (j - 1) * (d / 2 - 0.09), z + 0.055), slot, "pallet_foot", radius=0.02)
		for i in range(5):
			kit.box((0.03, d - 0.1, 0.012), (x0 - w / 2 + 0.15 + (w - 0.3) * i / 4, y0, z + 0.153), slot, "pallet_rib")
		return 0.15
	n = 7
	for i in range(n):
		kit.box((w, 0.1, 0.022), (x0, y0 - d / 2 + 0.05 + (d - 0.1) * i / (n - 1), z + 0.133), slot, "pallet_board")
	if style == "stringer":
		for i in range(3):
			kit.box((0.04, d, 0.09), (x0 + (i - 1) * (w / 2 - 0.02), y0, z + 0.067), slot, "pallet_stringer")
		for y in (-d / 2 + 0.05, 0, d / 2 - 0.05):
			kit.box((w, 0.1, 0.022), (x0, y0 + y, z + 0.011), slot, "pallet_base")
	else:
		for i in range(3):
			kit.box((0.1, d, 0.022), (x0 + (i - 1) * (w / 2 - 0.05), y0, z + 0.111), slot, "pallet_bearer")
			kit.box((0.1, d, 0.022), (x0 + (i - 1) * (w / 2 - 0.05), y0, z + 0.011), slot, "pallet_base")
			for j in range(3):
				kit.box((0.1, 0.14, 0.078), (x0 + (i - 1) * (w / 2 - 0.05), y0 + (j - 1) * (d / 2 - 0.07), z + 0.061), slot, "pallet_block")
	return 0.144


def pallet(w=1.2, d=1.0, style="block", stack=1, load=""):
	with kit.stage("main"):
		z = 0.0
		for i in range(stack):
			z += pallet_at(z, w, d, style, "plastic_blue" if style == "plastic" else TIMBER)
		if load == "boxes":
			for k in range(3):
				for i in range(3):
					for j in range(2):
						kit.box((w / 3 - 0.02, d / 2 - 0.02, 0.36), (-w / 3 + i * w / 3, -d / 4 + j * d / 2, z + 0.18 + k * 0.365), "softwood" if (i + j + k) % 3 else "plywood", "carton")
			with kit.hollow(0.01):
				kit.box((w + 0.01, d + 0.01, 0.7), (0, 0, z + 0.55), "glass", "shrink_wrap")
		elif load == "barrels":
			for sx in (-1, 1):
				for sy in (-1, 1):
					barrel_at((sx * 0.3, sy * 0.25 * d / 0.8 if d < 1 else sy * 0.3, z))
	kit.socket("load", (0, 0, z))


def barrel_at(at, slot=BLUE):
	with kit.hollow(0.08):
		kit.lathe([(0.27, 0.0), (0.285, 0.015), (0.285, 0.28), (0.297, 0.295), (0.285, 0.31), (0.285, 0.57), (0.297, 0.585), (0.285, 0.6), (0.285, 0.865), (0.297, 0.88), (0.275, 0.88), (0.27, 0.86)], at, slot, "barrel", segs=20)
	kit.cyl(0.03, 0.02, (at[0] + 0.17, at[1], at[2] + 0.87), GAL, "bung", segs=8)


def barrel(slot=BLUE):
	with kit.stage("main"):
		barrel_at((0, 0, 0), slot)


def ibc(w=1.0, d=1.2, h=1.16, stack=1):
	"""An intermediate bulk container: plastic tank in a galvanised cage on a pallet base."""
	with kit.stage("main"):
		for k in range(stack):
			z = k * (h + 0.01)
			kit.box((w, d, 0.02), (0, 0, z + 0.14), GAL, "base_plate")
			for x in (-w / 2 + 0.06, 0, w / 2 - 0.06):
				kit.box((0.1, d, 0.13), (x, 0, z + 0.065), GAL, "runner")
			th = h - 0.2
			with kit.hollow(0.03):
				kit.rounded_box((w - 0.06, d - 0.06, th), (0, 0, z + 0.16 + th / 2), "plastic_white", "tank", radius=0.07)
			zc = z + 0.15 + (th + 0.02) / 2
			for sy in (-1, 1):
				kit.grid_bars(w, th + 0.02, (0, sy * d / 2, zc), 6, 4, 0.009, GAL, "cage")
			for sx in (-1, 1):
				kit.grid_bars(d, th + 0.02, (sx * w / 2, 0, zc), 7, 4, 0.009, GAL, "cage", plane="yz")
				kit.box((0.03, d, 0.03), (sx * (w / 2 - 0.015), 0, z + h - 0.03), GAL, "top_rail")
			for y in (-d / 4, d / 4):
				kit.box((w, 0.03, 0.02), (0, y, z + h - 0.03), GAL, "top_bar")
			kit.cyl(0.11, 0.05, (0, 0, z + h - 0.03), K, "cap", segs=14)
			kit.cyl(0.04, 0.12, (0, d / 2 - 0.02, z + 0.24), "plastic_red", "valve", axis="y", segs=8)
			kit.box((0.4, 0.01, 0.3), (0, d / 2 + 0.012, z + h * 0.6), W, "label_plate")


def cable_drum(d=1.2, w=0.75, cable=K):
	"""A timber cable drum, axle along X."""
	r = d / 2
	with kit.stage("main"):
		for sx in (-1, 1):
			x = sx * (w / 2 - 0.03)
			kit.tube(r, 0.06, (x, 0, r), TIMBER, "flange", axis="x", wall=r - 0.06, segs=28)
			for a in range(0, 360, 60):
				c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
				kit.cyl(0.02, 0.02, (x + sx * 0.035, r * 0.45 * c, r + r * 0.45 * s), GAL, "bolt", axis="x", segs=6)
			kit.tube(0.1, 0.02, (x + sx * 0.035, 0, r), GAL, "bush", axis="x", wall=0.04, segs=12)
		kit.cyl(r * 0.45, w - 0.12, (0, 0, r), TIMBER, "barrel", axis="x", segs=20)
		with kit.hollow(0.6):
			kit.lathe([(r * 0.45, -w / 2 + 0.07)] + [(r * 0.8 + 0.012 * (i % 2), -w / 2 + 0.07 + (w - 0.14) * i / 16) for i in range(17)] + [(r * 0.45, w / 2 - 0.07)], (0, 0, r), cable, "cable", segs=24, rot=(0, 90, 0))
		for sy in (-1, 1):
			kit.prism([(0, 0), (0.18, 0), (0, 0.1)], 0.3, (0, sy * 0.3, 0), TIMBER, "chock", axis="x", rot=(0, 0, 0 if sy < 0 else 180))


def bearers(l, w, z, n=3, size=0.075):
	for i in range(n):
		y = -l / 2 + l * 0.12 + (l * 0.76) * i / (n - 1)
		kit.box((w, size, size), (0, y, z + size / 2), TIMBER, "bearer")
	return size


def hollowcore(l=6.0, n=4, t=0.2, w=1.2):
	"""Precast hollowcore planks stacked on timber bearers."""
	with kit.stage("main"):
		z = 0.0
		for k in range(n):
			z += bearers(l, w, z, 3)
			kit.prism([(-w / 2, 0), (w / 2, 0), (w / 2, t * 0.5), (w / 2 - 0.02, t), (-w / 2 + 0.02, t), (-w / 2, t * 0.5)], l, (0, 0, z), "concrete", "plank", axis="y")
			nc = int(w / (t * 0.95))
			for i in range(nc):
				x = -w / 2 + w * (i + 0.5) / nc
				for sy in (-1, 1):
					kit.cyl(t * 0.33, 0.012, (x, sy * l / 2, z + t / 2), D, "core", axis="y", segs=12)
			z += t
	kit.socket("load", (0, 0, z))


def beam_stack(l=6.0, what="steel", rows=3, per=3):
	"""Steel beams or timber baulks stacked on bearers, along Y."""
	with kit.stage("main"):
		z = 0.0
		if what == "steel":
			bw, bd = 0.2, 0.3
			for k in range(rows):
				z += bearers(l, per * (bw + 0.08), z, 3)
				for i in range(per):
					x = (i - (per - 1) / 2) * (bw + 0.08)
					kit.i_section(bw, bd, 0.016, 0.01, l - 0.3 * ((i + k) % 2), (x, 0, z + bd / 2), D, "beam", axis="y")
				z += bd
		else:
			bw, bd = 0.25, 0.25
			for k in range(rows):
				z += bearers(l, per * (bw + 0.02), z, 3, 0.05)
				for i in range(per):
					x = (i - (per - 1) / 2) * (bw + 0.02)
					kit.box((bw, l - 0.2 * ((i * 2 + k) % 3), bd), (x, 0.05 * ((i + k) % 2), z + bd / 2), "glulam" if (i + k) % 2 else TIMBER, "baulk")
				z += bd
	kit.socket("load", (0, 0, z))


def pipe_stack(l=2.5, r=0.3, base=3, slot="concrete", wall=0.05, collar=False):
	"""Pipes in a pyramid along Y, chocked on bearers."""
	with kit.stage("main"):
		wd = base * 2 * r
		bearers(l, wd + 0.3, 0.0, 2)
		z0 = 0.075 + r
		for k in range(base):
			n = base - k
			for i in range(n):
				x = (i - (n - 1) / 2) * 2 * r
				z = z0 + k * r * math.sqrt(3)
				kit.tube(r, l, (x, 0, z), slot, "pipe", axis="y", wall=wall, segs=20)
				if collar:
					kit.tube(r * 1.12, l * 0.06, (x, l / 2 - l * 0.03, z), slot, "pipe_socket", axis="y", wall=wall + r * 0.12, segs=20)
		for sx in (-1, 1):
			for y in (-l * 0.38, l * 0.38):
				kit.prism([(0, 0), (sx * 0.2, 0), (0, 0.12)], 0.075, (sx * (wd / 2 + 0.0), y, 0.075), TIMBER, "chock", axis="y")


def skip(w=1.8, l=3.1, h=1.23, full=""):
	"""A steel skip along Y with sloping ends, ribs and lifting lugs. `full` heaps it with
	soil or rubble."""
	lb = l * 0.62
	t = 0.035
	with kit.stage("main"):
		kit.box((w, lb, t), (0, 0, t / 2 + 0.04), Y, "floor")
		for y in (-lb * 0.3, lb * 0.3):
			kit.box((w * 0.9, 0.1, 0.04), (0, y, 0.02), D, "runner")
		for sx in (-1, 1):
			kit.prism([(-lb / 2, 0.04), (lb / 2, 0.04), (l / 2, h), (-l / 2, h)], t, (sx * (w / 2 - t / 2), 0, 0), Y, "side", axis="x")
			kit.box((0.07, l, 0.07), (sx * (w / 2 - 0.01), 0, h - 0.035), Y, "rim")
			for y in (-lb * 0.28, lb * 0.28):
				kit.box((0.05, 0.08, h - 0.12), (sx * (w / 2 + 0.02), y, 0.04 + (h - 0.12) / 2), Y, "rib")
			for sy in (-1, 1):
				kit.cyl(0.045, 0.14, (sx * (w / 2 + 0.07), sy * l * 0.36, h * 0.72), D, "lug", axis="x", segs=10)
				kit.cyl(0.07, 0.02, (sx * (w / 2 + 0.14), sy * l * 0.36, h * 0.72), D, "lug_head", axis="x", segs=10)
		for sy in (-1, 1):
			a, b = sy * lb / 2, sy * l / 2
			kit.prism([(a, 0.04), (a + sy * t * 1.3, 0.04), (b + sy * t * 1.3, h), (b, h)] if sy > 0 else [(a + sy * t * 1.3, 0.04), (a, 0.04), (b, h), (b + sy * t * 1.3, h)], w, (0, 0, 0), Y, "end", axis="x")
			kit.box((w, 0.07, 0.07), (0, sy * (l / 2 + 0.01), h - 0.035), Y, "rim")
		if full:
			slot = "soil" if full == "soil" else "concrete"
			kit.lathe([(1.0, 0.0), (0.8, 0.22), (0.45, 0.4), (0.12, 0.47)], (0, 0, h - 0.12), slot, "heap", segs=14, scale=(w / 2 - 0.06, l / 2 - 0.1, 1.0))
			if full == "rubble":
				for i in range(9):
					a = i * 2.4
					kit.chunk((0.4, 0.35, 0.25), (math.cos(a) * w * 0.25, math.sin(a) * l * 0.3, h + 0.12 + 0.05 * (i % 3)), "brick" if i % 2 else "concrete", "rubble", seed=i + 3)


# --- registration ---------------------------------------------------------------------------

reg("cabin.site_office", container, "Site office cabin, 20 ft", "temporary", "cabin", along="x")
reg("cabin.office_20", container, "Office cabin, 20 ft", "temporary", "cabin")
reg("cabin.office_10", container, "Office cabin, 10 ft", "temporary", "cabin", l=2.99)
reg("cabin.office_32", container, "Office cabin, 32 ft", "temporary", "cabin", l=9.75)
reg("cabin.welfare", container, "Welfare cabin, 24 ft", "temporary", "cabin", l=7.32, use="welfare", paint="plastic_green")
reg("cabin.store", container, "Secure store, 20 ft", "temporary", "cabin", use="store")
reg("cabin.store_10", container, "Secure store, 10 ft", "temporary", "cabin", l=2.99, use="store")
reg("cabin.toilet", toilet, "Portable toilet", "temporary", "cabin")
reg("cabin.toilet_green", toilet, "Portable toilet, green", "temporary", "cabin", paint="plastic_green")
reg("cabin.silo", silo, "Cement silo", "temporary", "concrete")
reg("cabin.silo_small", silo, "Cement silo, small", "temporary", "concrete", h=6.5, r=1.0)

reg("access.stair_tower", stair_tower, "Scaffold access tower, 3 lifts", "scaffold", "access")
reg("access.stair_tower_2", stair_tower, "Scaffold access tower, 2 lifts", "scaffold", "access", levels=2)
reg("access.stair_tower_5", stair_tower, "Scaffold access tower, 5 lifts", "scaffold", "access", levels=5)
reg("temporary.table_form", table_form, "Slab formwork table", "temporary", "formwork")
reg("temporary.table_form_small", table_form, "Slab formwork table, 2.4 m", "temporary", "formwork", l=2.4)

reg("small.generator", generator, "Towed generator, 60 kVA", "small_plant")
reg("small.generator_20kva", generator, "Towed generator, 20 kVA", "small_plant", s=0.7)
reg("small.generator_100kva", generator, "Towed generator, 100 kVA", "small_plant", s=1.3)
reg("small.generator_200kva", generator, "Towed generator, 200 kVA, twin axle", "small_plant", s=1.7)

reg("traffic.signal", traffic_light, "Portable traffic signal", "traffic")
reg("traffic.cone", cone, "Traffic cone, 500 mm", "traffic")
reg("traffic.cone_large", cone, "Traffic cone, 750 mm", "traffic", h=0.75)
reg("traffic.cone_1m", cone, "Traffic cone, 1 m", "traffic", h=1.0)
reg("traffic.cone_lamp", cone, "Traffic cone with road lamp", "traffic", h=0.75, lamp=True)

reg("fence.heras", fence_panel, "Mobile mesh fence panel", "temporary", "fence")
reg("fence.heras_run", fence_panel, "Mobile mesh fence, five panels", "temporary", "fence", n=5)
reg("fence.concrete_barrier", jersey, "Concrete jersey barrier, 3 m", "temporary", "barrier")
for _l in (1.0, 1.5, 2.0, 4.0, 6.0):
	reg("fence.concrete_barrier_%s" % str(_l).replace(".0", "").replace(".", "_"), jersey, "Concrete jersey barrier, %g m" % _l, "temporary", "barrier", l=_l)
reg("fence.concrete_barrier_tall", jersey, "Concrete jersey barrier, 1.1 m high", "temporary", "barrier", h=1.1)
reg("fence.concrete_barrier_tall_6", jersey, "Concrete jersey barrier, 1.1 m high, 6 m", "temporary", "barrier", l=6.0, h=1.1)

reg("store.pallet", pallet, "Timber pallet, 1200 x 1000", "stored")
reg("store.pallet_euro", pallet, "Euro pallet, 1200 x 800", "stored", d=0.8)
reg("store.pallet_stringer", pallet, "Stringer pallet", "stored", w=1.22, d=1.02, style="stringer")
reg("store.pallet_plastic", pallet, "Plastic pallet", "stored", style="plastic")
reg("store.pallets", pallet, "Stack of pallets", "stored", stack=7)
reg("store.pallet_loaded", pallet, "Loaded pallet, wrapped cartons", "stored", load="boxes")
reg("store.barrel", barrel, "Steel drum, 205 l", "stored")
reg("store.barrel_red", barrel, "Steel drum, red", "stored", slot="hazard_red")
reg("store.barrels", pallet, "Four drums on a pallet", "stored", load="barrels")
reg("store.ibc_1000", ibc, "IBC water tank, 1000 l", "stored")
reg("store.ibc_600", ibc, "IBC water tank, 600 l", "stored", w=0.8, h=1.0)
reg("store.ibc_1250", ibc, "IBC water tank, 330 gal", "stored", h=1.35)
reg("store.ibc_stack", ibc, "IBC water tanks, two high", "stored", stack=2)
reg("store.cable_drum", cable_drum, "Cable drum, 1.2 m", "stored")
reg("store.cable_drum_large", cable_drum, "Cable drum, 2 m", "stored", d=2.0, w=1.1)
reg("store.cable_drum_orange", cable_drum, "Duct drum, 1.6 m", "stored", d=1.6, w=0.9, cable="hivis_orange")
reg("store.hollowcore", hollowcore, "Hollowcore planks, 6 m", "stored", "precast")
reg("store.hollowcore_short", hollowcore, "Hollowcore planks, 4 m", "stored", "precast", l=4.0, n=5)
reg("store.hollowcore_long", hollowcore, "Hollowcore planks, 9 m, 300 deep", "stored", "precast", l=9.0, n=3, t=0.3)
reg("store.steel", beam_stack, "Steel beams, 6 m", "stored", per=4)
reg("store.steel_long", beam_stack, "Steel beams, 12 m", "stored", l=12.0, rows=2, per=4)
reg("store.timber", beam_stack, "Timber baulks, 4.8 m", "stored", l=4.8, what="timber", rows=2, per=4)
reg("store.timber_long", beam_stack, "Timber baulks, 7.2 m", "stored", l=7.2, what="timber", rows=3, per=3)
reg("store.concrete_pipes", pipe_stack, "Concrete pipes, 600 mm", "stored", "drainage")
reg("store.concrete_pipes_large", pipe_stack, "Concrete pipes, 1200 mm", "stored", "drainage", r=0.7, base=2, wall=0.09)
reg("store.clay_pipes", pipe_stack, "Clay drain pipes", "stored", "drainage", l=1.75, r=0.11, base=5, slot="clay_tile", wall=0.015, collar=True)
reg("store.pipes", pipe_stack, "Plastic duct pipes, 6 m", "stored", "drainage", l=6.0, r=0.08, base=5, slot="hivis_orange", wall=0.008)

reg("skip.builders", skip, "Builders skip, 8 yd", "waste")
reg("skip.builders_full", skip, "Builders skip, full of rubble", "waste", full="rubble")
reg("skip.builders_soil", skip, "Builders skip, full of soil", "waste", full="soil")
for _n, _w, _l, _h in (("mini_2yd", 1.2, 1.5, 0.9), ("midi_4yd", 1.3, 1.9, 1.0), ("6yd", 1.5, 2.6, 1.2), ("12yd", 1.8, 3.7, 1.7), ("14yd", 1.8, 4.0, 1.85), ("18yd", 1.9, 4.4, 2.1)):
	reg("skip." + _n, skip, "Skip, " + _n.replace("_", " ").replace("yd", " yd").replace("  ", " "), "waste", w=_w, l=_l, h=_h)
