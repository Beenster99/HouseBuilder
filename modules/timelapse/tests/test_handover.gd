extends ModuleTest
## With a contract taken, a finished timelapse offers "Hand over" and shows the settlement.
## The contracts module is optional to the timelapse, so it is used by duck typing here.
##   tools/run_tests.sh timelapse


func run_tests() -> void:
	var bus := Modules.bus("timelapse") as TimelapseBus
	var c := Modules.bus("contracts")
	if c == null or not c.has_method("hand_over"):
		check(true, "no contracts module: nothing to hand over")
		return
	var view: Node3D = load("res://modules/timelapse/internal/timelapse_view.tscn").instantiate()
	add_child(view)
	bus.start_timelapse(preload("res://modules/timelapse/internal/demo_house.gd").parts(), "Handover house", false)
	await frames(2)
	var button := view.find_child("HandOver", true, false) as Button
	check(button != null and not button.visible, "no Hand over while building without a contract")
	if (c.get("active") as Dictionary).is_empty():
		var board: Array = c.get("board")
		check(not board.is_empty(), "the contracts board has briefs")
		if board.is_empty():
			return
		c.call("accept", str(board[0].id))
	check(not (c.get("active") as Dictionary).is_empty(), "a contract is taken")
	bus.request_seek(bus.total_days())
	await frames(2)
	check(button.visible, "Hand over appears once the building is complete")
	button.pressed.emit()
	await frames(2)
	var panel := view.find_child("Settlement", true, false) as Control
	check(panel != null and panel.visible, "the settlement is shown")
	check((c.get("active") as Dictionary).is_empty(), "the contract is settled")
	view.queue_free()
	bus.apply_net_snapshot({})
	await frames(1)
