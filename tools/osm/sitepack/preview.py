"""Top-down PNG preview of a site pack, for curating plots by eye.

Needs Pillow (`pip install pillow`); the rest of the tool needs only the
standard library. North is up. Terrain is hillshaded, buildings are shaded by
height (purple = protected, red = on the plot), the plot is orange, and the
difficulty factors are listed underneath.
"""

from __future__ import annotations

import base64
import math
import struct
import textwrap


def _heights(pack):
    raw = base64.b64decode(pack["terrain"]["heights_b64"])
    return list(struct.unpack(f"<{len(raw) // 4}f", raw))


AREA_COLOURS = {
    "natural:water": (91, 143, 209), "waterway:riverbank": (91, 143, 209), "natural:wetland": (127, 169, 160),
    "natural:wood": (78, 122, 67), "landuse:forest": (78, 122, 67), "landuse:grass": (156, 194, 127),
    "leisure:park": (156, 194, 127), "leisure:garden": (170, 200, 140), "amenity:parking": (185, 185, 185),
    "landuse:construction": (201, 169, 122), "landuse:brownfield": (181, 154, 118),
    "landuse:meadow": (170, 205, 130), "landuse:farmland": (215, 210, 150),
}


def render_png(pack: dict, path: str, size: int = 1000) -> None:
    from PIL import Image, ImageDraw, ImageFont

    r = pack["radius_m"]
    scale = size / (2 * r)

    def P(p):
        return ((p[0] + r) * scale, (p[1] + r) * scale)

    t = pack["terrain"]
    hs = _heights(pack)
    nx, nz = t["size"]
    sp = t["spacing_m"]
    lo, span = t["min_y"], max(t["max_y"] - t["min_y"], 1.0)
    shade = Image.new("RGB", (nx, nz))
    px = shade.load()
    lx, ly, lz = -0.5, 0.7, -0.5
    ln = math.sqrt(lx * lx + ly * ly + lz * lz)
    for j in range(nz):
        for i in range(nx):
            dx = (hs[j * nx + min(i + 1, nx - 1)] - hs[j * nx + max(i - 1, 0)]) / (2 * sp)
            dz = (hs[min(j + 1, nz - 1) * nx + i] - hs[max(j - 1, 0) * nx + i]) / (2 * sp)
            nn = math.sqrt(dx * dx + 1 + dz * dz)
            s = max(0.0, (-dx * lx + ly - dz * lz) / (nn * ln))
            band = int((hs[j * nx + i] - lo) / span * 10) / 10
            g = 120 + 110 * s
            px[i, j] = (int(g * (0.85 + 0.15 * band)), int(g), int(g * (0.92 - 0.12 * band)))
    x0, z0 = t["origin"]
    left, top = P((x0 - sp / 2, z0 - sp / 2))
    terrain = shade.resize((int(nx * sp * scale), int(nz * sp * scale)), Image.BILINEAR)

    lines_txt = []
    p = pack["plot"]
    d = p["difficulty"]
    lines_txt.append(f'{pack["name"]}: difficulty {d["rating"]}/5, plot {p["area_m2"]:.0f} m2, '
                     f'slope {p["ground"]["slope_pct"]}%, soil {p["ground"]["soil"]}, '
                     f'terrain relief {t["max_y"] - t["min_y"]:.0f} m')
    for f in d["factors"]:
        lines_txt += textwrap.wrap(f'[{f["severity"]}] {f["label"]}: {f["detail"]}', 130)
    lines_txt.append("© OpenStreetMap contributors. North is up. Scale bar 50 m.")
    img = Image.new("RGB", (size, size + 14 + 17 * len(lines_txt)), (255, 255, 255))
    img.paste(terrain, (int(left), int(top)))
    dr = ImageDraw.Draw(img, "RGBA")

    for a in pack["areas"]:
        c = AREA_COLOURS.get(a["kind"])
        if c:
            dr.polygon([P(q) for q in a["outline"]], fill=c + (140,))
    for w in pack["waterways"]:
        dr.line([P(q) for q in w["line"]], fill=(58, 111, 192), width=max(1, int(w["width_m"] * scale)))
    for rd in pack["roads"]:
        dr.line([P(q) for q in rd["line"]], fill=(250, 250, 250), width=max(2, int(rd["width_m"] * scale)), joint="curve")
    for pth in pack["paths"]:
        dr.line([P(q) for q in pth["line"]], fill=(200, 170, 110), width=1)
    for rl in pack["railways"]:
        dr.line([P(q) for q in rl["line"]], fill=(60, 60, 60), width=3)
    for b in pack["buildings"]:
        h = min(b["height_m"], 40) / 40
        g = int(205 - h * 130)
        fill = (208, 80, 60) if b["on_plot"] else ((140, 95, 176) if b["protected"] else (g, g - 15, g - 35))
        dr.polygon([P(q) for q in b["outline"]], fill=fill, outline=(50, 50, 50))
    for tr in pack["trees"]:
        cx, cz = P(tr["pos"])
        rr = max(2.0, tr["crown_m"] / 2 * scale)
        dr.ellipse((cx - rr, cz - rr, cx + rr, cz + rr), fill=(47, 107, 42, 210))
    for pl in pack["power_lines"]:
        if pl["kind"] == "cable":
            continue
        dr.line([P(q) for q in pl["line"]], fill=(230, 176, 0), width=2)
    outline = [P(q) for q in p["outline"]]
    dr.polygon(outline, fill=(255, 140, 0, 70))
    dr.line(outline + [outline[0]], fill=(255, 90, 0), width=3)
    dr.rectangle((size - 20 - 50 * scale, size - 22, size - 20, size - 17), fill=(0, 0, 0))
    dr.rectangle((0, size, size, img.height), fill=(255, 255, 255))
    try:
        font = ImageFont.truetype("DejaVuSans.ttf", 13)
    except OSError:
        font = ImageFont.load_default()
    for k, s in enumerate(lines_txt):
        dr.text((8, size + 6 + k * 17), s, fill=(0, 0, 0), font=font)
    img.save(path, optimize=True)
