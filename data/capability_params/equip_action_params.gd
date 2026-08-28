class_name EquipActionParams
extends Resource
## Base resource for actions that can be triggered when an item is equipped.
## Action definitions are data-only and describe parameters such as cooldowns,
## animation triggers, and audio cues. Logic is handled by the equipped character
## controller or action execution system.

@export var id: String = ""
@export var cooldown_seconds: float = 0.5
@export var use_animation: String = "use"
@export var audio_event: String = ""
