"""Site plant rebuilt to the person's reference sheets: cranes, piling rig, earthmoving,
lorries and access machines. Origin: ground centre; machines face +Y. Each machine is split
into stages that move together (upper, boom, hook...) with sockets at the pivots, so the
timelapse can slew, luff and drive them."""
import math

import bpy
from mathutils import Matrix, Vector

import kit
import registry
from registry import register

Y, K, G, D, W = "plant_yellow", "plastic_black", "steel_painted", "steel_dark", "paint_white"


def reg(id, fn, label, *tags, **params):
	"""Registers plant.<id>, replacing an older model of the same id."""
	registry.ASSETS.pop("plant." + id, None)
	register("plant." + id, fn, label, family="plant", tags=("plant", "outdoor", "site") + tags, **params)


# --- shared parts ---------------------------------------------------------------------------

def scale_since(before, s):
	"""Scales everything made since `before` (a set of object names) about the origin."""
	if s == 1.0:
		return
	for ob in bpy.context.scene.collection.objects:
		if ob.name in before:
			continue
		if ob.type == "MESH":
			ob.data.transform(Matrix.Scale(s, 4))
			ob["mass"] = round(ob["mass"] * s ** 3, 3)
		else:
			ob.location = ob.location * s


def names():
	return {ob.name for ob in bpy.context.scene.collection.objects}


def wheel(r, w, at, hub="steel_galvanised"):
	"""A tyre with rounded shoulders and a dished hub, axle along X."""
	h = w / 2
	kit.lathe([(r * 0.56, -h), (r * 0.93, -h), (r, -h * 0.6), (r, h * 0.6), (r * 0.93, h), (r * 0.56, h)], at, "rubber", "tyre", segs=24, rot=(0, 90, 0))
	kit.cyl(r * 0.57, w * 0.72, at, hub, "rim", axis="x", segs=18)
	kit.cyl(r * 0.22, w * 0.9, at, D, "hub_cap", axis="x", segs=10)


def tracks(gauge, l, h, w):
	"""Two crawler tracks with pads, rollers and a frame between them."""
	r = h / 2
	loop = [(-l / 2 + r + r * math.cos(math.radians(a)), r + r * math.sin(math.radians(a))) for a in range(90, 271, 30)]
	loop += [(l / 2 - r + r * math.cos(math.radians(a)), r + r * math.sin(math.radians(a))) for a in range(-90, 91, 30)]
	for s in (-1, 1):
		x = s * gauge / 2
		with kit.hollow(0.45):
			kit.prism(loop, w, (x, 0, 0), D, "track", axis="x")
		n = max(6, int((l - h) / 0.2))
		for i in range(n + 1):
			y = -l / 2 + r + (l - h) * i / n
			kit.box((w + 0.05, 0.13, 0.04), (x, y, h + 0.015), K, "track_pad")
			kit.box((w + 0.05, 0.13, 0.04), (x, y, 0.02), K, "track_pad")
		for a in range(-60, 61, 30):
			for e, b in ((1, a), (-1, 180 - a)):
				c, sn = math.cos(math.radians(b)), math.sin(math.radians(b))
				kit.box((w + 0.05, 0.04, 0.13), (x, e * (l / 2 - r) + (r + 0.015) * c * (1 if e > 0 else 1), r + (r + 0.015) * sn), K, "track_pad", rot=(b if e > 0 else b, 0, 0))
		kit.box((w * 0.55, l - h * 1.1, h * 0.42), (x, 0, r), G, "track_frame")
		for y in (-l / 2 + r, l / 2 - r):
			kit.cyl(r * 0.78, w * 0.7, (x, y, r), G, "sprocket", axis="x", segs=14)
	kit.box((gauge - w, l * 0.42, h * 0.5), (0, 0, r + 0.05), D, "car_body")


def glazed_cab(w, d, h, at, paint=W, roof=None, seat=True):
	"""An operator's cab: solid lower panels, glass above, corner posts and a roof."""
	x, y, z = at
	with kit.hollow(0.08):
		kit.box((w, d, h * 0.36), (x, y, z + h * 0.18), paint, "cab_base")
		kit.rounded_box((w + 0.06, d + 0.08, 0.1), (x, y, z + h - 0.05), roof or paint, "cab_roof", radius=0.03)
		for sx in (-1, 1):
			for sy in (-1, 1):
				kit.box((0.07, 0.07, h * 0.6), (x + sx * (w / 2 - 0.035), y + sy * (d / 2 - 0.035), z + h * 0.65), paint, "cab_post")
		kit.box((0.05, d, 0.05), (x - w / 2 + 0.025, y, z + h * 0.62), paint, "cab_rail")
	kit.box((w - 0.05, d - 0.05, h * 0.57), (x, y, z + h * 0.645), "glass_dark", "cab_glass")
	if seat:
		kit.box((0.5, 0.5, 0.5), (x, y - d * 0.15, z + h * 0.3), K, "seat")


def ram(a, b, r, split=0.55):
	"""A hydraulic ram: a dark barrel and a bright rod."""
	a, b = Vector(a), Vector(b)
	m = a + (b - a) * split
	kit.rod(tuple(a), tuple(m), r, D, "ram_barrel", segs=10)
	kit.rod(tuple(m), tuple(b), r * 0.55, "steel_stainless", "ram_rod", segs=8)


def truss(a, b, w, h, chord=0.1, web=0.05, slot=Y, name="truss", tri=False, bays=None, up=(0, 0, 1), w2=None, h2=None):
	"""A lattice between two points: square, or triangular with its apex up (crane jibs).
	w2 and h2 taper it toward b."""
	a, b = Vector(a), Vector(b)
	t = (b - a).normalized()
	side = t.cross(Vector(up))
	if side.length < 1e-6:
		side = Vector((1, 0, 0))
	side.normalize()
	u = side.cross(t).normalized()
	length = (b - a).length
	w2, h2 = w if w2 is None else w2, h if h2 is None else h2
	base = [(-0.5, 0.0), (0.5, 0.0), (0.0, 1.0)] if tri else [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)]
	def p(c, d):
		f = d / length
		return tuple(a + t * d + side * c[0] * (w + (w2 - w) * f) + u * c[1] * (h + (h2 - h) * f))
	for c in base:
		kit.strut(p(c, 0), p(c, length), chord, slot=slot, name=name + "_chord")
	bays = bays or max(1, round(length / max(w, h)))
	st = length / bays
	n = len(base)
	for i in range(bays):
		for k in range(n):
			c0, c1 = base[k], base[(k + 1) % n]
			if i % 2:
				c0, c1 = c1, c0
			kit.strut(p(c0, i * st), p(c1, (i + 1) * st), web, slot=slot, name=name + "_web")
			kit.strut(p(base[k], (i + 1) * st), p(base[(k + 1) % n], (i + 1) * st), web, slot=slot, name=name + "_tie")


def hook_block(at, s=1.0, paint=Y):
	x, y, z = at
	kit.rounded_box((0.3 * s, 0.22 * s, 0.75 * s), (x, y, z + 0.6 * s), paint, "hook_block", radius=0.06 * s)
	kit.cyl(0.05 * s, 0.25 * s, (x, y, z + 0.18 * s), D, "hook_shank", segs=8)
	kit.sweep(kit.arc((x, y, z + 0.02 * s), 0.11 * s, 100, 370, 10, plane="xz"), kit.circle(0.035 * s, 6), D, "hook", up=(0, 1, 0))


def rails(pts, h=1.1, r=0.02, slot=Y, name="rail", mid=True, posts=True):
	"""A guard rail along a line of points (posts at each point)."""
	for a, b in zip(pts, pts[1:]):
		kit.rod((a[0], a[1], a[2] + h), (b[0], b[1], b[2] + h), r, slot, name, segs=6)
		if mid:
			kit.rod((a[0], a[1], a[2] + h * 0.5), (b[0], b[1], b[2] + h * 0.5), r * 0.8, slot, name, segs=6)
	if posts:
		for a in pts:
			kit.rod(a, (a[0], a[1], a[2] + h), r, slot, name + "_post", segs=6)


