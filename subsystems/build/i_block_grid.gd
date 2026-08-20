class_name IBlockGrid
extends RefCounted
## Voxel-agnostic block-grid contract (docs/ARCHITECTURE.md, Build subsystem).
##
## The Build subsystem talks to the map through this interface only — it never
## touches voxel_tool directly. The voxel/ subsystem provides the concrete
## BlockyGrid implementation; build/voxel_grid_adapter.gd adapts it onto
## BlockyGrid (per the Build subsystem Files table).
##
## Godot has no formal interfaces, so this is a documentation-only contract:
## implementations do NOT extend it (single inheritance is needed for Node).
## They simply provide every method below with matching signatures, and duck-type
## against this spec. `block_id` is the string id from data/blocks/
## (empty string = air).
##
## Signals an implementation must emit:
##   block_placed(pos: Vector3i, block_id: String)
##   block_destroyed(pos: Vector3i)

## Returns the block_id at pos, or "" if air.
func get_block_at(_pos: Vector3i) -> String:
	return ""

## Places a block of block_id at pos. Emits block_placed.
func set_block_at(_pos: Vector3i, _block_id: String) -> void:
	pass

## Removes whatever is at pos. Emits block_destroyed.
func remove_block_at(_pos: Vector3i) -> void:
	pass

## The block type id at pos — the def's BlockLibrary base index (stored
## rotation-variant voxels resolve to their owning def).
func get_block_type(_pos: Vector3i) -> int:
	return 0

## The orthogonal orientation (0..23) the block at pos renders at — the
## baked variant's orientation, 0 for unrotated/NONE blocks.
func get_block_rotation(_pos: Vector3i) -> int:
	return 0

## Returns the 3D Basis corresponding to the block rotation at pos.
func get_block_basis(_pos: Vector3i) -> Basis:
	return Basis()

## Sets the block at pos. type_id is the def's BlockLibrary base index;
## rot_index (0..23) is sanitized against the def's rotation_mode and stored
## as the baked variant index (see BlockyGrid's storage convention).
func set_block(_pos: Vector3i, _type_id: int, _rot_index: int = 0) -> void:
	pass

## Returns the raw stored voxel integer at pos — a VoxelBlockyLibrary model
## index (the mesher's addressing scheme; see BlockyGrid's class doc).
func get_raw_voxel(_pos: Vector3i) -> int:
	return 0

## Sets the raw stored voxel integer at pos (a library model index).
func set_raw_voxel(_pos: Vector3i, _raw_val: int) -> void:
	pass


## True if a block can be placed at cell: the cell is air (not terrain, not an
## existing buildable block).
func is_valid_placement(_pos: Vector3i) -> bool:
	return false


## True when cell is supported by ground: a solid voxel directly below, or a
## smooth surface within one cell of the cell's floor (smooth-hit placements
## have no blocky floor by construction — D3). Only smooth-derived placement
## cells are gated on this; blocky/body-derived cells keep is_valid_placement
## alone (their support exists by construction, and wall/ceiling placement
## must not regress).
func is_ground_supported(_pos: Vector3i) -> bool:
	return false

## Physics raycast resolved to a voxel index + face normal.
## Returns { position: Vector3i, normal: Vector3i, hit: bool, surface: String }
## (hit=false if no intersection). `surface` classifies the collider: "blocky"
## terrain, "smooth" terrain (position is then the pre-derived placement cell,
## normal zero — see BlockyGrid.raycast_to_voxel for the full contract), or
## "body" (World/Build interaction bodies). See gotchas/voxel_tool_raycast.md
## for why this is NOT VoxelTool.raycast.
func raycast_to_voxel(_origin: Vector3, _dir: Vector3, _max_dist: float) -> Dictionary:
	return {"position": Vector3i.ZERO, "normal": Vector3i.ZERO, "hit": false}

## Ground height at world column (x, z) via a downward physics ray masked to
## the terrain's collision layer (World statics / bodies / other terrains never
## answer). Returns NAN when no ground is hit within range. `normal_out`
## (optional): Array that receives the surface normal on hit (slope gating).
func height_at(_x: float, _z: float, _normal_out: Array = []) -> float:
	return NAN
