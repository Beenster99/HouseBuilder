"""Walls, floors, roofs, rainwater goods, foundations and steelwork details.

Walls are 1 m long (along Y) and 1 m high from the floor, with their real layers showing at
the ends and top; the game stretches them to length and height. Floors and roof coverings
are 1 m square tiles stretched both ways."""
import math

import kit
from registry import asset, catalog, register

# layer lists: (thickness m, slot), outside face first
WALLS = {
	"wall_block_100": [(0.013, "plasterboard"), (0.1, "blockwork"), (0.013, "plasterboard")],
	"wall_block_140": [(0.013, "plasterboard"), (0.14, "blockwork"), (0.013, "plasterboard")],
	"wall_brick_215": [(0.215, "brick"), (0.013, "plasterboard")],
	"wall_cavity_300": [(0.1025, "brick"), (0.05, None), (0.05, "mineral_wool"), (0.1, "blockwork"), (0.013, "plasterboard")],
	"wall_rc_200": [(0.2, "concrete")],
	"wall_rc_250": [(0.25, "concrete")],
	"wall_rc_300": [(0.3, "concrete")],
	"wall_timber_frame_140": [(0.02, "softwood"), (0.025, None), (0.009, "plywood"), (0.14, "mineral_wool"), (0.0125, "plasterboard")],
	"wall_stud_100": [(0.0125, "plasterboard"), (0.075, "mineral_wool"), (0.0125, "plasterboard")],
}


def wall(layers):
	total = sum(t for t, _ in layers)
	x = -total / 2
	for t, slot in layers:
		if slot:
			with kit.stage("structure" if slot in ("brick", "blockwork", "concrete", "mineral_wool", "plywood") else "finishes"):
				kit.box((t, 1.0, 1.0), (x + t / 2, 0, 0.5), slot, slot)
		x += t
	kit.socket("start", (0, -0.5, 0))
	kit.socket("end", (0, 0.5, 0))


for _sid, _layers in WALLS.items():
	_s = catalog()["sections"][_sid]
	register("structure.wall." + _sid[5:], wall, _s["label"], family="wall", kind=_sid, tags=("structure", "wall"), stretch="zy", layers=_layers)


@asset("structure.wall.curtain_module", "Curtain wall module, 1.5 m by 3.6 m", family="wall", kind="wall_curtain_150", tags=("structure", "wall", "glazing"))
def curtain_module(w=1.5, h=3.6):
	with kit.stage("frame"):
		for s in (-1, 1):
			kit.box((0.05, 0.15, h), (s * (w / 2 - 0.025), 0, h / 2), "aluminium", "mullion")
		for z in (0.025, 1.0, h - 0.6, h - 0.025):
			kit.box((w - 0.1, 0.15, 0.05), (0, 0, z), "aluminium", "transom")
	with kit.stage("glazing"):
		kit.box((w - 0.1, 0.028, 0.92), (0, 0.04, 0.51), "laminate_grey", "spandrel")
		kit.box((w - 0.1, 0.028, h - 1.65), (0, 0.04, 1.0 + (h - 1.6) / 2), "glass", "vision")
		kit.box((w - 0.1, 0.028, 0.52), (0, 0.04, h - 0.31), "glass", "top_light")


def stud_frame(w=2.4, h=2.4, slot="softwood"):
	"""An open stud panel, as it stands before boarding (timelapse)."""
	for z in (0.019, h - 0.019):
		kit.box((0.089, w, 0.038), (0, 0, z), slot, "plate")
	n = round(w / 0.6)
	for i in range(n + 1):
		kit.box((0.089, 0.038, h - 0.076), (0, -w / 2 + 0.019 + (w - 0.038) * i / n, h / 2), slot, "stud")
	for i in range(n):
		kit.box((0.089, w / n - 0.038, 0.038), (0, -w / 2 + w * (i + 0.5) / n, h / 2 + (0.05 if i % 2 else -0.05)), slot, "noggin")


register("structure.wall.stud_panel_timber", stud_frame, "Open timber stud panel, 2.4 m", family="wall", tags=("structure", "wall", "timber"))
register("structure.wall.stud_panel_metal", stud_frame, "Open metal stud panel, 2.4 m", family="wall", tags=("structure", "wall"), slot="steel_galvanised")

FLOORS = {
	"slab_150": [(0.15, "concrete")], "slab_200": [(0.2, "concrete")], "slab_250": [(0.25, "concrete")], "slab_300": [(0.3, "concrete")],
	"floor_joist_225": [(0.0125, "plasterboard"), (0.225, "softwood"), (0.022, "plywood")],
	"floor_joist_300": [(0.0125, "plasterboard"), (0.3, "softwood"), (0.022, "plywood")],
	"raft_250": [(0.25, "concrete")], "raft_300": [(0.3, "concrete")], "raft_400": [(0.4, "concrete")],
	"roof_timber_flat": [(0.0125, "plasterboard"), (0.2, "softwood"), (0.018, "plywood"), (0.07, "insulation"), (0.005, "roof_felt")],
	"roof_rc_flat": [(0.17, "concrete"), (0.075, "insulation"), (0.005, "roof_felt")],
}