def house(w, l, h, at, cab_side=-1, paint=Y, weights=3, rail=True):
	"""A crane or rig upper works: machinery house, white cab at the front, counterweight
	slabs at the back and a handrail."""
	x, y, z = at
	kit.cyl(min(w, l) * 0.3, 0.25, (x, y + l * 0.1, z - 0.12), D, "slew_ring", segs=24)
	with kit.hollow(0.25):
		kit.box((w, l, 0.3), (x, y, z + 0.15), paint, "deck")
		kit.rounded_box((w * 0.62, l * 0.72, h), (x - cab_side * w * 0.17, y - l * 0.12, z + 0.3 + h / 2), paint, "house", radius=0.08)
		for i in range(4):
			kit.box((0.02, 0.5, 0.06), (x - cab_side * (w * 0.48 + 0.005), y - l * 0.25, z + 0.7 + i * 0.16), D, "louvre")
		kit.cyl(0.3, w * 0.4, (x - cab_side * w * 0.15, y + l * 0.05, z + 0.3 + h), "steel_galvanised", "winch", axis="x", segs=14)
	glazed_cab(w * 0.34, l * 0.36, h + 0.35, (x + cab_side * w * 0.31, y + l * 0.3, z + 0.3), W)
	for i in range(weights):
		kit.rounded_box((w * 0.95, 0.6, 0.32), (x, y - l / 2 - 0.3, z + 0.3 + 0.17 + i * 0.34), "steel_galvanised", "counterweight", radius=0.04)
	if rail:
		sx = x + cab_side * w / 2
		rails([(sx, y - l * 0.45, z + 0.3), (sx, y + l * 0.1, z + 0.3)], 1.0, 0.02, "steel_galvanised", "handrail")


# --- tower cranes ---------------------------------------------------------------------------

def tower_crane(height=30.0, jib=40.0, counter=12.0, top="high", cabin="suspended", base="ballast", w=1.8):
	"""A tower crane, jib along +Y. top: high (cat head and pendants) or flat. cabin:
	suspended under the jib or on the side. base: ballasted cross frame or a cast pedestal."""
	zb = 0.9
	with kit.stage("base"):
		if base == "cast":
			kit.box((4.2, 4.2, zb), (0, 0, zb / 2), "concrete", "pedestal")
		else:
			for ax in ("x", "y"):
				kit.i_section(0.4, 0.5, 0.05, 0.04, 6.4, (0, 0, 0.45), Y, "base_beam", axis=ax)
			for sx in (-1, 1):
				for sy in (-1, 1):
					kit.strut((sx * 3.0 if sy > 0 else 0, 0 if sy > 0 else sx * 3.0, 0.7), (sx * w / 2 if sy > 0 else 0, 0 if sy > 0 else sx * w / 2, 5.0), 0.16, slot=Y, name="base_strut")
					kit.box((0.5, 0.5, 0.2), (sx * 3.1 if sy > 0 else 0, 0 if sy > 0 else sx * 3.1, 0.1), D, "foot")
				for i in range(3):
					kit.box((1.6, 4.6, 0.32), (sx * 1.9, 0, 0.88 + i * 0.34), "concrete", "ballast")
	with kit.stage("mast"):
		truss((0, 0, zb), (0, 0, height), w, w, 0.14, 0.07, Y, "mast", bays=max(2, round((height - zb) / w)))
		kit.rod((w / 2 - 0.25, -w / 2 + 0.25, zb), (w / 2 - 0.25, -w / 2 + 0.25, height), 0.03, "steel_galvanised", "ladder", segs=6)
	zj = height + 1.2
	with kit.stage("slew"):
		kit.cyl(w * 0.62, 0.35, (0, 0, height + 0.18), D, "slew_ring", segs=24)
		kit.box((w + 0.3, w + 0.3, 0.75), (0, 0, height + 0.75), Y, "slew_unit")
		jh = 1.5 if top == "high" else 2.1
		if top == "high":
			apex = (0, -0.2, zj + 8.0)
			for sx in (-1, 1):
				for sy in (-1, 1):
					kit.strut((sx * w / 2, sy * w / 2, zj - 0.1), apex, 0.14, slot=Y, name="cat_head")
			for f in (0.3, 0.55, 0.78):
				hw = w / 2 * (1 - f)
				zz = zj + 8.0 * f
				for k in range(4):
					c = [(-hw, -hw), (hw, -hw), (hw, hw), (-hw, hw)]
					kit.strut((c[k][0], c[k][1] - 0.2 * f, zz), (c[(k + 1) % 4][0], c[(k + 1) % 4][1] - 0.2 * f, zz), 0.07, slot=Y, name="cat_head_tie")
			kit.rod(apex, (0, jib * 0.58, zj + jh), 0.03, D, "pendant", segs=6)
			kit.rod(apex, (0, jib * 0.28, zj + jh), 0.03, D, "pendant", segs=6)
			for sx in (-1, 1):
				kit.rod(apex, (sx * 0.6, -counter + 1.2, zj + 0.2), 0.03, D, "pendant", segs=6)
		else:
			truss((0, 0, zj - 0.1), (0, 0, zj + jh), w, w, 0.14, 0.07, Y, "head", bays=1)
			kit.strut((0, 0, zj + jh), (0, -counter * 0.55, zj + 0.3), 0.14, slot=Y, name="back_stay")
		truss((0, w / 2, zj), (0, jib, zj), 1.3, jh, 0.13, 0.06, Y, "jib", tri=True, bays=max(4, round(jib / 1.6)), h2=jh * 0.75)
		kit.box((0.5, 0.3, 0.5), (0, jib + 0.1, zj + 0.3), Y, "jib_tip")
		for sx in (-1, 1):
			kit.i_section(0.2, 0.35, 0.03, 0.02, counter, (sx * 0.65, -counter / 2, zj), Y, "counter_jib")
		kit.box((1.5, counter - 0.4, 0.05), (0, -counter / 2, zj + 0.2), "steel_galvanised", "walkway")
		for sx in (-1, 1):
			rails([(sx * 0.75, -counter + 0.2 + i * (counter - 1.6) / 5, zj + 0.2) for i in range(6)], 1.0, 0.02, Y, "handrail")
		for i in range(4):
			kit.box((1.5, 0.38, 2.3), (0, -counter + 0.5 + i * 0.44, zj - 0.75), "concrete", "counterweight")
		kit.box((1.2, 1.6, 0.9), (0, -counter * 0.45, zj + 0.7), "steel_galvanised", "winch_house")
		if cabin == "suspended":
			glazed_cab(1.4, 1.7, 1.9, (w / 2 + 0.75, 1.0, zj - 2.3), W)
			kit.box((0.9, 0.9, 0.3), (w / 2 + 0.4, 0.8, zj - 0.3), Y, "cab_hanger")
		else:
			glazed_cab(1.4, 1.7, 1.9, (w / 2 + 0.85, 0.2, zj - 0.4), W)
			kit.box((0.5, 1.2, 0.15), (w / 2 + 0.2, 0.2, zj - 0.45), Y, "cab_bracket")
	ty = jib * 0.6
	hz = height * 0.42
	with kit.stage("trolley"):
		kit.box((1.3, 1.3, 0.18), (0, ty, zj - 0.12), Y, "trolley")
		for sx in (-1, 1):
			for sy in (-1, 1):
				kit.cyl(0.1, 0.06, (sx * 0.6, ty + sy * 0.5, zj - 0.02), D, "trolley_wheel", axis="x", segs=10)
	with kit.stage("hook"):
		for sx in (-1, 1):
			kit.rod((sx * 0.12, ty, zj - 0.2), (sx * 0.12, ty, hz + 1.2), 0.012, D, "hoist_rope", segs=5)
		hook_block((0, ty, hz), 1.3, W)
	kit.socket("slew", (0, 0, height + 0.35))
	kit.socket("trolley", (0, ty, zj - 0.12))
	kit.socket("hook", (0, ty, hz))
	kit.socket("jib_tip", (0, jib, zj))
	# The trolley can travel between trolley_min and trolley_max.
	kit.socket("trolley_min", (0, 3.0, zj - 0.12))
	kit.socket("trolley_max", (0, jib - 1.5, zj - 0.12))


# --- mobile, crawler and piling ---------------------------------------------------------------

