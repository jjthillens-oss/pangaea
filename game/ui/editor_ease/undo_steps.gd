extends RefCounted
## Editor-ease (docs/proposals/editor-ease.md): what one Undo takes back in the cell editor. EditorSession
## (game/domain/editor_session.gd) checkpoints every op, so a drag round the rim, which moves the part on every
## mouse motion, would take one Undo per motion event. This counts the session's steps per player action: an
## op outside a group is a step of its own; the ops between begin_group() and end_group() (a drag, or a part and
## its symmetry twin) are one step. undo() and redo() then step the session that many times. UI only: the
## session's own stacks are untouched (GitHub issue #209 asks for gestures in EditorSession). No class_name.

## The session steps in each action that can be undone, the newest last.
var _undo: Array[int] = []
## The same for the actions that can be redone.
var _redo: Array[int] = []
## The steps in the open group so far; -1 when no group is open.
var _open := -1


## Forgets every action (a new session).
func reset() -> void:
	_undo.clear()
	_redo.clear()
	_open = -1


## Opens a group: the session steps until end_group() are one action. A group already open stays open.
func begin_group() -> void:
	if _open < 0:
		_open = 0


## Closes the open group; an empty one (a press without a move) leaves nothing to undo.
func end_group() -> void:
	if _open > 0:
		_undo.append(_open)
	_open = -1


func in_group() -> bool:
	return _open >= 0


## Records an op's outcome: an accepted op (`ok`) is one session step, added to the open group or an action of
## its own. Like the session, a new step drops what could be redone. A refused op made no step.
func note(ok: bool) -> void:
	if not ok:
		return
	_redo.clear()
	if _open >= 0:
		_open += 1
	else:
		_undo.append(1)


## Takes back the last action: as many session undos as it made steps. A step no action holds (an op made on
## the session directly) is undone alone. Returns whether anything changed.
func undo(session: EditorSession) -> bool:
	end_group()
	if _undo.is_empty():
		return session.undo()
	var done := 0
	for i in _undo.pop_back():
		if session.undo():
			done += 1
	if done > 0:
		_redo.append(done)
	return done > 0


## Puts the last undone action back.
func redo(session: EditorSession) -> bool:
	end_group()
	if _redo.is_empty():
		return session.redo()
	var done := 0
	for i in _redo.pop_back():
		if session.redo():
			done += 1
	if done > 0:
		_undo.append(done)
	return done > 0


## The number of actions Undo can take back (for tests and the key line).
func undo_count() -> int:
	return _undo.size() + (1 if _open > 0 else 0)
