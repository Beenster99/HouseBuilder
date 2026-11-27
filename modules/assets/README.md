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
fixture, furniture, school, office, police, hospital, airport, vehicle, plant, landscape,
boundary, street, context (neighbouring buildings), demolition, people.
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

Then `godot --headless --path . --import` and `tools/run_tests.sh assets`. The gallery
(main menu, flag `assets.gallery`) shows everything.
