extends ModuleTest
## Z-fighting: every game scene with a building in it, in both looks (clean model and
## realistic), scanned with ZFightScan for surfaces that share a plane, face the same way
## and overlap (they flicker as the camera moves).
##
## A ratchet like test_budgets.gd: KNOWN holds each scene's count of fighting pairs today,
## with its owner. A scene that gains a fight fails; when an owner cleans some out, lower
## the number (0 removes the entry), so they can't come back. Each run prints the worst
## pairs with where they are, for whoever is fixing them:
##   tools/run_tests.sh perf

const SHOW := 8
## Real sites scanned (the first in SitePool.ids()).
const SITES := 2
## scene -> [fighting pairs when listed, owner]. 2026-11-27.
const KNOWN := {
	"design.house.clean": [0, "design"],
	"design.house.realistic": [0, "design"],
	"design.office.clean": [0, "design"],
	"design.office.realistic": [0, "design"],
	"timelapse.house": [0, "timelapse"],
	"timelapse.office": [0, "timelapse"],
	"demolition.house": [0, "demolition"],
	"demolition.office": [0, "demolition"],
	"sites.addenbrookes-car-park": [0, "sites"],
	"sites.ancoats-infill": [0, "sites"],
	"design.on_site.addenbrookes-car-park": [0, "design"],
	"design.on_site.ancoats-infill": [0, "design"],
	"walk.house": [0, "walk"],
	"assets.gallery": [0, "assets"],
	"sandbox.site": [0, "sandbox"],
}

## Library models scanned one by one: every ASSET_STEP-th id (all of them with PERF_FULL=1,
## about 10 minutes), in the realistic look where each material is its own.
const ASSET_STEP := 25
## Models allowed a fight (owner, or why) (a fight within one surface and material can't flicker).
const KNOWN_ASSETS := {
	"context.church.wal_saddle": "assets: a 10 cm² sliver of dark glass over itself, same surface and material",
	# Found in the realistic look 2026-11-27 (the clean look draws them in one white): remove each when fixed.
	"context.church.sco_free": "assets",
	"context.dales.house_10": "assets",
	"context.farm.dales_barn": "assets",
	"context.industrial.supermarket": "assets",
	"fixture.locker": "assets",
	"industrial.workshop.repair_pro": "assets",
	"industrial.yard.cone": "assets",
	"people.staff.teacher": "assets",
	"plant.cabin.toilet_green": "assets",
	"plant.excavator.midi": "assets",
	"services.plant.pump_set": "assets",
	"street.furniture.info_board": "assets",
	"street.traffic.signal_three_aspect": "assets",
	"vehicle.car.dales_1": "assets",
	"vehicle.car.wreck": "assets",
}

var building: BuildingBus
var lines: Array[String] = []


func run_tests() -> void:
	building = Modules.bus("building") as BuildingBus
	# The live structure and services checks would still be running on these buildings when
	# the test quits (see test_budgets.gd); they draw nothing, so they're paused.
	for id in ["structure", "services"]:
		var bus := Modules.bus(id)
		if bus and bus.has_method("watch"):
			bus.call("watch", null)
	var look_was: Variant = GraphicsOptions.get_value("art_style")
	for size in ["house", "office"]:
		building.model.load_data(ScaleBuildings.data(size))
		for look in ["clean", "realistic"]:
			_set_look(look)
			var room := _open(DesignBus.ROOM_SCENE)
			await get_tree().create_timer(1.0).timeout
			_judge("design.%s.%s" % [size, look], room)
			room.queue_free()
			await frames(2)
		_set_look("clean")
		await _timelapse(size)
		await _demolition(size)
	await _sites()
	await _walk()
	await _assets()
	var gallery := _open(AssetsBus.GALLERY_SCENE)
	await frames(5)
	_judge("assets.gallery", gallery)
	gallery.queue_free()
	await frames(2)
	var site := _open(SandboxBus.SITE_SCENE)
	await frames(5)
	_judge("sandbox.site", site)
	site.queue_free()
	await frames(2)
	GraphicsOptions.set_value("art_style", look_was)
	building.reset_data()
	print("\n".join(lines))


## Real sites: terrain, roads, neighbours, trees and the plot, alone and with the house on
## them in the design room.
func _sites() -> void:
	var sites := Modules.bus("sites") as SitesBus
	building.model.load_data(ScaleBuildings.data("house"))
	for id in SitePool.ids().slice(0, SITES):
		sites.load_site(id)
		await frames(3)
		var view := sites.make_view()
		if view == null:
			continue
		add_child(view)
		await frames(2)
		_judge("sites.%s" % id, view, {"ground_y": -INF})
		view.queue_free()
		var room := _open(DesignBus.ROOM_SCENE)
		await get_tree().create_timer(1.0).timeout
		_judge("design.on_site.%s" % id, room, {"ground_y": -INF})
		room.queue_free()
		await frames(2)
	sites.clear_site()
	await frames(2)


