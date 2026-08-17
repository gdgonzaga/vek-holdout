extends BuildableDef
class_name BlockDef
## Voxel-grid buildable (GDD §7.2). A BuildableDef exposed to the blocky voxel
## world — what BlockLibrary feeds into VoxelBlockyLibrary and BlockyGrid places.
## Schema: docs/ARCHITECTURE.md "data/blocks/<type>.tres".
##
## Inherits id/display_name/hp/mesh/material_cost/unlocked_by_default from
## BuildableDef. Adds only `is_terrain` to mark the non-buildable world ground.

## True for the non-buildable world ground (VoxelGeneratorFlat output). Skips
## build-cost validation and is not a valid build target.
@export var is_terrain: bool = false
