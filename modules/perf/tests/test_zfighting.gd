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
	"design.house.clean": [2, "design"],
	"design.house.realistic": [9, "design"],
	"design.office.clean": [19, "design"],
	"design.office.realistic": [100, "design"],
	"timelapse.house": [0, "timelapse"],
	"timelapse.office": [0, "timelapse"],
	"demolition.house": [0, "demolition"],
	"demolition.office": [0, "demolition"],
	"sites.addenbrookes-car-park": [2, "sites"],
	"sites.ancoats-infill": [5, "sites"],
	"design.on_site.addenbrookes-car-park": [7, "design (grid on terrain), sites"],
	"design.on_site.ancoats-infill": [9, "design (grid on terrain), sites"],
	"walk.house": [0, "walk"],
	"assets.gallery": [4, "assets"],
	"sandbox.site": [0, "sandbox"],
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
