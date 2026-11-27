"""Room fixtures for every catalog fixture kind, sized to the catalog's w, d, h.
Origin: floor centre. The back (the wall side) is -Y; the user stands at +Y."""
import math

import kit
from registry import catalog, register


def legs(w, d, h, sec=0.04, slot="steel_painted", inset=0.03, at=(0, 0)):
	for sx in (-1, 1):
		for sy in (-1, 1):
			kit.box((sec, sec, h), (at[0] + sx * (w / 2 - inset - sec / 2), at[1] + sy * (d / 2 - inset - sec / 2), h / 2), slot, "leg")


def chair(at=(0, 0), face=0.0, seat="fabric_blue", frame="steel_painted", sh=0.45, s=0.42):
	"""A simple chair at `at`, its front turned `face` degrees from +Y."""
	c, sn = math.cos(math.radians(face)), math.sin(math.radians(face))
	def p(x, y, z):
		return (at[0] + x * c - y * sn, at[1] + x * sn + y * c, z)
	for sx in (-1, 1):
		for sy in (-1, 1):
			a = p(sx * (s / 2 - 0.02), sy * (s / 2 - 0.02), 0)
			kit.rod(a, (a[0], a[1], sh if sy > 0 else sh + 0.38), 0.011, frame, "leg", segs=8)
	kit.rounded_box((s, s, 0.04), p(0, 0, sh), seat, "seat", radius=0.015, rot=(0, 0, face))
	kit.rounded_box((s, 0.03, 0.26), p(0, -s / 2 + 0.02, sh + 0.3), seat, "back", radius=0.012, rot=(0, 0, face))


def bed(w, d, h, pillows=1, hospital=False):
	frame = "steel_painted" if hospital else "hardwood"
	base = h * 0.55
	with kit.stage("frame"):
		kit.box((w, d, 0.12), (0, 0, base - 0.06), frame, "base")
		legs(w, d, base - 0.12, 0.05, frame)
		kit.box((w, 0.04, h + 0.45), (0, -d / 2 + 0.02, (h + 0.45) / 2), frame, "headboard")
		if hospital:
			kit.box((w, 0.04, h + 0.25), (0, d / 2 - 0.02, (h + 0.25) / 2), frame, "footboard")
			for s in (-1, 1):
				for z in (h + 0.12, h + 0.28):
					kit.rod((s * w / 2, -d / 4, z), (s * w / 2, d / 4, z), 0.012, "steel_stainless", "side_rail")
				for y in (-d / 4, d / 4):
					kit.rod((s * w / 2, y, base), (s * w / 2, y, h + 0.28), 0.012, "steel_stainless", "rail_post")
	with kit.stage("soft"):
		kit.rounded_box((w - 0.04, d - 0.08, h - base), (0, 0, base + (h - base) / 2), "fabric_white", "mattress", radius=0.05)
		for i in range(pillows):
			x = (i - (pillows - 1) / 2) * (w / pillows)
			kit.rounded_box((min(0.6, w / pillows - 0.1), 0.38, 0.12), (x, -d / 2 + 0.28, h + 0.05), "fabric_white", "pillow", radius=0.05)
		kit.rounded_box((w, d * 0.6, 0.05), (0, d * 0.18, h + 0.01), "fabric_blue", "duvet", radius=0.02)


def wc(w, d, h):
	with kit.hollow(0.25):
		with kit.stage("pan"):
			kit.lathe([(0.11, 0), (0.13, 0.05), (0.15, 0.3), (0.19, 0.4)], (0, d / 2 - 0.26, 0), "ceramic", "pan", scale=(w / 0.4, 1.25, 1))
			kit.lathe([(0.20, 0), (0.20, 0.025)], (0, d / 2 - 0.26, 0.4), "plastic_white", "seat", scale=(w / 0.42, 1.25, 1))
			kit.rounded_box((w, 0.18, h - 0.42), (0, -d / 2 + 0.09, 0.42 + (h - 0.42) / 2), "ceramic", "cistern", radius=0.025)
			kit.box((w * 0.5, 0.2, 0.42), (0, -d / 2 + 0.14, 0.21), "ceramic", "trap")
			kit.cyl(0.025, 0.012, (0, -d / 2 + 0.09, h + 0.006), "steel_stainless", "flush", segs=14)


