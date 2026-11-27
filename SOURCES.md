# Code copied from BSX Ltd

| Path | From | Commit |
| --- | --- | --- |
| modules/core/ | Beenster99/BSXLtd modules/core/ | 3f178e476f6284465013d6a68c0fe8f10d32237a |
| modules/ui/ | Beenster99/BSXLtd modules/ui/ | same |
| modules/multiplayer/ | Beenster99/BSXLtd modules/multiplayer/ | same |
| tools/run_tests.sh, tools/check_boundaries.py, Makefile | Beenster99/BSXLtd | same |

Changes made on copy: player cap 3 (MultiplayerBus.MAX_CREW), UPnP description, flag set,
core tests that named BSX-only modules, default player name "Builder". Port fixes between the two games on purpose and
record them here.

Fixes since the copy (worth porting back to BSX Ltd):
- NetMovers and CrewChannel no longer error ("previously freed instance") when a scene change
  frees a registered mover or avatar before it is unregistered.
- Crew avatars appear only in scenes whose root has meta `crew_avatars` = true (BSX's
  first-person scenes would set it); FredDibnah's overhead views use cursors instead.
- net_stats() no longer reports everything sent before its first call as one second of traffic.
- New in core here, not in BSX: ArtStyle and the Graphics "Look" option.