def mobile_crane(axles=3, raised=True, angle=68.0, ext=4):
	"""An all-terrain telescopic crane on a wheeled carrier, boom over the front."""
	nf = 1 if axles <= 3 else 2
	nr = axles - nf
	lc = 4.6 + axles * 1.65
	f = lc / 2
	fy = [f - 3.0 - i * 1.65 for i in range(nf)]
	ry = [-f + 1.25 + i * 1.65 for i in range(nr)]
	with kit.stage("carrier"):
		kit.box((2.5, lc - 0.4, 0.55), (0, -0.2, 1.2), D, "carrier_deck")
		cabp = [(f - 2.3, 0.75), (f, 0.75), (f, 1.5), (f - 0.25, 2.55), (f - 0.5, 2.65), (f - 2.3, 2.65)]
		with kit.hollow(0.12):
			kit.prism(cabp, 2.6, (0, 0, 0), Y, "carrier_cab", axis="x")
			kit.box((2.5, 1.6, 0.5), (0, f - 3.1, 1.72), Y, "engine_cover")
		kit.strut((0, f - 0.02, 1.62), (0, f - 0.235, 2.5), 2.3, 0.03, "glass_dark", "windscreen")
		for sx in (-1, 1):
			kit.box((0.02, 1.1, 0.7), (sx * 1.305, f - 1.1, 2.1), "glass_dark", "side_window")
			kit.box((0.4, 0.04, 0.22), (sx * 0.95, f + 0.01, 1.0), "hazard_red", "lamp")
			kit.box((0.3, 0.04, 0.16), (sx * 0.95, f + 0.012, 0.86), W, "lamp")
		kit.box((2.2, 0.05, 0.4), (0, f + 0.005, 1.25), D, "grille")
	with kit.stage("wheels"):
		for y in fy + ry:
			for sx in (-1, 1):
				wheel(0.66, 0.5, (sx * 1.05, y, 0.66), "steel_galvanised")
	yt = (ry[0] + ry[-1]) / 2
	with kit.stage("outriggers"):
		for y in (ry[-1] + 0.95 if ry[-1] + 0.95 < f - 3.9 else ry[-1] + 0.83, -f + 0.25):
			for sx in (-1, 1):
				if raised:
					kit.box((2.4, 0.3, 0.3), (sx * 2.3, y, 1.15), G, "outrigger_beam")
					kit.box((0.34, 0.36, 0.9), (sx * 3.4, y, 1.2), Y, "jack")
					kit.cyl(0.07, 0.8, (sx * 3.4, y, 0.42), "steel_stainless", "jack_leg", segs=8)
					kit.cyl(0.28, 0.06, (sx * 3.4, y, 0.03), "steel_galvanised", "pad", segs=14)
				else:
					kit.box((0.3, 0.36, 0.9), (sx * 1.3, y, 1.1), Y, "jack")
	bz = 2.75
	pivot = (0.25, yt - 1.3, bz)
	with kit.stage("upper"):
		kit.cyl(1.0, 0.22, (0, yt, 1.58), D, "slew_ring", segs=24)
		with kit.hollow(0.2):
			kit.box((2.5, 3.6, 0.5), (0, yt - 0.3, 1.95), Y, "upper_deck")
			kit.prism([(yt - 2.1, 2.2), (yt - 0.2, 2.2), (yt - 0.5, 3.0), (yt - 1.7, 3.0)], 0.9, (0.25, 0, 0), Y, "boom_foot", axis="x")
			kit.rounded_box((3.0, 1.0, 0.75), (0, yt - 2.45, 2.1), Y, "counterweight", radius=0.08)
		glazed_cab(0.95, 1.7, 1.75, (-0.85, yt + 0.7, 2.2), Y)
	bl = max(6.5, lc * 0.82)
	a = math.radians(angle if raised else 3.0)
	d = Vector((0, math.cos(a), math.sin(a)))
	p0 = Vector(pivot)
	with kit.stage("boom"):
		kit.strut(tuple(p0 - d * 0.6), tuple(p0 + d * bl), 0.8, 0.9, Y, "boom_base")
		tip = p0 + d * bl
		if raised:
			for i in range(ext):
				s0 = p0 + d * (bl * 0.25 + (i + 1) * bl * 0.62)
				s1 = s0 + d * bl * 0.74
				sz = 0.7 - i * 0.07
				kit.strut(tuple(s0), tuple(s1), sz, sz + 0.1, "steel_galvanised", "boom_section")
				kit.strut(tuple(s1 - d * 0.12), tuple(s1), sz + 0.05, sz + 0.15, D, "boom_collar")
				tip = s1
		else:
			kit.strut(tuple(tip - d * 0.3), tuple(tip + d * 0.5), 0.6, 0.75, "steel_galvanised", "boom_head")
			tip = tip + d * 0.5
		kit.strut(tuple(tip - d * 0.1), tuple(tip + d * 0.35), 0.5, 0.5, Y, "boom_tip")
		tip = tip + d * 0.25
		lift = p0 + d * bl * 0.45
		ram((0.25, yt + 0.4, 2.3), tuple(lift - Vector((0, 0, 0.45))), 0.16)
	with kit.stage("hook"):
		hz = max(1.3, tip.z * 0.4) if raised else tip.z - 1.9
		kit.rod((0.25, tip.y + 0.1, tip.z - 0.2), (0.25, tip.y + 0.1, hz + 1.0), 0.015, D, "hoist_rope", segs=5)
		hook_block((0.25, tip.y + 0.1, hz), 1.0, Y)
	kit.socket("slew", (0, yt, 1.7))
	kit.socket("boom_pivot", pivot)
	kit.socket("boom_tip", tuple(tip))
	kit.socket("hook", (0.25, tip.y + 0.1, hz))


def crawler_crane(boom=30.0, angle=65.0):
	"""A lattice boom crawler crane with a gantry and pendants."""
	with kit.stage("tracks"):
		tracks(3.6, 6.2, 1.05, 0.85)
	z0 = 1.25
	with kit.stage("upper"):
		house(3.3, 4.8, 1.5, (0, -0.4, z0), cab_side=1)
	a = math.radians(angle)
	foot = Vector((0, 1.7, z0 + 0.6))
	d = Vector((0, math.cos(a), math.sin(a)))
	tip = foot + d * boom
	apex = Vector((0, -2.0, z0 + 5.6))
	with kit.stage("boom"):
		truss(tuple(foot), tuple(foot + d * 3.0), 0.5, 0.5, 0.14, 0.07, Y, "boom", w2=1.5, h2=1.5, bays=2)
		truss(tuple(foot + d * 3.0), tuple(tip - d * 3.0), 1.5, 1.5, 0.13, 0.06, Y, "boom", bays=max(4, round((boom - 6.0) / 1.5)))
		truss(tuple(tip - d * 3.0), tuple(tip), 1.5, 1.5, 0.14, 0.07, Y, "boom", w2=0.6, h2=0.6, bays=2)
		kit.rounded_box((0.7, 0.9, 0.9), tuple(tip + d * 0.3), Y, "boom_head", radius=0.1)
		kit.cyl(0.35, 0.5, tuple(tip + d * 0.45), "steel_galvanised", "sheave", axis="x", segs=14)
	with kit.stage("upper"):
		for sx in (-1, 1):
			kit.strut((sx * 0.9, 0.2, z0 + 1.6), (sx * 0.5, apex.y, apex.z), 0.2, slot=K, name="gantry")
			kit.strut((sx * 0.9, -2.6, z0 + 1.0), (sx * 0.5, apex.y, apex.z), 0.16, slot=K, name="gantry_back")
		kit.cyl(0.3, 1.2, tuple(apex), "steel_galvanised", "gantry_sheave", axis="x", segs=14)
		kit.box((1.3, 0.2, 0.2), (0, apex.y + 0.9, z0 + 3.4), K, "gantry_tie")
	with kit.stage("boom"):
		for sx in (-1, 1):
			kit.rod((sx * 0.45, apex.y, apex.z), (sx * 0.3, tip.y, tip.z), 0.025, D, "pendant", segs=6)
	hz = max(1.5, tip.z * 0.2)
	hy = tip.y + d.y * 0.8
	with kit.stage("hook"):
		kit.rod((0, hy, tip.z + d.z * 0.3), (0, hy, hz + 1.2), 0.018, D, "hoist_rope", segs=5)
		hook_block((0, hy, hz), 1.3, Y)
	kit.socket("slew", (0, 0, z0))
	kit.socket("boom_pivot", tuple(foot))
	kit.socket("boom_tip", tuple(tip))
	kit.socket("hook", (0, hy, hz))