def plate(layers, joists=False):
	"""A 1 m square of floor or flat roof, its top at z = 0, layers listed bottom first."""
	z = -sum(t for t, _ in layers)
	for t, slot in layers:
		if joists and slot == "softwood":
			for y in (-0.4, 0.0, 0.4):
				kit.box((1.0, 0.047, t), (0, y, z + t / 2), slot, "joist")
		else:
			kit.box((1.0, 1.0, t), (0, 0, z + t / 2), slot, slot)
		z += t


for _sid, _layers in FLOORS.items():
	_s = catalog()["sections"][_sid]
	_fam = "roof" if _sid.startswith("roof") else ("foundation" if _sid.startswith("raft") else "slab")
	register("structure.%s.%s" % ("roof" if _fam == "roof" else "floor", _sid), plate, _s["label"], family=_fam, kind=_sid,
		tags=("structure", _fam), stretch="xz", layers=_layers, joists="joist" in _sid)


@asset("structure.floor.composite_deck", "Composite metal deck slab, 130 mm", family="slab", tags=("structure", "slab", "steel"), stretch="z")
def composite_deck():
	pts = []
	for i in range(5):
		x = -0.5 + i * 0.2
		pts += [(x, -0.13), (x + 0.03, -0.07), (x + 0.1, -0.07), (x + 0.13, -0.13)]
	pts += [(0.5, -0.13), (0.5, 0.0), (-0.5, 0.0)]
	kit.prism(pts, 1.0, slot="concrete", name="slab")
	kit.box((1.0, 1.0, 0.002), (0, 0, -0.131), "steel_galvanised", "deck")


def strip(s):
	kit.box((s["w"], 1.0, s["d"]), (0, 0, -s["d"] / 2), "concrete", "footing")


for _sid, _s in catalog()["sections"].items():
	if _sid.startswith("strip_"):
		register("structure.foundation." + _sid, strip, _s["label"], family="foundation", kind=_sid, tags=("structure", "concrete"), stretch="z", s=_s)


@asset("structure.foundation.pile_cap_2", "Pile cap on two piles", family="foundation", tags=("structure", "concrete"))
def pile_cap(piles=2):
	L = 1.0 + 0.9 * (piles - 1)
	kit.box((1.0, L, 0.8), (0, 0, -0.4), "concrete", "cap")
	for i in range(piles):
		kit.cyl(0.225, 1.0, (0, -L / 2 + 0.5 + i * 0.9, -1.3), "concrete", "pile", segs=20)
	kit.socket("column", (0, 0, 0))


register("structure.foundation.pile_cap_4", pile_cap, "Pile cap on four piles (in line)", family="foundation", tags=("structure", "concrete"), piles=4)


@asset("structure.rebar.column_cage", "Column reinforcement cage, 3 m", tags=("structure", "concrete", "rebar"))
def rebar_cage(w=0.3, h=3.0):
	for sx in (-1, 0, 1):
		for sy in (-1, 0, 1):
			if sx or sy:
				kit.rod((sx * w / 2, sy * w / 2, 0), (sx * w / 2, sy * w / 2, h + 0.6), 0.0125, "cast_iron", "bar", segs=6)
	for i in range(int(h / 0.2)):
		z = 0.1 + i * 0.2
		kit.sweep([(-w / 2 - 0.01, -w / 2 - 0.01, z), (w / 2 + 0.01, -w / 2 - 0.01, z), (w / 2 + 0.01, w / 2 + 0.01, z), (-w / 2 - 0.01, w / 2 + 0.01, z), (-w / 2 - 0.01, -w / 2 - 0.01, z)], kit.circle(0.005, 5), "cast_iron", "link")


@asset("structure.rebar.mesh_sheet", "A393 mesh sheet, 4.8 m by 2.4 m", tags=("structure", "concrete", "rebar"))
def mesh_sheet():
	kit.grid_bars(2.4, 4.8, (0, 0, 0.03), 12, 24, 0.005, "cast_iron", plane="xy")


@asset("structure.lintel.steel", "Steel cavity lintel", family="wall", tags=("structure", "wall", "steel"), stretch="z")
def lintel_steel():
	kit.prism([(-0.14, 0), (0.14, 0), (0.14, 0.004), (0.05, 0.004), (0.02, 0.15), (-0.02, 0.15), (-0.05, 0.004), (-0.14, 0.004)], 1.0, slot="steel_galvanised", name="lintel")


@asset("structure.lintel.concrete", "Concrete lintel, 100 by 140", family="wall", tags=("structure", "wall", "concrete"), stretch="z")
def lintel_concrete():
	kit.box((0.1, 1.0, 0.14), (0, 0, 0.07), "concrete", "lintel")


