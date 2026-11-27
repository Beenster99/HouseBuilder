"""Building services (M&E): pipework, ductwork, cable containment, heat emitters, electrical
points, fire and security devices, and plant. Straight runs are 1 m along Y, centred, and
stretch in the game. Fittings sit on their junction. Wall items have their back on y = 0."""
import math

import kit
from registry import asset, register

# --- pipework ------------------------------------------------------------------------------
PIPES = {15: "copper", 22: "copper", 28: "copper", 35: "copper", 54: "steel_painted", 110: "plastic_grey"}


def pipe_run(dia, slot):
	kit.tube(dia / 2000, 1.0, slot=slot, name="pipe", axis="y", segs=14)
	kit.socket("a", (0, -0.5, 0))
	kit.socket("b", (0, 0.5, 0))


def pipe_elbow(dia, slot):
	r = dia / 2000
	b = max(0.03, r * 3)
	kit.sweep(kit.arc((b, -b, 0), b, 180, 90, 8), kit.circle(r, 14), slot, "bend")
	for at, ax in (((0, -b, 0), "y"), ((b, 0, 0), "x")):
		kit.cyl(r * 1.25, r * 1.6, at, slot, "collar", axis=ax, segs=14)
	kit.socket("a", (0, -b, 0))
	kit.socket("b", (b, 0, 0))


def pipe_tee(dia, slot):
	r = dia / 2000
	L = max(0.08, r * 6)
	kit.tube(r, L, slot=slot, name="run", axis="y", segs=14)
	kit.tube(r, L / 2, (L / 4, 0, 0), slot, "branch", axis="x", segs=14)
	for at, ax in (((0, -L / 2, 0), "y"), ((0, L / 2, 0), "y"), ((L / 2, 0, 0), "x")):
		kit.cyl(r * 1.25, r * 1.6, at, slot, "collar", axis=ax, segs=14)
	kit.socket("a", (0, -L / 2, 0))
	kit.socket("b", (0, L / 2, 0))
	kit.socket("branch", (L / 2, 0, 0))


def pipe_valve(dia, slot):
	r = dia / 2000
	L = max(0.08, r * 6)
	kit.tube(r, L, slot=slot, name="run", axis="y", segs=14)
	kit.cyl(r * 1.7, r * 3, (0, 0, 0), "brass", "body", axis="y", segs=14)
	kit.cyl(r * 0.8, r * 3, (0, 0, r * 2.2), "brass", "stem", segs=10)
	kit.box((r * 1.2, r * 7, r * 0.8), (0, r * 2, r * 4), "plastic_red", "lever")
	kit.socket("a", (0, -L / 2, 0))
	kit.socket("b", (0, L / 2, 0))


def pipe_clip(dia, slot):
	r = dia / 2000
	kit.tube(r + 0.004, 0.02, slot="steel_galvanised", name="band", axis="y", wall=0.003, segs=14)
	kit.rod((0, 0, r), (0, 0, r + 0.08), 0.004, "steel_galvanised", "drop_rod", segs=6)
	kit.socket("fix", (0, 0, r + 0.08))


for _d, _s in PIPES.items():
	_t = ("services", "pipe", "plumbing")
	register("services.pipe.run_%d" % _d, pipe_run, "%d mm pipe" % _d, tags=_t, stretch="z", dia=_d, slot=_s)
	register("services.pipe.elbow_%d" % _d, pipe_elbow, "%d mm elbow" % _d, tags=_t, dia=_d, slot=_s)
	register("services.pipe.tee_%d" % _d, pipe_tee, "%d mm tee" % _d, tags=_t, dia=_d, slot=_s)
	register("services.pipe.valve_%d" % _d, pipe_valve, "%d mm isolating valve" % _d, tags=_t, dia=_d, slot=_s)
	register("services.pipe.clip_%d" % _d, pipe_clip, "%d mm pipe hanger" % _d, tags=_t, dia=_d, slot=_s)


@asset("services.pipe.lagged_run_54", "54 mm insulated pipe", tags=("services", "pipe", "heating"), stretch="z")
def lagged():
	kit.tube(0.052, 1.0, slot="insulation", name="lagging", axis="y", segs=16)


# --- ductwork ------------------------------------------------------------------------------
DUCTS = [(300, 200), (400, 300), (600, 400), (800, 500), (1200, 600)]


def _flange(w, h, y):
	kit.frame(w + 0.05, h + 0.05, 0.03, 0.006, at=(0, y, -h / 2 - 0.025), slot="steel_galvanised", name="flange")


def duct_run(w, h):
	w, h = w / 1000, h / 1000
	for x in (-w / 2, w / 2):
		kit.box((0.002, 1.0, h), (x, 0, 0), "steel_galvanised", "side")
	for z in (-h / 2, h / 2):
		kit.box((w, 1.0, 0.002), (0, 0, z), "steel_galvanised", "panel")
	_flange(w, h, -0.497)
	_flange(w, h, 0.497)


def duct_bend(w, h):
	w, h = w / 1000, h / 1000
	b = w * 0.75 + 0.1
	kit.sweep(kit.arc((b, -b, 0), b, 180, 90, 8), kit.rect(w, h), "steel_galvanised", "bend")
	kit.socket("a", (0, -b, 0))
	kit.socket("b", (b, 0, 0))


def duct_tee(w, h):
	w, h = w / 1000, h / 1000
	L = w + 0.4
	kit.box((w, L, h), (0, 0, 0), "steel_galvanised", "run")
	kit.box((0.3, w * 0.8, h * 0.8), (w / 2 + 0.15, 0, 0), "steel_galvanised", "branch")
	_flange(w, h, -L / 2)
	_flange(w, h, L / 2)
	kit.socket("branch", (w / 2 + 0.3, 0, 0))