def piling_rig(stowed=False, mast=17.0):
	"""A rotary bored piling rig: crawler base, a tall leader with a rotary head, kelly bar
	and auger over a casing. Stowed, the leader lies back over the cab for travel."""
	with kit.stage("tracks"):
		tracks(3.2, 5.0, 0.95, 0.75)
	z0 = 1.15
	with kit.stage("upper"):
		house(3.0, 4.2, 1.4, (0, -0.5, z0), cab_side=1, weights=2)
	if stowed:
		with kit.stage("mast"):
			zc = z0 + 2.9
			kit.box((0.6, mast, 0.6), (0, 0.6, zc), "steel_galvanised", "leader")
			kit.box((0.9, 0.9, 0.8), (0, 0.6 + mast / 2 - 0.3, zc - 0.5), "steel_galvanised", "head")
			for sx in (-1, 1):
				kit.cyl(0.3, 0.16, (sx * 0.3, 0.6 + mast / 2 + 0.25, zc - 0.6), "steel_galvanised", "sheave", axis="x", segs=14)
			kit.box((0.9, 1.0, 1.0), (0, 3.4, zc - 0.75), "steel_galvanised", "rotary_carriage")
			for sx in (-1, 1):
				kit.strut((sx * 0.7, 1.4, z0 + 0.6), (sx * 0.3, 2.8, zc - 0.3), 0.3, slot="steel_galvanised", name="kinematics")
				ram((sx * 0.5, 0.2, z0 + 1.2), (sx * 0.25, -1.5, zc - 0.3), 0.1)
			kit.box((0.7, 0.5, 0.5), (0, 0.6 - mast / 2 + 0.25, zc), "steel_galvanised", "foot")
		kit.socket("slew", (0, 0, z0))
		return
	ym, yk = 3.1, 4.05
	with kit.stage("mast"):
		kit.box((0.6, 0.6, mast), (0, ym, 0.3 + mast / 2), D, "leader")
		kit.box((0.9, 0.8, 0.25), (0, ym, 0.3), D, "leader_foot")
		top = 0.3 + mast
		kit.box((0.9, 1.8, 0.35), (0, ym + 0.3, top + 0.15), "steel_galvanised", "head")
		kit.strut((0, ym + 0.2, top + 0.3), (0, ym - 0.7, top + 1.3), 0.3, slot="steel_galvanised", name="head_arm")
		for sx in (-1, 1):
			kit.cyl(0.32, 0.14, (sx * 0.25, yk, top + 0.2), "steel_galvanised", "sheave", axis="x", segs=14)
			kit.cyl(0.32, 0.14, (sx * 0.25, ym - 0.75, top + 1.3), "steel_galvanised", "sheave", axis="x", segs=14)
			kit.rod((sx * 0.25, ym - 1.0, top + 1.2), (sx * 0.5, 0.3, z0 + 1.9), 0.012, D, "rope", segs=5)
			kit.strut((sx * 0.75, 1.2, z0 + 0.9), (sx * 0.4, ym - 0.3, 4.6), 0.28, slot="steel_galvanised", name="kinematics")
			ram((sx * 0.7, 0.6, z0 + 1.6), (sx * 0.25, ym - 0.3, 9.5), 0.11, 0.6)
		kit.box((1.1, 0.5, 1.4), (0, ym - 0.4, 4.6), "steel_galvanised", "kinematic_head")
	with kit.stage("rotary"):
		hz = 4.2
		kit.box((0.8, 0.5, 1.4), (0, ym + 0.5, hz + 0.6), "steel_galvanised", "rotary_carriage")
		kit.cyl(0.55, 1.3, (0, yk, hz + 0.2), K, "rotary_head", segs=20)
		kit.cyl(0.68, 0.2, (0, yk, hz + 0.9), "steel_galvanised", "rotary_flange", segs=20)
		kit.cyl(0.68, 0.2, (0, yk, hz - 0.5), "steel_galvanised", "rotary_flange", segs=20)
	with kit.stage("kelly"):
		kit.cyl(0.15, 8.5, (0, yk, hz + 0.9 + 4.25), "steel_galvanised", "kelly_bar", segs=14)
		kit.cyl(0.24, 0.5, (0, yk, hz + 9.4), "steel_galvanised", "kelly_swivel", segs=14, r2=0.12)
		kit.rod((0, yk, hz + 9.6), (0, yk, top + 0.1), 0.014, D, "rope", segs=5)
		kit.cyl(0.07, 1.6, (0, yk, hz - 1.3), D, "auger_stem", segs=8)
		for i in range(3):
			kit.cyl(0.42, 0.16, (0, yk, hz - 0.95 - i * 0.42), D, "auger_flight", segs=16, r2=0.1)
	with kit.stage("casing"):
		with kit.hollow(1.0):
			kit.tube(0.5, 2.5, (0, yk, 1.25), D, "casing", wall=0.04, segs=20)
			kit.tube(0.56, 0.3, (0, yk, 0.15), D, "casing_shoe", wall=0.1, segs=20)
	kit.socket("slew", (0, 0, z0))
	kit.socket("bore", (0, yk, 0))


# --- earthmoving ---------------------------------------------------------------------------------

def excavator(s=1.0, tool="bucket"):
	"""A tracked excavator, about 20 t at s = 1."""
	before = names()
	with kit.stage("tracks"):
		tracks(2.4, 4.3, 0.85, 0.6)
	with kit.stage("upper"):
		kit.cyl(0.75, 0.2, (0, 0, 0.98), D, "slew_ring", segs=24)
		with kit.hollow(0.25):
			kit.box((2.7, 3.7, 0.35), (0, -0.6, 1.25), Y, "deck")
			kit.rounded_box((2.7, 2.0, 1.05), (0, -1.45, 1.95), Y, "engine_house", radius=0.16)
			kit.box((2.0, 1.2, 0.04), (0, -1.45, 2.49), K, "engine_hatch")
			kit.rounded_box((2.72, 0.55, 0.95), (0, -2.55, 1.6), D, "counterweight", radius=0.12)
			kit.rounded_box((0.95, 1.7, 0.75), (0.87, 0.35, 1.8), Y, "tank", radius=0.08)
		glazed_cab(1.0, 1.65, 1.7, (-0.85, 0.4, 1.42), W)
	with kit.stage("boom"):
		kit.prism([(0.75, 1.5), (1.3, 1.45), (3.5, 4.35), (6.1, 3.35), (6.25, 3.85), (3.35, 5.3), (2.7, 5.0)], 0.5, (0.15, 0, 0), Y, "boom", axis="x")
		for sx in (-1, 1):
			ram((0.15 + sx * 0.38, 1.45, 1.5), (0.15 + sx * 0.38, 2.75, 3.75), 0.09)
		ram((0.15, 3.5, 5.42), (0.15, 5.95, 4.35), 0.09)
	with kit.stage("stick"):
		kit.prism([(5.85, 4.45), (6.5, 4.05), (5.5, 1.0), (5.12, 1.05)], 0.36, (0.15, 0, 0), Y, "stick", axis="x")
		ram((0.15, 6.35, 4.0), (0.15, 5.75, 1.75), 0.07)
	with kit.stage("bucket"):
		if tool == "breaker":
			kit.rounded_box((0.45, 0.5, 1.3), (0.15, 5.2, 0.75), D, "breaker_body", radius=0.06, rot=(-10, 0, 0))
			kit.cyl(0.07, 0.7, (0.15, 5.05, 0.1), "steel_stainless", "chisel", segs=8, r2=0.02)
		else:
			kit.prism([(5.6, 1.1), (5.0, 1.2), (4.3, 0.75), (4.2, 0.15), (4.65, 0.05), (4.72, 0.55), (5.2, 0.8)], 1.15, (0.15, 0, 0), D, "bucket", axis="x")
			for i in range(5):
				kit.box((0.08, 0.2, 0.06), (0.15 - 0.46 + i * 0.23, 4.72, 0.08), "steel_galvanised", "tooth", rot=(25, 0, 0))
	kit.socket("slew", (0, 0, 1.0))
	kit.socket("boom_pivot", (0.15, 1.0, 1.5))
	kit.socket("stick_pivot", (0.15, 6.1, 3.6))
	kit.socket("bucket_pivot", (0.15, 5.3, 1.05))
	scale_since(before, s)


