"""Fetching and parsing OpenStreetMap data.

Two sources are supported, both returning OSM XML:

* Overpass API (default). One query per site, recursed down to nodes.
* The main OSM API ``map`` call, as a fallback when Overpass is unreachable.
  It is meant for editors, so only use it for the odd hand-curated site.

Every response is cached on disk by a hash of the request, so re-running a
build (to tweak plot choice or simplification) never touches the network.
Requests are spaced at least ``MIN_INTERVAL_S`` apart, and 429/504 answers back
off politely, in keeping with the Overpass fair-use policy.
"""

from __future__ import annotations

import hashlib
import os
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

USER_AGENT = "HouseBuilder-sitepack/1.0 (private, offline site pack builder)"
OVERPASS_ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]
OSM_API = "https://api.openstreetmap.org/api/0.6/map"
MIN_INTERVAL_S = 5.0
_last_request = 0.0
_overpass_down = False  # set after one failed run so later sites skip straight to the fallback


def overpass_query(south: float, west: float, north: float, east: float, timeout_s: int = 60) -> str:
    bb = f"{south:.7f},{west:.7f},{north:.7f},{east:.7f}"
    return f"""[out:xml][timeout:{timeout_s}][bbox:{bb}];
(
  way["building"];
  relation["building"];
  way["building:part"];
  way["highway"];
  way["landuse"];
  relation["landuse"];
  way["natural"];
  relation["natural"];
  node["natural"="tree"];
  way["leisure"];
  way["amenity"="parking"];
  way["waterway"];
  way["water"];
  relation["water"];
  way["power"~"^(line|minor_line|cable)$"];
  node["power"~"^(pole|tower)$"];
  way["barrier"];
  way["railway"];
  way["man_made"];
  node["historic"];
  way["historic"];
);
(._;>;);
out body;"""


def _throttle():
    global _last_request
    wait = MIN_INTERVAL_S - (time.time() - _last_request)
    if wait > 0:
        time.sleep(wait)
    _last_request = time.time()


def _http(url: str, data: Optional[bytes] = None, timeout: float = 120.0) -> bytes:
    req = urllib.request.Request(url, data=data, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def _cached(cache_dir: str, key: str, fetch) -> bytes:
    os.makedirs(cache_dir, exist_ok=True)
    path = os.path.join(cache_dir, hashlib.sha1(key.encode()).hexdigest()[:16] + ".osm")
    if os.path.exists(path):
        with open(path, "rb") as f:
            return f.read()
    data = fetch()
    tmp = path + ".part"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, path)
    return data


def fetch_osm(bbox: Tuple[float, float, float, float], cache_dir: str, source: str = "auto",
              log=print) -> bytes:
    """Returns OSM XML for (south, west, north, east)."""
    s, w, n, e = bbox

    def via_overpass() -> bytes:
        global _overpass_down
        if _overpass_down:
            raise RuntimeError("Overpass was unreachable earlier in this run")
        q = overpass_query(s, w, n, e)
        last_err: Optional[Exception] = None
        for endpoint in OVERPASS_ENDPOINTS:
            for attempt in range(3):
                _throttle()
                try:
                    log(f"  overpass: {endpoint} (attempt {attempt + 1})")
                    return _http(endpoint, urllib.parse.urlencode({"data": q}).encode())
                except urllib.error.HTTPError as ex:
                    last_err = ex
                    if ex.code in (429, 504):
                        time.sleep(30 * (attempt + 1))
                        continue
                    break
                except (urllib.error.URLError, OSError) as ex:
                    last_err = ex
                    break
        _overpass_down = True
        raise RuntimeError(f"Overpass unavailable: {last_err}")

    def via_osm_api() -> bytes:
        return _osm_api_tiled(s, w, n, e, log, depth=0)

    key_bb = f"{s:.6f},{w:.6f},{n:.6f},{e:.6f}"
    if source == "overpass":
        return _cached(cache_dir, "overpass:" + key_bb, via_overpass)
    if source == "osmapi":
        return _cached(cache_dir, "osmapi:" + key_bb, via_osm_api)
    # auto: reuse any cached copy first, then try Overpass, then the OSM API.
    for prefix, fn in (("overpass:", via_overpass), ("osmapi:", via_osm_api)):
        path = os.path.join(cache_dir, hashlib.sha1((prefix + key_bb).encode()).hexdigest()[:16] + ".osm")
        if os.path.exists(path):
            with open(path, "rb") as f:
                return f.read()
    try:
        return _cached(cache_dir, "overpass:" + key_bb, via_overpass)
    except RuntimeError as ex:
        log(f"  {ex}; falling back to the OSM API")
        return _cached(cache_dir, "osmapi:" + key_bb, via_osm_api)


