class_name IBlockGrid
## Voxel-agnostic block-grid contract (docs/ARCHITECTURE.md, Build subsystem).
##
## The Build subsystem talks to the map through this interface only — it never
## touches voxel_tool directly. The voxel/ subsystem provides the concrete
## VoxelGrid implementation; build/voxel_grid_adapter.gd adapts it onto VoxelGrid
## (per the Build subsystem Files table).
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

## Physics raycast resolved to a voxel index + face normal.
## Returns { position: Vector3i, normal: Vector3i, hit: bool } (hit=false if no
## intersection). See gotchas/voxel_tool_raycast.md for why this is NOT
## VoxelTool.raycast.
func raycast_to_voxel(_origin: Vector3, _dir: Vector3, _max_dist: float) -> Dictionary:
	return {"position": Vector3i.ZERO, "normal": Vector3i.ZERO, "hit": false}
