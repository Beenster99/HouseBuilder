"""Whole-building models for the contract building types (context.type.<building type id>).

Massing models with real roofs, window grids, entrances and signage: richer than the plain
neighbouring blocks in outdoors.py, light enough to stand in a street or a library page.
Every model faces +Y with its origin at the ground centre, in stages walls, roof, openings.
"""
import math

import kit
from registry import register

STONE = "paving"
WHITE = "paint_white"


def reg(id, fn, label, *tags, **params):
	register(id, fn, label, family="context", tags=("context", "outdoor", "building", "building_type") + tags, **params)


class Mass:
	"""One box of a building, with helpers that hang things on its four faces.
	Faces: f (+Y, the front), b (-Y), l (-X), r (+X). `u` runs left to right as seen from outside."""

	def __init__(self, w, d, h, at=(0.0, 0.0), z=0.0, walls="brick", name="walls"):
		self.w, self.d, self.h, self.x, self.y, self.z, self.walls = w, d, h, at[0], at[1], z, walls
		with kit.stage("walls"):
			with kit.hollow(0.08):
				kit.box((w, d, h), (self.x, self.y, z + h / 2), walls, name)

	def span(self, face):
		return self.w if face in "fb" else self.d

	def panel(self, face, u, z, pw, ph, slot="glass", name="window", t=0.06, out=0.0, stage="openings"):
		"""A flat panel on a face. `u` is the offset along the face from its centre, `z` the
		height of the panel's centre above this mass's base."""
		o = t / 2 - 0.02 + out
		if face == "f":
			size, at = (pw, t, ph), (self.x + u, self.y + self.d / 2 + o, self.z + z)
		elif face == "b":
			size, at = (pw, t, ph), (self.x - u, self.y - self.d / 2 - o, self.z + z)
		elif face == "r":
			size, at = (t, pw, ph), (self.x + self.w / 2 + o, self.y - u, self.z + z)
		else:
			size, at = (t, pw, ph), (self.x - self.w / 2 - o, self.y + u, self.z + z)
		with kit.stage(stage):
			kit.box(size, at, slot, name)

	def row(self, face, z, n, pw, ph, slot="glass", name="window", skip=(), sill=None, margin=0.0, head=None):
		"""`n` evenly spaced panels along a face. `skip` lists indexes left out (for doors)."""
		span = self.span(face) - 2 * margin
		for i in range(n):
			if i in skip:
				continue
			u = -span / 2 + span * (i + 0.5) / n
			self.panel(face, u, z, pw, ph, slot, name)
			if sill:
				self.panel(face, u, z - ph / 2 - 0.05, pw + 0.16, 0.1, sill, "sill", t=0.12)
			if head:
				self.panel(face, u, z + ph / 2 + 0.09, pw + 0.16, 0.18, head, "lintel", t=0.08)

	def grid(self, face, floors, fh, n, pw, ph, slot="glass", name="window", z0=None, skip=(), sill=None, margin=0.0, head=None, first=0):
		for f in range(first, floors):
			self.row(face, (z0 if z0 is not None else fh * 0.55) + f * fh, n, pw, ph, slot, name, skip if f == 0 else (), sill, margin, head)

	def door(self, face, u=0.0, w=1.0, h=2.1, slot="plastic_blue", name="door", frame=WHITE):
		self.panel(face, u, h / 2, w + 0.16, h + 0.08, frame, "door_frame", t=0.05)
		self.panel(face, u, h / 2, w, h, slot, name, t=0.09)

	def band(self, face, z, bh, slot, name="band", t=0.08, inset=0.0):
		self.panel(face, 0.0, z, self.span(face) - inset * 2, bh, slot, name, t=t)

	def sign(self, face, z, w, h, slot="plastic_green", u=0.0, name="fascia"):
		self.panel(face, u, z, w, h, slot, name, t=0.14)

	def flat(self, parapet=0.5, slot=None, deck="roof_felt"):
		top = self.z + self.h
		with kit.stage("roof"):
			with kit.hollow(0.1):
				kit.box((self.w + 0.2, self.d + 0.2, parapet), (self.x, self.y, top + parapet / 2), slot or "concrete", "parapet")
			kit.box((self.w - 0.5, self.d - 0.5, 0.04), (self.x, self.y, top + parapet + 0.02), deck, "roof_deck")

	def gable(self, roof="clay_tile", pitch=0.32, ridge=None, over=0.35, rise=None):
		"""A pitched roof with gable ends. `ridge` is "x" or "y"; by default along the long side."""
		ridge = ridge or ("x" if self.w >= self.d else "y")
		span = (self.d if ridge == "x" else self.w)
		length = (self.w if ridge == "x" else self.d)
		rise = rise if rise is not None else span * pitch
		top = self.z + self.h
		with kit.stage("roof"):
			with kit.hollow(0.06):
				kit.prism([(-span / 2 - over, 0), (span / 2 + over, 0), (0, rise + over * rise / (span / 2))], length + over, (self.x, self.y, top), roof, "roof", axis=ridge)
		with kit.stage("walls"):
			with kit.hollow(0.08):
				kit.prism([(-span / 2, 0), (span / 2, 0), (0, rise)], length - 0.02, (self.x, self.y, top - 0.01), self.walls, "gable", axis=ridge)
		return rise

	def hip(self, roof="slate", pitch=0.3, over=0.4):
		"""A hipped roof: four slopes to a short ridge."""
		import bmesh
		w, d = self.w / 2 + over, self.d / 2 + over
		rise = min(self.w, self.d) * pitch
		r = max(0.0, max(w, d) - min(w, d))
		bm = bmesh.new()
		if self.w >= self.d:
			top = [(-r, 0, rise), (r, 0, rise)]
		else:
			top = [(0, -r, rise), (0, r, rise)]
		base = [bm.verts.new(p) for p in ((-w, -d, 0), (w, -d, 0), (w, d, 0), (-w, d, 0))]
		a, b = bm.verts.new(top[0]), bm.verts.new(top[1])
		bm.faces.new((base[3], base[2], base[1], base[0]))
		if self.w >= self.d:
			bm.faces.new((base[0], base[1], b, a))
			bm.faces.new((base[2], base[3], a, b))
			bm.faces.new((base[1], base[2], b))
			bm.faces.new((base[3], base[0], a))
		else:
			bm.faces.new((base[1], base[2], b, a))
			bm.faces.new((base[3], base[0], a, b))
			bm.faces.new((base[0], base[1], a))
			bm.faces.new((base[2], base[3], b))
		bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
		with kit.stage("roof"):
			with kit.hollow(0.06):
				kit._obj("roof", bm, roof, kit._place((self.x, self.y, self.z + self.h), (0, 0, 0)))
		return rise

	def shed(self, roof="steel_galvanised", rise=1.5, over=0.2):
		"""A shallow double-pitch shed roof (industrial)."""
		return self.gable(roof, ridge="x" if self.w >= self.d else "y", over=over, rise=rise)

	def chimney(self, u=0.0, v=0.0, h=2.2, slot="brick", w=0.7):
		with kit.stage("roof"):
			kit.box((w, 0.5, h), (self.x + u, self.y + v, self.z + self.h + h / 2), slot, "chimney")
			kit.cyl(0.11, 0.3, (self.x + u, self.y + v, self.z + self.h + h + 0.15), "clay_tile", "chimney_pot", segs=8)

	def dormer(self, u, rise_at=0.6, w=1.3, roof="slate", front=True):
		y = self.y + (self.d / 2 - 1.0) * (1 if front else -1)
		z = self.z + self.h + rise_at
		with kit.stage("roof"):
			kit.box((w, 1.6, 1.1), (self.x + u, y, z + 0.55), WHITE, "dormer")
			kit.prism([(-w / 2 - 0.1, 0), (w / 2 + 0.1, 0), (0, 0.45)], 1.8, (self.x + u, y, z + 1.1), roof, "dormer_roof", axis="y")
		with kit.stage("openings"):
			kit.box((w - 0.35, 0.05, 0.8), (self.x + u, y + (0.8 + 0.01) * (1 if front else -1), z + 0.55), "glass", "dormer_window")