def wheel_loader():
	"""An articulated wheel loader with its bucket on the ground."""
	with kit.stage("wheels"):
		for sx in (-1, 1):
			for y in (-1.6, 1.6):
				wheel(0.82, 0.62, (sx * 1.1, y, 0.82), "steel_galvanised")
	with kit.stage("body"):
		with kit.hollow(0.25):
			kit.box((1.5, 4.4, 0.75), (0, -0.2, 1.15), D, "frame")
			kit.rounded_box((2.2, 2.3, 1.15), (0, -2.1, 2.1), Y, "engine_hood", radius=0.14)
			kit.box((1.5, 1.4, 0.04), (0, -2.2, 2.69), K, "hood_grille")
			kit.rounded_box((2.4, 0.5, 0.8), (0, -3.35, 1.3), D, "counterweight", radius=0.08)
			kit.box((1.7, 1.7, 0.5), (0, -0.4, 1.75), Y, "cab_plinth")
			for sx in (-1, 1):
				for y in (-1.6, 1.6):
					kit.box((0.75, 1.5, 0.08), (sx * 1.15, y, 1.78), G, "mudguard")
					kit.box((0.75, 0.08, 0.5), (sx * 1.15, y - 0.75 * (1 if y < 0 else -1), 1.55), G, "mudguard_drop")
		glazed_cab(1.6, 1.6, 1.75, (0, -0.4, 2.0), Y, roof=W)
		kit.rod((0.8, -2.9, 2.6), (0.8, -2.9, 3.3), 0.06, D, "exhaust", segs=8)
	with kit.stage("arms"):
		for sx in (-1, 1):
			kit.prism([(0.3, 2.2), (0.8, 2.5), (3.7, 1.0), (3.45, 0.55), (2.1, 1.15), (1.0, 1.9)], 0.2, (sx * 0.78, 0, 0), Y, "lift_arm", axis="x")
			kit.box((0.35, 0.5, 1.0), (sx * 0.78, 0.55, 2.0), D, "arm_tower")
			ram((sx * 0.55, 0.9, 1.3), (sx * 0.55, 2.4, 1.3), 0.08)
		ram((0, 1.0, 2.3), (0, 3.2, 1.5), 0.08)
		kit.box((1.5, 0.2, 0.2), (0, 2.3, 1.2), Y, "arm_tie")
	with kit.stage("bucket"):
		kit.prism([(3.35, 1.45), (3.5, 0.2), (4.65, 0.06), (4.75, 0.16), (3.95, 0.55), (3.75, 1.55)], 2.75, (0, 0, 0), D, "bucket", axis="x")
		for sx in (-1, 1):
			kit.prism([(3.5, 0.2), (4.7, 0.1), (3.75, 1.55), (3.35, 1.45)], 0.05, (sx * 1.38, 0, 0), D, "bucket_side", axis="x")
	kit.socket("arm_pivot", (0, 0.5, 2.3))
	kit.socket("bucket_pivot", (0, 3.5, 0.8))


def road_roller():
	"""A single drum vibratory roller."""
	with kit.stage("drum"):
		kit.cyl(0.78, 2.1, (0, 1.9, 0.78), D, "drum", axis="x", segs=28)
		for sx in (-1, 1):
			kit.cyl(0.7, 0.04, (sx * 1.06, 1.9, 0.78), "steel_galvanised", "drum_end", axis="x", segs=24)
	with kit.stage("body"):
		for sx in (-1, 1):
			kit.box((0.16, 2.5, 0.55), (sx * 1.2, 1.9, 0.85), Y, "yoke")
			kit.cyl(0.13, 0.05, (sx * 1.29, 1.9, 0.78), "steel_galvanised", "drum_boss", axis="x", segs=12)
		kit.box((2.56, 0.18, 0.55), (0, 3.15, 0.85), Y, "yoke_front")
		kit.box((2.56, 0.18, 0.55), (0, 0.65, 0.85), Y, "yoke_back")
		with kit.hollow(0.2):
			kit.prism([(0.75, 1.15), (3.05, 1.15), (3.05, 1.45), (2.6, 1.85), (1.2, 1.85), (0.75, 1.45)], 2.2, (0, 0, 0), K, "drum_hood", axis="x")
			kit.box((1.0, 1.0, 0.6), (0, 0.2, 1.0), D, "articulation")
			kit.box((1.7, 1.6, 0.5), (0, -0.4, 1.45), K, "cab_plinth")
			kit.prism([(-3.0, 1.25), (-1.25, 1.25), (-1.25, 2.3), (-1.7, 2.45), (-2.6, 2.3), (-3.0, 1.9)], 1.9, (0, 0, 0), Y, "engine_cover", axis="x")
			kit.box((2.3, 0.3, 0.25), (0, -3.1, 1.3), Y, "rear_bumper")
		glazed_cab(1.6, 1.5, 1.8, (0, -0.4, 1.7), K)
		kit.rod((0.6, -1.9, 2.4), (0.6, -1.9, 3.05), 0.06, G, "exhaust", segs=8)
		kit.rod((0.6, -1.9, 3.05), (0.6, -2.1, 3.25), 0.06, G, "exhaust", segs=8)
	with kit.stage("wheels"):
		for sx in (-1, 1):
			wheel(0.78, 0.6, (sx * 0.95, -1.9, 0.78), "steel_galvanised")
	kit.socket("drum", (0, 1.9, 0.78))


def forklift(lift=0.0, mast=2.2):
	"""A counterbalance forklift. `lift` raises the carriage; above the mast height the inner
	mast stages follow it up."""
	with kit.stage("wheels"):
		for sx in (-1, 1):
			wheel(0.4, 0.3, (sx * 0.52, 0.78, 0.4), D)
			wheel(0.32, 0.24, (sx * 0.5, -0.85, 0.32), D)
	with kit.stage("body"):
		with kit.hollow(0.5):
			kit.box((1.2, 1.3, 0.35), (0, 0.2, 0.55), D, "floor")
			kit.prism([(-1.5, 0.35), (-0.2, 0.35), (-0.2, 1.25), (-0.5, 1.45), (-1.25, 1.45), (-1.5, 1.2)], 1.3, (0, 0, 0), Y, "counterweight", axis="x")
			kit.box((1.3, 0.25, 0.5), (0, 1.0, 0.75), Y, "front_cowl")
		kit.rounded_box((0.55, 0.55, 0.14), (0, -0.45, 1.52), K, "seat", radius=0.04)
		kit.rounded_box((0.55, 0.14, 0.55), (0, -0.72, 1.85), K, "seat_back", radius=0.04)
		kit.rod((0, 0.75, 0.9), (0, 0.4, 1.55), 0.025, K, "steering_column", segs=6)
		kit.cyl(0.19, 0.03, (0, 0.38, 1.58), K, "steering_wheel", segs=14, rot=(-30, 0, 0))
		for sx in (-1, 1):
			kit.strut((sx * 0.58, 0.95, 0.95), (sx * 0.55, 0.55, 2.2), 0.08, slot=K, name="guard_post")
			kit.strut((sx * 0.58, -1.1, 1.4), (sx * 0.55, -0.85, 2.2), 0.08, slot=K, name="guard_post")
			kit.box((0.08, 1.5, 0.08), (sx * 0.55, -0.15, 2.22), K, "guard_side")
		for i in range(6):
			kit.box((1.1, 0.06, 0.05), (0, -0.85 + i * 0.28, 2.22), K, "guard_bar")
	top = max(mast, lift + 0.7)
	with kit.stage("mast"):
		for sx in (-1, 1):
			kit.box((0.1, 0.14, mast), (sx * 0.38, 1.22, 0.12 + mast / 2), K, "mast_outer")
			if top > mast:
				kit.box((0.08, 0.1, top - 0.6), (sx * 0.28, 1.24, 0.72 + (top - 0.6) / 2), D, "mast_inner")
		kit.box((0.86, 0.1, 0.1), (0, 1.22, mast + 0.07), K, "mast_head")
		kit.rod((0, 1.15, 0.2), (0, 1.15, min(top, mast) * 0.9), 0.05, "steel_stainless", "lift_ram", segs=8)
		ram((0.3, 0.6, 0.7), (0.38, 1.15, 1.0), 0.04)
	with kit.stage("carriage"):
		kit.box((1.0, 0.06, 0.45), (0, 1.36, lift + 0.4), K, "carriage")
		kit.frame(1.0, 0.75, 0.05, 0.05, (0, 1.36, lift + 0.62), K, "backrest")
		for i in range(5):
			kit.box((0.03, 0.03, 0.7), (-0.3 + i * 0.15, 1.36, lift + 0.97), K, "backrest_bar")
		for sx in (-1, 1):
			kit.box((0.11, 0.05, 0.55), (sx * 0.27, 1.42, lift + 0.33), D, "fork_shank")
			kit.prism([(1.42, lift + 0.04), (2.55, lift + 0.04), (2.55, lift + 0.06), (1.42, lift + 0.1)], 0.11, (sx * 0.27, 0, 0), D, "fork", axis="x")
	kit.socket("load", (0, 2.0, lift + 0.1))


