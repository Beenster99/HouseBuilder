"""What torque_import.py brings in from Torque Shed UE, and the id and label each gets here.

File modes: "dales_stone" (roof slates and dressed stone told apart by slope), "street" (vertex colour, surface in alpha), "named" (plain materials),
"vc:<surface>" (vertex colour is the colour, one surface), "fix:<surface>:<r,g,b>" (one slot).
Entries: rot turns the model about the vertical (degrees), long_y lays its length along y
(the library's vehicles and trains run along y), centre centres it, ground stands it on 0.
"""
import glob
import os
import re

A, B, C3, D4 = ("a", "b", "c"), ("a", "b"), ("a", "b", "c"), ("a", "b", "c", "d")

# RideUK/Props kind -> (id stem, label, variant suffixes or None, variant labels)
RIDE = {
	"power_pylon": ("energy.line.pylon_lattice", "Lattice transmission pylon, 26 m", None, None),
	"power_pole": ("energy.line.pole", "Timber power pole", ("plain", "stay", "transformer"), ("cross arm and insulators", "with stay wire", "with pole transformer")),
	"power_mast": ("energy.telecom.mast_lattice", "Lattice telecom mast", ("plain", "panels"), ("bare", "with antenna panels")),
	"power_monopole": ("energy.telecom.monopole", "Telecom monopole", ("plain", "shrouded"), ("open antennas", "shrouded head")),
	"power_watertower": ("water.tower.concrete", "Water tower", ("bowl", "cone"), ("bowl tank", "cone tank")),
	"power_kiosk": ("energy.substation.kiosk", "Substation kiosk", ("grp", "steel"), ("green GRP", "steel")),
	"power_transformer": ("energy.substation.transformer_ground", "Ground transformer on plinth", None, None),
	"power_gantry": ("energy.substation.gantry", "Substation busbar gantry", None, None),
	"power_palisade": ("energy.substation.palisade_panel", "Substation palisade panel with warning sign", None, None),
	"street_lamp": ("street.light.column", "Street lamp", ("led_steel", "sodium_concrete"), ("steel column, LED lantern", "concrete column, sodium lantern")),
	"lamp_heritage": ("street.light.heritage_lantern", "Heritage lamp post with lantern", None, None),
	"traffic_signal": ("street.traffic.signal_three_aspect", "Traffic signal, three aspect with backing board", None, None),
	"post_box": ("street.furniture.post_box", "Post box", D4, ("pillar", "wall box", "lamp box", "double pillar")),
	"phone_box": ("street.furniture.phone_box", "Phone box", B, ("red kiosk", "modern kiosk")),
	"bus_stop": ("street.furniture.bus_stop_flag", "Bus stop pole and flag", None, None),
	"litter_bin": ("street.furniture.park_bin", "Park litter bin", ("green", "black"), ("green", "black with gold band")),
	"seat": ("street.furniture.seat", "Public seat", B, ("timber slats", "memorial bench")),
	"bollard": ("street.bollard.village", "Village bollard", None, None),
	"milestone": ("street.furniture.milestone", "Milestone", B, ("stone", "cast iron")),
	"village_sign": ("street.furniture.village_sign", "Village sign", B, ("one post", "two posts")),
	"info_board": ("street.furniture.info_board", "Information board", None, None),
	"notice_board": ("street.furniture.notice_board", "Parish notice board", None, None),
	"picnic_table": ("street.furniture.picnic_table", "Picnic table", B, ("timber", "heavy timber")),
	"farm_bales": ("farm.bale.stack", "Bale stack", ("round", "square", "wrapped"), ("round straw pyramid", "big square bales", "wrapped black pyramid")),
	"farm_bale": ("farm.bale.round", "Round bale", ("straw", "black", "green"), ("straw", "wrapped black", "wrapped green")),
	"farm_clamp": ("farm.store.silage_clamp", "Silage clamp, 6 m", ("run", "end"), ("length", "open end")),
	"farm_tank": ("farm.store.slurry_tank", "Slurry store", ("steel", "concrete"), ("steel ring tank", "concrete panel tank")),
	"farm_feedbin": ("farm.store.feed_bin", "Hopper feed bin", ("single", "twin"), ("single", "pair")),
	"farm_trough": ("farm.yard.trough", "Water trough", ("steel", "concrete"), ("galvanised", "concrete")),
	"farm_tractor": ("vehicle.farm.tractor", "Tractor with cab", ("green", "red", "blue_loader"), ("green", "red", "blue with front loader")),
	"farm_trailer": ("vehicle.farm.trailer", "Farm trailer", ("grain", "bale"), ("grain, high sides", "flat bale trailer")),
	"farm_diesel": ("farm.yard.diesel_tank", "Bunded diesel tank with pump", None, None),
	"farm_muck": ("farm.yard.heap", "Yard heap", ("muck", "stones"), ("muck", "field stones and rubble")),
	"field_gate": ("boundary.gate.field_bar", "Field gate", C3, ("galvanised seven bar", "timber five bar", "timber with posts")),
	"kissing_gate": ("boundary.gate.kissing", "Kissing gate", B, ("timber", "galvanised")),
	"stile": ("boundary.gate.stile", "Stile", C3, ("step stile", "ladder stile", "squeeze stile")),
	"lift_gate": ("boundary.gate.lift_barrier", "Lifting barrier", None, None),
	"static_caravan": ("vehicle.towed.static_caravan", "Static caravan", C3, ("cream", "green", "with deck")),
	"touring_caravan": ("vehicle.towed.touring_caravan", "Touring caravan", B, ("single axle", "twin axle")),
	"play_swings": ("sport.play.swings", "Swing frame, two seat", ("flat", "cradle"), ("flat seats", "cradle seats")),
	"play_slide": ("sport.play.slide", "Slide", ("steel", "plastic"), ("steel chute", "plastic chute with hood")),
	"play_climber": ("sport.play.climber", "Climbing frame, two towers", ("steel", "timber"), ("painted steel", "timber")),
	"play_springer": ("sport.play.springer", "Spring rider", ("pony", "scooter", "duck"), ("pony", "scooter", "duck")),
	"play_roundabout": ("sport.play.roundabout", "Playground roundabout", None, None),
	"play_seesaw": ("sport.play.seesaw", "Seesaw", None, None),
	"play_fence": ("sport.play.bowtop_fence", "Bow top railing panel, 2.5 m", ("green", "black"), ("green", "black")),
	"pitch_goal": ("sport.pitch.goal_netted", "Football goal with net, full size", None, None),
	"pitch_posts": ("sport.pitch.rugby_posts_padded", "Rugby posts with pads", None, None),
	"tennis_net": ("sport.court.tennis_net_posts", "Tennis net and posts", None, None),
	"court_fence": ("sport.court.fence_panel", "Court fence panel, 3 m", None, None),
	"basket_hoop": ("sport.court.basket_post", "Basketball post, board and hoop", None, None),
	"armco": ("sport.circuit.armco", "Armco barrier length", None, None),
	"braking_board": ("sport.circuit.braking_board", "Braking distance board", ("m100", "m200", "m300"), ("100", "200", "300")),
	"grandstand": ("sport.circuit.grandstand", "Covered grandstand", None, None),
	"marshal_post": ("sport.circuit.marshal_post", "Marshal post", None, None),
	"pit_wall": ("sport.circuit.pit_wall", "Pit wall with fence", None, None),
	"start_gantry": ("sport.circuit.start_gantry", "Start line gantry with lights", None, None),
	"tyre_wall": ("sport.circuit.tyre_wall", "Tyre wall length", None, None),
}

