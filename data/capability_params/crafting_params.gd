class_name CraftingParams
extends Resource
## Capability parameters for crafting furniture (GDD §7.9): the recipe list
## offered at this station. A nullable sub-resource on FurnitureDef, following
## the composition pattern documented in docs/architecture/data-schemas.md
## "FurnitureDef capability parameters" — sibling to StorageParams /
## ItemDispenserParams / TestParams. A placed furniture reads it via
## `def.crafting_params` (null if absent); FurnitureLayer attaches a
## CraftingStation child only when it is set, and the station copies `recipes`
## in `_ready` (the StorageInventory pattern).

@export var recipes: Array[RecipeDef] = []
