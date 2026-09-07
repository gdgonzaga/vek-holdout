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

## Playable volume bounding box. Prevents entity egress and out-of-bounds queries.
var world_bounds: AABB = AABB(Vector3(-96.0, -48.0, -96.0), Vector3(192.0, 64.0, 192.0))
var _boundaries_root: Node3D = null


func _ready() -> void:
	if blocky_grid != null:
		blocky_grid.set_world_bounds(world_bounds)
	if smooth_grid != null:
		smooth_grid.set_world_bounds(world_bounds)
	if _boundaries_root == null:
		# Physics Boundary: Initializing physical barriers upon entering the active scene tree.
		setup_boundary_colliders()


func get_world_bounds() -> AABB:
	return world_bounds


func set_world_bounds(bounds: AABB) -> void:
	world_bounds = bounds
	var bg := blocky_grid if blocky_grid != null else get_node_or_null(^"BlockyGrid") as BlockyGrid
	if bg != null:
		bg.set_world_bounds(bounds)
	var sg := smooth_grid if smooth_grid != null else get_node_or_null(^"SmoothGrid") as SmoothGrid
	if sg != null:
		sg.set_world_bounds(bounds)
	if is_inside_tree():
		# Physics Boundary: Rebuilding physical barriers to prevent entity escape beyond world limits.
		setup_boundary_colliders()


func setup_boundary_colliders() -> void:
	if _boundaries_root != null and is_instance_valid(_boundaries_root):
		if _boundaries_root.get_parent() == self:
			remove_child(_boundaries_root)
		_boundaries_root.queue_free()
	_boundaries_root = Node3D.new()
	_boundaries_root.name = "MapBoundaries"
	add_child(_boundaries_root)

	# 1. Floor Barrier: Creating the bottom boundary preventing falling into the void.
	_create_boundary_wall(_get_bottom_wall_pos(world_bounds), _get_bottom_wall_size(world_bounds), "FloorBarrier")

	# 2. Lateral Barriers: Constructing the four enclosing perimeter walls.
	_build_lateral_walls(world_bounds)


func _build_lateral_walls(bounds: AABB) -> void:
	## Auxiliary: Builds the 4 perimeter walls enclosing the lateral bounds.
	const THICKNESS := 16.0
	const INWARD_MARGIN := 1.0
	const EXTRA_HEIGHT := 128.0
	var min_p := bounds.position
	var sz := bounds.size
	var max_p := bounds.position + bounds.size
	var wall_h := sz.y + EXTRA_HEIGHT
	var wall_center_y := min_p.y + wall_h * 0.5

	# 1. West Barrier: Erects perimeter boundary along the negative X axis.
	var west_pos := Vector3(min_p.x - THICKNESS * 0.5, wall_center_y, min_p.z + sz.z * 0.5)
	var west_size := Vector3(THICKNESS, wall_h, sz.z)
	_create_boundary_wall(west_pos, west_size, "WestBarrier")

	# 2. East Barrier: Erects perimeter boundary along positive X, inset by 1.0m to align with discrete voxel coordinates.
	var east_pos := Vector3(max_p.x - INWARD_MARGIN + THICKNESS * 0.5, wall_center_y, min_p.z + sz.z * 0.5)
	var east_size := Vector3(THICKNESS, wall_h, sz.z)
	_create_boundary_wall(east_pos, east_size, "EastBarrier")

	# 3. North Barrier: Erects perimeter boundary along the negative Z axis.
	var north_pos := Vector3(min_p.x + sz.x * 0.5, wall_center_y, min_p.z - THICKNESS * 0.5)
	var north_size := Vector3(sz.x + THICKNESS * 2.0, wall_h, THICKNESS)
	_create_boundary_wall(north_pos, north_size, "NorthBarrier")

	# 4. South Barrier: Erects perimeter boundary along positive Z, inset by 1.0m to align with discrete voxel coordinates.
	var south_pos := Vector3(min_p.x + sz.x * 0.5, wall_center_y, max_p.z - INWARD_MARGIN + THICKNESS * 0.5)
	var south_size := Vector3(sz.x + THICKNESS * 2.0, wall_h, THICKNESS)
	_create_boundary_wall(south_pos, south_size, "SouthBarrier")


func _create_boundary_wall(center: Vector3, size: Vector3, wall_name: String) -> void:
	## Auxiliary: Instantiates a StaticBody3D with a BoxShape3D barrier on physics layer 1.
	var body := StaticBody3D.new()
	body.name = wall_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center

	var col := CollisionShape3D.new()
	col.name = "CollisionShape"
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

	_boundaries_root.add_child(body)


func _get_bottom_wall_pos(bounds: AABB) -> Vector3:
	## Auxiliary: Computes the center position for the floor barrier slab.
	const THICKNESS := 16.0
	return Vector3(
		bounds.position.x + bounds.size.x * 0.5,
		bounds.position.y - THICKNESS * 0.5,
		bounds.position.z + bounds.size.z * 0.5
	)


func _get_bottom_wall_size(bounds: AABB) -> Vector3:
	## Auxiliary: Computes the 3D dimensions for the floor barrier slab.
	const THICKNESS := 16.0
	return Vector3(bounds.size.x + THICKNESS * 2.0, THICKNESS, bounds.size.z + THICKNESS * 2.0)

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
	if blocky_grid == null:
		return NAN
	var terrain := blocky_grid.get_terrain()
	if terrain == null or not is_inside_tree() or terrain.get_world_3d() == null:
		return NAN
	var space := terrain.get_world_3d().direct_space_state
	if space == null:
		return NAN
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
	if furniture_container == null:
		furniture_container = get_node_or_null(^"FurnitureContainer") as Node3D
	return furniture_container

## Parent Node3D for colonist entities spawned by Colony at map load.
func get_colonist_container() -> Node3D:
	if colonist_container == null:
		colonist_container = get_node_or_null(^"ColonistContainer") as Node3D
	return colonist_container

## Parent Node3D for enemy entities spawned at map load.
func get_enemy_container() -> Node3D:
	if enemy_container == null:
		enemy_container = get_node_or_null(^"EnemyContainer") as Node3D
	return enemy_container