def duct_damper(w, h):
	w, h = w / 1000, h / 1000
	kit.box((w + 0.04, 0.2, h + 0.04), (0, 0, 0), "steel_galvanised", "casing")
	kit.box((0.1, 0.12, 0.14), (w / 2 + 0.07, 0, 0), "plastic_grey", "actuator")


for _w, _h in DUCTS:
	_t = ("services", "duct", "ventilation")
	_n = "%dx%d" % (_w, _h)
	register("services.duct.run_" + _n, duct_run, "%s duct" % _n.replace("x", " x "), tags=_t, stretch="z", w=_w, h=_h)
	register("services.duct.bend_" + _n, duct_bend, "%s duct bend" % _n.replace("x", " x "), tags=_t, w=_w, h=_h)
	register("services.duct.tee_" + _n, duct_tee, "%s duct branch" % _n.replace("x", " x "), tags=_t, w=_w, h=_h)
	register("services.duct.damper_" + _n, duct_damper, "%s fire damper" % _n.replace("x", " x "), tags=_t, w=_w, h=_h)


def round_duct(dia, what):
	r = dia / 2000
	if what == "run":
		kit.tube(r, 1.0, slot="steel_galvanised", name="duct", axis="y", wall=0.002, segs=20)
		for y in (-0.33, 0, 0.33):
			kit.cyl(r + 0.004, 0.012, (0, y, 0), "steel_galvanised", "seam", axis="y", segs=20)
	elif what == "bend":
		b = r * 2 + 0.05
		kit.sweep(kit.arc((b, -b, 0), b, 180, 90, 8), kit.circle(r, 20), "steel_galvanised", "bend")
	else:
		kit.sweep([(0, -0.5, 0), (0.02, -0.25, 0.03), (-0.02, 0, -0.02), (0.03, 0.25, 0.02), (0, 0.5, 0)], kit.circle(r, 16), "insulation", "flexible")


for _d in (100, 160, 250, 315, 500):
	for _k, _l in (("run", "spiral duct"), ("bend", "duct bend"), ("flex", "flexible duct")):
		register("services.duct.round_%s_%d" % (_k, _d), round_duct, "%d mm %s" % (_d, _l), tags=("services", "duct", "ventilation"),
			stretch="z" if _k != "bend" else "", dia=_d, what=_k)


def grille(w, h, what):
	w, h = w / 1000, h / 1000
	if what == "ceiling":
		kit.box((w, w, 0.01), (0, 0, -0.005), "paint_white", "plate")
		for i in range(1, 4):
			s = w * (1 - i * 0.22)
			kit.frame(s, s, 0.012, 0.012, at=(0, 0, 0), slot="paint_white", name="ring")
		kit.box((w * 0.6, w * 0.6, 0.15), (0, 0, 0.075), "steel_galvanised", "plenum")
	else:
		kit.frame(w, h, 0.02, 0.02, at=(0, 0.01, 0), slot="paint_white", name="frame")
		n = max(3, int(h / 0.025))
		for i in range(n):
			kit.box((w - 0.04, 0.02, 0.003), (0, 0.012, 0.02 + (h - 0.04) * (i + 0.5) / n), "paint_white", "blade", rot=(35, 0, 0))


register("services.grille.ceiling_diffuser_600", grille, "600 mm ceiling diffuser", tags=("services", "ventilation"), w=595, h=595, what="ceiling")
register("services.grille.ceiling_diffuser_300", grille, "300 mm ceiling diffuser", tags=("services", "ventilation"), w=295, h=295, what="ceiling")
register("services.grille.wall_300x150", grille, "300 x 150 wall grille", tags=("services", "ventilation"), w=300, h=150, what="wall")
register("services.grille.wall_600x300", grille, "600 x 300 wall grille", tags=("services", "ventilation"), w=600, h=300, what="wall")
register("services.grille.louvre_1200x900", grille, "1200 x 900 external louvre", tags=("services", "ventilation"), w=1200, h=900, what="wall")

# --- cable containment ---------------------------------------------------------------------

def tray_run(w, ladder=False):
	w = w / 1000
	for s in (-1, 1):
		kit.box((0.002 if not ladder else 0.02, 1.0, 0.05 if not ladder else 0.1), (s * w / 2, 0, 0.025 if not ladder else 0.05), "steel_galvanised", "side")
	if ladder:
		for i in range(4):
			kit.box((w, 0.03, 0.02), (0, -0.375 + i * 0.25, 0.02), "steel_galvanised", "rung")
	else:
		kit.box((w, 1.0, 0.002), (0, 0, 0.001), "steel_galvanised", "base")
		for i in range(10):
			kit.box((w * 0.7, 0.012, 0.003), (0, -0.45 + i * 0.1, 0.002), "plastic_black", "slot")
	n = max(2, int(w / 0.04))
	for i in range(n):
		kit.rod((-w / 2 + w * (i + 0.5) / n, -0.5, 0.02), (-w / 2 + w * (i + 0.5) / n, 0.5, 0.02), 0.007, ("plastic_grey", "plastic_black", "plastic_blue")[i % 3], "cable", segs=6)


def tray_bend(w):
	w = w / 1000
	b = w / 2 + 0.15
	kit.sweep(kit.arc((b, -b, 0), b, 180, 90, 8), [(-w / 2, 0), (w / 2, 0), (w / 2, 0.05), (w / 2 - 0.002, 0.05), (w / 2 - 0.002, 0.002), (-w / 2 + 0.002, 0.002), (-w / 2 + 0.002, 0.05), (-w / 2, 0.05)], "steel_galvanised", "bend")


