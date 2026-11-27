"""Surroundings (planting, boundaries, street furniture, neighbouring buildings), demolition
debris and people. Origin: ground centre; boundaries run along X and face +Y."""
import math
import random

import kit
from registry import register


def reg(id, fn, label, *tags, **params):
	register(id, fn, label, family=id.split(".")[0], tags=(id.split(".")[0], "outdoor") + tags, **params)


# --- planting ------------------------------------------------------------------------------

def tree(h=8.0, style="broadleaf", seed=1, foliage="foliage"):
	rng = random.Random(seed)
	tr = h * 0.035 + 0.03
	if style == "conifer":
		kit.cyl(tr, h * 0.25, (0, 0, h * 0.125), "bark", "trunk", segs=8)
		for i in range(5):
			z0 = h * (0.15 + i * 0.17)
			kit.cyl(h * 0.22 * (1 - i * 0.17), h * 0.26, (0, 0, z0 + h * 0.13), "foliage_dark", "tier", segs=10, r2=h * 0.02)
		return
	if style == "columnar":
		kit.cyl(tr, h * 0.2, (0, 0, h * 0.1), "bark", "trunk", segs=8)
		kit.lathe([(h * 0.03, h * 0.12), (h * 0.11, h * 0.3), (h * 0.1, h * 0.75), (h * 0.01, h)], (0, 0, 0), "foliage_dark", "crown", segs=10)
		return
	if style == "palm":
		pts = [(0.3 * math.sin(i * 0.5), 0, h * i / 6) for i in range(7)]
		kit.sweep(pts, kit.circle(tr * 0.8, 8), "bark", "trunk", up=(0, 1, 0))
		for i in range(9):
			a = math.radians(40 * i)
			top = pts[-1]
			kit.sweep([top, (top[0] + 1.2 * math.cos(a), 1.2 * math.sin(a), top[2] + 0.4), (top[0] + 2.4 * math.cos(a), 2.4 * math.sin(a), top[2] - 0.5)], kit.rect(0.5, 0.02), foliage, "frond")
		return
	fork = h * (0.45 if style != "bare" else 0.35)
	kit.cyl(tr, fork, (0, 0, fork / 2), "bark", "trunk", segs=8, r2=tr * 0.7)
	n = 5 if style != "bare" else 7
	tips = []
	for i in range(n):
		a = math.radians(360 * i / n + rng.random() * 30)
		reach = h * (0.16 + rng.random() * 0.1)
		tip = (reach * math.cos(a), reach * math.sin(a), fork + h * (0.18 + rng.random() * 0.15))
		kit.rod((0, 0, fork - 0.1), tip, tr * 0.4, "bark", "branch", segs=6)
		tips.append(tip)
		if style == "bare":
			for j in range(3):
				b = math.radians(rng.random() * 360)
				kit.rod(tip, (tip[0] + h * 0.1 * math.cos(b), tip[1] + h * 0.1 * math.sin(b), tip[2] + h * (0.08 + 0.08 * rng.random())), tr * 0.15, "bark", "twig", segs=4)
	if style != "bare":
		for t in tips:
			kit.sphere(h * (0.17 + rng.random() * 0.05), t, foliage, "crown", segs=10)
		kit.sphere(h * 0.24, (0, 0, h * 0.78), foliage, "crown", segs=10)


def shrub(w=1.0, h=0.9, seed=1, slot="foliage"):
	rng = random.Random(seed)
	for i in range(5):
		a = math.radians(72 * i)
		r = w * 0.25
		kit.sphere(w * (0.25 + rng.random() * 0.08), (r * math.cos(a), r * math.sin(a), h * (0.4 + rng.random() * 0.15)), slot, "leaves", segs=8)
	kit.sphere(w * 0.3, (0, 0, h * 0.7), slot, "leaves", segs=8)


def hedge(h=1.5, d=0.7):
	kit.rounded_box((1.0, d, h), (0, 0, h / 2), "foliage_dark", "hedge", radius=min(0.12, d / 3))


def flower_bed(w=2.0, d=1.0):
	kit.box((w, d, 0.1), (0, 0, 0.05), "soil", "soil")
	rng = random.Random(3)
	for i in range(int(w * d * 8)):
		x, y = (rng.random() - 0.5) * (w - 0.2), (rng.random() - 0.5) * (d - 0.2)
		kit.sphere(0.09, (x, y, 0.2), "foliage", "plant", segs=6)
		kit.sphere(0.05, (x, y, 0.3), ("plastic_red", "plastic_yellow", "fabric_white", "plastic_blue")[i % 4], "flower", segs=6)


def lawn(w=1.0):
	kit.box((1.0, 1.0, 0.04), (0, 0, 0.02), "foliage", "turf")


def raised_bed(w=2.4, d=1.2):
	for s in (-1, 1):
		kit.box((w, 0.05, 0.4), (0, s * d / 2, 0.2), "softwood", "side")
		kit.box((0.05, d, 0.4), (s * w / 2, 0, 0.2), "softwood", "end")
	kit.box((w - 0.05, d - 0.05, 0.3), (0, 0, 0.17), "soil", "soil")
	for i in range(6):
		kit.sphere(0.15, (-w / 2 + 0.3 + i * (w - 0.6) / 5, 0, 0.4), "foliage", "crop", segs=6)


def boulder(s=1.0, seed=1):
	kit.chunk((s, s * 0.8, s * 0.6), (0, 0, s * 0.28), "concrete", "boulder", seed=seed, points=24)


def pond(r=2.0):
	kit.lathe([(r * 1.1, 0), (r * 1.1, 0.06), (r, 0.06)], (0, 0, 0), "paving", "edge", segs=20, scale=(1.3, 1, 1))
	kit.cyl(r, 0.02, (0, 0, 0.04), "water", "water", segs=20).scale = (1.3, 1, 1)


_TREES = (("oak", "Oak", "broadleaf", "foliage"), ("lime", "Lime", "broadleaf", "foliage_dark"), ("winter", "Tree, bare", "bare", "foliage"), ("pine", "Pine", "conifer", "foliage_dark"), ("cypress", "Cypress", "columnar", "foliage_dark"))
for _n, _lab, _style, _fol in _TREES:
	for _sz, _h in (("small", 5.0), ("medium", 9.0), ("large", 15.0)):
		reg("landscape.tree.%s_%s" % (_n, _sz), tree, "%s, %s, %d m" % (_lab, _sz, _h), "planting", h=_h, style=_style, foliage=_fol, seed=len(_n) + int(_h))
reg("landscape.tree.sapling", tree, "Sapling with stake, 2.5 m", "planting", h=2.5, seed=4)
reg("landscape.tree.palm", tree, "Palm, 7 m", "planting", h=7.0, style="palm")
for _i, (_w, _h) in enumerate(((0.6, 0.5), (1.0, 0.9), (1.6, 1.4), (2.2, 2.0))):
	reg("landscape.shrub.size_%d" % (_i + 1), shrub, "Shrub, %.1f m" % _h, "planting", w=_w, h=_h, seed=_i + 2, slot="foliage" if _i % 2 else "foliage_dark")
for _h in (1.0, 1.8, 3.0):
	register("landscape.hedge.h%d" % (_h * 1000), hedge, "Hedge, %.1f m high, per metre" % _h, family="landscape", tags=("landscape", "outdoor", "planting", "boundary"), stretch="x", h=_h)
