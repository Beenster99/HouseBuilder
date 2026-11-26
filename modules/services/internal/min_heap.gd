extends RefCounted
## A binary min-heap of (cost, id) pairs. Ties go to the lower id, so a search pops cells in
## the same order on every machine.

var _cost := PackedFloat64Array()
var _id := PackedInt32Array()


func is_empty() -> bool:
	return _id.is_empty()


func push(cost: float, id: int) -> void:
	_cost.append(cost)
	_id.append(id)
	var i := _id.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if not _less(i, parent):
			break
		_swap(i, parent)
		i = parent


## Removes the lowest pair and returns its id (read top_cost() first for its cost).
func pop() -> int:
	var top := _id[0]
	var last := _id.size() - 1
	_swap(0, last)
	_cost.resize(last)
	_id.resize(last)
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < last and _less(l, m):
			m = l
		if r < last and _less(r, m):
			m = r
		if m == i:
			break
		_swap(i, m)
		i = m
	return top


func top_cost() -> float:
	return _cost[0]


func _less(a: int, b: int) -> bool:
	if _cost[a] != _cost[b]:
		return _cost[a] < _cost[b]
	return _id[a] < _id[b]


func _swap(a: int, b: int) -> void:
	var c := _cost[a]
	_cost[a] = _cost[b]
	_cost[b] = c
	var d := _id[a]
	_id[a] = _id[b]
	_id[b] = d
