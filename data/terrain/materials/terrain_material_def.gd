extends Resource
class_name TerrainMaterialDef
## Identity/stats for a placeable natural material (dirt, rock, ...). One of the
## mirrored BlockyGrid/SmoothGrid vocabularies (docs/TODO.md D1/D2).
##
## F8 verdict: VoxelMesherTransvoxel exposes NO material API in this build —
## voxel values are pure SDF density and the terrain has ONE fixed visual
## appearance. So unlike BlockDef there is no mesh/material here: the def
## carries identity + gameplay stats only. `hardness` is the relative mining
## cost multiplier for the Phase 5 dig action.

@export var id: String
@export var display_name: String

## Relative dig-effort multiplier (1 = baseline dirt). Higher = more swings.
@export var hardness: int = 1

## What one completed dig of this material drops into the digger's inventory
## (the HarvestParams.yields shape). v1 ceiling: the smooth terrain has no
## per-position material channel (F8), so every dig reports the map's default
## material and yields its drops — authoring per-material yields is ready for
## the day real material representation lands.
@export var yields: Array[ItemAmount] = []