def tray_tee(w):
	w = w / 1000
	L = w + 0.3
	kit.box((w, L, 0.002), (0, 0, 0.001), "steel_galvanised", "base")
	kit.box((0.15, w, 0.002), (w / 2 + 0.075, 0, 0.001), "steel_galvanised", "branch")
	kit.box((0.002, L, 0.05), (-w / 2, 0, 0.025), "steel_galvanised", "side")
	for y in (-1, 1):
		kit.box((0.002, 0.15, 0.05), (w / 2, y * (L / 2 - 0.075), 0.025), "steel_galvanised", "side")
		kit.box((0.15, 0.002, 0.05), (w / 2 + 0.075, y * w / 2, 0.025), "steel_galvanised", "side")


def tray_hanger(w):
	w = w / 1000
	kit.box((w + 0.1, 0.04, 0.04), (0, 0, -0.02), "steel_galvanised", "channel")
	for s in (-1, 1):
		kit.rod((s * (w / 2 + 0.03), 0, -0.02), (s * (w / 2 + 0.03), 0, 0.6), 0.005, "steel_galvanised", "drop_rod", segs=6)


for _w in (100, 150, 300, 450, 600):
	_t = ("services", "electrical", "containment")
	register("services.tray.run_%d" % _w, tray_run, "%d mm cable tray with cables" % _w, tags=_t, stretch="z", w=_w)
	register("services.tray.bend_%d" % _w, tray_bend, "%d mm tray bend" % _w, tags=_t, w=_w)
	register("services.tray.tee_%d" % _w, tray_tee, "%d mm tray tee" % _w, tags=_t, w=_w)
	register("services.tray.hanger_%d" % _w, tray_hanger, "%d mm trapeze hanger" % _w, tags=_t, w=_w)
for _w in (300, 600, 900):
	register("services.tray.ladder_%d" % _w, tray_run, "%d mm cable ladder with cables" % _w, tags=("services", "electrical", "containment"), stretch="z", w=_w, ladder=True)


def trunking(w, h, slot):
	kit.box((w / 1000, 1.0, h / 1000), (0, 0, h / 2000), slot, "trunking")
	kit.box((w / 1000 * 0.9, 1.0, 0.002), (0, 0, h / 1000), slot, "lid")


register("services.trunking.steel_100x100", trunking, "100 x 100 steel trunking", tags=("services", "electrical", "containment"), stretch="z", w=100, h=100, slot="steel_galvanised")
register("services.trunking.steel_50x50", trunking, "50 x 50 steel trunking", tags=("services", "electrical", "containment"), stretch="z", w=50, h=50, slot="steel_galvanised")
register("services.trunking.dado_170x50", trunking, "Dado trunking", tags=("services", "electrical", "containment"), stretch="z", w=50, h=170, slot="plastic_white")
register("services.trunking.mini_25x16", trunking, "Mini trunking", tags=("services", "electrical", "containment"), stretch="z", w=25, h=16, slot="plastic_white")
register("services.conduit.steel_20", pipe_run, "20 mm steel conduit", tags=("services", "electrical", "containment"), stretch="z", dia=20, slot="steel_galvanised")
register("services.conduit.steel_25", pipe_run, "25 mm steel conduit", tags=("services", "electrical", "containment"), stretch="z", dia=25, slot="steel_galvanised")

# --- heat emitters -------------------------------------------------------------------------

def radiator(length, h, double):
	L, H = length / 1000, h / 1000
	for k in range(2 if double else 1):
		y = 0.03 + k * 0.07
		kit.box((L, 0.012, H), (0, y, 0.15 + H / 2), "paint_white", "panel")
		n = int(L / 0.035)
		for i in range(n):
			kit.box((0.02, 0.022, H - 0.04), (-L / 2 + L * (i + 0.5) / n, y, 0.15 + H / 2), "paint_white", "flute")
	if double:
		for i in range(int(L / 0.03)):
			kit.box((0.002, 0.05, H - 0.06), (-L / 2 + 0.015 + i * 0.03, 0.065, 0.15 + H / 2), "paint_white", "fin")
	kit.box((L, 0.1 if double else 0.03, 0.01), (0, 0.065 if double else 0.03, 0.15 + H), "paint_white", "top_grille")
	for s in (-1, 1):
		kit.cyl(0.012, 0.05, (s * (L / 2 + 0.02), 0.03, 0.17), "steel_stainless", "valve", axis="x", segs=10)
		kit.rod((s * (L / 2 + 0.04), 0.03, 0.17), (s * (L / 2 + 0.04), 0.03, 0.0), 0.0075, "copper", "tail", segs=8)
	kit.cyl(0.017, 0.07, (L / 2 + 0.04, 0.03, 0.2), "plastic_white", "trv", segs=12)


for _l in (600, 1000, 1400, 1800):
	for _dbl in (False, True):
		register("services.radiator.%s_%d" % ("double" if _dbl else "single", _l), radiator, "%d mm %s panel radiator" % (_l, "double" if _dbl else "single"),
			tags=("services", "heating"), length=_l, h=600, double=_dbl)
register("services.radiator.low_2000", radiator, "2000 mm low-level radiator", tags=("services", "heating"), length=2000, h=300, double=True)


@asset("services.radiator.towel_rail", "Heated towel rail", tags=("services", "heating", "bathroom"))
def towel_rail(w=0.5, h=1.2):
	for s in (-1, 1):
		kit.rod((s * w / 2, 0.06, 0.2), (s * w / 2, 0.06, 0.2 + h), 0.015, "steel_stainless", "upright")
	for i in range(12):
		z = 0.25 + i * (h - 0.1) / 11 + (0.04 if i % 4 == 3 else 0)
		kit.rod((-w / 2, 0.06, z), (w / 2, 0.06, z), 0.01, "steel_stainless", "rail", segs=8)


