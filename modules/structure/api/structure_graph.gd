class_name StructureGraph
extends RefCounted
## The building as the solver sees it: connections are nodes, structural members are edges
## between two nodes, and foundations are anchor nodes with a bearing capacity. Plain data
## with no scene dependencies, so it runs headless and is cheap to send or save.
##
##   var g := StructureGraph.new()
##   g.add_anchor("f1", Vector3(0, 0, 0), StructureSections.foundation_capacity("pad", 1.0))
##   g.add_node("n1", Vector3(0, 3, 0))
##   g.add_member("c1", "f1", "n1", StructureGraph.COLUMN, "steel.uc_203x203x46")
##   g.add_member_load("b1", "live", 4.5)       # kN per metre along the member
##   g.add_area_load("s1", "dead", 1.0)         # kPa over the member's width
##
## Units: metres, kN, Y up. Ids are any strings; the solver sorts them, so the result never
## depends on the order things were added.

const COLUMN := "column"
const BEAM := "beam"
const BRACE := "brace"
const WALL := "wall"
const SLAB := "slab"
const RAFTER := "rafter"
const KINDS: PackedStringArray = [COLUMN, BEAM, BRACE, WALL, SLAB, RAFTER]

## Bumped on every change; the report records the revision it was made from.
var revision := 0
## id -> {"pos": Vector3, "anchor": bool, "bearing": float (kN, 0 = unlimited),
##        "loads": {case: kN}, "wind_area": m²}
var nodes: Dictionary = {}
## id -> {"a": node id, "b": node id, "kind": String, "section": String,
##        "width": m (walls and slabs: their width; else 1), "plane": Vector3 (walls: a
##        horizontal direction along the wall), "loads": {case: kN/m}, "label": String,
##        "part": the building part it models (several members may share one),
##        "chain": beams split into pieces along one straight line share a chain id, so
##        they bend as one beam span by span (default: the member's own id)}
var members: Dictionary = {}
## Sections made for this graph (StructureSections shape), looked up before the built-in
## table: id -> {"material", "axial", "bending", "shear", "weight", "per_width"?}.
var sections: Dictionary = {}
## Floor and roof plates, checked as one-metre strips over their span. Their loads reach
## the structure through the members that hold them up (add those as member loads), so a
## plate only checks itself. id -> {"section", "span": m, "cantilever": bool,
## "supports": Array of member ids, "loads": {case: kPa}, "label", "part"}
var plates: Dictionary = {}


func add_node(id: String, pos: Vector3) -> void:
	nodes[id] = {"pos": pos, "anchor": false, "bearing": 0.0, "loads": {}, "wind_area": 0.0}
	revision += 1


## A foundation. bearing_kn 0 means the ground never gives way. part: the foundation part
## it stands for, if any.
func add_anchor(id: String, pos: Vector3, bearing_kn: float = 0.0, part: String = "") -> void:
	add_node(id, pos)
	make_anchor(id, bearing_kn, part)


## Turns an existing node into a foundation.
func make_anchor(id: String, bearing_kn: float = 0.0, part: String = "") -> void:
	nodes[id].anchor = true
	nodes[id].bearing = maxf(bearing_kn, 0.0)
	if part != "":
		nodes[id].part = part
	revision += 1


## Adds a member between two existing nodes. Returns "" or why it was refused.
func add_member(id: String, a: String, b: String, kind: String, section: String,
		width: float = 1.0, plane: Vector3 = Vector3.ZERO, label: String = "", part: String = "",
		chain: String = "") -> String:
	if not nodes.has(a) or not nodes.has(b):
		return "member %s needs nodes %s and %s" % [id, a, b]
	if a == b:
		return "member %s joins %s to itself" % [id, a]
	if kind not in KINDS:
		return "member %s has unknown kind %s" % [id, kind]
	if not has_section(section):
		return "member %s has unknown section %s" % [id, section]
	if (nodes[a].pos as Vector3).distance_to(nodes[b].pos) < 0.001:
		return "member %s has no length" % id
	var p := Vector3(plane.x, 0.0, plane.z)
	members[id] = {"a": a, "b": b, "kind": kind, "section": section, "width": maxf(width, 0.01),
			"plane": p.normalized() if p.length() > 0.0 else Vector3.ZERO, "loads": {},
			"label": label, "part": part if part != "" else id, "chain": chain if chain != "" else id}
	revision += 1
	return ""


