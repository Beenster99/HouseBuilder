"""Road vehicles for streets, car parks and emergency services. Origin: ground centre,
front to +Y."""
import kit
from registry import register


def reg(id, fn, label, *tags, **params):
	register("vehicle." + id, fn, label, family="vehicle", tags=("vehicle", "outdoor") + tags, **params)


def wheels(track, axles, r=0.32, w=0.22):
	for y in axles:
		for s in (-1, 1):
			kit.wheel(r, w, (s * (track / 2 - w / 2), y, r))


def lamps(w, l, z, tail=True):
	for s in (-1, 1):
		kit.box((0.28, 0.03, 0.12), (s * (w / 2 - 0.22), l / 2, z), "light_emitter", "headlamp")
		if tail:
			kit.box((0.24, 0.03, 0.12), (s * (w / 2 - 0.2), -l / 2, z + 0.1), "hazard_red", "tail_lamp")


def car(l=4.3, w=1.8, h=1.5, style="hatch", paint="car_silver", roof_kit=""):
	"""A car from a side profile: body in paint, glasshouse in glass, then roof."""
	belt, sill = h * 0.58, 0.22
	f, b = l / 2, -l / 2
	bonnet = {"hatch": 0.24, "saloon": 0.26, "estate": 0.24, "suv": 0.25, "pickup": 0.27, "taxi": 0.24}[style] * l
	rear = {"hatch": 0.06, "saloon": 0.2, "estate": 0.03, "suv": 0.04, "pickup": 0.36, "taxi": 0.14}[style] * l
	with kit.hollow(0.25):
		body = [(b, sill), (f, sill), (f, belt * 0.75), (f - bonnet, belt), (b + (rear if style == "pickup" else 0), belt), (b, belt * (0.95 if style != "pickup" else 1.0))]
		if style == "pickup":
			body = [(b, sill), (f, sill), (f, belt * 0.75), (f - bonnet, belt), (b, belt)]
		kit.prism(body, w, (0, 0, 0), paint, "body", axis="x")
		g0, g1 = f - bonnet, b + rear
		rake_f, rake_b = 0.5, {"hatch": 0.35, "saloon": 0.55, "estate": 0.15, "suv": 0.2, "pickup": 0.05, "taxi": 0.3}[style]
		kit.prism([(g1, belt), (g0, belt), (g0 - rake_f, h - 0.04), (g1 + rake_b, h - 0.04)], w - 0.12, (0, 0, 0), "glass", "glasshouse", axis="x")
		kit.box((w - 0.2, (g0 - rake_f) - (g1 + rake_b) + 0.1, 0.05), (0, (g0 - rake_f + g1 + rake_b) / 2, h - 0.025), paint, "roof")
		for y in (g0 - rake_f - 0.02, (g0 - rake_f + g1 + rake_b) / 2, g1 + rake_b + 0.02):
			for s in (-1, 1):
				kit.strut((s * (w / 2 - 0.05), y + (0.5 if y > 0.3 else (-rake_b if y < -0.3 else 0)) * 0.9, belt), (s * (w / 2 - 0.09), y, h - 0.03), 0.07, 0.05, paint, "pillar")
		if style == "pickup":
			kit.box((w - 0.16, rear - 0.12, 0.02), (0, b + rear / 2, belt - 0.4), "plastic_black", "bed")
	r = 0.33 if style in ("suv", "pickup") else 0.3
	wheels(w, (f - l * 0.19, b + l * 0.19), r)
	lamps(w, l, belt * 0.72)
	kit.box((w * 0.5, 0.03, 0.14), (0, f, sill + 0.12), "plastic_black", "grille")
	for s in (-1, 1):
		kit.box((0.1, 0.06, 0.07), (s * (w / 2 + 0.04), f - bonnet - 0.1, belt + 0.05), paint, "mirror")
	if roof_kit == "police":
		kit.box((1.1, 0.25, 0.1), (0, 0, h + 0.05), "plastic_blue", "light_bar")
		for s in (-1, 1):
			kit.box((0.02, l * 0.5, 0.2), (s * (w / 2 + 0.002), -0.1, belt - 0.2), "hivis_yellow", "livery")
	elif roof_kit == "taxi":
		kit.box((0.35, 0.12, 0.12), (0, 0.2, h + 0.06), "plastic_yellow", "taxi_sign")


