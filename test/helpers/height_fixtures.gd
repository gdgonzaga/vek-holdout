## In-memory terrain-gen fixtures for height sampling and water generation
## tests. Plain script (never a suite): preload it, call the statics.
##
## Heights are authored in whole meters per WORLD column so a test states the
## terrain it wants ("corner (0,0) sits 6 m down") instead of pixel math. The
## span is fixed at start -128 / range 255, so one L8 grey level is exactly one
## meter and no test depends on the quantization the sampler snaps away.

const HEIGHT_START: float = -128.0
const HEIGHT_RANGE: float = 255.0


## Heightmap-driven def, `size` x `size` pixels centered on the world origin
## (world column x lands on pixel wrapi(x + size / 2, 0, size), the same
## mapping the generators use). Columns absent from `world_heights` sit at
## `default_height`.
static func make_heightmap_def(size: int, world_heights: Dictionary, default_height: int) -> TerrainGenDef:
	var image := Image.create(size, size, false, Image.FORMAT_L8)
	# 1. Baseline: every pixel starts at the default height so unlisted columns are flat.
	_fill_uniform(image, default_height)
	# 2. Overrides: each listed world column is written to its wrapped pixel.
	_write_world_heights(image, world_heights)
	var def := TerrainGenDef.new()
	def.id = "height_fixture"
	def.height_start = HEIGHT_START
	def.height_range = HEIGHT_RANGE
	def.heightmap = ImageTexture.create_from_image(image)
	return def


## Noise-path def (no heightmap) whose surface is flat at `height`: zero range
## makes the noise term vanish, so every column reads exactly `height`.
static func make_flat_noise_def(height: float) -> TerrainGenDef:
	var def := TerrainGenDef.new()
	def.id = "height_fixture_flat"
	def.height_start = height
	def.height_range = 0.0
	return def


static func _fill_uniform(image: Image, height_m: int) -> void:
	var grey := _height_to_grey(height_m)
	image.fill(Color(grey, grey, grey))


static func _write_world_heights(image: Image, world_heights: Dictionary) -> void:
	var size := image.get_width()
	for world_col: Vector2i in world_heights:
		var px := wrapi(world_col.x + size / 2, 0, size)
		var pz := wrapi(world_col.y + size / 2, 0, size)
		var grey := _height_to_grey(int(world_heights[world_col]))
		image.set_pixel(px, pz, Color(grey, grey, grey))


static func _height_to_grey(height_m: int) -> float:
	return (float(height_m) - HEIGHT_START) / HEIGHT_RANGE
