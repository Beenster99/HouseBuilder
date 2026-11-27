# perf: profiler, desync check, 60 fps budgets

Target: 60 fps on the host with 3 players, and every player seeing the same game.

- **Overlay**: press **F3** in game (flag `perf.overlay`). Frame rate and percentiles against
  the target, CPU script and physics time, draw calls, triangles, nodes, memory, players,
  round trip, upload/download, movers, view delay, sync status, and every engine custom
  monitor (`Performance.add_custom_monitor("fred/<module>/<what>", ...)`, no dependency on
  this module needed). The editor's Profiler, Visual Profiler and Monitors tabs give
  per-function detail.
- **Desync check** (flag `perf.desync_check`): while online, the host sends a fingerprint of
  the shared state every 3 s as an ordinary event, so each peer compares at the same point
  in the event order. Mismatches are logged, shown red on the overlay and reported to the
  host. Sections: building, demolition; add more with
  `Modules.bus("perf").register_digest("<section>", callable)`.
- **Tests** (`GODOT=godot tools/run_tests.sh perf`):
  - `test_budgets.gd`: edits, costing, stress test, M&E routing, design room open/idle/edit,
    demolition physics, bodies and network bytes on house, office and airport-terminal
    buildings (`ScaleBuildings`), against `PerfBudget`. Known over-budget items are listed
    with their owner (a ratchet: they fail if they get 2x worse; lower the entry when you
    speed one up). `PERF_FULL=1` also measures the very slow known items.
  - `test_three_players.gd`: three processes over ENet; everyone edits an office, every
    check must match within 0.25 s, and a deliberately diverged player must be caught.
  - `test_digest.gd`, `test_frame_stats.gd`: the fingerprints and the frame maths.
- **Benchmark** on your own PC, real rendering, 3 players (two headless copies join):
  `godot --path . -- --bench` (options: `--bench=design_office,demolition_office`,
  `--solo`, `--look=realistic`). Prints a row per scenario, saves JSON to `user://perf/`,
  exits 1 if any scenario misses 60 fps or desyncs.