def canopy(w, d, z, at, slot="steel_painted", posts=2, post="steel_painted", t=0.18):
	"""A flat entrance canopy on posts, standing in front of `at` (x, y of its back edge)."""
	x, y = at
	with kit.stage("roof"):
		kit.box((w, d, t), (x, y + d / 2, z + t / 2), slot, "canopy")
	with kit.stage("walls"):
		for i in range(posts):
			px = x - w / 2 + 0.2 + (w - 0.4) * (i / (posts - 1) if posts > 1 else 0.5)
			kit.cyl(0.07, z, (px, y + d - 0.2, z / 2), post, "canopy_post", segs=10)


def portico(w, h, at, n=4, d=3.0, slot=STONE):
	"""A classical portico: columns, entablature and a pediment."""
	x, y = at
	with kit.stage("walls"):
		for i in range(n):
			px = x - w / 2 + 0.5 + (w - 1.0) * i / (n - 1)
			kit.cyl(0.38, h, (px, y + d - 0.5, h / 2 + 0.3), slot, "column", segs=14)
			kit.box((1.0, 1.0, 0.3), (px, y + d - 0.5, 0.15), slot, "column_base")
			kit.box((0.95, 0.95, 0.25), (px, y + d - 0.5, h + 0.3 + 0.125), slot, "capital")
		kit.box((w, d, 0.3), (x, y + d / 2, 0.15), slot, "portico_step")
		kit.box((w + 1.2, d + 0.6, 0.15), (x, y + d / 2 + 0.3, 0.075), slot, "portico_step_lower")
	with kit.stage("roof"):
		with kit.hollow(0.15):
			kit.box((w, d, 0.8), (x, y + d / 2, h + 0.55 + 0.4), slot, "entablature")
			kit.prism([(-w / 2 - 0.2, 0), (w / 2 + 0.2, 0), (0, w * 0.16)], d + 0.2, (x, y + d / 2, h + 1.35), slot, "pediment", axis="y")


def steps(w, at, n=4, tread=0.32, riser=0.16, slot=STONE):
	x, y = at
	with kit.stage("walls"):
		for i in range(n):
			kit.box((w, tread * (n - i), riser), (x, y + tread * (n - i) / 2, riser * (i + 0.5)), slot, "step")


def ground(w, d, at=(0, 0), slot="asphalt", name="yard", t=0.04):
	with kit.stage("ground"):
		kit.box((w, d, t), (at[0], at[1], t / 2), slot, name)


def car_bays(n, at, slot="paint_white", bay=2.5, depth=4.8):
	x, y = at
	with kit.stage("ground"):
		for i in range(n + 1):
			kit.box((0.1, depth, 0.01), (x - n * bay / 2 + i * bay, y, 0.05), slot, "bay_line")


def rooflights(m, n, w=1.2, d=2.0, z=0.0):
	with kit.stage("openings"):
		for i in range(n):
			kit.box((w, d, 0.12), (m.x - m.w / 2 + m.w * (i + 0.5) / n, m.y, m.z + m.h + z + 0.06), "glass", "rooflight")


def plant_room(m, w=4.0, d=3.0, h=2.2, u=0.0, v=0.0, z=0.5):
	with kit.stage("roof"):
		with kit.hollow(0.1):
			kit.box((w, d, h), (m.x + u, m.y + v, m.z + m.h + z + h / 2), "aluminium", "plant_room")
		kit.box((w * 0.5, 0.04, h * 0.5), (m.x + u, m.y + v + d / 2 + 0.01, m.z + m.h + z + h / 2), "steel_dark", "louvre")


# --- the building types --------------------------------------------------------------------

def corner_shop():
	m = Mass(9.0, 10.0, 6.2, walls="brick")
	m.gable("slate", ridge="x")
	m.chimney(-3.2, 0.0, 2.6)
	m.panel("f", -0.8, 1.45, 5.6, 2.3, "glass", "shopfront")
	m.panel("f", -0.8, 0.2, 5.8, 0.4, "plastic_green", "stall_riser", t=0.08)
	m.door("f", 3.2, 1.0, 2.2, "plastic_green")
	m.sign("f", 3.0, 8.6, 0.7, "plastic_green")
	m.panel("f", 0.0, 3.05, 5.0, 0.3, WHITE, "lettering", t=0.17)
	m.row("f", 4.8, 3, 1.1, 1.4, sill=STONE, head=STONE)
	m.panel("r", -1.5, 1.45, 4.0, 2.3, "glass", "side_shopfront")
	m.sign("r", 3.0, 9.6, 0.7, "plastic_green", name="side_fascia")
	m.row("r", 4.8, 3, 1.1, 1.4, sill=STONE, head=STONE)
	m.row("b", 4.8, 2, 1.0, 1.2, sill=STONE)
	m.door("b", -2.5, 0.9, 2.1, "steel_dark")
	with kit.stage("roof"):
		kit.prism([(0, 0), (1.6, -0.5), (1.6, -0.42), (0, 0.08)], 6.0, (-0.8, 5.0, 2.75), "fabric_green", "awning", axis="x")
	kit.socket("front_door", (3.2, 5.0, 0))


def holiday_lodge():
	m = Mass(11.0, 6.5, 2.6, walls="softwood")
	m.gable("roof_felt", pitch=0.28, ridge="x", over=0.6)
	m.panel("f", -2.2, 1.15, 3.2, 2.1, "glass", "patio_doors")
	m.panel("f", -2.2, 1.15, 0.08, 2.1, WHITE, "patio_mullion", t=0.09)
	m.door("f", 1.2, 0.9, 2.05, "hardwood")
	m.panel("f", 3.8, 1.5, 1.4, 1.1)
	m.row("b", 1.5, 4, 1.0, 1.0, sill="softwood")
	m.row("l", 1.5, 1, 1.4, 1.1)
	m.row("r", 1.5, 2, 0.9, 1.0)
	with kit.stage("walls"):
		kit.box((11.0, 3.0, 0.35), (0, 4.75, 0.175), "softwood", "deck")
		for i in range(12):
			kit.box((0.06, 0.06, 1.0), (-5.4 + i * 0.98, 6.2, 0.85), "softwood", "deck_baluster")
		kit.box((11.0, 0.1, 0.06), (0, 6.2, 1.35), "softwood", "deck_rail")
		for sx in (-1, 1):
			kit.box((0.1, 3.0, 0.06), (sx * 5.45, 4.75, 1.35), "softwood", "deck_side_rail")
			kit.box((0.1, 0.1, 1.0), (sx * 5.45, 3.4, 0.85), "softwood", "deck_post")
		kit.box((1.9, 1.9, 0.75), (3.6, 4.7, 0.72), "softwood", "hot_tub")
		kit.box((1.6, 1.6, 0.03), (3.6, 4.7, 1.1), "water", "hot_tub_water")
	with kit.stage("roof"):
		kit.cyl(0.09, 1.6, (-4.0, -1.0, 3.9), "steel_dark", "flue", segs=8)
	kit.socket("front_door", (1.2, 3.25, 0))


def housing_row(n=6):
	bay = 5.4
	m = Mass(bay * n, 9.0, 5.6, walls="brick")
	rise = m.gable("clay_tile", ridge="x")
	for i in range(n):
		u = -bay * n / 2 + bay * (i + 0.5)
		flip = 1 if i % 2 == 0 else -1
		m.door("f", u + flip * 1.5, 0.95, 2.1, ("plastic_blue", "plastic_red", "plastic_green", "plastic_black")[i % 4])
		m.panel("f", u - flip * 0.9, 1.5, 1.8, 1.4)
		m.panel("f", u - flip * 0.9, 0.73, 1.96, 0.1, STONE, "sill", t=0.12)
		m.panel("f", u - flip * 0.9, 4.2, 1.6, 1.25)
		m.panel("f", u + flip * 1.5, 4.2, 0.9, 1.25)
		m.panel("b", u, 1.5, 2.4, 2.0, "glass", "patio_doors")
		m.panel("b", u - 1.3, 4.2, 1.2, 1.2)
		m.panel("b", u + 1.3, 4.2, 1.2, 1.2)
		with kit.stage("roof"):
			kit.prism([(0, 0), (1.0, -0.25), (1.0, -0.19), (0, 0.06)], 1.5, (u + flip * 1.5, 4.5, 2.45), "clay_tile", "porch_roof", axis="x")
		if i < n - 1:
			m.chimney(u + bay / 2, 0.0, rise + 0.9, w=0.9)
			with kit.stage("walls"):
				kit.box((0.12, 0.08, 5.6), (u + bay / 2, 4.5, 2.8), STONE, "party_wall_line")
	kit.socket("front_door", (-bay * n / 2 + bay * 0.5 + 1.5, 4.5, 0))


