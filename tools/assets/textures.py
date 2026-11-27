"""Makes the realistic look's tiling surface textures (needs numpy and Pillow):

    python3 tools/assets/textures.py

Writes modules/assets/internal/textures/<pattern>_a.png (a grey detail map the slot's colour
is multiplied by) and <pattern>_n.png (its normal map), 512 px, seamless. Each covers SIZE
metres; the game maps them triplanar, so no model needs UVs. PATTERN_OF says which pattern a
material slot gets; build.py writes that into internal/materials.json for the game.
"""
import os

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "modules", "assets", "internal", "textures")
N = 512

# pattern -> metres one repeat covers
SIZE = {"brick": 0.9, "block": 0.9, "concrete": 2.0, "timber": 0.8, "plywood": 1.2, "fabric": 0.2, "carpet": 0.4, "stone": 1.6,
	"slate": 1.0, "tile": 1.2, "asphalt": 0.8, "soil": 1.5, "render": 1.5, "paving": 0.9, "brushed": 0.5, "galv": 0.6,
	"paint": 1.0, "clad": 1.0, "foliage": 0.7, "marble": 1.6, "leather": 0.25, "grass": 1.0}


def noise(seed, falloff=1.6, stretch=(1.0, 1.0)):
	"""Seamless noise 0..1 from a power-law spectrum; stretch > 1 squeezes detail along that axis."""
	rng = np.random.default_rng(seed)
	ky = np.fft.fftfreq(N)[:, None] * N * stretch[0]
	kx = np.fft.fftfreq(N)[None, :] * N * stretch[1]
	k = np.hypot(kx, ky)
	k[0, 0] = 1.0
	f = (rng.normal(size=(N, N)) + 1j * rng.normal(size=(N, N))) / k ** falloff
	f[0, 0] = 0.0
	n = np.fft.ifft2(f).real
	n -= n.min()
	return n / n.max()


def cells(seed, count):
	"""Seamless Voronoi: (cell id per pixel, distance to the nearest cell edge in pixels)."""
	rng = np.random.default_rng(seed)
	pts = rng.uniform(0, N, size=(count, 2))
	yy, xx = np.mgrid[0:N, 0:N]
	d1 = np.full((N, N), 1e9)
	d2 = np.full((N, N), 1e9)
	ident = np.zeros((N, N), dtype=int)
	for i, (px, py) in enumerate(pts):
		dx = np.abs(xx - px)
		dy = np.abs(yy - py)
		d = np.hypot(np.minimum(dx, N - dx), np.minimum(dy, N - dy))
		closer = d < d1
		d2 = np.where(closer, d1, np.minimum(d2, d))
		ident = np.where(closer, i, ident)
		d1 = np.where(closer, d, d1)
	return ident, (d2 - d1) / 2.0


def courses(rows, per_row, joint, seed, stagger=0.5, jitter=0.0):
	"""Coursed units (bricks, blocks, slates): (unit id, distance to the joint in pixels)."""
	rng = np.random.default_rng(seed)
	yy, xx = np.mgrid[0:N, 0:N].astype(float)
	h, w = N / rows, N / per_row
	row = np.floor(yy / h).astype(int)
	shift = (row % 2) * stagger * w + (rng.uniform(-jitter, jitter, rows)[row % rows] * w if jitter else 0.0)
	col = np.floor(((xx + shift) % N) / w).astype(int)
	fy = yy - row * h
	fx = ((xx + shift) % N) - col * w
	edge = np.minimum(np.minimum(fx, w - fx), np.minimum(fy, h - fy)) - joint / 2.0
	return row * per_row + col, edge


def per_unit(ident, seed, lo, hi):
	rng = np.random.default_rng(seed)
	return rng.uniform(lo, hi, ident.max() + 1)[ident]


def save(name, albedo, height, strength):
	a = np.clip(albedo, 0.0, 1.0)
	Image.fromarray((a * 255).astype(np.uint8), "L").save(os.path.join(OUT, name + "_a.png"), optimize=True)
	dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * strength
	dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * strength
	inv = 1.0 / np.sqrt(dx * dx + dy * dy + 1.0)
	rgb = np.stack([(-dx * inv) * 0.5 + 0.5, (dy * inv) * 0.5 + 0.5, inv * 0.5 + 0.5], axis=-1)
	Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB").save(os.path.join(OUT, name + "_n.png"), optimize=True)


def units(name, ident, edge, seed, tone=(0.82, 1.0), joint_tone=0.6, grain=0.08, bevel=3.0, strength=6.0):
	face = np.clip(edge / bevel, 0.0, 1.0)
	g = noise(seed + 1, 1.0)
	albedo = (per_unit(ident, seed, *tone) - grain * g) * face + joint_tone * (1.0 - face)
	save(name, albedo, face + 0.15 * g * face + 0.1 * per_unit(ident, seed + 2, 0.0, 1.0) * face, strength)


