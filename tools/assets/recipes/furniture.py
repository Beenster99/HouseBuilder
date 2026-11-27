"""Loose furniture and fittings beyond the catalog fixtures: homes, offices, schools,
hospitals, police stations and airports. Origin: floor centre, back to -Y."""
import math

import kit
from recipes.fixtures import chair, legs, table, task_chair
from registry import register


def reg(id, fn, label, *tags, **params):
	register(id, fn, label, family="fixture", tags=("furniture",) + tags, **params)


# --- storage -------------------------------------------------------------------------------

def carcass(w, d, h, slot="laminate_white", doors=0, drawers=0, shelves=0, plinth=0.08, handle="steel_stainless", glass=False, open_front=False):
	"""The general cupboard: a box with doors, drawers or open shelves on its front."""
	with kit.hollow(0.15):
		if plinth:
			kit.box((w, d - 0.05, plinth), (0, -0.025, plinth / 2), slot, "plinth")
		t = 0.018
		for s in (-1, 1):
			kit.box((t, d, h - plinth), (s * (w / 2 - t / 2), 0, plinth + (h - plinth) / 2), slot, "side")
		for z in (plinth + t / 2, h - t / 2):
			kit.box((w - 2 * t, d, t), (0, 0, z), slot, "panel")
		kit.box((w - 2 * t, 0.006, h - plinth), (0, -d / 2 + 0.003, plinth + (h - plinth) / 2), slot, "back")
		for i in range(shelves):
			kit.box((w - 2 * t, d - 0.02, t), (0, 0, plinth + (h - plinth) * (i + 1) / (shelves + 1)), slot, "shelf")
	body_h = h - plinth
	dz = body_h * (0.3 if doors and drawers else 1.0) if drawers else 0.0
	for i in range(drawers):
		z = h - dz * (i + 0.5) / drawers
		kit.box((w - 0.006, 0.018, dz / drawers - 0.004), (0, d / 2 + 0.009, z), slot, "drawer")
		kit.rod((-min(0.1, w / 5), d / 2 + 0.035, z), (min(0.1, w / 5), d / 2 + 0.035, z), 0.005, handle, "handle", segs=6)
	if doors:
		dh = body_h - dz
		for i in range(doors):
			x = -w / 2 + w * (i + 0.5) / doors
			if glass:
				kit.frame(w / doors - 0.004, dh - 0.004, 0.05, 0.018, at=(x, d / 2 + 0.009, plinth + 0.002), slot=slot, name="door")
				kit.box((w / doors - 0.1, 0.004, dh - 0.1), (x, d / 2 + 0.009, plinth + dh / 2), "glass", "glass")
			else:
				kit.box((w / doors - 0.004, 0.018, dh - 0.004), (x, d / 2 + 0.009, plinth + dh / 2), slot, "door")
			hx = x + (w / doors / 2 - 0.04) * (1 if i % 2 == 0 or doors == 1 else -1)
			kit.rod((hx, d / 2 + 0.035, plinth + dh / 2 - 0.06), (hx, d / 2 + 0.035, plinth + dh / 2 + 0.06), 0.005, handle, "handle", segs=6)


for _n, _w, _dn in (("single", 0.5, 1), ("double", 1.0, 2), ("triple", 1.5, 3)):
	reg("furniture.wardrobe." + _n, carcass, "Wardrobe, %s" % _n, "home", "bedroom", w=_w, d=0.6, h=2.0, doors=_dn)
reg("furniture.storage.chest_of_drawers", carcass, "Chest of drawers", "home", "bedroom", w=0.8, d=0.45, h=0.9, drawers=4, slot="hardwood", plinth=0.05)
reg("furniture.storage.bedside_table", carcass, "Bedside table", "home", "bedroom", w=0.45, d=0.4, h=0.5, drawers=2, slot="hardwood", plinth=0.05)
reg("furniture.storage.sideboard", carcass, "Sideboard", "home", "living", w=1.6, d=0.45, h=0.8, doors=3, slot="hardwood", plinth=0.1)
reg("furniture.storage.tv_unit", carcass, "TV unit", "home", "living", w=1.5, d=0.4, h=0.45, doors=2, slot="hardwood", plinth=0.05)
reg("furniture.storage.display_cabinet", carcass, "Display cabinet", "home", "living", w=0.9, d=0.4, h=1.9, doors=2, shelves=3, glass=True, slot="hardwood")
for _n, _w, _h in (("low", 0.8, 0.9), ("tall", 0.8, 2.0), ("wide", 1.6, 2.0)):
	reg("furniture.storage.bookcase_" + _n, carcass, "Bookcase, %s" % _n, "home", "office", "school", w=_w, d=0.3, h=_h, shelves=2 if _h < 1 else 5, slot="hardwood")