def cladding(what):
	if what == "timber":
		for i in range(7):
			kit.box((0.02, 1.0, 0.14), (0.012, 0, 0.07 + i * 0.1428), "softwood", "board", rot=(0, 4, 0))
	elif what == "standing_seam":
		kit.box((0.002, 1.0, 1.0), (0.001, 0, 0.5), "aluminium", "sheet")
		for y in (-0.4, 0.0, 0.4):
			kit.box((0.025, 0.004, 1.0), (0.0135, y, 0.5), "aluminium", "seam")
	elif what == "profiled":
		pts = []
		for i in range(5):
			y = -0.5 + i * 0.2
			pts += [(y, 0), (y + 0.03, 0.032), (y + 0.09, 0.032), (y + 0.12, 0)]
		pts += [(0.5, 0), (0.5, -0.001), (-0.5, -0.001)]
		kit.prism(pts, 1.0, (0, 0, 0.5), "steel_painted", "sheet", axis="z", rot=(0, 0, 90))
	elif what == "render":
		kit.box((0.02, 1.0, 1.0), (0.01, 0, 0.5), "render", "render")
	elif what == "rainscreen":
		for i in range(2):
			for j in range(2):
				kit.box((0.012, 0.49, 0.49), (0.04, -0.25 + i * 0.5, 0.25 + j * 0.5), "laminate_grey", "panel")
		for y in (-0.25, 0.25):
			kit.box((0.034, 0.04, 1.0), (0.017, y, 0.5), "aluminium", "rail")


for _k, _l in (("timber", "Timber weatherboard cladding"), ("standing_seam", "Standing seam metal cladding"), ("profiled", "Profiled steel sheet cladding"),
		("render", "Rendered finish"), ("rainscreen", "Rainscreen panel cladding")):
	register("structure.cladding." + _k, cladding, _l, family="wall", tags=("structure", "wall", "cladding"), stretch="zy", what=_k)

# --- roof structure ------------------------------------------------------------------------

def fink_truss(span, pitch=35.0, attic=False):
	rise = span / 2 * math.tan(math.radians(pitch))
	t, d = 0.035, 0.097
	with kit.stage("truss"):
		kit.box((span, t, d), (0, 0, d / 2), "softwood", "tie")
		for s in (-1, 1):
			kit.strut((s * (span / 2 + 0.3), 0, -0.3 * math.tan(math.radians(pitch)) + d), (0, 0, rise + d), d, t, "softwood", "rafter")
		if attic:
			for s in (-1, 1):
				kit.box((d, t, rise * 0.55), (s * span * 0.22, 0, d + rise * 0.275), "softwood", "stud")
			kit.box((span * 0.44, t, d), (0, 0, rise * 0.56 + d), "softwood", "collar")
		else:
			for s in (-1, 1):
				kit.strut((s * span / 6, 0, d), (s * span / 4, 0, rise / 2 + d), 0.072, t, "softwood", "web")
				kit.strut((s * span / 6, 0, d), (0, 0, rise + d * 0.5), 0.072, t, "softwood", "web")
		for s in (-1, 1):
			kit.box((0.15, 0.002, 0.1), (s * (span / 2 - 0.1), t / 2, d), "steel_galvanised", "nail_plate")
		kit.box((0.2, 0.002, 0.12), (0, t / 2, rise + d * 0.6), "steel_galvanised", "nail_plate")
	kit.socket("left", (-span / 2, 0, 0))
	kit.socket("right", (span / 2, 0, 0))
	kit.socket("apex", (0, 0, rise + d))


for _sp in (5, 6, 8, 10, 12):
	register("structure.truss.fink_%d" % _sp, fink_truss, "Timber trussed rafter, %d m span" % _sp, family="truss", kind="truss_timber_domestic" if _sp == 8 else "",
		tags=("structure", "roof", "timber"), span=float(_sp))
for _sp in (8, 10):
	register("structure.truss.attic_%d" % _sp, fink_truss, "Attic truss, %d m span" % _sp, family="truss", tags=("structure", "roof", "timber"), span=float(_sp), pitch=45.0, attic=True)


def steel_truss(span, depth):
	n = max(4, round(span / depth / 1.2) * 2)
	bay = span / n
	c = 0.12 if depth < 2 else 0.2
	for z in (c / 2, depth - c / 2):
		kit.box((span, c, c), (0, 0, z), "steel_painted", "chord")
	for i in range(n + 1):
		x = -span / 2 + i * bay
		kit.box((c * 0.6, c * 0.6, depth - 2 * c), (x, 0, depth / 2), "steel_painted", "post")
		if i < n:
			a, b = (x, 0, c), (x + bay, 0, depth - c)
			if i >= n / 2:
				a, b = (x, 0, depth - c), (x + bay, 0, c)
			kit.strut(a, b, c * 0.6, slot="steel_painted", name="diagonal")
	kit.socket("left", (-span / 2, 0, 0))
	kit.socket("right", (span / 2, 0, 0))