def main() -> None:
	os.makedirs(OUT, exist_ok=True)
	units("brick", *courses(12, 4, 7.0, 1), 1, tone=(0.78, 1.0), joint_tone=0.72, strength=5.0)
	units("block", *courses(4, 2, 6.0, 2), 2, tone=(0.9, 1.0), joint_tone=0.78, grain=0.12, strength=4.0)
	units("slate", *courses(5, 4, 3.0, 3, jitter=0.15), 3, tone=(0.8, 1.0), joint_tone=0.55, bevel=2.0, strength=5.0)
	units("tile", *courses(4, 5, 5.0, 4), 4, tone=(0.8, 1.0), joint_tone=0.5, bevel=8.0, strength=7.0)
	units("paving", *courses(2, 2, 5.0, 5, stagger=0.0), 5, tone=(0.9, 1.0), joint_tone=0.6, grain=0.1, strength=3.0)
	ident, edge = cells(6, 90)
	units("stone", ident, np.minimum(edge, 6.0), 6, tone=(0.74, 1.0), joint_tone=0.5, grain=0.14, bevel=3.0, strength=6.0)
	c = noise(10, 1.8)
	pits = np.clip((noise(11, 0.6) - 0.72) * 9.0, 0.0, 1.0)
	save("concrete", 0.86 + 0.14 * c - 0.25 * pits, c * 0.4 - pits, 4.0)
	g = noise(12, 1.5, (0.06, 1.0))
	rings = 0.5 + 0.5 * np.sin((noise(13, 2.2, (0.25, 1.0)) * 26.0 + np.mgrid[0:N, 0:N][1] / N * 2 * np.pi * 9) )
	save("timber", 0.86 + 0.11 * g + 0.03 * rings, g * 0.8 + rings * 0.1, 2.0)
	g = noise(14, 1.4, (0.1, 1.0))
	save("plywood", 0.88 + 0.12 * g, g, 1.2)
	yy, xx = np.mgrid[0:N, 0:N]
	weave = 0.5 + 0.25 * np.sin(xx * 2 * np.pi * 32 / N) * (0.6 + 0.4 * np.sin(yy * 2 * np.pi * 64 / N)) + 0.25 * np.sin(yy * 2 * np.pi * 32 / N)
	save("fabric", 0.85 + 0.15 * weave - 0.05 * noise(15, 1.0), weave, 3.0)
	tuft = noise(16, 0.4)
	save("carpet", 0.8 + 0.2 * tuft, tuft, 5.0)
	a = noise(17, 0.5)
	save("asphalt", 0.75 + 0.25 * a, a, 5.0)
	s = noise(18, 1.2)
	save("soil", 0.7 + 0.3 * s, s + 0.3 * noise(19, 0.4), 5.0)
	r = noise(20, 1.0)
	save("render", 0.9 + 0.1 * noise(21, 2.0), r, 2.5)
	b = noise(22, 1.2, (1.0, 0.02))
	save("brushed", 0.9 + 0.1 * b, b, 1.0)
	ident, edge = cells(23, 220)
	save("galv", 0.84 + 0.16 * per_unit(ident, 23, 0.0, 1.0) * np.clip(edge / 1.5, 0, 1), noise(24, 1.5) * 0.2, 0.8)
	p = noise(25, 1.0)
	save("paint", 0.94 + 0.06 * noise(26, 2.0), p, 0.6)
	rib = np.clip(np.abs(((xx / N * 5.0) % 1.0) - 0.5) * 6.0 - 1.0, 0.0, 1.0)
	save("clad", 0.9 + 0.1 * rib - 0.04 * noise(27, 1.6, (0.1, 1.0)), rib * 6.0, 3.0)
	ident, edge = cells(28, 420)
	leaf = per_unit(ident, 28, 0.55, 1.0)
	save("foliage", leaf * (0.75 + 0.25 * np.clip(edge / 3.0, 0, 1)), leaf + np.clip(edge / 4.0, 0, 1), 6.0)
	v = np.abs(noise(29, 2.0) - 0.5) * 2.0
	vein = np.clip(1.0 - v * 9.0, 0.0, 1.0) ** 2
	save("marble", 0.97 - 0.45 * vein - 0.05 * noise(30, 1.6), np.zeros((N, N)), 0.0)
	ident, edge = cells(31, 900)
	save("leather", 0.9 + 0.1 * np.clip(edge / 2.0, 0, 1), np.clip(edge / 2.5, 0, 1), 3.0)
	blades = noise(32, 0.7, (0.3, 1.0))
	save("grass", 0.65 + 0.35 * blades * (0.7 + 0.3 * noise(33, 2.0)), blades, 5.0)
	print("textures: wrote %d patterns to %s" % (len(SIZE), OUT))


# slot name (or its start) -> pattern; first match wins. No entry: plain colour.
PATTERN_OF = [
	("brick", "brick"), ("blockwork", "block"), ("concrete", "concrete"), ("paving", "paving"), ("asphalt", "asphalt"),
	("render", "render"), ("plasterboard", "render"), ("stone", "stone"), ("slate", "slate"), ("clay_tile", "tile"), ("tile", "tile"),
	("softwood", "timber"), ("hardwood", "timber"), ("glulam", "timber"), ("timber", "timber"), ("bark", "timber"), ("plywood", "plywood"),
	("fabric", "fabric"), ("velvet", "carpet"), ("denim", "fabric"), ("carpet", "carpet"), ("mineral_wool", "carpet"),
	("leather", "leather"), ("soil", "soil"), ("foliage", "foliage"), ("marble", "marble"),
	("steel_stainless", "brushed"), ("aluminium", "brushed"), ("steel_galvanised", "galv"), ("galv", "galv"), ("lead", "galv"),
	("steel_painted", "paint"), ("steel", "paint"), ("cast_iron", "paint"), ("plant_yellow", "paint"), ("hazard_red", "paint"),
	("clad", "clad"), ("paint_", "paint"), ("enamel_", "paint"), ("roof_felt", "asphalt"), ("worktop", "concrete"),
]


def pattern_for(slot: str) -> str:
	for start, pattern in PATTERN_OF:
		if slot.startswith(start):
			return pattern
	return ""


if __name__ == "__main__":
	main()
