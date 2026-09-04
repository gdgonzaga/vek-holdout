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


## Returns true if the storage allows this item based on StorageParams (Hard Gate).
func is_item_allowed(item_id: String) -> bool:
	if _storage_params == null:
		return true
	if _storage_params.allowed_item_ids.is_empty() and _storage_params.allowed_tags.is_empty():
		return true
	if _storage_params.allowed_item_ids.has(item_id):
		return true
	if not _storage_params.allowed_tags.is_empty():
		var def := _get_def(item_id)
		if def != null:
			for tag in def.tags:
				if _storage_params.allowed_tags.has(tag):
					return true
	return false