def guest_house():
	m = Mass(12.0, 11.0, 8.6, walls="render")
	m.hip("slate")
	for sx in (-1, 1):
		with kit.stage("walls"):
			with kit.hollow(0.1):
				kit.prism([(-1.6, 0), (-1.0, 1.0), (1.0, 1.0), (1.6, 0)], 6.0, (sx * 3.6, 5.5, 3.0), "render", "bay", axis="z")
		with kit.stage("roof"):
			kit.prism([(-1.75, 0), (-1.1, 1.1), (1.1, 1.1), (1.75, 0)], 0.25, (sx * 3.6, 5.5, 6.12), "slate", "bay_roof", axis="z")
		with kit.stage("openings"):
			for f in range(2):
				kit.box((1.7, 0.06, 1.6), (sx * 3.6, 6.5, 1.6 + f * 2.9), "glass", "bay_window")
				for s2 in (-1, 1):
					kit.box((0.75, 0.06, 1.6), (sx * 3.6 + s2 * 1.32, 6.02, 1.6 + f * 2.9), "glass", "bay_side_window", rot=(0, 0, -s2 * 59))
	m.door("f", 0.0, 1.1, 2.3, "plastic_red")
	m.panel("f", 0.0, 4.5, 1.1, 1.6)
	m.row("f", 7.3, 3, 1.2, 1.3, sill=STONE)
	m.sign("f", 3.0, 2.6, 0.5, "plastic_black", name="sign")
	m.grid("b", 3, 2.9, 4, 1.1, 1.4, sill=STONE)
	m.grid("l", 3, 2.9, 3, 1.0, 1.4, sill=STONE)
	m.grid("r", 3, 2.9, 3, 1.0, 1.4, sill=STONE)
	m.chimney(-4.8, 0, 3.6)
	m.chimney(4.8, 0, 3.6)
	with kit.stage("roof"):
		kit.box((2.4, 1.6, 0.15), (0, 6.3, 2.75), WHITE, "porch_roof")
	with kit.stage("walls"):
		for sx in (-1, 1):
			kit.cyl(0.09, 2.7, (sx * 1.0, 6.9, 1.35), WHITE, "porch_column", segs=10)
	steps(2.4, (0, 5.5), 2)
	kit.socket("front_door", (0, 5.5, 0))


def pub():
	m = Mass(16.0, 10.0, 6.0, walls="render")
	rise = m.gable("slate", ridge="x")
	w2 = Mass(7.0, 6.0, 3.2, at=(-3.5, -8.0), walls="render", name="kitchen_wing")
	w2.gable("slate", ridge="y")
	m.chimney(-7.2, 0, rise + 1.2, w=1.0)
	m.chimney(7.2, 0, rise + 1.2, w=1.0)
	m.door("f", 0.0, 1.5, 2.2, "hardwood")
	m.row("f", 1.5, 4, 1.8, 1.5, skip=(), sill=STONE, margin=1.0)
	m.row("f", 4.5, 5, 1.1, 1.3, sill=STONE)
	m.band("f", 0.45, 0.9, "plastic_black", "plinth", t=0.05)
	m.sign("f", 3.05, 9.0, 0.6, "plastic_black")
	m.panel("f", 0.0, 3.05, 6.0, 0.28, "brass", "lettering", t=0.17)
	m.row("l", 1.5, 2, 1.4, 1.4, sill=STONE)
	m.row("r", 1.5, 2, 1.4, 1.4, sill=STONE)
	m.row("r", 4.5, 2, 1.1, 1.3, sill=STONE)
	m.row("b", 4.5, 4, 1.0, 1.2, sill=STONE)
	w2.door("l", 0.0, 0.9, 2.1, "steel_dark")
	with kit.stage("walls"):
		kit.box((0.18, 0.18, 5.5), (9.5, 7.0, 2.75), "hardwood", "sign_post")
		kit.box((1.6, 0.14, 0.14), (8.8, 7.0, 5.2), "hardwood", "sign_arm")
		kit.box((1.1, 0.08, 1.3), (8.7, 7.0, 4.4), "plastic_green", "hanging_sign")
		for i in range(3):
			x = 3.0 + i * 2.6
			kit.box((1.8, 0.8, 0.05), (x, 7.6, 0.75), "softwood", "bench_table")
			for sy in (-1, 1):
				kit.box((1.8, 0.28, 0.05), (x, 7.6 + sy * 0.7, 0.45), "softwood", "bench_seat")
				kit.box((0.08, 1.5, 0.45), (x + sy * 0.7, 7.6, 0.225), "softwood", "bench_leg")
	with kit.stage("openings"):
		for i in range(5):
			kit.box((0.7, 0.3, 0.3), (-6.4 + i * 3.2, 5.2, 3.6), "foliage", "hanging_basket")
	kit.socket("front_door", (0, 5.0, 0))


def industrial_unit():
	m = Mass(24.0, 18.0, 7.0, walls="steel_painted")
	m.shed("steel_galvanised", rise=1.6)
	m.band("f", 1.1, 2.2, "brick", "brick_plinth", t=0.05)
	m.band("l", 1.1, 2.2, "brick", "brick_plinth", t=0.05)
	m.band("r", 1.1, 2.2, "brick", "brick_plinth", t=0.05)
	m.panel("f", -6.0, 2.5, 5.0, 5.0, "steel_galvanised", "roller_door", t=0.1)
	for i in range(9):
		m.panel("f", -6.0, 0.4 + i * 0.55, 5.0, 0.04, "steel_dark", "roller_slat", t=0.12)
	m.door("f", -1.8, 1.0, 2.1, "plastic_blue")
	m.panel("f", 6.0, 1.6, 8.0, 1.6, "glass", "office_window")
	m.panel("f", 6.0, 4.6, 8.0, 1.4, "glass", "office_window_upper")
	m.door("f", 0.6, 1.0, 2.1, "glass", "office_door")
	m.sign("f", 6.3, 8.0, 0.9, "plastic_blue")
	m.door("b", 8.0, 1.0, 2.1, "hazard_red", "fire_exit")
	m.door("b", -8.0, 1.0, 2.1, "hazard_red", "fire_exit")
	rooflights(m, 6, 1.2, 3.0, z=0.9)
	ground(26.0, 12.0, (0, 15.0))
	car_bays(6, (5.0, 17.5))
	with kit.stage("walls"):
		for sx in (-1, 1):
			kit.cyl(0.08, 1.0, (-6.0 + sx * 2.9, 9.6, 0.5), "plastic_yellow", "bollard", segs=8)
	kit.socket("front_door", (0.6, 9.0, 0))


def retreat():
	hall = Mass(14.0, 10.0, 4.2, walls="softwood", name="hall")
	hall.gable("clay_tile", pitch=0.38, ridge="y", over=0.8)
	hall.panel("f", 0.0, 2.2, 9.0, 3.6, "glass", "great_window")
	for i in range(4):
		hall.panel("f", -4.5 + i * 3.0, 2.2, 0.14, 3.6, "glulam", "mullion", t=0.14)
	hall.door("f", 5.6, 1.0, 2.2, "hardwood")
	hall.row("l", 2.0, 3, 1.4, 2.0)
	hall.row("b", 2.0, 3, 1.6, 1.6)
	for sx in (-1, 1):
		wing = Mass(18.0, 7.0, 3.0, at=(sx * 16.0, -3.0), walls="render", name="bedroom_wing")
		wing.gable("clay_tile", ridge="x", over=0.5)
		wing.row("f", 1.4, 6, 1.4, 2.0, name="bedroom_doors")
		wing.row("b", 1.6, 6, 1.0, 1.0)
		wing.row("l" if sx < 0 else "r", 1.6, 2, 1.0, 1.2)
		with kit.stage("walls"):
			kit.box((18.0, 2.0, 0.2), (sx * 16.0, 1.5, 0.1), "softwood", "veranda")
			for i in range(7):
				kit.box((0.12, 0.12, 2.6), (sx * 16.0 - 8.8 + i * 2.93, 2.4, 1.5), "softwood", "veranda_post")
		with kit.stage("roof"):
			kit.box((18.4, 2.4, 0.1), (sx * 16.0, 1.5, 2.85), "clay_tile", "veranda_roof")
	spa = Mass(8.0, 8.0, 3.2, at=(0, -11.0), walls="softwood", name="spa")
	spa.hip("clay_tile")
	spa.row("l", 1.7, 2, 1.6, 1.8)
	spa.row("r", 1.7, 2, 1.6, 1.8)
	spa.row("b", 1.7, 2, 1.6, 1.8)
	link = Mass(3.0, 2.0, 2.6, at=(0, -6.0), walls="softwood", name="link")
	link.flat(0.2, "softwood")
	link.row("l", 1.3, 1, 1.4, 2.0)
	link.row("r", 1.3, 1, 1.4, 2.0)
	with kit.stage("ground"):
		kit.cyl(3.5, 0.3, (0, 11.0, 0.15), STONE, "pond_rim", segs=24)
		kit.cyl(3.1, 0.04, (0, 11.0, 0.3), "water", "pond", segs=24)
		kit.box((14.0, 4.0, 0.25), (0, 7.0, 0.125), "softwood", "terrace")
	kit.socket("front_door", (5.6, 5.0, 0))


