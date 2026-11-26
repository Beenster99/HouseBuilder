# design module

The co-op design room: the shared drafting space where up to three players draw the
building together on a snap grid (0.25 m by default, 0.1 to 1 m). The building itself is the
building module's `BuildingModel`; this module is the tools, cursors, selections, soft locks,
the live cost panel and the design library. Start on the main menu opens it.

## Classes

| File | What it is |
| --- | --- |
| `api/design_bus.gd` (`DesignBus`) | Registers the room scene (Start, priority 20) and lets other modules add top-bar buttons: `register_action(id, label, press(model), order)` (the timelapse's "Build it"). |
| `internal/design_session.gd` (`DesignSession`) | The room's logic with no scene: tools, snapping, picking, drags, undo and redo, levels, save and load. Tests drive it directly, two or three on their own buses. |
| `internal/design_presence.gd` (`DesignPresence`) | Selections (host-validated event `design.select`), soft locks (session claims, which the building's host validator honours; they lapse 8 s after a drag stops moving) and cursors (movers `player:<peer>:design_cursor` / `design_anchor`). |
| `internal/design_snap.gd` (`DesignSnap`) | Grid, corner and 45° snapping. |
| `internal/design_costs.gd` (`DesignCosts`) | The cost panel's numbers and notes with tips, from `BuildingQuantities`. |
| `internal/room/` | The scene: `design_room` (world, input, crew marks, ghost), `design_view` (draws the model; the 2D plan cuts walls at 1.2 m), `design_camera` (orbit and plan), `design_hud`. |

## Controls

Left click or drag uses the tool. Right drag orbits (3D), middle drag pans, wheel zooms.
1 to 0 pick tools; Tab switches 3D and the 2D plan; Page Up/Down change level; Del deletes;
Ctrl+Z / Ctrl+Y undo and redo your own edits; R turns furniture; T retags selected rooms;
Ctrl+S saves, Ctrl+O loads; Esc cancels, then pauses.

Designs are saved as plain JSON (`BuildingModel.to_data()`) in `user://designs/`. Loading one
replaces the building for everyone in the session.

## Tests

`tools/run_tests.sh design`: the tools solo, the room scene, and two then three players over
ENet on localhost (snapshots, cursors, selections, locks and timeouts, per-player undo, a
150-edit burst from all three ending in identical models, load for everyone).
