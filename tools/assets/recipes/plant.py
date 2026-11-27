"""Site plant, temporary works and demolition kit."""
import kit
from registry import asset


@asset("plant.crane.mast_section", "Tower crane mast section, 3 m", tags=("plant", "crane"))
def mast_section(h=3.0, w=1.6):
	kit.lattice(h, w, 0.12, 0.06, name="mast")
	kit.socket("top", (0, 0, h))


@asset("plant.crane.tower", "Tower crane, 30 m mast, 40 m jib", tags=("plant", "crane"))
def tower_crane(height=30.0, jib=40.0, counter=12.0, w=1.6):
	with kit.stage("base"):
		kit.box((6, 6, 0.8), (0, 0, 0.4), "concrete", "base")
	with kit.stage("mast"):
		kit.lattice(height, w, 0.12, 0.06, at=(0, 0, 0.8), bays=round(height / w), name="mast")
	top = 0.8 + height
	with kit.stage("slew"):
		kit.cyl(1.2, 0.5, (0, 0, top + 0.25), "plant_yellow", "slew_ring", segs=28)
		kit.box((1.4, 1.6, 2.0), (1.3, 0.2, top + 1.5), "paint_white", "cab")
		kit.box((0.02, 1.3, 1.1), (2.0, 0.2, top + 1.7), "glass", "cab_glass")
		kit.lattice(6.0, 1.0, 0.1, 0.05, at=(0, 0, top + 0.5), bays=5, name="tower_top")
	jz = top + 1.6
	with kit.stage("jib"):
		kit.lattice(jib, 1.2, 0.1, 0.05, at=(0, 0.8, jz), bays=round(jib / 1.6), name="jib", axis="y")
		kit.lattice(counter, 1.2, 0.1, 0.05, at=(0, -0.8 - counter, jz), bays=round(counter / 1.6), name="counter_jib", axis="y")
		for i in range(3):
			kit.box((1.6, 0.9, 1.4), (0, -counter + 0.4 + i * 1.0, jz - 0.9), "concrete", "counterweight")
		for y in (jib * 0.45, jib * 0.9):
			kit.rod((0, 0, top + 6.4), (0, y, jz + 0.6), 0.03, "steel_galvanised", "tie")
		kit.rod((0, 0, top + 6.4), (0, -counter, jz + 0.6), 0.03, "steel_galvanised", "tie")
	with kit.stage("hook"):
		ty = jib * 0.6
		kit.box((1.0, 1.2, 0.3), (0, ty, jz - 0.75), "plant_yellow", "trolley")
		kit.rod((0, ty, jz - 0.9), (0, ty, jz - 12.0), 0.012, "steel_galvanised", "cable", segs=6)
		kit.box((0.4, 0.25, 0.6), (0, ty, jz - 12.3), "hazard_red", "hook_block")
	kit.socket("hook", (0, ty, jz - 12.6))
	kit.socket("cab", (1.3, 0.2, top + 1.0))


@asset("plant.crane.wrecking_ball", "Wrecking ball, 2.5 t", tags=("plant", "demolition"))
def wrecking_ball(r=0.42):
	kit.sphere(r, (0, 0, r), "cast_iron", "ball", segs=28)
	kit.cyl(0.07, 0.2, (0, 0, 2 * r + 0.08), "cast_iron", "lug", segs=12)
	kit.socket("cable", (0, 0, 2 * r + 0.18))


@asset("plant.scaffold.bay", "Scaffold bay, 2.4 m by 1.3 m, one 2 m lift", tags=("plant", "temporary"))
def scaffold_bay(length=2.4, w=1.3, lift=2.0):
	r = 0.024
	with kit.stage("frame"):
		for x in (-length / 2, length / 2):
			for y in (-w / 2, w / 2):
				kit.box((0.15, 0.15, 0.008), (x, y, 0.004), "steel_galvanised", "base_plate")
				kit.rod((x, y, 0), (x, y, lift + 1.1), r, "steel_galvanised", "standard")
			kit.rod((x, -w / 2 - 0.1, lift), (x, w / 2 + 0.1, lift), r, "steel_galvanised", "transom")
		for y in (-w / 2, w / 2):
			kit.rod((-length / 2 - 0.1, y, lift - 0.06), (length / 2 + 0.1, y, lift - 0.06), r, "steel_galvanised", "ledger")
		kit.rod((-length / 2, w / 2 + 0.05, 0.15), (length / 2, w / 2 + 0.05, lift - 0.1), r, "steel_galvanised", "brace")
	with kit.stage("boards"):
		n = 5
		for i in range(n):
			kit.box((length + 0.2, 0.225, 0.038), (0, -w / 2 + 0.14 + i * 0.235, lift + 0.045), "softwood", "board")
		kit.box((length + 0.2, 0.038, 0.15), (0, w / 2 - 0.02, lift + 0.14), "softwood", "toe_board")
	with kit.stage("guardrail"):
		for z in (lift + 0.55, lift + 1.0):
			kit.rod((-length / 2 - 0.1, w / 2, z), (length / 2 + 0.1, w / 2, z), r, "steel_galvanised", "guardrail")
	kit.socket("next", (length, 0, 0))
	kit.socket("up", (0, 0, lift))


