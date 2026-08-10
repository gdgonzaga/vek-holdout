class_name StorageInventory
extends Inventory
## Per-instance contents of a storage container (crates, chests). Attached as a
## child Node of a Furniture, mirroring how CharacterInventory sits under the
## Player. Capacity is read from the furniture's `def.storage_params` (a
## StorageParams resource on the FurnitureDef) at `_ready`.
##
## Weight-only: the base Inventory enforces the weight budget via `capacity`,
## so this subclass does not override add/can_add. Player<->crate transfers use
## the inherited `transfer_to`, which already interoperates between any two
## Inventory instances. See docs/architecture/inventory.md.

func _ready() -> void:
	_apply_storage_params()


## Reads capacity from the parent furniture's def.storage_params. Extracted from
## _ready so it can be invoked directly in tests without a scene tree (a child
## only runs _ready once it enters the tree, which the unit harness can't do).
func _apply_storage_params() -> void:
	var furniture := get_parent() as Furniture
	if furniture == null or furniture.def == null:
		return
	var params := furniture.def.storage_params as StorageParams
	if params != null:
		capacity = params.capacity
