class_name CombatActionParams
extends EquipActionParams
## Capability parameters for combat actions (e.g. guns, melee weapons).
## Defines hitscan/projectile properties, damage, range, and spread.

@export var damage: float = 10.0
@export var range_meters: float = 50.0
@export var is_hitscan: bool = true
@export var projectile_scene: PackedScene = null
@export var spread_angle_degrees: float = 0.0
@export var ammo_item_id: String = ""
