class_name ICapabilityComponent
extends RefCounted
## Duck-typed contract for capability component nodes that carry save state.
## Components implementing this are discovered automatically by Furniture.serialize
## and Furniture.deserialize via has_method() checks — do NOT extend this script.


## Return a Dictionary snapshot of this component's per-instance state.
## Keys must be stable across game versions (treat as a save format).
func serialize_state() -> Dictionary:
	return {}


## Restore per-instance state from a Dictionary produced by serialize_state.
func deserialize_state(_data: Dictionary) -> void:
	pass
