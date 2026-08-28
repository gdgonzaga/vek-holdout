class_name EquippableParams
extends Resource
## Capability parameters for equippable items (GDD §7). A nullable sub-resource
## on ItemDef, following the composition pattern documented in AGENTS.md.
## An item with this capability populated can be equipped into character slots.

enum SlotType {
	MAIN_HAND,
	OFF_HAND,
	TWO_HAND,
	BODY,
	HEAD,
}

@export var slot_type: SlotType = SlotType.MAIN_HAND
@export var mesh_scene: PackedScene = null
@export var animation_stance: String = "default"
@export var primary_action: EquipActionParams = null
@export var secondary_action: EquipActionParams = null
