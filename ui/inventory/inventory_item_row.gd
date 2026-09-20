class_name InventoryItemRow
extends ItemRow
## One carried stack in the inventory panel: the shared ItemRow line plus the actions
## that apply to it (Equip, Eat, Drop, Drop All). Emits intent only; the panel owns the
## Player calls. Call setup_stack() after add_child.

signal equip_pressed()
signal eat_pressed()
signal drop_pressed(count: int)

@onready var _equip_button: Button = %EquipButton
@onready var _eat_button: Button = %EatButton
@onready var _drop_button: Button = %DropButton
@onready var _drop_all_button: Button = %DropAllButton

var _count: int = 0


func _ready() -> void:
	_equip_button.pressed.connect(func() -> void: equip_pressed.emit())
	_eat_button.pressed.connect(func() -> void: eat_pressed.emit())
	_drop_button.pressed.connect(func() -> void: drop_pressed.emit(1))
	_drop_all_button.pressed.connect(func() -> void: drop_pressed.emit(_count))


## Fills the shared line, then shows only the actions that apply. `can_equip` is
## decided by the panel (it knows the player's Equipment); Eat comes from the def.
func setup_stack(def: ItemDef, count: int, can_equip: bool) -> void:
	# 1. Shared Line: Icon, name, count and stack weight from ItemRow.
	setup(def, count)
	_count = count
	# 2. Applicable Actions: Drop and Drop All always; Equip and Eat only when they make sense.
	_equip_button.visible = can_equip
	_eat_button.visible = def.is_food()