def basin(w, d, h):
	with kit.hollow(0.3):
		with kit.stage("basin"):
			kit.lathe([(0.07, 0), (0.06, 0.3), (0.09, h - 0.17)], (0, -d / 2 + 0.2, 0), "ceramic", "pedestal", segs=16)
			kit.rounded_box((w, d, 0.17), (0, 0, h - 0.085), "ceramic", "bowl", radius=0.06)
			kit.lathe([(0.15, 0), (0.15, 0.006)], (0, 0.03, h - 0.002), "enamel", "bowl_inner", scale=(w / 0.42, d / 0.45, 1))
		with kit.stage("taps"):
			kit.cyl(0.018, 0.1, (0, -d / 2 + 0.07, h + 0.05), "steel_stainless", "tap", segs=12)
			kit.rod((0, -d / 2 + 0.07, h + 0.09), (0, -d / 2 + 0.19, h + 0.075), 0.011, "steel_stainless", "spout")


def bath(w, d, h):
	with kit.hollow(0.08):
		with kit.stage("bath"):
			kit.rounded_box((w, d, h), (0, 0, h / 2), "enamel", "tub", radius=0.05)
			kit.rounded_box((w - 0.14, d - 0.16, 0.012), (0, 0, h + 0.002), "ceramic", "inner", radius=0.004)
		with kit.stage("taps"):
			for s in (-1, 1):
				kit.cyl(0.02, 0.09, (s * 0.09, -d / 2 + 0.06, h + 0.045), "steel_stainless", "tap", segs=12)


def shower(w, d, h):
	with kit.hollow(0.5):
		with kit.stage("tray"):
			kit.rounded_box((w, d, 0.08), (0, 0, 0.04), "enamel", "tray", radius=0.02)
		with kit.stage("screen"):
			kit.box((w - 0.04, 0.008, h - 0.15), (0, d / 2 - 0.02, 0.08 + (h - 0.15) / 2), "glass", "door")
			kit.box((0.008, d - 0.04, h - 0.15), (w / 2 - 0.02, 0, 0.08 + (h - 0.15) / 2), "glass", "side")
			kit.rod((w / 2 - 0.02, d / 2 - 0.02, 0.08), (w / 2 - 0.02, d / 2 - 0.02, h - 0.07), 0.012, "aluminium", "post")
			kit.box((0.02, 0.03, 0.25), (-w / 4, d / 2, 1.05), "steel_stainless", "handle")
		with kit.stage("taps"):
			kit.rod((-w / 2 + 0.06, -d / 2 + 0.06, 1.0), (-w / 2 + 0.06, -d / 2 + 0.06, h - 0.05), 0.011, "steel_stainless", "riser")
			kit.rod((-w / 2 + 0.06, -d / 2 + 0.06, h - 0.05), (-w / 2 + 0.3, -d / 2 + 0.3, h - 0.05), 0.011, "steel_stainless", "arm")
			kit.cyl(0.1, 0.015, (-w / 2 + 0.3, -d / 2 + 0.3, h - 0.065), "steel_stainless", "head", segs=20)
			kit.box((0.14, 0.05, 0.1), (-w / 2 + 0.06, -d / 2 + 0.08, 1.05), "steel_stainless", "valve")


