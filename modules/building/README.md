# building module

The building as data: levels, parts, connections and rooms, the part catalog, edit ops with
shared undo and redo, save and load, and the network sync. No scenes; it runs headless.
Every other module (design, structure, timelapse, demolition, contracts) reads the
building through `api/` only.

## Classes (api/)

| Class | What it is |
| --- | --- |
| `BuildingModel` | The building. Read its `parts`, `rooms`, `connections`, `levels`; change it only with `apply(op)`. Signals `changed(op)`, `entry_added/changed/removed(id)`, `levels_changed`, `loaded`; `revision` goes up on every change. Save with `to_data()` / `from_data()` / `save_file()` / `load_file()`; `checksum()` to compare copies. |
| `BuildingCommands` | Builds ops: `place_part`, `place_opening`, `place_stair`, `place_lift`, `place_room`, `rect`, `connect_parts`, `move`, `delete`, `retag`, `set_fields`, `add_level`, `set_level`, `remove_level`, `set_design_meta`, `batch`. |
| `BuildingHistory` | Host-side undo and redo, one stack per player; `commit(op, author, group)` (same group = one undo step, for drags), `undo(author)`, `redo(author)`, `log`. |
| `BuildingSync` | Shares a model through a `MultiplayerBus`: `bind(net, prefix)`, `edit(op, group)`, `undo()`, `redo()`, `load_design(data)`. Host validates and broadcasts; joiners get a snapshot; claimed entries refuse other players' edits; `desync` signal on checksum mismatch. Unbound, it applies locally. |
| `BuildingCatalog` | Materials, sections, part kinds, room types, rates. `default_catalog()`, `kind()`, `kinds_in(family)`, `sections_for(kind, material)`, `section()`, `room_type()`, `rate()`. |
| `BuildingQuantities` | `part(model, id)` → length, area, volume, mass, cost; `room(model, id)` → area, fit-out cost, capacity; `totals(model)` → cost split by family, material, level. |
| `BuildingBus` | `Modules.bus("building")`: the shared `model`, its `sync` (bound to the global multiplayer bus) and `catalog`. Save section `"building"`. |

## Data shapes

Metres, y up, -Z forward. A part's y values are relative to its level's floor; level n's floor
is at `model.level_elevation(n)`.

```
part (shape "point")   {id, kind, material, section?, level, at: [x,y,z], rot, height?, length?, w?, d?, top_level? (lift)}
part (shape "line")    {id, kind, material, section?, level, a: [x,y,z], b: [x,y,z], height?, w? (stair)}
part (shape "area")    {id, kind, material, section?, level, outline: [[x,z],...], y, pitch?}
part (shape "opening") {id, kind, material, host: wall id, t: centre from the wall's a, w?, h?, sill?}
room                   {id, type, level, outline: [[x,z],...], name}
connection             {id, a, b, kind ("pinned" | "fixed" | "bearing"), at?: [x,y,z] world}
```

Families (`catalog.family_of(kind)`): foundation, column, beam, brace, truss, slab, roof,
wall, opening, fixture, circulation (`stair`: one flight up to the next level; `lift`: a
shaft from its level up to `top_level`). World-space helpers: `points_of(id)`, `aabb_of(id)`,
`footprint(id)`, `voids_on(level)` (holes the floor needs for stairs and lifts),
`part_height(id)`, `openings_in(wall)`, `connections_of(part)`, `parts_on(level)`,
`rooms_on(level)`, `parts_of_family(f)`.

Speed: `openings_in`, `connections_of` and `connection_between` read indexes the model keeps
up to date; `parts_on`, `rooms_on` and `parts_of_family` are cached until the next change, so
calling them per part or per room is fine. `BuildingQuantities.totals()` keeps each part's and
room's result on the model and recosts only what an edit touched: on the 4,000-part airport
terminal it takes about 50 ms the first time and about 19 ms after an edit (headless).
`checksum()` hashes everything (about 35 ms on the terminal): compare `revision` first.

## Library assets as parts

With flag `building.library` (on since 2026-11-27), `BuildingCatalog.default_catalog()` also holds the 3D
library's placeable assets (about 730: furniture, equipment, services plant, street and
garden objects, vehicles, site plant) as `fixture` kinds whose id is the asset id
(`"office.desk.bench_4"`). Each spec adds `asset`, `group` (palette heading), `category`,
`tags`, `loose` (vehicles, site plant, luggage: not part of the build, cost 0) and `outdoor`.
`cat.services_of(kind)` gives `{power_w, cold, hot, drain, gas, data, heating, heat_w, gen_w}`
for every fixture, `cat.group_of(kind)` the palette group, `cat.library_kinds()` the list.
Prices, services and capacities are in `internal/library_data.gd` (rules by id prefix).
Placing, costing, saving and syncing need nothing new: they are ordinary point parts.

## Ops

See the header of `api/building_model.gd`. `apply(op)` returns `{}` (refused) or
`{"do", "undo"}`; `do` carries the ids the model chose and is what the host broadcasts.

## Catalog data

`internal/catalog_data.gd`. Costs are approximate UK installed rates (GBP, 2025 to 2026), to
tune. Material strengths and section properties (area, iy, wy, kg_m) are there for the
structure module to use; design capacities and checks belong to structure.

## Tests

`tools/run_tests.sh building`: the model's edits and undo, save and load round trips,
shared undo, quantities, and two and three players over ENet on localhost.