def van(l=5.4, w=2.0, h=2.5, paint="car_white", style="panel"):
	f, b = l / 2, -l / 2
	cab = 1.9
	with kit.hollow(0.15):
		kit.prism([(f - cab, 0.3), (f, 0.3), (f, 1.0), (f - 0.5, 1.15), (f - 1.0, h * 0.82 if style != "luton" else 2.0), (f - cab, h * 0.82 if style != "luton" else 2.0)], w, (0, 0, 0), paint, "cab", axis="x")
		kit.prism([(f - 0.52, 1.17), (f - 1.0, h * 0.8 if style != "luton" else 1.95), (f - 1.5, h * 0.8 if style != "luton" else 1.95), (f - 1.5, 1.17)], w + 0.01, (0, 0, 0), "glass", "cab_glass", axis="x")
		if style == "panel":
			kit.box((w, l - cab, h - 0.3), (0, b + (l - cab) / 2, 0.3 + (h - 0.3) / 2), paint, "load_body")
		elif style == "luton":
			kit.box((w + 0.1, l - cab + 0.9, h - 1.0), (0, b + (l - cab + 0.9) / 2, 1.0 + (h - 1.0) / 2), paint, "box_body")
			kit.box((w - 0.2, l - cab, 0.25), (0, b + (l - cab) / 2, 0.75), "steel_painted", "chassis")
		elif style == "minibus":
			kit.box((w, l - cab, h - 0.3), (0, b + (l - cab) / 2, 0.3 + (h - 0.3) / 2), paint, "body")
			kit.box((w + 0.01, l - cab - 0.4, 0.7), (0, b + (l - cab) / 2, h * 0.62), "glass", "windows")
		elif style == "ambulance":
			kit.box((w + 0.1, l - cab, h - 0.3), (0, b + (l - cab) / 2, 0.3 + (h - 0.3) / 2), "hivis_yellow", "body")
			kit.box((w + 0.11, l - cab, 0.35), (0, b + (l - cab) / 2, 1.0), "plastic_green", "livery")
			kit.box((1.4, 0.3, 0.12), (0, f - 1.5, h + 0.04), "plastic_blue", "light_bar")
		elif style == "tipper":
			kit.box((w - 0.2, l - cab, 0.25), (0, b + (l - cab) / 2, 0.75), "steel_painted", "chassis")
			with kit.hollow(0.1):
				kit.box((w, l - cab - 0.1, 0.45), (0, b + (l - cab) / 2, 1.1), "steel_painted", "drop_sides")
	wheels(w, (f - 1.0, b + l * 0.22), 0.35, 0.24)
	lamps(w, l, 0.8)


def bus(decks=1, l=11.5, paint="car_red"):
	w, h = 2.55, 3.0 if decks == 1 else 4.4
	with kit.hollow(0.08):
		kit.rounded_box((w, l, h - 0.35), (0, 0, 0.35 + (h - 0.35) / 2), paint, "body", radius=0.12)
		for i in range(decks):
			z = 1.75 + i * 1.75 if decks == 2 else 1.9
			kit.box((w + 0.01, l - 0.8, 0.85), (0, -0.1, z), "glass", "windows")
			kit.box((w - 0.3, 0.02, 0.9 if i else 1.3), (0, l / 2 + 0.002, z - (0 if i else 0.2)), "glass", "windscreen")
		kit.box((1.6, 0.03, 0.3), (0, l / 2 + 0.003, h - 0.35), "screen", "destination")
		kit.box((0.02, 1.2, 2.0), (-w / 2 - 0.003, l / 2 - 1.2, 1.35), "glass", "door")
	wheels(w, (l / 2 - 2.6, -l / 2 + 3.2), 0.5, 0.3)
	lamps(w, l, 0.7)


