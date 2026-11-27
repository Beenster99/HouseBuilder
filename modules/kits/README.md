# kits module: room modules and the object preview

From the person's 0.0.1 feedback: "design a module: create a room, add components, save as
module with a specific name, selectable from the interface", and "an object preview window:
click an object and a small window shows it rotating, with its dimensions, weight,
power/water requirements".

## Room modules

- Save: in the designer, right-click a room, "Save as module…", give a name and a group. The
  room and everything in it (walls round it, its doors and windows, fittings, columns, beams,
  slabs) becomes a module. Stairs and lifts stay out (they reach other levels).
- Shared: saving is a host-checked request (`kits.save`); every player gets the module at once
  and keeps it on disk (`user://room_modules/`). A player who joins gets the crew's modules and
  adds the ones only they have. Starter modules (bedrooms, bathrooms, kitchen, living room,
  offices, classroom, hospital room, custody cell) are built in and can't be overwritten.
- Use: "Saved modules" in the designer's Add rooms palette (and walk-inside's Tab menu, which
  shows the same groups). Double-click stamps it: the ghost follows the pointer, R turns it,
  click places it as one edit (one undo). Walls that land on an existing wall are not doubled,
  and their doors and windows move onto that wall, so modules sit side by side.

## Object preview

Clicking any row in the designer's palette (objects, room types, modules) pops a small
floating window: the thing turning (drag to turn it yourself, wheel to zoom), and its size,
weight, cost, power, water, waste, gas, what it serves and its materials. The window drags by
its bar, rolls up (▾ or double-click the bar) and closes. Walk-inside shows the same preview
above its TAKE button. Figures: catalog sizes and rates (the cost panel's numbers), the
asset library's mass for loose furniture, and typical UK services demands (`ObjectSpecs.DEMAND`).

## API (Modules.bus("kits") as KitsBus)

```gdscript
kits.save_room(model, room_id, "En-suite", "Bathrooms")   # "" or why not
kits.place_ops(model, "En-suite", level, at, 90.0)         # ops for one sync.edit(C.batch(ops))
kits.make_ghost("En-suite")                                # Node3D, origin at the module's centre
kits.module_list("bath")                                   # [{name, group, room_type, area, parts, author, builtin}]
kits.show_preview("objects", "bath")                       # the floating window
kits.make_preview_for({id, label, tags})                   # an embeddable KitPreview
```

Palette item ids for modules are `kits:<name>`; place_ops and make_ghost take either form.
Classes: `KitCapture` (capture / place_ops / summary, pure), `KitLibrary` (the shared
library), `KitPreview` (the turning picture and figures), `ObjectSpecs` (the figures).
Hooks are found by name (no depends_on on design or walk): DesignBus
`register_palette_group`, `refresh_palette`, `palette_previewed`, `begin_stamp`; WalkBus
`set_preview_maker`.

Flags: `kits`, `kits.modules`, `kits.preview`, `kits.walk_preview`.

Tests: `tools/run_tests.sh kits`.
