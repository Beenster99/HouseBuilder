# FredDibnah

Godot 4.7.2, GDScript, typed, tabs. Read README.md for the module rules; in short:

- Each project thread owns one `modules/<id>/`. Change other modules only through their
  owner's thread; use them only through their `api/` and your `module.tres` depends_on.
- Register scenes, menu entries, HUD panels, settings, save sections and screenshot points
  with Core from your bus's `register_module()`. Core and UI never name other modules.
- Gate new player-facing work behind a flag (`Flags.is_on("<module>.<feature>")`).
- No pull requests: the owner does not want to review or merge on GitHub. Before pushing to
  `main`, run `GODOT=<godot> tools/run_tests.sh` and `python3 tools/check_boundaries.py`,
  then `git pull --rebase origin main` and push. Keep commits small and to your own module.
- Module threads should not need to edit `project.godot`; ask the groundwork (Phase 0) thread if
  you do.
- modules/core, ui and multiplayer were copied from BSX Ltd (SOURCES.md). Keep fixes in step
  with BSX Ltd on purpose and note them in SOURCES.md.