reg("landscape.bed.flowers", flower_bed, "Flower bed", "planting")
reg("landscape.bed.raised", raised_bed, "Raised vegetable bed", "planting")
register("landscape.ground.lawn", lawn, "Lawn, per square metre", family="landscape", tags=("landscape", "outdoor", "planting"), stretch="xz")
for _i, _s in enumerate((0.5, 1.0, 2.0)):
	reg("landscape.rock.boulder_%d" % (_i + 1), boulder, "Boulder, %.1f m" % _s, s=_s, seed=_i + 5)
reg("landscape.water.pond", pond, "Garden pond")


# --- boundaries ----------------------------------------------------------------------------

def fence(style="closeboard", h=1.8):
	"""A 1 m run; scale along X. Posts are separate assets."""
	if style == "closeboard":
		for i in range(10):
			kit.box((0.1, 0.012 + 0.006 * (i % 2), h), (-0.45 + i * 0.1, 0.006 * (i % 2), h / 2), "softwood", "board")
		for z in (0.3, h - 0.3):
			kit.box((1.0, 0.04, 0.09), (0, -0.03, z), "softwood", "rail")
		kit.box((1.0, 0.025, 0.15), (0, 0, 0.075), "softwood", "gravel_board")
	elif style == "picket":
		for i in range(8):
			kit.prism([(-0.035, 0), (0.035, 0), (0.035, h - 0.05), (0, h), (-0.035, h - 0.05)], 0.02, (-0.4375 + i * 0.125, 0, 0), "paint_white", "pale", axis="y")
		for z in (0.25, h - 0.25):
			kit.box((1.0, 0.03, 0.07), (0, -0.025, z), "paint_white", "rail")
	elif style == "post_rail":
		for z in (h * 0.35, h * 0.7, h * 0.98):
			kit.box((1.0, 0.04, 0.09), (0, 0, z - 0.05), "softwood", "rail")
	elif style == "chainlink":
		kit.grid_bars(1.0, h, (0, 0, h / 2), 16, int(h / 0.06), 0.0015, "steel_galvanised", "mesh")
		for z in (0.05, h):
			kit.rod((-0.5, 0, z), (0.5, 0, z), 0.004, "steel_galvanised", "line_wire", segs=4)
	elif style == "palisade":
		for i in range(7):
			kit.prism([(-0.035, 0.08), (0.035, 0.08), (0.035, h - 0.08), (0, h), (-0.035, h - 0.08)], 0.004, (-0.43 + i * 0.143, 0.02, 0), "steel_galvanised", "pale", axis="y")
		for z in (0.35, h - 0.35):
			kit.angle(0.045, 0.005, 1.0, (0, 0, z), "steel_galvanised", "rail", axis="x")
	elif style == "railings":
		for i in range(8):
			kit.rod((-0.4375 + i * 0.125, 0, 0.1), (-0.4375 + i * 0.125, 0, h), 0.008, "plastic_black", "bar", segs=6)
		for z in (0.12, h - 0.1):
			kit.box((1.0, 0.04, 0.012), (0, 0, z), "plastic_black", "flat")
	elif style == "mesh":
		kit.grid_bars(1.0, h, (0, 0, h / 2), 20, int(h / 0.2), 0.0025, "plastic_green", "mesh")
	elif style == "acoustic":
		kit.box((1.0, 0.1, h), (0, 0, h / 2), "softwood", "panel")
	elif style == "brick_wall":
		kit.box((1.0, 0.215, h - 0.06), (0, 0, (h - 0.06) / 2), "brick", "wall")
		kit.box((1.0, 0.28, 0.06), (0, 0, h - 0.03), "concrete", "coping")
	elif style == "stone_wall":
		kit.prism([(-0.3, 0), (0.3, 0), (0.2, h), (-0.2, h)], 1.0, (0, 0, 0), "paving", "wall", axis="x")
	elif style == "crash_barrier":
		kit.sweep([(-0.5, 0, 0.6), (0.5, 0, 0.6)], [(0, -0.15), (0.04, -0.1), (0, -0.03), (0, 0.03), (0.04, 0.1), (0, 0.15), (-0.005, 0.15), (-0.005, -0.15)], "steel_galvanised", "beam", up=(0, 0, 1))
	elif style == "kerb":
		kit.prism([(-0.0625, 0), (0.0625, 0), (0.0625, 0.24), (-0.04, 0.255), (-0.0625, 0.23)], 1.0, (0, 0, -0.13), "concrete", "kerb", axis="x")


def fence_post(style="timber", h=1.8):
	if style == "timber":
		kit.box((0.1, 0.1, h + 0.05), (0, 0, (h + 0.05) / 2), "softwood", "post")
		kit.prism([(-0.06, 0), (0.06, 0), (0, 0.04)], 0.12, (0, 0, h + 0.05), "softwood", "cap", axis="y")
	elif style == "concrete":
		kit.box((0.1, 0.1, h + 0.1), (0, 0, (h + 0.1) / 2), "concrete", "post")
	elif style == "steel":
		kit.cyl(0.03, h + 0.05, (0, 0, (h + 0.05) / 2), "steel_galvanised", "post", segs=10)
	elif style == "strainer":
		kit.cyl(0.03, h + 0.05, (0, 0, (h + 0.05) / 2), "steel_galvanised", "post", segs=10)
		kit.rod((0, 0, h * 0.8), (1.2, 0, 0), 0.02, "steel_galvanised", "stay")
		for i in range(3):
			kit.rod((0, 0, h + 0.05), (0.2, 0, h + 0.35), 0.01, "steel_galvanised", "crank", segs=5)
	elif style == "pier":
		kit.box((0.44, 0.44, h), (0, 0, h / 2), "brick", "pier")
		kit.prism([(-0.26, 0), (0.26, 0), (0.1, 0.1), (-0.1, 0.1)], 0.52, (0, 0, h), "concrete", "cap", axis="y")


def gate(style="garden", w=0.9, h=1.0):
	if style == "garden":
		for i in range(int(w / 0.11)):
			kit.box((0.07, 0.02, h), (-w / 2 + 0.05 + i * 0.11, 0, h / 2 + 0.05), "softwood", "pale")
		for z in (0.25, h - 0.15):
			kit.box((w, 0.03, 0.07), (0, -0.025, z), "softwood", "ledge")
		kit.strut((-w / 2, -0.025, 0.25), (w / 2, -0.025, h - 0.15), 0.07, 0.03, "softwood", "brace")
	elif style == "field":
		kit.frame(w, h, 0.07, 0.07, at=(0, 0, 0.1), slot="softwood", name="frame")
		for z in (0.4, 0.65, 0.9):
			kit.box((w, 0.025, 0.07), (0, 0, z), "softwood", "bar")
		kit.strut((-w / 2, 0, 0.15), (w / 2, 0, h + 0.05), 0.07, 0.025, "softwood", "brace")
	elif style == "driveway":
		for s in (-1, 1):
			kit.frame(w / 2 - 0.02, h, 0.04, 0.04, at=(s * w / 4, 0, 0.08), slot="plastic_black", name="leaf")
			for i in range(int(w / 2 / 0.12)):
				kit.rod((s * (0.06 + i * 0.12), 0, 0.1), (s * (0.06 + i * 0.12), 0, h + 0.05), 0.008, "plastic_black", "bar", segs=6)
	elif style == "barrier":
		kit.box((0.35, 0.35, 1.1), (-w / 2, 0, 0.55), "plant_yellow", "cabinet")
		kit.box((w, 0.05, 0.1), (0.1, 0.2, 0.95), "paint_white", "arm")
		for i in range(int(w / 0.8)):
			kit.box((0.3, 0.052, 0.102), (-w / 2 + 0.6 + i * 0.8, 0.2, 0.95), "hazard_red", "stripe")
	elif style == "sliding":
		kit.frame(w, h, 0.08, 0.08, at=(0, 0, 0.15), slot="steel_galvanised", name="frame")
		kit.grid_bars(w - 0.16, h - 0.16, (0, 0, 0.15 + h / 2), int(w / 0.12), 0, 0.012, "steel_galvanised", "bars")
		kit.box((w * 2, 0.1, 0.05), (w / 2, 0, 0.025), "steel_galvanised", "track")
		for s in (-1, 1):
			kit.box((0.15, 0.15, h + 0.4), (w / 2 + 0.2, s * 0.15, (h + 0.4) / 2), "steel_galvanised", "guide_post")
	kit.socket("hinge", (-w / 2, 0, 0))


