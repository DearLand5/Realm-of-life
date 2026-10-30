class_name EditorHistory
extends RefCounted
## Snapshot-based undo/redo for the creature editor.
##
## Every entry is a full design state {genome: Dictionary, selected: int,
## label: String}: genomes are small (a few KB of JSON-safe data), so whole
## snapshots are simpler and more robust than inverse commands (any edit,
## including structural ones, is undoable for free).
##
##   var h := EditorHistory.new()
##   h.reset(state)            # initial state (after loading a design)
##   h.push(state)             # after each committed edit
##   var s := h.undo()         # {} when nothing to undo
##   var r := h.redo()
## `current()` is the state the document should be in now.

const DEFAULT_LIMIT := 200

var limit: int = DEFAULT_LIMIT
var _states: Array[Dictionary] = []
var _index: int = -1


func reset(state: Dictionary) -> void:
	_states.clear()
	_states.append(state)
	_index = 0


## Appends a state after the current one (drops the redo branch). Returns
## false when the state equals the current one (nothing recorded).
func push(state: Dictionary) -> bool:
	if _index >= 0 and _same(_states[_index], state):
		# Keep the newest selection without creating an undo step.
		_states[_index]["selected"] = state.get("selected", -1)
		return false
	while _states.size() > _index + 1:
		_states.pop_back()
	_states.append(state)
	while _states.size() > maxi(limit, 2):
		_states.pop_front()
	_index = _states.size() - 1
	return true


func can_undo() -> bool:
	return _index > 0


func can_redo() -> bool:
	return _index >= 0 and _index < _states.size() - 1


func undo() -> Dictionary:
	if not can_undo():
		return {}
	_index -= 1
	return _states[_index]


func redo() -> Dictionary:
	if not can_redo():
		return {}
	_index += 1
	return _states[_index]


func current() -> Dictionary:
	return _states[_index] if _index >= 0 else {}


## Label of the edit that undo() would revert ("" if none).
func undo_label() -> String:
	return str(_states[_index].get("label", "")) if can_undo() else ""


func redo_label() -> String:
	return str(_states[_index + 1].get("label", "")) if can_redo() else ""


func size() -> int:
	return _states.size()


func index() -> int:
	return _index


static func _same(a: Dictionary, b: Dictionary) -> bool:
	return a.get("genome", {}) == b.get("genome", {})
