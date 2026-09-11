class_name BedParams
extends FurnitureCapability
## Capability parameters for bed furniture (GDD §6.8).
## Marks this furniture as a colonist rest destination.
## FurnitureLayer registry spawns BedComponent when this is non-null.

## Local offset from furniture origin to the colonist sleep position.
@export var sleep_offset: Vector3 = Vector3.ZERO

## Rest need restored per second (0.0 to 1.0 scale; 1.0 = fully restores in 1s).
@export var rest_rate_per_second: float = 0.15
