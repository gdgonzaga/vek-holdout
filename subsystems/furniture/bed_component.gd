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


# --- IOccupiable contract ----------------------------------------------------
# Thin adapters over reserve/occupy/vacate above so ColonistBrain can ration beds
# through the same duck-typed surface it uses for RecreationComponent. Before
# these existed the reserve/occupy API had no callers at all and every colonist
# pathed to the same nearest bed. See subsystems/furniture/i_occupiable.gd.

## True when this bed is free, or already claimed by `user` itself. The
## self-claim case matters because the brain re-scores its own current target
## every cycle and would otherwise abandon the bed it just reserved.
func is_usable_by(user: Node) -> bool:
	if user == null:
		return false
	if reserved_by == user or occupied_by == user:
		return true
	return is_available()


## Drop whatever claim `user` holds, reserved or occupied.
func release(user: Node) -> void:
	var colonist := user as Colonist
	if colonist == null:
		return
	release_reservation(colonist)
	vacate(colonist)


## Promote a reservation to active occupancy on arrival.
func begin_use(user: Node) -> bool:
	var colonist := user as Colonist
	if colonist == null:
		return false
	if occupied_by == colonist:
		return true
	if occupied_by != null:
		return false
	occupy(colonist)
	return true


## End occupancy and free the bed.
func end_use(user: Node) -> void:
	release(user)


## Global position the sleeping colonist should occupy. The authored
## BedParams.sleep_offset is local to the bed, so the furniture transform applies
## the placement yaw for free.
func use_position_for(_user: Node) -> Vector3:
	var furniture := get_parent() as Node3D
	if furniture == null:
		return Vector3.ZERO
	var p := params()
	if p == null:
		return furniture.global_position
	return furniture.global_transform * p.sleep_offset


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
