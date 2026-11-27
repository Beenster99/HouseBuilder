# sites module

Real-world plots in game (Phase 6): site packs made by `tools/osm` (format:
`tools/osm/FORMAT.md`) loaded, shared with the crew and drawn. Owned by the "Load real-world
sites in game" thread.

| Class | What it is |
| --- | --- |
| `SitePack` | One pack read into data: `height_at(x, z)`, `plot_outline()`, `ground()`, `soil()` and `structure_soil()`, `difficulty()`, `factors()`, `cost_multiplier_hint()`, `notes_text()`, `neighbours()`, `protected_ids()`, `attribution()`, `features(kind)`. |
| `SitePool` | The curated pool (`res://tools/osm/samples`): `list()`, `for_building(type)`, `pick(type, seed, max_rating)`, `open(id)`. |
| `SitesBus` | `Modules.bus("sites")`: `load_site(id)` (any player; the host loads it), `clear_site()`, `current()`, `make_view()`, signal `site_changed(pack)`. |

The host sends the whole pack file, zstd-compressed (about 40% of its size), as the
`sites.load` event, with an md5 digest each peer checks; joiners get it in the snapshot, so
every player builds on the identical site. On the host, loading a site writes the plot's soil
(`firm` → `clay`, `made_ground`, `soft_wet` → `soft_clay`) and the site id into the shared
building's design meta, which the structure module's foundations read.

`make_view()` returns a Node3D: terrain coloured by land use (with a height-map collider),
extruded neighbour buildings, roads and paths, railways, waterways, barriers, trees, power
lines and the plot outlined in orange. Buildings on the plot are orange too (brownfield:
clear them first). Every building gets a static collider; neighbours are in group
`site_neighbours` with meta `site_building` (pack id), `protected` and `site_building_data`,
for demolition scoring. y = 0 is the plot's mean ground, matching the building model.

Flag `sites.real_sites` adds "Real sites" to the main menu: a list of the pool with previews,
and a viewer with an orbit camera, the plot's problems and the OpenStreetMap credits.

Packs are read from `res://tools/osm/samples`, which `tools/.gdignore` keeps out of exported
builds: a release build needs the packs copied in or an export include filter.
