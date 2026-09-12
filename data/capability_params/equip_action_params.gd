class_name EquipActionParams
extends Resource
## Base resource for actions that can be triggered when an item is equipped.
## Action definitions describe parameters and provide the execution kernel
## (Strategy pattern) invoked by the equipping actor.

@export var id: String = ""
@export var cooldown_seconds: float = 0.5
@export var audio_event: String = ""


## Virtual method overridden by specific action types.
func execute(_actor: Node) -> void:
	pass


## How long the actor is locked out before this action can be triggered
## again. Base actions have no windup/active phases, so this is just
## cooldown_seconds; MeleeActionParams overrides it to also cover its own
## windup+active window (otherwise a short cooldown_seconds can expire
## mid-swing, letting callers re-trigger overlapping executions).
func get_lockout_duration() -> float:
	return cooldown_seconds