def lorry(style="artic", paint="car_white"):
	w = 2.5
	with kit.hollow(0.2):
		cab_y = 5.5 if style == "artic" else 3.4
		kit.rounded_box((w, 2.3, 2.6), (0, cab_y, 2.0), paint, "cab", radius=0.1)
		kit.box((w - 0.2, 0.02, 0.9), (0, cab_y + 1.152, 2.45), "glass", "windscreen")
		kit.box((1.0, 7.0 if style != "artic" else 3.6, 0.3), (0, cab_y - (3.4 if style != "artic" else 1.6), 0.85), "steel_painted", "chassis")
	if style == "artic":
		with kit.hollow(0.05):
			kit.box((w + 0.05, 13.6, 2.7), (0, -2.6, 2.65), "paint_white", "trailer")
		kit.box((1.0, 13.0, 0.25), (0, -2.6, 1.15), "steel_painted", "trailer_chassis")
		wheels(w, (5.4, 2.6, -6.2, -7.5, -8.8), 0.5, 0.32)
	elif style == "fire":
		with kit.hollow(0.15):
			kit.box((w, 5.6, 2.3), (0, -0.6, 1.9), "hazard_red", "body")
		kit.box((w + 0.01, 5.0, 0.3), (0, -0.6, 1.1), "hivis_yellow", "livery")
		kit.box((1.6, 0.3, 0.14), (0, 3.6, 3.37), "plastic_blue", "light_bar")
		for s in (-1, 1):
			kit.box((0.4, 5.0, 0.08), (s * 0.6, -0.6, 3.1), "aluminium", "ladder")
		wheels(w, (3.2, -1.9), 0.52, 0.32)
	elif style == "bin":
		with kit.hollow(0.08):
			kit.box((w, 4.6, 2.5), (0, -0.2, 2.25), "plastic_green", "hopper_body")
			kit.prism([(-4.3, 1.0), (-2.5, 1.0), (-2.5, 3.5), (-3.4, 3.5), (-4.3, 2.4)], w, (0, 0, 0), "plastic_green", "tailgate", axis="x")
		wheels(w, (3.2, -1.3, -2.6), 0.52, 0.32)
	elif style == "flatbed":
		kit.box((w, 7.0, 0.15), (0, -1.4, 1.1), "softwood", "deck")
		kit.box((w, 0.1, 1.2), (0, 2.15, 1.75), "steel_painted", "headboard")
		wheels(w, (3.2, -2.6, -3.9), 0.52, 0.32)
	lamps(w, 2 * (cab_y + 1.15), 0.9, tail=False)


def motorbike(scooter=False):
	r = 0.22 if scooter else 0.31
	for y in (-0.7, 0.7):
		kit.wheel(r, 0.11, (0, y, r))
	if scooter:
		kit.rounded_box((0.3, 0.9, 0.35), (0, -0.4, 0.5), "car_red", "body", radius=0.08)
		kit.box((0.35, 0.05, 0.6), (0, 0.45, 0.6), "car_red", "leg_shield", rot=(-15, 0, 0))
		kit.box((0.3, 0.5, 0.04), (0, 0.1, 0.25), "plastic_black", "footboard")
	else:
		kit.rounded_box((0.32, 0.5, 0.25), (0, 0.1, 0.82), "car_blue", "tank", radius=0.08)
		kit.rounded_box((0.3, 0.45, 0.3), (0, 0.05, 0.5), "aluminium", "engine", radius=0.04)
		kit.rod((0.15, 0, 0.35), (0.15, -0.85, 0.45), 0.04, "steel_stainless", "exhaust")
	kit.rounded_box((0.28, 0.6, 0.08), (0, -0.45, 0.8 if not scooter else 0.72), "leather_black", "seat", radius=0.035)
	kit.rod((0, 0.7, r), (0, 0.45, 1.0), 0.025, "steel_stainless", "forks")
	kit.rod((-0.33, 0.42, 1.03), (0.33, 0.42, 1.03), 0.014, "plastic_black", "handlebar")
	kit.cyl(0.07, 0.06, (0, 0.52, 0.9), "light_emitter", "headlamp", axis="y", segs=12)


