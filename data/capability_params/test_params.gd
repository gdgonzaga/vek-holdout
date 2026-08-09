extends Resource
class_name TestParams
## Seed of the composition pattern for capability-specific furniture parameters
## (GDD §7.9 crafting stations). See docs/architecture/data-schemas.md
## "FurnitureDef capability parameters" for the design record.
##
## Problem this exists to solve: a Workbench and a Workbench-T2 differ only in
## craft speed and max recipe tier. Rather than (a) two CraftAction subclasses
## per station, (b) a `CrafterDef extends FurnitureDef` subclass that dead-ends
## when a station needs two capabilities (craft + store), or (c) a free-form
## `params: Dictionary` that loses typing/editor ergonomics — capability params
## live on small, nullable sub-resources referenced from FurnitureDef.
##
## This is a throwaway placeholder so the pattern has a real home in the tree
## and FurnitureDef. It is NOT a real capability; replace with real capability
## params (CraftingParams, StorageParams, etc.) as those subsystems land. A
## placed furniture reads it via `def.test_params` (null if absent).

@export var speed: float = 1.0
@export var tier: int = 1
