extends Control
## HUD overlay for Dig Box Designation mode (ARCH "UI").
## Displays control instructions and current box dimensions.

@onready var _width_label: Label = %WidthLabel
@onready var _height_label: Label = %HeightLabel
@onready var _depth_label: Label = %DepthLabel
@onready var _instructions_label: Label = %InstructionsLabel


func _ready() -> void:
	visible = false
	EventBus.dig_box_toggled.connect(_on_dig_box_toggled)
	EventBus.dig_box_dimensions_changed.connect(_on_dimensions_changed)
	_update_dimensions(1, 3, 1)


func _on_dig_box_toggled(active: bool) -> void:
	visible = active
	if active:
		_update_dimensions(1, 3, 1)


func _on_dimensions_changed(width: int, height: int, depth: int) -> void:
	_update_dimensions(width, height, depth)


func _update_dimensions(width: int, height: int, depth: int) -> void:
	if _width_label:
		_width_label.text = "Width: %d" % width
	if _height_label:
		_height_label.text = "Height: %d" % height
	if _depth_label:
		_depth_label.text = "Depth: %d" % depth
