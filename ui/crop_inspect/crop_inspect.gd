extends Control
## Inspection UI panel for Farm Plots and Crops (GDD §6 / Farming, ARCH "Farming").
## Displays growth progress, hydration level, tending requirements, and estimated harvest time.

const _CROP_PICKER_SCENE: PackedScene = preload("res://ui/crop_picker/crop_picker.tscn")

@onready var _title_label: Label = %TitleLabel
@onready var _close_button: Button = %CloseButton
@onready var _crop_type_label: Label = %CropTypeLabel
@onready var _growth_val_label: Label = %GrowthValueLabel
@onready var _growth_bar: ProgressBar = %GrowthBar
@onready var _water_val_label: Label = %WaterValueLabel
@onready var _water_bar: ProgressBar = %WaterBar
@onready var _tending_label: Label = %TendingStatusLabel
@onready var _time_estimate_label: Label = %TimeEstimateLabel
@onready var _select_crop_button: Button = %SelectCropButton
@onready var _toggle_harvest_button: Button = %ToggleHarvestButton

var _actor: Node = null
var _target: Node = null
var _growable: Growable = null
var _harvestable: Harvestable = null


func _ready() -> void:
	UiGate.open_modal(self)
	_close_button.pressed.connect(close)
	_select_crop_button.pressed.connect(_on_select_crop_pressed)
	_toggle_harvest_button.pressed.connect(_on_toggle_harvest_pressed)


func _exit_tree() -> void:
	UiGate.close_modal(self)


func setup(actor: Node, target: Node) -> void:
	_actor = actor
	_target = target
	if _target != null:
		_growable = _target.get_node_or_null("Growable") as Growable
		_harvestable = _target.get_node_or_null("Harvestable") as Harvestable
		var tlabel = _target.get("label")
		if tlabel != null and tlabel != "":
			_title_label.text = str(tlabel)
	_refresh_display()


func _process(_delta: float) -> void:
	_refresh_display()


func _refresh_display() -> void:
	if _growable == null or not is_instance_valid(_growable):
		return

	var s := _growable.get_crop_state()
	var def := _growable.get_crop_def()
	var crop_name := def.display_name if def != null else "None"

	if s == Growable.CropState.EMPTY:
		var sel := _growable.get_selected_crop_id()
		if sel != "":
			var sel_def := CropLibrary.get_crop(sel)
			var sel_name := sel_def.display_name if sel_def != null else sel
			_crop_type_label.text = "Crop: Empty (Selected: %s)" % sel_name
		else:
			_crop_type_label.text = "Crop: Empty (No Crop Selected)"
		_growth_val_label.text = "0%"
		_growth_bar.value = 0.0
		_water_val_label.text = "N/A"
		_water_bar.value = 0.0
		_tending_label.text = "Tending Status: N/A"
		_time_estimate_label.text = "Est. Time to Harvest: N/A"
		_toggle_harvest_button.disabled = true
		_toggle_harvest_button.text = "Mark for Harvest"
		return

	_crop_type_label.text = "Crop: %s (%s)" % [crop_name, _state_name(s)]
	var prog := _growable.get_growth_progress()
	var pct := int(prog * 100.0)
	_growth_val_label.text = "%d%%" % pct
	_growth_bar.value = prog * 100.0

	var water_lvl := _growable.get_water_level()
	var dry_time_str := ""
	if def != null and def.water_decay_per_hour > 0.0:
		var dry_hours := water_lvl / def.water_decay_per_hour
		dry_time_str = " (~%.1fh left)" % dry_hours
	_water_val_label.text = "%d%%%s" % [int(water_lvl), dry_time_str]
	_water_bar.value = water_lvl

	if s == Growable.CropState.GROWING:
		if not _growable.is_tended():
			var gate_str := _build_gate_string(def)
			_tending_label.text = "Tending: [NEEDS TENDING]%s" % ((" - " + gate_str) if gate_str != "" else "")
			_tending_label.add_theme_color_override("font_color", Color("#ff7d7d"))
		else:
			_tending_label.text = "Tending: Satisfied"
			_tending_label.add_theme_color_override("font_color", Color("#7dff7d"))

		if def != null and def.growth_time_hours > 0.0:
			var remaining_hours := (1.0 - prog) * def.growth_time_hours
			_time_estimate_label.text = "Est. Time to Harvest: ~%.1f in-game hrs" % remaining_hours
		else:
			_time_estimate_label.text = "Est. Time to Harvest: Unknown"
	elif s == Growable.CropState.MATURE:
		_tending_label.text = "Tending: Mature"
		_time_estimate_label.text = "Est. Time to Harvest: Ready Now"
	else:
		_tending_label.text = "Tending: Withered"
		_time_estimate_label.text = "Est. Time to Harvest: Ruined"

	_toggle_harvest_button.disabled = false
	if _harvestable != null and _harvestable.is_marked_for_harvest():
		_toggle_harvest_button.text = "Unmark Harvest"
	else:
		_toggle_harvest_button.text = "Mark for Harvest"


func _build_gate_string(def: CropDef) -> String:
	if def == null or def.tend_conditions.is_empty():
		return ""
	var parts: Array[String] = []
	for c in def.tend_conditions:
		var min_skill := c as MinSkillCondition
		if min_skill != null:
			parts.append("%s Lvl %d" % [min_skill.skill_id.capitalize(), min_skill.min_level])
		var has_item := c as HasItemCondition
		if has_item != null:
			if has_item.item_tag != "":
				parts.append("Tool: %s" % has_item.item_tag.capitalize())
			elif has_item.item_id != "":
				parts.append("Item: %s" % has_item.item_id)
	return ", ".join(parts)


func _state_name(s: Growable.CropState) -> String:
	match s:
		Growable.CropState.EMPTY: return "Empty"
		Growable.CropState.GROWING: return "Growing"
		Growable.CropState.MATURE: return "Mature"
		Growable.CropState.WITHERED: return "Withered"
	return "Unknown"


func _on_select_crop_pressed() -> void:
	if _growable == null:
		return
	var picker := _CROP_PICKER_SCENE.instantiate()
	var layer := get_tree().get_first_node_in_group("hud_layer") as CanvasLayer
	if layer == null:
		layer = get_tree().get_first_node_in_group("ui_layer") as CanvasLayer
	if layer != null:
		layer.add_child(picker)
	else:
		add_child(picker)
	picker.setup(_actor, _growable)


func _on_toggle_harvest_pressed() -> void:
	if _harvestable != null:
		_harvestable.toggle_mark()
		_refresh_display()


func close() -> void:
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
