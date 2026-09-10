class_name EquipmentSlotRow
extends PanelContainer
## Single equipment slot row in the colonist equipment panel.
## Displays slot name, currently equipped item, desired target, and actions.

signal edit_requested(slot_id: String)
signal clear_requested(slot_id: String)
signal unequip_requested(slot_id: String)

var _slot_id: String = ""
var _colonist: Colonist = null

@onready var _slot_label: Label = %SlotLabel
@onready var _equipped_label: Label = %EquippedLabel
@onready var _unequip_button: Button = %UnequipButton
@onready var _desired_label: Label = %DesiredLabel
@onready var _status_label: Label = %StatusLabel
@onready var _set_target_button: Button = %SetTargetButton
@onready var _clear_target_button: Button = %ClearTargetButton

# ================
# Primary Functions
# ================

func _ready() -> void:
	_connect_button_signals()


## Initializes the row with target slot and colonist reference.
func setup(slot_id: String, colonist: Colonist) -> void:
	_slot_id = slot_id
	_colonist = colonist
	# 1. Display Refresh: Updates slot labels, equipped item, and desired target status.
	refresh()


## Refreshes all visual labels and button states for this slot.
func refresh() -> void:
	if _slot_id.is_empty() or _colonist == null or not is_instance_valid(_colonist):
		return
	if not is_node_ready():
		return

	# 1. Slot Name: Set human-readable slot name title.
	_slot_label.text = _format_slot_name(_slot_id)

	# 2. Equipped Item: Update current equipped item label and unequip button visibility.
	_update_equipped_display()

	# 3. Desired Target: Update desired target item and status badge.
	_update_desired_display()


func get_slot_id() -> String:
	return _slot_id

# ====================
# Auxiliary Functions
# ====================

func _connect_button_signals() -> void:
	## Auxiliary: Connects pressed signals from row buttons to event emitters.
	if _set_target_button != null and not _set_target_button.pressed.is_connected(_on_set_target_pressed):
		_set_target_button.pressed.connect(_on_set_target_pressed)
	if _clear_target_button != null and not _clear_target_button.pressed.is_connected(_on_clear_target_pressed):
		_clear_target_button.pressed.connect(_on_clear_target_pressed)
	if _unequip_button != null and not _unequip_button.pressed.is_connected(_on_unequip_pressed):
		_unequip_button.pressed.connect(_on_unequip_pressed)


func _format_slot_name(raw_slot: String) -> String:
	## Auxiliary: Converts internal snake_case slot ID to title case.
	return raw_slot.replace("_", " ").capitalize()


func _update_equipped_display() -> void:
	## Auxiliary: Evaluates the currently equipped item and configures labels and unequip button.
	var eq: Equipment = _colonist.equipment
	var current_item: ItemDef = eq.get_item(_slot_id) if eq != null else null
	if current_item != null:
		var item_name: String = current_item.resource_name if current_item.resource_name != "" else current_item.id
		_equipped_label.text = item_name
		_equipped_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
		_unequip_button.visible = true
	else:
		_equipped_label.text = "(Empty)"
		_equipped_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1.0))
		_unequip_button.visible = false


func _update_desired_display() -> void:
	## Auxiliary: Evaluates desired target item and configures desired target label, status, and clear button.
	var eq: Equipment = _colonist.equipment
	var desired_id: String = eq.get_desired_item(_slot_id) if eq != null else ""

	if desired_id.is_empty():
		_desired_label.text = "(None)"
		_desired_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1.0))
		_status_label.text = ""
		_clear_target_button.visible = false
	else:
		var def: ItemDef = ItemDB.get_def(desired_id)
		var d_name: String = def.resource_name if (def != null and def.resource_name != "") else desired_id
		_desired_label.text = d_name
		_desired_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85, 1.0))
		_clear_target_button.visible = true

		# 1. Status Evaluation: Determine if desired item is equipped or pending.
		var is_equipped: bool = eq != null and eq.is_desired_equipped(_slot_id)
		if is_equipped:
			_status_label.text = "✓ Equipped"
			_status_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3, 1.0))
		else:
			_status_label.text = "⏳ Pending"
			_status_label.add_theme_color_override("font_color", Color(0.9, 0.75, 0.2, 1.0))


func _on_set_target_pressed() -> void:
	edit_requested.emit(_slot_id)


func _on_clear_target_pressed() -> void:
	clear_requested.emit(_slot_id)


func _on_unequip_pressed() -> void:
	unequip_requested.emit(_slot_id)
