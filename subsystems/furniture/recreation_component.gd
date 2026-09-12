class_name RecreationComponent
extends Node
## Rations colonist access to a recreation object. Attached by FurnitureLayer when
## the parent FurnitureDef carries RecreationParams. Implements the duck-typed
## IOccupiable contract so ColonistBrain skips objects that are already full.
##
## Generalises BedComponent's single reserved_by/occupied_by pair to N slots, which
## is what lets one capability cover both an arcade cabinet (capacity 1) and a
## statue any number of colonists can admire at once (capacity -1).
##
## Group membership comes from FurnitureDef.tags via Furniture._register_tag_groups —
## this component does NOT add the group itself, it only warns when the tag is
## missing, because a def without it is invisible to the recreation need.

const REQUIRED_GROUP: StringName = &"recreation_object"

## Colonists en route, holding a slot but not yet accruing.
var _reserved: Array[Node] = []

## Colonists physically present and accruing the recreation need.
var _active: Array[Node] = []


func _ready() -> void:
	# 1. Authoring Validation: A recreation def missing its tag never enters the
	# need's target_group, so the brain can never find it and the capability is
	# silently inert. Warn at spawn rather than let it fail invisibly at runtime.
	_warn_when_group_tag_missing()


# =================
# Primary Functions
# =================

## Simultaneous users this object supports. -1 means unlimited.
func capacity() -> int:
	var p := params()
	if p == null:
		return 0
	return p.effective_capacity()


## True when `user` may claim a slot, including when it already holds one.
func is_usable_by(user: Node) -> bool:
	if user == null:
		return false
	if holds_slot(user):
		return true
	var cap := capacity()
	if cap < 0:
		return true
	return _held_slot_count() < cap


## Take a slot for a colonist en route. Idempotent for the same colonist.
func reserve(user: Node) -> bool:
	if user == null:
		return false
	if holds_slot(user):
		return true
	if not is_usable_by(user):
		return false
	_reserved.append(user)
	return true


## Drop whatever claim `user` holds. Safe for a user holding nothing.
func release(user: Node) -> void:
	_reserved.erase(user)
	_active.erase(user)


## Promote a reservation to active use once the colonist has arrived. A colonist
## that never reserved (e.g. its reservation was dropped while it walked) is
## admitted only when a slot is still free, so arrival can't overfill the object.
func begin_use(user: Node) -> bool:
	if user == null:
		return false
	if _active.has(user):
		return true
	if not _reserved.has(user):
		if not is_usable_by(user):
			return false
	else:
		_reserved.erase(user)
	_active.append(user)
	return true


## End active use and free the slot.
func end_use(user: Node) -> void:
	release(user)


## Stable index of this user's slot, or -1 when it holds none. Reserved users are
## indexed ahead of active ones so an arriving colonist keeps the same offset it
## walked toward.
func slot_index_of(user: Node) -> int:
	var active_idx := _active.find(user)
	if active_idx >= 0:
		return active_idx
	var reserved_idx := _reserved.find(user)
	if reserved_idx >= 0:
		return _active.size() + reserved_idx
	return -1


## True when `user` currently holds a reserved or active slot.
func holds_slot(user: Node) -> bool:
	return _reserved.has(user) or _active.has(user)


## Global position this user should stand at. Falls back to the furniture origin
## when no offsets are authored — ColonistBrain writes this into the blackboard and
## BTActionNavigateTo ring-searches a walkable cell near it, which reproduces the
## plain "walk up to the furniture" behaviour beds already get.
func use_position_for(user: Node) -> Vector3:
	var furniture := get_parent() as Node3D
	if furniture == null:
		return Vector3.ZERO
	var p := params()
	if p == null or p.use_offsets.is_empty():
		return furniture.global_position

	# 1. Slot Resolution: Map this user onto one authored offset. An unheld user
	# (scoring a target it has not reserved yet) previews the first spot.
	var slot := slot_index_of(user)
	if slot < 0:
		slot = 0
	return furniture.global_transform * p.use_offsets[slot % p.use_offsets.size()]


## Returns the RecreationParams capability resource from the parent furniture def.
func params() -> RecreationParams:
	var furniture := get_parent() as Furniture
	return Furniture.get_capability(furniture, RecreationParams) as RecreationParams


## SaveSystem protocol — persists nothing (occupancy is transient runtime-only,
## same rationale as BedComponent: colonists re-arbitrate on load).
func serialize_state() -> Dictionary:
	return {}


## SaveSystem protocol — restores transient state.
func deserialize_state(_data: Dictionary) -> void:
	pass


# ===================
# Auxiliary Functions
# ===================

func _held_slot_count() -> int:
	## Auxiliary: Counts live claims, pruning colonists freed since they claimed.
	_prune_freed_users()
	return _reserved.size() + _active.size()


func _prune_freed_users() -> void:
	## Auxiliary: Drops claims held by freed nodes so a dead colonist can't
	## permanently occupy a slot (colonists die mid-session during raids).
	_reserved = _reserved.filter(func(u: Node) -> bool: return is_instance_valid(u))
	_active = _active.filter(func(u: Node) -> bool: return is_instance_valid(u))


func _warn_when_group_tag_missing() -> void:
	## Auxiliary: Flags a def carrying RecreationParams but missing the matching tag.
	## Checks def.tags rather than group membership because child _ready runs
	## before the parent's, so Furniture._register_tag_groups has not necessarily
	## fired yet and the group would look absent on a perfectly valid def.
	var furniture := get_parent() as Furniture
	if furniture == null or furniture.def == null:
		return
	if furniture.has_tag(String(REQUIRED_GROUP)):
		return
	push_warning("RecreationComponent: furniture '%s' has RecreationParams but is not in group '%s' — add tags = [\"%s\"] to its FurnitureDef or colonists will never find it." % [
		furniture.def_id,
		REQUIRED_GROUP,
		REQUIRED_GROUP
	])