for _sp, _d, _k in ((12, 1.5, ""), (18, 1.5, "truss_steel_1500"), (24, 1.5, ""), (30, 3.0, "truss_steel_3000"), (36, 3.0, ""), (48, 3.0, "")):
	register("structure.truss.steel_%d" % _sp, steel_truss, "Steel truss, %d m span, %.1f m deep" % (_sp, _d), family="truss", kind=_k,
		tags=("structure", "roof", "steel"), span=float(_sp), depth=_d)


def portal(span, eaves, pitch=6.0):
	rise = span / 2 * math.tan(math.radians(pitch))
	d = 0.3 + span / 60
	for s in (-1, 1):
		x = s * span / 2
		kit.i_section(0.19, d, 0.015, 0.009, eaves, (x, 0, eaves / 2), "steel_painted", "column", axis="z", rot=(0, 0, 90))
		kit.box((0.5, 0.5, 0.025), (x, 0, 0.0125), "steel_painted", "base_plate")
		kit.strut((x, 0, eaves), (0, 0, eaves + rise), d * 0.8, 0.18, "steel_painted", "rafter")
		kit.prism([(0, 0), (-s * span * 0.1, 0), (0, -d * 1.2)], 0.012, (x - s * d / 2, 0, eaves - d * 0.2), "steel_painted", "haunch")
	kit.box((0.4, 0.02, d * 1.4), (0, 0, eaves + rise - d * 0.3), "steel_painted", "apex_plate")
	kit.socket("left", (-span / 2, 0, 0))
	kit.socket("right", (span / 2, 0, 0))


for _sp, _e in ((12, 4.0), (18, 6.0), (24, 6.0), (30, 8.0), (40, 10.0)):
	register("structure.frame.portal_%d" % _sp, portal, "Steel portal frame, %d m span, %.0f m eaves" % (_sp, _e), family="beam",
		tags=("structure", "steel", "frame"), span=float(_sp), eaves=_e)


def purlin(what):
	if what == "z":
		kit.prism([(-0.06, -0.1), (-0.058, -0.1), (-0.058, 0.098), (0.06, 0.098), (0.06, 0.1), (-0.06, 0.1), (-0.06, -0.098), (-0.0, -0.098)][::-1] if False else
			[(0.0, -0.1), (0.06, -0.1), (0.06, -0.098), (0.002, -0.098), (0.002, 0.1), (-0.06, 0.1), (-0.06, 0.098), (0.0, 0.098)], 1.0, slot="steel_galvanised", name="purlin")
	elif what == "timber":
		kit.box((0.075, 1.0, 0.2), (0, 0, 0), "softwood", "purlin")
	elif what == "rafter":
		kit.box((0.047, 1.0, 0.15), (0, 0, 0), "softwood", "rafter")
	elif what == "batten":
		kit.box((0.05, 1.0, 0.025), (0, 0, 0), "softwood", "batten")
	elif what == "tie_rod":
		kit.cyl(0.01, 1.0, slot="steel_galvanised", name="rod", axis="y", segs=8)


for _k, _l in (("z", "Z purlin, 200 mm"), ("timber", "Timber purlin, 75 by 200"), ("rafter", "Rafter, 47 by 150"), ("batten", "Tile batten, 25 by 50"), ("tie_rod", "Bracing tie rod, M20")):
	register("structure.roof." + _k, purlin, _l, family="roof", tags=("structure", "roof"), stretch="z", what=_k)

# --- roof coverings and details ------------------------------------------------------------

def covering(what):
	"""A 1 m square of roof covering lying flat (the game tilts it to the pitch); Y is up
	the slope."""
	if what in ("clay_tile", "slate", "concrete_tile"):
		slot = {"clay_tile": "clay_tile", "slate": "slate", "concrete_tile": "concrete"}[what]
		gauge = 0.2 if what == "slate" else 0.25
		n = round(1.0 / gauge)
		for i in range(n):
			y = -0.5 + (i + 0.5) / n
			kit.box((1.0, 1.0 / n + 0.06, 0.006 if what == "slate" else 0.014), (0, y + 0.03, 0.03 + (0.004 if what == "slate" else 0.008)), slot, "course", rot=(4, 0, 0))
			if what != "slate":
				for k in range(4):
					kit.cyl(0.03, 1.0 / n, (-0.375 + k * 0.25, y, 0.045), slot, "roll", axis="y", segs=8)
			kit.box((1.0, 0.05, 0.025), (0, y + 0.1, 0.0125), "softwood", "batten")
	elif what == "standing_seam":
		kit.box((1.0, 1.0, 0.002), (0, 0, 0.001), "lead" if False else "aluminium", "sheet")
		for x in (-0.4, 0.0, 0.4):
			kit.box((0.004, 1.0, 0.025), (x, 0, 0.0135), "aluminium", "seam")
	elif what == "felt":
		kit.box((1.0, 1.0, 0.006), (0, 0, 0.003), "roof_felt", "felt")
	elif what == "green":
		kit.box((1.0, 1.0, 0.1), (0, 0, 0.05), "soil", "substrate")
		kit.box((1.0, 1.0, 0.03), (0, 0, 0.115), "foliage", "sedum")
	elif what == "gravel":
		kit.box((1.0, 1.0, 0.05), (0, 0, 0.025), "paving", "ballast")