@asset("plant.fence.heras", "Temporary fence panel, 3.5 m", tags=("plant", "temporary"))
def heras(w=3.5, h=2.0):
	r = 0.019
	for x in (-w / 2, w / 2):
		kit.rod((x, 0, 0.1), (x, 0, h), r, "steel_galvanised", "upright")
		kit.rounded_box((0.22, 0.6, 0.14), (x, 0, 0.07), "concrete", "foot", radius=0.02)
	for z in (0.2, h):
		kit.rod((-w / 2, 0, z), (w / 2, 0, z), r, "steel_galvanised", "rail")
	for i in range(1, 24):
		x = -w / 2 + i * w / 24
		kit.rod((x, 0, 0.2), (x, 0, h), 0.003, "steel_galvanised", "wire", segs=4)
	for i in range(1, 6):
		z = 0.2 + i * (h - 0.2) / 6
		kit.rod((-w / 2, 0, z), (w / 2, 0, z), 0.003, "steel_galvanised", "wire", segs=4)
	kit.socket("next", (w, 0, 0))


@asset("plant.cabin.site_office", "Site cabin, 6 m", tags=("plant", "temporary"))
def cabin(w=6.0, d=2.4, h=2.6):
	with kit.hollow(0.012):
		with kit.stage("shell"):
			kit.box((w, d, h - 0.3), (0, 0, 0.15 + (h - 0.3) / 2), "steel_painted", "shell")
			kit.box((w + 0.06, d + 0.06, 0.1), (0, 0, h - 0.1), "steel_galvanised", "roof")
			for x in (-w / 2 + 0.3, w / 2 - 0.3):
				for y in (-d / 2 + 0.2, d / 2 - 0.2):
					kit.box((0.2, 0.2, 0.15), (x, y, 0.075), "steel_galvanised", "jack_leg")
		with kit.stage("openings"):
			kit.box((0.9, 0.03, 2.0), (-w / 2 + 0.9, d / 2, 1.15), "plant_yellow", "door")
			for x in (0.3, 1.9):
				kit.frame(1.1, 0.9, 0.04, 0.05, at=(x, d / 2, 1.1), slot="paint_white", name="window")
				kit.box((1.02, 0.02, 0.82), (x, d / 2, 1.55), "glass", "pane")


@asset("plant.skip.builders", "Builder's skip, 6 yd", tags=("plant", "waste"))
def skip(w=1.7, l=3.0, h=1.2):
	with kit.hollow(0.03):
		pts = [(-l / 2 + 0.5, 0), (l / 2 - 0.5, 0), (l / 2, h), (-l / 2, h)]
		kit.prism(pts, w, (0, 0, 0), "plant_yellow", "body", axis="x")
		kit.box((w + 0.08, l + 0.06, 0.06), (0, 0, h), "plant_yellow", "rim")
		for s in (-1, 1):
			for y in (-l / 4, l / 4):
				kit.box((0.06, 0.12, 0.14), (s * (w / 2 + 0.03), y, h - 0.2), "steel_painted", "lug")


@asset("demolition.charge.shaped", "Demolition charge with detonator lead", tags=("demolition",))
def charge():
	kit.rounded_box((0.22, 0.08, 0.12), (0, 0.04, 0), "hivis_orange", "charge", radius=0.012)
	kit.box((0.23, 0.082, 0.025), (0, 0.04, 0), "plastic_black", "strap")
	kit.cyl(0.006, 0.07, (0.06, 0.04, 0.09), "steel_stainless", "detonator", segs=8)
	kit.rod((0.06, 0.04, 0.12), (0.2, 0.02, 0.3), 0.003, "plant_yellow", "lead", segs=6)
	kit.socket("surface", (0, 0, 0))
