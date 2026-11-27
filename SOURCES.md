# Code copied from BSX Ltd

| Path | From | Commit |
| --- | --- | --- |
| modules/core/ | Beenster99/BSXLtd modules/core/ | 3f178e476f6284465013d6a68c0fe8f10d32237a |
| modules/ui/ | Beenster99/BSXLtd modules/ui/ | same |
| modules/multiplayer/ | Beenster99/BSXLtd modules/multiplayer/ | same |
| tools/run_tests.sh, tools/check_boundaries.py, Makefile | Beenster99/BSXLtd | same |
| modules/walk/ | Beenster99/BSXLtd modules/design/internal/walk/ (walk_inside.gd, walk_build.gd), repurposed for the BuildingModel | same |

Changes made on copy: player cap 3 (MultiplayerBus.MAX_CREW), UPnP description, flag set,
core tests that named BSX-only modules, default player name "Builder". Port fixes between the two games on purpose and
record them here.

Fixes since the copy (worth porting back to BSX Ltd):
- NetMovers and CrewChannel no longer error ("previously freed instance") when a scene change
  frees a registered mover or avatar before it is unregistered.
- Crew avatars appear only in scenes whose root has meta `crew_avatars` = true (BSX's
  first-person scenes would set it); FredDibnah's overhead views use cursors instead.
- net_stats() no longer reports everything sent before its first call as one second of traffic.
- boot.gd loads the splash's scenes one at a time (no sub-threads): threaded requests for all of
  them at once deadlocked compiling scripts on many-core Windows PCs ("Loading scenes 5 / 11").
  BSX's boot.gd likely has the same bug.
- Graphics.apply_surfaces() no longer sets the surface_detail / surface_normal shader globals,
  which aren't declared here and printed errors.
- New in core here, not in BSX: ArtStyle and the Graphics "Look" option.

## Design hall (modules/design/internal/hall)

Ported from BSX Ltd at 3f178e4 and repurposed for buildings: hall_screen.gd (ui/api/touch_screen.gd),
hall_wall_board.gd (design/internal/room/wall_board.gd), hall_holo_table.gd (design/internal/holo/holo_table.gd,
the table and its controls; the model on it is FredDibnah's DesignView) and hall_scaled_box.gd
(design/internal/console/scaled_box.gd, unchanged).