reg("furniture.storage.filing_cabinet_2", carcass, "Filing cabinet, 2 drawer", "office", w=0.47, d=0.62, h=0.71, drawers=2, slot="steel_painted", plinth=0.0)
reg("furniture.storage.filing_cabinet_4", carcass, "Filing cabinet, 4 drawer", "office", w=0.47, d=0.62, h=1.32, drawers=4, slot="steel_painted", plinth=0.0)
reg("furniture.storage.stationery_cupboard", carcass, "Stationery cupboard", "office", "school", w=0.9, d=0.45, h=1.8, doors=2, slot="steel_painted", plinth=0.0)
reg("furniture.storage.tambour_unit", carcass, "Low storage unit", "office", w=1.0, d=0.47, h=1.0, doors=2, slot="laminate_grey", plinth=0.05)
reg("furniture.storage.evidence_locker", carcass, "Evidence locker bank", "police", w=1.2, d=0.5, h=1.9, doors=4, drawers=0, shelves=0, slot="steel_painted", plinth=0.1)
reg("furniture.storage.medicine_cabinet", carcass, "Medicine cabinet", "hospital", w=0.8, d=0.3, h=0.9, doors=2, slot="paint_white", plinth=0.0)
reg("furniture.storage.clinical_cupboard", carcass, "Clinical base cupboard", "hospital", w=1.0, d=0.6, h=0.9, doors=2, drawers=2, slot="laminate_white", plinth=0.1)
reg("furniture.storage.coat_cupboard", carcass, "Coat cupboard", "home", "hall", w=0.8, d=0.6, h=2.1, doors=2, slot="paint_white")
reg("furniture.storage.garage_cabinet", carcass, "Garage tool cabinet", "home", "garage", w=0.9, d=0.45, h=1.8, doors=2, slot="plastic_red", plinth=0.1)

# --- kitchen -------------------------------------------------------------------------------

def kitchen(what, w=0.6):
	d, h = 0.6, 0.9
	if what in ("base", "drawers", "sink", "hob"):
		carcass(w, d - 0.02, h - 0.04, "laminate_grey", doors=0 if what == "drawers" else (2 if w > 0.6 else 1), drawers=3 if what == "drawers" else 0, plinth=0.1)
		kit.box((w, d + 0.02, 0.04), (0, 0.0, h - 0.02), "worktop", "worktop")
		if what == "sink":
			kit.rounded_box((w * 0.55, 0.4, 0.02), (-w * 0.12, 0, h + 0.002), "steel_stainless", "bowl", radius=0.008)
			kit.box((w * 0.28, 0.4, 0.006), (w * 0.3, 0, h + 0.003), "steel_stainless", "drainer")
			kit.sweep([(-w * 0.12, -0.24, h), (-w * 0.12, -0.24, h + 0.25), (-w * 0.12, -0.18, h + 0.3), (-w * 0.12, -0.08, h + 0.27)], kit.circle(0.012, 10), "steel_stainless", "tap", up=(1, 0, 0))
		if what == "hob":
			kit.box((w - 0.04, 0.5, 0.008), (0, 0, h + 0.004), "screen", "hob")
			for x in (-0.14, 0.14):
				for y in (-0.11, 0.11):
					kit.cyl(0.085, 0.002, (x, y, h + 0.009), "plastic_grey", "zone", segs=20)
	elif what == "wall":
		carcass(w, 0.32, 0.72, "laminate_grey", doors=2 if w > 0.6 else 1, plinth=0.0)
	elif what == "tall":
		carcass(w, d - 0.02, 2.1, "laminate_grey", doors=1, drawers=0, shelves=3, plinth=0.1)
	elif what == "oven":
		carcass(w, d - 0.02, 2.1, "laminate_grey", doors=0, plinth=0.1)
		for z in (0.75, 1.36):
			kit.box((w - 0.01, 0.02, 0.58), (0, d / 2, z), "steel_stainless", "oven_door")
			kit.box((w - 0.16, 0.022, 0.3), (0, d / 2, z - 0.04), "screen", "oven_glass")
			kit.rod((-w / 2 + 0.06, d / 2 + 0.04, z + 0.22), (w / 2 - 0.06, d / 2 + 0.04, z + 0.22), 0.008, "steel_stainless", "handle")
	elif what == "island":
		carcass(w, 0.9, h - 0.04, "laminate_grey", doors=4, plinth=0.1)
		kit.box((w + 0.3, 1.2, 0.04), (0, 0, h - 0.02), "worktop", "worktop")
	elif what == "extractor":
		kit.box((w, 0.5, 0.06), (0, 0.25, 0.03), "steel_stainless", "canopy")
		kit.box((0.25, 0.25, 0.7), (0, 0.125, 0.41), "steel_stainless", "chimney")


for _k, _l, _ws in (("base", "Kitchen base unit", (0.3, 0.6, 1.0)), ("drawers", "Kitchen drawer unit", (0.6,)), ("sink", "Kitchen sink unit", (1.0,)),
		("hob", "Kitchen hob unit", (0.6,)), ("wall", "Kitchen wall unit", (0.3, 0.6, 1.0)), ("tall", "Tall larder unit", (0.6,)),
		("oven", "Oven housing with double oven", (0.6,)), ("island", "Kitchen island", (1.8,)), ("extractor", "Chimney extractor hood", (0.6, 0.9))):
	for _w in _ws:
		reg("furniture.kitchen.%s_%d" % (_k, _w * 1000), kitchen, "%s, %d mm" % (_l, _w * 1000), "home", "kitchen", what=_k, w=_w)


