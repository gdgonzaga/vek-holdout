class_name BedParams
extends FurnitureCapability
## Capability parameters for bed furniture (GDD §6.8).
## Marks this furniture as a colonist rest destination.
## FurnitureLayer registry spawns BedComponent when this is non-null.

## Local offset from furniture origin to the colonist sleep position.
@export var sleep_offset: Vector3 = Vector3.ZERO

## Rest need restored per in-game hour.
@export var rest_per_game_hour: float = 11.25

@export var min_session_game_hours: float = 0.05
@export var max_session_game_hours: float = 0.25
@export var use_animation: StringName = &"Interact"

func session_ceiling_game_hours() -> float:
	return maxf(min_session_game_hours, max_session_game_hours)