def kitchen_unit(w, d, h):
	with kit.stage("carcass"):
		kit.box((w, d - 0.06, 0.1), (0, -0.03, 0.05), "laminate_grey", "plinth")
		kit.box((w, d - 0.02, h - 0.14), (0, -0.01, 0.1 + (h - 0.14) / 2), "laminate_white", "carcass")
	with kit.stage("doors"):
		kit.box((w - 0.006, 0.018, h - 0.30), (0, d / 2 - 0.011, 0.1 + (h - 0.30) / 2), "laminate_grey", "door")
		kit.box((w - 0.006, 0.018, 0.14), (0, d / 2 - 0.011, h - 0.115), "laminate_grey", "drawer")
		for z in (h - 0.115, h - 0.27):
			kit.rod((-0.08, d / 2 + 0.02, z), (0.08, d / 2 + 0.02, z), 0.006, "steel_stainless", "handle", segs=8)
	with kit.stage("worktop"):
		kit.box((w, d + 0.02, 0.04), (0, 0.01, h - 0.02), "worktop", "worktop")


def sofa(w, d, h):
	with kit.stage("frame"):
		kit.rounded_box((w, d, 0.22), (0, 0, 0.21), "fabric_grey", "base", radius=0.04)
		legs(w, d, 0.1, 0.05, "hardwood", inset=0.05)
		kit.rounded_box((w, 0.2, h - 0.1), (0, -d / 2 + 0.1, 0.1 + (h - 0.1) / 2), "fabric_grey", "back", radius=0.06)
		for s in (-1, 1):
			kit.rounded_box((0.18, d, 0.5), (s * (w / 2 - 0.09), 0, 0.35), "fabric_grey", "arm", radius=0.06)
	with kit.stage("soft"):
		n = max(2, round((w - 0.36) / 0.6))
		cw = (w - 0.36) / n
		for i in range(n):
			x = -w / 2 + 0.18 + cw * (i + 0.5)
			kit.rounded_box((cw - 0.01, d - 0.22, 0.14), (x, 0.1, 0.39), "fabric_grey", "seat_cushion", radius=0.045)
			kit.rounded_box((cw - 0.01, 0.16, 0.36), (x, -d / 2 + 0.27, 0.62), "fabric_grey", "back_cushion", radius=0.06, rot=(-10, 0, 0))


def table(w, d, h, top="hardwood", leg="hardwood"):
	kit.box((w, d, 0.035), (0, 0, h - 0.0175), top, "top")
	legs(w, d, h - 0.035, 0.06, leg, inset=0.04)
	for s in (-1, 1):
		kit.box((w - 0.24, 0.02, 0.08), (0, s * (d / 2 - 0.07), h - 0.075), leg, "apron")


def dining_table(w, d, h):
	with kit.stage("table"):
		table(w, d, h)
	with kit.stage("chairs"):
		for x in (-w / 4, w / 4):
			chair((x, d / 2 + 0.12), 180, "fabric_grey", "hardwood")
			chair((x, -d / 2 - 0.12), 0, "fabric_grey", "hardwood")
		chair((w / 2 + 0.12, 0), 90, "fabric_grey", "hardwood")
		chair((-w / 2 - 0.12, 0), -90, "fabric_grey", "hardwood")


def task_chair(at):
	x, y = at
	for i in range(5):
		a = math.radians(72 * i)
		kit.rod((x, y, 0.07), (x + 0.28 * math.cos(a), y + 0.28 * math.sin(a), 0.05), 0.014, "plastic_black", "base", segs=8)
		kit.cyl(0.025, 0.04, (x + 0.28 * math.cos(a), y + 0.28 * math.sin(a), 0.025), "plastic_black", "castor", axis="x", segs=10)
	kit.cyl(0.025, 0.36, (x, y, 0.25), "steel_stainless", "gas_lift", segs=12)
	kit.rounded_box((0.46, 0.46, 0.07), (x, y, 0.46), "fabric_blue", "seat", radius=0.03)
	kit.rounded_box((0.42, 0.05, 0.5), (x, y + 0.22, 0.8), "fabric_blue", "back", radius=0.025, rot=(8, 0, 0))


