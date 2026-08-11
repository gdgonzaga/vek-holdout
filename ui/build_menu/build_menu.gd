class_name BuildMenu
extends Control
## Build-mode selection menu (ARCH "Build" subsystem; first UI scene).
## Lists every unlocked buildable (display name only — no icons yet). Clicking
## one broadcasts EventBus.buildable_selected(id) so BuildController sets its
## selected_id and Player enters Blueprint mode. Only the no-selection dismissal
## (closed) stays as a local signal — the opener wires it.
##
## The container skeleton is authored in build_menu.tscn (ARCH line 135: UI is
## .tscn, not built dynamically); the per-buildable buttons are created in code
## in populate().

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
	# Broadcast the selection globally. BuildController listens and sets its
	# selected_id; Player listens and enters Blueprint mode. This menu stays
	# otherwise EventBus-agnostic — closed() (no-selection dismissal) stays local.
	EventBus.buildable_selected.emit(id)
	queue_free()


## Called by the opener when the menu should close without a selection (B-toggle
## from the menu state). Esc no longer closes it — it's reserved for the Pause
## Menu (GDD §4 controls table, line 214), and B is owned by the Player.
func close() -> void:
	closed.emit()
	queue_free()
