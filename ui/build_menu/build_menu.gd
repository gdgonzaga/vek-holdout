class_name BuildMenu
extends Control
## Build-mode selection menu (ARCH "Build" subsystem; first UI scene).
## Lists every unlocked buildable (display name only — no icons yet). Clicking
## one emits buildable_selected(id) so the opener can enter Blueprint mode with
## that buildable selected.
##
## The container skeleton is authored in build_menu.tscn (ARCH line 135: UI is
## .tscn, not built dynamically); the per-buildable buttons are created in code
## in populate().

signal buildable_selected(id: String)
signal closed()

@onready var _list: VBoxContainer = $Panel/List


## Read BuildLibrary and fill the list with one button per unlocked buildable.
func populate() -> void:
	for child in _list.get_children():
		child.queue_free()
	for def in BuildLibrary.get_unlocked():
		var btn := Button.new()
		btn.text = def.display_name
		btn.pressed.connect(_on_button_pressed.bind(def.id))
		_list.add_child(btn)


func _on_button_pressed(id: String) -> void:
	buildable_selected.emit(id)
	queue_free()


## Called by the opener when the menu should close without a selection (Esc, B).
func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	# Esc closes the menu without entering build mode. (B-toggle is handled by the
	# opener, not here, so we don't double-handle.)
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
