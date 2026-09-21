class_name WaterGenerator
extends VoxelGeneratorScript

var water_level: float = -2.0
var water_raw_idx: int = 14
var terrain_gen: TerrainGenDef = null
var _image: Image = null
var _noise: FastNoiseLite = null

func setup(def: TerrainGenDef, level: float, raw_idx: int) -> void:
	water_level = level
	water_raw_idx = raw_idx
	terrain_gen = def
	if def != null:
		if def.heightmap != null:
			var img = def.heightmap.get_image()
			if img != null:
				if img.is_compressed():
					img.decompress()
				img.convert(Image.FORMAT_RF)
				_image = img
		if _image == null:
			_noise = FastNoiseLite.new()
			_noise.seed = def.noise_seed
			_noise.frequency = def.noise_frequency

func _get_used_channels_mask() -> int:
	return 1 << VoxelBuffer.CHANNEL_TYPE

func _generate_block(out_buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	if lod > 0 or terrain_gen == null:
		return

	# Voxel unit cubes span [y, y + 1.0]. To keep the water surface at or below water_level,
	# the highest allowable voxel cell index is floor(water_level) - 1.
	var max_water_y: int = int(floor(water_level)) - 1
	if origin.y > max_water_y:
		return

	var size := out_buffer.get_size()
	for z in size.z:
		var world_z := origin.z + z
		for x in size.x:
			var world_x := origin.x + x

			# 1. Height Sampling: Resolves the continuous terrain elevation at (x, z).
			var h: float = _sample_terrain_height(world_x, world_z)
			if is_nan(h):
				continue

			var floor_y: int = int(floor(h))
			if floor_y > max_water_y:
				continue

			for y in size.y:
				var world_y := origin.y + y
				if world_y <= max_water_y and world_y >= floor_y:
					out_buffer.set_voxel(water_raw_idx, x, y, z, VoxelBuffer.CHANNEL_TYPE)


func _sample_terrain_height(world_x: int, world_z: int) -> float:
	## Auxiliary: Samples the terrain elevation from the heightmap image or procedural noise.
	if _image != null:
		var isize := _image.get_size()
		var px := wrapi(world_x + int(isize.x) / 2, 0, int(isize.x))
		var pz := wrapi(world_z + int(isize.y) / 2, 0, int(isize.y))
		var v: float = _image.get_pixel(px, pz).r
		return terrain_gen.height_start + v * terrain_gen.height_range
	elif _noise != null:
		var n: float = _noise.get_noise_2d(world_x, world_z)
		return terrain_gen.height_start + (n * 0.5 + 0.5) * terrain_gen.height_range
	return NAN