for _k, _l in (("clay_tile", "Clay roof tiles"), ("concrete_tile", "Concrete roof tiles"), ("slate", "Roof slates"), ("standing_seam", "Standing seam roof"),
		("felt", "Felt roof membrane"), ("green", "Green roof (sedum)"), ("gravel", "Ballasted roof")):
	register("roof.covering." + _k, covering, _l, family="roof", tags=("roof", "covering"), stretch="xz", what=_k)


def roof_run(what):
	"""1 m runs along Y: ridge, verge, eaves, gutter, coping."""
	if what == "ridge":
		kit.sweep([(0, -0.5, 0), (0, 0.5, 0)], [(-0.12, -0.06), (-0.11, -0.05), (0, 0.03), (0.11, -0.05), (0.12, -0.06), (0, 0.045)][::-1], "clay_tile", "ridge")
	elif what == "eaves":
		kit.box((0.02, 1.0, 0.2), (0, 0, -0.1), "paint_white", "fascia")
		kit.box((0.3, 1.0, 0.01), (-0.15, 0, -0.2), "paint_white", "soffit")
	elif what == "verge":
		kit.box((0.02, 1.0, 0.18), (0, 0, -0.09), "paint_white", "bargeboard")
	elif what == "gutter":
		kit.sweep([(0, -0.5, 0), (0, 0.5, 0)], [(0.056 * math.cos(math.radians(a)), 0.056 * math.sin(math.radians(a))) for a in range(180, 361, 20)] + [(0.053 * math.cos(math.radians(a)), 0.053 * math.sin(math.radians(a))) for a in range(360, 179, -20)], "plastic_black", "gutter")
		kit.box((0.02, 0.03, 0.07), (-0.06, 0, -0.01), "plastic_black", "bracket")
	elif what == "box_gutter":
		kit.prism([(-0.15, 0), (-0.15, -0.15), (0.15, -0.15), (0.15, 0), (0.147, 0), (0.147, -0.147), (-0.147, -0.147), (-0.147, 0)], 1.0, slot="lead", name="gutter")
	elif what == "coping":
		kit.prism([(-0.18, 0), (0.18, 0), (0.18, 0.04), (0, 0.06), (-0.18, 0.04)], 1.0, slot="concrete", name="coping")
	elif what == "parapet_cap":
		kit.prism([(-0.17, -0.06), (-0.17, 0.0), (0.17, 0.01), (0.17, -0.06), (0.168, -0.06), (0.168, 0.008), (-0.168, -0.002), (-0.168, -0.06)], 1.0, slot="aluminium", name="cap")
	elif what == "flashing":
		kit.prism([(0, 0), (0.15, 0), (0.15, 0.002), (0.002, 0.002), (0.002, 0.15), (0, 0.15)], 1.0, slot="lead", name="flashing")


for _k, _l in (("ridge", "Ridge tiles"), ("eaves", "Eaves fascia and soffit"), ("verge", "Bargeboard"), ("gutter", "Half-round gutter"), ("box_gutter", "Box gutter"),
		("coping", "Concrete coping"), ("parapet_cap", "Aluminium parapet capping"), ("flashing", "Lead flashing")):
	register("roof.edge." + _k, roof_run, _l, family="roof", tags=("roof", "rainwater" if "gutter" in _k else "edge"), stretch="z", what=_k)


@asset("roof.rainwater.downpipe", "68 mm downpipe", family="roof", tags=("roof", "rainwater"), stretch="y")
def downpipe():
	kit.tube(0.034, 1.0, (0, 0.05, 0.5), "plastic_black", "pipe", segs=14)
	kit.box((0.09, 0.05, 0.02), (0, 0.025, 0.5), "plastic_black", "clip")


@asset("roof.rainwater.outlet", "Gutter running outlet", family="roof", tags=("roof", "rainwater"))
def outlet():
	kit.box((0.12, 0.16, 0.06), (0, 0, -0.03), "plastic_black", "outlet")
	kit.tube(0.034, 0.1, (0, 0, -0.1), "plastic_black", "spigot", segs=14)