# Data/Props/Blender name pattern -> (id stem, extra entry fields). First match wins.
SHED = [
	(r"^bus$", "vehicle.bus.half_cab", dict(label="Half cab double decker bus", long_y=True)),
	(r"^car_wreck$", "vehicle.car.wreck", dict(label="Wrecked car", long_y=True)),
	(r"^train_(.+)$", "rail.train.%s", dict(long_y=True)),
	(r"^lx_(lit_.+|msl_lit_.+)$", "", dict()),  # (flat overlays for lit lamps: no thickness)
	(r"^lx_(.+)$", "rail.crossing.%s", dict()),
	(r"^ferry_(.+)$", "water.ferry.%s", dict()),
	(r"^petrol_pump$", "energy.plant.petrol_pump", dict(label="Petrol pump, period")),
	(r"^forecourt_garage$", "context.garage_forecourt", dict(label="Village garage with forecourt")),
	(r"^(fence_mesh|fence_wood|wall_brick|wall_concrete)$", "boundary.yard.%s", dict()),
	(r"^(ramp|landing|yard)_(.+)$", "sport.stunt.%s_%s", dict()),
	(r"^flag_(.+)$", "sport.circuit.flag_%s", dict()),
	(r"^(hay_bales)$", "farm.bale.hay_stack", dict(label="Hay bale stack")),
	(r"^(barrels|cone|crate_.+|box_.+|bin_.+|log|post|tyre_stack|trolley_.+)$", "industrial.yard.%s", dict()),
	(r"^(sticky_note|courier_label|_built|light_switches|ear_defenders|spray_can.*|tabletop|bus_row|pegboard_tools)$", "", dict()),
	(r"^(.+)$", "industrial.workshop.%s", dict()),
]

