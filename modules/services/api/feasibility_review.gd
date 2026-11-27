class_name FeasibilityReview
extends RefCounted
## The consultant's verdict on a design: can it be built as drawn? It reads the structural
## stress test (structure module), the services routing (this module) and, when there is a
## contract, the brief's requirements and budget (contracts module), and says in plain words
## what stops the design and what to do first.
##
##   var r := FeasibilityReview.review(model)              # no brief: structure, services, cost
##   var r := FeasibilityReview.review(model, brief)       # against a contract brief
##   r.feasible           # true when nothing blocks it
##   r.summary            # "Feasible: it stands up, is powered and plumbed, and comes in at ..."
##   r.issues             # [{area, text, tip}] worst first; area: structure | services | requirements | budget
##   r.areas              # {structure: {ok, summary, worst, failing}, services: {ok, summary, served, total},
##                        #  requirements: {ok, summary, passed, total}, budget: {ok, summary}}
##   r.cost               # {build, services, total, budget, currency}
##   r.fixes              # {structure?: {possible, added, upsized, cost, notes}, services?: {...}}
##   r.fixable            # Design structure and Design services would make it feasible
##   r.cost.after_fixes   # all-in cost once both are applied
##   r.structure, r.services, r.assessment   # the full reports behind it
##
## The build cost is the building's own price (BuildingQuantities); the services routes are
## priced on top, since the catalog's fit-out rates do not route anything. A contract budget
## is checked against the two together. Deterministic: every player who asks gets the same.

const MAX_ISSUES_PER_AREA := 3


