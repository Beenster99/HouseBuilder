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

On the building (`modules/building` api):

```gdscript
var report := StructureBuilding.stress_test(model)  # BuildingModel
report.part_envelope("p12"); report.failed_parts()
report.brief_result()      # {"ok", "failures": part ids, "worst", "scenario"} for contracts
StructureBuilding.collapse_after(model, ["p7"])      # part ids that fall if p7 goes
```

In a session only the host solves. `StructureBus` (`Modules.bus("structure")`):
`run_stress_test()` from anyone tests the shared building (`Modules.bus("building").model`;
`set_graph_provider(callable)` to test something else), and `report_changed(report)` fires on
every peer. The report is the event payload, so clients never solve; `report.digest()` is
equal on every peer, and late joiners get the last report in the join snapshot.

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

Beams split into pieces along one line (a beam with joists landing on it, a wall top) share
a `chain` and are bent span by span between the points where load leaves them.

**From a BuildingModel** (`internal/building_adapter.gd`): columns, beams, braces and trusses
become members split wherever another part's end or a connection lies on them (nodes are
keyed by position to 1 cm). A load-bearing wall becomes uprights at least every metre and at
the edges of its openings, tied by the wall spanning as a deep beam along its top and bottom
(over an opening only as deep as the wall above it). Slabs and roofs become plates: their
area goes to the nearest beam or wall top under them, with dead, room live (from the room
types) and snow loads, and each is checked over its shortest span between opposite
supports, or as a cantilever. Ground slabs with nothing under them bear on the ground.
Foundations anchor the nodes standing on them with the soil's bearing (`model.meta.soil`,
default clay); a strip or raft spreads its load over its whole area. Section strengths come
from the catalog's raw properties (`internal/section_props.gd`: steel at fy, timber with
load-duration factors, reinforced concrete rules of thumb, Rankine buckling for columns).

Simplifications for now: no overturning axial in columns, no deflection checks, each floor
acts as one rigid plate, spans are simply supported (no continuity), a column or wall
standing on a slab with nothing under it is unsupported (put a beam under it), non-structural
walls count only through the floor finishes allowance. A stiffness-matrix solver can replace
`internal/load_path_solver.gd` behind the same api and data.

## In the design room

With flag `structure.stress_test` on and the design module loaded, the bus adds a
"Stress test" button to the room's top bar and an "Engineer" view to its View picker
(found by name, so structure does not depend on design). The view colours each building
part by its worst utilisation over every scenario: green under 70%, amber to 100%, red
past it. Its side panel (`internal/stress_panel.gd`) shows the verdict, each scenario and
the notes on what failed and what to try. Every player sees the host's report.

## The engineer designs the structure

`StructureDesigner.design(model)` stress tests a BuildingModel and fixes what fails, round
after round, only by adding parts or upsizing sections: the next stronger section first,
then a column (down to a pad footing) under the middle of a beam, a steel beam across the
middle of an overloaded floor or flat roof, and columns under anything nothing holds up.
It never touches the model it is given: it returns `{op, notes, before, after, passed,
added, upsized}`, where `op` is one `BuildingCommands.batch` (one undo for everyone). Since
it is a dry run, other modules can use it to ask whether a design can be made to stand
and what that adds.

`StructureBus.design_structure()` (the "Design structure" button on the design room's top
bar and in the Engineer panel) runs it on the shared building, sends the edit through the
building sync, asks for a fresh stress test and emits `design_done(notes)`.


## Performance

- Graph building indexes candidate points and nodes in grid cells, and each floor finds its
  supports through a bucket grid, so it grows about linearly with the building.
- How a floor's load splits among its supports is cached by everything it depends on (a
  fingerprint of the floor, its supports and the rooms on it), so after an edit only the
  floors it touched are worked out again.
- On buildings with 400 or more members the scenarios solve on separate threads; they only
  read the solver, so the numbers are the same (tested).
- The live check never copies the building on the main thread after the first time: the
  bus queues each applied op and the worker replays them on its own copy (`_mirror`). It
  sends `StructureReport.compact()` (the verdict, notes, per-part utilisation and only the
  failing and worst rows), a fraction of the full report's size.
- "Stress test" and "Design structure" in a game go through the live check, so neither
  solves on a frame. The bus waits for a running check before it is freed, so quitting
  mid-check is safe.
