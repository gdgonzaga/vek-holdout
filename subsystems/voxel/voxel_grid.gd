class_name VoxelGrid
extends Node
## The sole owner of voxel_tool access for build/placement queries.
## Implements IBlockGrid (build/i_block_grid.gd). Voxel coupling lives here and
## nowhere else — other subsystems go through IBlockGrid, never voxel_tool.
##
## Block identity is a string block_id everywhere outside this class. Internally
## we store the integer voxel-tool library index; the BlockLibrary does the
## id<->index translation. Per-position HP is tracked so combat/raids can damage
## blocks below their BlockDef.hp before destroying them (see DamageResolver /
## raid breach flows).
##
## Lifecycle: _ready() fetches the VoxelTool from the VoxelTerrain child node.

signal block_placed(pos: Vector3i, block_id: String)
signal block_destroyed(pos: Vector3i)

## Path/name of the VoxelTerrain node, relative to this VoxelGrid. The WorldRoot
## (world.tscn) parents VoxelTerrain as a direct child of VoxelGrid.
@export var terrain_path: NodePath = ^"VoxelTerrain"

@onready var _terrain: VoxelTerrain = get_node(terrain_path)
var _voxel_tool: VoxelTool

var _library: BlockLibrary = null
var _hp_by_pos: Dictionary = {}      # Vector3i -> int (current HP; absent = air)

func _ready() -> void:
	_library = BlockLibrary.new()
	# Wire the data-driven block library into the terrain's mesher. Kept in code
	# (not the .tscn) because the VoxelBlockyLibrary is assembled from data/blocks/.
	var mesher: VoxelMesherBlocky = _terrain.mesher
	if mesher != null:
		mesher.library = _library.get_voxel_library()
	_voxel_tool = _terrain.get_voxel_tool()
	_voxel_tool.mode = VoxelTool.MODE_SET

# --- IBlockGrid ---------------------------------------------------------------

func get_block_at(pos: Vector3i) -> String:
	var index := _voxel_tool.get_voxel(pos)
	return _library.get_id(index)

func set_block_at(pos: Vector3i, block_id: String) -> void:
	var index := _library.get_index(block_id)
	if index < 0:
		push_error("VoxelGrid: unknown block_id '%s'" % block_id)
		return
	_voxel_tool.set_voxel(pos, index)
	var def := _library.get_def(block_id)
	_hp_by_pos[pos] = def.hp if def != null else 0
	block_placed.emit(pos, block_id)

func remove_block_at(pos: Vector3i) -> void:
	_voxel_tool.set_voxel(pos, 0)
	_hp_by_pos.erase(pos)
	block_destroyed.emit(pos)

## Godot physics raycast, NOT VoxelTool.raycast (see gotchas/voxel_tool_raycast.md:
## VoxelTool.raycast returns null even on valid hits). We raycast against the
## collision bodies that VoxelTerrain generates and resolve the hit point to a
## voxel index. The -normal*0.001 nudge keeps flooring inside the struck voxel
## instead of the adjacent empty one.
## `exclude` (optional): Array[RID] of physics bodies to ignore. Used by the
## build raycast to skip the player's own capsule (the third-person camera ray
## would otherwise hit the player body before the terrain).
func raycast_to_voxel(origin: Vector3, dir: Vector3, max_dist: float, exclude: Array = []) -> Dictionary:
	# VoxelGrid is a plain Node (no get_world_3d); the VoxelTerrain child is a
	# Node3D and owns the physics world its collision bodies live in.
	var space := _terrain.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_dist)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if not exclude.is_empty():
		query.exclude = exclude
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {"position": Vector3i.ZERO, "normal": Vector3i.ZERO, "hit": false}
	var p: Vector3 = (hit.position - hit.normal * 0.001).floor()
	var voxel_pos := Vector3i(int(p.x), int(p.y), int(p.z))
	var normal := Vector3i(int(round(hit.normal.x)), int(round(hit.normal.y)), int(round(hit.normal.z)))
	return {"position": voxel_pos, "normal": normal, "hit": true}

# --- block HP / damage surface (consumed by combat + raids) -------------------

## Current HP of the block at pos, or 0 if air/terrain.
func get_hp_at(pos: Vector3i) -> int:
	return _hp_by_pos.get(pos, 0)

func has_block_at(pos: Vector3i) -> bool:
	return _hp_by_pos.has(pos)

## Applies damage to a buildable block. Destroys it when HP hits 0 and emits
## block_destroyed. Terrain (non-buildable, sentinel HP) is ignored.
func apply_damage(pos: Vector3i, amount: int) -> void:
	if not _hp_by_pos.has(pos):
		return
	_hp_by_pos[pos] = _hp_by_pos[pos] - amount
	if _hp_by_pos[pos] <= 0:
		remove_block_at(pos)

# --- accessors for world/consumers -------------------------------------------

func get_library() -> BlockLibrary:
	return _library

func get_terrain() -> VoxelTerrain:
	return _terrain

func get_voxel_tool() -> VoxelTool:
	return _voxel_tool