@asset("roof.rainwater.shoe", "Downpipe shoe", family="roof", tags=("roof", "rainwater"))
def shoe():
	kit.sweep(kit.arc((0, 0.05 + 0.08, 0.08), 0.08, 180, 270, 6, plane="yz") if False else [(0, 0.05, 0.25), (0, 0.05, 0.1), (0, 0.08, 0.05), (0, 0.15, 0.03)], kit.circle(0.034, 14), "plastic_black", "shoe", up=(1, 0, 0))


@asset("roof.rainwater.hopper", "Rainwater hopper head", family="roof", tags=("roof", "rainwater"))
def hopper():
	kit.prism([(-0.12, 0.2), (0.12, 0.2), (0.05, 0.0), (-0.05, 0.0)], 0.14, (0, 0.07, 0), "lead", "hopper")
	kit.tube(0.034, 0.15, (0, 0.07, -0.075), "lead", "spigot", segs=14)


def chimney(pots, w):
	h = 1.6
	kit.box((w, 0.56, h), (0, 0, h / 2), "brick", "stack")
	kit.box((w + 0.1, 0.66, 0.08), (0, 0, h + 0.04), "concrete", "cap")
	for i in range(pots):
		x = (i - (pots - 1) / 2) * 0.36
		kit.lathe([(0.11, 0), (0.1, 0.25), (0.12, 0.28), (0.12, 0.33), (0.09, 0.33)], (x, 0, h + 0.08), "clay_tile", "pot", segs=16)
	kit.box((w + 0.04, 0.6, 0.15), (0, 0, 0.075), "lead", "flashing")


register("roof.chimney.single", chimney, "Chimney stack, one pot", family="roof", tags=("roof",), pots=1, w=0.56)
register("roof.chimney.double", chimney, "Chimney stack, two pots", family="roof", tags=("roof",), pots=2, w=0.9)
register("roof.chimney.triple", chimney, "Chimney stack, three pots", family="roof", tags=("roof",), pots=3, w=1.25)


def rooflight(w, h):
	kit.frame(w, h, 0.07, 0.12, at=(0, 0, 0), slot="plastic_grey", name="frame")
	kit.box((w - 0.14, 0.024, h - 0.14), (0, 0.02, h / 2), "glass", "pane")
	kit.box((w + 0.12, 0.01, h + 0.12), (0, -0.06, h / 2), "lead", "flashing")
	kit.box((w * 0.5, 0.03, 0.03), (0, 0.07, h - 0.05), "plastic_grey", "handle_bar")


for _n, _w, _h in (("550x980", 0.55, 0.98), ("780x1180", 0.78, 1.18), ("1140x1180", 1.14, 1.18), ("1340x1400", 1.34, 1.4)):
	register("roof.rooflight." + _n, rooflight, "Roof window, %s" % _n.replace("x", " by "), family="roof", tags=("roof", "glazing"), w=_w, h=_h)


@asset("roof.rooflight.lantern", "Roof lantern, 2 m by 1 m", family="roof", tags=("roof", "glazing"))
def lantern(w=2.0, d=1.0, h=0.5):
	kit.frame(w, d, 0.06, 0.15, at=(0, 0, 0), slot="aluminium", name="kerb") if False else None
	for s in (-1, 1):
		kit.box((w, 0.06, 0.15), (0, s * (d / 2 - 0.03), 0.075), "aluminium", "kerb")
		kit.box((0.06, d, 0.15), (s * (w / 2 - 0.03), 0, 0.075), "aluminium", "kerb")
		kit.strut((-w / 2 + d / 2, 0, 0.15 + h), (s * 0 - w / 2, s * d / 2, 0.15), 0.04, slot="aluminium", name="hip")
		kit.strut((w / 2 - d / 2, 0, 0.15 + h), (w / 2, s * d / 2, 0.15), 0.04, slot="aluminium", name="hip")
		kit.prism([(-w / 2, 0), (w / 2, 0), (w / 2 - d / 2, math.hypot(d / 2, h)), (-w / 2 + d / 2, math.hypot(d / 2, h))], 0.012,
			(0, s * d / 4, 0.15 + h / 2), "glass", "pane", axis="y", rot=(s * -(90 - math.degrees(math.atan2(h, d / 2))), 0, 0))
	kit.box((w - d, 0.05, 0.05), (0, 0, 0.15 + h), "aluminium", "ridge")


@asset("roof.dormer.pitched", "Pitched dormer window", family="roof", tags=("roof", "glazing"))
def dormer(w=1.4, h=1.3, d=1.6):
	for s in (-1, 1):
		kit.prism([(0, 0), (d, 0), (0, h)][::s] if False else [(-d / 2, 0), (d / 2, 0), (d / 2, h), (-d / 2 + 0.0, h)], 0.1, (s * (w / 2 - 0.05), 0, 0), "softwood", "cheek", axis="x")
		kit.strut((s * (w / 2 + 0.1), 0.0, h), (0, 0.0, h + 0.55), 0.03, d + 0.2, "clay_tile", "roof_slope")
	kit.prism([(-w / 2, h), (w / 2, h), (0, h + 0.5)], 0.02, (0, d / 2, 0), "paint_white", "gable")
	kit.frame(w - 0.3, h - 0.2, 0.06, 0.08, at=(0, d / 2, 0.1), slot="paint_white", name="frame")
	kit.box((w - 0.4, 0.02, h - 0.32), (0, d / 2, h / 2 + 0.05), "glass", "pane")
	kit.box((0.04, 0.06, h - 0.3), (0, d / 2, h / 2 + 0.05), "paint_white", "mullion")