@asset("services.heating.underfloor_manifold", "Underfloor heating manifold, 6 port", tags=("services", "heating"))
def manifold(ports=6):
	for z, slot in ((0.5, "plastic_red"), (0.3, "plastic_blue")):
		kit.rod((-0.05 * ports, 0.05, z), (0.05 * ports, 0.05, z), 0.02, "steel_stainless", "bar")
		for i in range(ports):
			x = -0.05 * ports + 0.05 + i * 0.1
			kit.cyl(0.012, 0.05, (x, 0.05, z + 0.04), slot, "actuator", segs=10)
			kit.rod((x, 0.05, z - 0.02), (x, 0.05, 0.0), 0.008, "plastic_white", "loop_pipe", segs=8)
	kit.box((0.1 * ports + 0.1, 0.01, 0.6), (0, 0.005, 0.35), "steel_galvanised", "backplate")


# --- electrical points ---------------------------------------------------------------------

def faceplate(what):
	w = 0.146 if what in ("double_socket", "cooker") else 0.086
	kit.rounded_box((w, 0.01, 0.086), (0, 0.005, 0.043), "plastic_white", "plate", radius=0.003, segments=2)
	if what == "socket" or what == "double_socket":
		for x in ((0,) if what == "socket" else (-0.03, 0.03)):
			for dx, dz, sz in ((0, 0.058, (0.007, 0.004, 0.009)), (-0.011, 0.036, (0.009, 0.004, 0.005)), (0.011, 0.036, (0.009, 0.004, 0.005))):
				kit.box(sz, (x + dx, 0.01, dz), "plastic_black", "pin_hole")
			kit.box((0.012, 0.006, 0.02), (x, 0.012, 0.016), "plastic_white", "rocker", rot=(8, 0, 0))
	elif what in ("switch", "switch_2g", "fused_spur", "cooker"):
		n = 2 if what == "switch_2g" else 1
		for i in range(n):
			kit.box((0.022 if n == 1 else 0.016, 0.008, 0.03), ((i - (n - 1) / 2) * 0.03, 0.012, 0.043), "plastic_white" if what != "cooker" else "plastic_red", "rocker", rot=(8, 0, 0))
		if what == "fused_spur":
			kit.box((0.02, 0.004, 0.012), (0.022, 0.011, 0.043), "plastic_black", "fuse")
	elif what == "data":
		for x in (-0.018, 0.018):
			kit.box((0.016, 0.004, 0.014), (x, 0.01, 0.043), "plastic_black", "rj45")
	elif what == "thermostat":
		kit.cyl(0.03, 0.012, (0, 0.016, 0.043), "plastic_white", "dial", axis="y", segs=20)
		kit.box((0.03, 0.002, 0.014), (0, 0.023, 0.043), "screen", "display")
	kit.socket("wall", (0, 0, 0.043))


for _k, _l in (("socket", "Single socket"), ("double_socket", "Double socket"), ("switch", "Light switch"), ("switch_2g", "Two-gang light switch"),
		("fused_spur", "Fused spur"), ("cooker", "Cooker switch"), ("data", "Twin data outlet"), ("thermostat", "Room thermostat")):
	register("services.point." + _k, faceplate, _l, tags=("services", "electrical", "point"), what=_k)


def light(what):
	if what == "pendant":
		kit.cyl(0.045, 0.02, (0, 0, -0.01), "plastic_white", "rose", segs=16)
		kit.rod((0, 0, -0.02), (0, 0, -0.5), 0.003, "plastic_white", "flex", segs=6)
		kit.cyl(0.02, 0.06, (0, 0, -0.53), "plastic_white", "holder", segs=12)
		kit.lathe([(0.06, -0.72), (0.16, -0.72), (0.12, -0.56), (0.04, -0.56)], slot="fabric_white", name="shade", segs=20)
		kit.sphere(0.03, (0, 0, -0.6), "light_emitter", "lamp", segs=12)
	elif what == "downlight":
		kit.cyl(0.045, 0.004, (0, 0, -0.002), "paint_white", "bezel", segs=20)
		kit.cyl(0.035, 0.002, (0, 0, -0.005), "light_emitter", "lens", segs=20)
		kit.cyl(0.036, 0.09, (0, 0, 0.045), "aluminium", "can", segs=16)
	elif what == "batten":
		kit.box((0.07, 1.2, 0.04), (0, 0, -0.02), "paint_white", "body")
		kit.rounded_box((0.06, 1.18, 0.03), (0, 0, -0.05), "light_emitter", "diffuser", radius=0.012, segments=2)
	elif what == "panel":
		kit.frame(0.595, 0.595, 0.012, 0.012, at=(0, 0, -0.2975), slot="paint_white", name="frame")
		kit.box((0.57, 0.57, 0.008), (0, 0, -0.006), "light_emitter", "panel")
	elif what == "highbay":
		kit.lathe([(0.05, -0.02), (0.2, -0.16), (0.2, -0.18), (0.04, -0.18)], slot="aluminium", name="reflector", segs=24)
		kit.cyl(0.19, 0.004, (0, 0, -0.181), "light_emitter", "lens", segs=24)
		kit.cyl(0.07, 0.1, (0, 0, 0.03), "plastic_black", "driver", segs=14)
		kit.rod((0, 0, 0.08), (0, 0, 0.5), 0.004, "steel_galvanised", "chain", segs=6)
	elif what == "bulkhead":
		kit.cyl(0.13, 0.03, (0, 0.015, 0), "plastic_black", "base", axis="y", segs=22)
		kit.lathe([(0.12, 0.0), (0.11, 0.04), (0.06, 0.065), (0.0, 0.07)], slot="light_emitter", name="dome", segs=22)
	elif what == "emergency":
		kit.box((0.35, 0.07, 0.12), (0, 0.035, 0), "paint_white", "body")
		kit.box((0.33, 0.004, 0.1), (0, 0.072, 0), "light_emitter", "lens")
	elif what == "exit_sign":
		kit.box((0.36, 0.05, 0.03), (0, 0.025, 0.1), "paint_white", "gear")
		kit.box((0.34, 0.008, 0.17), (0, 0.025, 0), "plastic_green", "legend")
	elif what == "floodlight":
		kit.box((0.3, 0.06, 0.22), (0, 0.1, 0), "plastic_black", "body", rot=(-25, 0, 0))
		kit.box((0.27, 0.005, 0.19), (0, 0.128, -0.013), "light_emitter", "lens", rot=(-25, 0, 0))
		kit.box((0.04, 0.1, 0.04), (0, 0.05, 0.02), "plastic_black", "bracket")


