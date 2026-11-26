# FredDibnah

A co-op Godot game: design a real building together (house to airport), watch it built in a
timelapse, then bring it down precisely with targeted charges and a wrecking ball. Modes:
sandbox, contracts with briefs and budgets, and real-world sites from OpenStreetMap.

Godot **4.7.2** (standard build, not .NET), static-typed GDScript, Jolt physics, SI units,
-Z forward. Up to 3 players, peer to peer: one player hosts, the others join by LAN or IP.

The plan: https://claude.ai/artifact/5m7ZUQnW8UJnCHLfKjqB2b

## Running it

1. Install Godot 4.7.2 and open this folder as a project.
2. Press Play. Play Online hosts or joins a session (port 24570, opened with UPnP).
3. Two copies on one PC without the menus: `godot --path . -- --host` in one terminal and
   `godot --path . -- --join=127.0.0.1` in another. Both open the sandbox site.

## Layout

The module layout, rules and tools are BSX Ltd's (see SOURCES.md for what was copied):

```
modules/<id>/          one folder per module
  api/                 the only part other modules may use (bus script, public classes)
  internal/            everything else
  tests/               test_*.gd, run headless
  module.tres          id, depends_on, flag, bus script
config/project_flags.tres   the active feature flags
tools/run_tests.sh          every module's tests   (GODOT=godot tools/run_tests.sh [module])
tools/check_boundaries.py   the module dependency rules
tools/osm/                  offline OpenStreetMap to site pack tool
```

Modules now: core, ui (the shell), multiplayer (sessions, crew, sync), sandbox (Phase 0
shared site), timelapse (construction schedule and synced playback; Timelapse demo on the
main menu). Planned: building, design, structure, demolition, contracts, sites.

## Module rules

1. Use another module only through its `api/` folder, and only if it is in your
   `module.tres` `depends_on`. Everyone may use `core/api` and `ui/api`. Core never uses UI.
2. Talk through buses: `Modules.bus("<id>")`. Never reach into another module's scenes.
3. Register with Core from your bus's `register_module()`: `Router.register_scene`,
   `Menu.register_entry`, `HudSlots.register_panel`, `Settings.register`,
   `Saves.register_section`.
4. Every change to shared game state is a request the host validates and broadcasts as an
   event (`MultiplayerBus.register_event` / `request`). Solo play is a session of one, so
   the same code runs offline and online.
5. Things that move every frame (cursors, cranes, debris) are movers
   (`MultiplayerBus.register_mover`), streamed 20 times a second and interpolated.
6. Gate new player-facing work behind a flag: `Flags.is_on("<module>.<feature>")`.
