class_name VoxelGridAdapter
extends RefCounted
## IBlockGrid implementation wrapping voxel/blocky_grid.gd (ARCH "Build").
## Keeps BuildController voxel-agnostic: it talks to this adapter, never to
## voxel_tool or BlockyGrid directly. Holds a BlockyGrid reference set at wiring
## time (map mounts the controller + hands it the grid).

var _grid: BlockyGrid = null


func set_grid(grid: BlockyGrid) -> void:
	_grid = grid


func get_grid() -> BlockyGrid:
	return _grid


## Block id at cell, or "" for air.
func get_block_at(pos: Vector3i) -> String:
	if _grid == null:
		return ""
	return _grid.get_block_at(pos)


## Places block_id at pos (delegates to BlockyGrid; emits block_placed there).
func set_block_at(pos: Vector3i, block_id: String) -> void:
	if _grid == null:
		return
	_grid.set_block_at(pos, block_id)


## Removes whatever is at pos (delegates to BlockyGrid; emits block_destroyed there).
func remove_block_at(pos: Vector3i) -> void:
	if _grid == null:
		return
	_grid.remove_block_at(pos)


## True if a block can be placed at cell: currently means the cell is air (not
## terrain and not already a buildable block). TODO: ownership/footprint checks
## once multi-cell blocks exist.
func is_valid_placement(pos: Vector3i) -> bool:
	if _grid == null:
		return false
	var id := _grid.get_block_at(pos)
	return id == ""


## Snap a world-space candidate to the integer voxel cell containing it.
## Returns the cell origin (integer Vector3). Used by strategies that take a
## free transform; the ghost uses integer cells directly so this is mostly for
## the placement path.
func snap_transform(world_pos: Vector3) -> Vector3i:
	return Vector3i(int(floor(world_pos.x)), int(floor(world_pos.y)), int(floor(world_pos.z)))


## Physics raycast resolved to a voxel cell + face/classification (delegates to
## BlockyGrid; see its raycast_to_voxel for the `surface` contract — "smooth"
## hits carry a pre-derived placement cell and zero normal).
## `exclude` (optional): Array[RID] to ignore (e.g. the player body). Returns
## { position: Vector3i, normal: Vector3i, hit: bool, surface: String }.
func raycast_to_voxel(origin: Vector3, dir: Vector3, max_dist: float, exclude: Array = []) -> Dictionary:
	if _grid == null:
		return {"position": Vector3i.ZERO, "normal": Vector3i.ZERO, "hit": false, "surface": ""}
	return _grid.raycast_to_voxel(origin, dir, max_dist, exclude)


## Ground height at world column (x, z) on the blocky terrain (delegates to
## BlockyGrid). NAN when no ground within range. `normal_out` optionally
## receives the surface normal on hit.
func height_at(x: float, z: float, normal_out: Array = []) -> float:
	if _grid == null:
		return NAN
	return _grid.height_at(x, z, normal_out)