for _k, _l in (("pendant", "Pendant light"), ("downlight", "Recessed downlight"), ("batten", "1200 mm LED batten"), ("panel", "600 x 600 LED panel"),
		("highbay", "High-bay light"), ("bulkhead", "Bulkhead light"), ("emergency", "Emergency light"), ("exit_sign", "Illuminated exit sign"), ("floodlight", "External floodlight")):
	register("services.light." + _k, light, _l, tags=("services", "electrical", "lighting"), what=_k)


def device(what):
	if what == "smoke":
		kit.cyl(0.055, 0.02, (0, 0, -0.01), "plastic_white", "base", segs=22)
		kit.lathe([(0.05, -0.02), (0.045, -0.04), (0.02, -0.05), (0.0, -0.05)], slot="plastic_white", name="head", segs=22)
		kit.cyl(0.004, 0.003, (0.03, 0, -0.045), "plastic_red", "led", segs=8)
	elif what == "sprinkler":
		kit.cyl(0.03, 0.004, (0, 0, -0.002), "steel_stainless", "rose", segs=18)
		kit.cyl(0.008, 0.03, (0, 0, -0.017), "brass", "body", segs=10)
		kit.cyl(0.003, 0.02, (0, 0, -0.04), "plastic_red", "bulb", segs=8)
		kit.cyl(0.014, 0.002, (0, 0, -0.052), "brass", "deflector", segs=14)
	elif what == "call_point":
		kit.box((0.088, 0.05, 0.088), (0, 0.025, 0.044), "plastic_red", "body")
		kit.box((0.05, 0.003, 0.04), (0, 0.051, 0.05), "paint_white", "glass")
	elif what == "sounder":
		kit.cyl(0.05, 0.08, (0, 0.04, 0.05), "plastic_red", "sounder", axis="y", segs=18)
		kit.cyl(0.03, 0.02, (0, 0.09, 0.05), "light_emitter", "beacon", axis="y", segs=14)
	elif what == "pir":
		kit.rounded_box((0.06, 0.045, 0.1), (0, 0.022, 0.05), "plastic_white", "body", radius=0.012)
		kit.box((0.04, 0.004, 0.03), (0, 0.046, 0.04), "plastic_grey", "lens")
	elif what == "cctv":
		kit.cyl(0.06, 0.015, (0, 0, -0.008), "paint_white", "base", segs=20)
		kit.sphere(0.055, (0, 0, -0.04), "plastic_black", "dome", segs=18)
	elif what == "extinguisher":
		kit.cyl(0.075, 0.42, (0, 0.085, 0.21), "plastic_red", "cylinder", segs=18)
		kit.cyl(0.02, 0.06, (0, 0.085, 0.45), "plastic_black", "valve", segs=10)
		kit.box((0.1, 0.02, 0.012), (0, 0.11, 0.49), "plastic_black", "handle")
		kit.sweep([(0, 0.085, 0.45), (0.06, 0.085, 0.42), (0.085, 0.085, 0.3), (0.085, 0.085, 0.15)], kit.circle(0.008, 8), "plastic_black", "hose", up=(0, 1, 0))
	elif what == "hose_reel":
		kit.cyl(0.28, 0.12, (0, 0.1, 0.3), "plastic_red", "reel", axis="y", segs=26)
		kit.cyl(0.3, 0.01, (0, 0.165, 0.3), "plastic_red", "cheek", axis="y", segs=26)
		kit.box((0.1, 0.04, 0.6), (0, 0.02, 0.3), "plastic_red", "bracket")
	elif what == "access_reader":
		kit.rounded_box((0.045, 0.02, 0.12), (0, 0.01, 0.06), "plastic_black", "reader", radius=0.006)
		kit.cyl(0.003, 0.002, (0, 0.021, 0.1), "plastic_green", "led", axis="y", segs=8)
	elif what == "extract_fan":
		kit.rounded_box((0.16, 0.03, 0.16), (0, 0.015, 0.08), "plastic_white", "cover", radius=0.01)
		kit.grid_bars(0.1, 0.1, (0, 0.031, 0.08), 5, 5, 0.002, "plastic_white")
	elif what == "wifi":
		kit.rounded_box((0.2, 0.2, 0.035), (0, 0, -0.0175), "plastic_white", "ap", radius=0.015)
	kit.socket("fix", (0, 0, 0))


for _k, _l, _g in (("smoke", "Smoke detector", "fire"), ("sprinkler", "Sprinkler head", "fire"), ("call_point", "Fire alarm call point", "fire"),
		("sounder", "Sounder beacon", "fire"), ("pir", "Movement sensor", "security"), ("cctv", "CCTV dome camera", "security"),
		("extinguisher", "Fire extinguisher", "fire"), ("hose_reel", "Fire hose reel", "fire"), ("access_reader", "Door access reader", "security"),
		("extract_fan", "Bathroom extract fan", "ventilation"), ("wifi", "Wireless access point", "electrical")):
	register("services.device." + _k, device, _l, tags=("services", _g), what=_k)

# --- plant ---------------------------------------------------------------------------------

def _louvre(w, h, at, facing="y"):
	x, y, z = at
	n = int(h / 0.04)
	for i in range(n):
		kit.box((w, 0.004, 0.03) if facing == "y" else (0.004, w, 0.03), (x, y, z - h / 2 + h * (i + 0.5) / n), "plastic_black", "louvre", rot=(30, 0, 0) if facing == "y" else (0, 30, 0))


