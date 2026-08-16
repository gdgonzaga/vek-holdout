class_name HarvestParams
extends Resource
## Capability parameters for harvestable furniture (GDD §6.10, ARCH "Harvesting").
## A nullable sub-resource on FurnitureDef, following the composition pattern
## documented in docs/architecture/data-schemas.md "FurnitureDef capability parameters"
## — sibling to CraftingParams / StorageParams.
## A placed furniture reads it via `def.harvest_params`; FurnitureLayer attaches
## a Harvestable child component when present.

@export var yields: Array[ItemAmount] = []
@export var work_time: float = 4.0
@export var respawn_time: float = 0.0
@export var required_tool_tag: String = ""
