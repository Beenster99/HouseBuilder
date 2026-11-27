class_name KitLibrary
extends RefCounted
## The crew's shared library of room modules. Saving one is a request the host checks and
## broadcasts, so every player gets it at once; a player joining gets the host's library and
## adds their own saved modules to it. Each player also keeps every module on disk
## (user://room_modules/), so they are there next time, solo or hosting. A few starter
## modules come built in and can't be overwritten or deleted.
##
##   var lib := KitLibrary.new()
##   lib.load_local()
##   lib.bind(net)                         # MultiplayerBus, or a stand-in in tests
##   lib.save(KitCapture.capture(model, "r3", "En-suite", "Bathrooms"))
##   lib.list("bath")                      # [{name, group, room_type, area, parts, author, builtin}]

signal changed

const EVENT_SAVE := "kits.save"
const EVENT_DELETE := "kits.delete"
const SECTION := "kits"
const DIR := "user://room_modules"
const StarterKits := preload("res://modules/kits/internal/starter_kits.gd")

## key (lower-case name) -> kit
var kits: Dictionary = {}
## Write saved modules to DIR (tests switch it off).
var persist := true
var net: Object = null
## The catalog that prices and checks kits.
var catalog: BuildingCatalog = BuildingCatalog.default_catalog()


static func key_of(kit_name: String) -> String:
	return kit_name.strip_edges().to_lower()


## The starter modules and every module saved on this computer.
func load_local(with_starters := true) -> void:
	if with_starters:
		for k: Dictionary in StarterKits.all(catalog):
			k["builtin"] = true
			kits[key_of(str(k.name))] = k
	if persist and DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			if not f.ends_with(".json"):
				continue
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join(f)))
			if parsed is Dictionary and KitCapture.problem(parsed) == "":
				var k: Dictionary = parsed
				k.erase("builtin")
				if not _is_builtin(str(k.name)):
					kits[key_of(str(k.name))] = k
	changed.emit()


func bind(bus: Object) -> void:
	if bus == null:
		return
	net = bus
	net.call("register_event", EVENT_SAVE, _apply_save, _validate_save)
	net.call("register_event", EVENT_DELETE, _apply_delete, _validate_delete)
	net.call("register_snapshot_provider", SECTION, self)


func unbind() -> void:
	if net == null:
		return
	net.call("unregister_event", EVENT_SAVE)
	net.call("unregister_event", EVENT_DELETE)
	net.call("unregister_snapshot_provider", SECTION)
	net = null


## Shares a kit with the crew (or keeps it, solo). Returns "" or why not.
func save(kit: Dictionary) -> String:
	var why := KitCapture.problem(kit)
	if why == "" and _is_builtin(str(kit.name)):
		why = "A starter module is called that: pick another name"
	if why != "":
		return why
	var k := kit.duplicate(true)
	k.erase("builtin")
	if net:
		net.call("request", EVENT_SAVE, {"kit": k})
	else:
		_apply_save({"kit": _stamped(k, "")})
	return ""


## Deletes a saved module for everyone. Returns "" or why not.
func remove(kit_name: String) -> String:
	if not kits.has(key_of(kit_name)):
		return "No module called %s" % kit_name
	if _is_builtin(kit_name):
		return "Starter modules stay"
	if net:
		net.call("request", EVENT_DELETE, {"name": kit_name})
	else:
		_apply_delete({"name": kit_name})
	return ""


func has_kit(kit_name: String) -> bool:
	return kits.has(key_of(kit_name))


func get_kit(kit_name: String) -> Dictionary:
	return kits.get(key_of(kit_name), {})


