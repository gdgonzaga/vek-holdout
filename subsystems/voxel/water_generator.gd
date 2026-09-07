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
	
	if origin.y > water_level:
		return
		
	var size := out_buffer.get_size()
	for z in size.z:
		var world_z = origin.z + z
		for x in size.x:
			var world_x = origin.x + x
			
			var h: float = NAN
			if _image != null:
				var isize = _image.get_size()
				var px = wrapi(world_x + int(isize.x) / 2, 0, int(isize.x))
				var pz = wrapi(world_z + int(isize.y) / 2, 0, int(isize.y))
				var v = _image.get_pixel(px, pz).r
				h = terrain_gen.height_start + v * terrain_gen.height_range
			elif _noise != null:
				var n = _noise.get_noise_2d(world_x, world_z)
				h = terrain_gen.height_start + (n * 0.5 + 0.5) * terrain_gen.height_range
			
			if is_nan(h):
				continue
				
			var floor_y = int(floor(h))
			if floor_y >= water_level:
				continue
				
			for y in size.y:
				var world_y = origin.y + y
				if world_y <= water_level and world_y > floor_y:
					out_buffer.set_voxel(water_raw_idx, x, y, z, VoxelBuffer.CHANNEL_TYPE)
