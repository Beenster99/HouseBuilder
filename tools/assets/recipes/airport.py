"""Airport terminal fittings and airside equipment. Origin: floor centre, the passenger or
front side to +Y; vehicles and aircraft point along +Y."""
import math

import kit
from recipes.fixtures import task_chair
from recipes.furniture import carcass
from recipes.public import monitor
from registry import register


def reg(id, fn, label, *tags, **params):
	register("airport." + id, fn, label, family="fixture", tags=("airport",) + tags, **params)


def belt(w, l, at=(0, 0, 0.4), slot="rubber", sides=True):
	x, y, z = at
	kit.box((w, l, 0.04), (x, y, z), slot, "belt")
	kit.box((w + 0.06, l, z - 0.06), (x, y, (z - 0.06) / 2), "steel_stainless", "belt_body")
	for e in (-1, 1):
		kit.cyl(0.03, w, (x, y + e * l / 2, z - 0.01), "steel_stainless", "roller", axis="x", segs=10)
	if sides:
		for s in (-1, 1):
			kit.box((0.03, l, 0.1), (x + s * (w / 2 + 0.03), y, z + 0.03), "steel_stainless", "side_guard")


# --- landside ------------------------------------------------------------------------------

def checkin_desk(pair=False):
	xs = (-1.1, 1.1) if pair else (0.0,)
	with kit.stage("desks"):
		for x in xs:
			with kit.hollow(0.2):
				kit.box((1.2, 0.7, 1.05), (x, 0, 0.525), "laminate_white", "desk")
				kit.box((1.3, 0.3, 0.04), (x, 0.3, 1.07), "worktop", "counter")
			monitor((x, -0.15, 0.78), 0.45, 180)
			kit.box((1.0, 0.03, 0.35), (x, 0.36, 0.75), "plastic_blue", "fascia")
			task_chair((x, -0.9))
	with kit.stage("belts"):
		for x in ((0.0,) if pair else (0.95,)):
			belt(0.65, 1.6, (x, 0.1, 0.3))
			kit.box((0.7, 0.9, 0.02), (x, 0.4, 0.33), "steel_stainless", "scale")
	with kit.stage("signage"):
		for x in xs:
			kit.rod((x - 0.5, -0.3, 1.05), (x - 0.5, -0.3, 2.5), 0.02, "aluminium", "post")
			kit.box((1.1, 0.06, 0.35), (x, -0.3, 2.45), "plastic_black", "sign")
			kit.box((1.05, 0.004, 0.3), (x, -0.268, 2.45), "screen", "sign_screen")
	if pair:
		kit.socket("belt_out", (0, -0.7, 0.3))


def kiosk(bagdrop=False):
	kit.rounded_box((0.5, 0.35, 1.1), (0, 0, 0.55), "plastic_white", "body", radius=0.04)
	kit.box((0.42, 0.03, 0.36), (0, 0.16, 1.25), "plastic_black", "head", rot=(-25, 0, 0))
	kit.box((0.38, 0.004, 0.32), (0, 0.177, 1.257), "screen", "screen", rot=(-25, 0, 0))
	kit.box((0.2, 0.01, 0.03), (0, 0.176, 0.85), "plastic_black", "printer_slot")
	if bagdrop:
		belt(0.7, 1.4, (0.75, 0, 0.3))
		kit.sweep([(0.35, -0.5, 0), (0.35, -0.5, 1.9), (1.15, -0.5, 1.9), (1.15, -0.5, 0)], kit.rect(0.06, 0.06), "aluminium", "scan_arch", up=(0, 1, 0))


def security_lane(l=8.0):
	with kit.stage("rollers"):
		for y0, y1 in ((-l / 2, -1.0), (1.0, l / 2)):
			ll = y1 - y0
			kit.box((0.7, ll, 0.06), (0, (y0 + y1) / 2, 0.82), "steel_stainless", "roller_bed")
			for i in range(int(ll / 0.12)):
				kit.cyl(0.025, 0.6, (0, y0 + 0.06 + i * 0.12, 0.86), "steel_galvanised", "roller", axis="x", segs=8)
			for x in (-0.3, 0.3):
				for y in (y0 + 0.2, y1 - 0.2):
					kit.box((0.05, 0.05, 0.8), (x, y, 0.4), "steel_stainless", "leg")
	with kit.stage("xray"):
		with kit.hollow(0.3):
			kit.box((0.95, 2.0, 0.75), (0, 0, 0.375), "plastic_grey", "xray_base")
			kit.rounded_box((1.0, 1.3, 0.75), (0, 0, 1.2), "plastic_white", "xray_tunnel", radius=0.05)
		for e in (-1, 1):
			kit.box((0.62, 0.02, 0.42), (0, e * 0.66, 1.08), "rubber", "curtain")
		kit.box((0.62, 2.0, 0.03), (0, 0, 0.84), "rubber", "belt")
	with kit.stage("operator"):
		kit.box((0.7, 0.5, 0.03), (-1.0, 0.3, 1.0), "laminate_grey", "desk")
		kit.box((0.05, 0.05, 1.0), (-1.0, 0.3, 0.5), "steel_painted", "desk_post")
		monitor((-1.0, 0.3, 1.015), 0.5, 90)
	with kit.stage("trays"):
		for i in range(3):
			with kit.hollow(0.15):
				kit.box((0.5, 0.38, 0.12), (0, -l / 2 + 0.5 + i * 0.6, 0.95), "plastic_grey", "tray")