## Modules whose name, group or room type matches `filter`, optionally in one group, sorted
## by group then name: [{name, group, room_type, room_label, area, parts, author, builtin}].
func list(filter: String = "", group: String = "") -> Array[Dictionary]:
	var f := filter.strip_edges().to_lower()
	var out: Array[Dictionary] = []
	for key: String in kits:
		var k: Dictionary = kits[key]
		var rt := str(k.room.get("type", ""))
		var label := str(catalog.room_type(rt).get("label", rt))
		var g := group_of(k)
		if group != "" and g != group:
			continue
		if f != "" and not (f in str(k.name).to_lower() or f in g.to_lower() or f in label.to_lower() or f in rt):
			continue
		var s := KitCapture.summary(k, catalog)
		out.append({"name": str(k.name), "group": g, "room_type": rt, "room_label": label,
				"area": s.area, "parts": s.parts, "author": str(k.get("author", "")), "builtin": bool(k.get("builtin", false))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.name.to_lower() < b.name.to_lower() if a.group == b.group else a.group < b.group)
	return out


## The module's group: as saved, else its room type's label.
func group_of(kit: Dictionary) -> String:
	var g := str(kit.get("group", "")).strip_edges()
	if g != "":
		return g
	var rt := str(kit.get("room", {}).get("type", ""))
	return str(catalog.room_type(rt).get("label", "Other")) if rt != "" else "Other"


func groups() -> PackedStringArray:
	var out := PackedStringArray()
	for key: String in kits:
		var g := group_of(kits[key])
		if not g in out:
			out.append(g)
	out.sort()
	return out


# --- Host and every peer -------------------------------------------------------------------

func _validate_save(sender: int, payload: Dictionary) -> Variant:
	var kit: Variant = payload.get("kit")
	if not kit is Dictionary:
		return "That module is damaged"
	var why := KitCapture.problem(kit)
	if why != "":
		return why
	if _is_builtin(str(kit.name)):
		return "A starter module is called that: pick another name"
	return {"kit": _stamped((kit as Dictionary).duplicate(true), _player(sender))}


func _apply_save(payload: Dictionary) -> void:
	var kit: Dictionary = payload.get("kit", {})
	if kit.is_empty():
		return
	kits[key_of(str(kit.name))] = kit
	_write(kit)
	changed.emit()


func _validate_delete(_sender: int, payload: Dictionary) -> Variant:
	var n := str(payload.get("name", ""))
	if not kits.has(key_of(n)):
		return "No module called %s" % n
	if _is_builtin(n):
		return "Starter modules stay"
	return {"name": n}


func _apply_delete(payload: Dictionary) -> void:
	var key := key_of(str(payload.get("name", "")))
	if not kits.has(key) or _is_builtin(key):
		return
	kits.erase(key)
	if persist:
		var path := _path(key)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	changed.emit()


func get_net_snapshot() -> Dictionary:
	var out: Array = []
	for key: String in kits:
		if not bool(kits[key].get("builtin", false)):
			out.append(kits[key])
	return {"kits": out}


## A joining player takes the host's modules, then shares the ones only they have.
func apply_net_snapshot(data: Dictionary) -> void:
	var mine: Array = []
	for key: String in kits:
		if not bool(kits[key].get("builtin", false)):
			mine.append(kits[key])
	for key: String in kits.keys():
		if not bool(kits[key].get("builtin", false)):
			kits.erase(key)
	for k: Variant in data.get("kits", []):
		if k is Dictionary and KitCapture.problem(k) == "":
			kits[key_of(str(k.name))] = k
			_write(k)
	changed.emit()
	if net:
		for k: Dictionary in mine:
			if not kits.has(key_of(str(k.name))):
				net.call("request", EVENT_SAVE, {"kit": k})


# --- Helpers -------------------------------------------------------------------------------

func _is_builtin(kit_name: String) -> bool:
	var k: Dictionary = kits.get(key_of(kit_name), {})
	return bool(k.get("builtin", false))


func _stamped(kit: Dictionary, author: String) -> Dictionary:
	if author != "" or not kit.has("author"):
		kit["author"] = author
	kit["saved"] = int(Time.get_unix_time_from_system())
	kit["format"] = KitCapture.FORMAT
	return kit


func _player(peer: int) -> String:
	if net and net.has_method("player_name"):
		return str(net.call("player_name", peer))
	return ""


func _write(kit: Dictionary) -> void:
	if not persist:
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(_path(key_of(str(kit.name))), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(kit, "\t"))


func _path(key: String) -> String:
	var slug := ""
	for ch in key:
		slug += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	return DIR.path_join("%s_%s.json" % [slug.left(40), str(key.hash() & 0xffffff)])