def _osm_api_tiled(s: float, w: float, n: float, e: float, log, depth: int) -> bytes:
    """OSM API map call. Dense areas exceed its 50,000 node limit (HTTP 400),
    so the box is split into quarters, up to two levels, and merged."""
    _throttle()
    log(f"  osm api: map call{' (part)' if depth else ''}")
    try:
        return _http(f"{OSM_API}?bbox={w:.7f},{s:.7f},{e:.7f},{n:.7f}")
    except urllib.error.HTTPError as ex:
        if ex.code != 400 or depth >= 2:
            raise
    mlat, mlon = (s + n) / 2, (w + e) / 2
    parts = [_osm_api_tiled(a, b, c, d, log, depth + 1) for a, b, c, d in
             ((s, w, mlat, mlon), (s, mlon, mlat, e), (mlat, w, n, mlon), (mlat, mlon, n, e))]
    return merge_osm_xml(parts)


def merge_osm_xml(parts: List[bytes]) -> bytes:
    seen = set()
    order = {"node": 0, "way": 1, "relation": 2}
    els = []
    for data in parts:
        for el in ET.fromstring(data):
            if el.tag not in order:
                continue
            key = (el.tag, el.get("id"))
            if key not in seen:
                seen.add(key)
                els.append(el)
    els.sort(key=lambda el: order[el.tag])
    root = ET.Element("osm", {"version": "0.6", "generator": "sitepack merge"})
    root.extend(els)
    return ET.tostring(root, encoding="utf-8")


@dataclass
class Way:
    id: int
    nodes: List[int]
    tags: Dict[str, str]

    @property
    def closed(self) -> bool:
        return len(self.nodes) >= 4 and self.nodes[0] == self.nodes[-1]


@dataclass
class Relation:
    id: int
    members: List[Tuple[str, int, str]]  # (type, ref, role)
    tags: Dict[str, str]


@dataclass
class OsmData:
    nodes: Dict[int, Tuple[float, float]] = field(default_factory=dict)
    node_tags: Dict[int, Dict[str, str]] = field(default_factory=dict)
    ways: Dict[int, Way] = field(default_factory=dict)
    relations: Dict[int, Relation] = field(default_factory=dict)

    def way_latlon(self, way: Way) -> Optional[List[Tuple[float, float]]]:
        try:
            return [self.nodes[n] for n in way.nodes]
        except KeyError:
            return None


def parse_osm_xml(data: bytes) -> OsmData:
    out = OsmData()
    root = ET.fromstring(data)
    for el in root:
        tags = {t.get("k"): t.get("v") for t in el.findall("tag")}
        if el.tag == "node":
            nid = int(el.get("id"))
            out.nodes[nid] = (float(el.get("lat")), float(el.get("lon")))
            if tags:
                out.node_tags[nid] = tags
        elif el.tag == "way":
            out.ways[int(el.get("id"))] = Way(int(el.get("id")), [int(n.get("ref")) for n in el.findall("nd")], tags)
        elif el.tag == "relation":
            members = [(m.get("type"), int(m.get("ref")), m.get("role") or "") for m in el.findall("member")]
            out.relations[int(el.get("id"))] = Relation(int(el.get("id")), members, tags)
    return out


def assemble_rings(osm: OsmData, way_ids: List[int]) -> List[List[int]]:
    """Joins member ways end to end into closed node rings. Incomplete rings
    (members missing from the download) are dropped."""
    segs = []
    for wid in way_ids:
        w = osm.ways.get(wid)
        if w and len(w.nodes) >= 2 and all(n in osm.nodes for n in w.nodes):
            segs.append(list(w.nodes))
    rings: List[List[int]] = []
    while segs:
        cur = segs.pop(0)
        changed = True
        while cur[0] != cur[-1] and changed:
            changed = False
            for i, s in enumerate(segs):
                if s[0] == cur[-1]:
                    cur = cur + s[1:]
                elif s[-1] == cur[-1]:
                    cur = cur + list(reversed(s))[1:]
                elif s[-1] == cur[0]:
                    cur = s[:-1] + cur
                elif s[0] == cur[0]:
                    cur = list(reversed(s))[:-1] + cur
                else:
                    continue
                segs.pop(i)
                changed = True
                break
        if cur[0] == cur[-1] and len(cur) >= 4:
            rings.append(cur)
    return rings