func _assets() -> void:
	_set_look("realistic")
	var all := AssetLibrary.ids()
	var step := 1 if OS.get_environment("PERF_FULL") == "1" else ASSET_STEP
	var scanned := 0
	var bad: Array[String] = []
	for i in range(0, all.size(), step):
		var id := all[i]
		var node := AssetLibrary.make(id)
		add_child(node)
		var fights := ZFightScan.scan(node)
		scanned += 1
		if fights.is_empty() and KNOWN_ASSETS.has(id) and str(KNOWN_ASSETS[id]) == "assets":
			lines.append("      %s is clean now: take it out of KNOWN_ASSETS" % id)
		if not fights.is_empty() and not KNOWN_ASSETS.has(id):
			bad.append("%s: %d pairs, worst %s" % [id, fights.size(), ZFightScan.describe(fights[0])])
		node.free()
	_set_look("clean")
	lines.append("  %-26s %4d of %d models scanned one by one, %d with new z-fighting, %d listed%s" % ["assets.models", scanned, all.size(),
			bad.size(), KNOWN_ASSETS.size(), "" if step == 1 else " (PERF_FULL=1 scans them all)"])
	for b in bad:
		lines.append("      " + b)
	check(bad.is_empty(), "library models with z-fighting (assets): %s" % ", ".join(bad))
	await frames(1)


## Walking round inside the house.
func _walk() -> void:
	var walk := Modules.bus("walk")
	if walk == null or not walk.has_method("open"):
		return
	building.model.load_data(ScaleBuildings.data("house"))
	var holder := Node3D.new()
	add_child(holder)
	var view: Node = walk.call("open", building.model, holder)
	if view == null:
		holder.queue_free()
		return
	await frames(5)
	_judge("walk.house", view)
	walk.call("close")
	holder.queue_free()
	await frames(2)


func _timelapse(size: String) -> void:
	var tl := Modules.bus("timelapse") as TimelapseBus
	tl.start_from_model(building.model, "", false)
	await frames(2)
	var view := _open(TimelapseBus.VIEW_SCENE)
	await frames(3)
	tl.request_seek(tl.total_days())
	await get_tree().create_timer(0.5).timeout
	_judge("timelapse.%s" % size, view)
	view.queue_free()
	await frames(2)


func _demolition(size: String) -> void:
	var demo := Modules.bus("demolition") as DemolitionBus
	demo.start_from_model(building.model, {"open": false})
	await frames(2)
	var view := _open(DemolitionBus.VIEW_SCENE)
	await frames(5)
	_judge("demolition.%s" % size, view)
	view.queue_free()
	demo.request_reset()
	await frames(2)


func _judge(scene: String, root: Node, options: Dictionary = {}) -> void:
	# The design room's minimap draws the same building again in its own world: its fights
	# are the room's, so they're counted once.
	var o := {"skip": ["MiniWorld"]}
	o.merge(options, true)
	var fights := ZFightScan.scan(root, o)
	var known: int = int(KNOWN.get(scene, [0])[0])
	var owner: String = str(KNOWN.get(scene, [0, "?"])[1])
	lines.append("  %-26s %4d fighting pairs (listed %d, %s)" % [scene, fights.size(), known, owner])
	for i in mini(SHOW, fights.size()):
		lines.append("      " + ZFightScan.describe(fights[i]))
	check(fights.size() <= known, "%s has %d z-fighting pairs, listed at %d: new z-fighting (%s)" % [scene, fights.size(), known,
			ZFightScan.describe(fights[0]) if not fights.is_empty() else ""])
	if fights.size() < known:
		lines.append("      fewer than listed: lower KNOWN[\"%s\"] to %d" % [scene, fights.size()])


func _open(id: String) -> Node:
	var n: Node = (load(Router.scene_path(id)) as PackedScene).instantiate()
	add_child(n)
	return n


## The look for scenes opened from now on. (Not Graphics.apply_all(): rooms freed earlier
## still listen to Graphics.changed and would error.)
func _set_look(look: String) -> void:
	GraphicsOptions.set_value("art_style", ArtStyle.REALISTIC if look == "realistic" else ArtStyle.MODEL)