def body_scanner(arch=False):
	if arch:
		kit.sweep([(-0.42, 0, 0), (-0.42, 0, 2.15), (0.42, 0, 2.15), (0.42, 0, 0)], kit.rect(0.1, 0.6), "plastic_grey", "arch", up=(0, 1, 0))
		kit.box((0.2, 0.004, 0.1), (0, 0.302, 2.15), "screen", "display")
	else:
		kit.cyl(0.9, 0.12, (0, 0, 0.06), "plastic_grey", "floor", segs=32)
		kit.cyl(0.9, 0.2, (0, 0, 2.3), "plastic_grey", "head", segs=32)
		for s in (-1, 1):
			kit.sweep(kit.arc((0, 0, 1.2), 0.86, 90 - 55 if s > 0 else 270 - 55, 90 + 55 if s > 0 else 270 + 55, 10, "xy") if False else [(0.86 * math.cos(math.radians(a + (0 if s > 0 else 180))), 0.86 * math.sin(math.radians(a + (0 if s > 0 else 180))), 1.2) for a in range(-55, 56, 11)], kit.rect(0.01, 2.1), "glass", "panel", up=(0, 0, 1))
			kit.box((0.12, 0.2, 2.1), (s * 0.84, 0, 1.2), "plastic_white", "mast")


def passport_booth(egate=False):
	if egate:
		for s in (-1, 1):
			kit.rounded_box((0.18, 1.8, 1.0), (s * 0.45, 0, 0.5), "steel_stainless", "side", radius=0.04)
		for y in (-0.7, 0.7):
			for s in (-1, 1):
				kit.box((0.3, 0.012, 0.9), (s * 0.2, y, 0.75), "glass", "gate")
		kit.box((0.2, 0.05, 0.5), (0.45, 0.2, 1.3), "plastic_black", "camera_mast")
		kit.box((0.15, 0.12, 0.005), (0.45, -0.3, 1.003), "screen", "reader")
		return
	with kit.hollow(0.1):
		kit.box((1.4, 1.5, 1.1), (0, 0, 0.55), "laminate_grey", "base")
		kit.box((1.4, 1.5, 0.08), (0, 0, 2.3), "laminate_grey", "roof")
	for x, y, w, d in ((0, 0.74, 1.4, 0.012), (-0.69, 0, 0.012, 1.5), (0, -0.74, 1.4, 0.012)):
		kit.box((w, d, 1.16), (x, y, 1.68), "glass", "glazing")
	kit.box((0.4, 0.3, 0.03), (0.72, 0.3, 1.1), "worktop", "counter")
	monitor((0, 0.2, 1.1), 0.45, 180)


def barrier_post(n=1, belt_len=2.0):
	for i in range(n + 1 if n > 1 else 1):
		x = i * belt_len - (n * belt_len / 2 if n > 1 else 0)
		kit.cyl(0.17, 0.02, (x, 0, 0.01), "plastic_black", "base", segs=20)
		kit.cyl(0.03, 0.95, (x, 0, 0.49), "steel_stainless", "post", segs=12)
		kit.cyl(0.04, 0.08, (x, 0, 0.95), "plastic_black", "head", segs=12)
		if n > 1 and i < n:
			kit.box((belt_len, 0.003, 0.05), (x + belt_len / 2, 0, 0.93), "plastic_blue", "belt")
	if n == 1:
		kit.socket("belt", (0, 0, 0.93))


def fids(cols=3, hung=True):
	z = 2.6 if hung else 1.6
	if hung:
		for s in (-1, 1):
			kit.rod((s * cols * 0.4, 0, z + 0.4), (s * cols * 0.4, 0, 3.6), 0.012, "aluminium", "drop")
	else:
		for s in (-1, 1):
			kit.box((0.08, 0.2, z), (s * (cols * 0.55 - 0.1), 0, z / 2), "aluminium", "leg")
	kit.box((cols * 1.1 + 0.06, 0.1, 0.72), (0, 0, z), "plastic_black", "case")
	for i in range(cols):
		kit.box((1.05, 0.004, 0.62), ((i - (cols - 1) / 2) * 1.1, 0.052, z), "screen", "screen")


def sign_hanging(w=2.4):
	for s in (-1, 1):
		kit.rod((s * (w / 2 - 0.2), 0, 2.75), (s * (w / 2 - 0.2), 0, 3.4), 0.006, "steel_stainless", "wire", segs=5)
	kit.box((w, 0.08, 0.4), (0, 0, 2.55), "plastic_yellow", "sign")
	for s in (-1, 1):
		kit.box((w - 0.1, 0.004, 0.2), (0, s * 0.041, 2.55), "plastic_black", "text_band")


def totem(h=2.4):
	kit.box((0.7, 0.14, h), (0, 0, h / 2), "plastic_blue", "totem")
	kit.box((0.6, 0.145, 0.6), (0, 0, h - 0.5), "plastic_yellow", "panel")
	kit.box((0.5, 0.004, 0.5), (0, 0.073, h - 1.3), "screen", "map")


def gate_desk():
	with kit.hollow(0.2):
		kit.box((1.8, 0.6, 1.1), (0, 0, 0.55), "laminate_white", "desk")
	kit.box((1.9, 0.7, 0.04), (0, 0, 1.12), "worktop", "top")
	for x in (-0.5, 0.5):
		monitor((x, -0.1, 0.8), 0.45, 180)
	kit.box((0.25, 0.3, 0.2), (0.75, 0.0, 1.24), "plastic_grey", "boarding_reader")
	kit.rod((-0.8, -0.2, 1.1), (-0.8, -0.2, 2.6), 0.025, "aluminium", "sign_post")
	kit.box((0.9, 0.08, 0.5), (-0.4, -0.2, 2.4), "plastic_black", "gate_sign")
	kit.box((0.85, 0.004, 0.45), (-0.4, -0.158, 2.4), "screen", "gate_screen")


