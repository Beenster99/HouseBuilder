class_name BuildingHistory
extends RefCounted
## Shared undo and redo for a BuildingModel, kept on the host. Every player has their own
## stacks, so Ctrl+Z takes back your last edit, not your friend's. Undo and redo are edits
## like any other: each returns the op as applied, for the host to broadcast to clients
## (who just call model.apply(op)).
##
##   var history := BuildingHistory.new(model)
##   var done := history.commit(op, author)   # {} if refused, else the op to broadcast
##   history.commit(op, author, "drag-7")     # same group, same author: one undo step
##   var undone := history.undo(author)       # {} if nothing to undo
##   var redone := history.redo(author)
##
## author is any String (a peer id). If someone else has since removed what your edit
## touched, that edit can no longer be undone and is skipped for the one before it.
## log holds every op applied through here, in order: {seq, author, op}.

signal committed(seq: int, author: String, op: Dictionary)

## Undo steps kept per author.
const LIMIT := 200

var model: BuildingModel
var log: Array = []
var seq := 0
## author -> Array of {"do", "undo"}, newest last.
var _undo: Dictionary = {}
var _redo: Dictionary = {}


func _init(building: BuildingModel) -> void:
	model = building


## Applies an edit for an author. Returns the op as applied ({} if refused). Consecutive
## commits by one author with the same non-empty group (one drag, one paint stroke) undo as
## one step.
func commit(op: Dictionary, author: String = "", group: String = "") -> Dictionary:
	var r := model.apply(op)
	if r.is_empty():
		return {}
	var stack: Array = _undo.get(author, [])
	if group != "" and not stack.is_empty() and str(stack[-1].get("group", "")) == group:
		var top: Dictionary = stack[-1]
		top["undo"] = {"op": "batch", "ops": [r.undo, top.undo]}
	else:
		_push(_undo, author, {"do": r.do, "undo": r.undo, "group": group})
	_redo.erase(author)
	return _record(author, r.do)


## Undoes the author's latest edit that still applies. Returns the op as applied.
func undo(author: String = "") -> Dictionary:
	var stack: Array = _undo.get(author, [])
	while not stack.is_empty():
		var step: Dictionary = stack.pop_back()
		var r := model.apply(step.undo)
		if not r.is_empty():
			_push(_redo, author, r)
			return _record(author, r.do)
	return {}


## Redoes the author's latest undone edit. Returns the op as applied.
func redo(author: String = "") -> Dictionary:
	var stack: Array = _redo.get(author, [])
	while not stack.is_empty():
		var step: Dictionary = stack.pop_back()
		var r := model.apply(step.undo)
		if not r.is_empty():
			_push(_undo, author, r)
			return _record(author, r.do)
	return {}


func can_undo(author: String = "") -> bool:
	return not (_undo.get(author, []) as Array).is_empty()


func can_redo(author: String = "") -> bool:
	return not (_redo.get(author, []) as Array).is_empty()


## Forgets every stack and the log (after loading another design).
func clear() -> void:
	_undo.clear()
	_redo.clear()
	log.clear()
	seq = 0


func _push(stacks: Dictionary, author: String, step: Dictionary) -> void:
	if not stacks.has(author):
		stacks[author] = []
	var stack: Array = stacks[author]
	stack.append(step)
	if stack.size() > LIMIT:
		stack.pop_front()


func _record(author: String, op: Dictionary) -> Dictionary:
	seq += 1
	log.append({"seq": seq, "author": author, "op": op})
	committed.emit(seq, author, op)
	return op
