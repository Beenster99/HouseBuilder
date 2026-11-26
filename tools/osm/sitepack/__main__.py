"""Command line entry: run `python -m sitepack --help` from tools/osm."""

from __future__ import annotations

import argparse
import json
import os
import sys

from . import geo
from .features import extract
from .osm import fetch_osm, parse_osm_xml
from .pack import build_site, summary, write_pack
from .plot import survey

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_CACHE = os.path.join(HERE, ".cache")
DEFAULT_OUT = os.path.join(HERE, "samples")
DEFAULT_SITES = os.path.join(HERE, "sites.json")


def _plot_arg(value: str):
    if value == "auto":
        return "auto"
    if value.startswith("{"):
        return json.loads(value)
    return {"osm": value}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="sitepack", description="Build HouseBuilder site packs from OpenStreetMap.")
    ap.add_argument("--cache", default=DEFAULT_CACHE, help="download cache folder (default tools/osm/.cache)")
    ap.add_argument("--source", choices=["auto", "overpass", "osmapi"], default="auto",
                    help="OSM source; auto tries the cache, then Overpass, then the OSM API")
    sub = ap.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("build", help="build one site pack from a centre point")
    b.add_argument("--id", required=True)
    b.add_argument("--name")
    b.add_argument("--lat", type=float, required=True)
    b.add_argument("--lon", type=float, required=True)
    b.add_argument("--radius", type=float, default=300.0)
    b.add_argument("--plot", default="auto", help='"auto", an OSM id such as w123, or a JSON plot spec')
    b.add_argument("--spacing", type=float, default=4.0, help="terrain grid spacing in metres")
    b.add_argument("--no-elevation", action="store_true")
    b.add_argument("--out", default=DEFAULT_OUT)

    ba = sub.add_parser("build-all", help="build every site listed in a sites file")
    ba.add_argument("sites", nargs="?", default=DEFAULT_SITES)
    ba.add_argument("--only", nargs="*", help="site ids to build")
    ba.add_argument("--out", default=DEFAULT_OUT)

    s = sub.add_parser("survey", help="list candidate plots around a point")
    s.add_argument("--lat", type=float, required=True)
    s.add_argument("--lon", type=float, required=True)
    s.add_argument("--radius", type=float, default=300.0)

    i = sub.add_parser("info", help="summarise a site pack file")
    i.add_argument("files", nargs="+")

    v = sub.add_parser("preview", help="write a top-down PNG preview next to each pack (needs Pillow)")
    v.add_argument("files", nargs="+")

    args = ap.parse_args(argv)

    if args.cmd == "build":
        site = {"id": args.id, "name": args.name or args.id, "lat": args.lat, "lon": args.lon,
                "radius_m": args.radius, "plot": _plot_arg(args.plot)}
        pack = build_site(site, args.cache, spacing=args.spacing, elevation=not args.no_elevation,
                          source=args.source)
        print(summary(pack))
        print("wrote", write_pack(pack, args.out))
    elif args.cmd == "build-all":
        with open(args.sites, encoding="utf-8") as f:
            sites = json.load(f)["sites"]
        for site in sites:
            if args.only and site["id"] not in args.only:
                continue
            pack = build_site(site, args.cache, spacing=site.get("spacing_m", 4.0), source=args.source)
            print(summary(pack))
            print("wrote", write_pack(pack, args.out))
    elif args.cmd == "survey":
        proj = geo.LocalProjection(args.lat, args.lon)
        raw = fetch_osm(proj.bbox_deg(args.radius * 1.1), os.path.join(args.cache, "osm"), source=args.source)
        feat = extract(parse_osm_xml(raw), proj)
        for r in survey(feat, args.radius):
            print(f"{r['osm']:>14}  {r['kind']:<28} {r['area_m2']:>7} m2  {r['dist_m']:>4} m  {r['name']}")
    elif args.cmd == "info":
        for path in args.files:
            with open(path, encoding="utf-8") as f:
                print(summary(json.load(f)))
    elif args.cmd == "preview":
        from .preview import render_png
        for path in args.files:
            with open(path, encoding="utf-8") as f:
                pack = json.load(f)
            out = path.replace(".sitepack.json", "") + ".preview.png"
            render_png(pack, out)
            print("wrote", out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
