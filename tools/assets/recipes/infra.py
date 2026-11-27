"""Industrial and warehouse equipment, and infrastructure: roads, rail, bridges, energy and
water. Origin: ground centre. Linear items are 1 m models running along Y (game z) unless
noted, scaled by length."""
import math

import kit
from registry import register


def reg(id, fn, label, *tags, **params):
	register(id, fn, label, family=id.split(".")[0], tags=(id.split(".")[0],) + tags, **params)


def per_m(id, fn, label, *tags, **params):
	register(id, fn, label, family=id.split(".")[0], tags=(id.split(".")[0],) + tags, stretch="z", **params)


# --- industrial ----------------------------------------------------------------------------

def racking(bays=1, h=6.0, levels=3, loaded=True, w=2.7, d=1.1):
	for i in range(bays + 1):
		x = -bays * w / 2 + i * w
		for s in (-1, 1):
			kit.box((0.1, 0.07, h), (x, s * (d / 2 - 0.035), h / 2), "plastic_blue", "upright")
		for j in range(int(h / 1.2)):
			kit.rod((x, -d / 2 + 0.05, 0.3 + j * 1.2), (x, d / 2 - 0.05, 0.3 + j * 1.2 + (0.6 if j % 2 else -0.0)), 0.015, "plastic_blue", "brace", segs=5)
	for b in range(bays):
		x = -bays * w / 2 + (b + 0.5) * w
		for lv in range(1, levels + 1):
			z = lv * (h - 0.6) / levels
			for s in (-1, 1):
				kit.box((w - 0.1, 0.05, 0.12), (x, s * (d / 2 - 0.035), z), "hivis_orange", "beam")
			if loaded:
				for k in (-1, 1):
					kit.box((1.2, 1.0, 0.12), (x + k * 0.66, 0, z + 0.12), "softwood", "pallet")
					kit.box((1.1, 0.95, 0.9 if (b + lv + k) % 3 else 0.6), (x + k * 0.66, 0, z + 0.18 + (0.45 if (b + lv + k) % 3 else 0.3)), ("plywood", "fabric_white", "plastic_blue")[(b + lv) % 3], "load")