def ahu(length, w, h):
	with kit.hollow(0.04):
		kit.box((w, length, 0.1), (0, 0, 0.05), "steel_galvanised", "skid")
		n = max(2, round(length / 1.0))
		for i in range(n):
			y = -length / 2 + length * (i + 0.5) / n
			kit.box((w, length / n - 0.02, h), (0, y, 0.1 + h / 2), "paint_white", "section")
			kit.box((0.01, length / n - 0.25, h - 0.25), (w / 2, y, 0.1 + h / 2), "steel_galvanised", "access_door")
			kit.box((0.03, 0.03, 0.14), (w / 2 + 0.02, y + length / n / 2 - 0.2, 0.1 + h / 2), "plastic_black", "handle")
		for s in (-1, 1):
			kit.box((w * 0.7, 0.3, h * 0.6), (0, s * (length / 2 + 0.15), 0.1 + h / 2), "steel_galvanised", "duct_spigot")
	kit.socket("supply", (0, length / 2 + 0.3, 0.1 + h / 2))
	kit.socket("return", (0, -length / 2 - 0.3, 0.1 + h / 2))


for _n, _dims in (("small", (2.0, 1.0, 1.0)), ("medium", (3.5, 1.6, 1.6)), ("large", (6.0, 2.4, 2.4))):
	register("services.plant.ahu_" + _n, ahu, "Air handling unit, " + _n, tags=("services", "plant", "ventilation"), length=_dims[0], w=_dims[1], h=_dims[2])


def condenser(w, d, h, fans):
	with kit.hollow(0.06):
		kit.box((w, d, h), (0, 0, 0.1 + h / 2), "paint_white", "casing")
		for s in (-1, 1):
			kit.box((0.06, d, 0.1), (s * (w / 2 - 0.1), 0, 0.05), "steel_galvanised", "foot")
	for i in range(fans):
		z = 0.1 + h * (i + 0.5) / fans
		kit.cyl(min(w, h / fans) * 0.38, 0.02, (0, d / 2 + 0.01, z), "plastic_black", "fan_guard", axis="y", segs=24)
		kit.cyl(0.05, 0.03, (0, d / 2 + 0.02, z), "plastic_grey", "fan_hub", axis="y", segs=12)
	_louvre(d * 0.8, h * 0.8, (-w / 2 - 0.002, 0, 0.1 + h / 2), "x")


register("services.plant.condenser_single", condenser, "Outdoor condenser, single fan", tags=("services", "plant", "cooling"), w=0.9, d=0.35, h=0.7, fans=1)
register("services.plant.condenser_twin", condenser, "Outdoor condenser, twin fan", tags=("services", "plant", "cooling"), w=1.0, d=0.4, h=1.4, fans=2)
register("services.plant.heat_pump", condenser, "Air source heat pump", tags=("services", "plant", "heating"), w=1.25, d=0.45, h=1.0, fans=1)


@asset("services.plant.chiller", "Roof chiller, 6 fans", tags=("services", "plant", "cooling"))
def chiller(length=6.0, w=2.2, h=2.2):
	with kit.hollow(0.05):
		kit.box((w, length, 0.2), (0, 0, 0.1), "steel_galvanised", "skid")
		kit.box((w, length, h - 0.2), (0, 0, 0.2 + (h - 0.2) / 2), "paint_white", "casing")
	for i in range(3):
		for s in (-1, 1):
			kit.cyl(0.45, 0.08, (s * w / 4, -length / 2 + length * (i + 0.5) / 3, h + 0.04), "plastic_black", "fan", segs=24)
	for s in (-1, 1):
		for i in range(14):
			kit.box((0.004, length - 0.4, 0.05), (s * (w / 2 + 0.002), 0, 0.4 + i * (h - 0.6) / 14), "aluminium", "coil_fin")


def cylinder(litres):
	r = {150: 0.24, 210: 0.27, 300: 0.3, 500: 0.36, 1000: 0.45}[litres]
	h = litres / 1000 / (math.pi * (r - 0.05) ** 2)
	kit.lathe([(r * 0.6, 0), (r, 0.05), (r, h), (r * 0.6, h + 0.08), (0.0, h + 0.1)], slot="paint_white", name="cylinder", segs=24)
	for z, slot in ((0.15, "copper"), (h * 0.5, "copper"), (h - 0.1, "copper")):
		kit.rod((r - 0.02, 0, z), (r + 0.08, 0, z), 0.011, slot, "tapping", segs=8)
	kit.box((0.1, 0.06, 0.14), (0, r + 0.02, 0.4), "plastic_white", "immersion")
	kit.socket("flow", (r + 0.08, 0, h - 0.1))


for _l in (150, 210, 300, 500, 1000):
	register("services.plant.cylinder_%d" % _l, cylinder, "%d litre hot water cylinder" % _l, tags=("services", "plant", "plumbing"), litres=_l)


def tank(w, d, h, sectional):
	with kit.hollow(0.03):
		kit.box((w, d, h), (0, 0, 0.1 + h / 2), "plastic_grey" if not sectional else "insulation", "tank")
	kit.box((w + 0.02, d + 0.02, 0.03), (0, 0, 0.1 + h + 0.015), "plastic_black" if not sectional else "insulation", "lid")
	for x in (-w / 2 + 0.05, w / 2 - 0.05):
		kit.box((0.1, d, 0.1), (x, 0, 0.05), "softwood" if not sectional else "steel_galvanised", "bearer")
	if sectional:
		for i in range(1, int(w)):
			kit.box((0.04, d + 0.04, h), (-w / 2 + i, 0, 0.1 + h / 2), "insulation", "panel_joint")
		for i in range(1, int(h)):
			kit.box((w + 0.04, d + 0.04, 0.04), (0, 0, 0.1 + i), "insulation", "panel_joint")
	kit.rod((w / 2, 0, 0.2), (w / 2 + 0.15, 0, 0.2), 0.02, "copper", "outlet")