STONE_WALL, STONE_ROOF = "fix:stone:0.36,0.31,0.24", "dales_stone"
DALES = {"Masonry": STONE_WALL, "Stone": STONE_ROOF, "Render": "vc:render", "Wood": "vc:paint", "Glass": "fix:glass:0.03,0.04,0.06",
	"Paint": "vc:enamel", "Metal": "vc:steel", "": "vc:paint"}


def title(name: str) -> str:
	return name.replace("_", " ").capitalize()


def glb_entries(root: str) -> list:
	out = []
	props = os.path.join(root, "Data", "RideUK", "Props")
	for path in sorted(glob.glob(os.path.join(props, "SM_Prop_*.glb"))):
		m = re.match(r"SM_Prop_(.+)_(\d+)\.glb$", os.path.basename(path))
		if not m or m.group(1) in ("power_turbine", "power_rotor") or m.group(1) not in RIDE:
			continue
		stem, label, suffixes, labels = RIDE[m.group(1)]
		n = int(m.group(2))
		e = {"id": stem if suffixes is None else "%s_%s" % (stem, suffixes[n]), "label": label if suffixes is None else "%s, %s" % (label, labels[n]),
			"files": [(os.path.relpath(path, root), "street")], "rot": -90, "tags": ["outdoor"]}
		if m.group(1) in ("farm_tractor", "farm_trailer", "static_caravan", "touring_caravan"):
			e["long_y"] = True
			e["rot"] = 0
		out.append(e)
	rel = "Data/RideUK/Props/SM_Prop_power_%s_0.glb"
	out.append({"id": "energy.wind.turbine_45m", "label": "Wind turbine, 45 m hub, 40 m rotor", "rot": -90, "tags": ["outdoor"],
		"files": [(rel % "turbine", "street"), (rel % "rotor", "street")], "rotor": True})
	for path in sorted(glob.glob(os.path.join(root, "Data", "RideUK", "Animals", "SM_Animal_*.glb"))):
		m = re.match(r"SM_Animal_(.+)\.glb$", os.path.basename(path))
		if m and "LOD" not in m.group(1):
			out.append({"id": "animal.farm." + m.group(1), "label": "Farm animal: " + m.group(1).replace("_", " "), "rot": -90, "tags": ["outdoor"],
				"files": [(os.path.relpath(path, root), "vc:fabric")]})
	shed = os.path.join(root, "Data", "Props", "Blender")
	for path in sorted(glob.glob(os.path.join(shed, "*.glb"))):
		name = os.path.basename(path)[:-4]
		for pattern, stem, extra in SHED:
			m = re.match(pattern, name)
			if m:
				break
		if not stem:
			continue
		e = {"id": stem % m.groups() if "%" in stem else stem, "label": title(name), "files": [(os.path.relpath(path, root), "named")], "tags": []}
		e.update(extra)
		out.append(e)
	out += dales(root)
	return out