def skid_steer():
	"""A skid-steer loader with a caged cab."""
	with kit.stage("wheels"):
		for sx in (-1, 1):
			for y in (-0.55, 0.55):
				wheel(0.42, 0.32, (sx * 0.78, y, 0.42), D)
	with kit.stage("body"):
		with kit.hollow(0.4):
			kit.box((1.2, 2.3, 0.6), (0, -0.1, 0.65), W, "chassis")
			kit.prism([(-1.4, 0.9), (-0.5, 0.9), (-0.5, 1.6), (-1.4, 1.75)], 1.2, (0, 0, 0), W, "engine_cover", axis="x")
			kit.box((1.0, 0.1, 0.6), (0, -1.42, 1.25), K, "rear_grille")
		with kit.hollow(0.08):
			kit.box((0.95, 1.2, 0.08), (0, 0.15, 2.05), K, "cab_roof")
			for sx in (-1, 1):
				for y in (-0.42, 0.72):
					kit.box((0.06, 0.06, 1.15), (sx * 0.45, y, 1.48), K, "cab_post")
				kit.grid_bars(1.1, 1.0, (sx * 0.46, 0.15, 1.5), 4, 4, 0.008, K, "cab_mesh", plane="yz")
		kit.box((0.86, 1.1, 1.0), (0, 0.15, 1.5), "glass", "cab_glass")
		kit.box((0.5, 0.5, 0.45), (0, -0.1, 1.15), K, "seat")
	with kit.stage("arms"):
		for sx in (-1, 1):
			kit.prism([(-1.35, 1.85), (-1.1, 1.95), (1.0, 1.05), (1.45, 0.45), (1.25, 0.35), (0.8, 0.85), (-1.3, 1.6)], 0.16, (sx * 0.68, 0, 0), W, "lift_arm", axis="x")
			kit.box((0.2, 0.4, 0.9), (sx * 0.68, -1.2, 1.4), W, "arm_tower")
			ram((sx * 0.68, -0.9, 0.95), (sx * 0.68, 0.2, 1.3), 0.05)
		kit.box((1.3, 0.12, 0.12), (0, 1.3, 0.45), W, "arm_tie")
	with kit.stage("bucket"):
		kit.prism([(1.4, 0.75), (1.45, 0.1), (2.2, 0.05), (2.27, 0.1), (1.75, 0.3), (1.6, 0.8)], 1.75, (0, 0, 0), D, "bucket", axis="x")
		for sx in (-1, 1):
			kit.prism([(1.45, 0.1), (2.25, 0.07), (1.6, 0.8), (1.4, 0.75)], 0.04, (sx * 0.88, 0, 0), D, "bucket_side", axis="x")
	kit.socket("bucket_pivot", (0, 1.4, 0.4))


def scissor_lift(h=6.0, extended=True):
	"""A self-propelled scissor lift with its platform at height h (1.4 is stowed)."""
	with kit.stage("base"):
		with kit.hollow(0.5):
			kit.rounded_box((1.25, 2.5, 0.5), (0, 0, 0.55), Y, "chassis", radius=0.04)
			kit.box((0.02, 1.1, 0.34), (0.635, 0, 0.55), D, "battery_door")
		for sx in (-1, 1):
			for y in (-0.95, 0.95):
				wheel(0.25, 0.16, (sx * 0.58, y, 0.25), D)
		kit.box((0.2, 0.06, 0.6), (0, -1.3, 0.75), Y, "ladder")
	z0, z1 = 0.85, h - 0.2
	n = max(1, round((z1 - z0) / 1.3))
	with kit.stage("scissors"):
		if h < 2.0:
			for i in range(5):
				kit.box((1.0, 2.2, 0.07), (0, 0, z0 + 0.05 + i * (z1 - z0 - 0.1) / 4), D, "scissor_stack")
		else:
			dz = (z1 - z0) / n
			for i in range(n):
				za, zb = z0 + i * dz, z0 + (i + 1) * dz
				for sx in (-1, 1):
					kit.strut((sx * 0.5, -1.05, za), (sx * 0.5, 1.05, zb), 0.06, 0.12, D, "scissor_arm")
					kit.strut((sx * 0.42, 1.05, za), (sx * 0.42, -1.05, zb), 0.06, 0.12, D, "scissor_arm")
				for y in (-1.05, 1.05):
					kit.rod((-0.52, y, zb), (0.52, y, zb), 0.035, D, "scissor_pin", segs=8)
				kit.rod((-0.52, 0, (za + zb) / 2), (0.52, 0, (za + zb) / 2), 0.03, D, "scissor_pin", segs=8)
			ram((0, -0.6, z0 + 0.1), (0, 0.3, z0 + dz * 1.2), 0.06)
	y1 = 1.25 + (0.9 if extended else 0.0)
	with kit.stage("platform"):
		with kit.hollow(0.4):
			kit.box((1.25, 2.5, 0.16), (0, 0, h - 0.08), Y, "deck_frame")
			kit.box((1.15, 2.4, 0.02), (0, 0, h + 0.01), G, "deck")
			if extended:
				kit.box((1.1, 0.95, 0.12), (0, 1.25 + 0.45, h - 0.06), Y, "deck_extension")
				kit.box((1.0, 0.9, 0.02), (0, 1.25 + 0.45, h + 0.01), G, "deck")
		ring = [(-0.6, -1.22, h), (-0.6, 0, h), (-0.6, 1.22, h)] + ([(-0.53, y1, h)] if extended else [])
		ring += [(0.53 if extended else 0.6, y1, h)] + [(0.6, 1.22, h), (0.6, 0, h), (0.6, -1.22, h), (-0.6, -1.22, h)]
		rails(ring, 1.1, 0.022, Y, "guard_rail")
		kit.rounded_box((0.06, 0.4, 0.55), (0.56, -0.9, h + 0.75), Y, "control_box", radius=0.02)
	kit.socket("platform", (0, 0, h))


# --- lorries -----------------------------------------------------------------------------------

def lorry_base(length, rear=2, paint="car_red"):
	"""A cab-over rigid lorry chassis. Returns (deck height, body front y, body back y)."""
	f = length / 2
	fa = f - 1.4
	ra = [-f + 1.35 + i * 1.35 for i in range(rear)]
	with kit.stage("chassis"):
		with kit.hollow(0.12):
			kit.prism([(f - 2.1, 0.95), (f, 0.95), (f, 1.82), (f - 0.1, 1.92), (f - 0.32, 2.8), (f - 0.55, 2.95), (f - 2.1, 2.95)], 2.45, (0, 0, 0), paint, "cab", axis="x")
			kit.box((2.1, 1.25, 0.06), (0, f - 1.35, 2.98), paint, "cab_roof_cap")
		kit.strut((0, f - 0.09, 1.95), (0, f - 0.29, 2.76), 2.2, 0.03, "glass_dark", "windscreen")
		for sx in (-1, 1):
			kit.box((0.02, 0.85, 0.72), (sx * 1.23, f - 0.9, 2.32), "glass_dark", "door_window")
			kit.box((0.02, 0.42, 0.55), (sx * 1.23, f - 1.75, 2.38), "glass_dark", "quarter_window")
			kit.box((0.015, 0.02, 1.5), (sx * 1.23, f - 1.4, 1.8), D, "door_line")
			kit.box((0.07, 0.12, 0.42), (sx * 1.36, f - 0.22, 2.3), K, "mirror")
			kit.rod((sx * 1.2, f - 0.2, 2.5), (sx * 1.36, f - 0.22, 2.5), 0.015, K, "mirror_arm", segs=5)
			kit.box((0.36, 0.04, 0.17), (sx * 0.95, f + 0.14, 0.78), W, "headlight")
			kit.box((0.4, 1.35, 0.3), (sx * 1.05, fa, 1.12), K, "wheel_arch")
			kit.box((0.5, 0.35, 0.06), (sx * 1.0, f - 2.0, 0.6), K, "step")
			kit.box((0.6, 1.1, 0.5), (sx * 0.95, f - 3.0, 0.75), K, "side_tank")
			kit.box((0.62, rear * 1.35 + 0.2, 0.06), (sx * 0.95, (ra[0] + ra[-1]) / 2, 1.13), K, "mudguard")
		kit.box((2.15, 0.05, 0.62), (0, f + 0.012, 1.46), K, "grille")
		for i in range(5):
			kit.box((1.9, 0.02, 0.03), (0, f + 0.045, 1.24 + i * 0.11), D, "grille_slat")
		kit.cyl(0.14, 0.03, (0, f + 0.05, 1.46), G, "badge", axis="y", segs=14)
		kit.box((2.5, 0.38, 0.36), (0, f - 0.06, 0.78), K, "bumper")
		kit.box((0.9, length - 2.2, 0.28), (0, -1.05, 0.95), D, "chassis_rails")
		kit.box((2.4, 0.14, 0.2), (0, -f + 0.07, 0.72), K, "rear_bar")
	with kit.stage("wheels"):
		for sx in (-1, 1):
			wheel(0.52, 0.32, (sx * 1.07, fa, 0.52), "steel_galvanised")
			for y in ra:
				wheel(0.52, 0.56, (sx * 0.95, y, 0.52), "steel_galvanised")
	return 1.1, f - 2.25, -f + 0.05


