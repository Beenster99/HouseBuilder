# OSM site pack tool

Offline Python tool that turns a point on the map into a **site pack**: a single JSON file
with the terrain, neighbouring buildings, roads, land use, trees and power lines around a
real plot, in local metres, with the plot marked and rated for how awkward it is to build
on. The game's `sites` module loads these. The file format is in [FORMAT.md](FORMAT.md).

Python 3.9 or later, standard library only. Making previews also needs Pillow.

## Quick start

Run everything from this folder (`tools/osm`):

```sh
# Rebuild every curated sample in sites.json into samples/
python3 -m sitepack build-all

# Build one site: centre point, radius and a plot
python3 -m sitepack build --id my-site --lat 51.3893 --lon -2.3612 --plot w217317513

# List candidate plots (open land, car parks, existing buildings) around a point
python3 -m sitepack survey --lat 51.3893 --lon -2.3612

# Print a pack's plot rating, or draw a top-down PNG of it (needs: pip install pillow)
python3 -m sitepack info samples/bath-hillside-garages.sitepack.json
python3 -m sitepack preview samples/*.sitepack.json

# Tests (offline)
python3 -m unittest discover -s tests
```

## How it works

1. **OpenStreetMap data.** One request per site for a box just larger than the radius. The
   tool tries the Overpass API first and falls back to the main OSM API's `map` call
   (splitting dense areas into quarters). Choose with `--source overpass|osmapi|auto`, given before the command
   (`python3 -m sitepack --source osmapi build-all`).
2. **Elevation.** Terrain Tiles (AWS Open Data, Terrarium PNG encoding) at zoom 15, about
   3 to 5 m per pixel, resampled onto a 4 m grid (`--spacing`).
3. **Conversion.** Lat and long become local metres around the centre (`x` east, `z` south,
   `y` up, `y = 0` at the plot's mean ground). Outlines are simplified (25 cm for buildings,
   75 cm for land use, 50 cm for roads), and buildings get heights from `height`,
   `building:levels`, or a typical height for their type.
4. **The plot.** Chosen from the `plot` spec (below), then measured: slope, shape, road
   frontage, neighbours on the boundary, listed buildings nearby, trees, overhead lines,
   railways, wet or made ground, and existing buildings to clear. Each problem becomes a
   factor with a severity, and they add up to a 1 to 5 difficulty rating.

### Being gentle with the servers

- Every response is cached in `.cache/` (git-ignored), keyed by the request. Rebuilding a
  site to try a different plot never touches the network again.
- Requests are at least 5 seconds apart. Overpass answers of 429 or 504 back off for 30 s
  or more, and if Overpass is unreachable the tool stops trying it for the rest of the run.
- Requests send a `User-Agent` naming the tool.
- The OSM API `map` call is meant for editors: use it for the odd hand-curated site, not
  for bulk building. For large batches, use Overpass or a local extract.

## Plot specs

In `sites.json` (`"plot": ...`) or on the command line (`--plot ...`):

| spec | meaning |
|---|---|
| `"auto"` | the smallest open area (car park, grass, brownfield and so on) containing the centre; otherwise a 20 by 30 m rectangle at the centre, aligned with the nearest road |
| `{"osm": "w123"}` | an OSM area or building outline as the plot |
| `{"osm": "w123", "buffer_m": 4}` | a building's outline grown into a rectangle with a margin: a brownfield plot where the building is cleared first |
| `{"rect": {"centre": [x, z], "width": 20, "depth": 30, "angle_deg": 0}}` | a rectangle in local metres; `"align": "road"` instead of `angle_deg` lines it up with the nearest road; `"latlon": [lat, lon]` instead of `centre` |
| `{"polygon_latlon": [[lat, lon], ...]}` | any outline |

Use `survey` to find ids, then `build` and `preview` to check the result by eye.

## Curating sites

`sites.json` lists the sample sites. Each entry has `id`, `name`, `description`,
`suited_to`, `lat`, `lon`, `radius_m` and `plot`, plus optional `notes` and `spacing_m`.
The plan wants plots that are often not ideal for the job, so aim for a spread of
ratings. The samples now:

| id | rating | why it is hard |
|---|---|---|
| `northstowe-meadow` | 2 | the easy one: flat greenfield, but an awkward triangle |
| `northstowe-powerline` | 3 | flat field with an overhead line across it and no road |
| `ancoats-phoenix-ironworks` | 3 | big former ironworks: made ground, a neighbour on the boundary |
| `ancoats-infill` | 3 | city gap site beside a canal, no road frontage |
| `camden-station-infill` | 3 | tiny plot, neighbours on every side, busy single road |
| `mk-central-carpark` | 4 | car park hemmed in by a shopping centre, service roads across it |
| `tewkesbury-floodplain` | 4 | between two rivers: wet ground, lanes across it, listed neighbours |
| `bath-hillside-garages` | 5 | clear a garage block on a steep hillside, party wall, no road frontage |
| `clovelly-cliffside` | 5 | replace a cottage on a 46% slope that no vehicle can reach |

`samples/*.preview.png` shows each one from above.

## Licence and attribution

Site packs are derived from OpenStreetMap, © OpenStreetMap contributors, under the Open
Database Licence (ODbL 1.0). The game must show "© OpenStreetMap contributors" wherever a
real site is used and in the credits, and the packs stay available under the ODbL.
Elevation is from Terrain Tiles (Mapzen and AWS Open Data), which combines SRTM, GMTED2010,
ETOPO1, EU-DEM, national LIDAR and other open sources that allow reuse with attribution.
Each pack's `attribution` array carries the exact lines.

## Layout

```
tools/osm/
  sitepack/        the tool (python3 -m sitepack)
    osm.py         Overpass and OSM API fetching, caching, XML parsing
    elevation.py   Terrain Tiles download and PNG decoding
    geo.py         projection and 2D geometry
    features.py    OSM tags to buildings, roads, areas, trees, lines
    plot.py        plot choice and the difficulty rating
    pack.py        writes the site pack
    preview.py     PNG previews (Pillow)
  sites.json       curated sample sites
  samples/         built packs and previews
  tests/           offline unit tests
  FORMAT.md        the site pack file format
  .gdignore        keeps Godot from importing this folder
```

The `.gdignore` means Godot does not see these files. When the `sites` module is written,
it should ship its own copy of the packs it uses (for example under `modules/sites/data/`),
built with `--out` pointing there.
