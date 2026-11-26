"""Offline tests for the site pack tool. Run from tools/osm:

    python3 -m unittest discover -s tests
"""

import base64
import math
import os
import struct
import sys
import unittest
import zlib

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sitepack import geo  # noqa: E402
from sitepack.elevation import FlatSampler, decode_png  # noqa: E402
from sitepack.features import building_height, parse_length  # noqa: E402
from sitepack.osm import merge_osm_xml, parse_osm_xml  # noqa: E402
from sitepack.pack import FORMAT_ID, FORMAT_VERSION, build_from_osm  # noqa: E402

LAT0, LON0 = 51.5, -1.0
PROJ = geo.LocalProjection(LAT0, LON0)


class OsmWriter:
    """Builds a small OSM XML document from local metre coordinates."""

    def __init__(self):
        self.nodes, self.ways, self.next_id = [], [], 1

    def node(self, x, z, tags=None):
        lat, lon = PROJ.to_latlon(x, z)
        nid = self.next_id
        self.next_id += 1
        self.nodes.append((nid, lat, lon, tags or {}))
        return nid

    def way(self, pts, tags, closed=False):
        ids = [self.node(x, z) for x, z in pts]
        if closed:
            ids.append(ids[0])
        wid = self.next_id
        self.next_id += 1
        self.ways.append((wid, ids, tags))
        return f"w{wid}"

    def xml(self) -> bytes:
        def tags(t):
            return "".join(f'<tag k="{k}" v="{v}"/>' for k, v in t.items())
        out = ['<?xml version="1.0"?><osm version="0.6">']
        out += [f'<node id="{i}" lat="{la:.8f}" lon="{lo:.8f}">{tags(t)}</node>' for i, la, lo, t in self.nodes]
        out += [f'<way id="{i}">' + "".join(f'<nd ref="{n}"/>' for n in ids) + tags(t) + "</way>"
                for i, ids, t in self.ways]
        out.append("</osm>")
        return "".join(out).encode()


def square(cx, cz, half):
    return [(cx - half, cz - half), (cx + half, cz - half), (cx + half, cz + half), (cx - half, cz + half)]


class GeoTests(unittest.TestCase):
    def test_projection_round_trip_and_axes(self):
        x, z = PROJ.to_local(LAT0 + 0.001, LON0 + 0.001)
        self.assertGreater(x, 0)   # east is +x
        self.assertLess(z, 0)      # north is -z
        self.assertAlmostEqual(-z, 111.25, delta=0.5)
        lat, lon = PROJ.to_latlon(x, z)
        self.assertAlmostEqual(lat, LAT0 + 0.001, places=9)
        self.assertAlmostEqual(lon, LON0 + 0.001, places=9)

    def test_area_centroid_inside(self):
        sq = square(10, 20, 5)
        self.assertAlmostEqual(geo.area(sq), 100)
        self.assertEqual(tuple(round(v, 6) for v in geo.centroid(sq)), (10, 20))
        self.assertTrue(geo.point_in_ring((10, 20), sq))
        self.assertFalse(geo.point_in_ring((16, 20), sq))

    def test_orientation_helpers(self):
        sq = square(0, 0, 1)
        self.assertLess(geo.signed_area(geo.make_ccw_on_map(sq)), 0)
        self.assertGreater(geo.signed_area(geo.make_cw_on_map(sq)), 0)

    def test_simplify_drops_collinear_points(self):
        line = [(0, 0), (1, 0.01), (2, 0), (3, 0.02), (4, 0)]
        self.assertEqual(geo.simplify(line, 0.1), [(0, 0), (4, 0)])
        ring = [(0, 0), (5, 0), (10, 0), (10, 10), (0, 10)]
        self.assertEqual(len(geo.simplify(ring, 0.1, closed=True)), 4)

    def test_min_area_rect_of_rotated_rectangle(self):
        r = geo.rect(0, 0, 30, 10, math.radians(30))
        w, d, ang, a = geo.min_area_rect(r)
        self.assertAlmostEqual(w, 30, places=6)
        self.assertAlmostEqual(d, 10, places=6)
        self.assertAlmostEqual(a, 300, places=4)

    def test_line_distance(self):
        self.assertAlmostEqual(geo.line_line_dist([(0, 0), (10, 0)], [(0, 5), (10, 5)]), 5)
        self.assertEqual(geo.line_line_dist([(0, -1), (0, 1)], [(-1, 0), (1, 0)]), 0.0)