def bus_station():
	c = Mass(34.0, 9.0, 5.0, walls="aluminium", name="concourse")
	c.flat(0.6, "aluminium")
	c.panel("f", 0.0, 2.3, 32.0, 3.6, "glass", "concourse_glazing")
	for i in range(9):
		c.panel("f", -16.0 + i * 4.0, 2.3, 0.12, 3.6, "steel_painted", "mullion", t=0.12)
	for i in range(8):
		c.panel("f", -14.0 + i * 4.0, 1.1, 1.6, 2.2, "plastic_blue", "stand_door", t=0.1)
	c.panel("b", 0.0, 2.3, 12.0, 3.6, "glass", "entrance_glazing")
	c.door("b", 0.0, 3.0, 2.4, "glass", "entrance")
	c.sign("b", 4.6, 10.0, 0.7, "plastic_blue")
	c.row("l", 2.5, 2, 2.4, 2.0)
	c.row("r", 2.5, 2, 2.4, 2.0)
	with kit.stage("roof"):
		kit.box((38.0, 9.0, 0.3), (0, 8.5, 5.75), "steel_painted", "stand_canopy")
		kit.box((36.0, 7.0, 0.05), (0, 8.5, 5.93), "glass", "canopy_rooflight")
		kit.cyl(0.9, 0.5, (0, -4.6, 6.4), WHITE, "clock", axis="y", segs=20)
	with kit.stage("walls"):
		for i in range(9):
			kit.cyl(0.14, 5.6, (-16.0 + i * 4.0, 12.3, 2.8), "steel_painted", "canopy_column", segs=10)
	with kit.stage("ground"):
		kit.box((60.0, 24.0, 0.04), (0, 24.0, 0.02), "asphalt", "apron")
		kit.box((38.0, 3.0, 0.14), (0, 6.0, 0.07), STONE, "platform")
		for i in range(8):
			x = -14.0 + i * 4.0
			for sx in (-1, 1):
				kit.box((0.15, 12.0, 0.01), (x + 2.9 + sx * 1.95, 14.6, 0.045), "paint_white", "bay_marking", rot=(0, 0, -30))
			kit.box((3.4, 0.12, 0.2), (x, 7.6, 0.14), "concrete", "bay_kerb")
	with kit.stage("openings"):
		for i in range(8):
			kit.box((1.0, 0.12, 0.5), (-14.0 + i * 4.0, 4.6, 4.0), "screen", "stand_display")
	for i, x in enumerate((-10.0, 2.0)):
		with kit.stage("ground"):
			with kit.hollow(0.1):
				kit.rounded_box((2.55, 11.5, 2.9), (x + 2.9, 14.6, 1.8), ("plastic_red", "plastic_green")[i], "bus", radius=0.25, rot=(0, 0, -30))
			kit.box((2.57, 9.5, 0.9), (x + 2.9, 14.6, 2.4), "glass_dark", "bus_windows", rot=(0, 0, -30))
	kit.socket("front_door", (0, -4.5, 0))


def shopping_parade(n=6):
	bay = 6.5
	w = bay * n
	m = Mass(w, 12.0, 7.2, walls="brick")
	m.flat(0.6)
	colours = ("plastic_red", "plastic_blue", "plastic_green", "plastic_yellow", "plastic_black", "hivis_orange")
	for i in range(n):
		u = -w / 2 + bay * (i + 0.5)
		m.panel("f", u - 0.7, 1.55, 4.2, 2.5, "glass", "shopfront")
		m.panel("f", u - 0.7, 0.2, 4.4, 0.4, "steel_dark", "stall_riser", t=0.08)
		m.door("f", u + 2.3, 1.0, 2.3, "glass", "shop_door", frame="aluminium")
		m.sign("f", 3.35, bay - 0.5, 0.8, colours[i % len(colours)], u)
		m.panel("f", u, 3.35, bay * 0.5, 0.3, WHITE, "lettering", t=0.17)
		m.panel("f", u - 1.5, 5.6, 1.6, 1.4)
		m.panel("f", u + 1.5, 5.6, 1.6, 1.4)
		m.door("b", u + 1.5, 1.0, 2.1, "steel_dark", "service_door")
		m.panel("b", u - 1.2, 5.6, 1.4, 1.2)
		with kit.stage("walls"):
			kit.box((0.4, 0.12, 3.9), (u - bay / 2, 6.04, 1.95), STONE, "pilaster")
	with kit.stage("walls"):
		kit.box((0.4, 0.12, 3.9), (w / 2, 6.04, 1.95), STONE, "pilaster")
	with kit.stage("roof"):
		kit.box((w + 0.4, 2.6, 0.2), (0, 7.3, 3.95), "steel_painted", "walkway_canopy")
	with kit.stage("walls"):
		for i in range(n + 1):
			kit.cyl(0.08, 3.85, (-w / 2 + i * bay, 8.4, 1.925), "steel_painted", "canopy_post", segs=8)
	ground(w + 6.0, 16.0, (0, 14.0))
	car_bays(int(w / 2.5) - 1, (0, 17.0))
	ground(w + 0.6, 3.0, (0, 7.5), STONE, "pavement", t=0.14)
	kit.socket("front_door", (-w / 2 + bay * 0.5 + 2.3, 6.0, 0))


def apartment_building(floors=5):
	fh = 3.0
	m = Mass(30.0, 16.0, fh * floors, walls="brick")
	m.flat(0.9)
	core = Mass(6.0, 4.0, fh * floors + 2.6, at=(0, 7.0), walls="render", name="stair_core")
	core.flat(0.3)
	core.panel("f", 0.0, (fh * floors) / 2 + 1.6, 2.4, fh * floors - 1.0, "glass", "stair_glazing")
	core.door("f", 0.0, 1.8, 2.3, "glass", "entrance", frame="aluminium")
	canopy(5.0, 2.2, 2.8, (0, 9.0))
	for f in range(floors):
		z = f * fh
		for sx in (-1, 1):
			for i in range(3):
				u = sx * (5.2 + i * 4.3)
				m.panel("f", u, z + 1.45, 2.4, 2.2, "glass", "balcony_door")
				with kit.stage("walls"):
					kit.box((3.4, 1.5, 0.18), (u, 8.75, z + 0.09 if f else 0.09), "concrete", "balcony_slab")
				with kit.stage("openings"):
					kit.box((3.4, 0.03, 1.05), (u, 9.48, z + 0.7), "glass", "balcony_front")
					for s2 in (-1, 1):
						kit.box((0.03, 1.44, 1.05), (u + s2 * 1.68, 8.72, z + 0.7), "glass", "balcony_side")
	m.grid("b", floors, fh, 8, 1.6, 1.5, sill=STONE)
	m.grid("l", floors, fh, 3, 1.4, 1.5, sill=STONE)
	m.grid("r", floors, fh, 3, 1.4, 1.5, sill=STONE)
	for f in range(1, floors):
		m.band("f", f * fh, 0.25, STONE, "floor_band", t=0.05)
		m.band("b", f * fh, 0.25, STONE, "floor_band", t=0.05)
	m.band("f", fh * floors - 1.6, 3.0, "aluminium", "top_cladding", t=0.05)
	plant_room(m, 5.0, 4.0, 2.4, u=-8.0, z=0.9)
	kit.socket("front_door", (0, 9.0, 0))