_FENCES = (("closeboard", "Close-board fence", (1.2, 1.8)), ("picket", "Picket fence", (0.9, 1.2)), ("post_rail", "Post and rail fence", (1.2,)), ("chainlink", "Chain-link fence", (1.8, 2.4, 3.0)),
	("palisade", "Steel palisade fence", (1.8, 2.4)), ("railings", "Railings", (1.1, 1.8)), ("mesh", "Weldmesh fence", (2.0, 3.0)), ("acoustic", "Acoustic barrier", (2.5, 4.0)),
	("brick_wall", "Brick garden wall", (0.6, 1.2, 1.8)), ("stone_wall", "Dry stone wall", (1.1,)), ("crash_barrier", "Crash barrier", (0.75,)), ("kerb", "Kerb", (0.125,)))
for _s, _lab, _hs in _FENCES:
	for _h in _hs:
		register("boundary.%s.h%d" % (_s, round(_h * 1000)), fence, "%s, %s m, per metre" % (_lab, _h), family="boundary", tags=("boundary", "outdoor"), stretch="x", style=_s, h=_h)
for _s, _lab, _hs in (("timber", "Timber fence post", (1.2, 1.8)), ("concrete", "Concrete fence post", (1.8,)), ("steel", "Steel fence post", (1.8, 2.4, 3.0)), ("strainer", "Security fence end post", (2.4,)), ("pier", "Brick pier", (1.2, 1.8))):
	for _h in _hs:
		reg("boundary.post.%s_%d" % (_s, round(_h * 1000)), fence_post, "%s, %s m" % (_lab, _h), style=_s, h=_h)
reg("boundary.gate.garden", gate, "Garden gate", "opening")
reg("boundary.gate.side", gate, "Side gate, 1.8 m", "opening", h=1.8)
reg("boundary.gate.field", gate, "Field gate, 3.6 m", "opening", style="field", w=3.6, h=1.1)
reg("boundary.gate.driveway", gate, "Driveway gates, 3 m", "opening", style="driveway", w=3.0, h=1.5)
reg("boundary.gate.barrier_arm", gate, "Car park barrier arm", "opening", style="barrier", w=3.5)
reg("boundary.gate.sliding", gate, "Sliding security gate, 6 m", "opening", style="sliding", w=6.0, h=2.2)


# --- street furniture ----------------------------------------------------------------------

