# walk module

Walk-inside mode, ported from BSX Ltd's design room (`modules/design/internal/walk/`:
walk_inside.gd, walk_build.gd) and repurposed for the BuildingModel. The open building is
built round you at full size in a world of its own (a SubViewport with its own World3D,
sky, sun and physics) and drawn over the whole screen. Walk it, fly round it and design in
it; every change goes through BuildingSync, so the designer, the holotable and every other
player follow.

## Opening it

The designer's top bar gets a **Walk inside** button (`DesignBus.register_action`, found by
name; walk does not depend on design). Or from code:

```
var walk := Modules.bus("walk") as WalkBus
walk.open(model, get_tree().current_scene)     # spawn: {at, yaw}; sync: defaults to the building bus's
walk.closed.connect(...)                        # Esc closes it
```

While open it holds `HudSlots.claim_pointer("walk.inside")`. When opened from a node inside a
SubViewport (the designer drawn in the hall; the button finds the viewport it was pressed in),
a stand-in camera is made current in that viewport, so the designer steps aside (HUD and
input) and takes over again when the walk closes and frees it. Esc only closes the walk.

## Controls (BSX's)

WASD walk, Shift run, Space jump, mouse look, Esc back. Q fly (Space up, C down, through
walls). V swaps the architectural model look and the realistic one (the Graphics "Look"
option). Tab: fittings, doors and windows, columns; undo and redo. Aim at a part: click picks
it up and click puts it down (green where it fits, amber where it hits something), R turns,
E edits (kind, material, section), X removes. Aim at a wall: F puts a door in it, the mouse
wheel pushes it away or pulls it towards you a grid step (the walls meeting it stretch, rooms
and floors on it follow; one undo per run of steps). Aim at a ceiling: the wheel raises or
lowers it (the storey height). Ctrl+Z / Ctrl+Y.

## Tab menu

OBJECTS and ROOMS tabs, a filter box (every word must match a label, id, tag or group), and
folding groups. The groups come from `DesignBus.palette_groups(kind)` when the design module
has it (so the designer and walk-inside show the same ones; `palette_changed` refills),
else walk's own copy (`internal/walk_palette.gd`). An object goes in your hands; a room type
makes the room you stand in that type. Hooks for other modules on WalkBus:
`register_tab_section(id, title, make(view) -> Control, order)`,
`set_preview_maker(make(item) -> Control)` (a click then previews, TAKE takes),
`register_taker(id, take(view, item) -> bool)` for items that aren't catalog kinds (a saved
module).

## Co-op

`WalkBus.walkers`: peer id -> {name, colour, pos (feet, world m), yaw, aim (Vector3 or null),
flying}; `walkers_changed` when someone starts or stops. Who is walking is a host event
(`walk.state`, snapshot section `walk`); bodies and pointers stream as movers
`player:<id>:walk` and `player:<id>:walkaim`. In the walk each other player is a figure in
their colour with their name, and their pointer is a dot with a faint line from their eyes.
A part you hold is claimed, so the host refuses anyone else's edit to it until you put it down.

## Files

- `api/walk_bus.gd` (WalkBus): open/close, walkers, the designer button.
- `internal/walk_inside.gd`: the view, walker, HUD, palette and edits (BSX WalkInside).
- `internal/walk_build.gd`: the building at full size with collision, doors that swing open,
  stair ramps, room lamps; batched like the designer's view (BSX WalkBuild).
- `internal/walk_edits.gd`: the edits as BuildingModel ops (pure, tested headless).

Flags: `walk`, `walk.inside`. Tests: `tools/run_tests.sh walk` (solo, and two players over
ENet). Opening the 4,000-part terminal takes about 2 s headless; edits redo only what they touch.