def council_offices(floors=3):
	fh = 3.8
	m = Mass(36.0, 16.0, fh * floors, walls=STONE)
	m.hip("slate", pitch=0.22)
	centre = Mass(11.0, 3.0, fh * floors + 1.2, at=(0, 9.5), walls=STONE, name="centre_bay")
	centre.flat(0.5, STONE)
	portico(9.0, fh * 2 - 0.6, (0, 11.0), 4, 3.0)
	centre.door("f", 0.0, 2.2, 3.0, "hardwood")
	centre.row("f", fh * 1.55, 3, 1.5, 2.4, sill=STONE)
	centre.row("f", fh * 2.5, 3, 1.5, 1.8, sill=STONE)
	for sx in (-1, 1):
		for f in range(floors):
			for i in range(4):
				u = sx * (7.2 + i * 3.0)
				m.panel("f", u, f * fh + fh * 0.55, 1.5, 2.3 if f < 2 else 1.7)
				m.panel("f", u, f * fh + fh * 0.55 - (1.2 if f < 2 else 0.9), 1.8, 0.12, WHITE, "sill", t=0.14)
	m.grid("b", floors, fh, 11, 1.5, 2.0, sill=WHITE)
	m.grid("l", floors, fh, 4, 1.5, 2.0, sill=WHITE)
	m.grid("r", floors, fh, 4, 1.5, 2.0, sill=WHITE)
	m.band("f", fh * floors - 0.3, 0.6, WHITE, "cornice", t=0.3)
	m.band("f", fh, 0.2, WHITE, "string_course", t=0.1)
	m.band("f", 0.5, 1.0, "concrete", "plinth", t=0.07)
	with kit.stage("roof"):
		kit.box((2.6, 2.6, 4.0), (0, 0, fh * floors + 4.0), STONE, "clock_tower")
		kit.cyl(0.9, 2.7, (0, 0, fh * floors + 5.0), WHITE, "clock_face", axis="y", segs=20)
		kit.lathe([(1.6, 0), (1.5, 0.5), (0.9, 1.4), (0.15, 2.0), (0.05, 3.2)], (0, 0, fh * floors + 6.0), "copper", "cupola", segs=12)
		kit.cyl(0.04, 5.0, (0, 9.5, fh * floors + 4.2), "steel_galvanised", "flagpole", segs=6)
		kit.box((1.6, 0.03, 0.9), (0.85, 9.5, fh * floors + 6.1), "plastic_blue", "flag")
	steps(11.0, (0, 14.0), 3)
	kit.socket("front_door", (0, 11.0, 0))