def street(what="lamp", h=8.0):
	if what == "lamp":
		kit.cyl(0.09, h, (0, 0, h / 2), "steel_galvanised", "column", segs=12, r2=0.045)
		kit.sweep([(0, 0, h), (0, 0.3, h + 0.25), (0, 1.2, h + 0.3)], kit.circle(0.035, 8), "steel_galvanised", "bracket", up=(1, 0, 0))
		kit.rounded_box((0.3, 0.7, 0.1), (0, 1.4, h + 0.28), "aluminium", "lantern", radius=0.04)
		kit.box((0.22, 0.5, 0.01), (0, 1.4, h + 0.225), "light_emitter", "lens")
		kit.box((0.1, 0.005, 0.5), (0, 0.092, 0.9), "steel_galvanised", "door")
	elif what == "lamp_twin":
		kit.cyl(0.11, h, (0, 0, h / 2), "steel_galvanised", "column", segs=12, r2=0.06)
		for s in (-1, 1):
			kit.rod((0, 0, h), (0, s * 1.2, h + 0.2), 0.035, "steel_galvanised", "bracket")
			kit.rounded_box((0.3, 0.7, 0.1), (0, s * 1.4, h + 0.2), "aluminium", "lantern", radius=0.04)
			kit.box((0.22, 0.5, 0.01), (0, s * 1.4, h + 0.145), "light_emitter", "lens")
	elif what == "lamp_heritage":
		kit.lathe([(0.12, 0), (0.1, 0.5), (0.05, 0.7), (0.04, h - 0.6), (0.07, h - 0.55)], (0, 0, 0), "plastic_black", "column", segs=12)
		kit.lathe([(0.1, 0), (0.2, 0.45), (0.22, 0.47), (0.02, 0.6)], (0, 0, h - 0.55), "glass", "lantern", segs=6)
		kit.sphere(0.06, (0, 0, h - 0.3), "light_emitter", "lamp", segs=8)
	elif what == "bollard":
		kit.cyl(0.07, 1.0, (0, 0, 0.5), "plastic_black", "bollard", segs=14)
		kit.sphere(0.075, (0, 0, 1.0), "plastic_black", "top", segs=12)
		kit.cyl(0.072, 0.06, (0, 0, 0.85), "paint_white", "band", segs=14)
	elif what == "bollard_steel":
		kit.cyl(0.057, 1.0, (0, 0, 0.5), "steel_stainless", "bollard", segs=14)
	elif what == "bollard_concrete":
		kit.lathe([(0.2, 0), (0.2, 0.1), (0.14, 0.7), (0.1, 0.8), (0.02, 0.85)], (0, 0, 0), "concrete", "bollard", segs=14)
	elif what == "bollard_lit":
		kit.cyl(0.08, 0.75, (0, 0, 0.375), "aluminium", "bollard", segs=14)
		kit.cyl(0.075, 0.18, (0, 0, 0.84), "light_emitter", "lamp", segs=14)
		kit.cyl(0.085, 0.04, (0, 0, 0.95), "aluminium", "cap", segs=14)
	elif what == "traffic_light":
		kit.cyl(0.057, 3.6, (0, 0, 1.8), "plastic_grey", "pole", segs=12)
		kit.rounded_box((0.3, 0.2, 0.95), (0, 0.12, 3.0), "plastic_black", "head", radius=0.03)
		for i, c in enumerate(("hazard_red", "plastic_yellow", "plastic_green")):
			kit.cyl(0.1, 0.03, (0, 0.225, 3.3 - i * 0.3), c, "signal", axis="y", segs=14)
		kit.box((0.15, 0.1, 0.25), (0, 0.1, 1.1), "plastic_yellow", "push_button")
	elif what == "sign_round":
		kit.cyl(0.038, 2.9, (0, 0, 1.45), "steel_galvanised", "post", segs=10)
		kit.cyl(0.3, 0.01, (0, 0.045, 2.55), "hazard_red", "sign", axis="y", segs=24)
		kit.cyl(0.23, 0.012, (0, 0.046, 2.55), "paint_white", "face", axis="y", segs=24)
	elif what == "sign_triangle":
		kit.cyl(0.038, 2.9, (0, 0, 1.45), "steel_galvanised", "post", segs=10)
		kit.prism([(-0.38, 2.2), (0.38, 2.2), (0, 2.86)], 0.01, (0, 0.045, 0), "hazard_red", "sign", axis="y")
		kit.prism([(-0.26, 2.27), (0.26, 2.27), (0, 2.72)], 0.012, (0, 0.046, 0), "paint_white", "face", axis="y")
	elif what == "sign_direction":
		for s in (-1, 1):
			kit.cyl(0.045, 3.4, (s * 0.8, 0, 1.7), "steel_galvanised", "post", segs=10)
		kit.box((2.2, 0.02, 1.2), (0, 0.055, 2.7), "plastic_green", "sign")
		kit.box((2.0, 0.022, 0.25), (0, 0.056, 2.9), "paint_white", "text_band")
	elif what == "sign_street":
		for s in (-1, 1):
			kit.box((0.05, 0.05, 0.9), (s * 0.45, 0, 0.45), "plastic_black", "leg")
		kit.box((1.1, 0.02, 0.18), (0, 0, 0.85), "paint_white", "plate")
	elif what == "bench":
		for s in (-1, 1):
			kit.sweep([(s * 0.75, 0.25, 0), (s * 0.75, 0.25, 0.42), (s * 0.75, -0.22, 0.42), (s * 0.75, -0.3, 0.85)], kit.rect(0.05, 0.05), "cast_iron", "end", up=(1, 0, 0))
			kit.box((0.05, 0.05, 0.42), (s * 0.75, -0.2, 0.21), "cast_iron", "back_leg")
		for y in (-0.15, -0.03, 0.09, 0.21):
			kit.box((1.8, 0.09, 0.03), (0, y, 0.45), "hardwood", "slat")
		for z in (0.58, 0.72):
			kit.box((1.8, 0.03, 0.09), (0, -0.26, z), "hardwood", "slat")
	elif what == "litter_bin":
		with kit.hollow(0.1):
			kit.cyl(0.25, 0.9, (0, 0, 0.5), "plastic_black", "bin", segs=16)
		kit.cyl(0.27, 0.06, (0, 0, 0.98), "plastic_black", "hood", segs=16)
		kit.box((0.25, 0.02, 0.12), (0, 0.245, 0.8), "plastic_grey", "slot")
	elif what == "bus_shelter":
		for x in (-1.9, 1.9):
			kit.box((0.08, 0.08, 2.5), (x, -0.7, 1.25), "aluminium", "post")
		kit.box((4.0, 0.012, 1.9), (0, -0.7, 1.15), "glass", "back")
		kit.box((0.012, 1.3, 1.9), (-1.95, -0.05, 1.15), "glass", "end")
		kit.box((1.3, 0.1, 1.9), (1.3, -0.72, 1.15), "plastic_black", "advert_case")
		kit.sweep([(0, -0.9, 2.5), (0, 0, 2.62), (0, 0.9, 2.5)], [(-2.1, 0), (2.1, 0), (2.1, 0.03), (-2.1, 0.03)], "aluminium", "roof")
		kit.box((2.4, 0.3, 0.04), (-0.6, -0.5, 0.5), "plastic_red", "perch")
		kit.cyl(0.04, 2.8, (2.4, 0.5, 1.4), "steel_galvanised", "stop_pole", segs=10)
		kit.box((0.45, 0.03, 0.45), (2.4, 0.5, 2.7), "hazard_red", "stop_flag")
	elif what == "post_box":
		kit.cyl(0.23, 1.3, (0, 0, 0.65), "hazard_red", "pillar", segs=20)
		kit.lathe([(0.26, 0), (0.25, 0.05), (0.08, 0.14)], (0, 0, 1.3), "hazard_red", "cap", segs=20)
		kit.cyl(0.24, 0.1, (0, 0, 0.05), "plastic_black", "base", segs=20)
		kit.box((0.22, 0.03, 0.035), (0, 0.225, 1.1), "plastic_black", "slot")
	elif what == "phone_box":
		with kit.hollow(0.1):
			kit.box((0.9, 0.9, 0.1), (0, 0, 0.05), "hazard_red", "base")
			for sx in (-1, 1):
				for sy in (-1, 1):
					kit.box((0.08, 0.08, 2.2), (sx * 0.41, sy * 0.41, 1.2), "hazard_red", "corner")
			kit.box((0.9, 0.9, 0.2), (0, 0, 2.3), "hazard_red", "head")
		kit.lathe([(0.6, 0), (0.3, 0.12)], (0, 0, 2.4), "hazard_red", "dome", segs=4, rot=(0, 0, 45))
		kit.box((0.76, 0.76, 2.0), (0, 0, 1.15), "glass", "glazing")
	elif what == "cycle_stand":
		kit.sweep([(-0.35, 0, 0), (-0.35, 0, 0.7), (-0.25, 0, 0.8), (0.25, 0, 0.8), (0.35, 0, 0.7), (0.35, 0, 0)], kit.circle(0.024, 8), "steel_stainless", "hoop", up=(0, 1, 0))
	elif what == "manhole":
		kit.box((0.75, 0.75, 0.02), (0, 0, 0.0), "cast_iron", "frame")
		kit.box((0.6, 0.6, 0.025), (0, 0, 0.002), "cast_iron", "cover")
	elif what == "gully":
		kit.box((0.45, 0.33, 0.02), (0, 0, 0.0), "cast_iron", "frame")
		kit.grid_bars(0.4, 0.28, (0, 0, 0.012), 6, 0, 0.012, "cast_iron", "grate", plane="xy")
	elif what == "hydrant":
		kit.lathe([(0.1, 0), (0.08, 0.1), (0.08, 0.55), (0.1, 0.6), (0.02, 0.72)], (0, 0, 0), "plastic_yellow", "hydrant", segs=12)
		for s in (-1, 1):
			kit.cyl(0.04, 0.08, (s * 0.1, 0, 0.42), "plastic_yellow", "outlet", axis="x", segs=10)
	elif what == "cabinet":
		kit.box((1.2, 0.4, 1.3), (0, 0, 0.7), "plastic_green", "cabinet")
		kit.box((1.3, 0.5, 0.1), (0, 0, 0.05), "concrete", "plinth")
	elif what == "telegraph_pole":
		kit.cyl(0.13, 9.0, (0, 0, 4.5), "softwood", "pole", segs=10, r2=0.09)
		for z in (8.2, 8.6):
			kit.box((1.2, 0.06, 0.08), (0, 0, z), "softwood", "cross_arm")
			for x in (-0.5, -0.25, 0.25, 0.5):
				kit.cyl(0.025, 0.08, (x, 0, z + 0.08), "ceramic", "insulator", segs=8)
	elif what == "pylon":
		kit.lattice(26.0, 5.0, 0.12, 0.06, at=(0, 0, 0), bays=6, slot="steel_galvanised", name="tower")
		for z, w in ((17.0, 14.0), (21.0, 10.0), (25.0, 12.0)):
			kit.lattice(w, 0.8, 0.06, 0.03, at=(0, -w / 2, z), bays=10, slot="steel_galvanised", name="cross_arm", axis="y")
			for s in (-1, 1):
				kit.cyl(0.08, 1.6, (0, s * (w / 2 - 0.3), z - 0.8), "ceramic", "insulator", segs=8)
	elif what == "flagpole":
		kit.cyl(0.05, 8.0, (0, 0, 4.0), "paint_white", "pole", segs=10, r2=0.03)
		kit.sphere(0.06, (0, 0, 8.03), "brass", "finial", segs=8)
		kit.sweep([(0.04 + i * 0.2, 0.08 * math.sin(i * 1.3), 7.3) for i in range(10)], kit.rect(0.004, 1.2), "fabric_red", "flag")
	elif what == "fountain":
		with kit.hollow(0.4):
			kit.lathe([(2.0, 0), (2.0, 0.5), (1.8, 0.5), (1.8, 0.15), (0, 0.15)], (0, 0, 0), "paving", "basin", segs=24)
		kit.cyl(1.8, 0.02, (0, 0, 0.4), "water", "water", segs=24)
		kit.lathe([(0.25, 0), (0.15, 1.0), (0.7, 1.2), (0.72, 1.3), (0.1, 1.25)], (0, 0, 0.15), "paving", "bowl", segs=16)
	elif what == "statue":
		kit.box((1.2, 1.2, 1.5), (0, 0, 0.75), "paving", "plinth")
		kit.box((1.4, 1.4, 0.15), (0, 0, 0.075), "paving", "base")
		person(pose="stand", top="lead", legs="lead", skin="lead", hat="", z0=1.5)
	elif what == "billboard":
		for s in (-1, 1):
			kit.i_section(0.15, 0.3, 0.012, 0.008, 6.0, (s * 2.0, -0.2, 3.0), "steel_galvanised", "post", axis="z")
		kit.box((6.0, 0.15, 3.0), (0, 0, 4.5), "plastic_black", "frame")
		kit.box((5.8, 0.01, 2.8), (0, 0.08, 4.5), "paint_white", "poster")
	elif what == "parking_meter":
		kit.box((0.3, 0.25, 1.5), (0, 0, 0.75), "plastic_grey", "body")
		kit.box((0.2, 0.004, 0.12), (0, 0.127, 1.3), "screen", "display")
		kit.box((0.34, 0.3, 0.05), (0, 0, 1.6), "plastic_blue", "solar_panel", rot=(20, 0, 0))
	elif what == "tree_grate":
		kit.grid_bars(1.2, 1.2, (0, 0, 0.01), 12, 0, 0.012, "cast_iron", "grate", plane="xy")
		kit.cyl(0.02, 1.8, (0.25, 0, 0.9), "softwood", "stake", segs=6)
	elif what == "parasol":
		kit.rounded_box((0.5, 0.5, 0.1), (0, 0, 0.05), "concrete", "base", radius=0.02)
		kit.cyl(0.02, 2.4, (0, 0, 1.2), "hardwood", "pole", segs=8)
		kit.lathe([(1.5, 0), (0.02, 0.5)], (0, 0, 1.95), "fabric_white", "canopy", segs=8)
	elif what == "pergola":
		for x in (-1.5, 1.5):
			for y in (-1.2, 1.2):
				kit.box((0.12, 0.12, 2.4), (x, y, 1.2), "softwood", "post")
		for y in (-1.2, 1.2):
			kit.box((3.6, 0.05, 0.2), (0, y, 2.4), "softwood", "beam")
		for i in range(8):
			kit.box((0.045, 3.0, 0.15), (-1.6 + i * 0.457, 0, 2.57), "softwood", "rafter")
	elif what == "greenhouse":
		kit.box((2.5, 3.1, 0.15), (0, 0, 0.075), "brick", "base")
		with kit.hollow(0.02):
			kit.prism([(-1.22, 0.15), (1.22, 0.15), (1.22, 1.6), (0, 2.4), (-1.22, 1.6)], 3.0, (0, 0, 0), "glass", "glazing", axis="y")
		for y in (-1.5, -0.75, 0, 0.75, 1.5):
			kit.sweep([(-1.22, y, 0.15), (-1.22, y, 1.6), (0, y, 2.4), (1.22, y, 1.6), (1.22, y, 0.15)], kit.rect(0.03, 0.03), "aluminium", "frame", up=(0, 1, 0))
	elif what == "trampoline":
		kit.cyl(1.5, 0.03, (0, 0, 0.7), "plastic_black", "mat", segs=24)
		kit.sweep([(1.6 * math.cos(math.radians(a)), 1.6 * math.sin(math.radians(a)), 0.7) for a in range(0, 361, 20)], kit.rect(0.3, 0.04), "plastic_blue", "pad")
		for i in range(6):
			a = math.radians(60 * i)
			kit.rod((1.6 * math.cos(a), 1.6 * math.sin(a), 0), (1.6 * math.cos(a), 1.6 * math.sin(a), 2.4), 0.02, "steel_galvanised", "pole")
	elif what == "garage":
		with kit.hollow(0.08):
			kit.box((3.0, 5.4, 2.3), (0, 0, 1.15), "brick", "walls")
		kit.box((3.2, 5.6, 0.12), (0, 0, 2.36), "roof_felt", "roof", rot=(1.5, 0, 0))
		kit.box((2.3, 0.04, 2.0), (0, 2.7, 1.0), "paint_white", "door")
	elif what == "oil_tank":
		with kit.hollow(0.05):
			kit.rounded_box((1.8, 0.7, 1.3), (0, 0, 0.95), "plastic_green", "tank", radius=0.15)
		for x in (-0.6, 0.6):
			kit.box((0.2, 0.7, 0.3), (x, 0, 0.15), "blockwork", "pier")
	elif what == "rotary_line":
		kit.cyl(0.02, 1.9, (0, 0, 0.95), "aluminium", "pole", segs=8)
		for i in range(4):
			a = math.radians(90 * i)
			kit.rod((0, 0, 1.4), (1.2 * math.cos(a), 1.2 * math.sin(a), 1.9), 0.012, "aluminium", "arm", segs=6)
		for r in (0.5, 0.85, 1.2):
			pts = [(r * math.cos(math.radians(90 * i)), r * math.sin(math.radians(90 * i)), 1.4 + r / 1.2 * 0.5) for i in range(5)]
			kit.sweep(pts, kit.circle(0.002, 4), "plastic_white", "line")


