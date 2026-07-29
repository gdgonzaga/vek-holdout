class_name World
extends Node3D
## The WorldRoot (docs/ARCHITECTURE.md, Scene Tree Overview). Swapped by
## SceneManager on base <-> POI transitions. Owns:
##   - VoxelGrid  (the IBlockGrid owner; sole voxel_tool access point)
##     - VoxelTerrain (voxel_tool blocky terrain)
##   - Player, ColonistContainer, EnemyContainer, FurnitureContainer,
##     BuildController (added by their own subsystems / SceneManager; world.gd
##     just provides the slots).
##
## world.gd holds no gameplay logic — it is a structural container. The voxel
## world's behavior lives in VoxelGrid / BlockLibrary.

@onready var voxel_grid: VoxelGrid = $VoxelGrid
@onready var colonist_container: Node3D = $ColonistContainer
@onready var enemy_container: Node3D = $EnemyContainer
@onready var furniture_container: Node3D = $FurnitureContainer

## Buildable-block convenience proxy (most callers want the grid, not the world).
func get_grid() -> VoxelGrid:
	return voxel_grid

func get_terrain() -> VoxelTerrain:
	return voxel_grid.get_terrain()

## Parent Node3D for free-standing furniture placed at runtime (build subsystem).
func get_furniture_container() -> Node3D:
	return furniture_container