def appliance(what):
	w, d = 0.6, 0.6
	if what == "fridge_freezer":
		with kit.hollow(0.1):
			kit.rounded_box((w, d, 1.85), (0, 0, 0.925), "paint_white", "cabinet", radius=0.015)
		for z, hh in ((0.42, 0.78), (1.36, 0.95)):
			kit.box((w - 0.01, 0.02, hh), (0, d / 2 + 0.005, z), "paint_white", "door")
			kit.rod((-w / 2 + 0.05, d / 2 + 0.04, z - hh / 4), (-w / 2 + 0.05, d / 2 + 0.04, z + hh / 4), 0.008, "steel_stainless", "handle")
	elif what in ("washing_machine", "dishwasher", "tumble_dryer"):
		with kit.hollow(0.15):
			kit.rounded_box((w, d - 0.03, 0.85), (0, -0.015, 0.425), "paint_white", "cabinet", radius=0.012)
		kit.box((w - 0.02, 0.012, 0.1), (0, d / 2 - 0.01, 0.78), "plastic_white", "fascia")
		kit.cyl(0.025, 0.02, (0.2, d / 2, 0.78), "plastic_grey", "dial", axis="y", segs=14)
		if what != "dishwasher":
			kit.tube(0.2, 0.03, (0, d / 2 - 0.005, 0.42), "plastic_grey", "door_ring", axis="y", wall=0.04, segs=24)
			kit.cyl(0.16, 0.02, (0, d / 2 - 0.005, 0.42), "glass", "porthole", axis="y", segs=24)
		else:
			kit.rod((-0.2, d / 2 + 0.02, 0.68), (0.2, d / 2 + 0.02, 0.68), 0.008, "steel_stainless", "handle")
	elif what == "range_cooker":
		with kit.hollow(0.2):
			kit.box((0.9, d, 0.9), (0, 0, 0.45), "steel_stainless", "body")
		for x in (-0.22, 0.22):
			kit.box((0.42, 0.02, 0.5), (x, d / 2, 0.4), "screen", "oven_door")
			kit.rod((x - 0.18, d / 2 + 0.04, 0.68), (x + 0.18, d / 2 + 0.04, 0.68), 0.008, "steel_stainless", "handle")
		for i in range(5):
			kit.cyl(0.05, 0.02, (-0.3 + i * 0.15, 0.05 * (i % 2) - 0.05, 0.91), "cast_iron", "burner", segs=14)
			kit.cyl(0.018, 0.03, (-0.3 + i * 0.15, d / 2 + 0.01, 0.8), "plastic_black", "knob", axis="y", segs=10)
	elif what == "microwave":
		kit.rounded_box((0.48, 0.36, 0.28), (0, 0, 0.14), "steel_stainless", "body", radius=0.01)
		kit.box((0.32, 0.01, 0.2), (-0.06, 0.18, 0.14), "screen", "door")
	elif what == "kettle":
		kit.lathe([(0.07, 0), (0.075, 0.12), (0.06, 0.2), (0.0, 0.21)], slot="steel_stainless", name="kettle", segs=16)
		kit.sweep([(0.06, 0, 0.18), (0.11, 0, 0.16), (0.11, 0, 0.06), (0.07, 0, 0.04)], kit.circle(0.01, 8), "plastic_black", "handle", up=(0, 1, 0))
	elif what == "vending_machine":
		with kit.hollow(0.2):
			kit.box((0.95, 0.85, 1.83), (0, 0, 0.915), "plastic_black", "cabinet")
		kit.box((0.6, 0.01, 1.2), (-0.13, 0.425, 1.1), "glass", "window")
		kit.box((0.2, 0.012, 0.5), (0.33, 0.425, 1.2), "plastic_grey", "panel")
		kit.box((0.6, 0.012, 0.18), (-0.13, 0.425, 0.3), "plastic_grey", "tray")
	elif what == "water_cooler":
		kit.rounded_box((0.32, 0.32, 1.0), (0, 0, 0.5), "paint_white", "body", radius=0.02)
		kit.lathe([(0.13, 1.0), (0.135, 1.3), (0.06, 1.38), (0.0, 1.38)], slot="water", name="bottle", segs=18)
		for x, s in ((-0.05, "plastic_blue"), (0.05, "plastic_red")):
			kit.box((0.03, 0.04, 0.03), (x, 0.17, 0.82), s, "tap")
	elif what == "tv_55":
		kit.box((1.23, 0.03, 0.71), (0, 0, 0.5), "screen", "screen")
		kit.box((0.4, 0.2, 0.015), (0, 0, 0.0075), "plastic_black", "stand")
		kit.box((0.06, 0.03, 0.15), (0, -0.01, 0.08), "plastic_black", "neck")
	elif what == "photocopier":
		with kit.hollow(0.2):
			kit.box((0.62, 0.68, 1.0), (0, 0, 0.5), "plastic_white", "body")
		kit.box((0.6, 0.5, 0.08), (0, 0.02, 1.04), "plastic_grey", "feeder")
		kit.box((0.2, 0.12, 0.02), (0.15, 0.32, 1.02), "screen", "panel", rot=(30, 0, 0))
		for i in range(3):
			kit.box((0.56, 0.01, 0.14), (0, 0.34, 0.15 + i * 0.17), "plastic_grey", "tray")


for _k, _l, _t in (("fridge_freezer", "Fridge freezer", "kitchen"), ("washing_machine", "Washing machine", "utility"), ("dishwasher", "Dishwasher", "kitchen"),
		("tumble_dryer", "Tumble dryer", "utility"), ("range_cooker", "Range cooker", "kitchen"), ("microwave", "Microwave oven", "kitchen"),
		("kettle", "Kettle", "kitchen"), ("vending_machine", "Vending machine", "office"), ("water_cooler", "Water cooler", "office"),
		("tv_55", "55 inch television", "living"), ("photocopier", "Photocopier", "office")):
	reg("furniture.appliance." + _k, appliance, _l, "home" if _t not in ("office",) else "office", _t, what=_k)

# --- seating and tables --------------------------------------------------------------------

