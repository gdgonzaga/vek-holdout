class_name StorageParams
extends Resource
## Capability parameters for storage furniture (GDD §7.11). A nullable
## sub-resource on FurnitureDef, following the composition pattern documented
## in docs/architecture/data-schemas.md "FurnitureDef capability parameters"
## — sibling to TestParams / ItemDispenserParams. A placed furniture reads it
## via `def.storage_params` (null if absent); StorageInventory copies
## `capacity` into the base Inventory.capacity in `_ready`.
##
## Storage item filters (Hard Gate):
## - `allowed_item_ids`: Whitelist of specific item IDs (e.g. ["scrap_ammo"]).
## - `allowed_tags`: Whitelist of item tags (e.g. ["ammo", "food"]).
## If both are empty, the storage accepts any item within its weight capacity.

@export var capacity: float = 100.0

## Specific item IDs that this storage is restricted to hold.
## If empty and allowed_tags is also empty, the storage is unrestricted.
@export var allowed_item_ids: Array[String] = []

## Specific item tags that this storage is restricted to hold.
## If empty and allowed_item_ids is also empty, the storage is unrestricted.
@export var allowed_tags: Array[String] = []


## Returns true if this definition accepts `item_id`.
func is_item_allowed(item_id: String) -> bool:
	if allowed_item_ids.is_empty() and allowed_tags.is_empty():
		return true
	if allowed_item_ids.has(item_id):
		return true
	if not allowed_tags.is_empty() and ItemDB != null:
		var def := ItemDB.get_def(item_id)
		if def != null:
			for tag in def.tags:
				if allowed_tags.has(tag):
					return true
	return false
