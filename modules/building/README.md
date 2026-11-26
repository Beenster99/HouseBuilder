# building module

The building as data: levels, parts, connections and rooms, the part catalog, edit ops with
shared undo and redo, save and load, and the network sync. No scenes; it runs headless.
Every other module (design, structure, timelapse, demolition, contracts) reads the
building through `api/` only.

## Classes (api/)

| Class | What it is |
| --- | --- |
| `BuildingModel` | The building. Read its `parts`, `rooms`, `connections`, `levels`; change it only with `apply(op)`. Signals `changed(op)`, `entry_added/changed/removed(id)`, `levels_changed`, `loaded`; `revision` goes up on every change. Save with `to_data()` / `from_data()` / `save_file()` / `load_file()`; `checksum()` to compare copies. |
| `BuildingCommands` | Builds ops: `place_part`, `place_opening`, `place_room`, `rect`, `connect_parts`, `move`, `delete`, `retag`, `set_fields`, `add_level`, `set_level`, `remove_level`, `set_design_meta`, `batch`. |
| `BuildingHistory` | Host-side undo and redo, one stack per player; `commit(op, author, group)` (same group = one undo step, for drags), `undo(author)`, `redo(author)`, `log`. |
| `BuildingSync` | Shares a model through a `MultiplayerBus`: `bind(net, prefix)`, `edit(op, group)`, `undo()`, `redo()`, `load_design(data)`. Host validates and broadcasts; joiners get a snapshot; claimed entries refuse other players' edits; `desync` signal on checksum mismatch. Unbound, it applies locally. |
| `BuildingCatalog` | Materials, sections, part kinds, room types, rates. `default_catalog()`, `kind()`, `kinds_in(family)`, `sections_for(kind, material)`, `section()`, `room_type()`, `rate()`. |
| `BuildingQuantities` | `part(model, id)` → length, area, volume, mass, cost; `room(model, id)` → area, fit-out cost, capacity; `totals(model)` → cost split by family, material, level. |
| `BuildingBus` | `Modules.bus("building")`: the shared `model`, its `sync` (bound to the global multiplayer bus) and `catalog`. Save section `"building"`. |

## Data shapes

Metres, y up, -Z forward. A part's y values are relative to its level's floor; level n's floor
is at `model.level_elevation(n)`.

```
part (shape "point")   {id, kind, material, section?, level, at: [x,y,z], rot, height?, length?}
part (shape "line")    {id, kind, material, section?, level, a: [x,y,z], b: [x,y,z], height?}
part (shape "area")    {id, kind, material, section?, level, outline: [[x,z],...], y, pitch?}
part (shape "opening") {id, kind, material, host: wall id, t: centre from the wall's a, w?, h?, sill?}
room                   {id, type, level, outline: [[x,z],...], name}
connection             {id, a, b, kind ("pinned" | "fixed" | "bearing"), at?: [x,y,z] world}
```

Families (`catalog.family_of(kind)`): foundation, column, beam, brace, truss, slab, roof,
wall, opening, fixture. World-space helpers: `points_of(id)`, `aabb_of(id)`,
`part_height(id)`, `openings_in(wall)`, `connections_of(part)`, `parts_on(level)`,
`rooms_on(level)`, `parts_of_family(f)`.

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