def seat(what, n=1):
	if what == "armchair":
		kit.rounded_box((0.85, 0.85, 0.2), (0, 0, 0.3), "fabric_grey", "base", radius=0.04)
		kit.rounded_box((0.85, 0.2, 0.75), (0, -0.325, 0.475), "fabric_grey", "back", radius=0.06)
		for s in (-1, 1):
			kit.rounded_box((0.16, 0.7, 0.42), (s * 0.345, 0.07, 0.41), "fabric_grey", "arm", radius=0.05)
		kit.rounded_box((0.52, 0.62, 0.14), (0, 0.1, 0.44), "fabric_grey", "cushion", radius=0.045)
		legs(0.85, 0.85, 0.1, 0.05, "hardwood", 0.05)
	elif what == "dining_chair":
		chair((0, 0), 180, "fabric_grey", "hardwood")
	elif what == "stool":
		kit.cyl(0.17, 0.04, (0, 0, 0.73), "hardwood", "seat", segs=20)
		for a in range(4):
			c, s = math.cos(math.radians(45 + 90 * a)), math.sin(math.radians(45 + 90 * a))
			kit.rod((0.1 * c, 0.1 * s, 0.72), (0.19 * c, 0.19 * s, 0), 0.014, "steel_painted", "leg")
		kit.tube(0.16, 0.012, (0, 0, 0.25), "steel_painted", "foot_ring", wall=0.012, segs=20)
	elif what == "task_chair":
		task_chair((0, 0))
	elif what == "stacking_chair":
		chair((0, 0), 180, "plastic_blue", "steel_stainless", sh=0.44, s=0.42)
	elif what == "beam_seating":
		kit.box((0.55 * n, 0.06, 0.06), (0, 0, 0.35), "steel_painted", "beam")
		for s in (-1, 1):
			kit.box((0.05, 0.5, 0.03), (s * (0.275 * n - 0.1), 0, 0.015), "steel_painted", "foot")
			kit.box((0.05, 0.05, 0.32), (s * (0.275 * n - 0.1), 0, 0.19), "steel_painted", "leg")
		for i in range(n):
			x = (i - (n - 1) / 2) * 0.55
			kit.rounded_box((0.48, 0.46, 0.05), (x, 0.03, 0.42), "leather_black", "seat", radius=0.02)
			kit.rounded_box((0.48, 0.05, 0.42), (x, -0.2, 0.66), "leather_black", "back", radius=0.02, rot=(-8, 0, 0))
			kit.box((0.04, 0.4, 0.03), (x - 0.275, 0.02, 0.6), "steel_stainless", "armrest")
		kit.box((0.04, 0.4, 0.03), ((n - 1) / 2 * 0.55 + 0.275, 0.02, 0.6), "steel_stainless", "armrest")
	elif what == "bench":
		kit.box((1.5 * n / 3, 0.38, 0.045), (0, 0, 0.44), "hardwood", "seat")
		for s in (-1, 1):
			kit.box((0.045, 0.34, 0.42), (s * (0.75 * n / 3 - 0.1), 0, 0.21), "hardwood", "leg")
	elif what == "wheelchair":
		for s in (-1, 1):
			kit.tube(0.3, 0.03, (s * 0.3, -0.05, 0.3), "rubber", "wheel", axis="x", wall=0.025, segs=24)
			kit.cyl(0.07, 0.03, (s * 0.25, 0.4, 0.07), "rubber", "castor", axis="x", segs=14)
			kit.sweep([(s * 0.25, -0.25, 0.95), (s * 0.25, -0.2, 0.5), (s * 0.25, 0.3, 0.5), (s * 0.25, 0.4, 0.15)], kit.circle(0.012, 8), "steel_stainless", "frame", up=(1, 0, 0))
		kit.box((0.45, 0.42, 0.03), (0, 0.07, 0.5), "leather_black", "seat")
		kit.box((0.45, 0.02, 0.4), (0, -0.2, 0.72), "leather_black", "back")
	elif what == "bean_bag":
		kit.lathe([(0.3, 0), (0.42, 0.12), (0.36, 0.38), (0.15, 0.5), (0.0, 0.5)], slot="fabric_red", name="bag", segs=18)
	elif what == "sofa_2":
		from recipes.fixtures import sofa
		sofa(1.5, 0.9, 0.8)
	elif what == "corner_sofa":
		from recipes.fixtures import sofa
		sofa(2.4, 0.9, 0.8)
		kit.rounded_box((0.9, 1.4, 0.3), (0.75, 1.15, 0.25), "fabric_grey", "chaise", radius=0.05)
		kit.rounded_box((0.86, 1.36, 0.12), (0.75, 1.15, 0.45), "fabric_grey", "chaise_cushion", radius=0.045)
	elif what == "pew":
		kit.box((2.0, 0.4, 0.04), (0, 0.05, 0.44), "hardwood", "seat")
		kit.box((2.0, 0.04, 0.5), (0, -0.17, 0.7), "hardwood", "back")
		for s in (-1, 1):
			kit.box((0.04, 0.5, 0.95), (s * 1.0, 0, 0.475), "hardwood", "end")


for _k, _l, _tags in (("armchair", "Armchair", ("home", "living")), ("dining_chair", "Dining chair", ("home", "dining")), ("stool", "Bar stool", ("home", "kitchen")),
		("task_chair", "Task chair", ("office",)), ("stacking_chair", "Stacking chair", ("school", "office")), ("wheelchair", "Wheelchair", ("hospital",)),
		("bean_bag", "Bean bag", ("home", "school")), ("sofa_2", "Two-seat sofa", ("home", "living")), ("corner_sofa", "Corner sofa", ("home", "living")),
		("pew", "Bench pew, 2 m", ("police", "public"))):
	reg("furniture.seat." + _k, seat, _l, *_tags, what=_k)
for _n in (2, 3, 4, 5):
	reg("furniture.seat.beam_%d" % _n, seat, "Beam seating, %d seats" % _n, "airport", "hospital", "waiting", what="beam_seating", n=_n)