def carousel(l=12.0, w=4.0):
	"""An oval baggage reclaim belt."""
	r = w / 2
	path = []
	for a in range(-90, 91, 15):
		path.append((r * 0.75 * math.cos(math.radians(a)), l / 2 - r + r * 0.75 * math.sin(math.radians(a)), 0))
	for a in range(90, 271, 15):
		path.append((r * 0.75 * math.cos(math.radians(a)), -l / 2 + r + r * 0.75 * math.sin(math.radians(a)), 0))
	path.append(path[0])
	path.append(path[1])
	with kit.stage("body"):
		with kit.hollow(0.15):
			kit.sweep(path[:-1], [(-r * 0.25, 0), (r * 0.25, 0), (r * 0.25, 0.35), (r * 0.05, 0.6), (-r * 0.25, 0.6)], "steel_stainless", "skirt")
	with kit.stage("belt"):
		kit.sweep(path[:-1], [(-r * 0.05, 0.6), (r * 0.25, 0.35), (r * 0.25, 0.37), (-r * 0.05, 0.62)], "rubber", "plates")
	with kit.stage("feed"):
		kit.box((1.0, 3.0, 0.08), (0, 0, 1.3), "rubber", "feed_belt", rot=(20, 0, 0))
		kit.box((1.1, 3.0, 0.9), (0, 0, 0.75), "steel_stainless", "feed_housing")
		kit.box((1.6, 0.1, 0.5), (0, 0, 2.6), "plastic_black", "flight_sign")


def carousel_straight():
	belt(1.0, 1.0, (0, 0, 0.45))


def trolley():
	kit.sweep([(-0.3, -0.35, 0.2), (-0.3, -0.45, 1.0), (0.3, -0.45, 1.0), (0.3, -0.35, 0.2)], kit.circle(0.014, 8), "steel_stainless", "handle", up=(0, 1, 0))
	kit.grid_bars(0.55, 0.8, (0, 0.05, 0.2), 6, 2, 0.006, "steel_stainless", "deck", plane="xy")
	kit.grid_bars(0.55, 0.4, (0, -0.38, 0.75), 6, 3, 0.005, "steel_stainless", "basket_back")
	kit.box((0.45, 0.02, 0.15), (0, -0.4, 0.85), "plastic_yellow", "advert")
	for x, y in ((-0.25, 0.4), (0.25, 0.4), (0, -0.35)):
		kit.cyl(0.06, 0.03, (x, y, 0.06), "rubber", "wheel", axis="x", segs=12)


def trolley_bay(n=8):
	for s in (-1, 1):
		kit.sweep([(s * 0.45, -0.5, 0), (s * 0.45, -0.5, 0.9), (s * 0.45, n * 0.3 + 0.5, 0.9), (s * 0.45, n * 0.3 + 0.5, 0)], kit.circle(0.025, 8), "steel_galvanised", "rail", up=(1, 0, 0))
	for i in range(n):
		y = i * 0.3
		kit.grid_bars(0.55, 0.4, (0, y - 0.38, 0.75), 4, 2, 0.005, "steel_stainless", "trolleys")
		kit.box((0.55, 0.8, 0.02), (0, y + 0.05, 0.2 + i * 0.002), "steel_stainless", "trolley_deck")


def suitcase(w=0.48, h=0.72, d=0.28, slot="plastic_blue", upright=True):
	if upright:
		kit.rounded_box((w, d, h), (0, 0, h / 2 + 0.04), slot, "case", radius=0.04)
		for s in (-1, 1):
			kit.cyl(0.025, 0.03, (s * (w / 2 - 0.05), 0, 0.025), "rubber", "wheel", axis="x", segs=8)
			kit.rod((s * 0.08, -d / 2 + 0.03, h), (s * 0.08, -d / 2 + 0.03, h + 0.35), 0.006, "aluminium", "handle", segs=6)
		kit.rod((-0.08, -d / 2 + 0.03, h + 0.35), (0.08, -d / 2 + 0.03, h + 0.35), 0.01, "plastic_black", "grip", segs=6)
	else:
		kit.rounded_box((h, w, d), (0, 0, d / 2), slot, "case", radius=0.04)
		kit.rod((-0.06, w / 2 + 0.015, d / 2), (0.06, w / 2 + 0.015, d / 2), 0.008, "plastic_black", "grip", segs=6)


def holdall():
	kit.rounded_box((0.6, 0.3, 0.28), (0, 0, 0.14), "fabric_red", "bag", radius=0.1)
	kit.sweep([(-0.12, 0, 0.27), (-0.08, 0, 0.36), (0.08, 0, 0.36), (0.12, 0, 0.27)], kit.rect(0.03, 0.006), "plastic_black", "strap", up=(0, 1, 0))


def rucksack():
	kit.rounded_box((0.32, 0.22, 0.5), (0, 0, 0.25), "fabric_green", "pack", radius=0.08)
	kit.rounded_box((0.24, 0.06, 0.2), (0, 0.13, 0.18), "fabric_green", "pocket", radius=0.025)


def gondola(w=1.2, h=1.5, slot="laminate_white"):
	with kit.hollow(0.2):
		kit.box((w, 0.7, 0.15), (0, 0, 0.075), slot, "base")
		kit.box((w, 0.03, h), (0, 0, h / 2), slot, "spine")
		for i in range(1, int(h / 0.35) + 1):
			for s in (-1, 1):
				z = 0.15 + (i - 1) * 0.35
				kit.box((w, 0.32, 0.02), (0, s * 0.18, z), slot, "shelf")
				for j in range(4):
					kit.box((w / 4 - 0.04, 0.22, 0.2), (-w / 2 + w * (j + 0.5) / 4, s * 0.18, z + 0.11), ("plastic_red", "plastic_yellow", "plastic_green", "plastic_blue")[(i + j) % 4], "stock")


