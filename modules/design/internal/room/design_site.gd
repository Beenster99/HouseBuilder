class_name DesignSite
extends Node3D
## The real-world site's scenery round the design (terrain, neighbours, roads, trees and the
## plot outline) when the sites module has one loaded: Modules.bus("sites").make_plot_view(),
## already placed so the plot sits on the design origin. While a site shows, the sandbox
## ground (`ground`) is hidden; it comes back when the site is cleared.

var ground: Node3D
var view: Node3D


func _init(p_ground: Node3D = null) -> void:
	ground = p_ground
	name = "SiteScenery"


func _ready() -> void:
	var sites := Modules.bus("sites")
	if sites == null or not sites.has_signal("site_changed"):
		return
	sites.connect("site_changed", func(_pack: Variant) -> void: refresh())
	refresh()


## Rebuilds the scenery from the site loaded now.
func refresh() -> void:
	if view:
		view.queue_free()
		view = null
	var sites := Modules.bus("sites")
	var loaded: bool = sites != null and sites.has_method("current") and sites.call("current") != null \
			and sites.has_method("make_plot_view")
	if loaded:
		var v: Variant = sites.call("make_plot_view")
		if v is Node3D:
			view = v
			view.name = "Site"
			add_child(view)
	if ground:
		ground.visible = view == null
