class_name Map
extends Node3D
## The MapRoot (docs/ARCHITECTURE.md, Scene Tree Overview). Swapped by
## SceneManager on base <-> POI transitions. Owns:
##   - BlockyGrid (the IBlockGrid owner; sole voxel_tool access point for
##     structures) - VoxelTerrain (voxel_tool blocky terrain)
##   - SmoothGrid (optional; natural terrain — present only when the template
##     stamped it AND MapDef.terrain_gen is set; frees itself otherwise)
##   - Player, ColonistContainer, EnemyContainer, FurnitureContainer,
##     BuildController (added by their own subsystems / SceneManager; map.gd
##     just provides the slots).
##
## map.gd holds no gameplay logic — it is a structural container. The voxel
## map's behavior lives in BlockyGrid / BlockLibrary (and SmoothGrid for
## natural terrain — dual-voxel conversion, docs/TODO.md).

@onready var blocky_grid: BlockyGrid = $BlockyGrid
## Null on maps without natural terrain (get_node_or_null: the node may not
## exist, and even when it does it frees itself unless terrain_gen was set).
@onready var smooth_grid: SmoothGrid = get_node_or_null(^"SmoothGrid")
@onready var colonist_container: Node3D = $ColonistContainer
@onready var enemy_container: Node3D = $EnemyContainer
@onready var furniture_container: Node3D = $FurnitureContainer

## Buildable-block convenience proxy (most callers want the grid, not the map).
func get_blocky_grid() -> BlockyGrid:
	return blocky_grid

## The natural-terrain grid, or null when this map has no smooth terrain.
## Callers must null-check; terrain-less maps are the default, not the exception.
func get_smooth_grid() -> SmoothGrid:
	return smooth_grid

func get_blocky_terrain() -> VoxelTerrain:
	return blocky_grid.get_terrain()

## Parent Node3D for free-standing furniture placed at runtime (build subsystem).
func get_furniture_container() -> Node3D:
	return furniture_container

## Parent Node3D for colonist entities spawned by Colony at map load.
func get_colonist_container() -> Node3D:
	return colonist_container
