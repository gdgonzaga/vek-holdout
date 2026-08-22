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


## The block type id at pos - the def's BlockLibrary BASE index. The stored
## voxel may be a rotation-variant index; the grid resolves it to its owning
## def (see BlockyGrid's class doc for the variant storage convention).
func get_block_type(pos: Vector3i) -> int:
	if _grid == null:
		return 0
	return _grid.get_block_type(pos)


## The orthogonal orientation (0..23) the block at pos renders at — the
## variant's orientation, 0 for unrotated/NONE blocks.
func get_block_rotation(pos: Vector3i) -> int:
	if _grid == null:
		return 0
	return _grid.get_block_rotation(pos)


## Returns the 3D Basis corresponding to the block rotation at pos.
func get_block_basis(pos: Vector3i) -> Basis:
	return VoxelBlockEncoder.rot_index_to_basis(get_block_rotation(pos))


## Sets the block at pos. type_id is the def's BlockLibrary base index;
## rot_index (0..23) is sanitized against the def's rotation_mode and stored
## as the baked variant index (plain base index when unrotated).
func set_block(pos: Vector3i, type_id: int, rot_index: int = 0) -> void:
	if _grid == null:
		return
	_grid.set_block(pos, type_id, rot_index)


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


## True if pos contains solid natural smooth terrain meeting the height / SDF threshold.
func is_terrain_at(pos: Vector3i, threshold: float = 0.5) -> bool:
	if _smooth == null:
		return false
	var vt: VoxelTool = _smooth.get_voxel_tool()
	if vt != null and vt.has_method("get_voxel_f"):
		if vt.get_voxel_f(pos) >= 0.25:
			return false
	var h: float = _smooth.height_at(float(pos.x) + 0.5, float(pos.z) + 0.5)
	if not is_nan(h):
		return h >= (float(pos.y) + threshold)
	if vt != null and vt.has_method("get_voxel_f"):
		return vt.get_voxel_f(pos) <= -threshold
	return false


## Applies damage to the block or smooth terrain at pos.
func apply_damage_at(pos: Vector3i, amount: int, actor: Node = null, normal: Vector3 = Vector3.UP) -> Dictionary:
	if _smooth != null and is_instance_valid(_smooth) and _smooth.is_inside_tree():
		if _smooth.get_material_def_at(pos) != null or is_terrain_at(pos):
			return _smooth.apply_damage_at(pos, amount, actor, normal)
	if _grid != null and _grid.has_block_at(pos):
		_grid.apply_damage(pos, amount)
		var hp: int = _grid.get_hp_at(pos)
		return {
			"destroyed": hp <= 0,
			"material": null,
			"remaining_hp": hp,
			"max_hp": 0
		}
	if _smooth != null and is_instance_valid(_smooth) and _smooth.is_inside_tree():
		return _smooth.apply_damage_at(pos, amount, actor, normal)
	return {"destroyed": false, "material": null, "remaining_hp": 0, "max_hp": 0}
