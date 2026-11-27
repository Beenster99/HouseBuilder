# assets module

The 3D asset library. Every model is built in Blender from a scripted recipe and exported as
glTF; the game asks for one by id and gets a ready node in the current look (sketch or
realistic). Design: https://claude.ai/artifact/67J26qgDYxtfKYt8nbfQQz

## Using it (other modules)

Add `assets` to your `module.tres` `depends_on`, then:

```gdscript
var bed := AssetLibrary.make_kind("bed_double")                 # by building catalog kind
var door := AssetLibrary.make("opening.door.fire")              # by asset id
var beam := AssetLibrary.make("structure.section.ub_305x165x40", {"length": 6.0})
var box := AssetLibrary.make_kind("not_modelled_yet", {"size": Vector3(1, 2, 1)})  # plain box
AssetLibrary.apply_look(root)                                   # on Graphics.changed
AssetLibrary.show_stages(node, ["frame"])                       # timelapse: stage by stage
```

Axes: x right, y up, -z forward, metres. Fixtures: origin at floor centre, back to +z.
Openings: origin at the bottom centre of the hole, in the wall's plane (x along the wall).
Sections: 1 m long along z and centred; `length` stretches them. Piles: 1 m, top at the
origin, stretch down y. Stairs: foot at the origin, climbing toward -z, 3 m rise (scale to
suit). `AssetLibrary.info(id)` gives the manifest entry: aabb, stages, pieces with mass,
sockets, tags.

Stretch assets are 1 m models scaled by `make()`; `info(id).stretch` says how:
`z`, `x` or `y` take `length` (sections, pipes, ducts, fences and kerbs along x, piles);
`zy` takes `length` and `height` (walls, cladding); `xz` takes `width` and `length`
(floors, roof coverings, lawn).

Categories (the first part of the id): structure, opening, roof, circulation, services,
fixture, furniture, school, office, police, hospital, airport, sport, retail, hospitality,
industrial, vehicle, plant, landscape, boundary, street, context (neighbouring buildings),
road, rail, bridge, earthworks, energy, water, demolition, people, home (room contents and
garden), farm, animal.
`AssetLibrary.ids("hospital")` lists by tag: categories, building types (home, school,
office, police, hospital, airport) and uses (wall, ceiling, outdoor, temporary, debris).

## Adding or changing assets

Blender side, in `tools/assets/` (Python, needs `pip install bpy`):

- `kit.py`: the kit pieces (box, tube, I-section, prism, lathe, frame, lattice...).
- `materials.py`: the PBR material slots.
- `recipes/<category>.py`: one function per asset or family, registered with an id
  `category.name.variant` and, where it draws one, the building catalog kind.
- `python3 tools/assets/build.py [id prefix ...]` rebuilds the .glb files and
  `internal/manifest.json`. `--blend` also saves a .blend to open in Blender.
- `python3 tools/assets/render.py out [id prefix ...]` renders a contact sheet in both looks.

Models from Torque Shed UE (the owner's other game; tag `torque_shed`, about 490: lorry
trailers, vans, tractors, buses, trains, pylons, poles, the wind turbine, industrial units,
farm and school buildings, churches, Dales stone houses, street, farm and playground props,
animals):
`python3 tools/assets/torque_import.py /path/to/torque-shed-ue` reads its .glb files and runs
its Blender kit scripts, and writes one neutral .glb per asset to
`tools/assets/vendor/torque_shed/` with `index.json`; `torque_catalog.py` lists what comes
in and under which id. `recipes/torque.py` builds them like any other asset (no Torque Shed
checkout needed) and makes the powerline spans and runs and the wind farms from them. Their
colours get slots named `<surface>_<colour>` (for example `paint_c22`), with PBR values in
the index; dark opaque window glass is `glass_dark`. Lit parts of lights are in the slot
`glow` (statement lights) or `light_emitter`.

Realistic look, flag `assets.textures`: `AssetLibrary.apply_look()` gives each mesh a
textured material for its slot from `AssetMaterials` (internal). `build.py` writes the slots'
colour, roughness, metal and surface pattern to `internal/materials.json`;
`python3 tools/assets/textures.py` makes the 22 seamless detail and normal maps in
`internal/textures/` (brick, block, stone, slate, tile, timber, concrete, cladding, fabric...)
and holds the table that says which slot gets which pattern. They are mapped triplanar in the
model's own space at true size, so no model needs UVs and stretched pieces are not smeared.
Colours in `materials.py` are written as they should look on screen. With the flag off the
models show their own flat PBR colours.

Then `godot --headless --path . --import` and `tools/run_tests.sh assets`. The gallery
(main menu, flag `assets.gallery`) shows everything.
