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

## The natural-terrain VoxelTerrain, or null when this map has no smooth
## terrain. A SmoothGrid that reached _ready without terrain_gen queues itself
## for deletion — the terrain_gen guard catches it even before the free lands.
func get_smooth_terrain() -> VoxelTerrain:
	var grid := get_smooth_grid()
	if grid == null or not is_instance_valid(grid) or grid.terrain_gen == null:
		return null
	return grid.get_terrain()

## Sqlite dbs that persist this map's voxels (dual-voxel Phase 4): blocky
## always, terrain.sqlite only on maps with smooth terrain. `map.sqlite` keeps
## its pre-conversion name — renaming would orphan every existing map and save.
const BLOCKY_DB := "map.sqlite"
const SMOOTH_DB := "terrain.sqlite"

## The persisted db filenames, blocky first. A function rather than a const
## because typed array literals are not constant expressions in GDScript.
static func stream_dbs() -> Array[String]:
	return [BLOCKY_DB, SMOOTH_DB]

## The terrains that persist via sqlite streams, paired with their db filename.
## One source of truth for SceneManager's runtime redirect and SaveSystem's
## park flush / slot snapshot (Phase 4: one shared pairing, not per-site copies
## that can drift on which grids exist).
func persisted_streams() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var blocky := get_blocky_terrain()
	if blocky != null:
		out.append({"terrain": blocky, "db": BLOCKY_DB})
	var smooth := get_smooth_terrain()
	if smooth != null:
		out.append({"terrain": smooth, "db": SMOOTH_DB})
	return out

## Flush each stream's edited blocks to its sqlite db — INV-3's voxel half for
## BOTH grids (SaveSystem parks via this). VoxelStreamSQLite.flush() blocks
## until the async save tasks land: without it, SaveSystem's slot snapshot can
## copy a db mid-transaction (torn file — the reload then fails every
## begin_transaction) and load_game's cache wipe races in-flight writes.
func flush_voxel_streams() -> void:
	for pair: Dictionary in persisted_streams():
		var terrain: VoxelTerrain = pair["terrain"]
		if terrain.stream is VoxelStreamSQLite:
			terrain.save_modified_blocks()
			(terrain.stream as VoxelStreamSQLite).flush()

## Ray origin height / length for the combined ground query: far above anything
## authorable, so one straight-down ray covers the whole column.
const GROUND_RAY_FROM_Y := 512.0
const GROUND_RAY_LENGTH := 1024.0

## Height of the highest TERRAIN surface at column (x, z): one downward ray
## masked to TerrainBlocky|TerrainSmooth, so hills and the blocky plate compete
## and the first hit from above wins (dual-voxel Phase 3 spawns). Furniture
## statics, character bodies, and Build interaction bodies never answer — a
## spawn marker under a built floor still resolves to the terrain. NAN when
## neither terrain reaches the column; callers keep their authored Y then.
## Per-grid height_at stays layer-specific — this query is for placement, not
## walkability.
func ground_height_at(x: float, z: float) -> float:
	var space := blocky_grid.get_terrain().get_world_3d().direct_space_state
	var from := Vector3(x, GROUND_RAY_FROM_Y, z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * GROUND_RAY_LENGTH)
	# BlockyGrid.TERRAIN_LAYER doubles as its bit value (layer 2 = bit 2);
	# SmoothGrid exposes the explicit VALUE constant. Both terrains live in
	# this map's physics world.
	query.collision_mask = BlockyGrid.TERRAIN_LAYER | SmoothGrid.TERRAIN_LAYER_VALUE
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return NAN
	return hit.position.y

## Parent Node3D for free-standing furniture placed at runtime (build subsystem).
func get_furniture_container() -> Node3D:
	return furniture_container

## Parent Node3D for colonist entities spawned by Colony at map load.
func get_colonist_container() -> Node3D:
	return colonist_container