class ParsingTests(unittest.TestCase):
    def test_lengths(self):
        self.assertEqual(parse_length("12"), 12)
        self.assertEqual(parse_length("12.5 m"), 12.5)
        self.assertAlmostEqual(parse_length("10'"), 3.048)
        self.assertAlmostEqual(parse_length("10'6\""), 3.2004)
        self.assertIsNone(parse_length(None))

    def test_building_heights(self):
        self.assertEqual(building_height({"building": "yes", "height": "21"})[2], "tag")
        h, levels, src = building_height({"building": "house", "building:levels": "2", "roof:shape": "gabled"})
        self.assertEqual((h, levels, src), (7.5, 2, "levels"))
        self.assertEqual(building_height({"building": "garage"}), (2.8, None, "default"))

    def test_png_decoder(self):
        w, h = 3, 2
        rows = [bytes([1, 2, 3, 4, 5, 6, 7, 8, 9]), bytes([10, 11, 12, 13, 14, 15, 16, 17, 18])]
        # Second row uses the Up filter to exercise filtering.
        raw = b"\x00" + rows[0] + b"\x02" + bytes((b - a) & 255 for a, b in zip(rows[0], rows[1]))

        def chunk(tag, body):
            return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body))
        png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
               + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
        self.assertEqual(decode_png(png), (3, 2, 3, rows))

    def test_merge_dedupes(self):
        a = b'<osm><node id="1" lat="0" lon="0"/><way id="5"><nd ref="1"/></way></osm>'
        b = b'<osm><node id="1" lat="0" lon="0"/><node id="2" lat="1" lon="1"/></osm>'
        osm = parse_osm_xml(merge_osm_xml([a, b]))
        self.assertEqual(sorted(osm.nodes), [1, 2])
        self.assertIn(5, osm.ways)


