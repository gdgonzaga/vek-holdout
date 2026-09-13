class_name StorageInventory
extends Inventory
## Per-instance contents of a storage container (crates, chests). Attached as a
## child Node of a Furniture, mirroring how CharacterInventory sits under the
## Player. Capacity and item filter restrictions are read from the furniture's
## `def.storage_params` (a StorageParams resource on the FurnitureDef) at `_ready`.
##
## Storage filtering: restricts accepted items based on `StorageParams.allowed_item_ids`
## and `StorageParams.allowed_tags`. Player<->crate transfers use the inherited
## `transfer_to`, which interoperates between any two Inventory instances.

var _storage_params: StorageParams = null

## Specific item IDs that this storage instance is restricted to hold.
## If empty and allowed_tags is also empty, the storage is unrestricted.
var allowed_item_ids: Array[String] = []

## Specific item tags that this storage instance is restricted to hold.
## If empty and allowed_item_ids is also empty, the storage is unrestricted.
var allowed_tags: Array[String] = []

## Storage priority (1 to 5). Higher priority crates are preferred for hauling deposits.
var priority: int = 3


func _ready() -> void:
	_apply_storage_params()


## Reads capacity and filter constraints from the parent furniture's def.storage_params.
## Extracted from _ready so it can be invoked directly in tests without a scene tree.
func _apply_storage_params() -> void:
	var furniture := get_parent() as Furniture
	if furniture == null or furniture.def == null:
		return
	var params := furniture.def.storage_params as StorageParams
	if params != null:
		_storage_params = params
		capacity = params.capacity
		priority = params.priority
		if allowed_item_ids.is_empty() and not params.allowed_item_ids.is_empty():
			allowed_item_ids = params.allowed_item_ids.duplicate()
		if allowed_tags.is_empty() and not params.allowed_tags.is_empty():
			allowed_tags = params.allowed_tags.duplicate()


## Returns true if the storage allows this item based on instance filters (Hard Gate).
func is_item_allowed(item_id: String) -> bool:
	if allowed_item_ids.is_empty() and allowed_tags.is_empty():
		return true
	if allowed_item_ids.has(item_id):
		return true
	if not allowed_tags.is_empty():
		var def := _get_def(item_id)
		if def != null:
			for tag in def.tags:
				if allowed_tags.has(tag):
					return true
	return false


## Sets the storage container priority (clamped to 1..5).
func set_priority(p: int) -> void:
	var new_priority := clampi(p, 1, 5)
	if priority != new_priority:
		priority = new_priority
		inventory_changed.emit()


## Adds or removes an item ID from the whitelist.
func set_item_allowed(item_id: String, allowed: bool) -> void:
	if allowed:
		if not allowed_item_ids.has(item_id):
			allowed_item_ids.append(item_id)
			inventory_changed.emit()
	else:
		if allowed_item_ids.has(item_id):
			allowed_item_ids.erase(item_id)
			inventory_changed.emit()


## Clears all whitelisted item IDs (making storage accept any item if tags are also empty).
func clear_allowed_items() -> void:
	if not allowed_item_ids.is_empty():
		allowed_item_ids.clear()
		inventory_changed.emit()


# --- SaveSystem contract -----------------------------------------------------

## Snapshot item stacks and instance-level item filter whitelist.
func serialize() -> Dictionary:
	var data := super.serialize()
	data["priority"] = priority
	if not allowed_item_ids.is_empty():
		data["allowed_item_ids"] = allowed_item_ids.duplicate()
	if not allowed_tags.is_empty():
		data["allowed_tags"] = allowed_tags.duplicate()
	return data


## Restore item stacks and instance-level item filter whitelist.
func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	priority = int(data.get("priority", priority))
	allowed_item_ids.clear()
	var saved_ids: Array = data.get("allowed_item_ids", [])
	for id in saved_ids:
		allowed_item_ids.append(str(id))
	allowed_tags.clear()
	var saved_tags: Array = data.get("allowed_tags", [])
	for tag in saved_tags:
		allowed_tags.append(str(tag))