for _n, _l in ((3, "1.5 m"), (4, "2 m")):
	reg("furniture.seat.bench_%d" % _n, seat, "Timber bench, " + _l, "school", "changing", what="bench", n=_n)


def tables(what, w=1.2, d=0.6):
	if what == "coffee":
		kit.box((w, d, 0.03), (0, 0, 0.42), "hardwood", "top")
		kit.box((w - 0.1, d - 0.1, 0.02), (0, 0, 0.15), "hardwood", "shelf")
		legs(w, d, 0.405, 0.05, "hardwood", 0.02)
	elif what == "side":
		kit.cyl(0.25, 0.025, (0, 0, 0.55), "hardwood", "top", segs=22)
		kit.cyl(0.02, 0.53, (0, 0, 0.275), "steel_painted", "stem", segs=10)
		kit.cyl(0.18, 0.015, (0, 0, 0.0075), "steel_painted", "base", segs=22)
	elif what == "meeting":
		kit.rounded_box((w, d, 0.03), (0, 0, 0.735), "hardwood", "top", radius=0.012, segments=2)
		for s in (-1, 1):
			kit.box((0.08, d * 0.6, 0.72), (s * (w / 2 - 0.4), 0, 0.36), "steel_painted", "pedestal")
			kit.box((0.5, d * 0.7, 0.02), (s * (w / 2 - 0.4), 0, 0.01), "steel_painted", "foot")
		n = max(1, int(w / 0.7))
		for i in range(n):
			x = -w / 2 + w * (i + 0.5) / n
			task_chair((x, d / 2 + 0.3))
			task_chair((x, -d / 2 - 0.3))
	elif what == "folding":
		kit.box((w, d, 0.02), (0, 0, 0.73), "laminate_white", "top")
		for s in (-1, 1):
			kit.sweep([(s * (w / 2 - 0.15), -d / 2 + 0.05, 0), (s * (w / 2 - 0.15), -d / 2 + 0.05, 0.71), (s * (w / 2 - 0.15), d / 2 - 0.05, 0.71), (s * (w / 2 - 0.15), d / 2 - 0.05, 0)], kit.circle(0.012, 8), "steel_painted", "leg", up=(1, 0, 0))
	elif what == "canteen":
		kit.box((w, d, 0.025), (0, 0, 0.73), "laminate_white", "top")
		for s in (-1, 1):
			kit.box((w, 0.28, 0.03), (0, s * (d / 2 + 0.25), 0.44), "plastic_blue", "bench")
			for x in (-w / 2 + 0.2, w / 2 - 0.2):
				kit.sweep([(x, s * (d / 2 + 0.25), 0.43), (x, s * (d / 2 + 0.25), 0.05), (x, 0, 0.05), (x, 0, 0.72)], kit.circle(0.02, 8), "steel_painted", "frame", up=(1, 0, 0))
	elif what == "lab_bench":
		kit.box((w, d, 0.03), (0, 0, 0.885), "worktop", "top")
		legs(w, d, 0.87, 0.05, "steel_painted", 0.0)
		kit.box((0.4, d - 0.1, 0.5), (-w / 2 + 0.25, 0, 0.6), "laminate_grey", "cupboard")
		kit.sweep([(0.3, -0.1, 0.9), (0.3, -0.1, 1.15), (0.3, 0.0, 1.2), (0.3, 0.08, 1.12)], kit.circle(0.01, 8), "brass", "gas_tap", up=(1, 0, 0))
		kit.rounded_box((0.3, 0.3, 0.02), (0.3, 0.08, 0.902), "ceramic", "sink", radius=0.008)
	elif what == "workbench":
		kit.box((w, d, 0.05), (0, 0, 0.875), "hardwood", "top")
		legs(w, d, 0.85, 0.08, "softwood", 0.0)
		kit.box((w - 0.1, d - 0.1, 0.02), (0, 0, 0.2), "plywood", "shelf")
		kit.box((0.15, 0.2, 0.12), (w / 2 - 0.15, d / 2, 0.82), "cast_iron", "vice")
	elif what == "overbed":
		kit.box((0.8, 0.4, 0.02), (0, 0, 0.9), "laminate_white", "top")
		kit.box((0.05, 0.05, 0.85), (-0.35, 0, 0.47), "steel_stainless", "column")
		kit.box((0.7, 0.05, 0.04), (0, 0, 0.05), "steel_stainless", "base")
	elif what == "interview":
		table(w, d, 0.74, "laminate_grey", "steel_painted")
		chair((-0.3, d / 2 + 0.15), 180, "plastic_grey", "steel_painted")
		chair((0.3, d / 2 + 0.15), 180, "plastic_grey", "steel_painted")
		chair((-0.3, -d / 2 - 0.15), 0, "plastic_grey", "steel_painted")
		chair((0.3, -d / 2 - 0.15), 0, "plastic_grey", "steel_painted")
	elif what == "picnic":
		kit.box((w, 0.7, 0.04), (0, 0, 0.74), "softwood", "top")
		for s in (-1, 1):
			kit.box((w, 0.25, 0.04), (0, s * 0.62, 0.44), "softwood", "seat")
			for x in (-w / 2 + 0.2, w / 2 - 0.2):
				kit.strut((x, s * 0.75, 0), (x, s * 0.2, 0.72), 0.09, 0.04, "softwood", "leg")
		for x in (-w / 2 + 0.2, w / 2 - 0.2):
			kit.box((0.04, 1.5, 0.09), (x, 0, 0.4), "softwood", "rail")