_STREET = (("light.column_8m", "lamp", "Street light, 8 m", {}), ("light.column_5m", "lamp", "Street light, 5 m", {"h": 5.0}), ("light.column_12m", "lamp", "Street light, 12 m", {"h": 12.0}),
	("light.twin_10m", "lamp_twin", "Street light, twin arm, 10 m", {"h": 10.0}), ("light.heritage", "lamp_heritage", "Heritage lamp post", {"h": 4.0}),
	("bollard.cast", "bollard", "Bollard, cast iron", {}), ("bollard.steel", "bollard_steel", "Bollard, stainless", {}), ("bollard.concrete", "bollard_concrete", "Bollard, concrete", {}), ("bollard.lit", "bollard_lit", "Lit bollard", {}),
	("traffic.signal", "traffic_light", "Traffic signal", {}), ("traffic.sign_round", "sign_round", "Road sign, round", {}), ("traffic.sign_triangle", "sign_triangle", "Road sign, warning", {}),
	("traffic.sign_direction", "sign_direction", "Direction sign", {}), ("traffic.street_name", "sign_street", "Street name plate", {}), ("traffic.parking_meter", "parking_meter", "Pay and display machine", {}),
	("traffic.billboard", "billboard", "Billboard", {}),
	("furniture.bench", "bench", "Street bench", {}), ("furniture.litter_bin", "litter_bin", "Litter bin", {}), ("furniture.bus_shelter", "bus_shelter", "Bus shelter and stop", {}),
	("furniture.post_box", "post_box", "Pillar box", {}), ("furniture.phone_box", "phone_box", "Telephone box", {}), ("furniture.cycle_stand", "cycle_stand", "Cycle stand", {}),
	("furniture.flagpole", "flagpole", "Flagpole", {}), ("furniture.fountain", "fountain", "Fountain", {}), ("furniture.statue", "statue", "Statue on plinth", {}), ("furniture.tree_grate", "tree_grate", "Tree grate and stake", {}),
	("utility.manhole", "manhole", "Manhole cover", {}), ("utility.gully", "gully", "Road gully", {}), ("utility.hydrant", "hydrant", "Fire hydrant", {}), ("utility.cabinet", "cabinet", "Telecoms cabinet", {}),
	("garden.parasol", "parasol", "Parasol", {}), ("garden.pergola", "pergola", "Pergola", {}), ("garden.greenhouse", "greenhouse", "Greenhouse", {}), ("garden.trampoline", "trampoline", "Trampoline", {}),
	("garden.garage", "garage", "Detached garage", {}), ("garden.oil_tank", "oil_tank", "Heating oil tank", {}), ("garden.rotary_line", "rotary_line", "Rotary washing line", {}))