def industrial(what="conveyor"):
	if what == "conveyor":
		kit.box((0.6, 1.0, 0.04), (0, 0, 0.8), "rubber", "belt")
		for s in (-1, 1):
			kit.box((0.04, 1.0, 0.12), (s * 0.32, 0, 0.78), "steel_galvanised", "side")
		for i in range(5):
			kit.cyl(0.025, 0.6, (0, -0.4 + i * 0.2, 0.76), "steel_galvanised", "roller", axis="x", segs=8)
	elif what == "conveyor_leg":
		for s in (-1, 1):
			kit.box((0.05, 0.05, 0.75), (s * 0.32, 0, 0.375), "steel_galvanised", "leg")
		kit.box((0.64, 0.04, 0.04), (0, 0, 0.3), "steel_galvanised", "tie")
	elif what == "mezzanine":
		for x in (-3, 3):
			for y in (-3, 3):
				kit.box((0.15, 0.15, 3.0), (x, y, 1.5), "steel_painted", "column")
		for y in (-3, 3):
			kit.i_section(0.15, 0.3, 0.012, 0.008, 6.3, (0, y, 3.0), "steel_painted", "beam", axis="x")
		for i in range(7):
			kit.i_section(0.1, 0.2, 0.01, 0.006, 6.0, (-3 + i, 0, 3.2), "steel_galvanised", "joist", axis="y")
		kit.box((6.3, 6.3, 0.04), (0, 0, 3.32), "plywood", "deck")
		for z in (3.9, 4.4):
			kit.sweep([(-3.1, -3.1, z), (3.1, -3.1, z), (3.1, 3.1, z), (-3.1, 3.1, z), (-3.1, -3.1, z)], kit.circle(0.02, 6), "plant_yellow", "handrail")
	elif what == "workbench":
		kit.box((1.8, 0.75, 0.05), (0, 0, 0.875), "hardwood", "top")
		for s in (-1, 1):
			kit.box((0.05, 0.7, 0.85), (s * 0.85, 0, 0.425), "plastic_blue", "leg_frame")
		kit.box((1.8, 0.03, 0.8), (0, -0.36, 1.3), "plastic_blue", "tool_board")
		kit.box((0.2, 0.25, 0.2), (0.6, 0.2, 1.0), "cast_iron", "vice")
	elif what in ("lathe", "mill", "cnc", "press", "saw_bench", "pillar_drill", "injection"):
		if what == "lathe":
			kit.box((2.2, 0.6, 0.8), (0, 0, 0.4), "plastic_grey", "bed_base")
			kit.box((0.5, 0.5, 0.45), (-0.8, 0, 1.03), "plastic_grey", "headstock")
			kit.cyl(0.12, 0.12, (-0.5, 0, 1.05), "steel_stainless", "chuck", axis="x", segs=16)
			kit.box((1.5, 0.3, 0.08), (0.2, 0, 0.84), "steel_stainless", "ways")
			kit.box((0.3, 0.4, 0.2), (0.2, 0, 0.98), "plastic_grey", "carriage")
			kit.box((0.25, 0.25, 0.3), (0.95, 0, 1.0), "plastic_grey", "tailstock")
		elif what == "mill":
			kit.box((0.7, 0.9, 0.7), (0, 0, 0.35), "plastic_grey", "base")
			kit.box((0.4, 0.5, 1.4), (0, -0.25, 1.4), "plastic_grey", "column")
			kit.box((1.2, 0.35, 0.08), (0, 0.2, 0.95), "steel_stainless", "table")
			kit.box((0.35, 0.6, 0.4), (0, 0.1, 1.9), "plastic_grey", "head")
			kit.cyl(0.04, 0.3, (0, 0.25, 1.55), "steel_stainless", "spindle", segs=10)
		elif what == "cnc":
			with kit.hollow(0.3):
				kit.rounded_box((2.6, 1.8, 2.1), (0, 0, 1.05), "paint_white", "enclosure", radius=0.06)
			kit.box((1.2, 0.02, 1.0), (-0.3, 0.9, 1.2), "glass", "door")
			kit.box((0.4, 0.1, 0.5), (0.95, 0.92, 1.4), "plastic_black", "control")
			kit.box((0.34, 0.004, 0.25), (0.95, 0.972, 1.5), "screen", "screen")
		elif what == "press":
			for s in (-1, 1):
				kit.box((0.3, 0.6, 2.4), (s * 0.6, 0, 1.2), "plastic_green", "frame")
			kit.box((1.5, 0.6, 0.5), (0, 0, 2.3), "plastic_green", "crown")
			kit.box((0.9, 0.6, 0.7), (0, 0, 0.35), "plastic_green", "bed")
			kit.cyl(0.15, 0.8, (0, 0, 1.7), "steel_stainless", "ram", segs=14)
		elif what == "saw_bench":
			kit.box((1.2, 2.4, 0.04), (0, 0, 0.88), "steel_stainless", "table")
			kit.box((0.9, 0.9, 0.86), (0, 0, 0.43), "plastic_green", "cabinet")
			kit.cyl(0.18, 0.004, (0, 0, 0.92), "steel_stainless", "blade", axis="x", segs=24)
			kit.box((0.06, 2.4, 0.1), (0.4, 0, 0.95), "aluminium", "fence")
		elif what == "pillar_drill":
			kit.box((0.4, 0.6, 0.06), (0, 0, 0.03), "cast_iron", "base")
			kit.cyl(0.04, 1.6, (0, -0.2, 0.8), "steel_stainless", "column", segs=10)
			kit.box((0.25, 0.5, 0.3), (0, 0, 1.6), "plastic_green", "head")
			kit.box((0.3, 0.3, 0.03), (0, 0.05, 1.0), "cast_iron", "table")
			kit.cyl(0.015, 0.2, (0, 0.1, 1.38), "steel_stainless", "chuck", segs=8)
		else:
			kit.box((4.5, 1.2, 0.9), (0, 0, 0.45), "plastic_green", "base")
			kit.box((1.6, 1.0, 0.9), (-1.2, 0, 1.35), "paint_white", "clamp_unit")
			kit.cyl(0.15, 2.0, (0.9, 0, 1.2), "steel_stainless", "barrel", axis="x", segs=14)
			kit.lathe([(0.1, 0), (0.3, 0.5)], (0.8, 0, 1.4), "steel_stainless", "hopper", segs=12)
	elif what in ("tank_vertical", "tank_horizontal", "silo_grain"):
		with kit.hollow(0.03):
			if what == "tank_vertical":
				kit.lathe([(1.5, 0), (1.5, 5.5), (0.2, 6.0)], (0, 0, 0.2), "steel_stainless", "tank", segs=24)
				kit.cyl(1.7, 0.2, (0, 0, 0.1), "concrete", "plinth", segs=24)
			elif what == "tank_horizontal":
				kit.lathe([(0.6, 0), (1.2, 0.3), (1.2, 5.7), (0.6, 6.0)], (0, -3.0, 1.7), "paint_white", "tank", segs=24, rot=(-90, 0, 0))
				for y in (-1.8, 1.8):
					kit.box((2.0, 0.4, 0.9), (0, y, 0.45), "concrete", "saddle")
			else:
				kit.lathe([(0.3, 2.0), (3.0, 4.5), (3.0, 14.0), (0.3, 16.0)], (0, 0, 0), "steel_galvanised", "silo", segs=24)
				for i in range(6):
					a = math.radians(60 * i)
					kit.rod((2.9 * math.cos(a), 2.9 * math.sin(a), 0), (2.9 * math.cos(a), 2.9 * math.sin(a), 4.5), 0.1, "steel_galvanised", "leg")
		kit.rod((1.55 if what == "tank_vertical" else 1.25, 0, 0), (1.55 if what == "tank_vertical" else 1.25, 0, 6.0 if what != "silo_grain" else 15.0), 0.03, "steel_galvanised", "ladder_rail") if what != "tank_horizontal" else None
	elif what == "chimney_stack":
		with kit.hollow(0.1):
			kit.lathe([(1.6, 0), (1.0, 40.0), (1.1, 40.0), (1.1, 40.5), (1.0, 40.5)], (0, 0, 0), "concrete", "stack", segs=20)
		for z in (38.0, 39.0):
			kit.cyl(1.06, 0.5, (0, 0, z), "hazard_red", "band", segs=20)
	elif what == "cooling_tower":
		with kit.hollow(0.05):
			kit.box((6.0, 6.0, 4.0), (0, 0, 2.5), "steel_galvanised", "casing")
		kit.cyl(2.2, 1.2, (0, 0, 5.1), "steel_galvanised", "fan_stack", segs=24)
		for s in (-1, 1):
			for i in range(8):
				kit.box((5.6, 0.05, 0.25), (0, s * 3.02, 1.0 + i * 0.4), "plastic_grey", "louvre", rot=(s * 30, 0, 0))
		kit.box((6.2, 6.2, 0.5), (0, 0, 0.25), "concrete", "basin")
	elif what == "gantry_crane":
		for y in (-6, 6):
			kit.i_section(0.3, 0.6, 0.02, 0.012, 20.0, (0, y, 7.0), "plant_yellow", "runway", axis="x")
		kit.i_section(0.4, 1.0, 0.025, 0.015, 12.4, (2.0, 0, 7.8), "plant_yellow", "bridge", axis="y")
		kit.box((0.8, 1.0, 0.6), (2.0, 1.5, 7.2), "plant_yellow", "hoist")
		kit.rod((2.0, 1.5, 6.9), (2.0, 1.5, 3.5), 0.012, "steel_galvanised", "rope", segs=5)
		kit.box((0.3, 0.2, 0.5), (2.0, 1.5, 3.3), "hazard_red", "hook_block")
	elif what == "jib_crane":
		kit.cyl(0.15, 4.0, (0, 0, 2.0), "plant_yellow", "column", segs=14)
		kit.i_section(0.15, 0.3, 0.012, 0.008, 4.0, (0, 2.0, 4.0), "plant_yellow", "jib", axis="y")
		kit.rod((0, 0, 4.6), (0, 3.6, 4.15), 0.02, "plant_yellow", "tie")
		kit.box((0.3, 0.3, 0.3), (0, 3.0, 3.7), "plant_yellow", "hoist")
	elif what == "dock_leveller":
		kit.box((2.0, 2.5, 0.08), (0, 0, 1.2), "steel_galvanised", "deck")
		kit.box((2.0, 0.4, 0.02), (0, 1.45, 1.17), "steel_galvanised", "lip", rot=(-8, 0, 0))
		kit.box((2.2, 2.6, 1.15), (0, 0, 0.575), "concrete", "pit")
	elif what == "column_guard":
		kit.sweep([(-0.4, -0.4, 0), (-0.4, -0.4, 0.5), (0.4, -0.4, 0.5), (0.4, -0.4, 0)], kit.circle(0.045, 8), "plant_yellow", "hoop", up=(0, 1, 0))
		kit.sweep([(-0.4, 0.4, 0), (-0.4, 0.4, 0.5), (0.4, 0.4, 0.5), (0.4, 0.4, 0)], kit.circle(0.045, 8), "plant_yellow", "hoop", up=(0, 1, 0))
	elif what == "pallet_truck":
		for s in (-1, 1):
			kit.box((0.16, 1.15, 0.05), (s * 0.2, 0.1, 0.08), "hazard_red", "fork")
		kit.box((0.5, 0.2, 0.35), (0, -0.55, 0.22), "hazard_red", "pump")
		kit.rod((0, -0.6, 0.35), (0, -0.9, 1.15), 0.02, "plastic_black", "tiller")
		kit.rod((-0.15, -0.9, 1.15), (0.15, -0.9, 1.15), 0.015, "plastic_black", "handle")
	elif what == "ibc":
		with kit.hollow(0.05):
			kit.rounded_box((1.0, 1.2, 1.0), (0, 0, 0.65), "plastic_white", "tank", radius=0.06)
		kit.grid_bars(1.0, 1.0, (0, 0.6, 0.65), 6, 4, 0.008, "steel_galvanised", "cage")
		kit.grid_bars(1.0, 1.0, (0, -0.6, 0.65), 6, 4, 0.008, "steel_galvanised", "cage")
		kit.box((1.0, 1.2, 0.14), (0, 0, 0.07), "softwood", "pallet")
	elif what == "drums":
		for i in range(4):
			kit.cyl(0.29, 0.88, ((i % 2) * 0.6 - 0.3, (i // 2) * 0.6 - 0.3, 0.58), ("plastic_blue", "hazard_red")[i % 2], "drum", segs=16)
		kit.box((1.2, 1.2, 0.14), (0, 0, 0.07), "softwood", "pallet")
	elif what == "bund":
		for s in (-1, 1):
			kit.box((6.0, 0.2, 0.8), (0, s * 2.9, 0.4), "concrete", "bund_wall")
			kit.box((0.2, 6.0, 0.8), (s * 2.9, 0, 0.4), "concrete", "bund_wall")
		kit.box((6.0, 6.0, 0.15), (0, 0, 0.075), "concrete", "slab")
	elif what == "pipe_rack":
		for y in (-3, 3):
			for s in (-1, 1):
				kit.i_section(0.2, 0.2, 0.012, 0.008, 5.0, (s * 1.5, y, 2.5), "steel_galvanised", "column", axis="z")
			for z in (3.5, 4.9):
				kit.i_section(0.15, 0.2, 0.01, 0.007, 3.2, (0, y, z), "steel_galvanised", "beam", axis="x")
		for i, c in enumerate(("steel_stainless", "plastic_yellow", "insulation", "steel_painted", "copper")):
			kit.cyl(0.08 + 0.03 * (i % 3), 7.0, (-1.2 + i * 0.6, 0, 3.75 if i % 2 else 5.15), c, "pipe", axis="y", segs=12)
	elif what == "dust_extractor":
		with kit.hollow(0.05):
			kit.lathe([(0.15, 1.2), (0.8, 2.4), (0.8, 4.5), (0.3, 4.9)], (0, 0, 0), "steel_galvanised", "cyclone", segs=18)
		for i in range(3):
			a = math.radians(120 * i)
			kit.rod((0.8 * math.cos(a), 0.8 * math.sin(a), 0), (0.75 * math.cos(a), 0.75 * math.sin(a), 2.4), 0.05, "steel_galvanised", "leg")
		kit.cyl(0.3, 0.8, (0, 0, 0.5), "plastic_blue", "bin", segs=14)
	elif what == "paint_booth":
		with kit.hollow(0.03):
			kit.box((4.0, 7.0, 3.0), (0, 0, 1.5), "paint_white", "booth")
		kit.box((3.0, 0.05, 2.6), (0, 3.5, 1.3), "glass", "doors")
		kit.box((1.2, 1.2, 1.5), (0, -1.0, 3.75), "steel_galvanised", "extract")
	elif what == "weighbridge":
		kit.box((3.0, 18.0, 0.4), (0, 0, 0.2), "concrete", "deck")
		for s in (-1, 1):
			kit.prism([(-3.0, 0), (0, 0), (0, 0.4)], 3.0, (0, s * 9.0 + (3.0 if s > 0 else 0), 0), "concrete", "approach", axis="x", rot=(0, 0, 0 if s < 0 else 180))
			kit.box((0.1, 18.0, 0.1), (s * 1.45, 0, 0.6), "plant_yellow", "guide_rail")


_RACK = (("bay_1", "Pallet racking, one bay, 6 m", dict()), ("bay_3", "Pallet racking, three bays, 6 m", dict(bays=3)), ("bay_6", "Pallet racking, six bays, 9 m", dict(bays=6, h=9.0, levels=5)),
	("empty_1", "Pallet racking, one bay, empty", dict(loaded=False)), ("empty_3", "Pallet racking, three bays, empty", dict(bays=3, loaded=False)), ("high_bay", "High-bay racking, three bays, 15 m", dict(bays=3, h=15.0, levels=8)),
	("shelving", "Longspan shelving bay", dict(h=2.4, levels=4, w=1.8, d=0.6, loaded=False)), ("shelving_3", "Longspan shelving, three bays", dict(bays=3, h=2.4, levels=4, w=1.8, d=0.6, loaded=False)))
for _n, _l, _kw in _RACK:
	reg("industrial.racking." + _n, racking, _l, "warehouse", **_kw)
_IND = (("handling.mezzanine", "mezzanine", "Mezzanine floor, 6 m square"), ("handling.conveyor_leg", "conveyor_leg", "Conveyor stand"), ("handling.gantry_crane", "gantry_crane", "Overhead travelling crane, 12 m span"),
	("handling.jib_crane", "jib_crane", "Pillar jib crane"), ("handling.dock_leveller", "dock_leveller", "Dock leveller in pit"), ("handling.column_guard", "column_guard", "Column guard hoops"),
	("handling.pallet_truck", "pallet_truck", "Pallet truck"), ("handling.weighbridge", "weighbridge", "Weighbridge"),
	("machine.workbench", "workbench", "Workbench with tool board"), ("machine.lathe", "lathe", "Lathe"), ("machine.mill", "mill", "Milling machine"), ("machine.cnc", "cnc", "CNC machining centre"), ("machine.press", "press", "Hydraulic press"),
	("machine.saw_bench", "saw_bench", "Panel saw bench"), ("machine.pillar_drill", "pillar_drill", "Pillar drill"), ("machine.injection_moulder", "injection", "Injection moulding machine"), ("machine.dust_extractor", "dust_extractor", "Dust extractor cyclone"),
	("machine.paint_booth", "paint_booth", "Spray booth"),
	("process.tank_vertical", "tank_vertical", "Process tank, vertical"), ("process.tank_horizontal", "tank_horizontal", "Storage tank, horizontal"), ("process.grain_silo", "silo_grain", "Storage silo, 16 m"),
	("process.chimney_stack", "chimney_stack", "Chimney stack, 40 m"), ("process.cooling_tower", "cooling_tower", "Cooling tower cell"), ("process.ibc", "ibc", "IBC container"), ("process.drums", "drums", "Drums on pallet"),
	("process.bund", "bund", "Bund wall and slab, 6 m"), ("process.pipe_rack", "pipe_rack", "Pipe rack bay"))
for _id, _w, _l in _IND:
	reg("industrial." + _id, industrial, _l, what=_w)
per_m("industrial.handling.conveyor", industrial, "Belt conveyor, per metre", what="conveyor")


# --- roads, rail, bridges, energy, water ---------------------------------------------------

def road(what="carriageway", w=7.3):
	if what == "carriageway":
		kit.box((w, 1.0, 0.15), (0, 0, -0.075), "asphalt", "surface")
	elif what == "carriageway_marked":
		kit.box((w, 1.0, 0.15), (0, 0, -0.075), "asphalt", "surface")
		kit.box((0.1, 0.5, 0.004), (0, 0, 0.002), "paint_white", "centre_line")
		for s in (-1, 1):
			kit.box((0.1, 1.0, 0.004), (s * (w / 2 - 0.2), 0, 0.002), "paint_white", "edge_line")
	elif what == "pavement":
		kit.box((w, 1.0, 0.2), (0, 0, -0.025), "paving", "footway")
	elif what == "cycle_lane":
		kit.box((w, 1.0, 0.15), (0, 0, -0.075), "plastic_green", "surface")
	elif what == "verge":
		kit.box((w, 1.0, 0.2), (0, 0, -0.04), "foliage", "grass")
	elif what == "gravel":
		kit.box((w, 1.0, 0.12), (0, 0, -0.06), "concrete", "gravel")
	elif what == "crossing":
		kit.box((w, 4.0, 0.15), (0, 0, -0.075), "asphalt", "surface")
		for i in range(int(w / 1.2)):
			kit.box((0.6, 2.8, 0.004), (-w / 2 + 0.6 + i * 1.2, 0, 0.002), "paint_white", "stripe")
		for s in (-1, 1):
			kit.cyl(0.04, 2.6, (s * (w / 2 + 0.4), 1.8 * s, 1.3), "plastic_black", "beacon_post", segs=8)
			kit.sphere(0.15, (s * (w / 2 + 0.4), 1.8 * s, 2.7), "plastic_yellow", "beacon", segs=12)
	elif what == "speed_hump":
		kit.prism([(-1.8, 0), (-0.8, 0.075), (0.8, 0.075), (1.8, 0)], w, (0, 0, 0), "asphalt", "hump", axis="x")
	elif what == "roundabout":
		kit.cyl(w, 0.15, (0, 0, -0.075), "asphalt", "circulatory", segs=40)
		kit.cyl(w * 0.45, 0.25, (0, 0, 0.125), "foliage", "island", segs=32)
		kit.tube(w * 0.47, 0.14, (0, 0, 0.07), "concrete", "kerb", wall=0.12, segs=32)
	elif what == "parking_bay":
		kit.box((2.4, 4.8, 0.12), (0, 0, -0.06), "asphalt", "surface")
		for s in (-1, 1):
			kit.box((0.1, 4.8, 0.004), (s * 1.2, 0, 0.002), "paint_white", "line")
	elif what == "parking_accessible":
		kit.box((3.6, 6.0, 0.12), (0, 0, -0.06), "asphalt", "surface")
		kit.box((2.4, 4.8, 0.004), (-0.6, -0.6, 0.002), "plastic_blue", "bay")
		kit.box((1.2, 6.0, 0.004), (1.2, 0, 0.003), "plastic_yellow", "transfer_zone")
	elif what == "island":
		kit.rounded_box((1.8, 6.0, 0.15), (0, 0, 0.075), "concrete", "island", radius=0.07)
		for y in (-2.5, 2.5):
			kit.cyl(0.07, 1.0, (0, y, 0.65), "paint_white", "bollard", segs=10)
			kit.cyl(0.075, 0.25, (0, y, 0.9), "plastic_blue", "sign", segs=10)
	elif what == "gantry_sign":
		for s in (-1, 1):
			kit.lattice(7.0, 0.6, 0.06, 0.03, at=(s * (w / 2 + 1.0), 0, 0), bays=8, slot="steel_galvanised", name="leg")
		kit.box((w + 2.6, 0.6, 0.8), (0, 0, 7.0), "steel_galvanised", "boom")
		for s in (-1, 1):
			kit.box((w / 2 - 0.5, 0.1, 2.0), (s * w / 4, 0.35, 7.0), "plastic_blue", "sign")
			kit.box((w / 2 - 1.0, 0.11, 0.4), (s * w / 4, 0.36, 7.3), "paint_white", "legend")


def rail(what="track"):
	if what in ("track", "track_slab"):
		if what == "track":
			kit.prism([(-2.2, 0), (2.2, 0), (1.5, 0.35), (-1.5, 0.35)], 1.0, (0, 0, 0), "concrete", "ballast", axis="y")
			kit.box((2.6, 0.26, 0.2), (0, 0, 0.42), "concrete", "sleeper")
		else:
			kit.box((2.8, 1.0, 0.45), (0, 0, 0.225), "concrete", "slab")
		for s in (-1, 1):
			kit.prism([(-0.07, 0), (0.07, 0), (0.07, 0.02), (0.01, 0.04), (0.01, 0.13), (0.036, 0.13), (0.036, 0.17), (-0.036, 0.17), (-0.036, 0.13), (-0.01, 0.13), (-0.01, 0.04), (-0.07, 0.02)], 1.0, (s * 0.7535, 0, 0.5 if what == "track" else 0.45), "steel_painted", "rail", axis="y")
	elif what == "platform":
		kit.box((4.0, 1.0, 0.915), (0, 0, 0.4575), "concrete", "platform")
		kit.box((0.4, 1.0, 0.01), (1.3, 0, 0.92), "plastic_yellow", "tactile_strip")
		kit.box((0.3, 1.0, 0.08), (1.9, 0, 0.88), "paving", "coping")
	elif what == "ole_mast":
		kit.i_section(0.2, 0.25, 0.012, 0.008, 7.0, (-2.8, 0, 3.5), "steel_galvanised", "mast", axis="z")
		kit.rod((-2.8, 0, 6.2), (0, 0, 5.6), 0.025, "steel_galvanised", "cantilever")
		kit.rod((-2.8, 0, 5.0), (0, 0, 5.1), 0.02, "steel_galvanised", "registration_arm")
		kit.cyl(0.05, 0.4, (-2.4, 0, 6.1), "ceramic", "insulator", axis="x", segs=10)
	elif what == "ole_wire":
		kit.cyl(0.006, 1.0, (0, 0, 5.1), "copper", "contact_wire", axis="y", segs=5)
		kit.cyl(0.006, 1.0, (0, 0, 5.9), "copper", "catenary", axis="y", segs=5)
	elif what == "signal":
		kit.cyl(0.06, 4.5, (0, 0, 2.25), "steel_galvanised", "post", segs=10)
		kit.rounded_box((0.35, 0.2, 1.1), (0, 0.1, 4.2), "plastic_black", "head", radius=0.03)
		for i, c in enumerate(("plastic_green", "plastic_yellow", "hazard_red", "plastic_yellow")):
			kit.cyl(0.08, 0.03, (0, 0.21, 4.6 - i * 0.26), c, "aspect", axis="y", segs=12)
		for i in range(8):
			kit.rod((-0.15, -0.1, 0.5 + i * 0.4), (0.15, -0.1, 0.5 + i * 0.4), 0.008, "steel_galvanised", "rung", segs=5)
	elif what == "buffer":
		for s in (-1, 1):
			kit.strut((s * 0.75, -1.2, 0.5), (s * 0.75, 0, 1.4), 0.12, 0.15, "hazard_red", "raker")
			kit.box((0.12, 0.15, 1.0), (s * 0.75, 0, 1.0), "hazard_red", "post")
		kit.box((2.4, 0.2, 0.3), (0, 0.1, 1.4), "hazard_red", "beam")
		kit.box((0.3, 0.05, 0.3), (0, 0.22, 1.9), "light_emitter", "lamp")
	elif what == "level_crossing":
		kit.box((0.3, 0.3, 1.0), (0, 0, 0.5), "paint_white", "pedestal")
		kit.box((4.5, 0.08, 0.12), (2.2, 0.2, 0.95), "paint_white", "boom")
		for i in range(5):
			kit.box((0.4, 0.082, 0.122), (0.6 + i * 0.9, 0.2, 0.95), "hazard_red", "stripe")
		kit.cyl(0.05, 3.5, (-0.6, 0, 1.75), "paint_white", "light_post", segs=8)
		kit.box((0.9, 0.05, 0.5), (-0.6, 0.05, 3.0), "plastic_black", "backboard")
		for s in (-1, 1):
			kit.cyl(0.1, 0.03, (-0.6 + s * 0.22, 0.09, 3.0), "hazard_red", "lamp", axis="y", segs=12)
	elif what in ("carriage", "loco", "tram", "wagon"):
		l = {"carriage": 23.0, "loco": 20.0, "tram": 30.0, "wagon": 14.0}[what]
		if what == "wagon":
			kit.box((2.6, l, 0.3), (0, 0, 1.15), "steel_painted", "underframe")
			with kit.hollow(0.05):
				kit.box((2.6, l - 0.6, 1.6), (0, 0, 2.1), "plastic_blue", "box")
		else:
			with kit.hollow(0.06):
				kit.rounded_box((2.7, l, 2.7), (0, 0, 2.45), "paint_white" if what != "loco" else "hazard_red", "body", radius=0.25)
			kit.box((2.72, l - (2.0 if what != "loco" else 16.0), 0.8), (0, 0 if what != "loco" else l / 2 - 2.0, 2.9), "glass", "windows")
			kit.box((2.72, l - 1.0, 0.25), (0, 0, 1.6), "plastic_blue" if what != "loco" else "plastic_yellow", "stripe")
			if what != "tram":
				for y in (-l / 4, l / 4):
					for s in (-1, 1):
						kit.box((0.02, 1.2, 1.9), (s * 1.36, y, 2.2), "plastic_yellow" if what == "carriage" else "plastic_grey", "door")
			else:
				kit.rod((0, 0, 3.8), (0, 1.5, 4.9), 0.03, "steel_stainless", "pantograph")
				kit.rod((-0.6, 1.5, 4.9), (0.6, 1.5, 4.9), 0.02, "steel_stainless", "pan_head")
		for y in ((-l / 2 + 2.5, l / 2 - 2.5) if what != "tram" else (-l / 2 + 3, -l / 6, l / 6, l / 2 - 3)):
			kit.box((2.2, 3.0 if what != "tram" else 1.8, 0.5), (0, y, 0.75), "plastic_black", "bogie")
			for dy in (-0.9, 0.9) if what != "tram" else (-0.5, 0.5):
				for s in (-1, 1):
					kit.cyl(0.46 if what != "tram" else 0.33, 0.13, (s * 0.7535, y + dy, 0.46 if what != "tram" else 0.33), "steel_painted", "wheel", axis="x", segs=18)
	elif what == "shelter":
		for x in (-2.5, 2.5):
			kit.box((0.12, 0.12, 2.6), (x, -0.6, 1.3), "steel_painted", "column")
		kit.box((6.0, 2.4, 0.08), (0, 0.2, 2.65), "steel_galvanised", "roof", rot=(4, 0, 0))
		kit.box((5.0, 0.012, 1.8), (0, -0.6, 1.2), "glass", "screen")
		kit.box((3.0, 0.4, 0.05), (0, -0.3, 0.45), "steel_stainless", "bench")
	elif what == "ticket_gate":
		for i in range(4):
			kit.rounded_box((0.3, 1.6, 1.0), ((i - 1.5) * 0.9, 0, 0.5), "steel_stainless", "pedestal", radius=0.04)
		for i in range(3):
			for s in (-1, 1):
				kit.prism([(0, 0.3), (0.28, 0.5), (0.28, 0.9), (0, 0.95)], 0.03, ((i - 1) * 0.9 + s * 0.3 - (0.28 if s > 0 else 0), 0, 0), "hazard_red", "paddle", axis="y", rot=(0, 0, 0))


def bridge(what="beam", span=20.0):
	if what == "beam":
		kit.i_section(0.6, 1.4, 0.2, 0.2, span, (0, 0, 0.7), "concrete", "beam", axis="y")
	elif what == "steel_girder":
		kit.i_section(0.6, 1.8, 0.04, 0.02, span, (0, 0, 0.9), "steel_painted", "girder", axis="y")
		for i in range(int(span / 2.5) + 1):
			for s in (-1, 1):
				kit.box((0.25, 0.015, 1.7), (s * 0.15, -span / 2 + i * span / int(span / 2.5), 0.9), "steel_painted", "stiffener")
	elif what == "deck":
		kit.box((11.0, 1.0, 0.25), (0, 0, 0.125), "concrete", "deck")
		kit.box((7.3, 1.0, 0.1), (0, 0, 0.3), "asphalt", "surfacing")
		for s in (-1, 1):
			kit.box((1.6, 1.0, 0.2), (s * 4.5, 0, 0.35), "paving", "footway")
	elif what == "parapet":
		kit.box((0.25, 1.0, 0.1), (0, 0, 0.05), "concrete", "plinth")
		for z in (0.45, 0.8, 1.15):
			kit.box((0.1, 1.0, 0.08), (0, 0, z), "aluminium", "rail")
		kit.box((0.1, 0.06, 1.1), (0, 0, 0.6), "aluminium", "post")
	elif what == "pier":
		kit.box((3.0, 3.0, 1.0), (0, 0, 0.5), "concrete", "pile_cap")
		kit.cyl(0.75, span, (0, 0, 1.0 + span / 2), "concrete", "column", segs=20)
		kit.box((9.0, 1.8, 1.2), (0, 0, 1.6 + span), "concrete", "crosshead")
	elif what == "abutment":
		kit.box((12.0, 1.2, 6.0), (0, 0, 3.0), "concrete", "wall")
		kit.box((12.0, 3.5, 1.0), (0, -0.6, 0.5), "concrete", "base")
		for s in (-1, 1):
			kit.prism([(0, 0), (6.0, 0), (0, 6.0)], 0.5, (s * 5.75, -0.6, 0), "concrete", "wing_wall", axis="x", rot=(0, 0, 180))
	elif what == "bearing":
		kit.box((0.6, 0.5, 0.04), (0, 0, 0.02), "steel_painted", "plate")
		kit.box((0.5, 0.4, 0.1), (0, 0, 0.09), "rubber", "elastomer")
		kit.box((0.6, 0.5, 0.04), (0, 0, 0.16), "steel_painted", "plate")
	elif what == "footbridge":
		for s in (-1, 1):
			kit.box((0.15, span, 0.15), (s * 1.3, 0, 0.075), "steel_painted", "bottom_chord")
			kit.box((0.15, span, 0.15), (s * 1.3, 0, 1.6), "steel_painted", "top_chord")
			n = int(span / 2)
			for i in range(n):
				y0 = -span / 2 + i * span / n
				kit.strut((s * 1.3, y0, 0.1), (s * 1.3, y0 + span / n, 1.6) if i % 2 == 0 else (s * 1.3, y0 + span / n, 0.1), 0.08, 0.08, "steel_painted", "diagonal") if i % 2 == 0 else kit.strut((s * 1.3, y0, 1.6), (s * 1.3, y0 + span / n, 0.1), 0.08, 0.08, "steel_painted", "diagonal")
		kit.box((2.5, span, 0.12), (0, 0, 0.2), "concrete", "deck")
	elif what == "arch":
		pts = [(-span / 2 + span * i / 16, 0, span * 0.2 * math.sin(math.pi * i / 16)) for i in range(17)]
		kit.sweep([(0, p[0], p[2]) for p in pts], [(-0.5, -0.4), (0.5, -0.4), (0.5, 0.4), (-0.5, 0.4)], "steel_painted", "rib", up=(1, 0, 0))
		for i in range(2, 15, 2):
			kit.rod((0, pts[i][0], pts[i][2]), (0, pts[i][0], 0), 0.04, "steel_galvanised", "hanger")
	elif what == "culvert":
		with kit.hollow(0.3):
			kit.prism([(-1.5, 0), (1.5, 0), (1.5, 2.0), (-1.5, 2.0)], 1.0, (0, 0, 0), "concrete", "box", axis="y")
	elif what == "retaining":
		kit.prism([(-0.2, 0), (1.6, 0), (1.6, 0.4), (0.2, 0.4), (0.1, span), (-0.2, span)], 1.0, (0, 0, 0), "concrete", "wall", axis="x")
	elif what == "gabion":
		kit.box((1.0, 1.0, 1.0), (0, 0, 0.5), "paving", "stone_fill")
		for s in (-1, 1):
			kit.grid_bars(1.0, 1.0, (0, s * 0.505, 0.5), 10, 10, 0.003, "steel_galvanised", "mesh")
	elif what == "sheet_pile":
		kit.prism([(-0.5, -0.15), (-0.3, -0.15), (-0.15, 0.15), (0.15, 0.15), (0.3, -0.15), (0.5, -0.15), (0.5, -0.135), (0.31, -0.135), (0.16, 0.165), (-0.16, 0.165), (-0.31, -0.135), (-0.5, -0.135)], span, (0, 0, -span / 2 + 1.0), "steel_painted", "pile", axis="z")
	elif what == "tunnel_ring":
		kit.tube(3.5, 1.0, (0, 0, 3.2), "concrete", "lining", axis="y", wall=0.35, segs=32)
		kit.box((5.2, 1.0, 0.5), (0, 0, 0.85), "concrete", "invert")


def energy(what="turbine"):
	if what == "turbine":
		kit.cyl(2.0, 80.0, (0, 0, 40.0), "paint_white", "tower", segs=20, r2=1.2)
		kit.rounded_box((3.5, 9.0, 3.5), (0, -1.5, 81.5), "paint_white", "nacelle", radius=0.8)
		kit.sphere(1.6, (0, 3.5, 81.5), "paint_white", "hub", segs=14)
		for i in range(3):
			a = math.radians(90 + 120 * i)
			kit.strut((0, 3.5, 81.5), (40.0 * math.cos(a), 3.5, 81.5 + 40.0 * math.sin(a)), 0.5, 2.2, "paint_white", "blade")
	elif what in ("solar_ground", "solar_roof"):
		rows = 2 if what == "solar_ground" else 1
		for r in range(rows):
			for i in range(6):
				kit.box((1.0, 1.7, 0.04), (-2.6 + i * 1.04, 0, 1.2 + r * 0.0) if rows == 1 else (-2.6 + i * 1.04, -0.8 + r * 1.6, 1.0 + r * 0.9), "plastic_blue", "panel", rot=(30, 0, 0))
		if what == "solar_ground":
			for x in (-2.5, 0, 2.5):
				kit.rod((x, -1.2, 0), (x, -1.2, 0.8), 0.04, "steel_galvanised", "leg")
				kit.rod((x, 1.2, 0), (x, 1.2, 2.2), 0.04, "steel_galvanised", "leg")
				kit.rod((x, -1.4, 0.7), (x, 1.5, 2.35), 0.03, "steel_galvanised", "rafter")
		else:
			for x in (-2.5, 2.5):
				kit.box((0.05, 1.6, 0.05), (x, 0, 0.9), "aluminium", "rail")
	elif what == "transformer":
		with kit.hollow(0.4):
			kit.box((2.4, 1.6, 2.0), (0, 0, 1.2), "plastic_grey", "tank")
		for s in (-1, 1):
			for i in range(8):
				kit.box((0.03, 1.2, 1.5), (s * (1.3 + i * 0.06), 0, 1.2), "plastic_grey", "radiator")
		for i in range(3):
			kit.lathe([(0.06, 0), (0.1, 0.1), (0.06, 0.2), (0.1, 0.3), (0.06, 0.4), (0.1, 0.5), (0.04, 0.7)], (-0.7 + i * 0.7, 0, 2.2), "ceramic", "bushing", segs=10)
		kit.box((3.6, 2.2, 0.2), (0, 0, 0.1), "concrete", "plinth")
	elif what == "substation":
		with kit.hollow(0.05):
			kit.box((3.5, 2.5, 2.4), (0, 0, 1.2), "plastic_green", "enclosure")
		kit.prism([(-1.85, 0), (1.85, 0), (0, 0.3)], 2.7, (0, 0, 2.4), "plastic_green", "roof", axis="y")
		for s in (-1, 1):
			kit.box((0.9, 0.03, 2.0), (s * 0.5, 1.26, 1.05), "plastic_green", "door")
	elif what == "battery":
		with kit.hollow(0.1):
			kit.box((2.4, 6.0, 2.6), (0, 0, 1.3), "paint_white", "container")
		for i in range(4):
			kit.box((0.03, 1.2, 2.0), (1.21, -2.2 + i * 1.45, 1.2), "plastic_grey", "door")
		kit.box((1.0, 1.0, 0.8), (0, -2.0, 3.0), "steel_galvanised", "cooling")
	elif what == "water_tower":
		for i in range(6):
			a = math.radians(60 * i)
			kit.rod((4.0 * math.cos(a), 4.0 * math.sin(a), 0), (3.0 * math.cos(a), 3.0 * math.sin(a), 20.0), 0.25, "concrete", "leg")
		with kit.hollow(0.05):
			kit.lathe([(2.0, 18.0), (6.0, 22.0), (6.0, 27.0), (1.0, 29.0)], (0, 0, 0), "concrete", "tank", segs=24)
		kit.cyl(0.8, 20.0, (0, 0, 10.0), "concrete", "riser", segs=14)
	elif what == "pump_station":
		with kit.hollow(0.08):
			kit.box((4.0, 3.0, 2.8), (0, 0, 1.4), "brick", "kiosk")
		kit.box((4.3, 3.3, 0.15), (0, 0, 2.87), "roof_felt", "roof")
		kit.box((1.6, 0.05, 2.1), (0, 1.5, 1.05), "steel_painted", "doors")
	elif what == "settlement_tank":
		with kit.hollow(0.1):
			kit.tube(8.0, 2.5, (0, 0, 0.75), "concrete", "wall", wall=0.3, segs=36)
		kit.cyl(7.7, 0.05, (0, 0, 1.6), "water", "water", segs=36)
		kit.box((0.8, 16.0, 0.3), (0, 0, 2.3), "steel_galvanised", "bridge")
		kit.cyl(0.5, 1.5, (0, 0, 2.2), "steel_galvanised", "drive", segs=12)
	elif what == "manhole_chamber":
		with kit.hollow(0.2):
			kit.tube(0.75, 2.0, (0, 0, -1.0), "concrete", "rings", wall=0.1, segs=20)
		kit.cyl(0.4, 0.04, (0, 0, 0.0), "cast_iron", "cover", segs=20)
	elif what in ("pipe_large", "pipe_gas"):
		kit.tube(0.6 if what == "pipe_large" else 0.3, 1.0, (0, 0, 0), "concrete" if what == "pipe_large" else "plastic_yellow", "pipe", axis="y", wall=0.06 if what == "pipe_large" else 0.02, segs=20)
	elif what == "mast_telecom":
		kit.cyl(0.4, 25.0, (0, 0, 12.5), "steel_galvanised", "monopole", segs=12, r2=0.2)
		for z in (24.0, 21.5):
			for i in range(3):
				a = math.radians(120 * i)
				kit.box((0.3, 0.12, 2.0), (0.5 * math.cos(a), 0.5 * math.sin(a), z), "plastic_white", "antenna", rot=(0, 0, 120 * i + 90))
		kit.box((1.5, 0.8, 1.6), (1.5, 0, 0.8), "plastic_green", "cabinet")
	elif what == "ev_hub":
		for i in range(4):
			kit.rounded_box((0.5, 0.3, 1.9), (-3.6 + i * 2.4, 0, 0.95), "paint_white", "charger", radius=0.04)
			kit.box((0.3, 0.004, 0.2), (-3.6 + i * 2.4, 0.152, 1.4), "screen", "screen")
		for x in (-4.5, 4.5):
			kit.box((0.2, 0.2, 3.5), (x, -0.8, 1.75), "steel_painted", "column")
		kit.box((10.0, 5.5, 0.15), (0, 1.5, 3.6), "plastic_blue", "canopy", rot=(-4, 0, 0))
	elif what == "fuel_pump":
		kit.rounded_box((1.0, 0.5, 1.6), (0, 0, 0.9), "paint_white", "dispenser", radius=0.04)
		kit.box((0.6, 0.004, 0.3), (0, 0.252, 1.35), "screen", "display")
		for s in (-1, 1):
			kit.sweep([(s * 0.52, 0, 1.2), (s * 0.7, 0, 0.6), (s * 0.55, 0, 0.9)], kit.circle(0.012, 6), "plastic_black", "hose", up=(0, 1, 0))
		kit.box((1.6, 1.0, 0.15), (0, 0, 0.075), "concrete", "island")
	elif what == "forecourt_canopy":
		for x in (-6, 6):
			kit.box((0.4, 0.4, 5.0), (x, 0, 2.5), "paint_white", "column")
		kit.box((18.0, 9.0, 0.8), (0, 0, 5.4), "paint_white", "canopy")
		kit.box((18.05, 9.05, 0.3), (0, 0, 5.4), "plastic_green", "fascia_band")


_ROAD = (("carriageway", "Road, two lane", 7.3, "z"), ("carriageway_marked", "Road with markings, two lane", 7.3, "z"), ("pavement", "Footway, 2 m", 2.0, "z"), ("cycle_lane", "Cycle lane, 1.5 m", 1.5, "z"),
	("verge", "Grass verge, 2 m", 2.0, "z"), ("gravel", "Gravel track, 3 m", 3.0, "z"))
for _w, _l, _wd, _st in _ROAD:
	per_m("road.surface." + _w, road, _l + ", per metre", "outdoor", what=_w, w=_wd)
per_m("road.surface.single_lane", road, "Road, single lane, per metre", "outdoor", what="carriageway", w=3.65)
per_m("road.surface.dual", road, "Road, three lane carriageway, per metre", "outdoor", what="carriageway_marked", w=11.0)
for _w, _l, _wd in (("crossing", "Zebra crossing with beacons", 7.3), ("speed_hump", "Speed hump", 7.3), ("roundabout", "Roundabout, 28 m", 14.0), ("mini_roundabout", "Mini roundabout", 6.0), ("parking_bay", "Parking bay", 2.4),
	("parking_accessible", "Accessible parking bay", 3.6), ("island", "Traffic island with bollards", 1.8), ("gantry_sign", "Motorway sign gantry", 11.0)):
	reg("road.feature." + _w, road, _l, "outdoor", what=_w if _w != "mini_roundabout" else "roundabout", w=_wd)
for _w, _l in (("track", "Railway track on ballast"), ("track_slab", "Railway slab track"), ("platform", "Station platform, 4 m wide"), ("ole_wire", "Overhead line wires")):
	per_m("rail.way." + _w, rail, _l + ", per metre", "outdoor", what=_w)
for _w, _l in (("ole_mast", "Overhead line mast"), ("signal", "Colour light signal"), ("buffer", "Buffer stop"), ("level_crossing", "Level crossing barrier and lights"), ("shelter", "Platform shelter"), ("ticket_gate", "Ticket gates, three aisles")):
	reg("rail.feature." + _w, rail, _l, "outdoor", what=_w)
for _w, _l in (("carriage", "Passenger carriage"), ("loco", "Locomotive"), ("tram", "Tram"), ("wagon", "Freight wagon")):
	reg("rail.train." + _w, rail, _l, "outdoor", "vehicle", what=_w)
for _s in (15.0, 25.0, 35.0):
	reg("bridge.beam.precast_%d" % _s, bridge, "Precast bridge beam, %d m" % _s, "outdoor", "structure", span=_s)
	reg("bridge.beam.steel_%d" % _s, bridge, "Steel plate girder, %d m" % _s, "outdoor", "structure", what="steel_girder", span=_s)
for _s in (5.0, 8.0, 12.0):
	reg("bridge.support.pier_%d" % _s, bridge, "Bridge pier, %d m" % _s, "outdoor", "structure", what="pier", span=_s)
reg("bridge.support.abutment", bridge, "Bridge abutment with wing walls", "outdoor", "structure", what="abutment")
reg("bridge.support.bearing", bridge, "Bridge bearing", "outdoor", "structure", what="bearing")
per_m("bridge.deck.road", bridge, "Bridge deck with surfacing, per metre", "outdoor", "structure", what="deck")
per_m("bridge.deck.parapet", bridge, "Bridge parapet, per metre", "outdoor", what="parapet")
reg("bridge.span.footbridge_20", bridge, "Truss footbridge, 20 m", "outdoor", "structure", what="footbridge")
reg("bridge.span.footbridge_30", bridge, "Truss footbridge, 30 m", "outdoor", "structure", what="footbridge", span=30.0)
reg("bridge.span.arch_40", bridge, "Steel arch rib with hangers, 40 m", "outdoor", "structure", what="arch", span=40.0)
reg("bridge.span.arch_80", bridge, "Steel arch rib with hangers, 80 m", "outdoor", "structure", what="arch", span=80.0)
per_m("earthworks.culvert.box", bridge, "Box culvert, per metre", "outdoor", what="culvert")
per_m("earthworks.tunnel.ring", bridge, "Tunnel lining, 7 m bore, per metre", "outdoor", what="tunnel_ring")
for _h in (2.0, 3.5, 5.0):
	register("earthworks.retaining.h%d" % (_h * 1000), bridge, "Retaining wall, %.1f m, per metre" % _h, family="earthworks", tags=("earthworks", "outdoor", "structure"), stretch="x", what="retaining", span=_h)
reg("earthworks.retaining.gabion", bridge, "Gabion basket", "outdoor", what="gabion")
for _l in (6.0, 12.0):
	reg("earthworks.pile.sheet_%d" % _l, bridge, "Sheet pile, %d m" % _l, "outdoor", "structure", what="sheet_pile", span=_l)
for _w, _l in (("solar_ground", "Solar array, ground mounted"), ("solar_roof", "Solar panels, roof row of six"), ("transformer", "Power transformer"), ("substation", "Substation enclosure"),
	("battery", "Battery storage container"), ("mast_telecom", "Telecoms monopole, 25 m"), ("ev_hub", "EV charging hub, four chargers"), ("fuel_pump", "Fuel pump on island"), ("forecourt_canopy", "Forecourt canopy")):
	reg("energy.plant." + _w, energy, _l, "outdoor", what=_w)
for _w, _l in (("water_tower", "Water tower"), ("pump_station", "Pumping station kiosk"), ("settlement_tank", "Settlement tank, 16 m"), ("manhole_chamber", "Manhole chamber")):
	reg("water.plant." + _w, energy, _l, "outdoor", what=_w)
per_m("water.pipe.sewer_1200", energy, "Concrete sewer pipe, 1200, per metre", "outdoor", what="pipe_large")
per_m("water.pipe.gas_main", energy, "Gas main, per metre", "outdoor", what="pipe_gas")