def retail_counter(w=2.4, cafe=False):
	with kit.hollow(0.2):
		kit.box((w, 0.7, 0.9), (0, 0, 0.45), "hardwood" if cafe else "laminate_white", "counter")
	kit.box((w + 0.06, 0.8, 0.04), (0, 0, 0.92), "worktop", "top")
	kit.box((0.35, 0.35, 0.08), (w / 2 - 0.4, -0.1, 0.98), "plastic_black", "till")
	kit.box((0.3, 0.02, 0.22), (w / 2 - 0.4, -0.1, 1.15), "screen", "till_screen", rot=(-15, 0, 0))
	if cafe:
		kit.rounded_box((0.7, 0.5, 0.45), (-w / 2 + 0.6, -0.05, 1.165), "steel_stainless", "espresso_machine", radius=0.03)
		kit.rounded_box((0.9, 0.5, 0.5), (0.1, 0.1, 1.19), "glass", "cake_display", radius=0.04)
		kit.box((w, 0.05, 0.6), (0, -0.9, 2.3), "plastic_black", "menu_board")


def info_desk():
	path = [(1.4 * math.cos(math.radians(a)), 1.4 * math.sin(math.radians(a)), 0) for a in range(0, 181, 15)]
	with kit.hollow(0.2):
		kit.sweep(path, [(-0.3, 0), (0.3, 0), (0.3, 1.05), (-0.3, 1.05)], "laminate_white", "desk")
	kit.sweep(path, [(-0.4, 1.05), (0.35, 1.05), (0.35, 1.09), (-0.4, 1.09)], "worktop", "top")
	kit.cyl(0.03, 1.4, (0, 0.2, 1.8), "aluminium", "post", segs=10)
	kit.sphere(0.3, (0, 0.2, 2.6), "plastic_yellow", "beacon", segs=20)
	task_chair((0, 0.6))


def charging_station():
	kit.cyl(0.25, 0.03, (0, 0, 0.015), "steel_stainless", "base", segs=24)
	kit.cyl(0.04, 1.0, (0, 0, 0.5), "steel_stainless", "post", segs=12)
	kit.cyl(0.4, 0.04, (0, 0, 1.05), "laminate_white", "top", segs=28)
	kit.cyl(0.1, 0.12, (0, 0, 1.13), "plastic_black", "sockets", segs=14)


def travelator(l=1.0, pallet="steel_galvanised"):
	"""A 1 m length of moving walkway; scale along its length."""
	kit.box((1.0, l, 0.02), (0, 0, 0.01), pallet, "pallets")
	for s in (-1, 1):
		kit.box((0.02, l, 0.9), (s * 0.62, 0, 0.47), "glass", "balustrade")
		kit.rounded_box((0.09, l, 0.05), (s * 0.62, 0, 0.94), "rubber", "handrail", radius=0.02)
		kit.box((0.24, l, 0.04), (s * 0.62, 0, 0.02), "steel_stainless", "skirt")


def travelator_end():
	kit.box((1.5, 1.2, 0.03), (0, 0, 0.015), "steel_stainless", "comb_plate")
	for s in (-1, 1):
		kit.sweep([(s * 0.62, -0.6, 0.94), (s * 0.62, 0.2, 0.94), (s * 0.62, 0.55, 0.6), (s * 0.62, 0.2, 0.25), (s * 0.62, -0.6, 0.25)], kit.rect(0.05, 0.09), "rubber", "newel", up=(1, 0, 0))
		kit.box((0.02, 0.8, 0.65), (s * 0.62, -0.2, 0.6), "glass", "balustrade")


def escalator(rise=4.0):
	run = rise / math.tan(math.radians(30))
	y0, y1 = -run / 2, run / 2
	with kit.stage("truss"):
		with kit.hollow(0.2):
			kit.prism([(y0 - 2.0, 0), (y0 - 2.0, -0.9), (y0, -0.9), (y1 + 0.6, rise - 1.0), (y1 + 2.2, rise - 1.0), (y1 + 2.2, rise), (y1, rise), (y0, 0)], 1.5, (0, 0, 0), "steel_stainless", "truss", axis="x")
	with kit.stage("steps"):
		n = int(rise / 0.2)
		for i in range(n):
			kit.box((1.0, run / n + 0.02, 0.2), (0, y0 + run * (i + 0.5) / n, rise * (i + 0.5) / n - 0.08), "aluminium", "step")
		for y, z in ((y0 - 1.0, 0), (y1 + 1.1, rise)):
			kit.box((1.0, 2.0, 0.03), (0, y, z + 0.005), "aluminium", "landing")
	with kit.stage("balustrade"):
		for s in (-1, 1):
			path = [(s * 0.6, y0 - 1.9, 0.95), (s * 0.6, y0 - 0.4, 0.95), (s * 0.6, y1 + 0.3, rise + 0.95), (s * 0.6, y1 + 2.1, rise + 0.95)]
			kit.sweep(path, kit.rect(0.05, 0.09), "rubber", "handrail", up=(1, 0, 0))
			kit.sweep([(p[0], p[1], p[2] - 0.47) for p in path], kit.rect(0.86, 0.012), "glass", "glass", up=(1, 0, 0))
	kit.socket("bottom", (0, y0 - 2.0, 0))
	kit.socket("top", (0, y1 + 2.2, rise))


def seat_row_charging(n=4):
	kit.box((n * 0.58, 0.08, 0.06), (0, 0, 0.36), "steel_painted", "beam")
	for s in (-1, 1):
		kit.box((0.05, 0.5, 0.36), (s * (n * 0.29 - 0.2), 0, 0.18), "steel_painted", "leg")
	for i in range(n):
		x = (i - (n - 1) / 2) * 0.58
		kit.rounded_box((0.5, 0.48, 0.07), (x, 0.03, 0.43), "leather_black", "seat", radius=0.03)
		kit.rounded_box((0.5, 0.07, 0.45), (x, -0.22, 0.7), "leather_black", "back", radius=0.03, rot=(-10, 0, 0))
		kit.box((0.05, 0.4, 0.03), (x - 0.29, 0.03, 0.62), "aluminium", "arm")
	kit.box((0.05, 0.4, 0.03), ((n / 2) * 0.58, 0.03, 0.62), "aluminium", "arm")