def cinema():
	box_ = Mass(34.0, 28.0, 11.0, at=(0, -6.0), walls="aluminium", name="auditoria")
	box_.flat(0.8, "aluminium")
	foyer = Mass(24.0, 9.0, 6.5, at=(0, 12.5), walls="glass_dark", name="foyer")
	foyer.flat(0.5, "aluminium")
	foyer.panel("f", 0.0, 3.2, 22.0, 5.6, "glass", "foyer_glazing")
	for i in range(8):
		foyer.panel("f", -11.0 + i * 3.14, 3.2, 0.12, 5.6, "aluminium", "mullion", t=0.12)
	for i in range(3):
		foyer.door("f", -3.0 + i * 3.0, 1.8, 2.4, "glass", "entrance", frame="aluminium")
	foyer.row("l", 3.2, 1, 6.0, 5.0)
	foyer.row("r", 3.2, 1, 6.0, 5.0)
	with kit.stage("roof"):
		kit.box((18.0, 3.5, 0.5), (0, 18.6, 3.6), "plastic_black", "marquee")
		kit.box((18.2, 0.12, 1.6), (0, 20.4, 4.4), "light_emitter", "marquee_readograph")
		kit.box((1.4, 1.2, 10.0), (-9.0, 17.4, 10.0), "hazard_red", "sign_fin")
		kit.box((0.7, 1.24, 8.0), (-9.0, 17.4, 10.2), "light_emitter", "sign_fin_letters")
	for i in range(5):
		box_.panel("f", -15.0 + i * 2.2, 5.0, 1.6, 2.4, "screen", "poster_case", t=0.12)
		box_.panel("f", 15.0 - i * 2.2, 5.0, 1.6, 2.4, "screen", "poster_case", t=0.12) if i < 2 else None
	box_.band("f", 9.6, 1.4, "plastic_red", "stripe", t=0.05)
	box_.band("l", 9.6, 1.4, "plastic_red", "stripe", t=0.05)
	box_.band("r", 9.6, 1.4, "plastic_red", "stripe", t=0.05)
	for i in range(4):
		box_.door("b", -12.0 + i * 8.0, 1.8, 2.2, "steel_dark", "exit")
		box_.door("l" if i % 2 else "r", -6.0 + (i // 2) * 12.0, 1.8, 2.2, "steel_dark", "exit")
	plant_room(box_, 8.0, 5.0, 2.6, u=6.0, v=-4.0, z=0.8)
	plant_room(box_, 6.0, 4.0, 2.2, u=-8.0, v=2.0, z=0.8)
	kit.socket("front_door", (0, 17.0, 0))


def hotel(floors=6):
	fh = 3.1
	pod = Mass(44.0, 20.0, 4.6, walls=STONE, name="podium")
	pod.flat(0.5, STONE)
	t = Mass(40.0, 15.0, fh * (floors - 1), at=(0, -1.5), z=4.6, walls="render", name="bedroom_block")
	t.flat(1.0, "render")
	pod.panel("f", 0.0, 2.3, 22.0, 3.6, "glass", "lobby_glazing")
	for i in range(8):
		pod.panel("f", -11.0 + i * 3.14, 2.3, 0.1, 3.6, "aluminium", "mullion", t=0.1)
	pod.door("f", 0.0, 3.2, 2.5, "glass", "revolving_entrance", frame="brass")
	for sx in (-1, 1):
		pod.panel("f", sx * 16.5, 2.3, 8.0, 3.0, "glass", "restaurant_window")
	pod.row("l", 2.3, 3, 3.5, 2.6)
	pod.row("r", 2.3, 3, 3.5, 2.6)
	n = 12
	for face in "fb":
		t.grid(face, floors - 1, fh, n, 1.9, 1.9, sill="aluminium")
		for i in range(n + 1):
			t.panel(face, -20.0 + i * 40.0 / n, fh * (floors - 1) / 2, 0.35, fh * (floors - 1), STONE, "pier", t=0.2)
	t.grid("l", floors - 1, fh, 1, 1.6, 1.9)
	t.grid("r", floors - 1, fh, 1, 1.6, 1.9)
	with kit.stage("roof"):
		kit.box((12.0, 5.0, 0.35), (0, 12.5, 4.2), "steel_dark", "porte_cochere")
		kit.box((12.2, 0.12, 0.7), (0, 15.0, 4.4), "brass", "porte_cochere_fascia")
		kit.box((10.0, 0.3, 1.6), (0, 6.0, 4.6 + fh * (floors - 1) + 1.9), "light_emitter", "roof_sign")
	with kit.stage("walls"):
		for sx in (-1, 1):
			for sy in (10.6, 14.4):
				kit.box((0.4, 0.4, 4.0), (sx * 5.4, sy, 2.0), STONE, "porte_cochere_column")
	plant_room(t, 8.0, 5.0, 2.6, u=-10.0, z=1.0)
	plant_room(t, 5.0, 4.0, 3.2, u=12.0, z=1.0)
	ground(30.0, 8.0, (0, 14.0), "paving", "forecourt")
	kit.socket("front_door", (0, 10.0, 0))


def business_centre(floors=3):
	fh = 3.6
	m = Mass(40.0, 16.0, fh * floors, walls="brick")
	m.flat(0.7, "aluminium")
	atrium = Mass(8.0, 4.0, fh * floors + 1.0, at=(0, 9.0), walls="glass_dark", name="atrium")
	atrium.flat(0.3, "aluminium")
	atrium.panel("f", 0.0, (fh * floors + 1.0) / 2, 7.2, fh * floors, "glass", "atrium_glazing")
	for i in range(1, floors + 1):
		atrium.panel("f", 0.0, i * fh, 7.4, 0.14, "aluminium", "transom", t=0.1)
	for i in range(5):
		atrium.panel("f", -3.6 + i * 1.8, (fh * floors + 1.0) / 2, 0.1, fh * floors, "aluminium", "mullion", t=0.1)
	atrium.door("f", 0.0, 2.0, 2.4, "glass", "entrance", frame="aluminium")
	canopy(6.0, 2.5, 3.0, (0, 11.0), "aluminium")
	for face, span in (("f", 40.0), ("b", 40.0)):
		for f in range(floors):
			for sx in (-1, 1):
				if face == "f":
					m.panel(face, sx * 12.0, f * fh + fh * 0.58, 14.5, 1.9, "glass", "ribbon_window")
				else:
					m.panel(face, sx * 10.0, f * fh + fh * 0.58, 18.0, 1.9, "glass", "ribbon_window")
		for f in range(1, floors):
			m.band(face, f * fh, 0.3, "aluminium", "spandrel", t=0.05)
	for face in "lr":
		for f in range(floors):
			m.panel(face, 0.0, f * fh + fh * 0.58, 12.0, 1.9, "glass", "ribbon_window")
	m.sign("f", fh * floors - 0.5, 6.0, 0.7, "plastic_blue", u=-14.0, name="sign")
	plant_room(m, 7.0, 5.0, 2.4, u=10.0, z=0.7)
	with kit.stage("walls"):
		kit.box((2.4, 0.3, 3.0), (14.0, 16.0, 1.5), "aluminium", "tenant_totem")
		kit.box((2.0, 0.34, 2.2), (14.0, 16.0, 1.7), "plastic_blue", "tenant_panels")
	ground(44.0, 16.0, (0, 21.0))
	car_bays(14, (0, 25.0))
	kit.socket("front_door", (0, 11.0, 0))


def theatre():
	aud = Mass(26.0, 24.0, 14.0, at=(0, -2.0), walls="brick", name="auditorium")
	aud.hip("slate", pitch=0.2)
	fly = Mass(22.0, 14.0, 24.0, at=(0, -19.0), walls="brick", name="fly_tower")
	fly.flat(0.8, "brick")
	front = Mass(28.0, 8.0, 12.0, at=(0, 14.0), walls=STONE, name="front_of_house")
	front.flat(1.0, STONE)
	for i in range(5):
		u = -8.0 + i * 4.0
		front.door("f", u, 2.2, 2.8, "hardwood", "entrance", frame="brass")
		front.panel("f", u, 7.4, 2.2, 4.4, "glass", "foyer_window")
		with kit.stage("roof"):
			kit.cyl(1.1, 0.12, (u, 18.05, 9.6), "glass", "arched_head", axis="y", segs=16)
	for i in range(6):
		front.panel("f", -10.0 + i * 4.0, 7.0, 0.8, 9.0, STONE, "pilaster", t=0.35)
	front.band("f", 11.4, 0.9, WHITE, "cornice", t=0.5)
	front.band("f", 4.3, 0.4, WHITE, "string_course", t=0.2)
	front.row("l", 7.4, 2, 1.8, 3.6)
	front.row("r", 7.4, 2, 1.8, 3.6)
	with kit.stage("roof"):
		kit.box((24.0, 3.4, 0.4), (0, 19.7, 3.9), "plastic_black", "canopy")
		kit.box((24.2, 0.14, 1.0), (0, 21.45, 4.2), "light_emitter", "canopy_lights")
		kit.prism([(-9.0, 0), (9.0, 0), (0, 3.0)], 0.8, (0, 17.6, 13.0), STONE, "pediment", axis="y")
		kit.box((1.2, 0.5, 9.0), (15.0, 17.0, 9.0), "hazard_red", "vertical_sign")
		kit.box((0.6, 0.54, 7.6), (15.0, 17.0, 9.0), "light_emitter", "vertical_sign_letters")
	fly.door("b", 0.0, 4.0, 5.0, "steel_dark", "scene_dock")
	fly.door("b", 8.0, 1.0, 2.1, "steel_dark", "stage_door")
	aud.row("l", 3.0, 3, 1.8, 2.2, "steel_dark", "exit_doors")
	aud.row("r", 3.0, 3, 1.8, 2.2, "steel_dark", "exit_doors")
	for sx in "lr":
		aud.row(sx, 9.0, 4, 1.2, 2.4)
	steps(26.0, (0, 18.0), 3)
	kit.socket("front_door", (0, 18.0, 0))


def law_courts():
	m = Mass(48.0, 26.0, 13.0, walls=STONE)
	m.flat(1.2, STONE)
	portico(22.0, 10.0, (0, 13.0), 8, 4.0)
	m.door("f", 0.0, 3.0, 4.2, "hardwood", "great_door", frame="brass")
	for sx in (-1, 1):
		m.door("f", sx * 6.0, 1.6, 3.0, "hardwood", "side_door", frame=STONE)
		for f in range(3):
			for i in range(4):
				u = sx * (13.5 + i * 3.2)
				m.panel("f", u, 2.4 + f * 4.0, 1.5, 2.6 if f < 2 else 1.6)
				m.panel("f", u, 2.4 + f * 4.0 - (1.4 if f < 2 else 0.9), 1.9, 0.14, WHITE, "sill", t=0.16)
		for i in range(5):
			m.panel("f", sx * (11.9 + i * 3.2), 6.5, 0.6, 11.5, STONE, "pilaster", t=0.3)
	m.band("f", 12.4, 1.0, WHITE, "cornice", t=0.5)
	m.band("l", 12.4, 1.0, WHITE, "cornice", t=0.5)
	m.band("r", 12.4, 1.0, WHITE, "cornice", t=0.5)
	m.band("f", 0.6, 1.2, "concrete", "rusticated_plinth", t=0.1)
	m.grid("b", 3, 4.0, 13, 1.5, 2.2, z0=2.4, sill=WHITE)
	m.grid("l", 3, 4.0, 6, 1.5, 2.2, z0=2.4, sill=WHITE)
	m.grid("r", 3, 4.0, 6, 1.5, 2.2, z0=2.4, sill=WHITE)
	with kit.stage("roof"):
		with kit.hollow(0.1):
			kit.cyl(6.0, 3.0, (0, 0, 15.7), STONE, "drum", segs=24)
			kit.lathe([(6.2, 0), (5.9, 1.6), (4.8, 3.4), (3.0, 4.8), (0.8, 5.5), (0.6, 6.5), (0.05, 7.6)], (0, 0, 17.2), "copper", "dome", segs=24)
		for i in range(12):
			a = math.radians(i * 30)
			kit.box((0.8, 0.06, 1.7), (6.0 * math.sin(a), 6.0 * math.cos(a), 15.8), "glass", "drum_window", rot=(0, 0, -i * 30))
	m.door("b", 16.0, 3.5, 3.6, "steel_dark", "custody_gate")
	steps(26.0, (0, 17.3), 4, tread=0.4)
	kit.socket("front_door", (0, 13.0, 0))


def mansion_house():
	m = Mass(26.0, 14.0, 10.4, walls="brick", name="main_block")
	m.hip("slate", pitch=0.24)
	for sx in (-1, 1):
		w = Mass(11.0, 10.0, 7.0, at=(sx * 18.5, -1.0), walls="brick", name="wing")
		w.hip("slate", pitch=0.26)
		w.grid("f", 2, 3.5, 3, 1.3, 2.2, sill=STONE, head=STONE)
		w.grid("b", 2, 3.5, 3, 1.3, 2.0, sill=STONE)
		w.grid("l" if sx < 0 else "r", 2, 3.5, 3, 1.3, 2.0, sill=STONE)
		w.band("f", 6.7, 0.5, STONE, "cornice", t=0.3)
		w.chimney(sx * 3.0, 0, 3.6, w=1.2)
		with kit.stage("walls"):
			kit.box((0.5, 0.2, 7.0), (sx * 13.0, 4.05, 3.5), STONE, "quoin")
			kit.box((0.5, 0.2, 7.0), (sx * 24.0, 4.05, 3.5), STONE, "quoin")
	portico(9.0, 6.6, (0, 7.0), 4, 3.0)
	m.door("f", 0.0, 1.8, 3.0, "hardwood", "front_door", frame=STONE)
	for f in range(3):
		ph = (2.4, 2.4, 1.5)[f]
		z = (2.2, 5.8, 8.9)[f]
		for sx in (-1, 1):
			for i in range(3):
				u = sx * (5.6 + i * 3.0)
				m.panel("f", u, z, 1.4, ph)
				m.panel("f", u, z - ph / 2 - 0.06, 1.7, 0.12, STONE, "sill", t=0.14)
				m.panel("f", u, z + ph / 2 + 0.12, 1.7, 0.24, STONE, "lintel", t=0.1)
		if f:
			m.panel("f", 0.0, z, 1.6, ph)
	m.grid("b", 3, 3.4, 8, 1.4, 2.0, sill=STONE, head=STONE, skip=(3, 4))
	m.panel("b", 0.0, 1.5, 4.0, 2.8, "glass", "garden_doors")
	m.band("f", 10.0, 0.8, STONE, "cornice", t=0.45)
	m.band("b", 10.0, 0.8, STONE, "cornice", t=0.45)
	m.band("f", 0.45, 0.9, STONE, "plinth", t=0.08)
	for sx in (-1, 1):
		with kit.stage("walls"):
			kit.box((0.6, 0.22, 10.4), (sx * 12.7, 7.05, 5.2), STONE, "quoin")
		m.chimney(sx * 9.0, 0, 5.2, w=1.5)
		m.chimney(sx * 3.5, -2.0, 5.6, w=1.2)
	for i in range(3):
		m.dormer(-7.0 + i * 7.0, 0.5, 1.4, "slate")
	with kit.stage("ground"):
		kit.cyl(7.0, 0.05, (0, 19.0, 0.025), "sand", "carriage_circle", segs=28)
		kit.cyl(2.2, 0.4, (0, 19.0, 0.2), STONE, "fountain_basin", segs=20)
		kit.cyl(1.9, 0.04, (0, 19.0, 0.4), "water", "fountain_water", segs=20)
		kit.lathe([(0.3, 0), (0.2, 0.8), (0.9, 1.0), (0.15, 1.1), (0.1, 1.8), (0.02, 2.0)], (0, 19.0, 0.4), STONE, "fountain", segs=12)
	kit.socket("front_door", (0, 7.0, 0))


def retail_park(units=4):
	widths = (26.0, 18.0, 18.0, 30.0)[:units]
	total = sum(widths)
	colours = ("plastic_blue", "plastic_red", "plastic_green", "hivis_orange")
	x = -total / 2
	for i, w in enumerate(widths):
		m = Mass(w - 0.05, 30.0, 8.5, at=(x + w / 2, -8.0), walls="steel_painted", name="unit")
		m.flat(0.8, "steel_painted", "steel_galvanised")
		m.panel("f", 0.0, 2.0, w * 0.55, 3.6, "glass", "shopfront")
		m.door("f", 0.0, 3.6, 2.6, "glass", "entrance", frame="aluminium")
		m.panel("f", 0.0, 6.4, w * 0.75, 2.6, colours[i % 4], "sign_board", t=0.25)
		m.panel("f", 0.0, 6.4, w * 0.5, 1.0, WHITE, "lettering", t=0.3)
		m.band("f", 0.5, 1.0, "brick", "plinth", t=0.05)
		m.panel("b", 0.0, 2.4, 4.5, 4.8, "steel_galvanised", "service_door", t=0.1)
		m.door("b", w * 0.3, 1.0, 2.1, "hazard_red", "fire_exit")
		with kit.stage("walls"):
			kit.box((0.5, 0.5, 9.6), (x, 7.1, 4.8), "aluminium", "feature_pier")
		x += w
	with kit.stage("walls"):
		kit.box((0.5, 0.5, 9.6), (x, 7.1, 4.8), "aluminium", "feature_pier")
		for i in range(int(total / 6.0) + 1):
			kit.cyl(0.09, 4.2, (-total / 2 + i * total / int(total / 6.0), 10.3, 2.1), "steel_painted", "canopy_post", segs=8)
		kit.box((0.6, 0.6, 9.0), (-total / 2 + 3.0, 44.0, 4.5), "aluminium", "totem")
		for i in range(units):
			kit.box((3.6, 0.7, 1.3), (-total / 2 + 3.0, 44.0, 8.0 - i * 1.5), colours[i % 4], "totem_panel")
	with kit.stage("roof"):
		kit.box((total, 3.6, 0.25), (0, 8.8, 4.3), "steel_painted", "walkway_canopy")
	ground(total + 8.0, 39.6, (0, 27.2))
	ground(total, 3.0, (0, 9.1), STONE, "pavement", t=0.14)
	for r in range(3):
		car_bays(int((total - 8.0) / 2.5), (0, 17.0 + r * 10.0), depth=9.6)
		with kit.stage("ground"):
			for i in range(5):
				kit.cyl(0.08, 6.0, (-total / 2 + 6.0 + i * (total - 12.0) / 4, 17.0 + r * 10.0, 3.0), "steel_galvanised", "lamp_column", segs=6)
				kit.box((1.2, 0.3, 0.12), (-total / 2 + 6.0 + i * (total - 12.0) / 4, 17.0 + r * 10.0, 6.0), "steel_galvanised", "lantern")
	with kit.stage("ground"):
		for i in range(4):
			kit.box((2.4, 5.0, 2.2), (-total / 2 + 12.0 + i * 5.0, 12.5, 1.14), "glass", "trolley_shelter")
	kit.socket("front_door", (-total / 2 + widths[0] / 2, 7.0, 0))


def train_station():
	m = Mass(46.0, 14.0, 9.0, walls="brick", name="station_building")
	m.hip("slate", pitch=0.2)
	tower = Mass(6.0, 6.0, 20.0, at=(-15.0, 6.0), walls="brick", name="clock_tower")
	tower.hip("slate", pitch=0.9, over=0.5)
	for face in "fblr":
		tower.panel(face, 0.0, 16.5, 3.0, 3.0, WHITE, "clock_face", t=0.14)
		tower.panel(face, 0.0, 16.5, 0.14, 1.2, "plastic_black", "clock_hand", t=0.2)
		tower.panel(face, 0.0, 9.0, 1.2, 3.0)
	for i in range(3):
		u = 2.0 + i * 5.0 - 5.0
		m.door("f", u, 3.2, 4.4, "glass", "entrance_arch", frame=STONE)
		with kit.stage("roof"):
			kit.cyl(1.68, 0.14, (u, 7.03, 4.44), "glass", "arch_head", axis="y", segs=18)
	m.row("f", 6.9, 9, 1.4, 1.8, sill=STONE, head=STONE, margin=1.0)
	for u in (-8.0, 14.0, 19.0):
		m.panel("f", u, 2.6, 2.0, 3.4)
		m.panel("f", u, 0.84, 2.3, 0.14, STONE, "sill", t=0.16)
	m.band("f", 8.7, 0.6, STONE, "cornice", t=0.4)
	m.band("f", 5.2, 0.3, STONE, "string_course", t=0.15)
	m.sign("f", 5.75, 12.0, 0.8, "plastic_blue", u=2.0)
	m.row("l", 3.0, 2, 1.8, 3.0)
	m.row("r", 3.0, 2, 1.8, 3.0)
	for i in range(5):
		m.door("b", -18.0 + i * 9.0, 2.4, 3.0, "glass", "platform_door", frame=STONE)
	with kit.stage("roof"):
		kit.box((20.0, 4.0, 0.3), (2.0, 9.0, 5.0), "steel_painted", "entrance_canopy")
		kit.box((19.0, 3.4, 0.05), (2.0, 9.0, 5.18), "glass", "entrance_canopy_glass")
	with kit.stage("walls"):
		for i in range(5):
			kit.cyl(0.1, 4.9, (-7.5 + i * 4.75, 10.7, 2.45), "cast_iron", "canopy_column", segs=10)
	# Train shed behind: arched roof over two island platforms and four tracks.
	L, span = 70.0, 30.0
	arch = [(span / 2 * math.cos(math.radians(a)), 9.0 * math.sin(math.radians(a))) for a in range(0, 181, 12)]
	inner = [((span / 2 - 0.25) * math.cos(math.radians(a)), (9.0 - 0.25) * math.sin(math.radians(a))) for a in range(180, -1, -12)]
	with kit.stage("roof"):
		with kit.hollow(0.5):
			kit.prism(arch + inner, L, (0, -7.0 - span / 2, 5.0), "glass", "train_shed_roof", axis="x")
		for i in range(8):
			kit.prism(arch + inner, 0.3, (-L / 2 + 0.2 + i * (L - 0.4) / 7, -7.0 - span / 2, 5.02), "steel_painted", "shed_rib", axis="x")
	with kit.stage("walls"):
		for i in range(8):
			for sy in (-1, 1):
				kit.box((0.4, 0.4, 5.0), (-L / 2 + 0.2 + i * (L - 0.4) / 7, -7.0 - span / 2 + sy * (span / 2 - 0.2), 2.5), "cast_iron", "shed_column")
	with kit.stage("ground"):
		kit.box((L, span, 0.05), (0, -22.0, 0.025), "soil", "ballast")
		for py in (-10.0, -22.0, -34.0):
			pw = 6.0 if py == -22.0 else 5.0
			kit.box((L, pw, 1.0), (0, py, 0.5), "concrete", "platform")
			kit.box((L, 0.3, 0.02), (0, py + pw / 2 - 0.5, 1.01), "plastic_yellow", "platform_line")
			kit.box((L, 0.3, 0.02), (0, py - pw / 2 + 0.5, 1.01), "plastic_yellow", "platform_line")
		for ty in (-14.6, -17.4, -26.6, -29.4):
			for sy in (-1, 1):
				kit.box((L, 0.08, 0.16), (0, ty + sy * 0.72, 0.2), "steel_dark", "rail")
			for i in range(0, 70, 2):
				kit.box((0.26, 2.5, 0.12), (-L / 2 + 1.0 + i, ty, 0.1), "concrete", "sleeper")
		with kit.hollow(0.15):
			kit.rounded_box((46.0, 2.8, 3.2), (-6.0, -14.6, 2.2), "plastic_blue", "train", radius=0.3)
		kit.box((44.0, 2.84, 0.9), (-6.0, -14.6, 2.7), "glass_dark", "train_windows")
	kit.socket("front_door", (2.0, 7.0, 0))


def prison():
	W, D = 96.0, 90.0
	with kit.stage("walls"):
		with kit.hollow(0.5):
			for sx in (-1, 1):
				kit.box((0.5, D, 5.4), (sx * W / 2, 0, 2.7), "concrete", "perimeter_wall")
			kit.box((W, 0.5, 5.4), (0, -D / 2, 2.7), "concrete", "perimeter_wall")
			for sx in (-1, 1):
				kit.box((W / 2 - 7.0, 0.5, 5.4), (sx * (W / 4 + 3.5), D / 2, 2.7), "concrete", "perimeter_wall")
	with kit.stage("roof"):
		for sx in (-1, 1):
			kit.cyl(0.45, D, (sx * W / 2, 0, 5.6), "steel_galvanised", "anti_climb_cowl", axis="y", segs=10)
			kit.cyl(0.45, W / 2 - 7.0, (sx * (W / 4 + 3.5), D / 2, 5.6), "steel_galvanised", "anti_climb_cowl", axis="x", segs=10)
		kit.cyl(0.45, W, (0, -D / 2, 5.6), "steel_galvanised", "anti_climb_cowl", axis="x", segs=10)
	gate = Mass(14.0, 10.0, 8.0, at=(0, D / 2 - 1.0), walls="brick", name="gatehouse")
	gate.flat(0.8, "brick")
	gate.panel("f", -2.5, 2.4, 5.0, 4.8, "plastic_blue", "vehicle_gate", t=0.14)
	gate.door("f", 3.5, 1.2, 2.2, "steel_dark", "visitor_door")
	gate.row("f", 6.2, 4, 1.2, 1.0)
	gate.sign("f", 7.3, 8.0, 0.5, "plastic_black", name="sign")
	hub = Mass(16.0, 16.0, 12.0, at=(0, -4.0), walls="brick", name="control_hub")
	hub.hip("slate", pitch=0.25)
	hub.row("f", 9.5, 4, 1.4, 1.6)
	hub.row("b", 9.5, 4, 1.4, 1.6)
	for k, (dx, dy) in enumerate(((1, 0), (-1, 0), (0, -1), (0.72, 0.72), (-0.72, 0.72))):
		diag = dx and dy
		if diag:
			continue
		horiz = bool(dx)
		length = 30.0 if horiz else 26.0
		at = (dx * (8.0 + length / 2), -4.0 + dy * (8.0 + length / 2)) if not diag else (0, 0)
		wing = Mass(length if horiz else 12.0, 12.0 if horiz else length, 11.2, at=at, walls="brick", name="cell_wing")
		wing.gable("slate", pitch=0.28, ridge="x" if horiz else "y")
		faces = "fb" if horiz else "lr"
		for face in faces:
			wing.grid(face, 4, 2.8, int(length / 2.4), 0.5, 0.9, "glass_dark", "cell_window", z0=1.9, sill=STONE)
		end = ("r" if dx > 0 else "l") if horiz else "b"
		wing.row(end, 6.0, 1, 2.4, 7.0, "glass", "wing_end_window")
		wing.door(end, 0.0, 1.4, 2.2, "steel_dark", "yard_door")
	visits = Mass(22.0, 12.0, 4.5, at=(-26.0, 28.0), walls="brick", name="visits_and_admin")
	visits.gable("slate", ridge="x")
	visits.row("f", 2.4, 6, 1.4, 1.4, sill=STONE)
	visits.row("b", 2.4, 6, 1.4, 1.4, sill=STONE)
	work = Mass(26.0, 14.0, 6.0, at=(26.0, 28.0), walls="steel_painted", name="workshops")
	work.shed("steel_galvanised", rise=1.4)
	work.row("f", 4.4, 6, 2.4, 1.0)
	work.panel("b", 0.0, 2.0, 4.0, 4.0, "steel_galvanised", "roller_door", t=0.1)
	kitchen = Mass(16.0, 12.0, 5.0, at=(0, 26.0), walls="brick", name="kitchen_and_reception")
	kitchen.flat(0.5, "brick")
	kitchen.row("f", 2.6, 4, 1.4, 1.4)
	with kit.stage("ground"):
		kit.box((W - 1.0, D - 1.0, 0.03), (0, 0, 0.015), "asphalt", "compound")
		kit.box((24.0, 18.0, 0.02), (-30.0, -28.0, 0.04), "plastic_green", "exercise_yard")
		kit.box((24.0, 18.0, 0.02), (30.0, -28.0, 0.04), "plastic_green", "sports_pitch")
	with kit.stage("walls"):
		for sx, sy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
			with kit.hollow(0.2):
				kit.box((3.0, 3.0, 9.0), (sx * (W / 2 - 1.5), sy * (D / 2 - 1.5), 4.5), "concrete", "watch_tower")
				kit.box((4.4, 4.4, 2.6), (sx * (W / 2 - 1.5), sy * (D / 2 - 1.5), 10.3), "glass_dark", "watch_cabin")
			kit.box((5.0, 5.0, 0.25), (sx * (W / 2 - 1.5), sy * (D / 2 - 1.5), 11.72), "steel_painted", "watch_roof")
		for sx in (-1, 1):
			for i in range(13):
				kit.cyl(0.05, 4.0, (sx * 18.0, -37.0 + i * 1.5, 2.0), "steel_galvanised", "yard_fence_post", segs=6)
			kit.box((0.03, 18.0, 3.9), (sx * 18.0, -28.0, 2.0), "steel_galvanised", "yard_fence")
	kit.socket("front_door", (3.5, D / 2 + 4.0, 0))


_TYPES = (
	("corner_shop", corner_shop, "Corner shop", dict()),
	("holiday_lodge", holiday_lodge, "Holiday lodge", dict()),
	("housing_row", housing_row, "Row of houses", dict()),
	("guest_house", guest_house, "Guest house", dict()),
	("pub", pub, "Pub", dict()),
	("industrial_unit", industrial_unit, "Industrial unit", dict()),
	("retreat", retreat, "Retreat", dict()),
	("bus_station", bus_station, "Bus station", dict()),
	("shopping_parade", shopping_parade, "Shopping parade", dict()),
	("apartment_building", apartment_building, "Apartment building", dict()),
	("council_offices", council_offices, "Council offices", dict()),
	("cinema", cinema, "Cinema", dict()),
	("hotel", hotel, "Hotel", dict()),
	("business_centre", business_centre, "Business centre", dict()),
	("theatre", theatre, "Theatre", dict()),
	("law_courts", law_courts, "Law courts", dict()),
	("mansion_house", mansion_house, "Mansion house", dict()),
	("retail_park", retail_park, "Retail park", dict()),
	("train_station", train_station, "Train station", dict()),
	("prison", prison, "Prison", dict()),
)

for _id, _fn, _lab, _kw in _TYPES:
	reg("context.type." + _id, _fn, _lab, **_kw)
