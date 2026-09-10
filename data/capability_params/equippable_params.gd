class_name EquippableParams
extends Resource
## Capability parameters for equippable items (GDD §7). A nullable sub-resource
## on ItemDef, following the composition pattern documented in AGENTS.md.
## An item with this capability populated can be equipped into character slots.
##
## Slot routing is tag-based: which slot an item fits is determined by the
## tags on ItemDef (e.g. "tool"/"weapon" → main_hand/holster). This resource
## owns only animation and action parameters. ARCH: equipment.md.

@export var stance_animation: StringName = &"idle"
@export var use_animation: StringName = &"use"
@export var primary_action: EquipActionParams = null
@export var secondary_action: EquipActionParams = null
