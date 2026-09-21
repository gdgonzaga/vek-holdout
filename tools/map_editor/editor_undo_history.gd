class_name EditorUndoHistory
extends RefCounted
## Bounded stack of undo entries (formats documented in map-editor.md section B).

const MAX_DEPTH: int = 50

var entries: Array[Dictionary] = []


func push(entry: Dictionary) -> void:
	entries.append(entry)
	if entries.size() > MAX_DEPTH:
		entries.pop_front()


## The newest entry, removed; an empty Dictionary when there is none.
func pop() -> Dictionary:
	return entries.pop_back() if not entries.is_empty() else {}


func clear() -> void:
	entries.clear()


func size() -> int:
	return entries.size()


func is_empty() -> bool:
	return entries.is_empty()
