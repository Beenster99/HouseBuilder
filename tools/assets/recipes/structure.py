"""Structure: every catalog section as a 1 m length the game stretches, pads, and connections."""
import kit
from registry import asset, catalog, register

SLOT = {"t": "softwood", "gl": "glulam", "ub": "steel_painted", "uc": "steel_painted", "chs": "steel_painted", "rc": "concrete"}


def _flange(w, d, area):
	"""Flange thickness of an I-section from its area, with the web 0.62 of the flange."""
	lo, hi = 0.002, d / 3
	for _ in range(40):
		tf = (lo + hi) / 2
		if 2 * w * tf + (d - 2 * tf) * 0.62 * tf < area:
			lo = tf
		else:
			hi = tf
	return tf


def _section(sid, s):
	slot = SLOT[sid.split("_")[0]]
	if s["shape"] == "i":
		tf = _flange(s["w"], s["d"], s["area"])
		kit.i_section(s["w"], s["d"], tf, 0.62 * tf, 1.0, slot=slot, name="section")
	elif s["shape"] == "chs":
		kit.tube(s["w"] / 2, 1.0, slot=slot, name="section", axis="y", wall=0.006, segs=20)
	else:
		kit.box((s["w"], 1.0, s["d"]), slot=slot, name="section")
	kit.socket("start", (0, -0.5, 0))
	kit.socket("end", (0, 0.5, 0))


for _sid, _s in catalog()["sections"].items():
	if _s["shape"] in ("i", "chs", "rect") and _sid.split("_")[0] in SLOT:
		register("structure.section." + _sid, _section, _s["label"], family="beam", kind=_sid,
			tags=("structure", SLOT[_sid.split("_")[0]]), stretch="z", sid=_sid, s=_s)


def _pad(s):
	kit.box((s["w"], s["w"], s["d"]), (0, 0, -s["d"] / 2), "concrete", "pad")
	kit.socket("top", (0, 0, 0))


def _pile(s):
	kit.cyl(s["dia"] / 2, 1.0, (0, 0, -0.5), "concrete", "pile", segs=24)
	kit.socket("top", (0, 0, 0))


for _sid, _s in catalog()["sections"].items():
	if _s["shape"] == "pad":
		register("structure.foundation." + _sid, _pad, _s["label"], family="foundation", kind=_sid, tags=("structure", "concrete"), s=_s)
	elif _s["shape"] == "pile":
		register("structure.foundation." + _sid, _pile, _s["label"], family="foundation", kind=_sid, tags=("structure", "concrete"), stretch="y", s=_s)


@asset("structure.connection.baseplate", "Column base plate, 4 bolts", family="column", tags=("structure", "steel", "connection"))
def baseplate(size=0.4, t=0.025):
	kit.box((size, size, t), (0, 0, t / 2), "steel_painted", "plate")
	for x in (-1, 1):
		for y in (-1, 1):
			at = (x * size * 0.36, y * size * 0.36, 0)
			kit.cyl(0.012, 0.09, (at[0], at[1], 0.045), "steel_galvanised", "bolt", segs=10)
			kit.cyl(0.022, 0.02, (at[0], at[1], t + 0.01), "steel_galvanised", "nut", segs=6)
	kit.socket("column", (0, 0, t))


@asset("structure.connection.endplate", "Beam end plate, 6 bolts", family="beam", tags=("structure", "steel", "connection"))
def endplate(w=0.2, d=0.42, t=0.015):
	kit.box((w, t, d), (0, t / 2, 0), "steel_painted", "plate")
	for x in (-1, 1):
		for z in (-1, 0, 1):
			kit.cyl(0.018, 0.03, (x * w * 0.3, t, z * d * 0.36), "steel_galvanised", "bolt", axis="y", segs=6)
	kit.socket("beam", (0, 0, 0))