for _id, _k, _l, _dims, _tags in (("coffee", "coffee", "Coffee table", (1.1, 0.6), ("home", "living")), ("side", "side", "Side table", (0.5, 0.5), ("home", "living")),
		("meeting_4", "meeting", "Meeting table for 4", (1.6, 1.0), ("office",)), ("meeting_8", "meeting", "Meeting table for 8", (2.8, 1.2), ("office",)),
		("boardroom_14", "meeting", "Boardroom table for 14", (5.0, 1.4), ("office",)), ("folding", "folding", "Folding table", (1.8, 0.75), ("school", "office")),
		("canteen", "canteen", "Canteen table with benches", (1.8, 0.7), ("school",)), ("lab_bench", "lab_bench", "Science lab bench", (1.5, 0.75), ("school",)),
		("workbench", "workbench", "Workbench with vice", (1.8, 0.7), ("home", "garage", "school")), ("overbed", "overbed", "Overbed table", (0.8, 0.4), ("hospital",)),
		("interview", "interview", "Interview table and four chairs", (1.2, 0.8), ("police",)), ("picnic", "picnic", "Picnic table", (1.8, 0.7), ("outdoor", "school"))):
	reg("furniture.table." + _id, tables, _l, *_tags, what=_k, w=_dims[0], d=_dims[1])

# --- rooms: bathroom, bedroom, living extras ---------------------------------------------------