register("services.plant.tank_cold_230", tank, "230 litre cold water tank", tags=("services", "plant", "plumbing"), w=1.0, d=0.6, h=0.5, sectional=False)
register("services.plant.tank_sectional_4000", tank, "4,000 litre sectional tank", tags=("services", "plant", "plumbing"), w=2.0, d=2.0, h=1.0, sectional=True)
register("services.plant.tank_sectional_18000", tank, "18,000 litre sectional tank", tags=("services", "plant", "plumbing"), w=3.0, d=3.0, h=2.0, sectional=True)


def cabinet(w, d, h, doors, slot, style, vents=False):
	with kit.hollow(0.05):
		kit.box((w, d, 0.1), (0, 0, 0.05), "plastic_black", "plinth")
		kit.box((w, d - 0.02, h), (0, -0.01, 0.1 + h / 2), slot, "enclosure")
		for i in range(doors):
			x = -w / 2 + w * (i + 0.5) / doors
			kit.box((w / doors - 0.012, 0.02, h - 0.02), (x, d / 2 - 0.01, 0.1 + h / 2), slot, "door")
			kit.box((0.02, 0.03, 0.12), (x + w / doors / 2 - 0.05, d / 2 + 0.005, 0.1 + h / 2), "plastic_black", "handle")
			if style == "switch":
				kit.box((0.12, 0.024, 0.08), (x, d / 2, 0.1 + h * 0.75), "screen", "meter")
				for k in range(3):
					kit.cyl(0.012, 0.01, (x - 0.05 + k * 0.05, d / 2 + 0.005, 0.1 + h * 0.62), ("plastic_red", "plastic_yellow", "plastic_blue")[k], "lamp", axis="y", segs=10)
			if vents:
				_louvre(w / doors * 0.6, 0.2, (x, d / 2 + 0.001, 0.3))


register("services.plant.switchgear_panel", cabinet, "LV switchboard, 4 section", tags=("services", "plant", "electrical"), w=3.2, d=0.8, h=2.1, doors=4, slot="laminate_grey", style="switch")
register("services.plant.distribution_board", cabinet, "Distribution board", tags=("services", "plant", "electrical"), w=0.6, d=0.2, h=0.9, doors=1, slot="laminate_grey", style="switch")
register("services.plant.control_panel", cabinet, "Plant control panel", tags=("services", "plant", "electrical"), w=0.8, d=0.3, h=1.8, doors=1, slot="laminate_grey", style="switch")
register("services.plant.ups", cabinet, "UPS and battery cabinet", tags=("services", "plant", "electrical"), w=1.2, d=0.8, h=1.9, doors=2, slot="plastic_black", style="ups", vents=True)
register("services.plant.server_rack", cabinet, "42U server rack", tags=("services", "plant", "data", "office"), w=0.6, d=1.0, h=2.0, doors=1, slot="plastic_black", style="rack", vents=True)


@asset("services.plant.transformer", "11 kV transformer, 1 MVA", tags=("services", "plant", "electrical"))
def transformer():
	kit.box((1.6, 1.0, 1.3), (0, 0, 0.75), "plastic_green", "tank")
	kit.box((1.8, 1.2, 0.1), (0, 0, 0.05), "steel_galvanised", "skid")
	for s in (-1, 1):
		for i in range(7):
			kit.box((1.3, 0.01, 1.0), (0, s * (0.52 + i * 0.024), 0.75), "plastic_green", "fin")
	for x in (-0.5, 0, 0.5):
		kit.lathe([(0.04, 0), (0.07, 0.05), (0.04, 0.1), (0.07, 0.15), (0.04, 0.2), (0.02, 0.3)], (x, -0.2, 1.4), "ceramic", "bushing", segs=14)
		kit.cyl(0.03, 0.12, (x, 0.25, 1.46), "ceramic", "lv_bushing", segs=12)
	kit.cyl(0.15, 0.7, (0, 0, 1.75), "plastic_green", "conservator", axis="x", segs=18)


@asset("services.plant.generator", "Standby generator, 500 kVA, canopied", tags=("services", "plant", "electrical"))
def generator(length=4.5, w=1.6, h=2.2):
	with kit.hollow(0.08):
		kit.box((w, length, 0.3), (0, 0, 0.15), "plastic_black", "base_tank")
		kit.box((w, length, h - 0.3), (0, 0, 0.3 + (h - 0.3) / 2), "plastic_green", "canopy")
	for s in (-1, 1):
		_louvre(length * 0.25, h * 0.5, (s * (w / 2 + 0.002), -length / 2 + length * 0.2, 0.3 + (h - 0.3) / 2), "x")
		for k in (0, 1):
			kit.box((0.01, 0.9, h - 0.6), (s * (w / 2 + 0.004), 0.2 + k * 1.0, 0.3 + (h - 0.3) / 2), "plastic_green", "door")
	kit.cyl(0.1, 0.6, (0.4, length / 2 - 0.5, h + 0.3), "steel_stainless", "exhaust", segs=14)


@asset("services.plant.pump_set", "Twin booster pump set", tags=("services", "plant", "plumbing"))
def pump_set():
	kit.box((1.2, 0.7, 0.08), (0, 0, 0.04), "steel_painted", "skid")
	for x in (-0.3, 0.3):
		kit.cyl(0.11, 0.35, (x, 0, 0.5), "plastic_blue", "motor", segs=18)
		kit.cyl(0.13, 0.2, (x, 0, 0.2), "cast_iron", "volute", segs=18)
		kit.rod((x, 0.1, 0.2), (x, 0.3, 0.2), 0.03, "steel_painted", "discharge")
		kit.rod((x, -0.1, 0.2), (x, -0.3, 0.2), 0.03, "steel_painted", "suction")
	for y in (-0.3, 0.3):
		kit.rod((-0.55, y, 0.2), (0.55, y, 0.2), 0.04, "steel_painted", "header")
	kit.box((0.3, 0.15, 0.4), (0, 0.2, 0.75), "laminate_grey", "controller")
	kit.cyl(0.12, 0.35, (0.5, -0.05, 0.5), "plastic_red", "expansion_vessel", segs=16)


