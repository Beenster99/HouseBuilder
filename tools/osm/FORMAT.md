# Site pack format, version 1

A site pack is one UTF-8 JSON file, `<id>.sitepack.json`, describing a real place around a
build plot: terrain, neighbouring buildings, roads, land use, trees, overhead lines, and the
plot itself with a difficulty rating. It is written by `tools/osm` and read by the in-game
loader (the `sites` module). The host sends the same file to every player, so everyone builds
on an identical site.

Typical size is 150 to 450 KB for a 300 m radius. Godot reads it with `JSON.parse_string`.

## Conventions

- **Units** are metres, SI throughout.
- **Axes** match the game: `x` east, `y` up, `z` south, so `-z` is north (Godot's forward).
- **Plan points** are `[x, z]` pairs. Heights are separate `y` values.
- **Datum**: `y = 0` is the plot's mean ground level. `origin.elevation_m` is that level
  above sea level, so `y = -origin.elevation_m` is sea level (also given as
  `terrain.sea_level_y`).
- **Origin**: `(0, 0)` in plan is the centre point the pack was built around
  (`origin.lat`, `origin.lon`). The plot is usually near, but not always at, the origin.
- **Rings** (outlines) are open: the last point is not repeated. Outer rings run
  counter-clockwise as seen on a north-up map; holes run clockwise.
- **Ids** are the OpenStreetMap ids: `w123` a way, `r456` a relation, `n789` a node. A
  relation split into several outer rings gets `r456.0`, `r456.1`, and so on.
- Optional keys are left out rather than set to null. Loaders should ignore unknown keys,
  so later versions can add fields without breaking older readers.

## Top level

| key | type | meaning |
|---|---|---|
| `format` | string | always `"housebuilder.sitepack"` |
| `version` | int | `1`. A loader should refuse a higher major version. |
| `id` | string | file-safe id, matches the file name |
| `name`, `description` | string | shown to players |
| `suited_to` | string[] | building types this plot was curated for (`house`, `school`, `police_station`, `hospital`, `office`, `airport_terminal`) |
| `attribution` | string[] | lines that must be shown in game wherever the site is used |
| `licence` | object | `osm_derived: "ODbL-1.0"` and a note |
| `generator` | object | tool, creation time, simplification tolerances |
| `origin` | object | `lat`, `lon`, `elevation_m` (see Datum) |
| `axes` | string | human-readable reminder of the conventions above |
| `radius_m` | number | features are kept if any part lies inside this circle |
| `terrain` | object | height grid, below |
| `plot` | object | the build site, below |
| `buildings`, `roads`, `paths`, `railways`, `waterways`, `areas`, `trees`, `power_lines`, `barriers` | arrays | neighbourhood features, below |

## `terrain`

A regular grid of ground heights covering the square around the radius.

| key | meaning |
|---|---|
| `origin` | `[x, z]` of the first sample (the north-west corner) |
| `spacing_m` | distance between samples (4 m by default) |
| `size` | `[nx, nz]` sample counts |
| `heights_b64` | base64 of `nx * nz` little-endian float32 `y` values. Row-major: row `j` is at `z = origin.z + j * spacing` (rows run north to south), column `i` at `x = origin.x + i * spacing` (west to east). Index `j * nx + i`. |
| `min_y`, `max_y` | range of the grid |
| `sea_level_y` | `y` of sea level |
| `encoding`, `source` | descriptive |

In GDScript: `Marshalls.base64_to_raw(t.heights_b64).to_float32_array()`. Sample with
bilinear interpolation, clamped at the edges. Heights come from a ~3 to 5 m elevation
model, so they are smooth: OSM `barriers` with `kind: retaining_wall` mark sharper steps.

## `plot`

| key | meaning |
|---|---|
| `outline` | ring of the build site |
| `source` | how it was chosen: `{method: "spec" or "auto-area" or "auto-rect", osm?: id}` |
| `area_m2`, `perimeter_m` | size |
| `bounding_rect` | minimum-area rectangle: `width_m` (long side), `depth_m`, `angle_deg` of the long side from +x |
| `compactness` | area divided by bounding rectangle area; 1 is a rectangle |
| `ground` | `min_y`, `max_y`, `mean_y`, `slope_pct` (best-fit plane), `downhill` (compass word), `soil`, `wet`, `piles_suggested` |
| `access` | vehicle roads that front the plot: `{road, name, kind, width_m, frontage_m}`, longest frontage first; empty means no road access |
| `existing_buildings` | ids of buildings standing on the plot (brownfield: clear them first) |
| `difficulty` | rating, below |
| `notes` | optional curator's notes |

`ground.soil` is one of `firm`, `made_ground` (previously developed land), `soft_wet`
(next to water or low lying beside a river). The foundations system should read it.

### `plot.difficulty`

| key | meaning |
|---|---|
| `rating` | 1 (easy) to 5 (very hard) |
| `score` | sum of factor severities |
| `cost_multiplier_hint` | a suggested build cost multiplier, `1 + 0.06 * score`. Contracts decide the real effect. |
| `factors` | list, most severe first: `{id, severity 1-3, label, detail, metrics}` |

Factor ids, so game logic can react to them:

| id | what it means | metrics |
|---|---|---|
| `slope` | the ground falls across the plot | `slope_pct`, `relief_m`, `downhill` |
| `shape` | irregular, long and thin, or narrow | `compactness`, `width_m`, `depth_m` |
| `access` | no road frontage, or only narrow, single or short frontage | `frontage_m`, `roads` or `nearest_road_m` |
| `right_of_way` | a road or public path crosses the plot | `count` |
| `neighbours` | buildings within 6 m of the boundary, or on it | `count`, `nearest_m` |
| `heritage` | listed or historic buildings within 25 m | `count` |
| `existing_buildings` | buildings on the plot to demolish first | `count`, `footprint_m2` |
| `trees` | trees on or at the boundary, or woodland edge | `on_plot`, `boundary`, `protected` |
| `overhead_lines` | power lines crossing or near (buried cables count lightly) | |
| `railway` | a surface railway within 20 m | `distance_m` |
| `ground` | wet ground (needs piles or a raft) or made ground | `reasons` |

`label` and `detail` are written for players and can be shown as they are.

## Features

Every feature has `id` and `kind`. Lines are `line: [[x, z], ...]`; polygons are
`outline` plus optional `holes`.

**`buildings`**: `kind` is the OSM `building` value (`house`, `terrace`, `apartments`,
`retail`, `church`, `yes`, ...). `outline`, `holes?`, `base_y` (lowest ground under the
outline: extrude from here), `ground_max_y` (highest ground, so a loader can add a plinth on
slopes), `height_m` (eaves or roof top as tagged; top is `base_y + height_m`),
`height_source` (`tag`, `levels` or `default` when OSM had nothing and a typical height for
the kind was used), `levels?`, `min_height_m?` (for overhangs and bridges), `roof_shape?`,
`material?`, `name?`, `house_number?`, `on_plot` (true for buildings standing on the plot),
`protected` (listed or historic: demolition must not damage it).

**`roads`**: vehicle roads. `kind` is the OSM `highway` value. `width_m` (from tags or a
default per kind), `name?`, `ref?`, `surface?`, `lanes?`, `oneway?` (`true`, or `-1` for
against the drawing direction), `bridge?`, `tunnel?`, `layer?`, `sidewalk?`. Roads are cut
to the radius, so one OSM road can appear as several runs with the same id. Lines carry no
heights: drape them on the terrain unless `bridge` or `tunnel`.

**`paths`**: footways, cycleways, steps and the like; same fields as roads.

**`railways`**: `kind` is the OSM `railway` value, with `tunnel?`. Do not draw tunnels or
`kind: subway`; the plot rating ignores them too.

**`waterways`**: rivers, streams, canals and drains as centre lines with `width_m`. Broad
water also appears in `areas` as `natural:water` or `waterway:riverbank`.

**`areas`**: land use and surface polygons. `kind` is `key:value` from OSM, for example
`landuse:grass`, `landuse:residential`, `natural:water`, `natural:wood`, `amenity:parking`,
`leisure:park`. Draw smaller areas over larger ones. `name?`, `surface?`.

**`trees`**: `pos` `[x, z]`, `base_y`, `height_m` (default 9), `crown_m` diameter
(default 6), `leaf_type?`, `protected?`. Tree rows are expanded into single trees every 6 m.

**`power_lines`**: `kind` is `line` (high voltage, on pylons), `minor_line` (on poles) or
`cable` (buried; do not draw). `height_m` is the wire height (tagged, or 15 and 8 by
default), `voltage?`.

**`barriers`**: walls, fences, hedges and retaining walls as lines with `height_m`.

## Licence

Site packs are derived from OpenStreetMap and so are under the Open Database Licence
(ODbL 1.0). Show "© OpenStreetMap contributors" in game wherever a real site appears and in
the credits, and keep packs (and any edited versions) available under the ODbL. The
`attribution` array carries the exact lines, including the terrain source.

## Changes

Additive changes (new optional keys, new factor ids, new area kinds) keep `version: 1`.
Anything that changes the meaning of an existing key bumps the version.