def glass_balustrade(l=1.0):
	kit.box((l, 0.02, 1.05), (0, 0, 0.55), "glass", "pane")
	kit.box((l, 0.06, 0.08), (0, 0, 0.04), "steel_stainless", "shoe")
	kit.rod((-l / 2, 0, 1.1), (l / 2, 0, 1.1), 0.022, "steel_stainless", "handrail")


def smoking_shelter():
	for x in (-1.5, 1.5):
		kit.rod((x, -0.7, 0), (x, -0.7, 2.2), 0.03, "aluminium", "post")
		kit.box((0.012, 1.3, 1.9), (x, 0, 1.05), "glass", "side")
	kit.box((3.0, 0.012, 1.9), (0, -0.7, 1.05), "glass", "back")
	kit.box((3.2, 1.6, 0.05), (0, 0, 2.22), "aluminium", "roof", rot=(4, 0, 0))
	kit.box((2.4, 0.3, 0.04), (0, -0.5, 0.45), "aluminium", "perch")


for _id, _fn, _label, _kw in (
	("landside.checkin_desk", checkin_desk, "Check-in desk with bag belt", {}),
	("landside.checkin_pair", checkin_desk, "Check-in desks, pair with shared belt", {"pair": True}),
	("landside.kiosk", kiosk, "Self check-in kiosk", {}),
	("landside.bag_drop", kiosk, "Self bag drop", {"bagdrop": True}),
	("landside.trolley", trolley, "Baggage trolley", {}),
	("landside.trolley_bay", trolley_bay, "Trolley bay with nested trolleys", {}),
	("landside.info_desk", info_desk, "Information desk", {}),
	("landside.totem", totem, "Wayfinding totem", {}),
	("landside.smoking_shelter", smoking_shelter, "Smoking shelter", {}),
	("security.lane", security_lane, "Security lane with X-ray, 8 m", {}),
	("security.lane_long", security_lane, "Security lane with X-ray, 12 m", {"l": 12.0}),
	("security.body_scanner", body_scanner, "Body scanner", {}),
	("security.metal_arch", body_scanner, "Walk-through metal detector", {"arch": True}),
	("security.passport_booth", passport_booth, "Passport control booth", {}),
	("security.egate", passport_booth, "Passport e-gate", {"egate": True}),
	("queue.post", barrier_post, "Queue barrier post", {}),
	("queue.run_3", barrier_post, "Queue barrier run, three belts", {"n": 3}),
	("queue.run_6", barrier_post, "Queue barrier run, six belts", {"n": 6}),
	("sign.fids_3", fids, "Departure board, three screens, hung", {}),
	("sign.fids_6", fids, "Departure board, six screens, hung", {"cols": 6}),
	("sign.fids_floor", fids, "Departure board, floor standing", {"cols": 2, "hung": False}),
	("sign.hanging", sign_hanging, "Hanging direction sign, 2.4 m", {}),
	("sign.hanging_long", sign_hanging, "Hanging direction sign, 4 m", {"w": 4.0}),
	("gate.desk", gate_desk, "Gate desk with sign", {}),
	("gate.seat_row_4", seat_row_charging, "Gate seating, four", {}),
	("gate.seat_row_6", seat_row_charging, "Gate seating, six", {"n": 6}),
	("gate.charging_station", charging_station, "Charging table", {}),
	("reclaim.carousel", carousel, "Baggage carousel, 12 m", {}),
	("reclaim.carousel_large", carousel, "Baggage carousel, 20 m", {"l": 20.0, "w": 5.0}),
	("bags.suitcase_large", suitcase, "Suitcase, large", {}),
	("bags.suitcase_cabin", suitcase, "Suitcase, cabin", {"w": 0.36, "h": 0.52, "d": 0.22, "slot": "plastic_red"}),
	("bags.suitcase_flat", suitcase, "Suitcase, lying flat", {"slot": "plastic_black", "upright": False}),
	("bags.holdall", holdall, "Holdall", {}),
	("bags.rucksack", rucksack, "Rucksack", {}),
	("retail.gondola", gondola, "Shop gondola shelving", {}),
	("retail.gondola_tall", gondola, "Shop gondola shelving, tall", {"h": 2.0, "slot": "hardwood"}),
	("retail.counter", retail_counter, "Shop counter with till", {}),
	("retail.cafe_counter", retail_counter, "Cafe counter", {"w": 3.6, "cafe": True}),
	("move.travelator_end", travelator_end, "Moving walkway end", {}),
	("move.escalator_4000", escalator, "Escalator, 4 m rise", {}),
	("move.escalator_6000", escalator, "Escalator, 6 m rise", {"rise": 6.0}),
):
	reg(_id, _fn, _label, **_kw)
register("airport.move.travelator", travelator, "Moving walkway, per metre", family="fixture", tags=("airport",), stretch="z")
register("airport.reclaim.belt", carousel_straight, "Baggage conveyor, per metre", family="fixture", tags=("airport",), stretch="z")
register("airport.move.glass_balustrade", glass_balustrade, "Glass balustrade, per metre", family="fixture", tags=("airport", "office"), stretch="x")


# --- airside -------------------------------------------------------------------------------

