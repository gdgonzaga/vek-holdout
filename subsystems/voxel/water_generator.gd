class_name WaterGenerator
extends VoxelGeneratorScript
## Fills every below-water-level column of the blocky grid with water cubes.
##
## Heights come from the same TerrainHeightSampler the smooth ground reads, so
## the shoreline follows the ground's own bank. A blocky cell (x, z) spans four
## ground samples (x, z) (x+1, z) (x, z+1) (x+1, z+1); the column is wet when ANY
## of them is below the water top and fills down to the lowest one. The cube then
## overshoots into the bank, and the smooth ground buries the cube's step edge
## instead of leaving it standing above the slope.

var water_level: float = -2.0
var water_raw_idx: int = 14
var _sampler: TerrainHeightSampler = null


func setup(sampler: TerrainHeightSampler, level: float, raw_idx: int) -> void:
	_sampler = sampler
	water_level = level
	water_raw_idx = raw_idx


func _get_used_channels_mask() -> int:
	return 1 << VoxelBuffer.CHANNEL_TYPE


# =================
# Primary Functions
# =================

func _generate_block(out_buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	if lod > 0 or _sampler == null:
		return

	# 1. Surface Ceiling: Resolving the highest allowed water cell so the top face never exceeds water_level.
	var max_water_y: int = _get_max_water_y()
	if origin.y > max_water_y:
		return

	var size := out_buffer.get_size()
	for z in size.z:
		for x in size.x:
			# 2. Bank Height: Lowest of the 4 ground samples under this cell, so the wet test sees the whole footprint.
			var lowest: float = _get_lowest_corner_height(origin.x + x, origin.z + z)
			if is_nan(lowest):
				continue

			var floor_y: int = int(floor(lowest))
			if floor_y > max_water_y:
				continue

			# 3. Column Fill: Writing water from the ground floor up to the surface ceiling inside this block.
			_fill_column(out_buffer, Vector2i(x, z), origin.y, floor_y, max_water_y)


# ===================
# Auxiliary Functions
# ===================

func _get_max_water_y() -> int:
	## Auxiliary: Voxel unit cubes span [y, y + 1.0], so the highest cell keeping the top at or below water_level is floor(water_level) - 1.
	return int(floor(water_level)) - 1


func _get_lowest_corner_height(world_x: int, world_z: int) -> float:
	## Auxiliary: Lowest ground height over the 2x2 samples a cell spans, or NAN when any sample is unreadable.
	var lowest := INF
	for dz in 2:
		for dx in 2:
			var h: float = _sampler.sample_height(world_x + dx, world_z + dz)
			if is_nan(h):
				return NAN
			lowest = minf(lowest, h)
	return lowest


func _fill_column(buffer: VoxelBuffer, column: Vector2i, origin_y: int, floor_y: int, max_water_y: int) -> void:
	## Auxiliary: Writes water into one buffer column for world y floor_y..max_water_y, clipped to the buffer.
	var first_y: int = maxi(floor_y - origin_y, 0)
	var last_y: int = mini(max_water_y - origin_y, buffer.get_size().y - 1)
	for y in range(first_y, last_y + 1):
		buffer.set_voxel(water_raw_idx, column.x, y, column.y, VoxelBuffer.CHANNEL_TYPE)
