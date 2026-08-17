class_name BlockyGrid
extends Node
## The sole owner of voxel_tool access for build/placement queries on the
## structures terrain. Implements IBlockGrid (build/i_block_grid.gd). Voxel
## coupling lives here and nowhere else — other subsystems go through
## IBlockGrid, never voxel_tool. The dual-voxel conversion (docs/TODO.md)
## mirrors this class as SmoothGrid for natural terrain: same vocabulary,
## different mesher/generator.
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

## Collision-layer plan (docs/architecture/voxel-world.md "Collision layers"):
## this terrain owns layer 2 (TerrainBlocky) so physics queries can address
## blocky ground separately from World furniture statics (layer 1) and from the
## smooth terrain that will own layer 3 (dual-voxel conversion, docs/TODO.md).
## Assigned in code, not the map template, so every map — including already
## stamped POIs — gets it at runtime.
const TERRAIN_LAYER := 2
## F7 (docs/VOXEL-TOOL-NOTES.md): giving a terrain a custom layer REQUIRES a
## mask that includes the body layers standing on it, or body interaction
## silently stops (rays keep working — they test query-mask vs layer only).
## Player (layer 4) and Colonist (layer 6) are the terrain-standing bodies.
const TERRAIN_BODY_MASK := 8 | 32
## The build/deconstruct ray stops on World statics, this terrain, and Build
## interaction bodies (furniture/blueprint BuildBody, layer 5) — nothing else.
## The pre-remap ray was unmasked and could hit a colonist standing between
## camera and target; that quirk is intentionally gone.
const BUILD_RAY_MASK := 1 | TERRAIN_LAYER | 16

## Path/name of the VoxelTerrain node, relative to this BlockyGrid. The map
## template parents VoxelTerrain as a direct child of BlockyGrid.
@export var terrain_path: NodePath = ^"VoxelTerrain"

@onready var _terrain: VoxelTerrain = get_node(terrain_path)
var _voxel_tool: VoxelTool

var _library: BlockLibrary = null
var _hp_by_pos: Dictionary = {}      # Vector3i -> int (current HP; absent = air)

func _ready() -> void:
	# Own collision layer 2 before any collision blocks stream in (they read
	# the terrain's layer/mask when generated). Guarded set() — collision_layer
	# on VoxelTerrain is a GDExtension property (spike idiom, F7).
	if "collision_layer" in _terrain:
		_terrain.set("collision_layer", TERRAIN_LAYER)
		_terrain.set("collision_mask", TERRAIN_BODY_MASK)
	else:
		push_warning("BlockyGrid: VoxelTerrain lacks collision_layer; terrain stays on the default layer")
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
		push_error("BlockyGrid: unknown block_id '%s'" % block_id)
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
	# BlockyGrid is a plain Node (no get_world_3d); the VoxelTerrain child is a
	# Node3D and owns the physics world its collision bodies live in.
	var space := _terrain.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_dist)
	query.collision_mask = BUILD_RAY_MASK
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

## Ray origin height / length for height_at: far above anything authorable, so
## one straight-down ray covers the whole column.
const HEIGHT_RAY_FROM_Y := 512.0
const HEIGHT_RAY_LENGTH := 1024.0

## World-space height of the highest terrain surface at column (x, z): a
## downward physics ray masked to this terrain's collision layer, so furniture,
## character bodies, and (later) the smooth terrain never answer. Returns NAN
## when no ground is hit within range. `normal_out` (optional) receives the
## surface normal on hit — callers gate slopes on it. The dual-voxel conversion
## mirrors this on SmoothGrid for walkability stand cells (docs/TODO.md D4).
func height_at(x: float, z: float, normal_out: Array = []) -> float:
	var space := _terrain.get_world_3d().direct_space_state
	var from := Vector3(x, HEIGHT_RAY_FROM_Y, z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * HEIGHT_RAY_LENGTH)
	query.collision_mask = TERRAIN_LAYER
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return NAN
	normal_out.append(hit.normal)
	return hit.position.y

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


# --- SaveSystem contract -----------------------------------------------------
# Only buildable-block HP lives here. Voxel block TYPES are not enumerated by
# this class: they persist via the per-map VoxelStreamSQLite (flushed on save by
# VoxelTerrain.save_modified_blocks(), auto-mounted on load), so restore only
# re-applies the HP metadata — it does NOT write voxels.

## Snapshot buildable-block HP: {"x,y,z" (String): hp (int)}.
func serialize() -> Dictionary:
	var hp := {}
	for pos in _hp_by_pos:
		hp["%d,%d,%d" % [pos.x, pos.y, pos.z]] = int(_hp_by_pos[pos])
	return {"hp": hp}


## Restore buildable-block HP from a serialize() dict. Clears current HP state
## first so it is a true inverse of serialize(). No voxel writes — block types
## come from the sqlite stream.
func deserialize(data: Dictionary) -> void:
	_hp_by_pos.clear()
	var hp: Dictionary = data.get("hp", {})
	for key in hp:
		var parts := String(key).split(",")
		if parts.size() != 3:
			continue
		var pos := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
		_hp_by_pos[pos] = int(hp[key])