def dales(root: str) -> list:
	"""The Dales models: every other prop, and a spread of the stone houses and barns."""
	folder = os.path.join(root, "Data", "Buttertubs", "Props")
	groups: dict = {}
	for path in sorted(glob.glob(os.path.join(folder, "SM_*.glb"))):
		name = os.path.basename(path)[3:-4]
		m = re.match(r"(.+)_(Masonry|Stone|Render|Wood|Glass|Paint|Metal)$", name)
		key, mat = (m.group(1), m.group(2)) if m else (name, "")
		groups.setdefault(key, []).append((os.path.relpath(path, root), mat))
	out = []
	houses = sorted([k for k in groups if k.startswith("Bld_") and any(m == "Glass" for _p, m in groups[k])],
		key=lambda k: sum(os.path.getsize(os.path.join(root, p)) for p, _m in groups[k]))
	barns = sorted([k for k in groups if k.startswith("Bld_") and not any(m == "Glass" for _p, m in groups[k])],
		key=lambda k: sum(os.path.getsize(os.path.join(root, p)) for p, _m in groups[k]))
	for kind, keys, count in (("house", houses, 30), ("barn", barns, 12)):
		step = max(1, len(keys) / float(count))
		picked = [keys[min(len(keys) - 1, int(i * step))] for i in range(min(count, len(keys)))]
		for i, key in enumerate(dict.fromkeys(picked)):
			out.append({"id": "context.dales.%s_%02d" % (kind, i + 1), "label": "Dales stone %s %d" % (kind, i + 1), "tags": ["outdoor", "context"],
				"files": [(p, DALES[m]) for p, m in groups[key]], "rot": -90, "size_label": True})
	named = {
		"Car_": ("vehicle.car.dales_%s", "Parked car, simple", "vc"), "Farm4x4_": ("vehicle.car.farm_4x4_%s", "Farm 4x4 pickup", "vc"),
		"QuadBike": ("vehicle.bike.quad", "Quad bike", "vc"), "Sheep_": ("animal.farm.sheep_%s", "Swaledale sheep", "vc"),
		"Corvid_": ("animal.bird.crow_%s", "Crow", "vc"), "Wall_": ("boundary.dry_stone.wall_%s", "Dry stone wall length", "stone"),
		"WallEnd_": ("boundary.dry_stone.end_%s", "Dry stone wall end", "stone"), "GateStoop_": ("boundary.dry_stone.stoop_%s", "Stone gate stoop", "stone"),
		"Gate": ("boundary.gate.dales_field", "Dales field gate, galvanised", "vc"), "Rock_": ("landscape.rock.gritstone_%s", "Gritstone rock", "stone"),
		"Scar_": ("landscape.rock.scar_%s", "Limestone scar", "stone"), "Scree_": ("landscape.rock.scree_%s", "Scree patch", "stone"),
		"FingerPost_": ("street.furniture.finger_post_%s", "Finger post", "vc"), "SignJunction": ("street.traffic.sign_junction", "Junction sign", "vc"),
		"LogPile_": ("landscape.yard.log_pile_%s", "Log pile", "vc"), "WashingLine_": ("street.garden.washing_line_%s", "Washing line", "vc"),
		"ChurnStand": ("farm.yard.churn_stand", "Milk churn stand", "vc"), "Bench": ("street.furniture.dales_bench", "Bench, iron ends", "vc"),
		"Bales_": ("farm.bale.dales_%s", "Bale stack, wrapped", "vc"), "PicnicTable": ("street.furniture.dales_picnic_table", "Picnic table", "vc"),
	}
	for key in groups:
		for prefix, (stem, label, mode) in named.items():
			tail = key[len(prefix):]
			if key.startswith(prefix) and (tail == "" or (prefix.endswith("_") and re.match(r"^[0-9A-Za-z]+$", tail))):
				files = [(p, STONE_WALL if mode == "stone" else DALES[m]) for p, m in groups[key]]
				e = {"id": (stem % tail.lower()) if "%" in stem else stem, "label": label + ((" " + tail) if "%" in stem else ""), "files": files, "tags": ["outdoor"]}
				if stem.startswith("vehicle."):
					e["long_y"] = True
				out.append(e)
				break
	return out


