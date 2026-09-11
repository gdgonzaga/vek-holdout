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