def caravan():
	with kit.hollow(0.06):
		kit.rounded_box((2.2, 5.0, 2.0), (0, 0, 1.5), "paint_white", "body", radius=0.25)
	kit.box((1.4, 0.02, 0.6), (0, 2.502, 1.7), "glass", "front_window")
	for s in (-1, 1):
		kit.box((0.02, 1.2, 0.6), (s * 1.101, 0.6, 1.7), "glass", "side_window")
	wheels(2.2, (-0.3,), 0.3, 0.2)
	kit.prism([(-0.5, 0), (0.5, 0), (0, 1.3)], 0.08, (0, 2.5, 0.5), "steel_galvanised", "a_frame", axis="z")
	kit.rod((0, 3.6, 0), (0, 3.6, 0.5), 0.03, "steel_galvanised", "jockey_wheel")


def trailer():
	with kit.hollow(0.1):
		kit.box((1.3, 2.4, 0.45), (0, 0, 0.65), "steel_galvanised", "box")
	wheels(1.6, (-0.2,), 0.28, 0.16)
	kit.rod((0, 1.2, 0.5), (0, 2.2, 0.5), 0.03, "steel_galvanised", "drawbar")


_COLOURS = (("silver", "car_silver"), ("red", "car_red"), ("blue", "car_blue"), ("white", "car_white"))
_CARS = (("hatchback", "Hatchback", dict(l=4.1, w=1.78, h=1.48, style="hatch")), ("saloon", "Saloon car", dict(l=4.7, w=1.82, h=1.44, style="saloon")),
	("estate", "Estate car", dict(l=4.7, w=1.82, h=1.48, style="estate")), ("suv", "SUV", dict(l=4.6, w=1.9, h=1.7, style="suv")),
	("city", "City car", dict(l=3.5, w=1.62, h=1.5, style="hatch")))
for _n, _lab, _kw in _CARS:
	for _c, _slot in _COLOURS:
		reg("car.%s_%s" % (_n, _c), car, "%s, %s" % (_lab, _c), "car", paint=_slot, **_kw)
reg("car.pickup", car, "Pickup truck", "car", "site", l=5.3, w=1.9, h=1.8, style="pickup", paint="car_white")
reg("car.taxi", car, "Taxi", "car", l=4.6, w=1.85, h=1.8, style="taxi", paint="plastic_black", roof_kit="taxi")
reg("emergency.police_car", car, "Police car", "police", l=4.7, w=1.82, h=1.48, style="estate", paint="car_white", roof_kit="police")
reg("emergency.police_van", van, "Police van", "police", paint="car_white", style="minibus")
reg("emergency.ambulance", van, "Ambulance", "hospital", l=6.5, w=2.2, h=2.8, style="ambulance")
reg("emergency.fire_engine", lorry, "Fire engine", style="fire", paint="hazard_red")
reg("van.panel", van, "Panel van", "site")
reg("van.small", van, "Small van", "site", l=4.4, w=1.8, h=1.9)
reg("van.luton", van, "Luton box van", l=6.5, w=2.1, h=3.2, style="luton")
reg("van.minibus", van, "Minibus", "school", l=6.0, style="minibus")
reg("van.tipper", van, "Tipper van", "site", l=5.8, h=2.2, style="tipper")
reg("bus.single", bus, "Bus, single deck", "school")
reg("bus.double", bus, "Bus, double deck", decks=2, l=10.5)
reg("bus.coach", bus, "Coach", "airport", l=13.0, paint="car_white")
reg("bus.airside", bus, "Airside transfer bus", "airport", l=13.5, paint="car_blue")
reg("lorry.artic", lorry, "Articulated lorry")
reg("lorry.flatbed", lorry, "Flatbed lorry", "site", style="flatbed")
reg("lorry.bin", lorry, "Refuse lorry", style="bin")
reg("bike.motorbike", motorbike, "Motorbike")
reg("bike.scooter", motorbike, "Scooter", scooter=True)
reg("towed.caravan", caravan, "Caravan")
reg("towed.trailer", trailer, "Box trailer")