def home(what):
	if what == "vanity":
		carcass(0.8, 0.45, 0.8, "laminate_white", doors=2, plinth=0.1)
		kit.rounded_box((0.82, 0.47, 0.05), (0, 0.0, 0.825), "ceramic", "basin_top", radius=0.012)
		kit.lathe([(0.17, 0), (0.17, 0.006)], (0, 0.03, 0.848), "enamel", "bowl", scale=(1.3, 0.9, 1))
		kit.cyl(0.015, 0.12, (0, -0.17, 0.91), "steel_stainless", "tap", segs=10)
	elif what == "mirror_cabinet":
		kit.box((0.6, 0.14, 0.7), (0, 0.07, 0.35), "paint_white", "cabinet")
		kit.box((0.59, 0.005, 0.69), (0, 0.143, 0.35), "mirror", "mirror")
	elif what == "mirror":
		kit.box((0.5, 0.02, 1.5), (0, 0.01, 0.75), "hardwood", "frame")
		kit.box((0.44, 0.005, 1.44), (0, 0.021, 0.75), "mirror", "mirror")
	elif what == "bidet":
		kit.lathe([(0.11, 0), (0.13, 0.05), (0.15, 0.3), (0.19, 0.38), (0.15, 0.39), (0.0, 0.3)], slot="ceramic", name="bidet", scale=(1, 1.3, 1))
		kit.cyl(0.012, 0.08, (0, -0.2, 0.42), "steel_stainless", "tap", segs=10)
	elif what == "urinal":
		kit.lathe([(0.0, 0.0), (0.12, 0.02), (0.17, 0.2), (0.17, 0.55), (0.1, 0.62), (0.0, 0.62)], (0, 0.1, 0.4), "ceramic", "bowl", scale=(1, 0.75, 1))
		kit.rod((0, 0.03, 1.02), (0, 0.03, 1.4), 0.01, "steel_stainless", "flush_pipe")
	elif what == "accessible_wc":
		from recipes.fixtures import wc
		wc(0.4, 0.75, 0.85)
		for s in (-1, 1):
			kit.sweep([(s * 0.4, -0.375, 0.68), (s * 0.4, 0.3, 0.68), (s * 0.4, 0.3, 0.45), (s * 0.4, -0.375, 0.45)], kit.circle(0.017, 10), "plastic_blue", "grab_rail", up=(1, 0, 0))
	elif what == "bathroom_radiator_shelf":
		kit.box((0.6, 0.15, 0.02), (0, 0.075, 0), "glass", "shelf")
		for x in (-0.25, 0.25):
			kit.box((0.02, 0.15, 0.03), (x, 0.075, -0.02), "steel_stainless", "bracket")
	elif what == "bunk_bed":
		for z in (0.3, 1.4):
			kit.box((0.95, 2.0, 0.1), (0, 0, z), "softwood", "frame")
			kit.rounded_box((0.9, 1.9, 0.15), (0, 0, z + 0.125), "fabric_white", "mattress", radius=0.04)
			kit.rounded_box((0.5, 0.35, 0.1), (0, -0.75, z + 0.24), "fabric_white", "pillow", radius=0.04)
		for sx in (-1, 1):
			for sy in (-1, 1):
				kit.box((0.07, 0.07, 1.8), (sx * 0.47, sy * 0.98, 0.9), "softwood", "post")
		kit.box((0.03, 1.5, 0.08), (0.49, 0.2, 1.7), "softwood", "guard_rail")
		for i in range(4):
			kit.box((0.35, 0.03, 0.04), (0.3, 1.02, 0.35 + i * 0.3), "softwood", "rung")
	elif what == "cot":
		kit.box((0.7, 1.3, 0.06), (0, 0, 0.45), "paint_white", "base")
		kit.rounded_box((0.64, 1.24, 0.1), (0, 0, 0.53), "fabric_white", "mattress", radius=0.03)
		for s in (-1, 1):
			kit.box((0.03, 1.3, 0.03), (s * 0.35, 0, 0.95), "paint_white", "top_rail")
			for i in range(13):
				kit.rod((s * 0.35, -0.6 + i * 0.1, 0.45), (s * 0.35, -0.6 + i * 0.1, 0.95), 0.008, "paint_white", "bar", segs=6)
			kit.box((0.7, 0.03, 0.95), (0, s * 0.65, 0.475), "paint_white", "end")
	elif what == "dressing_table":
		table(1.1, 0.45, 0.76, "paint_white", "paint_white")
		kit.box((0.6, 0.02, 0.6), (0, -0.2, 1.1), "mirror", "mirror")
		seat("stool") if False else kit.rounded_box((0.4, 0.3, 0.42), (0, 0.45, 0.21), "fabric_grey", "stool", radius=0.04)
	elif what == "rug":
		kit.box((2.0, 1.4, 0.012), (0, 0, 0.006), "carpet", "rug")
	elif what == "floor_lamp":
		kit.cyl(0.14, 0.02, (0, 0, 0.01), "steel_painted", "base", segs=20)
		kit.cyl(0.012, 1.4, (0, 0, 0.72), "steel_painted", "stem", segs=10)
		kit.lathe([(0.2, 1.35), (0.14, 1.65)], slot="fabric_white", name="shade", segs=20)
	elif what == "desk_lamp":
		kit.cyl(0.07, 0.015, (0, 0, 0.0075), "plastic_black", "base", segs=16)
		kit.rod((0, 0, 0.01), (0, 0.1, 0.3), 0.006, "plastic_black", "arm")
		kit.rod((0, 0.1, 0.3), (0, -0.1, 0.42), 0.006, "plastic_black", "arm")
		kit.lathe([(0.02, 0.0), (0.06, -0.07)], (0, -0.1, 0.43), "plastic_black", "shade", segs=14)
	elif what == "curtains":
		kit.rod((-0.9, 0.05, 2.2), (0.9, 0.05, 2.2), 0.012, "steel_stainless", "pole")
		for s in (-1, 1):
			pts = []
			for i in range(9):
				pts.append((i * 0.05, 0.03 if i % 2 else -0.03))
			pts += [(0.4, -0.04), (0.0, -0.04)]
			kit.prism([(s * (0.45 + x), y + 0.05) for x, y in pts][::s], 2.15, (0, 0, 1.1), "fabric_blue", "curtain", axis="z")
	elif what == "blind":
		kit.box((1.2, 0.05, 0.05), (0, 0.025, 1.3), "paint_white", "cassette")
		kit.box((1.16, 0.003, 1.25), (0, 0.025, 0.65), "fabric_white", "blind")
	elif what == "fireplace":
		kit.box((1.3, 0.2, 1.1), (0, 0.1, 0.55), "paint_white", "surround")
		kit.box((1.45, 0.25, 0.05), (0, 0.125, 1.125), "paint_white", "mantel")
		kit.box((0.6, 0.21, 0.65), (0, 0.1, 0.325), "cast_iron", "firebox")
		kit.box((1.3, 0.45, 0.04), (0, 0.225, 0.02), "slate", "hearth")
	elif what == "wood_stove":
		kit.rounded_box((0.5, 0.4, 0.55), (0, 0, 0.4), "cast_iron", "body", radius=0.02)
		legs(0.5, 0.4, 0.13, 0.04, "cast_iron", 0.02)
		kit.box((0.34, 0.01, 0.3), (0, 0.2, 0.4), "glass", "door_glass")
		kit.cyl(0.075, 1.6, (0, -0.08, 1.45), "cast_iron", "flue", segs=16)
	elif what == "piano":
		with kit.hollow(0.3):
			kit.box((1.5, 0.6, 1.2), (0, -0.05, 0.6), "leather_black", "case")
		kit.box((1.3, 0.2, 0.03), (0, 0.33, 0.72), "paint_white", "keys")
		kit.box((0.6, 0.35, 0.05), (0, 0.75, 0.48), "leather_black", "stool")
	elif what == "plant_pot":
		kit.lathe([(0.12, 0), (0.17, 0.3), (0.15, 0.3)], slot="clay_tile", name="pot", segs=16)
		kit.cyl(0.02, 0.5, (0, 0, 0.55), "bark", "stem", segs=8)
		for i in range(5):
			a = math.radians(72 * i)
			kit.sphere(0.16, (0.12 * math.cos(a), 0.12 * math.sin(a), 0.85 + 0.06 * (i % 2)), "foliage", "leaves", segs=10)
	elif what == "coat_stand":
		kit.cyl(0.02, 1.7, (0, 0, 0.85), "hardwood", "pole", segs=10)
		for a in range(4):
			c, s = math.cos(math.radians(90 * a)), math.sin(math.radians(90 * a))
			kit.rod((0, 0, 0.1), (0.25 * c, 0.25 * s, 0), 0.014, "hardwood", "foot")
			kit.rod((0, 0, 1.55), (0.14 * c, 0.14 * s, 1.68), 0.01, "hardwood", "hook")
	elif what == "shoe_rack":
		for z in (0.1, 0.35, 0.6):
			for y in (-0.1, 0.1):
				kit.rod((-0.4, y, z), (0.4, y, z), 0.008, "steel_stainless", "rail")
		for s in (-1, 1):
			kit.box((0.02, 0.3, 0.7), (s * 0.4, 0, 0.35), "hardwood", "end")
	elif what == "ironing_board":
		kit.rounded_box((0.38, 1.25, 0.03), (0, 0, 0.9), "fabric_blue", "board", radius=0.012)
		kit.strut((0, -0.45, 0), (0, 0.35, 0.88), 0.025, slot="steel_stainless", name="leg")
		kit.strut((0, 0.45, 0), (0, -0.35, 0.88), 0.025, slot="steel_stainless", name="leg")
	elif what == "wheelie_bin":
		kit.prism([(-0.24, 0), (0.24, 0), (0.29, 0.95), (-0.29, 0.95)], 0.6, (0, 0, 0), "plastic_green", "body", axis="y")
		kit.box((0.6, 0.72, 0.05), (0, 0.03, 0.98), "plastic_green", "lid")
		for s in (-1, 1):
			kit.cyl(0.1, 0.04, (s * 0.26, -0.3, 0.1), "rubber", "wheel", axis="x", segs=16)
	elif what == "garden_shed":
		with kit.hollow(0.05):
			kit.box((2.4, 1.8, 1.9), (0, 0, 0.95), "softwood", "walls")
		for s in (-1, 1):
			kit.strut((s * 1.3, 0, 1.85), (0, 0, 2.3), 0.03, 2.0, "roof_felt", "roof")
		kit.box((0.8, 0.03, 1.7), (-0.5, 0.9, 0.87), "softwood", "door")
		kit.box((0.6, 0.02, 0.5), (0.6, 0.9, 1.3), "glass", "window")
	elif what == "washing_line":
		kit.cyl(0.02, 1.9, (0, 0, 0.95), "aluminium", "pole", segs=10)
		for a in range(4):
			c, s = math.cos(math.radians(90 * a)), math.sin(math.radians(90 * a))
			kit.rod((0, 0, 1.4), (1.1 * c, 1.1 * s, 1.85), 0.01, "aluminium", "arm")
	elif what == "bbq":
		kit.lathe([(0.0, 0.55), (0.25, 0.65), (0.28, 0.8), (0.25, 0.95), (0.0, 1.05)], slot="leather_black", name="kettle", segs=20)
		for a in range(3):
			c, s = math.cos(math.radians(120 * a)), math.sin(math.radians(120 * a))
			kit.rod((0.15 * c, 0.15 * s, 0.6), (0.3 * c, 0.3 * s, 0), 0.01, "steel_stainless", "leg")
	elif what == "garden_bench":
		kit.box((1.5, 0.45, 0.04), (0, 0, 0.43), "hardwood", "seat")
		kit.box((1.5, 0.04, 0.4), (0, -0.22, 0.7), "hardwood", "back")
		for s in (-1, 1):
			kit.box((0.06, 0.55, 0.62), (s * 0.72, 0, 0.31), "hardwood", "end")
	elif what == "bicycle":
		for y in (-0.52, 0.52):
			kit.tube(0.33, 0.03, (0, y, 0.33), "rubber", "wheel", axis="x", wall=0.025, segs=24)
		for a, b in (((0, -0.52, 0.33), (0, -0.1, 0.3)), ((0, -0.1, 0.3), (0, -0.2, 0.85)), ((0, -0.2, 0.85), (0, 0.4, 0.85)), ((0, 0.4, 0.85), (0, 0.52, 0.33)), ((0, 0.4, 0.85), (0, -0.1, 0.3)), ((0, -0.52, 0.33), (0, -0.2, 0.85)), ((0, 0.4, 0.85), (0, 0.38, 1.0))):
			kit.rod(a, b, 0.014, "plastic_blue", "frame", segs=8)
		kit.rod((-0.25, 0.38, 1.0), (0.25, 0.38, 1.0), 0.012, "steel_stainless", "handlebar")
		kit.rounded_box((0.14, 0.26, 0.05), (0, -0.22, 0.9), "leather_black", "saddle", radius=0.02)
	elif what == "car_charger":
		kit.rounded_box((0.25, 0.12, 0.4), (0, 0.06, 1.2), "plastic_white", "unit", radius=0.03)
		kit.sweep([(0, 0.12, 1.05), (0.1, 0.16, 0.8), (0.12, 0.14, 1.1), (0.14, 0.1, 1.25)], kit.circle(0.01, 8), "plastic_black", "cable", up=(0, 1, 0))