def unit_entries(root: str, wanted) -> list:
	"""[(entry, unit)] script by script; each script's units are all made before the next's."""
	import blender_warehouse_kit as K
	import blender_estate_props as E
	import blender_farm_kit as F
	import blender_village_kit as V

	def batch(pairs):
		for entry, make in pairs:
			if wanted(entry["id"]):
				yield entry, make()

	K.clear()
	yield list(batch([({"id": "context.industrial." + name[3:].lower(), "label": label, "centre": True, "tags": ["outdoor", "context"],
		"source": ["Tools/blender_warehouse_kit.py " + name]}, (lambda n=name, l=label, s=spec: K.unit(n, l, s))) for name, label, spec in K.DESIGNS]))
	K.clear()
	estate = {"trailer": ("vehicle.lorry.%s", True), "van": ("vehicle.van.estate_%s", True), "palisade": ("boundary.palisade.estate_%s", False),
		"gate": ("boundary.gate.estate_sliding_%s", False), "estate_board": ("street.traffic.estate_board", False),
		"trolley_shelter": ("retail.yard.trolley_shelter", False), "yard_lamp": ("street.light.yard_column", False)}
	pairs = []
	for name, label, make in E.PROPS:
		head = name if name in estate else name.split("_")[0]
		stem, long_y = estate.get(head, ("industrial.yard.%s", False))
		tail = name if head == "trailer" else name[len(head) + 1:]
		id = (stem % (tail if head in estate else name)) if "%" in stem else stem
		pairs.append(({"id": id, "label": label, "long_y": long_y, "tags": ["outdoor"], "source": ["Tools/blender_estate_props.py " + name]}, make))
	yield list(batch(pairs))
	K.clear()
	yield list(batch([({"id": "context.farm." + d[0][3:].lower(), "label": d[1], "centre": True, "tags": ["outdoor", "context"],
		"source": ["Tools/blender_farm_kit.py " + d[0]]}, (lambda d=d: F.unit(d[0], d[1], d[2]))) for d in F.DESIGNS]))
	K.clear()
	saved = (F.wall_surface, F.wall_rgb, F.thick, F.plinth, F.bay)
	V.patch()
	yield list(batch([({"id": "context.school." + d[0][3:].lower(), "label": d[1], "centre": True, "tags": ["outdoor", "context"],
		"source": ["Tools/blender_village_kit.py " + d[0]]}, (lambda d=d: F.unit(d[0], d[1], d[2]))) for d in V.DESIGNS]))
	F.wall_surface, F.wall_rgb, F.thick, F.plinth, F.bay = saved
	K.clear()
	import blender_church_assemble as CH
	yield list(batch([({"id": "context.church." + spec["name"][10:].lower(), "label": spec["label"], "centre": True, "tags": ["outdoor", "context"],
		"source": ["Tools/blender_church_assemble.py " + spec["name"]]}, (lambda spec=spec: CH.build_one(spec))) for spec in CH.SPECS]))