def desk_office(w, d, h):
	with kit.stage("desk"):
		kit.box((w, d, 0.025), (0, 0, h - 0.0125), "laminate_white", "top")
		for s in (-1, 1):
			x = s * (w / 2 - 0.05)
			kit.box((0.05, d - 0.1, 0.03), (x, 0, 0.015), "steel_painted", "foot")
			kit.box((0.05, 0.05, h - 0.055), (x, -d / 4, 0.03 + (h - 0.055) / 2), "steel_painted", "leg")
		kit.box((w - 0.1, 0.018, 0.3), (0, -d / 2 + 0.06, h - 0.2), "laminate_grey", "modesty")
		kit.box((0.4, d - 0.2, 0.55), (w / 2 - 0.3, -0.02, 0.3), "laminate_grey", "pedestal")
	with kit.stage("equipment"):
		kit.box((0.56, 0.02, 0.33), (-0.1, -d / 2 + 0.2, h + 0.3), "plastic_black", "monitor")
		kit.cyl(0.02, 0.14, (-0.1, -d / 2 + 0.18, h + 0.07), "plastic_black", "stand", segs=10)
		kit.box((0.22, 0.16, 0.012), (-0.1, -d / 2 + 0.18, h + 0.006), "plastic_black", "stand_base")
		kit.box((0.42, 0.14, 0.02), (-0.1, 0.08, h + 0.01), "plastic_black", "keyboard")
	with kit.stage("chairs"):
		task_chair((-0.1, d / 2 + 0.25))


def desk_small(w, d, h, with_chair=True, slot="laminate_white"):
	with kit.stage("desk"):
		kit.box((w, d, 0.02), (0, 0, h - 0.01), slot, "top")
		legs(w, d, h - 0.02, 0.025, "steel_painted", inset=0.02)
		kit.box((w - 0.1, d - 0.12, 0.012), (0, 0, h - 0.14), "steel_painted", "tray")
	if with_chair:
		with kit.stage("chairs"):
			chair((0, d / 2 + 0.2), 180, "plastic_grey", "steel_painted", sh=0.4, s=0.36)


def desk_teacher(w, d, h):
	with kit.stage("desk"):
		table(w, d, h, "laminate_white", "steel_painted")
		kit.box((0.4, d - 0.15, 0.5), (w / 2 - 0.28, 0, h - 0.29), "laminate_grey", "drawers")
	with kit.stage("chairs"):
		task_chair((0, d / 2 + 0.25))


def hall_chair(w, d, h):
	chair((0, 0), 180, "plastic_grey", "steel_stainless", sh=0.44, s=min(w, d) - 0.06)


def reception_desk(w, d, h):
	with kit.stage("desk"):
		kit.box((w - 0.1, 0.05, h - 0.04), (0, d / 2 - 0.025, (h - 0.04) / 2), "laminate_grey", "front")
		kit.box((w, 0.3, 0.04), (0, d / 2 - 0.15, h - 0.02), "hardwood", "counter")
		kit.box((w - 0.1, d - 0.1, 0.03), (0, -0.05, 0.735), "laminate_white", "worktop")
		for s in (-1, 1):
			kit.box((0.05, d, h), (s * (w / 2 - 0.025), 0, h / 2), "laminate_grey", "end")
	with kit.stage("chairs"):
		task_chair((0, -d / 2 - 0.2))


def cell_bench(w, d, h):
	kit.box((w, d, h), (0, 0, h / 2), "concrete", "plinth")
	kit.rounded_box((w - 0.06, d - 0.1, 0.08), (0, 0, h + 0.04), "fabric_blue", "mattress", radius=0.03)


