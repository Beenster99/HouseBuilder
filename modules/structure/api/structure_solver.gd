class_name StructureSolver
extends RefCounted
## Runs the structural graph solver: pure functions of a StructureGraph, with no scene or
## network dependencies, so they run headless and give the same answer on every machine.
## In a session only the host runs them (see StructureBus.run_stress_test()).
##
##   var report := StructureSolver.stress_test(graph)
##   if not report.passed(): print(report.summary, "\n", "\n".join(report.notes))
##
## The model is a simplified load path (see internal/load_path_solver.gd). A stiffness-
## matrix solver can replace it later behind these same calls and data.

const Solver := preload("res://modules/structure/internal/load_path_solver.gd")
const Notes := preload("res://modules/structure/internal/failure_notes.gd")


## One scenario.
static func solve(graph: StructureGraph, scenario: StructureScenario) -> StructureResult:
	return Solver.new(graph).solve(scenario)


## Each scenario in turn (normal use, storm, quake by default) with the failure report.
## Buildings with this many members or more solve their scenarios on separate threads
## (tests set it to 0 or a huge number to compare the two).
static var parallel_members := 400


static func stress_test(graph: StructureGraph, scenarios: Array[StructureScenario] = []) -> StructureReport:
	if scenarios.is_empty():
		scenarios = StructureScenario.standard()
	var solver = Solver.new(graph)
	var report := StructureReport.new()
	report.graph_revision = graph.revision
	# Scenarios only read the solver, so on a big building they run side by side. Each one's
	# numbers are worked out the same way whichever thread does it.
	if scenarios.size() > 1 and graph.members.size() >= parallel_members and OS.get_processor_count() > 1:
		var threads: Array[Thread] = []
		for i in range(1, scenarios.size()):
			var t := Thread.new()
			t.start(solver.solve.bind(scenarios[i]))
			threads.append(t)
		report.results.append(solver.solve(scenarios[0]))
		for t in threads:
			report.results.append(t.wait_to_finish())
	else:
		for sc in scenarios:
			report.results.append(solver.solve(sc))
	Notes.write(report, graph)
	return report


## Building parts that fall once the parts in removed are gone (see
## StructureBuilding.collapse_after()).
static func collapse_after(model: BuildingModel, removed: PackedStringArray, options: Dictionary = {}) -> PackedStringArray:
	return StructureBuilding.collapse_after(model, removed, options)
