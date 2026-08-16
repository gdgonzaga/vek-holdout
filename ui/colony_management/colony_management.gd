extends Control
## Colony Management window with tabbed sections for colony overview, colonist roster,
## labor assignments, crafting stations, and storage management.
##
## Opened via Tab hotkey (or UI button). Closed via Tab/Esc hotkey or close button.

@onready var _close_button: Button = %CloseButton
@onready var _tab_container: TabContainer = %TabContainer


func _ready() -> void:
	if _close_button != null:
		_close_button.pressed.connect(_on_close_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("colony_management"):
		SceneManager.close_screen()
		get_viewport().set_input_as_handled()


func _on_close_pressed() -> void:
	SceneManager.close_screen()
