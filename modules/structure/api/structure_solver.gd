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
static func stress_test(graph: StructureGraph, scenarios: Array[StructureScenario] = []) -> StructureReport:
	if scenarios.is_empty():
		scenarios = StructureScenario.standard()
	var solver = Solver.new(graph)
	var report := StructureReport.new()
	report.graph_revision = graph.revision
	for sc in scenarios:
		report.results.append(solver.solve(sc))
	Notes.write(report, graph)
	return report