def stabilisers(ys, reach=3.0, paint=Y, deployed=True):
	for y in ys:
		for sx in (-1, 1):
			if deployed:
				kit.box((reach - 1.0, 0.25, 0.25), (sx * (reach + 1.0) / 2, y, 1.0), G, "stabiliser_beam")
				kit.box((0.3, 0.32, 0.8), (sx * reach, y, 1.1), paint, "jack")
				kit.cyl(0.06, 0.75, (sx * reach, y, 0.4), "steel_stainless", "jack_leg", segs=8)
				kit.cyl(0.22, 0.06, (sx * reach, y, 0.03), G, "pad", segs=12)
			else:
				kit.box((0.2, 0.3, 0.85), (sx * 1.2, y, 1.0), paint, "jack")
				kit.cyl(0.06, 0.4, (sx * 1.2, y, 0.45), "steel_stainless", "jack_leg", segs=8)


def lorry(body="dropside", axles=3, paint="car_red", deployed=False):
	"""A site lorry. body: dropside, mixer, tanker, pump or platform. axles counts them all."""
	length = {2: 7.0, 3: 8.6, 4: 10.0}[axles] + (1.6 if body == "pump" else 0.0)
	z, y1, y0 = lorry_base(length, rear=axles - 1, paint=paint)
	bl = y1 - y0
	yc = (y0 + y1) / 2
	if body == "dropside":
		with kit.stage("body"), kit.hollow(0.3):
			kit.box((2.5, bl, 0.12), (0, yc, z + 0.16), G, "bed")
			for sx in (-1, 1):
				kit.box((0.05, bl, 0.75), (sx * 1.225, yc, z + 0.55), G, "side_board")
				kit.box((0.02, bl - 0.1, 0.04), (sx * 1.26, yc, z + 0.6), D, "board_rib")
			for y in (y0 + 0.025, y1 - 0.025):
				kit.box((2.5, 0.05, 0.75 if y < yc else 1.0), (0, y, z + (0.55 if y < yc else 0.675)), G, "end_board")
			kit.box((2.2, 0.1, 0.35), (0, y0 - 0.02, 0.85), K, "under_run")
		kit.socket("load", (0, yc, z + 0.22))
	elif body == "tanker":
		r = 1.08
		with kit.stage("body"), kit.hollow(0.1):
			kit.lathe([(0.0, 0.0), (r * 0.6, 0.06), (r * 0.92, 0.25), (r, 0.5), (r, bl - 0.5), (r * 0.92, bl - 0.25), (r * 0.6, bl - 0.06), (0.0, bl)], (0, y0, z + 0.2 + r), "steel_galvanised", "tank", segs=28, rot=(-90, 0, 0))
			for y in (y0 + 0.9, yc, y1 - 0.9):
				kit.box((2.0, 0.2, 0.5), (0, y, z + 0.35), D, "cradle")
			kit.box((0.5, bl - 1.4, 0.04), (0, yc, z + 0.22 + 2 * r), G, "walkway")
			kit.cyl(0.3, 0.14, (0, yc, z + 0.27 + 2 * r), D, "hatch", segs=16)
			kit.box((0.5, 0.3, 0.6), (0.9, y0 + 0.4, z - 0.1), D, "valve_box")
	elif body == "mixer":
		with kit.stage("body"):
			kit.prism([(y0, z), (y1, z), (y1, z + 0.35), (y1 - 0.8, z + 0.9), (y1 - 1.3, z + 0.9), (y1 - 1.8, z + 0.3), (y0 + 1.6, z + 0.3), (y0 + 0.9, z + 1.9), (y0 + 0.4, z + 1.9), (y0, z + 0.5)], 1.5, (0, 0, 0), D, "subframe", axis="x")
			kit.cyl(0.42, 1.9, (0, y1 - 0.15, z + 1.55), W, "water_tank", axis="x", segs=18)
			kit.cyl(0.5, 0.5, (0, y0 + 0.5, z + 2.45), D, "hopper", segs=14, r2=0.25)
			kit.strut((0, y0 + 0.5, z + 1.6), (0.5, y0 - 0.5, z + 0.6), 0.4, 0.08, D, "chute")
			for sx in (-1, 1):
				kit.rod((sx * 0.8, y0 + 0.2, z + 0.3), (sx * 0.8, y0 + 0.2, z + 1.8), 0.02, G, "ladder", segs=5)
		with kit.stage("drum"), kit.hollow(0.15):
			kit.lathe([(0.0, 0.0), (0.55, 0.02), (1.05, 0.9), (1.18, 1.7), (1.18, 2.5), (0.6, 4.1), (0.0, 4.1)], (0, y1 - 1.0, z + 0.95), paint, "drum", segs=28, rot=(77, 0, 0))
			kit.lathe([(1.2, 1.68), (1.22, 1.7), (1.22, 1.78), (1.2, 1.8)], (0, y1 - 1.0, z + 0.95), paint, "drum_band", segs=28, rot=(77, 0, 0))
			kit.lathe([(1.2, 2.4), (1.22, 2.42), (1.22, 2.5), (1.2, 2.52)], (0, y1 - 1.0, z + 0.95), paint, "drum_band", segs=28, rot=(77, 0, 0))
		kit.socket("drum", (0, y1 - 1.0, z + 0.95))
		# The drum spins about the line from drum to drum_axis.
		kit.socket("drum_axis", (0, y1 - 1.0 - 4.1 * math.sin(math.radians(77)), z + 0.95 + 4.1 * math.cos(math.radians(77))))
		kit.socket("chute", (0.5, y0 - 0.5, z + 0.6))
	elif body == "pump":
		yt = y1 - 0.7
		with kit.stage("body"), kit.hollow(0.3):
			kit.box((2.4, bl, 0.3), (0, yc, z + 0.15), paint, "deck")
			kit.box((1.2, 1.4, 0.9), (0, y0 + 0.7, z + 0.6), paint, "hopper")
			kit.cyl(0.75, 0.9, (0, yt, z + 0.75), D, "turret", segs=20)
			kit.cyl(0.9, 0.12, (0, yt, z + 1.25), G, "turret_ring", segs=20)
		with kit.stage("outriggers"):
			stabilisers((yt - 0.4, y0 + 1.6), 3.6 if deployed else 0, paint, deployed)
		with kit.stage("boom"):
			if deployed:
				pts = [(yt, z + 1.3), (yt - 1.6, z + 9.5), (yt - 8.5, z + 14.2), (yt - 17.0, z + 14.0), (yt - 23.5, z + 8.0), (yt - 25.0, z + 0.9)]
				for i, (a, b) in enumerate(zip(pts, pts[1:])):
					sz = 0.6 - i * 0.08
					kit.strut((0, a[0], a[1]), (0, b[0], b[1]), sz * 0.7, sz, paint, "boom_section")
					kit.rod((sz * 0.45, a[0], a[1]), (sz * 0.45, b[0], b[1]), 0.07, D, "delivery_pipe", segs=8)
					kit.cyl(0.16, sz * 0.9, (0, b[0], b[1]), D, "boom_knuckle", axis="x", segs=10)
				kit.rod((0.15, pts[-1][0], pts[-1][1]), (0.15, pts[-1][0], 0.4), 0.08, K, "end_hose", segs=8)
				kit.socket("hose", (0.15, pts[-1][0], 0.4))
			else:
				for i in range(4):
					zz = z + 1.6 + i * 0.5
					ya, yb = yt + (0.3 if i % 2 == 0 else -0.2), y0 + 0.2 + (0.3 if i % 2 else 0.0)
					kit.strut((0, ya, zz + (0.1 if i % 2 else 0)), (0, yb, zz + (0 if i % 2 else 0.1)), 0.5, 0.42, paint, "boom_section")
					kit.rod((0.3, ya, zz), (0.3, yb, zz), 0.07, D, "delivery_pipe", segs=8)
				kit.strut((0, yt, z + 1.3), (0, yt + 0.3, z + 1.8), 0.4, slot=paint, name="boom_foot")
		kit.socket("slew", (0, yt, z + 1.3))
	elif body == "platform":
		yt = y1 - 0.8
		with kit.stage("body"), kit.hollow(0.3):
			kit.box((2.45, bl, 0.14), (0, yc, z + 0.07), G, "deck")
			for sx in (-1, 1):
				kit.box((0.75, bl - 2.2, 0.6), (sx * 0.8, yc - 1.0, z + 0.44), "steel_galvanised", "locker")
			kit.cyl(0.6, 0.5, (0, yt, z + 0.39), paint, "turret", segs=20)
			kit.cyl(0.7, 0.1, (0, yt, z + 0.68), G, "turret_ring", segs=20)
			kit.prism([(yt - 0.5, z + 0.7), (yt + 0.5, z + 0.7), (yt + 0.3, z + 1.7), (yt - 0.3, z + 1.7)], 0.7, (0, 0, 0), paint, "turret_tower", axis="x")
		with kit.stage("outriggers"):
			stabilisers((yt - 0.9, y0 + 0.5), 2.6 if deployed else 0, paint, deployed)
		p0 = Vector((0, yt, z + 1.55))
		a = math.radians(118.0 if deployed else 178.0)
		d = Vector((0, math.cos(a), math.sin(a)))
		bl2 = bl - 1.2
		with kit.stage("boom"):
			kit.strut(tuple(p0 - d * 0.4), tuple(p0 + d * bl2), 0.5, 0.6, paint, "boom_base")
			tip = p0 + d * bl2
			if deployed:
				for i in range(3):
					s1 = tip + d * bl2 * 0.55
					kit.strut(tuple(tip - d * 0.6), tuple(s1), 0.42 - i * 0.06, 0.5 - i * 0.06, "steel_galvanised", "boom_section")
					kit.strut(tuple(s1 - d * 0.1), tuple(s1), 0.46 - i * 0.06, 0.54 - i * 0.06, D, "boom_collar")
					tip = s1
				ram((0, yt - 0.3, z + 0.9), tuple(p0 + d * bl2 * 0.5), 0.09)
			kit.strut(tuple(tip), tuple(tip + Vector((0, 0, -0.9))), 0.2, slot=paint, name="basket_arm")
		by = tip.y - 0.75
		bz = tip.z - 1.0
		with kit.stage("basket"):
			kit.box((1.6, 1.0, 0.12), (0, by, bz), G, "basket_floor")
			rails([(-0.78, by - 0.48, bz), (0.78, by - 0.48, bz), (0.78, by + 0.48, bz), (-0.78, by + 0.48, bz), (-0.78, by - 0.48, bz)], 1.1, 0.025, "steel_galvanised", "basket_rail")
		kit.socket("slew", (0, yt, z + 0.7))
		kit.socket("boom_pivot", tuple(p0))
		kit.socket("basket", (0, by, bz + 0.06))