def airbridge(l=18.0):
	with kit.stage("rotunda"):
		kit.cyl(1.8, 2.8, (0, 0, 5.4), "paint_white", "rotunda", segs=24)
		kit.cyl(0.4, 4.0, (0, 0, 2.0), "steel_painted", "rotunda_column", segs=16)
	with kit.stage("tunnel"):
		with kit.hollow(0.06):
			kit.box((1.7, l, 2.5), (0, l / 2 + 1.5, 5.3), "paint_white", "tunnel")
		kit.box((1.72, l - 1.0, 0.9), (0, l / 2 + 1.5, 5.5), "glass", "windows")
	with kit.stage("drive"):
		y = l * 0.75
		kit.box((0.5, 0.5, 4.0), (0, y, 2.0), "steel_painted", "drive_column")
		kit.box((2.4, 0.4, 0.3), (0, y, 0.55), "steel_painted", "bogie")
		for s in (-1, 1):
			kit.wheel(0.4, 0.3, (s * 1.0, y, 0.4))
	with kit.stage("cab"):
		kit.cyl(1.6, 2.6, (0, l + 2.6, 5.3), "paint_white", "cab", segs=20)
		kit.box((2.0, 0.9, 2.3), (0.6, l + 4.0, 5.2), "rubber", "canopy")
	kit.socket("terminal", (0, -1.8, 4.1))
	kit.socket("aircraft", (0.6, l + 4.5, 4.1))


def tug(tow=False):
	l, w = (3.0, 1.5) if not tow else (5.5, 2.4)
	with kit.hollow(0.5):
		kit.rounded_box((w, l, 0.6), (0, 0, 0.55), "paint_white", "body", radius=0.06)
		if not tow:
			kit.box((w - 0.1, 1.0, 0.9), (0, -0.2, 1.3), "paint_white", "cab")
			kit.box((w - 0.08, 0.02, 0.6), (0, 0.31, 1.35), "glass", "screen")
		else:
			kit.box((1.0, 1.2, 0.5), (-0.5, l / 2 - 1.0, 1.1), "paint_white", "cab")
			kit.box((1.02, 1.0, 0.3), (-0.5, l / 2 - 1.0, 1.2), "glass", "screen")
	r = 0.3 if not tow else 0.5
	for s in (-1, 1):
		for y in (-l / 2 + r + 0.2, l / 2 - r - 0.2):
			kit.wheel(r, 0.25, (s * (w / 2 - 0.1), y, r))
	kit.cyl(0.06, 0.06, (w / 2 - 0.2, 0, 2.0 if not tow else 1.4), "hivis_orange", "beacon", segs=10)
	kit.socket("hitch", (0, -l / 2, 0.4))


def dolly(cover=False):
	kit.box((1.5, 3.0, 0.1), (0, 0, 0.5), "steel_galvanised", "deck")
	for s in (-1, 1):
		for y in (-1.1, 1.1):
			kit.wheel(0.2, 0.12, (s * 0.6, y, 0.2))
	kit.rod((0, 1.5, 0.4), (0, 2.3, 0.4), 0.025, "steel_galvanised", "drawbar")
	if cover:
		for s in (-1, 1):
			kit.frame(1.5, 1.4, 0.04, 0.04, at=(0, s * 1.48, 0.55), slot="steel_galvanised", name="end_frame")
		kit.box((1.55, 3.0, 0.04), (0, 0, 1.97), "fabric_blue", "canopy")
		for i in range(5):
			kit.rounded_box((0.6, 0.45, 0.3), (-0.35 + 0.7 * (i % 2), -1.1 + i * 0.5, 0.7 + 0.31 * (i % 2)), ("plastic_black", "plastic_blue", "plastic_red")[i % 3], "bag", radius=0.05)
	else:
		with kit.hollow(0.05):
			kit.prism([(-0.78, 0), (0.78, 0), (0.78, 1.63), (0.3, 1.63), (-0.78, 1.0)], 1.5, (0, 0, 0.56), "aluminium", "uld_container", axis="y")
	kit.socket("hitch", (0, -1.5, 0.4))


def belt_loader():
	with kit.hollow(0.4):
		kit.rounded_box((1.6, 4.5, 0.5), (0, 0, 0.55), "paint_white", "chassis", radius=0.05)
	for s in (-1, 1):
		for y in (-1.5, 1.5):
			kit.wheel(0.3, 0.22, (s * 0.75, y, 0.3))
	kit.box((0.8, 7.0, 0.15), (-0.3, 0.8, 1.9), "rubber", "belt", rot=(18, 0, 0))
	kit.box((0.9, 7.0, 0.12), (-0.3, 0.8, 1.8), "steel_painted", "boom", rot=(18, 0, 0))
	kit.strut((-0.3, 1.5, 0.8), (-0.3, 2.2, 2.2), 0.1, 0.1, "steel_galvanised", "ram")
	kit.box((0.6, 0.8, 0.5), (0.45, 0.6, 1.05), "paint_white", "seat_box")


def aircraft_steps(h=3.4):
	run = h * 1.5
	with kit.hollow(0.4):
		kit.box((2.0, run + 1.5, 0.4), (0, 0, 0.6), "paint_white", "chassis")
	for s in (-1, 1):
		for y in (-run / 2, run / 2):
			kit.wheel(0.3, 0.2, (s * 0.95, y, 0.3))
	n = int(h / 0.19)
	for i in range(n):
		kit.box((1.4, run / n + 0.03, 0.04), (0, -run / 2 + run * (i + 0.5) / n, 0.8 + (h - 0.8) * (i + 1) / n), "aluminium", "tread")
	kit.box((1.6, 1.4, 0.06), (0, run / 2 + 0.7, h), "aluminium", "platform")
	for s in (-1, 1):
		kit.strut((s * 0.72, -run / 2, 0.8), (s * 0.72, run / 2, h), 0.04, 0.3, "paint_white", "stringer")
		kit.strut((s * 0.75, -run / 2, 1.8), (s * 0.75, run / 2, h + 1.0), 0.04, 0.04, "steel_stainless", "handrail")
		kit.rod((s * 0.75, run / 2, h + 1.0), (s * 0.75, run / 2 + 1.4, h + 1.0), 0.02, "steel_stainless", "platform_rail")
		kit.rod((s * 0.75, run / 2 + 0.7, 0.8), (s * 0.75, run / 2 + 0.7, h), 0.05, "steel_painted", "prop")
	kit.socket("door", (0, run / 2 + 1.4, h))


