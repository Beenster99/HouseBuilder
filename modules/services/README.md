# services module

The M&E (mechanical and electrical) consultant from the plan's design room section: it
finds the cheapest routes for wiring and piping through the building, prices them, and
checks every room is powered and every wet room plumbed. Headless and deterministic; it
reads the building only through `modules/building/api` (and, for the feasibility verdict,
the structure and contracts apis). Owned by the "Build mechanical and
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

**Design services**: `ServicesDesigner.propose(model)` (or `bus.design_services()`) does the
design work: it fits out bare wet rooms (bathroom: WC, basin, bath; WC: WC, basin; kitchen
and utility: a sink unit; toilets and commercial kitchens more), lined up on the wall
nearest the soil stack, then places a consumer unit, water main, boiler and soil stack part
where the routes start. The bus sends it to the building as one batch edit (one undo step
for everyone) and routes again. It only adds; it never moves what players drew.

**Check feasibility**: `FeasibilityReview.review(model, brief?)` (or
`bus.review_feasibility()`, which uses the active contract's brief) gives one verdict: does
it pass the structural stress tests (structure module), is every room powered and plumbed,
does it meet the brief's requirements, and is the all-in cost (the building's own price plus
the services routes, which the catalog's fit-out rates do not cover) within budget. It lists
the issues worst first, each with what to do, and works on each player's shared copy of the
building, so everyone gets the same answer.

When structure fails, the verdict also runs the structural engineer's Design structure
(StructureDesigner) and Design services as dry runs on a copy: `fixes` says what each would
add and cost, `fixable` whether together they make it feasible, and `cost.after_fixes` the
all-in price then ("Design structure would make it work, at £160,110 all in").

**Live** (flag `services.live`, on): `watch(model)` (the shared building, by default) restarts
a one-second timer on every change; when it runs out the host routes the services again
for everyone and each player's verdict is redone on a worker thread (`review_done`,
`last_review()`), so the room never stalls. The design room shows it in an always-on
"Feasibility" window (`design.register_panel`, order 15) with a tick or cross per area:
structure, services, brief, cost.

In the design room (flag `services.consultant`, on): "Route services", "Design services" and
"Check feasibility" on the top bar, and an "M&E" view that tints rooms green (served) or red (missing
something), source units blue, with a side panel of the summary, per-system length and cost,
the notes and both buttons.

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
  `soil_stack` (priced by the building, not again here); else the players' placed source; else the
  consultant chooses (plant room, utility, garage, hallway...; consumer unit by the front
  door, water main on the street side, stack under the WCs) and says so.
- Rates are approximate UK installed costs (2025 to 2026) to tune in playtesting.
- Speed: nothing heavy runs on the main thread. Routing (host), Design services and the
  feasibility review run on worker threads on a copy of the building; the main thread only
  takes the building's to_data() snapshot (about 10 ms on a 128-room office, 35 ms on a
  384-room terminal) and applies the report. The grid coarsens past 12,000 cells, so a
  house routes in about 16 ms, the office in about 350 ms and the terminal in about 800 ms.

## Still to come

- A riser fixture kind, so players can mark where vertical runs go.
- Drawing the route lines themselves in the design room (the view only tints entries now).
- Contracts reading `report.passed()` and `report.total_cost` for briefs.
- Ventilation and heating runs; incremental re-routing on big buildings.
