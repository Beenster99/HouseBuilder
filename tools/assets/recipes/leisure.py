"""Sports, leisure, shops, restaurants and hotels. Origin: floor centre, back to -Y."""
import math

import kit
from recipes.fixtures import chair, legs, table
from recipes.furniture import carcass
from recipes.public import castors, monitor
from registry import register


def reg(id, fn, label, *tags, **params):
	register(id, fn, label, family="fixture", tags=(id.split(".")[0],) + tags, **params)


def gym(what="treadmill"):
	if what == "treadmill":
		kit.rounded_box((0.8, 1.9, 0.18), (0, 0, 0.11), "plastic_black", "deck", radius=0.04)
		kit.box((0.55, 1.5, 0.01), (0, -0.1, 0.205), "rubber", "belt")
		for s in (-1, 1):
			kit.strut((s * 0.36, 0.7, 0.2), (s * 0.36, 0.85, 1.3), 0.06, 0.08, "plastic_grey", "upright")
			kit.rod((s * 0.36, 0.85, 1.15), (s * 0.36, 0.2, 1.05), 0.02, "plastic_black", "handrail")
		kit.rounded_box((0.8, 0.12, 0.35), (0, 0.85, 1.4), "plastic_black", "console", radius=0.03, rot=(-20, 0, 0))
		kit.box((0.4, 0.004, 0.22), (0, 0.78, 1.43), "screen", "display", rot=(-20, 0, 0))
	elif what in ("bike", "cross_trainer", "rower"):
		l = {"bike": 1.1, "cross_trainer": 1.8, "rower": 2.3}[what]
		for y in (-l / 2 + 0.1, l / 2 - 0.1):
			kit.box((0.55, 0.08, 0.06), (0, y, 0.03), "plastic_black", "foot")
		kit.box((0.08, l - 0.2, 0.08), (0, 0, 0.1 if what != "rower" else 0.3), "plastic_grey", "frame")
		kit.cyl(0.25, 0.1, (0, l / 2 - 0.35, 0.4), "plastic_black", "flywheel", axis="x", segs=24)
		if what == "bike":
			kit.rod((0, -0.2, 0.1), (0, -0.25, 0.95), 0.03, "plastic_grey", "seat_post")
			kit.rounded_box((0.2, 0.28, 0.06), (0, -0.25, 0.98), "leather_black", "saddle", radius=0.025)
			kit.rod((0, 0.25, 0.4), (0, 0.3, 1.15), 0.03, "plastic_grey", "stem")
			kit.rod((-0.25, 0.3, 1.15), (0.25, 0.3, 1.15), 0.015, "plastic_black", "bars")
		elif what == "cross_trainer":
			for s in (-1, 1):
				kit.rod((s * 0.3, 0.5, 0.3), (s * 0.3, 0.3, 1.6), 0.02, "plastic_grey", "arm")
				kit.box((0.15, 0.45, 0.04), (s * 0.2, -0.3 + s * 0.15, 0.3), "plastic_black", "pedal")
			kit.rod((0, 0.55, 0.4), (0, 0.6, 1.5), 0.04, "plastic_grey", "mast")
			kit.box((0.3, 0.05, 0.25), (0, 0.58, 1.55), "plastic_black", "console")
		else:
			kit.rounded_box((0.3, 0.3, 0.06), (0, -0.5, 0.37), "leather_black", "seat", radius=0.02)
			kit.box((0.3, 0.02, 0.3), (0, 0.5, 0.45), "plastic_black", "foot_plate", rot=(40, 0, 0))
			kit.rod((-0.2, 0.3, 0.6), (0.2, 0.3, 0.6), 0.015, "plastic_black", "handle")
	elif what in ("bench_press", "squat_rack", "smith"):
		w = 1.2
		for s in (-1, 1):
			kit.box((0.06, 0.06, 2.2 if what != "bench_press" else 1.2), (s * w / 2, -0.3, 1.1 if what != "bench_press" else 0.6), "steel_painted", "upright")
			kit.box((0.06, 1.3, 0.06), (s * w / 2, 0.2, 0.03), "steel_painted", "base")
			if what != "bench_press":
				kit.box((0.06, 0.06, 2.2), (s * w / 2, 0.8, 1.1), "steel_painted", "upright")
				kit.box((0.06, 1.16, 0.06), (s * w / 2, 0.25, 2.17), "steel_painted", "top")
		barz = 1.1 if what == "bench_press" else 1.5
		kit.rod((-1.1, -0.25, barz), (1.1, -0.25, barz), 0.014, "steel_stainless", "bar")
		for s in (-1, 1):
			for i in range(2):
				kit.cyl(0.22, 0.04, (s * (0.75 + i * 0.05), -0.25, barz), "plastic_black", "plate", axis="x", segs=20)
		if what != "squat_rack":
			kit.rounded_box((0.3, 1.2, 0.08), (0, 0.3, 0.45), "leather_black", "bench", radius=0.03)
			legs(0.3, 1.2, 0.41, 0.05, "steel_painted", at=(0, 0.3))
	elif what == "dumbbells":
		for t in range(2):
			kit.box((1.8, 0.4, 0.04), (0, 0.1 * t, 0.4 + t * 0.4), "steel_painted", "shelf", rot=(15, 0, 0))
			for i in range(8):
				x = -0.8 + i * 0.228
				for e in (-1, 1):
					kit.cyl(0.05 + 0.006 * i, 0.06, (x, 0.1 * t + e * 0.09, 0.47 + t * 0.4 + 0.006 * i), "plastic_black", "weight", axis="y", segs=8)
				kit.rod((x, 0.1 * t - 0.09, 0.47 + t * 0.4), (x, 0.1 * t + 0.09, 0.47 + t * 0.4), 0.015, "steel_stainless", "grip", segs=6)
		for s in (-1, 1):
			kit.box((0.05, 0.5, 0.9), (s * 0.9, 0.05, 0.45), "steel_painted", "end")
	elif what == "cable_machine":
		with kit.hollow(0.3):
			kit.box((0.7, 0.4, 2.2), (0, -0.3, 1.1), "steel_painted", "tower")
		kit.box((0.4, 0.2, 0.9), (0, -0.3, 0.6), "plastic_black", "weight_stack")
		kit.rod((0, -0.1, 2.1), (0, 0.5, 2.0), 0.03, "steel_painted", "arm")
		kit.rod((0, 0.5, 2.0), (0, 0.5, 1.5), 0.004, "plastic_black", "cable", segs=4)
		kit.rod((-0.3, 0.5, 1.5), (0.3, 0.5, 1.5), 0.014, "steel_stainless", "bar")
	elif what == "punch_bag":
		kit.rod((0, 0, 2.8), (0, 0, 2.2), 0.006, "steel_galvanised", "chain", segs=5)
		kit.cyl(0.18, 1.2, (0, 0, 1.6), "leather_black", "bag", segs=16)
	elif what == "mat_stack":
		for i in range(6):
			kit.rounded_box((0.62, 1.8, 0.015), (0, 0, 0.01 + i * 0.016), ("plastic_blue", "plastic_green")[i % 2], "mat", radius=0.005)
	elif what == "boxing_ring":
		kit.box((6.0, 6.0, 0.9), (0, 0, 0.45), "fabric_blue", "platform")
		kit.box((5.9, 5.9, 0.02), (0, 0, 0.91), "fabric_white", "canvas")
		for sx in (-1, 1):
			for sy in (-1, 1):
				kit.cyl(0.06, 1.4, (sx * 2.7, sy * 2.7, 1.6), "hazard_red" if sx * sy > 0 else "plastic_blue", "post", segs=10)
		for z in (1.3, 1.6, 1.9, 2.2):
			kit.sweep([(-2.7, -2.7, z), (2.7, -2.7, z), (2.7, 2.7, z), (-2.7, 2.7, z), (-2.7, -2.7, z)], kit.circle(0.015, 6), "fabric_white", "rope")


