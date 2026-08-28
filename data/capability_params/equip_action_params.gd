class_name EquipActionParams
extends Resource
## Base resource for actions that can be triggered when an item is equipped.
## Action definitions describe parameters and provide the execution kernel
## (Strategy pattern) invoked by the equipping actor.

@export var id: String = ""
@export var cooldown_seconds: float = 0.5
@export var use_animation: String = "use"
@export var audio_event: String = ""


## Virtual method overridden by specific action types.
func execute(_actor: Node) -> void:
	pass