class PackTests(unittest.TestCase):
    """A synthetic site with every kind of awkwardness the rating looks for."""

    @classmethod
    def setUpClass(cls):
        o = OsmWriter()
        cls.plot = o.way(square(0, 0, 10), {"landuse": "brownfield"}, closed=True)
        o.way(square(0, 0, 3), {"building": "garage"}, closed=True)                    # on the plot
        o.way(square(14, 0, 4), {"building": "house", "building:levels": "2"}, closed=True)  # on boundary
        o.way(square(-30, 0, 5), {"building": "church", "listed_status": "Grade II"}, closed=True)
        o.way([(-100, 13), (100, 13)], {"highway": "service", "name": "Back Lane"})
        o.way([(-100, -60), (100, -60)], {"highway": "residential", "name": "High Street"})
        o.way([(-100, -5), (100, 5)], {"power": "minor_line"})
        o.way([(-100, 30), (100, 30)], {"waterway": "river", "name": "Avon"})
        o.way([(-100, 80), (100, 80)], {"railway": "rail", "tunnel": "yes"})
        o.node(8, 8, {"natural": "tree", "height": "15"})
        cls.raw = o.xml()
        # Ground falls 10 m per 100 m to the south (+z).
        sampler = FlatSampler(lambda lat, lon: 50.0 - 0.1 * PROJ.to_local(lat, lon)[1])
        site = {"id": "test-site", "name": "Test", "lat": LAT0, "lon": LON0, "radius_m": 120,
                "plot": {"osm": cls.plot}}
        cls.pack = build_from_osm(site, cls.raw, sampler, spacing=5.0, log=lambda *_: None)

    def factor(self, fid):
        return next((f for f in self.pack["plot"]["difficulty"]["factors"] if f["id"] == fid), None)

    def test_header(self):
        p = self.pack
        self.assertEqual((p["format"], p["version"]), (FORMAT_ID, FORMAT_VERSION))
        self.assertIn("© OpenStreetMap contributors", p["attribution"])

    def test_terrain_grid(self):
        t = self.pack["terrain"]
        nx, nz = t["size"]
        hs = struct.unpack(f"<{nx * nz}f", base64.b64decode(t["heights_b64"]))
        self.assertEqual(len(hs), nx * nz)
        # Rows run north to south, so heights fall along each column.
        self.assertGreater(hs[0], hs[(nz - 1) * nx])
        # y = 0 at the plot's mean ground.
        self.assertAlmostEqual(self.pack["plot"]["ground"]["mean_y"], 0.0, delta=0.3)
        self.assertAlmostEqual(self.pack["origin"]["elevation_m"], 50.0, delta=0.3)

    def test_plot_outline_and_size(self):
        plot = self.pack["plot"]
        self.assertEqual(len(plot["outline"]), 4)
        self.assertAlmostEqual(plot["area_m2"], 400, delta=1)
        self.assertLess(geo.signed_area([tuple(p) for p in plot["outline"]]), 0)

    def test_factors(self):
        self.assertEqual(self.factor("slope")["metrics"]["downhill"], "south")
        self.assertAlmostEqual(self.factor("slope")["metrics"]["slope_pct"], 10, delta=0.5)
        self.assertEqual(self.factor("existing_buildings")["metrics"]["count"], 1)
        self.assertEqual(self.factor("neighbours")["severity"], 3)
        self.assertIsNotNone(self.factor("heritage"))
        self.assertGreaterEqual(self.factor("overhead_lines")["severity"], 2)
        self.assertEqual(self.factor("trees")["metrics"]["on_plot"], 1)
        self.assertEqual(self.pack["plot"]["ground"]["soil"], "soft_wet")
        self.assertIsNone(self.factor("railway"))  # it is in a tunnel
        access = self.pack["plot"]["access"]
        self.assertEqual([a["name"] for a in access], ["Back Lane"])
        self.assertGreaterEqual(self.factor("access")["severity"], 2)
        self.assertEqual(self.pack["plot"]["difficulty"]["rating"], 5)

    def test_features(self):
        p = self.pack
        kinds = sorted(b["kind"] for b in p["buildings"])
        self.assertEqual(kinds, ["church", "garage", "house"])
        on_plot = [b for b in p["buildings"] if b["on_plot"]]
        self.assertEqual([b["kind"] for b in on_plot], ["garage"])
        church = next(b for b in p["buildings"] if b["kind"] == "church")
        self.assertTrue(church["protected"])
        house = next(b for b in p["buildings"] if b["kind"] == "house")
        self.assertEqual(house["levels"], 2)
        self.assertLessEqual(house["base_y"], house["ground_max_y"])
        self.assertEqual(len(p["trees"]), 1)
        self.assertEqual(p["trees"][0]["height_m"], 15)
        self.assertEqual({r["name"] for r in p["roads"]}, {"Back Lane", "High Street"})
        self.assertEqual(p["power_lines"][0]["kind"], "minor_line")


class SamplePackTests(unittest.TestCase):
    """Checks the committed sample packs still match the format."""

    def test_samples(self):
        import json
        folder = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "samples")
        files = [f for f in os.listdir(folder) if f.endswith(".sitepack.json")] if os.path.isdir(folder) else []
        for name in files:
            with open(os.path.join(folder, name), encoding="utf-8") as f:
                p = json.load(f)
            self.assertEqual(p["format"], FORMAT_ID, name)
            self.assertEqual(p["version"], FORMAT_VERSION, name)
            self.assertEqual(name, p["id"] + ".sitepack.json")
            nx, nz = p["terrain"]["size"]
            self.assertEqual(len(base64.b64decode(p["terrain"]["heights_b64"])), nx * nz * 4, name)
            self.assertGreaterEqual(len(p["plot"]["outline"]), 3, name)
            self.assertIn(p["plot"]["difficulty"]["rating"], range(1, 6), name)


if __name__ == "__main__":
    unittest.main()