@asset("services.plant.boiler_commercial", "Commercial boiler, floor standing", tags=("services", "plant", "heating"))
def boiler_commercial():
	with kit.hollow(0.1):
		kit.box((0.7, 1.1, 1.5), (0, 0, 0.8), "plastic_red", "casing")
		kit.box((0.7, 1.1, 0.05), (0, 0, 0.025), "plastic_black", "plinth")
	kit.box((0.3, 0.01, 0.15), (0, 0.555, 1.3), "screen", "controls")
	kit.cyl(0.1, 0.8, (0, -0.3, 1.95), "steel_stainless", "flue", segs=16)
	for x in (-0.2, 0.2):
		kit.rod((x, -0.55, 1.2), (x, -0.85, 1.2), 0.035, "steel_painted", "flow_return")


@asset("services.plant.fan_coil", "Ceiling fan coil unit", tags=("services", "plant", "cooling"))
def fan_coil():
	with kit.hollow(0.06):
		kit.box((1.0, 0.6, 0.25), (0, 0, 0.125), "steel_galvanised", "casing")
	for x in (-0.3, 0, 0.3):
		kit.tube(0.1, 0.12, (x, 0.36, 0.125), "steel_galvanised", "spigot", axis="y", wall=0.002, segs=16)
	for s in (-1, 1):
		kit.rod((s * 0.45, 0.25, 0.25), (s * 0.45, 0.25, 0.6), 0.005, "steel_galvanised", "drop_rod", segs=6)
		kit.rod((s * 0.45, -0.25, 0.25), (s * 0.45, -0.25, 0.6), 0.005, "steel_galvanised", "drop_rod", segs=6)


@asset("services.plant.cassette_ac", "Ceiling cassette air conditioner", tags=("services", "cooling"))
def cassette():
	kit.box((0.62, 0.62, 0.02), (0, 0, -0.01), "paint_white", "fascia")
	kit.box((0.36, 0.36, 0.005), (0, 0, -0.022), "plastic_grey", "intake")
	for a in range(4):
		kit.box((0.4, 0.04, 0.006), (0.27 * math.cos(math.radians(90 * a + 90)), 0.27 * math.sin(math.radians(90 * a + 90)), -0.022), "plastic_grey", "vane", rot=(0, 0, 90 * a))
	kit.box((0.57, 0.57, 0.25), (0, 0, 0.125), "steel_galvanised", "body")


@asset("services.plant.roof_fan", "Roof extract fan", tags=("services", "plant", "ventilation"))
def roof_fan():
	kit.box((0.8, 0.8, 0.25), (0, 0, 0.125), "steel_galvanised", "upstand")
	kit.lathe([(0.45, 0.25), (0.45, 0.4), (0.3, 0.65), (0.0, 0.7)], slot="aluminium", name="cowl", segs=24)


@asset("services.plant.meter_gas", "Gas meter and regulator", tags=("services", "plant", "gas"))
def gas_meter():
	kit.rounded_box((0.3, 0.16, 0.25), (0, 0.08, 0.5), "steel_galvanised", "meter", radius=0.03)
	kit.box((0.1, 0.004, 0.04), (0, 0.162, 0.56), "screen", "index")
	for x in (-0.1, 0.1):
		kit.rod((x, 0.08, 0.62), (x, 0.08, 0.85), 0.012, "plastic_yellow", "pipe")
		kit.rod((x, 0.08, 0.85), (x * 3.5, 0.08, 0.85), 0.012, "plastic_yellow", "pipe")
	kit.cyl(0.04, 0.06, (-0.25, 0.08, 0.85), "plastic_red", "regulator", axis="x", segs=14)


def drainage(what):
	if what == "manhole":
		kit.box((0.7, 0.7, 0.04), (0, 0, -0.02), "cast_iron", "frame")
		kit.box((0.6, 0.6, 0.042), (0, 0, -0.02), "cast_iron", "cover")
		for i in range(5):
			kit.box((0.5, 0.02, 0.004), (0, -0.2 + i * 0.1, 0.002), "cast_iron", "tread")
	elif what == "gully":
		kit.box((0.32, 0.32, 0.03), (0, 0, -0.015), "cast_iron", "frame")
		for i in range(7):
			kit.box((0.02, 0.28, 0.032), (-0.12 + i * 0.04, 0, -0.015), "cast_iron", "bar")
	elif what == "channel":
		kit.box((0.13, 1.0, 0.15), (0, 0, -0.075), "concrete", "channel")
		for i in range(20):
			kit.box((0.1, 0.02, 0.012), (0, -0.475 + i * 0.05, -0.004), "steel_galvanised", "grating")
	elif what == "inspection":
		kit.cyl(0.225, 0.03, (0, 0, -0.015), "plastic_black", "cover", segs=24)
		kit.tube(0.225, 0.6, (0, 0, -0.33), "plastic_grey", "riser", wall=0.008, segs=24)
	elif what == "floor_drain":
		kit.cyl(0.075, 0.01, (0, 0, -0.005), "steel_stainless", "grate", segs=18)
		kit.cyl(0.05, 0.1, (0, 0, -0.06), "plastic_grey", "trap", segs=14)


for _k, _l, _st in (("manhole", "Manhole cover and frame", ""), ("gully", "Road gully grating", ""), ("channel", "Channel drain", "z"),
		("inspection", "Inspection chamber", ""), ("floor_drain", "Floor drain", "")):
	register("services.drainage." + _k, drainage, _l, tags=("services", "drainage"), stretch=_st, what=_k)