## A section only this graph uses (for sizes worked out from a catalog's properties).
func add_section(id: String, props: Dictionary) -> void:
	sections[id] = props.duplicate()
	revision += 1


func has_section(id: String) -> bool:
	return sections.has(id) or StructureSections.has(id)


## A section's numbers: this graph's own first, then StructureSections; {} if unknown.
func section(id: String) -> Dictionary:
	return sections.get(id, StructureSections.get_section(id))


## A floor or roof plate spanning span metres between its supports (or out from one, as a
## cantilever). Returns "" or why it was refused.
func add_plate(id: String, section_id: String, span: float, cantilever: bool,
		supports: PackedStringArray, label: String = "", part: String = "") -> String:
	if not has_section(section_id):
		return "plate %s has unknown section %s" % [id, section_id]
	var sup: Array = Array(supports)
	sup.sort()
	plates[id] = {"section": section_id, "span": maxf(span, 0.0), "cantilever": cantilever,
			"supports": sup, "loads": {}, "label": label, "part": part if part != "" else id}
	revision += 1
	return ""


## A pressure on a plate (kPa, unfactored).
func add_plate_load(plate_id: String, case: String, kpa: float) -> void:
	var loads: Dictionary = plates[plate_id].loads
	loads[case] = float(loads.get(case, 0.0)) + kpa
	revision += 1


## A point load at a node, kN downward (unfactored; case is one of StructureLoads.CASES).
func add_node_load(node_id: String, case: String, kn: float) -> void:
	var loads: Dictionary = nodes[node_id].loads
	loads[case] = float(loads.get(case, 0.0)) + kn
	revision += 1


## A load spread along a member, kN per metre of its length, downward.
func add_member_load(member_id: String, case: String, kn_per_m: float) -> void:
	var loads: Dictionary = members[member_id].loads
	loads[case] = float(loads.get(case, 0.0)) + kn_per_m
	revision += 1


## A pressure on the strip a member carries: kPa times the member's width (its tributary
## width for a beam, its own width for a slab).
func add_area_load(member_id: String, case: String, kpa: float) -> void:
	add_member_load(member_id, case, kpa * float(members[member_id].width))


## Facade area (m²) whose wind pressure arrives at this node.
func set_wind_area(node_id: String, m2: float) -> void:
	nodes[node_id].wind_area = maxf(m2, 0.0)
	revision += 1


## Rough wind areas when the source has no facade data: each upright member (column or
## wall) catches wind over its height times bay_width (its own width for walls), shared
## between its two ends; the ground end's share goes straight into the ground.
func auto_wind_areas(bay_width: float = 3.0) -> void:
	for id: String in nodes:
		nodes[id].wind_area = 0.0
	for id: String in members:
		var m: Dictionary = members[id]
		if m.kind != COLUMN and m.kind != WALL:
			continue
		var h := absf((nodes[m.a].pos as Vector3).y - (nodes[m.b].pos as Vector3).y)
		var w: float = m.width if m.kind == WALL else bay_width
		for n: String in [m.a, m.b]:
			if not nodes[n].anchor:
				nodes[n].wind_area += h * w * 0.5
	revision += 1


func has_node(id: String) -> bool:
	return nodes.has(id)


func has_member(id: String) -> bool:
	return members.has(id)


func anchor_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in nodes:
		if nodes[id].anchor:
			out.append(id)
	out.sort()
	return out


func member_length(id: String) -> float:
	var m: Dictionary = members[id]
	return (nodes[m.a].pos as Vector3).distance_to(nodes[m.b].pos)