def pitch(what="tennis_net"):
	if what == "tennis_net":
		for s in (-1, 1):
			kit.cyl(0.04, 1.07, (s * 6.4, 0, 0.535), "plastic_green", "post", segs=10)
		kit.grid_bars(12.8, 0.9, (0, 0, 0.55), 64, 6, 0.002, "plastic_black", "net")
		kit.box((12.8, 0.01, 0.05), (0, 0, 1.02), "fabric_white", "band")
	elif what == "rugby_posts":
		for s in (-1, 1):
			kit.cyl(0.07, 11.0, (s * 2.8, 0, 5.5), "paint_white", "post", segs=10)
			kit.cyl(0.18, 1.8, (s * 2.8, 0, 0.9), "plastic_blue", "pad", segs=12)
		kit.rod((-2.8, 0, 3.0), (2.8, 0, 3.0), 0.05, "paint_white", "crossbar")
	elif what == "cricket":
		for y in (-10.06, 10.06):
			for x in (-0.11, 0, 0.11):
				kit.cyl(0.018, 0.71, (x, y, 0.355), "softwood", "stump", segs=8)
		kit.box((3.05, 20.12, 0.01), (0, 0, 0.005), "render", "wicket")
	elif what == "sight_screen":
		kit.box((4.5, 0.05, 3.6), (0, 0, 2.2), "paint_white", "screen")
		for s in (-1, 1):
			kit.box((0.1, 1.5, 0.1), (s * 2.0, 0, 0.35), "softwood", "skid")
			kit.wheel(0.2, 0.08, (s * 2.0, 0.5, 0.2))
	elif what == "dugout":
		with kit.hollow(0.05):
			kit.sweep([(0, -0.9, 0), (0, -0.9, 1.6), (0, -0.4, 2.1), (0, 0.6, 2.2)], [(-2.5, 0), (2.5, 0), (2.5, 0.03), (-2.5, 0.03)], "glass", "shell")
		for s in (-1, 1):
			kit.box((0.03, 1.5, 2.1), (s * 2.5, -0.15, 1.05), "glass", "end")
		kit.box((4.6, 0.35, 0.05), (0, -0.5, 0.45), "plastic_blue", "bench")
	elif what == "scoreboard":
		for s in (-1, 1):
			kit.box((0.2, 0.2, 6.0), (s * 2.5, 0, 3.0), "steel_galvanised", "leg")
		kit.box((7.0, 0.4, 3.5), (0, 0, 6.0), "plastic_black", "board")
		kit.box((6.6, 0.01, 3.1), (0, 0.205, 6.0), "screen", "display")
	elif what == "corner_flag":
		kit.cyl(0.012, 1.5, (0, 0, 0.75), "plastic_yellow", "pole", segs=8)
		kit.prism([(0, 1.5), (0.4, 1.35), (0, 1.2)], 0.004, (0, 0, 0), "hazard_red", "flag", axis="y")
	elif what == "floodlight":
		kit.cyl(0.3, 18.0, (0, 0, 9.0), "steel_galvanised", "mast", segs=12, r2=0.12)
		for i in range(4):
			for j in range(2):
				kit.box((0.5, 0.2, 0.4), (-0.9 + i * 0.6, 0.15, 17.6 + j * 0.5), "aluminium", "lamp", rot=(25, 0, 0))
				kit.box((0.44, 0.01, 0.34), (-0.9 + i * 0.6, 0.24, 17.55 + j * 0.5), "light_emitter", "lens", rot=(25, 0, 0))
	elif what == "running_hurdle":
		for s in (-1, 1):
			kit.sweep([(s * 0.55, 0.6, 0.02), (s * 0.55, 0, 0.02), (s * 0.55, 0, 0.9)], kit.rect(0.03, 0.03), "aluminium", "frame", up=(1, 0, 0))
		kit.box((1.2, 0.02, 0.07), (0, 0, 0.88), "paint_white", "bar")
	elif what == "lifeguard_chair":
		for s in (-1, 1):
			kit.strut((s * 0.4, 0.5, 0), (s * 0.3, 0, 1.8), 0.05, 0.05, "paint_white", "leg")
			kit.strut((s * 0.4, -0.5, 0), (s * 0.3, 0, 1.8), 0.05, 0.05, "paint_white", "leg")
		kit.rounded_box((0.6, 0.5, 0.06), (0, 0, 1.83), "plastic_white", "seat", radius=0.02)
		kit.box((0.6, 0.05, 0.5), (0, -0.25, 2.1), "plastic_white", "back")
		for i in range(5):
			kit.rod((-0.38 + 0.02 * i, 0.5 - i * 0.1, 0.3 + i * 0.3), (0.38 - 0.02 * i, 0.5 - i * 0.1, 0.3 + i * 0.3), 0.015, "paint_white", "rung")
	elif what == "diving_board":
		kit.box((0.6, 1.2, 1.0), (0, -1.5, 0.5), "concrete", "plinth")
		kit.box((0.5, 4.0, 0.05), (0, 0, 1.03), "plastic_blue", "board")
		for s in (-1, 1):
			kit.sweep([(s * 0.3, -2.1, 1.0), (s * 0.3, -2.1, 1.9), (s * 0.3, -0.9, 1.9), (s * 0.3, -0.9, 1.0)], kit.circle(0.02, 8), "steel_stainless", "rail", up=(1, 0, 0))
	elif what == "pool_ladder":
		for s in (-1, 1):
			kit.sweep([(s * 0.25, 0.5, 0), (s * 0.25, 0.5, 0.8), (s * 0.25, 0.1, 0.9), (s * 0.25, -0.1, 0.6), (s * 0.25, -0.1, -1.0)], kit.circle(0.02, 8), "steel_stainless", "rail", up=(1, 0, 0))
		for i in range(3):
			kit.box((0.5, 0.08, 0.02), (0, -0.1, -0.25 - i * 0.28), "steel_stainless", "tread")
	elif what == "lane_rope":
		for i in range(10):
			kit.cyl(0.055, 0.09, (0, -0.45 + i * 0.1, 0), ("hazard_red", "paint_white", "plastic_blue")[i % 3], "float", axis="y", segs=10)
	elif what == "starting_block":
		kit.box((0.5, 0.5, 0.4), (0, 0, 0.2), "steel_stainless", "pedestal")
		kit.box((0.5, 0.7, 0.05), (0, 0.05, 0.43), "plastic_blue", "platform", rot=(-8, 0, 0))
	elif what == "table_tennis":
		kit.box((1.525, 2.74, 0.025), (0, 0, 0.75), "plastic_blue", "top")
		kit.box((1.83, 0.01, 0.15), (0, 0, 0.84), "plastic_black", "net")
		for y in (-0.9, 0.9):
			kit.frame(1.2, 0.74, 0.04, 0.04, at=(0, y, 0), slot="steel_painted", name="legs", bottom=False)
	elif what == "pool_table":
		with kit.hollow(0.4):
			kit.box((1.5, 2.7, 0.25), (0, 0, 0.72), "hardwood", "body")
		kit.box((1.3, 2.5, 0.01), (0, 0, 0.85), "fabric_green", "cloth")
		legs(1.5, 2.7, 0.6, 0.12, "hardwood", inset=0.1)
	elif what == "stand":
		with kit.hollow(0.1):
			for i in range(6):
				kit.box((10.0, 0.8, 0.45 * (i + 1)), (0, -i * 0.8, 0.225 * (i + 1)), "concrete", "tier")
		for i in range(6):
			for j in range(18):
				kit.rounded_box((0.45, 0.4, 0.06), (-4.6 + j * 0.54, -i * 0.8 - 0.1, 0.45 * (i + 1) + 0.25), "plastic_blue" if (i + j) % 5 else "plastic_red", "seat", radius=0.02)
		for s in (-1, 1):
			kit.box((0.2, 0.2, 6.5), (s * 4.5, -4.6, 3.25), "steel_painted", "column")
			kit.strut((s * 4.5, -4.6, 6.4), (s * 4.5, 1.5, 5.6), 0.2, 0.4, "steel_painted", "cantilever")
		kit.box((10.4, 6.4, 0.06), (0, -1.5, 6.25), "steel_galvanised", "roof", rot=(7.5, 0, 0))


