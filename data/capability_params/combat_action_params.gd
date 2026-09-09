class_name CombatActionParams
extends EquipActionParams
## Base capability parameters for combat actions (e.g. melee weapons, firearms).
## Defines common combat properties such as damage and effective range.

@export var damage: float = 10.0
@export var range_meters: float = 2.0


func execute(_actor: Node) -> void:
	pass