## Plain data (arrays, numbers, strings) for the wire, saves and hashing.
func to_dict() -> Dictionary:
	var n_out := {}
	var ids := nodes.keys()
	ids.sort()
	for id: String in ids:
		var n: Dictionary = nodes[id]
		var p: Vector3 = n.pos
		n_out[id] = {"pos": [p.x, p.y, p.z], "anchor": n.anchor, "bearing": n.bearing,
				"loads": _sorted(n.loads), "wind_area": n.wind_area, "part": str(n.get("part", ""))}
	var m_out := {}
	ids = members.keys()
	ids.sort()
	for id: String in ids:
		var m: Dictionary = members[id]
		var pl: Vector3 = m.plane
		m_out[id] = {"a": m.a, "b": m.b, "kind": m.kind, "section": m.section, "width": m.width,
				"plane": [pl.x, pl.y, pl.z], "loads": _sorted(m.loads), "label": m.label, "part": m.part, "chain": m.chain}
	var s_out := {}
	ids = sections.keys()
	ids.sort()
	for id: String in ids:
		s_out[id] = sections[id].duplicate()
	var p_out := {}
	ids = plates.keys()
	ids.sort()
	for id: String in ids:
		var pl: Dictionary = plates[id]
		p_out[id] = {"section": pl.section, "span": pl.span, "cantilever": pl.cantilever,
				"supports": pl.supports.duplicate(), "loads": _sorted(pl.loads), "label": pl.label,
				"part": pl.part}
	return {"revision": revision, "nodes": n_out, "members": m_out, "sections": s_out, "plates": p_out}


static func from_dict(data: Dictionary) -> StructureGraph:
	var g := StructureGraph.new()
	var n_in: Dictionary = data.get("nodes", {})
	for id: String in n_in:
		var n: Dictionary = n_in[id]
		var p: Array = n.get("pos", [0, 0, 0])
		g.add_node(id, Vector3(p[0], p[1], p[2]))
		g.nodes[id].anchor = bool(n.get("anchor", false))
		g.nodes[id].bearing = float(n.get("bearing", 0.0))
		g.nodes[id].loads = (n.get("loads", {}) as Dictionary).duplicate()
		g.nodes[id].wind_area = float(n.get("wind_area", 0.0))
		if str(n.get("part", "")) != "":
			g.nodes[id].part = str(n.part)
	var s_in: Dictionary = data.get("sections", {})
	for id: String in s_in:
		g.add_section(id, s_in[id])
	var m_in: Dictionary = data.get("members", {})
	for id: String in m_in:
		var m: Dictionary = m_in[id]
		var pl: Array = m.get("plane", [0, 0, 0])
		var why := g.add_member(id, str(m.get("a", "")), str(m.get("b", "")), str(m.get("kind", "")),
				str(m.get("section", "")), float(m.get("width", 1.0)), Vector3(pl[0], pl[1], pl[2]),
				str(m.get("label", "")), str(m.get("part", "")), str(m.get("chain", "")))
		if why == "":
			g.members[id].loads = (m.get("loads", {}) as Dictionary).duplicate()
		else:
			push_warning("StructureGraph.from_dict: " + why)
	var p_in: Dictionary = data.get("plates", {})
	for id: String in p_in:
		var pl: Dictionary = p_in[id]
		var why := g.add_plate(id, str(pl.get("section", "")), float(pl.get("span", 0.0)),
				bool(pl.get("cantilever", false)), PackedStringArray(pl.get("supports", [])),
				str(pl.get("label", "")), str(pl.get("part", "")))
		if why == "":
			g.plates[id].loads = (pl.get("loads", {}) as Dictionary).duplicate()
		else:
			push_warning("StructureGraph.from_dict: " + why)
	g.revision = int(data.get("revision", g.revision))
	return g


static func _sorted(d: Dictionary) -> Dictionary:
	var keys := d.keys()
	keys.sort()
	var out := {}
	for k: String in keys:
		out[k] = float(d[k])
	return out
