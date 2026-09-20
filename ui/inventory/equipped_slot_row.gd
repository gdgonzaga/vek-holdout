class_name EquippedSlotRow
extends HBoxContainer
## One occupied equipment slot in the inventory panel's Equipped strip: slot name,
## item icon and name, and an Unequip button. Emits intent only; the panel owns
## the Player call. Call setup() after add_child.

signal unequip_pressed(slot_id: String)

@onready var _slot_label: Label = %SlotLabel
@onready var _icon: TextureRect = %Icon
@onready var _name_label: Label = %NameLabel
@onready var _unequip_button: Button = %UnequipButton

var _slot_id: String = ""


func _ready() -> void:
	_unequip_button.pressed.connect(_on_unequip_button_pressed)


func setup(slot_id: String, def: ItemDef) -> void:
	_slot_id = slot_id
	_slot_label.text = GearText.slot_display_name(slot_id)
	_icon.texture = def.icon
	_name_label.text = def.get_display_name()


func _on_unequip_button_pressed() -> void:
	unequip_pressed.emit(_slot_id)
