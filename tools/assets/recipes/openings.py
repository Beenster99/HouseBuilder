"""Doors and windows for every catalog opening kind. Origin: bottom centre of the opening,
in the wall's plane; X along the wall, Y through it."""
import kit
from registry import catalog, register


def window(w, h):
	lights = 1 if w < 0.9 else (2 if w < 1.6 else 3)
	with kit.stage("frame"):
		kit.frame(w, h, 0.07, 0.10, slot="paint_white", name="frame")
		kit.box((w + 0.10, 0.20, 0.03), (0, 0.04, -0.015), "paint_white", "sill_board")
		lw = (w - 0.14 - 0.06 * (lights - 1)) / lights
		for i in range(1, lights):
			kit.box((0.06, 0.10, h - 0.14), (-w / 2 + 0.07 + i * lw + (i - 0.5) * 0.06, 0, h / 2), "paint_white", "mullion")
	for i in range(lights):
		x = -w / 2 + 0.07 + lw / 2 + i * (lw + 0.06)
		with kit.stage("frame"):
			kit.frame(lw, h - 0.14, 0.045, 0.06, at=(x, 0, 0.07), slot="paint_white", name="sash")
		with kit.stage("glazing"):
			kit.box((lw - 0.09, 0.024, h - 0.23), (x, 0, h / 2), "glass", "pane")
		with kit.stage("ironmongery"):
			if i == 0 or i == lights - 1:
				kit.box((0.02, 0.03, 0.12), (x + (lw / 2 - 0.022) * (1 if i == 0 else -1), 0.045, h / 2), "steel_stainless", "handle")
	kit.socket("wall", (0, 0, 0))


def _lever(x, z, side, hand):
	kit.cyl(0.026, 0.008, (x, side * 0.026, z), "steel_stainless", "rose", axis="y", segs=16)
	kit.rod((x, side * 0.026, z), (x, side * 0.07, z), 0.009, "steel_stainless", "spindle")
	kit.rod((x, side * 0.065, z), (x + hand * 0.12, side * 0.065, z), 0.009, "steel_stainless", "lever")


def door(w, h, material, style="panel"):
	"""style: panel (timber), flush (fire, vision panel), glazed, secure (steel), double."""
	leaves = 2 if w >= 1.5 else 1
	lining = 0.032
	leaf_slot = {"timber": "paint_white", "steel": "steel_painted", "glass": "aluminium"}[material]
	if style == "external":
		leaf_slot = "hardwood"
	with kit.stage("frame"):
		kit.frame(w, h, lining, 0.12, slot="steel_painted" if material == "steel" else "paint_white", name="lining", bottom=False)
		if style in ("external", "secure"):
			kit.box((w - 2 * lining, 0.12, 0.015), (0, 0, 0.0075), "aluminium", "threshold")
	lw = (w - 2 * lining - 0.006 * (leaves + 1)) / leaves
	lh = h - lining - 0.010
	for i in range(leaves):
		x = -w / 2 + lining + 0.006 + lw / 2 + i * (lw + 0.006)
		hand = 1 if i == 0 else -1  # hinge side is -hand; the handle sits toward +hand... of the meeting edge
		zc = 0.005 + lh / 2
		with kit.stage("leaf"):
			if material == "glass" or style == "glazed":
				kit.frame(lw, lh, 0.09, 0.044, at=(x, 0, 0.005), slot=leaf_slot, name="stile")
				kit.box((lw - 0.18, 0.012, lh - 0.18), (x, 0, zc), "glass", "glass")
			else:
				kit.box((lw, 0.044, lh), (x, 0, zc), leaf_slot, "leaf")
				if style in ("panel", "external"):
					for pz, ph in ((0.22 + (lh * 0.36) / 2, lh * 0.36), (lh - 0.18 - (lh * 0.42) / 2, lh * 0.42)):
						kit.box((lw - 0.28, 0.056, ph), (x, 0, pz), leaf_slot, "panel")
				elif style == "flush":
					kit.box((0.2, 0.05, 0.6), (x + hand * (lw / 2 - 0.24), 0, 1.5), "glass", "vision_panel")
				elif style == "secure":
					kit.box((0.25, 0.05, 0.25), (x, 0, 1.55), "glass", "viewer")
					kit.box((lw * 0.5, 0.05, 0.12), (x, 0, 1.0), "steel_galvanised", "hatch")
		with kit.stage("ironmongery"):
			hx = x + hand * (lw / 2 - 0.065) if leaves == 1 else x + (1 if i == 0 else -1) * (lw / 2 - 0.065)
			for side in (-1, 1):
				_lever(hx, 1.0, side, -1 if hx > x else 1)
			hinge_x = x - (hx - x) / abs(hx - x) * (lw / 2 + 0.003)
			for hz in (0.25, lh / 2, lh - 0.22):
				kit.cyl(0.007, 0.1, (hinge_x, 0.03, hz), "steel_stainless", "hinge", segs=8)
			if style == "flush":
				kit.box((0.26, 0.05, 0.06), (x, 0.045, lh - 0.06), "aluminium", "closer")
	kit.socket("wall", (0, 0, 0))


def shutter(w, h):
	with kit.hollow(0.08):
		with kit.stage("frame"):
			for s in (-1, 1):
				kit.box((0.09, 0.07, h), (s * (w / 2 - 0.045), 0, h / 2), "steel_galvanised", "guide")
			kit.box((w, 0.36, 0.36), (0, -0.14, h + 0.18 - 0.36), "steel_galvanised", "hood")
		with kit.stage("leaf"):
			n = int((h - 0.36) / 0.08)
			for i in range(n):
				kit.box((w - 0.2, 0.022 if i % 2 else 0.03, 0.078), (0, 0, 0.12 + i * 0.08), "steel_galvanised", "slat")
			kit.box((w - 0.2, 0.05, 0.08), (0, 0, 0.04), "plant_yellow", "bottom_rail")
		kit.socket("wall", (0, 0, 0))


STYLE = {"door_internal": "panel", "door_external": "external", "door_double": "panel", "door_fire": "flush",
	"door_accessible": "flush", "door_secure": "secure"}

for _kind, _k in catalog()["kinds"].items():
	if _k["family"] != "opening" or "." in _kind:
		continue  # (a kind that is itself an asset id is drawn by that asset)
	_a, _b = _kind.split("_", 1)
	for _m in _k["materials"]:
		_id = "opening.%s.%s" % (_a, _b) + ("" if _m == _k["materials"][0] else "_" + _m)
		if _a == "window":
			register(_id, window, _k["label"], family="opening", kind=_kind, tags=("opening", "window"), w=_k["w"], h=_k["h"])
		elif _kind.startswith("door_vehicle_"):
			continue  # (the roller and up-and-over vehicle doors: recipes/openings_more.py)
		elif _kind == "door_vehicle":
			register(_id, shutter, _k["label"], family="opening", kind=_kind, tags=("opening", "door"), w=_k["w"], h=_k["h"])
		else:
			register(_id, door, _k["label"] + (" (glazed)" if _m == "glass" else ""), family="opening", kind=_kind,
				tags=("opening", "door"), w=_k["w"], h=_k["h"], material=_m, style="glazed" if _m == "glass" else STYLE[_kind])