# --- neighbouring buildings ----------------------------------------------------------------

def context_building(style="detached", floors=2, w=8.0, d=9.0, walls="brick", roof="clay_tile", flat=False):
	"""A simple neighbouring building: walls, window bands, a roof. Faces +Y."""
	fh = 2.8 if style not in ("warehouse", "shop") else (7.0 if style == "warehouse" else 3.6)
	h = fh * floors
	with kit.hollow(0.08):
		with kit.stage("walls"):
			kit.box((w, d, h), (0, 0, h / 2), walls, "walls")
		with kit.stage("roof"):
			if flat:
				kit.box((w + 0.2, d + 0.2, 0.4), (0, 0, h + 0.2), "concrete", "parapet")
				kit.box((w - 0.4, d - 0.4, 0.05), (0, 0, h + 0.38), "roof_felt", "roof")
			else:
				rise = min(w, d) * 0.3
				if w >= d:
					kit.prism([(-d / 2 - 0.3, 0), (d / 2 + 0.3, 0), (0, rise)], w + 0.4, (0, 0, h), roof, "roof", axis="x")
				else:
					kit.prism([(-w / 2 - 0.3, 0), (w / 2 + 0.3, 0), (0, rise)], d + 0.4, (0, 0, h), roof, "roof", axis="y")
				if style in ("detached", "semi", "terrace"):
					kit.box((0.6, 0.45, 1.4), (w / 2 - 0.5, 0, h + rise * 0.5 + 0.5), "brick", "chimney")
	with kit.stage("openings"):
		n = max(2, int(w / 2.6))
		for f in range(floors):
			for i in range(n):
				x = -w / 2 + w * (i + 0.5) / n
				z = f * fh + fh * 0.55
				door = f == 0 and i == (n // 2 if style != "semi" else 0) and style != "warehouse"
				if style == "shop" and f == 0:
					continue
				if door:
					kit.box((0.95, 0.06, 2.1), (x, d / 2, 1.05), "plastic_blue", "front_door")
				elif style == "warehouse":
					if f == 0 and i % 2 == 0:
						kit.box((w / n * 0.7, 0.06, 4.5), (x, d / 2, 2.25), "steel_galvanised", "roller_door")
				else:
					kit.box((min(1.4, w / n * 0.6), 0.06, 1.25), (x, d / 2, z), "glass", "window")
					kit.box((min(1.4, w / n * 0.6), 0.06, 1.25), (x, -d / 2, z), "glass", "window")
		if style == "shop":
			kit.box((w - 0.8, 0.06, 2.4), (0, d / 2, 1.3), "glass", "shopfront")
			kit.box((w - 0.2, 0.1, 0.6), (0, d / 2 + 0.03, 3.0), "plastic_green", "fascia")
	kit.socket("front_door", (0, d / 2, 0))


_CONTEXT = (("house_detached", "Neighbouring house, detached", dict()), ("house_semi", "Neighbouring houses, semi-detached pair", dict(style="semi", w=11.0, d=8.5)),
	("house_terrace_4", "Neighbouring terrace, four houses", dict(style="terrace", w=20.0, d=8.5)), ("house_terrace_8", "Neighbouring terrace, eight houses", dict(style="terrace", w=40.0, d=8.5)),
	("bungalow", "Neighbouring bungalow", dict(floors=1, w=11.0, d=8.0)), ("house_rendered", "Neighbouring house, rendered", dict(walls="render", roof="slate")),
	("house_3_storey", "Neighbouring town house, three storey", dict(floors=3, w=6.0, d=10.0, roof="slate")),
	("flats_4", "Block of flats, four storey", dict(style="flats", floors=4, w=24.0, d=14.0, flat=True)), ("flats_8", "Block of flats, eight storey", dict(style="flats", floors=8, w=24.0, d=16.0, walls="concrete", flat=True)),
	("flats_15", "Tower block, fifteen storey", dict(style="flats", floors=15, w=20.0, d=20.0, walls="concrete", flat=True)),
	("office_5", "Office block, five storey", dict(style="office", floors=5, w=30.0, d=18.0, walls="render", flat=True)), ("office_12", "Office tower, twelve storey", dict(style="office", floors=12, w=28.0, d=28.0, walls="aluminium", flat=True)),
	("shop_parade", "Shop parade with flats over", dict(style="shop", floors=2, w=24.0, d=10.0, flat=True)), ("corner_shop", "Corner shop", dict(style="shop", floors=2, w=8.0, d=9.0)),
	("warehouse", "Warehouse unit", dict(style="warehouse", floors=1, w=30.0, d=20.0, walls="steel_painted", roof="steel_galvanised")),
	("warehouse_large", "Distribution shed", dict(style="warehouse", floors=1, w=80.0, d=45.0, walls="steel_painted", roof="steel_galvanised")),
	("church_hall", "Hall with pitched roof", dict(floors=1, w=10.0, d=20.0, roof="slate")), ("pub", "Public house", dict(floors=2, w=14.0, d=10.0, walls="render", roof="slate")))


# --- demolition debris ---------------------------------------------------------------------

def debris(what="rubble", size=0.3, slot="concrete", seed=1, n=1):
	rng = random.Random(seed)
	if what == "rubble":
		for i in range(n):
			s = size * (0.6 + rng.random() * 0.8)
			r = 0 if n == 1 else size * math.sqrt(n) * 0.5 * rng.random()
			a = rng.random() * 6.283
			kit.chunk((s, s * (0.6 + rng.random() * 0.5), s * (0.5 + rng.random() * 0.4)), (r * math.cos(a), r * math.sin(a), s * 0.25), slot, "lump", seed=seed * 100 + i, points=10, rot=(0, 0, rng.random() * 360))
	elif what == "heap":
		kit.lathe([(size * 2.0, 0), (size * 1.3, size * 0.4), (size * 0.4, size * 0.75), (0.02, size * 0.8)], (0, 0, 0), slot, "heap", segs=9, scale=(1, 0.8, 1))
		for i in range(int(50 + size * 40)):
			a, f = rng.random() * 6.283, math.sqrt(rng.random())
			r = size * 2.1 * f
			s = (0.3 + rng.random() * 0.5) * (0.7 + size * 0.3)
			kit.chunk((s, s * 0.7, s * 0.5), (r * math.cos(a), r * 0.8 * math.sin(a), max(0.08, size * 0.85 * (1 - f) ** 0.8 + 0.05)), "brick" if i % 3 == 0 and slot == "concrete" else slot, "lump", seed=seed * 100 + i, points=9, rot=(rng.random() * 50, rng.random() * 50, rng.random() * 360))
		for i in range(5):
			a = rng.random() * 6.283
			kit.rod((size * math.cos(a), size * 0.8 * math.sin(a), size * 0.3), (size * 1.6 * math.cos(a + 0.4), size * 1.3 * math.sin(a + 0.4), size * (0.6 + rng.random() * 0.5)), 0.012, "steel_painted", "rebar", segs=5)
	elif what == "slab":
		kit.chunk((size * 4, size * 3, 0.2), (0, 0, 0.25), "concrete", "slab", seed=seed, points=30, rot=(8, -5, 0))
		for i in range(6):
			x = -size * 1.5 + i * size * 0.6
			kit.sweep([(x, size * 1.0, 0.25), (x, size * 1.8, 0.3 + rng.random() * 0.2), (x + rng.random() * 0.3, size * 2.2, 0.1 + rng.random() * 0.5)], kit.circle(0.008, 5), "steel_painted", "rebar")
	elif what == "wall":
		for i in range(5):
			for j in range(6 - i):
				if rng.random() > 0.15:
					kit.box((0.44, 0.215, 0.215), (-1.2 + j * 0.45 + (i % 2) * 0.22, 0, 0.11 + i * 0.225), slot, "block")
		for i in range(6):
			kit.box((0.44, 0.215, 0.215), ((rng.random() - 0.5) * 2.5, 0.4 + rng.random() * 0.8, 0.11), slot, "fallen_block", rot=(0, 0, rng.random() * 180))
	elif what == "beam":
		kit.sweep([(-2.0, 0, 0.15), (-0.5, 0, 0.18), (0.6, 0.2, 0.6), (1.8, 0.5, 0.9)], [(a, b) for a, b in kit.i_points(0.17, 0.36, 0.013, 0.008)], "steel_painted", "bent_beam")
	elif what == "rebar":
		for i in range(7):
			pts = [((rng.random() - 0.5) * 0.3, -1.0, 0.03 + i * 0.01)]
			for k in range(1, 5):
				pts.append((pts[-1][0] + (rng.random() - 0.5) * 0.5, -1.0 + k * 0.5, 0.03 + rng.random() * 0.3 * k / 2))
			kit.sweep(pts, kit.circle(0.008, 5), "steel_painted", "bar")
	elif what == "timber":
		for i in range(8):
			l = 0.8 + rng.random() * 1.6
			kit.box((0.1, l, 0.047), ((rng.random() - 0.5) * 1.2, (rng.random() - 0.5) * 0.8, 0.03 + i * 0.045), "softwood", "broken_joist", rot=((rng.random() - 0.5) * 12, 0, rng.random() * 180))
	elif what == "glass":
		for i in range(14):
			a = rng.random() * 6.283
			r = rng.random() * 0.7
			kit.prism([(0, 0), (0.1 + rng.random() * 0.15, 0.02), (0.05, 0.1 + rng.random() * 0.15)], 0.004, (r * math.cos(a), r * math.sin(a), 0.003), "glass", "shard", axis="z", rot=(0, 0, rng.random() * 360))
	elif what == "roof_tiles":
		for i in range(16):
			kit.box((0.26, 0.16, 0.015), ((rng.random() - 0.5) * 1.4, (rng.random() - 0.5) * 1.4, 0.01 + i * 0.006), "clay_tile", "tile", rot=((rng.random() - 0.5) * 20, 0, rng.random() * 360))
	elif what == "column_stub":
		kit.box((0.4, 0.4, 0.5), (0, 0, 0.25), "concrete", "stub")
		kit.chunk((0.45, 0.45, 0.3), (0, 0, 0.55), "concrete", "broken_top", seed=seed, points=16)
		for sx in (-1, 1):
			for sy in (-1, 1):
				kit.sweep([(sx * 0.14, sy * 0.14, 0.5), (sx * 0.15, sy * 0.15, 1.0), (sx * 0.3, sy * 0.25, 1.3)], kit.circle(0.012, 5), "steel_painted", "rebar")
	elif what == "dust":
		kit.lathe([(size, 0), (size * 0.6, size * 0.12), (0.01, size * 0.2)], (0, 0, 0), "render", "dust", segs=14)
	elif what == "crushed":
		kit.lathe([(3.0, 0), (2.0, 1.0), (0.6, 1.9), (0.03, 2.1)], (0, 0, 0), slot, "stockpile", segs=16)
	elif what == "scrap_bin":
		with kit.hollow(0.03):
			kit.prism([(-2.5, 0.2), (2.5, 0.2), (2.9, 2.0), (-2.9, 2.0)], 2.3, (0, 0, 0), "plastic_blue", "bin", axis="x")
		for i in range(12):
			kit.rod(((rng.random() - 0.5) * 1.8, (rng.random() - 0.5) * 4, 1.9), ((rng.random() - 0.5) * 1.8, (rng.random() - 0.5) * 4, 2.1 + rng.random() * 0.5), 0.03, "steel_painted", "scrap", segs=5)


_DEBRIS = []
for _slot in ("concrete", "brick", "blockwork"):
	for _i, _s in enumerate((0.15, 0.3, 0.6, 1.0)):
		_DEBRIS.append(("rubble.%s_%d" % (_slot, _i + 1), "%s lump, %.2f m" % (_slot.capitalize(), _s), dict(size=_s, slot=_slot, seed=_i + 3)))
	_DEBRIS.append(("rubble.%s_scatter" % _slot, "%s rubble scatter" % _slot.capitalize(), dict(size=0.25, slot=_slot, seed=9, n=12)))
	_DEBRIS.append(("heap.%s_small" % _slot, "%s rubble heap, small" % _slot.capitalize(), dict(what="heap", size=0.8, slot=_slot, seed=4)))
	_DEBRIS.append(("heap.%s_large" % _slot, "%s rubble heap, large" % _slot.capitalize(), dict(what="heap", size=1.8, slot=_slot, seed=6)))
_DEBRIS += [("piece.slab", "Broken slab with rebar", dict(what="slab", size=0.6)), ("piece.slab_large", "Broken slab with rebar, large", dict(what="slab", size=1.2, seed=3)),
	("piece.wall_brick", "Part-demolished brick wall", dict(what="wall", slot="brick")), ("piece.wall_block", "Part-demolished block wall", dict(what="wall", slot="blockwork", seed=2)),
	("piece.bent_beam", "Bent steel beam", dict(what="beam")), ("piece.rebar_tangle", "Tangled rebar", dict(what="rebar")), ("piece.timbers", "Broken timbers", dict(what="timber")),
	("piece.glass", "Broken glass", dict(what="glass")), ("piece.roof_tiles", "Fallen roof tiles", dict(what="roof_tiles")), ("piece.column_stub", "Broken column stub", dict(what="column_stub")),
	("heap.dust", "Dust pile", dict(what="dust", size=1.0)), ("heap.crushed_concrete", "Crushed concrete stockpile", dict(what="crushed")), ("heap.crushed_brick", "Crushed brick stockpile", dict(what="crushed", slot="brick")),
	("bin.scrap_metal", "Scrap metal bin", dict(what="scrap_bin"))]


# --- people --------------------------------------------------------------------------------

def person(pose="stand", top="hivis_yellow", legs="denim", skin="skin", hat="plastic_yellow", height=1.75, z0=0.0, carry=""):
	"""A simple figure for scale and for crews. Faces +Y."""
	k = height / 1.75
	hip = 0.9 * k
	sit = pose == "sit"
	if sit:
		hip = 0.47 * k
	z = z0
	for s in (-1, 1):
		if sit:
			kit.rod((s * 0.1 * k, 0, z + hip), (s * 0.1 * k, 0.42 * k, z + hip), 0.07 * k, legs, "thigh", segs=8)
			kit.rod((s * 0.1 * k, 0.42 * k, z + hip), (s * 0.1 * k, 0.42 * k, z + 0.08), 0.055 * k, legs, "shin", segs=8)
			kit.rounded_box((0.1 * k, 0.26 * k, 0.08 * k), (s * 0.1 * k, 0.5 * k, z + 0.04 * k), "plastic_black", "boot", radius=0.03 * k)
		else:
			stride = (0.22 * k * s) if pose == "walk" else 0.0
			kit.rod((s * 0.1 * k, 0, z + hip), (s * 0.1 * k, stride, z + 0.08), 0.07 * k, legs, "leg", segs=8)
			kit.rounded_box((0.1 * k, 0.26 * k, 0.08 * k), (s * 0.1 * k, stride + 0.05 * k, z + 0.04 * k), "plastic_black", "boot", radius=0.03 * k)
	kit.rounded_box((0.38 * k, 0.22 * k, 0.6 * k), (0, 0, z + hip + 0.28 * k), top, "torso", radius=0.07 * k)
	sh = z + hip + 0.52 * k
	for s in (-1, 1):
		if pose == "point" and s > 0:
			kit.rod((s * 0.23 * k, 0, sh), (s * 0.3 * k, 0.55 * k, sh + 0.1 * k), 0.045 * k, top, "arm", segs=8)
			kit.sphere(0.045 * k, (s * 0.3 * k, 0.6 * k, sh + 0.11 * k), skin, "hand", segs=8)
		elif pose == "walk":
			kit.rod((s * 0.23 * k, 0, sh), (s * 0.25 * k, -0.2 * k * s, sh - 0.55 * k), 0.045 * k, top, "arm", segs=8)
			kit.sphere(0.045 * k, (s * 0.25 * k, -0.22 * k * s, sh - 0.6 * k), skin, "hand", segs=8)
		elif sit:
			kit.rod((s * 0.23 * k, 0, sh), (s * 0.2 * k, 0.3 * k, sh - 0.4 * k), 0.045 * k, top, "arm", segs=8)
			kit.sphere(0.045 * k, (s * 0.2 * k, 0.33 * k, sh - 0.42 * k), skin, "hand", segs=8)
		else:
			kit.rod((s * 0.23 * k, 0, sh), (s * 0.26 * k, 0.02, sh - 0.58 * k), 0.045 * k, top, "arm", segs=8)
			kit.sphere(0.045 * k, (s * 0.26 * k, 0.02, sh - 0.63 * k), skin, "hand", segs=8)
	kit.cyl(0.05 * k, 0.08 * k, (0, 0, sh + 0.1 * k), skin, "neck", segs=8)
	kit.sphere(0.11 * k, (0, 0, sh + 0.24 * k), skin, "head", segs=12)
	if hat:
		kit.lathe([(0.125 * k, 0), (0.12 * k, 0.05 * k), (0.08 * k, 0.1 * k), (0.01, 0.12 * k)], (0, 0, sh + 0.27 * k), hat, "hat", segs=12)
		kit.box((0.18 * k, 0.08 * k, 0.012), (0, 0.13 * k, sh + 0.275 * k), hat, "peak")
	if top.startswith("hivis"):
		for dz in (0.12, 0.3):
			kit.box((0.385 * k, 0.225 * k, 0.04 * k), (0, 0, z + hip + dz * k), "steel_stainless", "reflective_band")
	if carry == "case":
		kit.rounded_box((0.4, 0.22, 0.6), (0.45 * k, 0.1, 0.34), "plastic_blue", "suitcase", radius=0.04)
		kit.rod((0.45 * k, 0.0, 0.64), (0.28 * k, 0.02, sh - 0.6 * k), 0.008, "aluminium", "handle", segs=5)
	elif carry == "clipboard":
		kit.box((0.22, 0.02, 0.3), (0, 0.16 * k, z + hip + 0.3 * k), "plywood", "clipboard", rot=(-25, 0, 0))
	elif carry == "shovel":
		kit.rod((0.3 * k, 0.1, 0), (0.3 * k, 0.05, 1.3), 0.018, "softwood", "shaft", segs=6)
		kit.box((0.2, 0.01, 0.28), (0.3 * k, 0.1, 0.14), "steel_painted", "blade")
	kit.socket("head", (0, 0, z0 + height))


_PEOPLE = (("crew.operative", "Site operative", dict()), ("crew.operative_walking", "Site operative, walking", dict(pose="walk", top="hivis_orange")),
	("crew.labourer", "Labourer with shovel", dict(carry="shovel", top="hivis_orange")), ("crew.banksman", "Banksman, signalling", dict(pose="point")),
	("crew.foreman", "Site manager with clipboard", dict(hat="paint_white", carry="clipboard")), ("crew.engineer", "Engineer", dict(hat="paint_white", top="hivis_yellow", legs="fabric_grey")),
	("crew.plant_operator", "Plant operator, seated", dict(pose="sit", top="hivis_orange")), ("crew.demolition", "Demolition operative", dict(top="hivis_orange", hat="hazard_red", legs="hivis_orange")),
	("public.man", "Man, standing", dict(top="fabric_blue", hat="")), ("public.woman", "Woman, standing", dict(top="fabric_red", legs="fabric_grey", hat="", height=1.63)),
	("public.man_walking", "Man, walking", dict(pose="walk", top="fabric_green", hat="")), ("public.woman_walking", "Woman, walking", dict(pose="walk", top="fabric_white", legs="denim", hat="", height=1.63)),
	("public.child", "Child", dict(top="fabric_red", hat="", height=1.2)), ("public.seated", "Person, seated", dict(pose="sit", top="fabric_grey", hat="")),
	("public.passenger", "Passenger with suitcase", dict(pose="walk", top="fabric_blue", hat="", carry="case"), ),
	("staff.police_officer", "Police officer", dict(top="plastic_black", legs="plastic_black", hat="plastic_black")), ("staff.nurse", "Nurse", dict(top="plastic_blue", legs="plastic_blue", hat="")),
	("staff.doctor", "Doctor", dict(top="fabric_white", legs="fabric_grey", hat="", carry="clipboard")), ("staff.pilot", "Pilot", dict(top="plastic_black", legs="plastic_black", hat="paint_white")),
	("staff.office_worker", "Office worker, seated", dict(pose="sit", top="fabric_white", legs="fabric_grey", hat="")), ("staff.teacher", "Teacher, pointing", dict(pose="point", top="fabric_green", legs="fabric_grey", hat="")),
	("staff.pupil", "Pupil, seated", dict(pose="sit", top="fabric_blue", legs="fabric_grey", hat="", height=1.35)), ("staff.security", "Security officer", dict(top="hivis_yellow", legs="plastic_black", hat="plastic_black")))

for _id, _what, _lab, _kw in _STREET:
	reg("street." + _id, street, _lab, what=_what, **_kw)
for _id, _lab, _kw in _CONTEXT:
	reg("context." + _id, context_building, _lab, "building", **_kw)
for _id, _lab, _kw in _DEBRIS:
	reg("demolition." + _id, debris, _lab, "debris", **_kw)
for _id, _lab, _kw in _PEOPLE:
	reg("people." + _id, person, _lab, **_kw)