def cabinet(w, d, h, slot="steel_painted", doors=1, detail="none"):
	"""A wall or floor cabinet (consumer unit, boiler, lockers)."""
	with kit.hollow(0.05):
		with kit.stage("case"):
			kit.box((w, d - 0.02, h), (0, -0.01, h / 2), slot, "case")
		with kit.stage("doors"):
			dw = w / doors
			for i in range(doors):
				x = -w / 2 + dw * (i + 0.5)
				kit.box((dw - 0.01, 0.02, h - 0.02), (x, d / 2 - 0.01, h / 2), slot, "door")
				if detail == "locker":
					kit.box((0.02, 0.03, 0.08), (x + dw / 2 - 0.05, d / 2 + 0.005, h * 0.55), "steel_stainless", "latch")
					for z in (h - 0.12, h - 0.16, h - 0.2):
						kit.box((dw * 0.5, 0.024, 0.012), (x, d / 2 - 0.01, z), "plastic_black", "vent")
			if detail == "consumer":
				kit.box((w * 0.8, 0.024, h * 0.3), (0, d / 2 - 0.01, h * 0.5), "plastic_black", "window")
			if detail == "boiler":
				kit.box((w * 0.5, 0.024, 0.08), (0, d / 2 - 0.01, h * 0.25), "plastic_black", "controls")
				for x in (-0.12, -0.04, 0.04, 0.12):
					kit.cyl(0.011, 0.2, (x, -0.02, -0.1), "brass", "pipe", segs=10)
				kit.cyl(0.05, 0.25, (0, -d / 2 + 0.1, h + 0.125), "steel_stainless", "flue", segs=16)


def water_main(w, d, h):
	kit.rod((0, 0, 0), (0, 0, h), 0.016, "plastic_grey", "riser")
	kit.cyl(0.028, 0.06, (0, 0, h * 0.5), "brass", "stopcock", segs=12)
	kit.rod((0, 0, h * 0.5), (0, 0.08, h * 0.5), 0.008, "brass", "spindle")
	kit.box((0.08, 0.012, 0.02), (0, 0.08, h * 0.5), "hazard_red", "handle")
	kit.cyl(0.035, 0.1, (0, 0, h * 0.8), "plastic_black", "meter", segs=14)


def soil_stack(w, d, h):
	kit.tube(w / 2, h, (0, 0, h / 2), "plastic_grey", "stack", wall=0.004, segs=18)
	for z in (0.3, h - 0.3):
		kit.cyl(w / 2 + 0.008, 0.06, (0, 0, z), "plastic_grey", "collar", segs=18)
	kit.rod((0, 0, 0.45), (0, 0.16, 0.5), w / 2 - 0.005, "plastic_grey", "branch", segs=14)


RECIPES = {
	"bed_single": (bed, {"pillows": 1}), "bed_double": (bed, {"pillows": 2}), "hospital_bed": (bed, {"pillows": 1, "hospital": True}),
	"wc": (wc, {}), "basin": (basin, {}), "bath": (bath, {}), "shower": (shower, {}), "kitchen_unit": (kitchen_unit, {}),
	"sofa": (sofa, {}), "dining_table": (dining_table, {}), "desk_office": (desk_office, {}), "desk_pupil": (desk_small, {}),
	"desk_teacher": (desk_teacher, {}), "hall_chair": (hall_chair, {}), "reception_desk": (reception_desk, {}),
	"cell_bench": (cell_bench, {}), "consumer_unit": (cabinet, {"detail": "consumer", "slot": "plastic_white"}),
	"water_main": (water_main, {}), "boiler": (cabinet, {"detail": "boiler", "slot": "paint_white"}),
	"soil_stack": (soil_stack, {}), "locker": (cabinet, {"detail": "locker", "doors": 4, "slot": "steel_painted"}),
}

for _kind, _k in catalog()["kinds"].items():
	if _k["family"] == "fixture" and _kind in RECIPES:
		_fn, _extra = RECIPES[_kind]
		register("fixture." + _kind, _fn, _k["label"], family="fixture", kind=_kind, tags=("fixture",), w=_k["w"], d=_k["d"], h=_k["h"], **_extra)