static func review(model: BuildingModel, brief: Dictionary = {}, sources: Dictionary = {}) -> Dictionary:
	var out := {"feasible": false, "issues": [], "areas": {}, "cost": {}, "summary": ""}
	if model == null or (model.rooms.is_empty() and model.parts.is_empty()):
		out.summary = "Nothing to review yet: draw some rooms first."
		out.issues.append({"area": "design", "text": "The design is empty.", "tip": "Draw some rooms and walls."})
		return out
	var issues: Array = []

	# Structure.
	var st := StructureBuilding.stress_test(model)
	out["structure"] = st
	var st_ok := st.passed()
	out.areas["structure"] = {"ok": st_ok, "summary": st.summary, "worst": snappedf(st.worst_utilisation(), 0.001),
		"failing": st.failed_parts().size()}
	if not st_ok:
		var lines := Array(st.notes)
		if lines.is_empty():
			lines = [st.summary]
		for n: String in lines.slice(0, MAX_ISSUES_PER_AREA):
			# The structure report's lines already say what to try.
			issues.append({"area": "structure", "text": n, "tip": ""})

	# Services.
	var sv := ServicesConsultant.route(model, sources)
	out["services"] = sv
	var sv_ok := sv.passed()
	out.areas["services"] = {"ok": sv_ok, "summary": sv.summary, "served": sv.rooms.size() - sv.failures().size(),
		"total": sv.rooms.size()}
	if not sv_ok:
		var n := 0
		for rid: String in sv.failures():
			if n >= MAX_ISSUES_PER_AREA:
				break
			var miss := PackedStringArray()
			for s: String in sv.failures()[rid]:
				miss.append(ServicesRates.label(s).to_lower())
			issues.append({"area": "services", "text": "%s has no %s." % [str(sv.rooms[rid].name), " or ".join(miss)],
				"tip": _service_tip(sv, rid)})
			n += 1
	for w: String in sv.warnings.slice(0, MAX_ISSUES_PER_AREA):
		issues.append({"area": "services", "text": w, "tip": "Use Design services, or move the room nearer the stack.", "soft": true})

	# Cost, requirements and budget.
	var totals := BuildingQuantities.totals(model)
	var build := float(totals.cost)
	var total := build + sv.total_cost
	out.cost = {"build": snappedf(build, 0.01), "services": sv.total_cost, "total": snappedf(total, 0.01),
		"budget": 0.0, "currency": str(totals.get("currency", "GBP"))}
	var req_ok := true
	var budget_ok := true
	if not brief.is_empty():
		var a := ContractValidator.assess(brief, model, st.brief_result())
		out["assessment"] = a
		req_ok = true
		var n := 0
		for item: Dictionary in a.items:
			if not bool(item.hard) or bool(item.ok) or str(item.kind) in ["budget", "structure"]:
				continue
			req_ok = false
			if n < MAX_ISSUES_PER_AREA:
				issues.append({"area": "requirements", "text": "%s: %s" % [item.label, item.get("detail", "")], "tip": str(item.get("tip", ""))})
			n += 1
		out.areas["requirements"] = {"ok": req_ok, "summary": "%d of %d requirements met." % [int(a.passed), int(a.total)],
			"passed": int(a.passed), "total": int(a.total)}
		var budget := float(a.budget)
		out.cost.budget = budget
		if budget > 0.0:
			budget_ok = total <= budget
			out.areas["budget"] = {"ok": budget_ok, "summary": "%s all in (%s build, %s services) of %s." % [
				_money(total), _money(build), _money(sv.total_cost), _money(budget)]}
			if not budget_ok:
				issues.append({"area": "budget", "text": "It costs %s all in, %s over the %s budget." % [
					_money(total), _money(total - budget), _money(budget)], "tip": _budget_tip(totals, sv)})
	else:
		out.areas["budget"] = {"ok": true, "summary": "%s all in (%s build, %s services); no budget set." % [
			_money(total), _money(build), _money(sv.total_cost)]}

	# What the engineers could fix: dry runs of Design structure and Design services on a copy.
	var fixed := BuildingModel.from_data(model.to_data(), model.catalog)
	var fixes := {}
	if not st_ok:
		var sp := StructureDesigner.design(model)
		if not (sp.op as Dictionary).is_empty():
			fixed.apply(sp.op)
		var extra := float(BuildingQuantities.totals(fixed).cost) - build
		fixes["structure"] = {"possible": bool(sp.passed), "added": int(sp.added), "upsized": int(sp.upsized),
			"cost": snappedf(extra, 0.01), "notes": sp.notes}
		var tip := "Design structure fixes this (%d parts added, %d made bigger, about %s)." % [int(sp.added), int(sp.upsized), _money(extra)] \
				if bool(sp.passed) else "Design structure cannot fix all of it: " + (str(sp.notes[sp.notes.size() - 1]) if not (sp.notes as PackedStringArray).is_empty() else "it needs a rethink.")
		for i: Dictionary in issues:
			if i.area == "structure":
				i.tip = tip
	var plan := ServicesDesigner.propose(fixed, sources)
	if not (plan.ops as Array).is_empty() or not sv_ok:
		for op: Dictionary in plan.ops:
			fixed.apply(op)
		var after: ServicesReport = plan.after
		fixes["services"] = {"possible": after.passed(), "added": (plan.added as Array).size(),
			"cost": snappedf(after.total_cost - sv.total_cost, 0.01), "notes": plan.notes}
	var fixed_build := float(BuildingQuantities.totals(fixed).cost)
	var fixed_total := fixed_build + (plan.after as ServicesReport).total_cost
	out.cost["after_fixes"] = snappedf(fixed_total, 0.01)
	out["fixes"] = fixes
	var fix_ok := bool(fixes.get("structure", {}).get("possible", true)) and bool(fixes.get("services", {}).get("possible", true))
	var fix_budget := float(out.cost.budget) <= 0.0 or fixed_total <= float(out.cost.budget)
	out["fixable"] = fix_ok and req_ok and fix_budget

	out.issues = issues
	var blocking := issues.filter(func(i: Dictionary) -> bool: return not bool(i.get("soft", false)))
	out.feasible = st_ok and sv_ok and req_ok and budget_ok
	if out.feasible:
		out.summary = "Feasible: it stands up to the stress tests, every room is powered and plumbed, and it comes to %s all in." % _money(total)
		if not brief.is_empty():
			out.summary += " It meets the brief within budget."
	else:
		var bad := PackedStringArray()
		for area: String in ["structure", "services", "requirements", "budget"]:
			if out.areas.has(area) and not bool(out.areas[area].ok):
				bad.append(area)
		out.summary = "Not feasible yet (%s). Start with: %s" % [", ".join(bad), str(blocking[0].text) if not blocking.is_empty() else ""]
		if fix_ok and not fixes.is_empty():
			var press := PackedStringArray()
			for k: String in ["structure", "services"]:
				if fixes.has(k):
					press.append("Design " + k)
			if fix_budget:
				out.summary += " %s would make it work, at %s all in." % [" and ".join(press), _money(fixed_total)]
			else:
				out.summary += " %s would make it stand and work, but at %s all in it is still %s over budget." % [
					" and ".join(press), _money(fixed_total), _money(fixed_total - float(out.cost.budget))]
	return out


static func _service_tip(sv: ServicesReport, rid: String) -> String:
	var miss: Array = sv.failures()[rid]
	if "waste" in miss:
		return "Waste only runs downhill: put a soil stack under this room, or move it above one."
	return "Something walls it off (a curtain wall or lift shaft): add a door, or use Design services."


static func _budget_tip(totals: Dictionary, sv: ServicesReport) -> String:
	var fam: Dictionary = totals.get("by_family", {})
	var biggest := ""
	for f: String in BuildingModel.sort_ids(fam.keys()):
		if biggest == "" or float(fam[f]) > float(fam[biggest]):
			biggest = f
	var fit := float(totals.get("fit_out", 0.0))
	if fit > float(fam.get(biggest, 0.0)):
		return "Fit-out is the biggest spend (%s): fewer or plainer rooms cost less." % _money(fit)
	if biggest != "":
		return "The %s cost most (%s): try a cheaper material or a lighter section." % [biggest, _money(float(fam[biggest]))]
	return "Services cost %s: group wet rooms over each other to shorten the runs." % _money(sv.total_cost)


static func _money(v: float) -> String:
	return ServicesConsultant._money(v)
