extends Control
## Modal crop selector for farm plots (GDD §6 / Farming, ARCH "Farming").

@onready var _close_button: Button = %CloseButton
@onready var _crop_list: VBoxContainer = %CropList

var _actor: Node = null
var _growable: Growable = null


func _ready() -> void:
	UiGate.open_modal(self)
	_close_button.pressed.connect(close)


func _exit_tree() -> void:
	UiGate.close_modal(self)


func setup(actor: Node, growable: Growable) -> void:
	_actor = actor
	_growable = growable
	_populate_crops()


func _populate_crops() -> void:
	for child in _crop_list.get_children():
		child.queue_free()

	if _growable == null:
		return

	var all_crops := CropLibrary.get_all_crops()
	var params := _growable.params()
	var allowed := params.allowed_crops if params != null else []

	for crop in all_crops:
		if not allowed.is_empty() and not allowed.has(crop.id):
			continue
		var btn := Button.new()
		var desc := "%s (Growth: ~%.0fh, Water Decay: %.1f/h)" % [crop.display_name, crop.growth_time_hours, crop.water_decay_per_hour]
		btn.text = desc
		btn.pressed.connect(_on_crop_selected.bind(crop.id))
		_crop_list.add_child(btn)

	var clear_btn := Button.new()
	clear_btn.text = "None (Clear Crop)"
	clear_btn.pressed.connect(_on_crop_selected.bind(""))
	_crop_list.add_child(clear_btn)


func _on_crop_selected(crop_id: String) -> void:
	if _growable != null and is_instance_valid(_growable):
		_growable.set_selected_crop(crop_id)
	close()


func close() -> void:
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