# --- registrations ---------------------------------------------------------------------------

reg("crane.tower", tower_crane, "Tower crane, high top, 30 m mast and 40 m jib", "crane")
reg("crane.tower_45", tower_crane, "Tower crane, high top, 45 m mast and 50 m jib", "crane", height=45.0, jib=50.0, counter=14.0)
reg("crane.tower_60", tower_crane, "Tower crane, high top, 60 m mast and 60 m jib, cast base", "crane", height=60.0, jib=60.0, counter=16.0, base="cast")
reg("crane.tower_city", tower_crane, "City tower crane, flat top, 24 m mast and 30 m jib", "crane", height=24.0, jib=30.0, counter=9.0, top="flat", cabin="side", base="cast")
reg("crane.tower_flat_30", tower_crane, "Tower crane, flat top, 30 m mast and 40 m jib", "crane", top="flat", cabin="side", base="cast")
reg("crane.tower_flat_45", tower_crane, "Tower crane, flat top, 45 m mast and 50 m jib", "crane", height=45.0, jib=50.0, counter=14.0, top="flat", cabin="side", base="cast")
reg("crane.tower_flat_60", tower_crane, "Tower crane, flat top, 60 m mast and 60 m jib", "crane", height=60.0, jib=60.0, counter=16.0, top="flat", cabin="side", base="ballast")
reg("lifting.mobile_crane", mobile_crane, "Mobile crane, 3 axle, boom raised", "crane")
reg("lifting.mobile_crane_stowed", mobile_crane, "Mobile crane, 3 axle, travelling", "crane", raised=False)
for _n in (2, 4, 5, 6):
	reg("lifting.mobile_crane_%d_axle" % _n, mobile_crane, "Mobile crane, %d axle, boom raised" % _n, "crane", axles=_n, ext=max(2, _n - 1), angle=72.0)
	reg("lifting.mobile_crane_%d_axle_stowed" % _n, mobile_crane, "Mobile crane, %d axle, travelling" % _n, "crane", axles=_n, raised=False)
reg("lifting.crawler_crane", crawler_crane, "Crawler crane, 30 m lattice boom", "crane")
reg("lifting.crawler_crane_low", crawler_crane, "Crawler crane, 30 m boom lowered", "crane", angle=28.0)
reg("lifting.crawler_crane_45", crawler_crane, "Crawler crane, 45 m lattice boom", "crane", boom=45.0, angle=72.0)
reg("piling.rig", piling_rig, "Rotary piling rig, drilling", "piling")
reg("piling.rig_stowed", piling_rig, "Rotary piling rig, leader stowed", "piling", stowed=True)
reg("excavator.mini", excavator, "Mini excavator", "earthmoving", s=0.42)
reg("excavator.midi", excavator, "Midi excavator, 8 t", "earthmoving", s=0.68)
reg("excavator.20t", excavator, "Excavator, 20 t", "earthmoving")
reg("excavator.45t", excavator, "Excavator, 45 t", "earthmoving", s=1.3)
reg("excavator.breaker", excavator, "Excavator with hydraulic breaker", "earthmoving", "demolition", tool="breaker")
reg("earthmoving.wheel_loader", wheel_loader, "Wheel loader", "earthmoving")
reg("earthmoving.roller", road_roller, "Road roller, single drum", "earthmoving")
reg("earthmoving.skid_steer", skid_steer, "Skid-steer loader", "earthmoving")
reg("lifting.forklift", forklift, "Forklift, forks down", "lifting")
reg("lifting.forklift_raised", forklift, "Forklift, forks at 3 m", "lifting", lift=3.0)
reg("lifting.forklift_high", forklift, "Forklift, forks at 4.5 m", "lifting", lift=4.5)
reg("access.scissor_lift_stowed", scissor_lift, "Scissor lift, stowed", "access", h=1.4, extended=False)
reg("access.scissor_lift_6", scissor_lift, "Scissor lift at 6 m", "access", h=6.0)
reg("access.scissor_lift_10", scissor_lift, "Scissor lift at 10 m", "access", h=10.0)
reg("truck.tipper", lorry, "Dropside lorry, 3 axle", "lorry")
reg("truck.dropside_2_axle", lorry, "Dropside lorry, 2 axle", "lorry", axles=2)
reg("truck.dropside_4_axle", lorry, "Dropside lorry, 4 axle", "lorry", axles=4)
reg("truck.concrete_mixer", lorry, "Concrete mixer lorry", "lorry", "concrete", body="mixer")
reg("truck.tanker", lorry, "Tanker lorry", "lorry", body="tanker")
reg("truck.concrete_pump", lorry, "Concrete pump lorry, boom folded", "lorry", "concrete", body="pump", axles=4, paint=Y)
reg("truck.concrete_pump_deployed", lorry, "Concrete pump lorry, boom placing", "lorry", "concrete", body="pump", axles=4, paint=Y, deployed=True)
reg("truck.access_platform", lorry, "Lorry mounted access platform, raised", "lorry", "access", body="platform", deployed=True)
reg("truck.access_platform_stowed", lorry, "Lorry mounted access platform, travelling", "lorry", "access", body="platform")
reg("truck.access_platform_2_axle", lorry, "Lorry mounted access platform, 2 axle, raised", "lorry", "access", body="platform", axles=2, deployed=True)
