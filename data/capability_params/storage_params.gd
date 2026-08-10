class_name StorageParams
extends Resource
## Capability parameters for storage furniture (GDD §7.11). A nullable
## sub-resource on FurnitureDef, following the composition pattern documented
## in docs/architecture/data-schemas.md "FurnitureDef capability parameters"
## — sibling to TestParams / ItemDispenserParams. A placed furniture reads it
## via `def.storage_params` (null if absent); StorageInventory copies
## `capacity` into the base Inventory.capacity in `_ready`.
##
## Weight-only: the base Inventory already enforces a weight budget, so
## StorageInventory does not override add/can_add. A future stack limit
## (e.g. GDD's "32 stacks per crate") would add a field here and an override
## in StorageInventory.

@export var capacity: float = 100.0
