class_name VoxelGridAdapter
extends IBlockGrid
## IBlockGrid implementation wrapping voxel/blocky_grid.gd (ARCH "Build").
## Keeps BuildController voxel-agnostic: it talks to this adapter, never to
## voxel_tool or BlockyGrid directly. Holds a BlockyGrid reference set at wiring
## time (map mounts the controller + hands it the grid), plus an optional
## SmoothGrid for ground-support queries on smooth placements (dual-voxel D3).

var _grid: BlockyGrid = null
var _smooth: SmoothGrid = null


func set_grid(grid: BlockyGrid) -> void:
	_grid = grid


## Optional natural-terrain half (MapWiring passes the live SmoothGrid, or
## null on terrain-less maps) — used only by is_ground_supported.
func set_smooth_grid(smooth: SmoothGrid) -> void:
	_smooth = smooth


## The live SmoothGrid (or null on terrain-less maps). The dig tool resolves
## its target terrain through this — smooth edits are the one place build code
## intentionally reaches past the blocky contract.
func get_smooth_grid() -> SmoothGrid:
	return _smooth


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


## Returns the raw 16-bit packed voxel integer at pos.
func get_raw_voxel(pos: Vector3i) -> int:
	if _grid == null:
		return 0
	if _grid.has_method("get_raw_voxel"):
		return _grid.get_raw_voxel(pos)
	var vt := _grid.get_voxel_tool()
	if vt != null:
		return vt.get_voxel(pos)
	return 0


## Sets the raw 16-bit packed voxel integer at pos.
func set_raw_voxel(pos: Vector3i, raw_val: int) -> void:
	if _grid == null:
		return
	if _grid.has_method("set_raw_voxel"):
		_grid.set_raw_voxel(pos, raw_val)
		return
	var vt := _grid.get_voxel_tool()
	if vt != null:
		vt.set_voxel(pos, raw_val)


## Returns the 11-bit block type ID at pos (decoded from raw voxel).
func get_block_type(pos: Vector3i) -> int:
	var raw := get_raw_voxel(pos)
	return VoxelBlockEncoder.decode_type(raw)


## Returns the 5-bit rotation index (0..23) at pos (decoded from raw voxel).
func get_block_rotation(pos: Vector3i) -> int:
	var raw := get_raw_voxel(pos)
	return VoxelBlockEncoder.decode_rotation(raw)


## Returns the 3D Basis corresponding to the block rotation at pos.
func get_block_basis(pos: Vector3i) -> Basis:
	return VoxelBlockEncoder.rot_index_to_basis(get_block_rotation(pos))


## Sets the block at pos with type_id (11-bit) and rot_index (5-bit rotation, 0..23).
func set_block(pos: Vector3i, type_id: int, rot_index: int = 0) -> void:
	var raw := VoxelBlockEncoder.encode(type_id, rot_index)
	set_raw_voxel(pos, raw)


## True if a block can be placed at cell: currently means the cell is air (not
## terrain and not already a buildable block). TODO: ownership/footprint checks
## once multi-cell blocks exist.
func is_valid_placement(pos: Vector3i) -> bool:
	if _grid == null:
		return false
	var id := _grid.get_block_at(pos)
	return id == ""


## True when cell sits on natural or blocky ground: a solid blocky voxel
## directly below, or a smooth surface within one cell of the cell's floor.
## Placement cells derived from a smooth hit (D3: floor(point + normal * 0.5))
## have no blocky floor by construction — this is their support check. The
## one-cell window is generous by design: the derived cell of a smooth hit can
## sit up to half a cell above the surface on steep slopes (model embed on
## slopes is the accepted v1 trade-off, not a support failure).
func is_ground_supported(pos: Vector3i) -> bool:
	if _grid == null:
		return false
	if _grid.get_block_at(pos + Vector3i(0, -1, 0)) != "":
		return true
	if _smooth != null:
		var h: float = _smooth.height_at(float(pos.x) + 0.5, float(pos.z) + 0.5)
		if not is_nan(h) and h >= float(pos.y - 1) and h <= float(pos.y + 1):
			return true
	return false


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