def retail(what="checkout"):
	if what == "checkout":
		with kit.hollow(0.2):
			kit.box((0.9, 2.6, 0.85), (0, 0, 0.425), "laminate_grey", "counter")
		kit.box((0.5, 1.4, 0.02), (0.1, -0.5, 0.86), "rubber", "belt")
		kit.box((0.3, 0.3, 0.08), (0.1, 0.5, 0.89), "glass", "scanner")
		kit.box((0.35, 0.35, 0.1), (-0.3, 0.9, 0.95), "plastic_black", "till")
		kit.box((0.3, 0.03, 0.22), (-0.3, 0.9, 1.15), "screen", "till_screen")
		kit.rod((-0.4, -1.2, 0.85), (-0.4, -1.2, 2.0), 0.02, "aluminium", "lane_post")
		kit.box((0.25, 0.25, 0.25), (-0.4, -1.2, 2.1), "light_emitter", "lane_light")
	elif what == "self_checkout":
		kit.rounded_box((0.6, 0.5, 0.9), (0, 0, 0.45), "plastic_grey", "base", radius=0.03)
		kit.box((0.4, 0.05, 0.32), (0, -0.1, 1.2), "plastic_black", "screen_case", rot=(-15, 0, 0))
		kit.box((0.36, 0.004, 0.28), (0, -0.072, 1.205), "screen", "screen", rot=(-15, 0, 0))
		kit.box((0.6, 0.5, 0.03), (0.65, 0, 0.6), "steel_stainless", "bagging_shelf")
		kit.box((0.05, 0.05, 0.6), (0.65, 0, 0.3), "steel_stainless", "shelf_post")
	elif what in ("chiller", "freezer"):
		w = 2.5
		with kit.hollow(0.15):
			kit.box((w, 0.9, 0.4), (0, 0, 0.2), "paint_white", "plinth")
			kit.box((w, 0.12, 2.0), (0, -0.39, 1.0), "paint_white", "back")
			kit.box((w, 0.9, 0.2), (0, 0, 2.0), "paint_white", "canopy")
			for s in (-1, 1):
				kit.box((0.05, 0.9, 2.0), (s * (w / 2 - 0.025), 0, 1.0), "paint_white", "end")
		for i in range(4):
			kit.box((w - 0.1, 0.5, 0.02), (0, -0.1, 0.5 + i * 0.36), "steel_stainless", "shelf")
			for j in range(8):
				kit.box((0.22, 0.3, 0.2), (-w / 2 + 0.2 + j * 0.3, -0.1, 0.62 + i * 0.36), ("plastic_red", "plastic_white", "plastic_green", "plastic_yellow")[(i + j) % 4], "stock")
		if what == "freezer":
			for i in range(3):
				kit.box((w / 3 - 0.04, 0.02, 1.5), (-w / 3 + i * w / 3, 0.43, 1.15), "glass", "door")
	elif what == "chest_freezer":
		with kit.hollow(0.2):
			kit.box((2.0, 0.9, 0.85), (0, 0, 0.425), "paint_white", "body")
		kit.box((1.9, 0.8, 0.01), (0, 0, 0.86), "glass", "lid")
	elif what == "trolley":
		with kit.hollow(0.02):
			kit.prism([(-0.4, 0.5), (0.45, 0.45), (0.5, 1.0), (-0.45, 1.0)], 0.55, (0, 0, 0), "steel_galvanised", "basket", axis="x")
		kit.box((0.5, 0.9, 0.03), (0, 0, 0.2), "steel_galvanised", "chassis")
		castors(0.5, 0.9, 0.06)
		kit.rod((-0.28, -0.5, 1.02), (0.28, -0.5, 1.02), 0.015, "plastic_red", "handle")
	elif what == "basket_stack":
		for i in range(8):
			with kit.hollow(0.05):
				kit.box((0.45, 0.3, 0.06), (0, 0, 0.1 + i * 0.05), "plastic_red", "basket")
	elif what == "clothes_rail":
		for s in (-1, 1):
			kit.rod((s * 0.7, 0, 0.05), (s * 0.7, 0, 1.6), 0.015, "steel_stainless", "post")
			kit.box((0.04, 0.5, 0.03), (s * 0.7, 0, 0.04), "steel_stainless", "foot")
		kit.rod((-0.7, 0, 1.6), (0.7, 0, 1.6), 0.015, "steel_stainless", "rail")
		for i in range(10):
			kit.rounded_box((0.04, 0.45, 0.8), (-0.6 + i * 0.13, 0, 1.15), ("fabric_red", "fabric_blue", "fabric_grey", "fabric_green", "fabric_white")[i % 5], "garment", radius=0.015)
	elif what == "mannequin":
		from recipes.outdoors import person
		person(pose="stand", top="fabric_white", legs="fabric_white", skin="fabric_white", hat="")
		kit.cyl(0.2, 0.02, (0, 0, 0.01), "steel_stainless", "base", segs=18)
	elif what == "fitting_room":
		with kit.hollow(0.2):
			for s in (-1, 1):
				kit.box((0.04, 1.2, 2.1), (s * 0.6, 0, 1.05), "laminate_white", "side")
			kit.box((1.2, 0.04, 2.1), (0, -0.6, 1.05), "laminate_white", "back")
		kit.box((0.5, 0.01, 1.5), (0, -0.575, 1.1), "mirror", "mirror")
		kit.rod((-0.6, 0.6, 2.0), (0.6, 0.6, 2.0), 0.012, "steel_stainless", "curtain_rail")
		kit.box((0.6, 0.02, 1.8), (-0.25, 0.6, 1.08), "fabric_grey", "curtain")
		kit.box((0.4, 0.3, 0.04), (0.38, -0.4, 0.45), "hardwood", "seat")
	elif what == "display_table":
		table(1.6, 0.9, 0.8, "hardwood", "hardwood")
		for i in range(6):
			kit.box((0.3, 0.25, 0.08), (-0.55 + (i % 3) * 0.55, -0.2 + (i // 3) * 0.4, 0.84), ("fabric_blue", "fabric_grey", "fabric_red")[i % 3], "stock")
	elif what == "jewellery_case":
		carcass(1.2, 0.5, 0.75, "hardwood", doors=2, plinth=0.08)
		kit.box((1.2, 0.5, 0.25), (0, 0, 0.875), "glass", "case")
	elif what == "atm":
		kit.rounded_box((0.5, 0.6, 1.4), (0, 0, 0.7), "plastic_grey", "body", radius=0.03)
		kit.box((0.3, 0.004, 0.22), (0, 0.302, 1.15), "screen", "screen")
		kit.box((0.25, 0.1, 0.02), (0, 0.33, 0.95), "steel_stainless", "keypad", rot=(20, 0, 0))
	elif what == "parcel_locker":
		with kit.hollow(0.1):
			kit.box((2.0, 0.6, 2.0), (0, 0, 1.0), "plastic_yellow", "body")
		for i in range(5):
			for j in range(5):
				if not (i == 2 and j == 2):
					kit.box((0.38, 0.01, 0.38), (-0.8 + i * 0.4, 0.305, 0.2 + j * 0.4), "plastic_grey", "door")
		kit.box((0.3, 0.004, 0.2), (0, 0.302, 1.05), "screen", "screen")
	elif what == "market_stall":
		table(2.4, 1.0, 0.8, "plywood", "steel_galvanised")
		for sx in (-1, 1):
			for sy in (-1, 1):
				kit.rod((sx * 1.3, sy * 0.9, 0), (sx * 1.3, sy * 0.9, 2.1), 0.02, "steel_galvanised", "pole")
		kit.prism([(-1.4, 0), (1.4, 0), (0, 0.6)], 2.0, (0, 0, 2.1), "fabric_red", "canopy", axis="y")
	elif what == "kiosk":
		with kit.hollow(0.08):
			kit.box((3.0, 2.4, 2.6), (0, 0, 1.3), "plastic_green", "body")
		kit.box((2.2, 0.03, 1.1), (0, 1.2, 1.65), "glass", "hatch")
		kit.box((2.4, 0.4, 0.04), (0, 1.35, 1.08), "steel_stainless", "counter")
		kit.box((3.2, 1.2, 0.05), (0, 1.7, 2.65), "plastic_green", "awning", rot=(-8, 0, 0))


def food(what="table_2"):
	if what.startswith("table_"):
		n = int(what.split("_")[1])
		w = {2: 0.7, 4: 1.2, 6: 1.8}[n]
		with kit.stage("table"):
			kit.box((w, 0.75, 0.03), (0, 0, 0.74), "hardwood", "top")
			for x in ((0,) if n == 2 else (-w / 2 + 0.35, w / 2 - 0.35)):
				kit.cyl(0.035, 0.7, (x, 0, 0.37), "cast_iron", "pedestal", segs=10)
				kit.cyl(0.22, 0.03, (x, 0, 0.015), "cast_iron", "foot", segs=16)
		with kit.stage("chairs"):
			per = n // 2
			for i in range(per):
				x = -w / 2 + w * (i + 0.5) / per
				chair((x, 0.6), 180, "leather_black", "hardwood")
				chair((x, -0.6), 0, "leather_black", "hardwood")
	elif what == "round_table":
		with kit.stage("table"):
			kit.cyl(0.9, 0.03, (0, 0, 0.74), "fabric_white", "top", segs=28)
			kit.cyl(0.05, 0.7, (0, 0, 0.37), "steel_painted", "pedestal", segs=10)
			kit.cyl(0.35, 0.03, (0, 0, 0.015), "steel_painted", "foot", segs=16)
		with kit.stage("chairs"):
			for i in range(8):
				a = math.radians(45 * i)
				chair((1.2 * math.cos(a), 1.2 * math.sin(a)), 45 * i + 90, "fabric_red", "brass")
	elif what == "booth":
		for s in (-1, 1):
			with kit.hollow(0.4):
				kit.rounded_box((1.3, 0.15, 1.1), (0, s * 0.95, 0.55), "leather_black", "back", radius=0.04)
			kit.rounded_box((1.3, 0.5, 0.45), (0, s * 0.65, 0.225), "leather_black", "seat", radius=0.05)
		kit.box((1.2, 0.7, 0.03), (0, 0, 0.74), "hardwood", "top")
		kit.cyl(0.04, 0.72, (0, 0, 0.36), "cast_iron", "pedestal", segs=10)
	elif what == "bar":
		with kit.hollow(0.2):
			kit.box((4.0, 0.6, 1.05), (0, 0, 0.525), "hardwood", "front")
		kit.box((4.2, 0.75, 0.05), (0, 0.05, 1.075), "hardwood", "top")
		kit.rod((-1.9, 0.38, 0.2), (1.9, 0.38, 0.2), 0.02, "brass", "foot_rail")
		for i in range(4):
			kit.cyl(0.02, 0.3, (-0.6 + i * 0.4, -0.1, 1.25), "brass", "beer_tap", segs=8)
		with kit.hollow(0.2):
			kit.box((4.0, 0.4, 2.2), (0, -1.2, 1.1), "hardwood", "back_bar")
		kit.box((3.6, 0.02, 0.9), (0, -0.99, 1.6), "mirror", "mirror")
		for i in range(14):
			kit.cyl(0.04, 0.28, (-1.6 + i * 0.25, -1.05, 1.3), ("glass", "plastic_green", "brass")[i % 3], "bottle", segs=8)
	elif what == "bar_stool":
		kit.cyl(0.2, 0.02, (0, 0, 0.01), "steel_stainless", "base", segs=18)
		kit.cyl(0.025, 0.72, (0, 0, 0.38), "steel_stainless", "post", segs=10)
		kit.cyl(0.18, 0.07, (0, 0, 0.77), "leather_black", "seat", segs=18)
		kit.tube(0.16, 0.012, (0, 0, 0.3), "steel_stainless", "foot_ring", wall=0.012, segs=18)
	elif what == "high_table":
		kit.cyl(0.35, 0.03, (0, 0, 1.08), "hardwood", "top", segs=22)
		kit.cyl(0.035, 1.05, (0, 0, 0.54), "steel_stainless", "post", segs=10)
		kit.cyl(0.25, 0.02, (0, 0, 0.01), "steel_stainless", "base", segs=18)
	elif what in ("range", "fryer", "griddle", "combi_oven", "dishwasher", "prep_table", "sink_unit", "pass", "walk_in", "extract_hood"):
		if what == "walk_in":
			with kit.hollow(0.1):
				kit.box((2.4, 2.4, 2.3), (0, 0, 1.15), "steel_stainless", "cold_room")
			kit.box((0.9, 0.08, 1.9), (0.4, 1.2, 0.97), "steel_stainless", "door")
			kit.rod((0.1, 1.27, 0.9), (0.1, 1.27, 1.2), 0.015, "plastic_black", "handle")
			kit.box((0.8, 0.5, 0.35), (-0.5, 0, 2.48), "steel_galvanised", "condenser")
			return
		if what == "extract_hood":
			with kit.hollow(0.05):
				kit.prism([(-0.6, 2.0), (0.6, 2.0), (0.45, 2.5), (-0.6, 2.5)], 3.0, (0, 0, 0), "steel_stainless", "canopy", axis="x")
			for i in range(5):
				kit.box((0.5, 0.02, 0.4), (-1.2 + i * 0.6, -0.3, 2.2), "steel_galvanised", "filter", rot=(40, 0, 0))
			kit.box((0.5, 0.4, 0.5), (0, -0.2, 2.75), "steel_galvanised", "duct")
			return
		w = 0.9 if what not in ("prep_table", "pass", "sink_unit") else 1.8
		with kit.hollow(0.2):
			if what in ("prep_table", "sink_unit", "pass"):
				kit.box((w, 0.7, 0.04), (0, 0, 0.88), "steel_stainless", "top")
				legs(w, 0.7, 0.86, 0.04, "steel_stainless")
				kit.box((w - 0.1, 0.6, 0.02), (0, 0, 0.2), "steel_stainless", "undershelf")
			else:
				kit.box((w, 0.8, 0.9 if what != "combi_oven" else 1.8), (0, 0, 0.45 if what != "combi_oven" else 0.9), "steel_stainless", "body")
		if what == "range":
			for x in (-0.22, 0.22):
				for y in (-0.18, 0.18):
					kit.cyl(0.1, 0.03, (x, y, 0.915), "cast_iron", "burner", segs=12)
			kit.box((0.8, 0.02, 0.5), (0, 0.41, 0.4), "steel_stainless", "oven_door")
			kit.rod((-0.35, 0.44, 0.62), (0.35, 0.44, 0.62), 0.012, "steel_stainless", "handle")
		elif what == "fryer":
			for x in (-0.22, 0.22):
				kit.box((0.36, 0.5, 0.02), (x, 0, 0.9), "plastic_yellow", "oil")
				kit.grid_bars(0.3, 0.3, (x, 0, 0.93), 6, 6, 0.003, "steel_stainless", "basket", plane="xy")
		elif what == "griddle":
			kit.box((0.8, 0.6, 0.03), (0, 0, 0.915), "cast_iron", "plate")
		elif what == "combi_oven":
			kit.box((0.6, 0.02, 1.2), (-0.1, 0.41, 1.0), "glass", "door")
			kit.box((0.18, 0.01, 1.2), (0.34, 0.405, 1.0), "plastic_black", "controls")
		elif what == "dishwasher":
			kit.box((0.7, 0.7, 0.6), (0, 0, 1.3), "steel_stainless", "hood")
			kit.rod((-0.3, 0.37, 1.2), (0.3, 0.37, 1.2), 0.012, "steel_stainless", "handle")
		elif what == "sink_unit":
			for x in (-0.45, 0.45):
				kit.box((0.6, 0.5, 0.01), (x, 0, 0.902), "steel_galvanised", "bowl")
				kit.sweep([(x, -0.3, 0.9), (x, -0.3, 1.25), (x, -0.1, 1.25)], kit.circle(0.012, 8), "steel_stainless", "tap", up=(1, 0, 0))
		elif what == "pass":
			for s in (-1, 1):
				kit.rod((s * 0.85, -0.2, 0.9), (s * 0.85, -0.2, 1.4), 0.015, "steel_stainless", "post")
			kit.box((1.8, 0.35, 0.03), (0, -0.2, 1.4), "steel_stainless", "shelf")
			kit.box((1.6, 0.1, 0.04), (0, -0.2, 1.36), "light_emitter", "heat_lamp")
	elif what == "hotel_bed":
		kit.rounded_box((1.8, 2.0, 0.3), (0, 0, 0.2), "fabric_grey", "base", radius=0.03)
		kit.rounded_box((1.8, 2.0, 0.25), (0, 0, 0.47), "fabric_white", "mattress", radius=0.06)
		kit.box((2.2, 0.08, 1.2), (0, -1.04, 0.6), "leather_black", "headboard")
		for s in (-1, 1):
			kit.rounded_box((0.7, 0.45, 0.12), (s * 0.42, -0.72, 0.64), "fabric_white", "pillow", radius=0.05)
			kit.box((0.45, 0.4, 0.5), (s * 1.2, -0.8, 0.25), "hardwood", "bedside")
			kit.cyl(0.1, 0.2, (s * 1.2, -0.8, 0.75), "fabric_white", "lamp", segs=12)
		kit.box((1.82, 0.6, 0.02), (0, 0.6, 0.6), "fabric_red", "runner")
	elif what == "luggage_rack":
		for s in (-1, 1):
			kit.strut((s * 0.3, -0.25, 0), (s * 0.3, 0.25, 0.5), 0.03, 0.03, "hardwood", "leg")
			kit.strut((s * 0.3, 0.25, 0), (s * 0.3, -0.25, 0.5), 0.03, 0.03, "hardwood", "leg")
		for i in range(4):
			kit.box((0.05, 0.5, 0.005), (-0.24 + i * 0.16, 0, 0.5), "fabric_grey", "strap")
	elif what == "minibar":
		carcass(0.5, 0.5, 0.6, "plastic_black", doors=1, plinth=0.0)
	elif what == "housekeeping_cart":
		carcass(0.9, 0.5, 1.1, "plastic_grey", shelves=2, plinth=0.15, open_front=True)
		castors(0.9, 0.5, 0.05)
		with kit.hollow(0.05):
			kit.box((0.4, 0.45, 0.8), (0.67, 0, 0.6), "fabric_blue", "linen_bag")
	elif what == "cinema_seats":
		for i in range(5):
			x = (i - 2) * 0.6
			kit.rounded_box((0.5, 0.5, 0.12), (x, 0.05, 0.42), "fabric_red", "seat", radius=0.04)
			kit.rounded_box((0.5, 0.12, 0.7), (x, -0.25, 0.75), "fabric_red", "back", radius=0.04, rot=(-10, 0, 0))
		for i in range(6):
			kit.box((0.08, 0.5, 0.6), ((i - 2.5) * 0.6, 0, 0.3), "plastic_black", "arm")
	elif what == "piano_grand":
		kit.prism([(-0.75, -1.0), (0.75, -1.0), (0.75, 0.2), (0.3, 1.0), (-0.4, 1.2), (-0.75, 0.8)], 0.3, (0, 0, 0.85), "plastic_black", "case", axis="z")
		kit.box((1.3, 0.15, 0.03), (0, -1.05, 0.75), "fabric_white", "keys")
		for x, y in ((-0.6, -0.8), (0.6, -0.8), (-0.1, 0.9)):
			kit.cyl(0.045, 0.7, (x, y, 0.35), "plastic_black", "leg", segs=10)


_GYM = (("treadmill", "Treadmill"), ("bike", "Exercise bike"), ("cross_trainer", "Cross trainer"), ("rower", "Rowing machine"), ("bench_press", "Bench press"), ("squat_rack", "Squat rack"), ("smith", "Smith machine with bench"),
	("dumbbells", "Dumbbell rack"), ("cable_machine", "Cable machine"), ("punch_bag", "Punch bag"), ("mat_stack", "Exercise mats"), ("boxing_ring", "Boxing ring"))
_PITCH = (("tennis_net", "Tennis net and posts"), ("rugby_posts", "Rugby posts"), ("cricket", "Cricket wicket and stumps"), ("sight_screen", "Cricket sight screen"), ("dugout", "Team shelter"), ("scoreboard", "Scoreboard"),
	("corner_flag", "Corner flag"), ("floodlight", "Sports floodlight mast, 18 m"), ("running_hurdle", "Hurdle"), ("lifeguard_chair", "Lifeguard chair"), ("diving_board", "Diving board"), ("pool_ladder", "Pool ladder"),
	("starting_block", "Starting block"), ("table_tennis", "Table tennis table"), ("pool_table", "Pool table"), ("stand", "Covered spectator stand, 10 m"))
_RETAIL = (("checkout", "Supermarket checkout"), ("self_checkout", "Self checkout"), ("chiller", "Chiller cabinet, open"), ("freezer", "Freezer cabinet with doors"), ("chest_freezer", "Chest freezer"), ("trolley", "Shopping trolley"),
	("basket_stack", "Basket stack"), ("clothes_rail", "Clothes rail"), ("mannequin", "Mannequin"), ("fitting_room", "Fitting room"), ("display_table", "Display table"), ("jewellery_case", "Glass display counter"),
	("atm", "Cash machine"), ("parcel_locker", "Parcel locker"), ("market_stall", "Market stall"), ("kiosk", "Refreshment kiosk"))
_FOOD = (("table_2", "Restaurant table for two"), ("table_4", "Restaurant table for four"), ("table_6", "Restaurant table for six"), ("round_table", "Banquet table for eight"), ("booth", "Booth seating"), ("bar", "Bar with back bar"),
	("bar_stool", "Bar stool"), ("high_table", "Poseur table"))
_KITCHEN = (("range", "Six burner range"), ("fryer", "Twin fryer"), ("griddle", "Griddle"), ("combi_oven", "Combi oven"), ("dishwasher", "Pass-through dishwasher"), ("prep_table", "Stainless prep table"),
	("sink_unit", "Double pot wash sink"), ("pass", "Heated pass"), ("walk_in", "Walk-in cold room"), ("extract_hood", "Kitchen extract canopy"))
_HOTEL = (("hotel_bed", "Hotel bed with bedsides"), ("luggage_rack", "Luggage rack"), ("minibar", "Minibar"), ("housekeeping_cart", "Housekeeping cart"), ("cinema_seats", "Cinema seats, row of five"), ("piano_grand", "Grand piano"))
for _w, _l in _GYM:
	reg("sport.gym." + _w, gym, _l, "school", what=_w)
for _w, _l in _PITCH:
	reg("sport.pitch." + _w, pitch, _l, "school", "outdoor", what=_w)
register("sport.pitch.lane_rope", pitch, "Pool lane rope, per metre", family="fixture", tags=("sport",), stretch="z", what="lane_rope")
for _w, _l in _RETAIL:
	reg("retail.shop." + _w, retail, _l, "airport", what=_w)
for _w, _l in _FOOD:
	reg("hospitality.dining." + _w, food, _l, "airport", "school", what=_w)
for _w, _l in _KITCHEN:
	reg("hospitality.kitchen." + _w, food, _l, "school", "hospital", what=_w)
for _w, _l in _HOTEL:
	reg("hospitality.room." + _w, food, _l, what=_w)
