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
ratings. The 21 samples now (the Phase 6 target is 20):

| id | rating | suits | main problems |
|---|---|---|---|
| `manston-airfield` | 2 | airport terminal, hospital | no road frontage |
| `northstowe-meadow` | 2 | hospital, school, airport terminal, civic | awkward plot shape; tight access |
| `ancoats-infill` | 3 | house, office | no road frontage; poor, wet ground; awkward plot shape |
| `ancoats-phoenix-ironworks` | 3 | school, hospital, office, civic | neighbours close to the boundary; made ground |
| `camden-station-infill` | 3 | house, civic | neighbours close to the boundary; tight access; made ground |
| `glasgow-allotments` | 3 | school, house | awkward plot shape; sloping site; trees to protect |
| `middlehaven-docks` | 3 | hospital, office, school | neighbours close to the boundary; sloping site; awkward plot shape |
| `northstowe-powerline` | 3 | house, school | no road frontage; overhead or buried lines |
| `cambourne-centre` | 4 | school, house, civic, police station | neighbours close to the boundary; road or path crosses the plot; poor, wet ground |
| `liverpool-warehouse-clearance` | 4 | house, school, office | neighbours close to the boundary; no road frontage; existing buildings to clear |
| `mk-central-carpark` | 4 | school, police station, office, civic | tight access; road or path crosses the plot; neighbours close to the boundary |
| `shaftesbury-hillside` | 4 | school, house | sloping site; no road frontage; awkward plot shape |
| `sheffield-city-gap` | 4 | office, house | no road frontage; neighbours close to the boundary; protected neighbours |
| `tewkesbury-floodplain` | 4 | police station, school, house, civic | road or path crosses the plot; neighbours close to the boundary; poor, wet ground |
| `york-castle-gateway` | 4 | police station, office, civic | neighbours close to the boundary; existing buildings to clear; poor, wet ground |
| `addenbrookes-car-park` | 5 | hospital | neighbours close to the boundary; awkward plot shape; tight access |
| `bath-hillside-garages` | 5 | house | neighbours close to the boundary; sloping site; no road frontage |
| `clovelly-cliffside` | 5 | house | sloping site; no road frontage; neighbours close to the boundary |
| `edinburgh-parliament-square` | 5 | civic, office, police station | neighbours close to the boundary; sloping site; road or path crosses the plot |
| `hebden-bridge-garden-street` | 5 | police station, civic | sloping site; neighbours close to the boundary; awkward plot shape |
| `robin-hoods-bay` | 5 | house | sloping site; road or path crosses the plot; awkward plot shape |

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

The `.gdignore` keeps Godot from importing the Python tool and cache. The `sites` module's
curated pool (`SitePool`) reads the packs straight from `res://tools/osm/samples`, so
`build-all` updates the game's sites too.
