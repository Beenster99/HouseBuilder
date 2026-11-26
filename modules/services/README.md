# services module

The M&E (mechanical and electrical) consultant from the plan's design room section: it
finds the cheapest routes for wiring and piping through the building, prices them, and
checks every room is powered and every wet room plumbed. Headless and deterministic; it
reads the building only through `modules/building/api`. Owned by the "Build mechanical and
electrical routing" thread.

## Using it

```gdscript
var report := ServicesConsultant.route(model)          # api/services_consultant.gd
report.passed()                    # every room powered, every wet room plumbed
report.summary                     # "Every room is powered and every wet room plumbed: £14,210 in total."
report.notes                       # per system length and cost, where sources went, what failed and why
report.warnings                    # e.g. a WC more than 6 m of pipe from the soil stack
report.system("waste")             # {source, length, run_cost, hole_cost, cost, holes, branches, unserved}
report.room("r4")                  # {name, type, wet, powered, plumbed, missing}
report.routes("power")             # world-space polylines, for an overlay
```

In a session only the host routes. `ServicesBus` (`Modules.bus("services")`):
`run_consultant()` from anyone, `place_source(system, level, Vector2(x, z))` /
`clear_source(system)` to pin the consumer unit, water main, boiler or soil stack, and
`report_changed(report)` on every peer. The report is the event payload, so clients never
route; `report.digest()` is equal on every peer and late joiners get the sources and last
report in the join snapshot. Save section `"services"`: the placed sources.

With flag `services.consultant` on and the design module loaded, "Route services" appears on
the design room's top bar (`design.register_action`). Off for now.

## How it routes

Systems (`api/services_rates.gd`): **power** (consumer unit to a lighting and socket point in
every room, and the boiler), **cold water** (water main to every WC, basin, bath, shower,
kitchen sink and the boiler), **hot water** (boiler to every basin, bath, shower and sink),
**waste** (every wet fixture to the soil stack). Wet rooms (bathroom, WC, kitchen, utility,
toilets, commercial kitchen) with no fixtures yet are routed to their centre.

- **Grid**: cells (0.5 m, coarser on big buildings) over every level, inside wherever a room
  or slab is. Lift shafts are no-go.
- **Cost of a step** is money: metres times the system's rate (20% less in corridors, plant
  rooms and other service zones), plus a hole: £15 through a partition, £90 through a
  load-bearing wall, nothing through a door, £60 through a floor (£30 in a riser room such
  as a plant room or utility). Curtain walls cannot be crossed.
- **Network**: grown from the source; each round finds the cheapest path from the network
  to the nearest waiting point and adds it, so branches share runs (the shortest-path
  Steiner heuristic). Waste routes WCs first (110 mm rate) and never steps down a level
  while growing from the stack, so everything drains downhill.
- **Sources**: a building part of kind `consumer_unit`, `water_main`, `boiler` or
  `soil_stack` once the catalog has them; else the players' placed source; else the
  consultant chooses (plant room, utility, garage, hallway...; consumer unit by the front
  door, water main on the street side, stack under the WCs) and says so.
- Rates are approximate UK installed costs (2025 to 2026) to tune in playtesting.
- Speed: a two-storey house routes in a few milliseconds; a 60 by 30 m, three-storey office
  with 64 rooms in under a second, and its report is about 40 KB on the wire.

## Still to come

- Source and riser fixture kinds in the building catalog (asked of the building thread).
- Routes overlay and the room checklist in the design room; the quantity surveyor view.
- Contracts reading `report.passed()` and `report.total_cost` for briefs.
- Ventilation and heating runs; incremental re-routing on big buildings.