## ICapabilityComponent: snapshot per-instance storage state.
func serialize_state() -> Dictionary:
	return serialize()


## ICapabilityComponent: restore per-instance storage state.
func deserialize_state(data: Dictionary) -> void:
	deserialize(data)


# --- Haul reservations --------------------------------------------------------
# Lets an in-flight haul job "hold" the capacity it intends to deliver into, so
# repeated is_available_for() checks on that SAME job don't need to re-derive
# availability from a live scan that other concurrent haulers are also
# mutating (the source of the claim/drop churn documented in ai-brain.md
# "Job Slot Capacity Self-Rejection" — this is the storage-capacity shape of
# the same failure class). Reservations self-expire so a claim_key that never
# explicitly releases (a missed unassign/abort path) can't leak capacity
# forever — mirrors ColonistBrain's food-source blacklist TTL pattern.

const RESERVATION_TTL_MSEC: int = 30000

## claim_key (Variant, typically the Job/JobInstance itself) -> Dictionary
## {"item_id": String, "count": int, "expires_at_msec": int}.
var _reservations: Dictionary = {}


## Reserves capacity for count of item_id on behalf of claim_key, or renews an
## existing reservation for that same key. Returns true if capacity was (or
## already is) available and the reservation is now recorded.
func reserve_capacity(claim_key: Variant, item_id: String, count: int) -> bool:
	_purge_expired_reservations()
	if not _has_capacity_for(item_id, count, claim_key):
		return false
	_reservations[claim_key] = {
		"item_id": item_id,
		"count": count,
		"expires_at_msec": Time.get_ticks_msec() + RESERVATION_TTL_MSEC,
	}
	return true


## True if claim_key currently holds a live (unexpired) reservation here.
func has_reservation(claim_key: Variant) -> bool:
	_purge_expired_reservations()
	return _reservations.has(claim_key)


## Releases a previously held reservation (delivered, aborted, or unassigned).
## No-op if claim_key never reserved anything here.
func release_reservation(claim_key: Variant) -> void:
	_reservations.erase(claim_key)


## Weight-aware capacity check that also counts every OTHER claim_key's live
## reservations, so two concurrent haulers can't both be told the same last
## unit of room is free. Pass the querying job as exclude_claim_key so a job
## re-checking its own already-reserved crate isn't blocked by itself.
func can_add_reserving(item_id: String, count: int, exclude_claim_key: Variant = null) -> bool:
	_purge_expired_reservations()
	return _has_capacity_for(item_id, count, exclude_claim_key)


func _has_capacity_for(item_id: String, count: int, exclude_claim_key: Variant) -> bool:
	## Auxiliary: Same weight-budget math as can_add(), plus every live
	## reservation's weight except the caller's own.
	var def := _get_def(item_id)
	if def == null or not is_item_allowed(item_id):
		return false
	var reserved_weight: float = _reserved_weight_excluding(exclude_claim_key)
	return current_weight() + reserved_weight + (count * def.weight) <= capacity


func _reserved_weight_excluding(exclude_claim_key: Variant) -> float:
	## Auxiliary: Sums the weight of every live reservation except exclude_claim_key's own.
	var total := 0.0
	for key in _reservations:
		if key == exclude_claim_key:
			continue
		var r: Dictionary = _reservations[key]
		var r_def := _get_def(str(r.get("item_id", "")))
		if r_def != null:
			total += float(r.get("count", 0)) * r_def.weight
	return total


func _purge_expired_reservations() -> void:
	## Auxiliary: Drops reservations past their TTL — the leak-proofing safety net.
	if _reservations.is_empty():
		return
	var now := Time.get_ticks_msec()
	var expired: Array = []
	for key in _reservations:
		if now >= int(_reservations[key].get("expires_at_msec", 0)):
			expired.append(key)
	for key in expired:
		_reservations.erase(key)


