extends RefCounted
## Turns a stress test into plain words: a summary line and, for each failure, what gave
## way, why, and what to try. Members are named by their label if they have one.

const MAX_NOTES := 12


static func write(report: StructureReport, graph: StructureGraph) -> void:
	var notes := PackedStringArray()
	var said := {}
	for r in report.results:
		for id in r.failures:
			if said.has(id) or notes.size() >= MAX_NOTES:
				continue
			said[id] = true
			notes.append(_note(r, id, graph))
	report.notes = notes
	if report.results.is_empty():
		report.summary = "Nothing was tested."
	elif report.passed():
		var worst_u := -1.0
		var worst_id := ""
		var worst_scenario := ""
		for r in report.results:
			var w := r.worst()
			if w.u > worst_u:
				worst_u = w.u
				worst_id = w.id
				worst_scenario = r.scenario_title
		if worst_id == "":
			report.summary = "Passes every test."
		else:
			report.summary = "Passes every test. Most loaded: %s at %d%% in the %s test." % [
					_name(graph, worst_id), roundi(worst_u * 100.0), worst_scenario.to_lower()]
	else:
		var first := report.first_failure()
		var r := report.result(first.scenario)
		report.summary = "Fails the %s test: %d over capacity. First to give way: %s at %s." % [
				r.scenario_title.to_lower(), r.failures.size(), _name(graph, first.id), _pct(first.u)]


static func _note(r: StructureResult, id: String, graph: StructureGraph) -> String:
	var who := _name(graph, id)
	if r.anchors.has(id):
		var a: Dictionary = r.anchors[id]
		return "%s carries %d kN, %s of what the ground can take (%s). Use a bigger pad, a strip or raft footing, or piles." % [
				who, roundi(a.load), _pct(a.u), r.scenario_title.to_lower()]
	var m: Dictionary = r.members[id]
	var pct := _pct(m.u)
	var when := "in the %s test" % r.scenario_title.to_lower()
	var from := ""
	if bool(m.lateral) and int(m.direction) >= 0:
		var sc := StructureScenario.by_id(r.scenario_id)
		if sc and int(m.direction) < sc.directions.size():
			from = " " + StructureScenario.direction_name(sc.directions[int(m.direction)])
	match str(m.mode):
		"unsupported":
			return "%s is not connected to any foundation, so nothing holds it up. Connect it to a column or wall that reaches the ground." % who
		"shear":
			if m.kind == StructureGraph.WALL:
				return "%s racks at %s %s%s. Make it longer or stronger, or add another wall in the same line." % [who, pct, when, from]
			return "%s fails in shear at %s %s. Use a deeper section or shorten the span." % [who, pct, when]
	if bool(m.lateral):
		match str(m.kind):
			StructureGraph.BRACE:
				return "%s is overloaded at %s %s%s. Add more bracing in that direction or use a stronger brace." % [who, pct, when, from]
			StructureGraph.WALL:
				return "%s is overloaded at %s %s%s. Add shear walls or bracing in that direction." % [who, pct, when, from]
		return "%s sways and bends at %s %s%s. Add a brace or a shear wall in that direction." % [who, pct, when, from]
	if str(m.mode) == "bending":
		if bool(m.cantilever):
			return "%s cantilevers %.1f m and bends at %s %s. Support its free end with a column or wall, or shorten it." % [
					who, float(m.length), pct, when]
		return "%s spans %.1f m and bends at %s %s. Add a column or wall under it, or use a deeper section." % [
				who, float(m.length), pct, when]
	match str(m.kind):
		StructureGraph.COLUMN:
			return "%s is crushed at %s %s. Use a bigger section or add columns to share the load." % [who, pct, when]
		StructureGraph.WALL:
			return "%s is crushed by the floors above at %s %s. Make it thicker or add columns or walls to share the load." % [who, pct, when]
		StructureGraph.BRACE:
			return "%s is overloaded at %s %s. Use a stronger brace." % [who, pct, when]
	return "%s is overloaded at %s %s. Use a bigger section or add support." % [who, pct, when]


static func _pct(u: float) -> String:
	if u >= StructureResult.UNSUPPORTED:
		return "no support"
	return "%d%%" % roundi(u * 100.0)


static func _name(graph: StructureGraph, id: String) -> String:
	if graph.members.has(id):
		var m: Dictionary = graph.members[id]
		if str(m.label) != "":
			return str(m.label)
		return "%s %s" % [str(m.kind).capitalize(), id]
	if graph.nodes.has(id):
		return "Foundation %s" % id
	return id