def gpu():
	with kit.hollow(0.5):
		kit.rounded_box((1.4, 2.4, 1.2), (0, 0, 1.0), "plant_yellow", "housing", radius=0.06)
	for s in (-1, 1):
		for y in (-0.8, 0.8):
			kit.wheel(0.25, 0.15, (s * 0.7, y, 0.25))
	kit.rod((0, 1.2, 0.5), (0, 2.0, 0.5), 0.025, "steel_galvanised", "drawbar")
	kit.sweep([(0.7, -0.5, 0.8), (1.0, -0.5, 0.3), (1.2, 0, 0.05), (1.0, 0.8, 0.05)], kit.circle(0.03, 8), "plastic_black", "cable")


def bowser():
	with kit.hollow(0.4):
		kit.box((2.4, 2.2, 2.3), (0, 3.6, 1.75), "paint_white", "cab")
		kit.box((2.2, 9.5, 0.3), (0, 0, 0.95), "steel_painted", "chassis")
	kit.box((2.3, 0.02, 0.9), (0, 4.71, 2.2), "glass", "windscreen")
	with kit.hollow(0.03):
		kit.lathe([(0.5, 0), (1.15, 0.3), (1.15, 6.4), (0.5, 6.7)], (0, -4.5, 2.25), "steel_stainless", "tank", segs=24, scale=(1.05, 1, 1) if False else (1, 1, 1), rot=(-90, 0, 0))
	for s in (-1, 1):
		for y in (3.6, -2.5, -3.7):
			kit.wheel(0.52, 0.32, (s * 1.05, y, 0.52))
	kit.box((2.0, 0.8, 1.0), (0, 2.0, 1.6), "steel_painted", "pump_module")


def cone():
	kit.box((0.28, 0.28, 0.03), (0, 0, 0.015), "hivis_orange", "base")
	kit.cyl(0.11, 0.47, (0, 0, 0.265), "hivis_orange", "cone", segs=16, r2=0.025)
	kit.cyl(0.074, 0.1, (0, 0, 0.3), "paint_white", "band", segs=16, r2=0.053)


def chock():
	for y in (-0.25, 0.25):
		kit.prism([(-0.1, 0), (0.1, 0), (0, 0.14)], 0.3, (0, y, 0), "plastic_yellow", "chock", axis="x")
	kit.rod((0, -0.25, 0.1), (0, 0.25, 0.1), 0.008, "plastic_black", "rope", segs=5)


def windsock():
	kit.cyl(0.05, 6.0, (0, 0, 3.0), "paint_white", "mast", segs=12)
	kit.lathe([(0.45, 0), (0.2, 3.0)], (0, 0, 5.9), "hivis_orange", "sock", segs=14, rot=(-80, 0, 0))


def runway_light(tall=False):
	if tall:
		kit.cyl(0.03, 0.5, (0, 0, 0.25), "plant_yellow", "stem", segs=10)
		kit.cyl(0.07, 0.12, (0, 0, 0.56), "light_emitter", "lamp", segs=14)
	else:
		kit.cyl(0.15, 0.03, (0, 0, 0.015), "aluminium", "ring", segs=20)
		kit.cyl(0.07, 0.02, (0, 0, 0.035), "light_emitter", "lens", segs=14)


def flood_mast(h=25.0):
	kit.cyl(0.35, h, (0, 0, h / 2), "steel_galvanised", "mast", segs=14, r2=0.15)
	kit.box((3.0, 0.3, 0.2), (0, 0, h), "steel_galvanised", "headframe")
	for i in range(6):
		x = -1.25 + i * 0.5
		kit.box((0.4, 0.15, 0.5), (x, 0.2, h - 0.4), "aluminium", "floodlight", rot=(30, 0, 0))
		kit.box((0.36, 0.01, 0.45), (x, 0.26, h - 0.44), "light_emitter", "lens", rot=(30, 0, 0))


def stand_board():
	kit.rod((0, 0, 0), (0, 0, 5.0), 0.08, "steel_galvanised", "post")
	kit.box((1.6, 0.25, 1.2), (0, 0, 5.4), "plastic_black", "guidance_display")
	kit.box((1.4, 0.004, 1.0), (0, 0.127, 5.4), "screen", "screen")


def blast_fence(l=3.0):
	for i in range(8):
		kit.box((l, 0.02, 0.35), (0, -i * 0.12, 0.3 + i * 0.4), "steel_galvanised", "louvre", rot=(-55, 0, 0))
	for s in (-1, 1):
		kit.strut((s * (l / 2 - 0.1), 0.1, 0), (s * (l / 2 - 0.1), -0.9, 3.3), 0.1, 0.1, "steel_galvanised", "raker")
		kit.strut((s * (l / 2 - 0.1), -1.6, 0), (s * (l / 2 - 0.1), -0.9, 3.3), 0.1, 0.1, "steel_galvanised", "back_prop")


