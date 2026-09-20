class_name RowFocus
extends RefCounted
## Keeps keyboard focus on "the same button of the same row" when a list is torn down
## and rebuilt. The panels rebuild their rows on every change, which would otherwise
## drop focus after each Enter and make Tab / Enter unusable. Rows opt in by setting
## KEY_META (an item id, a slot id) so they can be matched across the rebuild.
##
## Usage: token = RowFocus.capture(list) BEFORE removing the rows, then
## RowFocus.restore(list, token) once the new rows are in the list.

const KEY_META: StringName = &"row_key"


# =================
# Primary Functions
# =================

## Notes which row and button inside `list` has focus ({} when focus is elsewhere).
static func capture(list: Container) -> Dictionary:
	var viewport: Viewport = list.get_viewport()
	if viewport == null:
		return {}
	var focused: Control = viewport.gui_get_focus_owner()
	if focused == null or not list.is_ancestor_of(focused):
		return {}
	var row: Node = _row_containing(list, focused)
	if row == null:
		return {}
	return {"key": row.get_meta(KEY_META, null), "button": String(focused.name), "index": row.get_index()}


## Puts focus back on the noted button of the row with the same key; if that button
## is gone or disabled, on the first usable button of that row, else of the row now at
## the same position (a removed row hands focus to its neighbour). No-op for an empty token.
static func restore(list: Container, token: Dictionary) -> void:
	if token.is_empty() or list.get_child_count() == 0:
		return
	# 1. Same Row: The exact button when it is still usable.
	var row: Node = _find_row(list, token["key"])
	if row != null and _focus_named_button(row, token["button"]):
		return
	# 2. Fallbacks: Another button of that row, then whichever row now sits at the old position.
	var neighbour: Node = list.get_child(clampi(int(token["index"]), 0, list.get_child_count() - 1))
	for candidate: Node in [row, neighbour]:
		if candidate != null and _focus_first_usable_button(candidate):
			return


# ===================
# Auxiliary Functions
# ===================

static func _row_containing(list: Container, node: Node) -> Node:
	## Auxiliary: The direct child of `list` that `node` sits under.
	var current: Node = node
	while current != null and current.get_parent() != list:
		current = current.get_parent()
	return current


static func _find_row(list: Container, key: Variant) -> Node:
	## Auxiliary: The row tagged with `key`, or null (a null key matches nothing).
	if key == null:
		return null
	for child: Node in list.get_children():
		if child.get_meta(KEY_META, null) == key:
			return child
	return null


static func _is_usable(button: Button) -> bool:
	## Auxiliary: A button focus can actually land on right now.
	return button != null and not button.disabled and button.is_visible_in_tree() and button.focus_mode != Control.FOCUS_NONE


static func _focus_named_button(row: Node, button_name: String) -> bool:
	## Auxiliary: Focuses the row's button called `button_name` if it is usable.
	var button := row.find_child(button_name, true, false) as Button
	if not _is_usable(button):
		return false
	button.grab_focus()
	return true


static func _focus_first_usable_button(row: Node) -> bool:
	## Auxiliary: Focuses the first usable button anywhere under `row`.
	for node: Node in row.find_children("*", "Button", true, false):
		if _is_usable(node as Button):
			(node as Button).grab_focus()
			return true
	return false
