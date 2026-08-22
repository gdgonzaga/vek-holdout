extends Control
## HUD overlay for Dig Box Designation mode (ARCH "UI").
## Displays control instructions, active mode, and current box dimensions.

@onready var _mode_label: Label = %ModeLabel
@onready var _width_label: Label = %WidthLabel
@onready var _height_label: Label = %HeightLabel
@onready var _depth_label: Label = %DepthLabel
@onready var _instructions_label: Label = %InstructionsLabel

var _current_mode: String = "Horizontal"


func _ready() -> void:
	visible = false
	EventBus.dig_box_toggled.connect(_on_dig_box_toggled)
	EventBus.dig_box_dimensions_changed.connect(_on_dimensions_changed)
	EventBus.dig_box_mode_changed.connect(_on_mode_changed)
	_update_hud(1, 3, 3, "Horizontal")


func _on_dig_box_toggled(active: bool) -> void:
	visible = active
	if active:
		_update_hud(1, 3, 3, "Horizontal")


func _on_mode_changed(mode_name: String) -> void:
	_current_mode = mode_name
	if _mode_label:
		_mode_label.text = "Mode: %s" % mode_name
	_update_instructions()


func _on_dimensions_changed(width: int, height: int, depth: int) -> void:
	_update_hud(width, height, depth, _current_mode)


func _update_hud(width: int, height: int, depth: int, mode_name: String) -> void:
	_current_mode = mode_name
	if _mode_label:
		_mode_label.text = "Mode: %s" % mode_name
	if _width_label:
		_width_label.text = "Width: %d" % width
	if _height_label:
		_height_label.text = "Height: %d" % height
	if _depth_label:
		if mode_name.begins_with("Stairway"):
			_depth_label.text = "Steps: %d" % depth
		else:
			_depth_label.text = "Depth: %d" % depth
	_update_instructions()


func _update_instructions() -> void:
	if not _instructions_label:
		return
	if _current_mode.begins_with("Stairway"):
		_instructions_label.text = "RMB: Cycle Mode (Horiz/Vert/Stair)\nScroll: Adjust Steps\nLMB: Confirm Dig\nEsc / Shift+G: Cancel"
	else:
		_instructions_label.text = "RMB: Cycle Mode (Horiz/Vert/Stair)\nScroll: Width\nCtrl + Scroll: Height\nShift + Scroll: Depth\nLMB: Confirm Dig\nEsc / Shift+G: Cancel"
