extends Resource
class_name NeedDef
## Data-driven definition for a colonist need (hunger, rest, recreation).

@export var id: StringName = &"hunger"
@export var decay_per_second: float = 0.05
@export var response_curve: Curve          ## Visual Inspector Curve (Deficit 0..1 -> Urgency 0..1)
@export var emergency_threshold: float = 0.10
@export var goal_name: StringName = &"eat"
@export var target_group: StringName = &"storage_crate"