def roof_kit(what):
	if what == "solar_panel":
		kit.box((1.0, 1.7, 0.035), (0, 0, 0.08), "screen", "panel", rot=(0, 0, 0))
		kit.frame(1.0, 1.7, 0.02, 0.04, at=(0, 0.0, 0.0), slot="aluminium", name="frame") if False else None
		for x in (-0.3, 0.3):
			kit.box((0.04, 1.8, 0.04), (x, 0, 0.04), "aluminium", "rail")
	elif what == "access_hatch":
		kit.box((0.9, 0.9, 0.25), (0, 0, 0.125), "aluminium", "kerb")
		kit.box((0.96, 0.96, 0.05), (0, 0, 0.275), "aluminium", "lid")
		kit.box((0.2, 0.03, 0.03), (0, 0.4, 0.31), "plastic_black", "handle")
	elif what == "flue_terminal":
		kit.cyl(0.075, 0.9, (0, 0, 0.45), "steel_stainless", "flue", segs=16)
		kit.lathe([(0.14, 0.9), (0.1, 0.98), (0.0, 1.0)], slot="steel_stainless", name="cowl", segs=16)
		kit.lathe([(0.25, 0.0), (0.08, 0.12)], slot="lead", name="flashing", segs=16)
	elif what == "aerial":
		kit.rod((0, 0, 0), (0, 0, 1.8), 0.016, "aluminium", "mast")
		kit.rod((0, -0.5, 1.7), (0, 0.5, 1.7), 0.008, "aluminium", "boom")
		for i in range(8):
			kit.rod((-0.15, -0.45 + i * 0.12, 1.7), (0.15, -0.45 + i * 0.12, 1.7), 0.004, "aluminium", "element", segs=6)
	elif what == "satellite_dish":
		kit.lathe([(0.0, 0.0), (0.15, 0.015), (0.3, 0.06), (0.3, 0.065), (0.0, 0.006)], (0, 0.25, 0.3), "plastic_grey", "dish", segs=24)
		kit.rod((0, 0, 0.3), (0, 0.25, 0.3), 0.012, "steel_galvanised", "arm")
		kit.box((0.12, 0.01, 0.12), (0, 0.005, 0.3), "steel_galvanised", "bracket")
	elif what == "vent_tile":
		kit.box((0.33, 0.42, 0.02), (0, 0, 0.01), "clay_tile", "tile")
		kit.box((0.2, 0.2, 0.05), (0, 0, 0.04), "clay_tile", "hood")
	elif what == "snow_guard":
		for y in (0, 0.06):
			kit.rod((-0.5, y, 0.1 + y), (0.5, y, 0.1 + y), 0.012, "steel_galvanised", "rail")
		for x in (-0.4, 0.4):
			kit.box((0.03, 0.15, 0.16), (x, 0.02, 0.08), "steel_galvanised", "bracket")
	elif what == "roof_anchor":
		kit.cyl(0.02, 0.4, (0, 0, 0.2), "steel_stainless", "post", segs=12)
		kit.cyl(0.1, 0.01, (0, 0, 0.005), "steel_stainless", "plate", segs=18)
		kit.tube(0.03, 0.01, (0, 0, 0.42), "plastic_yellow", "eye", axis="y", wall=0.008, segs=14)
	elif what == "lightning_rod":
		kit.rod((0, 0, 0), (0, 0, 1.5), 0.008, "copper", "rod")
		kit.box((0.1, 0.1, 0.02), (0, 0, 0.01), "copper", "base")


for _k, _l in (("solar_panel", "Solar panel on rails"), ("access_hatch", "Roof access hatch"), ("flue_terminal", "Flue terminal"), ("aerial", "TV aerial"),
		("satellite_dish", "Satellite dish"), ("vent_tile", "Roof vent tile"), ("snow_guard", "Snow guard"), ("roof_anchor", "Fall-arrest anchor"), ("lightning_rod", "Lightning rod")):
	register("roof.kit." + _k, roof_kit, _l, family="roof", tags=("roof",), what=_k)

# --- steelwork connections -----------------------------------------------------------------

def bolts(points, axis="y", r=0.012, length=0.05):
	for p in points:
		kit.cyl(r, length, p, "steel_galvanised", "bolt", axis=axis, segs=8)
		kit.cyl(r * 1.7, r * 1.2, p, "steel_galvanised", "nut", axis=axis, segs=6)


