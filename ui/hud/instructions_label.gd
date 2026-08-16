extends Label

const _MENU_TEXT := "Click an item to place\nEsc: cancel"
const _PLACEMENT_TEXT := "Esc: cancel"

func _ready() -> void:
	EventBus.build_menu_toggled.connect(_on_build_menu_toggled)
	EventBus.build_placement_toggled.connect(_on_build_placement_toggled)


func _on_build_placement_toggled(active: bool) -> void:
	if active:
		text = _PLACEMENT_TEXT
	visible = active


func _on_build_menu_toggled(open: bool) -> void:
	if open:
		text = _MENU_TEXT
	visible = open
