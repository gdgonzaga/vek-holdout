class_name StructureStamper
extends RefCounted
## Logic for transforming and stamping parsed MagicaVoxel structures (VoxData)
## into the voxel world via VoxelGridAdapter (ARCH "Build" / "Map Editor").

## Radius for smooth terrain sphere additions when stamping terrain voxels.
const SMOOTH_TERRAIN_ADD_RADIUS: float = 0.75

## Radius for smooth terrain sphere carving when stamping air voxels.
const SMOOTH_TERRAIN_CARVE_RADIUS: float = 0.75


## Calculates the local pivot offset vector for a StructureDef within its voxel bounds.
## Uses vox_data.dimensions if available, otherwise structure.bounding_box_size.
static func calculate_pivot_offset(structure: StructureDef, vox_data: VoxData = null) -> Vector3i:
	if structure == null:
		return Vector3i.ZERO

	var dims := structure.bounding_box_size
	if vox_data != null and vox_data.dimensions != Vector3i.ZERO:
		dims = vox_data.dimensions

	match structure.pivot_anchor:
		StructureDef.PivotAnchor.BOTTOM_CENTER:
			return Vector3i(dims.x / 2, 0, dims.z / 2) + structure.custom_pivot_offset
		StructureDef.PivotAnchor.BOTTOM_CORNER:
			return structure.custom_pivot_offset
		StructureDef.PivotAnchor.GEOMETRIC_CENTER:
			return Vector3i(dims.x / 2, dims.y / 2, dims.z / 2) + structure.custom_pivot_offset
		StructureDef.PivotAnchor.CUSTOM:
			return structure.custom_pivot_offset

	return structure.custom_pivot_offset


## Private alias for calculate_pivot_offset matching the subsystem plan specification.
static func _calculate_pivot_offset(structure: StructureDef, vox_data: VoxData) -> Vector3i:
	return calculate_pivot_offset(structure, vox_data)


## Rotates a discrete integer vector around the Y-axis by the given number of 90-degree steps.
## Positive steps rotate clockwise in standard top-down (+X right, +Z back/forward).
static func rotate_vector_y(v: Vector3i, steps: int) -> Vector3i:
	var s := (steps % 4 + 4) % 4
	match s:
		0:
			return v
		1:
			return Vector3i(v.z, v.y, -v.x)
		2:
			return Vector3i(-v.x, v.y, -v.z)
		3:
			return Vector3i(-v.z, v.y, v.x)
	return v


## Computes world-space positions and mapped palette entries for all voxels in vox_data
## after applying pivot offset and Y-axis rotation relative to origin.
static func get_transformed_voxels(
	structure: StructureDef,
	vox_data: VoxData,
	origin: Vector3i,
	rotation_y_steps: int = 0
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if structure == null or vox_data == null:
		return result

	var pivot := calculate_pivot_offset(structure, vox_data)
	var mapping := structure.palette_mapping

	for local_pos: Vector3i in vox_data.voxel_map.keys():
		var color_idx: int = vox_data.get_voxel(local_pos)
		if color_idx <= 0:
			continue

		var rel_pos := local_pos - pivot
		var rot_pos := rotate_vector_y(rel_pos, rotation_y_steps)
		var world_pos := origin + rot_pos

		var hex_color := vox_data.get_hex_color(color_idx)
		var target_entry: VoxPaletteEntry = null
		if mapping != null:
			target_entry = mapping.get_target_for_index(color_idx, hex_color)

		result.append({
			"world_pos": world_pos,
			"local_pos": local_pos,
			"color_index": color_idx,
			"hex_color": hex_color,
			"target_entry": target_entry,
		})

	return result


## Stamps vox_data into the voxel world via VoxelGridAdapter.
## Applies BLOCK, SMOOTH_TERRAIN, and AIR operations according to structure.palette_mapping.
## Returns an array of operation records describing changes made for undo/redo history.
static func stamp_structure(
	grid: VoxelGridAdapter,
	structure: StructureDef,
	vox_data: VoxData,
	origin: Vector3i,
	rotation_y_steps: int = 0
) -> Array[Dictionary]:
	var ops: Array[Dictionary] = []
	if grid == null or structure == null or vox_data == null:
		return ops

	var transformed := get_transformed_voxels(structure, vox_data, origin, rotation_y_steps)
	var smooth_grid := grid.get_smooth_grid()

	for item in transformed:
		var world_pos: Vector3i = item["world_pos"]
		var entry: VoxPaletteEntry = item["target_entry"]

		# If no entry or target is IGNORE, skip modifying this voxel cell
		if entry == null or entry.target_type == VoxPaletteEntry.TargetType.IGNORE:
			continue

		var old_raw := grid.get_raw_voxel(world_pos)
		var old_block_id := grid.get_block_at(world_pos)

		match entry.target_type:
			VoxPaletteEntry.TargetType.BLOCK:
				if not entry.block_id.is_empty():
					grid.set_block_at(world_pos, entry.block_id)
					ops.append({
						"type": "block",
						"pos": world_pos,
						"old_raw": old_raw,
						"old_block_id": old_block_id,
						"block_id": entry.block_id,
					})

			VoxPaletteEntry.TargetType.SMOOTH_TERRAIN:
				if smooth_grid != null:
					var world_center := Vector3(world_pos.x + 0.5, world_pos.y + 0.5, world_pos.z + 0.5)
					var mat_id := entry.terrain_material_id
					if mat_id.is_empty() and smooth_grid.default_material != null:
						mat_id = smooth_grid.default_material.id
					smooth_grid.add_material(world_center, mat_id, SMOOTH_TERRAIN_ADD_RADIUS)
					ops.append({
						"type": "terrain",
						"pos": world_pos,
						"material_id": mat_id,
					})

			VoxPaletteEntry.TargetType.AIR:
				grid.remove_block_at(world_pos)
				if smooth_grid != null:
					var world_center := Vector3(world_pos.x + 0.5, world_pos.y + 0.5, world_pos.z + 0.5)
					smooth_grid.carve(world_center, SMOOTH_TERRAIN_CARVE_RADIUS)
				ops.append({
					"type": "air",
					"pos": world_pos,
					"old_raw": old_raw,
					"old_block_id": old_block_id,
				})

	return ops


## Computes the world-space bounding box (AABB) of the structure at origin and rotation.
static func calculate_bounding_box(
	structure: StructureDef,
	vox_data: VoxData,
	origin: Vector3i,
	rotation_y_steps: int = 0
) -> AABB:
	if vox_data == null or vox_data.voxel_map.is_empty():
		return AABB(Vector3(origin), Vector3.ZERO)

	var transformed := get_transformed_voxels(structure, vox_data, origin, rotation_y_steps)
	if transformed.is_empty():
		return AABB(Vector3(origin), Vector3.ZERO)

	var min_p := Vector3(INF, INF, INF)
	var max_p := Vector3(-INF, -INF, -INF)

	for item in transformed:
		var wp: Vector3i = item["world_pos"]
		var v_min := Vector3(wp)
		var v_max := Vector3(wp) + Vector3.ONE
		min_p.x = minf(min_p.x, v_min.x)
		min_p.y = minf(min_p.y, v_min.y)
		min_p.z = minf(min_p.z, v_min.z)
		max_p.x = maxf(max_p.x, v_max.x)
		max_p.y = maxf(max_p.y, v_max.y)
		max_p.z = maxf(max_p.z, v_max.z)

	return AABB(min_p, max_p - min_p)