for _k, _l, _tags in (("vanity", "Vanity unit with basin", ("home", "bathroom")), ("mirror_cabinet", "Mirror cabinet", ("home", "bathroom")), ("mirror", "Full-length mirror", ("home", "bedroom")),
		("bidet", "Bidet", ("home", "bathroom")), ("urinal", "Urinal", ("school", "office", "toilets")), ("accessible_wc", "Accessible WC with grab rails", ("hospital", "school", "toilets")),
		("bathroom_radiator_shelf", "Glass shelf", ("home", "bathroom")), ("bunk_bed", "Bunk bed", ("home", "bedroom")), ("cot", "Cot", ("home", "bedroom")),
		("dressing_table", "Dressing table", ("home", "bedroom")), ("rug", "Rug, 2 m", ("home", "living")), ("floor_lamp", "Floor lamp", ("home", "living")),
		("desk_lamp", "Desk lamp", ("home", "office")), ("curtains", "Curtains on a pole", ("home",)), ("blind", "Roller blind", ("home", "office")),
		("fireplace", "Fireplace", ("home", "living")), ("wood_stove", "Wood-burning stove", ("home", "living")), ("piano", "Upright piano", ("home", "school")),
		("plant_pot", "Potted plant", ("home", "office")), ("coat_stand", "Coat stand", ("home", "office")), ("shoe_rack", "Shoe rack", ("home", "hall")),
		("ironing_board", "Ironing board", ("home", "utility")), ("wheelie_bin", "Wheelie bin", ("home", "outdoor")), ("garden_shed", "Garden shed", ("home", "outdoor")),
		("washing_line", "Rotary washing line", ("home", "outdoor")), ("bbq", "Kettle barbecue", ("home", "outdoor")), ("garden_bench", "Garden bench", ("home", "outdoor")),
		("bicycle", "Bicycle", ("home", "outdoor")), ("car_charger", "Car charging point", ("home", "garage"))):
	reg("furniture.home." + _k, home, _l, *_tags, what=_k)
