class_name EquipmentSlotRow
extends Button
## One-line, whole-row selectable slot tile in the Gear sub-tab: slot name, equipped item,
## the pending target ("-> Name") and a status pip. There are deliberately no per-row buttons
## (the picker pane owns Unequip / Clear), so rows never change width when state changes.
## Call setup() after add_child.

signal selected(slot_id: String)

const COLOR_EQUIPPED: Color = Color(0.9, 0.9, 0.9, 1.0)
const COLOR_EMPTY: Color = Color(0.55, 0.55, 0.55, 1.0)
const STATUS_PIP: String = "●"

var _slot_id: String = ""
var _colonist: Colonist = null

@onready var _slot_label: Label = %SlotLabel
@onready var _equipped_label: Label = %EquippedLabel
@onready var _target_label: Label = %TargetLabel
@onready var _status_pip: Label = %StatusPip

# =================
# Primary Functions
# =================

func _ready() -> void:
	pressed.connect(_on_pressed)


## Initializes the row with its slot and colonist and renders it.
func setup(slot_id: String, colonist: Colonist) -> void:
	_slot_id = slot_id
	_colonist = colonist

	# 1. Display Refresh: fill slot name, equipped item and target status for the first time.
	refresh()


## Re-renders equipped item, target text and status pip from current colonist state.
func refresh() -> void:
	if _slot_id.is_empty() or _colonist == null or not is_instance_valid(_colonist):
		return
	if not is_node_ready():
		return
	_slot_label.text = GearText.slot_display_name(_slot_id)

	# 1. Equipped Item: what the slot holds right now, muted when empty.
	_update_equipped_display()

	# 2. Target Status: why the target is met or pending, shown as target text, pip and tooltip.
	_update_target_display()


## Marks this row as the slot the picker pane is editing, without emitting signals.
func set_selected(is_selected: bool) -> void:
	set_pressed_no_signal(is_selected)


func get_slot_id() -> String:
	return _slot_id

# ===================
# Auxiliary Functions
# ===================

func _update_equipped_display() -> void:
	## Auxiliary: Shows the equipped item's name, or a muted "(empty)".
	var item: ItemDef = _colonist.equipment.get_item(_slot_id) if _colonist.equipment != null else null
	if item == null:
		_equipped_label.text = "(empty)"
		_equipped_label.add_theme_color_override("font_color", COLOR_EMPTY)
		return
	_equipped_label.text = item.get_display_name()
	_equipped_label.add_theme_color_override("font_color", COLOR_EQUIPPED)


func _update_target_display() -> void:
	## Auxiliary: Resolves the slot's status and renders it as target text, pip color and tooltip.
	var result: GearStatus.Result = GearStatus.evaluate(
			_colonist, _slot_id, Colony.storage_registry, Colony.job_board)
	tooltip_text = result.text
	_status_pip.text = "" if result.state == GearStatus.State.NO_TARGET else STATUS_PIP
	_status_pip.add_theme_color_override("font_color", result.color)

	# 1. Target Text: only a pending target is spelled out; a met target is already the equipped item.
	_target_label.text = _pending_target_text() if result.is_pending() else ""
	_target_label.add_theme_color_override("font_color", result.color)


func _pending_target_text() -> String:
	## Auxiliary: "-> Name" for the slot's target, falling back to the raw id if its def is gone.
	var target_id: String = _colonist.equipment.get_desired_item(_slot_id)
	return "→ %s" % ItemDB.get_display_name(target_id)


func _on_pressed() -> void:
	selected.emit(_slot_id)
