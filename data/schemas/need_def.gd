extends Resource
class_name NeedDef
## Data-driven definition for a colonist need (hunger, rest, recreation).

@export var id: StringName = &"hunger"
@export var decay_per_game_hour: float = 3.75
@export var response_curve: Curve          ## Visual Inspector Curve (Deficit 0..1 -> Urgency 0..1)
@export var emergency_threshold: float = 0.10
@export var goal_name: StringName = &"eat"
@export var target_group: StringName = &"storage_crate"

## Depletion consequences when need level reaches 0.0 (e.g. starvation, exhaustion)
@export var depletion_damage_interval: float = 0.0  ## Seconds between periodic damage ticks (0.0 = no damage)
@export var depletion_damage: int = 0               ## Hit points deducted per depletion damage tick
@export var depletion_speed_mult: float = 1.0       ## Locomotion speed multiplier when depleted
@export var depletion_stamina_mult: float = 1.0     ## Stamina recovery multiplier when depleted
