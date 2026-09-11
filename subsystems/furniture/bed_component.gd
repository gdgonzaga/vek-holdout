class_name BedComponent
extends Node
## Manages occupancy state for a colonist bed (GDD §6.8). Attached by FurnitureLayer
## when the parent FurnitureDef carries BedParams. Exposes reserve/occupy/vacate
## so ColonistBrain can claim a specific bed before navigating to it, preventing
## multiple colonists from pathing to the same bed.
##
## The Furniture node is already in group &"bed" via tags = ["bed"] on FurnitureDef
## (Furniture._register_tag_groups handles this) — BedComponent does NOT re-add it.

## Colonist navigating toward this bed (transient reservation).
var reserved_by: Colonist = null

## Colonist currently asleep in this bed.
var occupied_by: Colonist = null


## Returns true when the bed is neither reserved by an en-route colonist nor occupied.
func is_available() -> bool:
	return reserved_by == null and occupied_by == null


## Reserve this bed for a colonist en route. Idempotent for the same colonist.
## Returns false if already reserved by another colonist or currently occupied.
func reserve(colonist: Colonist) -> bool:
	if occupied_by != null:
		return false
	if reserved_by != null and reserved_by != colonist:
		return false
	reserved_by = colonist
	return true


## Release transient reservation if held by colonist.
func release_reservation(colonist: Colonist) -> void:
	if reserved_by == colonist:
		reserved_by = null


## Transition from reserved to actively occupied when colonist arrives.
func occupy(colonist: Colonist) -> void:
	occupied_by = colonist
	reserved_by = null


## Release active occupancy when colonist wakes up or leaves.
func vacate(colonist: Colonist) -> void:
	if occupied_by == colonist:
		occupied_by = null


## Returns the BedParams capability resource from the parent furniture definition.
func params() -> BedParams:
	var furniture := get_parent() as Furniture
	return Furniture.get_capability(furniture, BedParams) as BedParams


## SaveSystem protocol — persists nothing (occupancy is transient runtime-only).
func serialize_state() -> Dictionary:
	return {}


## SaveSystem protocol — restores transient state.
func deserialize_state(_data: Dictionary) -> void:
	pass