def connection(what):
	if what == "fin_plate":
		kit.box((0.01, 0.1, 0.22), (0, 0.05, 0), "steel_painted", "plate")
		bolts([(0, 0.06, z) for z in (-0.07, 0, 0.07)], "x")
	elif what == "angle_cleats":
		for s in (-1, 1):
			kit.angle(0.09, 0.01, 0.22, (s * 0.006, 0, -0.11), "steel_painted", "cleat", axis="z", rot=(0, 0, 0 if s > 0 else 90))
		bolts([(0, 0.05, z) for z in (-0.07, 0, 0.07)], "x")
	elif what == "flange_splice":
		for z in (-0.16, 0.16):
			kit.box((0.18, 0.5, 0.012), (0, 0, z), "steel_painted", "cover_plate")
			bolts([(x, y, z) for x in (-0.05, 0.05) for y in (-0.19, -0.09, 0.09, 0.19)], "z")
		kit.box((0.01, 0.3, 0.2), (0.01, 0, 0), "steel_painted", "web_plate")
	elif what == "haunch":
		kit.prism([(0, 0), (0.9, 0), (0, -0.4)], 0.01, slot="steel_painted", name="web")
		kit.strut((0, 0, -0.4), (0.9, 0, 0), 0.012, 0.16, "steel_painted", "flange")
	elif what == "gusset":
		kit.prism([(0, 0), (0.35, 0), (0.35, 0.1), (0.1, 0.35), (0, 0.35)], 0.012, slot="steel_painted", name="gusset")
		bolts([(0.16, 0, 0.16), (0.22, 0, 0.1), (0.1, 0, 0.22)], "y")
	elif what == "column_cap":
		kit.box((0.3, 0.3, 0.02), (0, 0, 0.01), "steel_painted", "cap_plate")
		bolts([(x, y, 0.02) for x in (-0.1, 0.1) for y in (-0.1, 0.1)], "z")
	elif what == "holding_down":
		for x in (-0.15, 0.15):
			for y in (-0.15, 0.15):
				kit.rod((x, y, -0.45), (x, y, 0.12), 0.012, "steel_galvanised", "bolt")
				kit.box((0.1, 0.1, 0.012), (x, y, -0.45), "steel_galvanised", "anchor_plate")
		kit.box((0.42, 0.42, 0.006), (0, 0, 0.1), "plywood", "template")
	elif what == "purlin_cleat":
		kit.box((0.008, 0.15, 0.2), (0, 0, 0.1), "steel_galvanised", "cleat")
		kit.box((0.1, 0.15, 0.008), (0.05, 0, 0.004), "steel_galvanised", "foot")
		bolts([(0, 0, 0.07), (0, 0, 0.15)], "x", 0.008, 0.04)
	elif what == "shear_stud":
		kit.cyl(0.0095, 0.1, (0, 0, 0.05), "steel_painted", "shank", segs=10)
		kit.cyl(0.016, 0.01, (0, 0, 0.1), "steel_painted", "head", segs=10)
	elif what == "turnbuckle":
		kit.tube(0.018, 0.2, slot="steel_galvanised", name="body", axis="y", wall=0.006, segs=10)
		for s in (-1, 1):
			kit.rod((0, s * 0.1, 0), (0, s * 0.3, 0), 0.01, "steel_galvanised", "rod")
			kit.box((0.012, 0.06, 0.05), (0, s * 0.33, 0), "steel_galvanised", "fork")
	elif what == "joist_hanger":
		kit.prism([(-0.026, 0), (0.026, 0), (0.026, 0.2), (0.024, 0.2), (0.024, 0.002), (-0.024, 0.002), (-0.024, 0.2), (-0.026, 0.2)], 0.075, (0, 0.0375, 0), "steel_galvanised", "hanger")
	elif what == "wall_tie":
		kit.rod((0, -0.1, 0), (0, 0.1, 0), 0.002, "steel_stainless", "tie", segs=5)
		kit.cyl(0.03, 0.003, (0, 0, 0), "plastic_black", "retaining_disc", axis="y", segs=12)
	kit.socket("fix", (0, 0, 0))


for _k, _l in (("fin_plate", "Fin plate connection"), ("angle_cleats", "Double angle cleats"), ("flange_splice", "Column splice plates"), ("haunch", "Portal haunch"),
		("gusset", "Bracing gusset plate"), ("column_cap", "Column cap plate"), ("holding_down", "Holding-down bolt set"), ("purlin_cleat", "Purlin cleat"),
		("shear_stud", "Shear stud"), ("turnbuckle", "Bracing turnbuckle"), ("joist_hanger", "Joist hanger"), ("wall_tie", "Cavity wall tie")):
	register("structure.connection." + _k, connection, _l, family="beam", tags=("structure", "connection"), what=_k)
