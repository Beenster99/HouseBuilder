"""Stairs and lifts. A stair starts at the origin and climbs along +Y; the game scales it to
the drawn run and the storey height."""
import kit
from registry import register

RISE, GOING = 0.1875, 0.25


def _handrail(side_x, n, slot="steel_painted"):
	top = lambda i: (side_x, i * GOING + GOING / 2, (i + 1) * RISE)
	posts = sorted(set(list(range(0, n - 1, 3)) + [n - 2]))
	for i in posts:
		p = top(i)
		kit.rod(p, (p[0], p[1], p[2] + 0.9), 0.016, slot, "post")
	a, b = top(0), top(n - 2)
	for hgt, r in ((0.9, 0.021), (0.45, 0.012)):
		kit.rod((a[0], a[1], a[2] + hgt), (b[0], b[1], b[2] + hgt), r, slot, "rail")


def stair(material, rise=3.0, w=1.0):
	n = round(rise / RISE)
	run = (n - 1) * GOING
	with kit.stage("flight"):
		if material == "concrete":
			pts = [(0.0, 0.0)]
			for i in range(n):
				pts.append((i * GOING, (i + 1) * RISE))
				if i < n - 1:
					pts.append(((i + 1) * GOING, (i + 1) * RISE))
			pts += [(run, rise - 0.3), (0.35, 0.0)]
			kit.prism(pts, w, slot="concrete", name="flight", axis="x")
		else:
			slot, tread, t, sw = ("softwood", "hardwood", 0.032, 0.032) if material == "timber" else ("steel_painted", "steel_galvanised", 0.04, 0.012)
			for s in (-1, 1):
				x = s * (w / 2 - sw / 2)
				kit.strut((x, -0.1, 0.02), (x, run, rise + 0.06), 0.26, sw, slot, "stringer")
			for i in range(n - 1):
				kit.box((w - 2 * sw, GOING + 0.02, t), (0, i * GOING + GOING / 2, (i + 1) * RISE - t / 2), tread, "tread")
				if material == "timber":
					kit.box((w - 2 * sw, 0.012, RISE - t), (0, i * GOING + 0.006, (i + 0.5) * RISE - t / 2), "softwood", "riser")
	with kit.stage("balustrade"):
		for s in (-1, 1):
			_handrail(s * (w / 2 - 0.05), n, "hardwood" if material == "timber" else "steel_painted")
	kit.socket("foot", (0, 0, 0))
	kit.socket("head", (0, run, rise))


for _m in ("concrete", "timber", "steel"):
	register("circulation.stair." + _m, stair, _m.capitalize() + " stair flight", family="circulation", kind="stair",
		tags=("circulation", "stair", _m), material=_m)


def lift(w=2.0, d=2.0, h=2.3):
	cw, cd = w - 0.4, d - 0.5
	with kit.stage("car"):
		kit.box((cw, cd, 0.08), (0, -0.05, 0.04), "steel_painted", "floor")
		kit.box((cw, cd, 0.06), (0, -0.05, h), "steel_painted", "roof")
		kit.box((cw, 0.03, h), (0, -0.05 - cd / 2, h / 2), "steel_stainless", "back")
		for s in (-1, 1):
			kit.box((0.03, cd, h), (s * cw / 2, -0.05, h / 2), "steel_stainless", "side")
			kit.rod((s * (cw / 2 - 0.05), -cd / 2 + 0.2, 0.95), (s * (cw / 2 - 0.05), cd / 2 - 0.4, 0.95), 0.018, "steel_stainless", "handrail")
	with kit.stage("doors"):
		kit.frame(1.1, 2.15, 0.08, 0.14, at=(0, d / 2 - 0.07, 0), slot="steel_stainless", name="architrave", bottom=False)
		for s in (-1, 1):
			kit.box((0.465, 0.03, 2.07), (s * 0.235, d / 2 - 0.09, 1.035), "steel_stainless", "door")
		kit.box((0.09, 0.02, 0.2), (0.72, d / 2 + 0.005, 1.1), "plastic_black", "call_panel")
	with kit.stage("gear"):
		for s in (-1, 1):
			kit.box((0.09, 0.07, h + 0.5), (s * (w / 2 - 0.08), -0.05, (h + 0.5) / 2), "steel_galvanised", "guide_rail")
		kit.box((0.5, 0.25, 0.35), (0, -0.05, h + 0.24), "steel_painted", "hanger")
	kit.socket("landing", (0, d / 2, 0))


register("circulation.lift.passenger", lift, "Passenger lift car and landing doors", family="circulation", kind="lift", tags=("circulation", "lift"))
