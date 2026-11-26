# structure module

Layer 1 of the plan's structural simulation: a deterministic, headless structural graph
solver and the stress tests (normal use, storm, quake) with a plain-language failure report.
Owned by the "Build the structural stress solver" thread.

## Using it

```gdscript
var g := StructureGraph.new()                       # api/structure_graph.gd
g.add_anchor("f1", Vector3(0, 0, 0), StructureSections.foundation_capacity("pad", 1.0, "clay"))
g.add_node("n1", Vector3(0, 3, 0))
g.add_member("c1", "f1", "n1", StructureGraph.COLUMN, "steel.uc_203x203x46")
...
g.add_area_load("f0", "live", StructureLoads.live_kpa("bedroom"))   # kPa over the member's width
g.auto_wind_areas(3.0)

var report := StructureSolver.stress_test(g)        # normal use, storm, quake
report.passed(); report.summary; report.notes       # "Beam f0 spans 6.0 m and bends at 140% ..."
report.envelope("f0"); report.status("f0")          # utilisation, "green" | "amber" | "red"
report.first_failure()                              # {"scenario", "id", "u"}
```

In a session only the host solves. `StructureBus` (`Modules.bus("structure")`):
`set_graph_provider(callable)` on the host, `run_stress_test()` from anyone, and
`report_changed(report)` on every peer. The report is the event payload, so clients never
solve; `report.digest()` is equal on every peer, and late joiners get the last report in the
join snapshot.

## The model

Members are edges, connections are nodes, foundations are anchor nodes with a bearing
capacity. Units are metres and kN, Y up.

- **Gravity**: each node's route to the ground is the cheapest path to a foundation (a metre
  of post costs 1, diagonal 2, beam 4). A node passes its load to the members leading nearer
  the ground, shared by 1 / route cost (for a beam split at a point load this is exactly the
  lever rule). Posts and diagonals carry it axially; beams bend. A beam whose end has no
  other support is a cantilever; one between two supports is simply supported.
- **Sideways** (wind on each node's facade area, quake as a fraction of weight), tried from
  four directions: beams tie nodes into floors; each floor shares its storey shear among the
  posts, braces and walls below by stiffness (a brace or wall in line is far stiffer than a
  post), and passes it down. Posts bend, braces take it axially, walls rack in shear.
- **Utilisation** = axial / capacity + moment / capacity, or shear / capacity if higher.
  Green under 0.7, amber to 1.0, red (failed) over 1.0. Members with no path to a
  foundation get 99 ("unsupported").
- Sections, soils and foundation capacities: `api/structure_sections.gd`; floor loads by room
  type: `api/structure_loads.gd`. Game values for playtesting, not a design code.

Simplifications for now: no overturning axial in columns, no deflection checks, each floor
acts as one rigid plate. A stiffness-matrix solver can replace `internal/load_path_solver.gd`
behind the same api and data.

## Still to come

- Adapter from the building module's BuildingModel once its api is on main.
- The stress test button and utilisation overlay in the design room (flag
  `structure.stress_test`, off).
