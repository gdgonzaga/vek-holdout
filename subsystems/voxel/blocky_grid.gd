class_name BlockyGrid
extends Node
## The sole owner of voxel_tool access for build/placement queries on the
## structures terrain. Implements IBlockGrid (build/i_block_grid.gd). Voxel
## terrain layers and collision bodies live here. BuildController talks to
## IBlockGrid, never voxel_tool. The dual-voxel conversion (docs/TODO.md)
## retains this class for structure blocks; smooth natural terrain uses
## SmoothGrid.
##
## Stored voxel values are plain VoxelBlockyLibrary model indices (0 = air,
## then BlockLibrary's base table + variant appendix — see docs/VOXEL-TOOL-NOTES.md).
## The mesher indexes models by the raw value, so anything else (e.g. bit-packed
## type+rotation) silently produces no mesh and no collision while still
## persisting to the sqlite stream — invisible, un-collidable voxels. Per-voxel
## rotation is expressed by WHICH index is stored: BlockLibrary bakes variant
## models for rotatable defs and set_block resolves (type, rotation) to the
## matching variant index.

signal block_placed(pos: Vector3i, block_id: String)
signal block_destroyed(pos: Vector3i)

## Terrain collision layer (2) + mask (player body 8 + colonist body 32).
const TERRAIN_LAYER := 2
const TERRAIN_BODY_MASK := 8 | 32

## Collision layer 3 for smooth natural terrain (used in dual-voxel raycasts).
const SMOOTH_TERRAIN_LAYER_VALUE := 4

## Physics raycast mask for placement cursor: World statics (1) + terrain (2) + smooth terrain (4) + body (16).
const BUILD_RAY_MASK := 1 | TERRAIN_LAYER | SMOOTH_TERRAIN_LAYER_VALUE | 16

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
	_library = _make_library()
	# Wire the data-driven block library into the terrain's mesher. Kept in code
	# (not the .tscn) because the VoxelBlockyLibrary is assembled from data/blocks/.
	var mesher: VoxelMesherBlocky = _terrain.mesher
	if mesher != null:
		mesher.library = _library.get_voxel_library()
	_voxel_tool = _terrain.get_voxel_tool()
	_voxel_tool.mode = VoxelTool.MODE_SET

## Library factory — overridable so tests can mount a fixture BlockLibrary
## (fixture defs with rotation modes) without touching data/blocks/.
func _make_library() -> BlockLibrary:
	return BlockLibrary.new()

# --- IBlockGrid ---------------------------------------------------------------

func get_block_at(pos: Vector3i) -> String:
	return _library.get_id(get_block_type(pos))

func set_block_at(pos: Vector3i, block_id: String, rot_index: int = 0) -> void:
	var index := _library.get_index(block_id)
	if index < 0:
		push_error("BlockyGrid: unknown block_id '%s'" % block_id)
		return
	set_block(pos, index, rot_index)
	var def := _library.get_def(block_id)
	_hp_by_pos[pos] = def.hp if def != null else 0
	block_placed.emit(pos, block_id)

func remove_block_at(pos: Vector3i) -> void:
	_voxel_tool.set_voxel(pos, 0)
	_hp_by_pos.erase(pos)
	block_destroyed.emit(pos)

func get_raw_voxel(pos: Vector3i) -> int:
	if _voxel_tool == null:
		return 0
	return _voxel_tool.get_voxel(pos)

func set_raw_voxel(pos: Vector3i, raw_val: int) -> void:
	if _voxel_tool == null:
		return
	_voxel_tool.set_voxel(pos, raw_val)

## The block type id at pos: the def's BlockLibrary BASE index. Stored values
## may be variant indices (rotated placements) — the library resolves them
## back to their owning def's base. None-rotatable blocks store their base
## index directly, so this passes those through unchanged.
func get_block_type(pos: Vector3i) -> int:
	if _library == null:
		return 0
	return _library.get_base_index(get_raw_voxel(pos))

## The orthogonal orientation (0..23) the block at pos renders at. Variant
## indices report their orientation; base indices (and NONE defs) report 0.
func get_block_rotation(pos: Vector3i) -> int:
	if _library == null:
		return 0
	return _library.get_rotation_index(get_raw_voxel(pos))

func get_block_basis(pos: Vector3i) -> Basis:
	return VoxelBlockEncoder.rot_index_to_basis(get_block_rotation(pos))

## type_id is the def's BlockLibrary base index; rot_index an orthogonal
## orientation (0..23), sanitized against the def's rotation_mode and stored
## as the matching baked variant index — plain and renderable, never packed
## (see the class doc).
func set_block(pos: Vector3i, type_id: int, rot_index: int = 0) -> void:
	set_raw_voxel(pos, _library.get_stored_index(type_id, rot_index))

## Godot physics raycast, NOT VoxelTool.raycast (see gotchas/voxel_tool_raycast.md:
## VoxelTool.raycast returns null even on valid hits). We raycast against the
## collision bodies that VoxelTerrain generates and resolve the hit point to a
## voxel index. The -normal*0.001 nudge keeps flooring inside the struck voxel
## instead of the adjacent empty one.
## `exclude` (optional): Array[RID] of physics bodies to ignore. Used by the
## build raycast to skip the player's own capsule (the third-person camera ray
## would otherwise hit the player body before the terrain).
##
## Returns { position, normal, hit, surface }: `surface` classifies the collider
## by collision layer — "blocky" (this terrain), "smooth" (SmoothGrid, layer 3),
## or "body" (World statics / Build interaction boxes). Blocky/body hits resolve
## as today (position = struck cell, normal = axis-aligned face) and consumers
## derive the placement cell as position + normal. A smooth hit keeps nothing
## integer: `position` IS the derived placement cell floor(point + normal * 0.5),
## `normal` is Vector3i.ZERO, and the float hit rides along as
## `smooth_point`/`smooth_normal` (smooth normals are non-axis-aligned, F7) for
## slope-aware consumers. Deconstruct ignores smooth hits — natural ground is
## removed by mining, not the build ray (D3).
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
		return {"position": Vector3i.ZERO, "normal": Vector3i.ZERO, "hit": false, "surface": ""}
	var collider: Object = hit.get("collider")
	var layer := int(collider.get("collision_layer")) if collider != null and "collision_layer" in collider else 0
	if (layer & SMOOTH_TERRAIN_LAYER_VALUE) != 0:
		var smooth_normal: Vector3 = hit.normal
		var cell: Vector3 = (hit.position + smooth_normal * 0.5).floor()
		return {
			"position": Vector3i(int(cell.x), int(cell.y), int(cell.z)),
			"normal": Vector3i.ZERO,
			"hit": true,
			"surface": "smooth",
			"smooth_point": hit.position,
			"smooth_normal": smooth_normal,
		}
	var p: Vector3 = (hit.position - hit.normal * 0.001).floor()
	var voxel_pos := Vector3i(int(p.x), int(p.y), int(p.z))
	var normal := Vector3i(int(round(hit.normal.x)), int(round(hit.normal.y)), int(round(hit.normal.z)))
	var surface := "blocky" if (layer & TERRAIN_LAYER) != 0 else "body"
	return {"position": voxel_pos, "normal": normal, "hit": true, "surface": surface}

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