def airliner(l=37.6, span=35.8, r=1.98, engines=2):
	"""A single-aisle (or with a larger span, twin-aisle) airliner, nose to +Y, on its gear."""
	gz = r + 1.6
	with kit.hollow(0.02):
		with kit.stage("fuselage"):
			prof = [(0.05, 0), (r * 0.45, r * 0.5), (r * 0.8, r * 1.4), (r, r * 2.8), (r, l * 0.62), (r * 0.8, l * 0.8), (r * 0.42, l * 0.93), (r * 0.12, l)]
			kit.lathe([(a, l - b) for a, b in reversed(prof)], (0, -l / 2, gz), "paint_white", "fuselage", segs=28, rot=(-90, 0, 0))
			kit.box((r * 1.2, 0.05, 0.5), (0, l / 2 - r * 1.25, gz + r * 0.42), "glass", "flight_deck_glass", rot=(-28, 0, 0))
			for s in (-1, 1):
				kit.box((0.02, l * 0.62, 0.22), (s * (r - 0.005), 0.5, gz + 0.3), "screen", "windows")
		with kit.stage("wings"):
			for s in (-1, 1):
				root, tip = l * 0.17, l * 0.045
				pts = [(0, 0.6 + root / 2), (0, 0.6 - root / 2), (s * span / 2, -l * 0.19 - tip / 2), (s * span / 2, -l * 0.19 + tip / 2)]
				if s < 0:
					pts = pts[::-1]
				kit.prism(pts, 0.35, (0, 0, gz - r * 0.55), "aluminium", "wing", axis="z")
				kit.box((0.1, tip, 1.4), (s * span / 2, -l * 0.19, gz - r * 0.55 + 0.7), "paint_white", "winglet")
				tp = [(0, -l / 2 + 4.2), (0, -l / 2 + 1.4), (s * span * 0.19, -l / 2 + 0.3), (s * span * 0.19, -l / 2 + 1.4)]
				if s < 0:
					tp = tp[::-1]
				kit.prism(tp, 0.2, (0, 0, gz + r * 0.35), "aluminium", "tailplane", axis="z")
			kit.prism([(-l / 2 + 6.0, 0), (-l / 2 + 1.2, 0), (-l / 2 - 0.3, l * 0.16), (-l / 2 + 1.4, l * 0.16)], 0.3, (0, 0, gz + r * 0.7), "plastic_blue", "fin", axis="x")
		with kit.stage("engines"):
			per = engines // 2
			for s in (-1, 1):
				for i in range(per):
					x = s * span * (0.16 + 0.17 * i)
					y = 2.2 - abs(x) * 0.55
					er = r * 0.55
					kit.lathe([(er * 0.85, 0), (er, 0.6), (er, 2.6), (er * 0.6, 3.6)], (x, y - 1.4, gz - r * 0.55 - er - 0.15), "paint_white", "nacelle", segs=20, rot=(-90, 0, 0))
					kit.cyl(er * 0.8, 0.05, (x, y + 2.15, gz - r * 0.55 - er - 0.15), "plastic_black", "fan", axis="y", segs=20)
					kit.box((0.25, 2.2, 0.5), (x, y + 0.2, gz - r * 0.55 - 0.2), "paint_white", "pylon")
	with kit.stage("gear"):
		kit.rod((0, l / 2 - l * 0.13, gz - r), (0, l / 2 - l * 0.13, 0.45), 0.09, "steel_stainless", "nose_leg")
		for s in (-1, 1):
			kit.wheel(0.42, 0.22, (s * 0.2, l / 2 - l * 0.13, 0.42))
			x = s * span * 0.085
			kit.rod((x, -0.4, gz - r * 0.6), (x, -0.4, 0.6), 0.13, "steel_stainless", "main_leg")
			for sx in (-1, 1):
				for y in ((-0.4,) if span < 45 else (-1.1, 0.3)):
					kit.wheel(0.58, 0.4, (x + sx * 0.42, y, 0.58))
	kit.socket("door_front_left", (-r, l / 2 - l * 0.14, gz - 0.3))
	kit.socket("nose_gear", (0, l / 2 - l * 0.13, 0))


for _id, _fn, _label, _kw in (
	("airside.airbridge", airbridge, "Passenger boarding bridge, 18 m", {}),
	("airside.airbridge_long", airbridge, "Passenger boarding bridge, 28 m", {"l": 28.0}),
	("airside.baggage_tug", tug, "Baggage tug", {}),
	("airside.pushback_tractor", tug, "Pushback tractor", {"tow": True}),
	("airside.baggage_cart", dolly, "Baggage cart, loaded", {"cover": True}),
	("airside.container_dolly", dolly, "Container dolly with container", {}),
	("airside.belt_loader", belt_loader, "Belt loader", {}),
	("airside.steps", aircraft_steps, "Aircraft steps, narrow body", {}),
	("airside.steps_tall", aircraft_steps, "Aircraft steps, wide body", {"h": 5.2}),
	("airside.gpu", gpu, "Ground power unit", {}),
	("airside.fuel_bowser", bowser, "Fuel bowser", {}),
	("airside.cone", cone, "Traffic cone", {}),
	("airside.chocks", chock, "Wheel chocks", {}),
	("airside.windsock", windsock, "Windsock", {}),
	("airside.runway_light", runway_light, "Runway inset light", {}),
	("airside.edge_light", runway_light, "Taxiway edge light", {"tall": True}),
	("airside.flood_mast", flood_mast, "Apron floodlight mast, 25 m", {}),
	("airside.stand_guidance", stand_board, "Stand guidance display", {}),
	("airside.blast_fence", blast_fence, "Jet blast fence, 3 m", {}),
	("aircraft.narrow_body", airliner, "Airliner, single aisle, 180 seat", {}),
	("aircraft.regional", airliner, "Regional jet, 90 seat", {"l": 31.0, "span": 26.0, "r": 1.5}),
	("aircraft.wide_body", airliner, "Airliner, twin aisle, 300 seat", {"l": 63.0, "span": 60.0, "r": 2.95}),
	("aircraft.jumbo", airliner, "Airliner, four engine, 500 seat", {"l": 72.0, "span": 79.0, "r": 3.5, "engines": 4}),
):
	reg(_id, _fn, _label, "outdoor", **_kw)
