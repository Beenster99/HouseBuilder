"""Terrain elevation from the open Terrain Tiles dataset (AWS Open Data,
originally Mapzen/Tilezen "Joerd"), in the Terrarium PNG encoding.

Height in metres = R * 256 + G + B / 256 - 32768.

Zoom 15 gives roughly 4.8 m per pixel at the equator and about 3 m in the UK.
Sources blend SRTM, GMTED, ETOPO1, EU-DEM, national LIDAR (for example the
UK Environment Agency's, under the Open Government Licence) and others; all
allow reuse, including commercial, with attribution.
"""

from __future__ import annotations

import math
import os
import struct
import urllib.request
import zlib
from typing import Callable, Dict, List, Tuple

TILE_URL = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
ATTRIBUTION = ("Terrain: Terrain Tiles (AWS Open Data / Mapzen), including data from "
               "SRTM, GMTED2010, ETOPO1, EU-DEM (Copernicus) and national LIDAR sources")
USER_AGENT = "HouseBuilder-sitepack/1.0 (private, offline site pack builder)"


def decode_png(data: bytes) -> Tuple[int, int, int, List[bytes]]:
    """Minimal PNG decoder for 8-bit RGB/RGBA, non-interlaced images.
    Returns (width, height, channels, rows)."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos = 8
    idat = bytearray()
    width = height = channels = 0
    while pos < len(data):
        length, ctype = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if ctype == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or colour not in (2, 6) or interlace:
                raise ValueError(f"unsupported PNG (depth {depth}, colour {colour}, interlace {interlace})")
            channels = 3 if colour == 2 else 4
        elif ctype == b"IDAT":
            idat += body
        elif ctype == b"IEND":
            break
    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    rows: List[bytes] = []
    prev = bytearray(stride)
    i = 0
    for _ in range(height):
        f = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        if f == 1:
            for k in range(channels, stride):
                line[k] = (line[k] + line[k - channels]) & 255
        elif f == 2:
            for k in range(stride):
                line[k] = (line[k] + prev[k]) & 255
        elif f == 3:
            for k in range(stride):
                left = line[k - channels] if k >= channels else 0
                line[k] = (line[k] + ((left + prev[k]) >> 1)) & 255
        elif f == 4:
            for k in range(stride):
                a = line[k - channels] if k >= channels else 0
                b = prev[k]
                c = prev[k - channels] if k >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[k] = (line[k] + pr) & 255
        elif f != 0:
            raise ValueError(f"bad PNG filter {f}")
        rows.append(bytes(line))
        prev = line
    return width, height, channels, rows


def _tile_xy(lat: float, lon: float, z: int) -> Tuple[float, float]:
    n = 2 ** z
    x = (lon + 180.0) / 360.0 * n
    lr = math.radians(lat)
    y = (1.0 - math.asinh(math.tan(lr)) / math.pi) / 2.0 * n
    return x, y


class TerrainSampler:
    """Bilinear height lookup by lat/lon over cached Terrarium tiles."""

    def __init__(self, cache_dir: str, zoom: int = 15, log=print):
        self.cache_dir = cache_dir
        self.zoom = zoom
        self.log = log
        self._tiles: Dict[Tuple[int, int], List[List[float]]] = {}

    def _load(self, tx: int, ty: int) -> List[List[float]]:
        key = (tx, ty)
        if key in self._tiles:
            return self._tiles[key]
        os.makedirs(self.cache_dir, exist_ok=True)
        path = os.path.join(self.cache_dir, f"terrarium_{self.zoom}_{tx}_{ty}.png")
        if not os.path.exists(path):
            url = TILE_URL.format(z=self.zoom, x=tx, y=ty)
            self.log(f"  elevation tile {self.zoom}/{tx}/{ty}")
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = resp.read()
            with open(path + ".part", "wb") as f:
                f.write(data)
            os.replace(path + ".part", path)
        with open(path, "rb") as f:
            w, h, ch, rows = decode_png(f.read())
        grid = []
        for row in rows:
            grid.append([row[k] * 256 + row[k + 1] + row[k + 2] / 256.0 - 32768.0
                         for k in range(0, w * ch, ch)])
        self._tiles[key] = grid
        return grid

    def _pixel(self, px: int, py: int) -> float:
        tx, ix = divmod(px, 256)
        ty, iy = divmod(py, 256)
        return self._load(tx, ty)[iy][ix]

    def height(self, lat: float, lon: float) -> float:
        fx, fy = _tile_xy(lat, lon, self.zoom)
        # Pixel centres sit at +0.5.
        gx, gy = fx * 256 - 0.5, fy * 256 - 0.5
        x0, y0 = math.floor(gx), math.floor(gy)
        tx, ty = gx - x0, gy - y0
        h00 = self._pixel(x0, y0)
        h10 = self._pixel(x0 + 1, y0)
        h01 = self._pixel(x0, y0 + 1)
        h11 = self._pixel(x0 + 1, y0 + 1)
        return (h00 * (1 - tx) * (1 - ty) + h10 * tx * (1 - ty)
                + h01 * (1 - tx) * ty + h11 * tx * ty)


class FlatSampler:
    """Stand-in used with --no-elevation and in tests."""

    def __init__(self, fn: Callable[[float, float], float] = lambda lat, lon: 0.0):
        self.fn = fn

    def height(self, lat: float, lon: float) -> float:
        return self.fn(lat, lon)
