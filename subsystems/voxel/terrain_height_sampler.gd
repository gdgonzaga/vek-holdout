class_name TerrainHeightSampler
extends RefCounted
## The one source of "how high is the natural ground at world column (x, z)".
##
## SmoothGrid (strata depth, pristine height) and WaterGenerator (shoreline)
## both read through this, so the water and the ground can never disagree about
## where the bank is. Heightmap defs read the image snapped to whole meters (the
## same image the smooth generator meshes); noise defs read a FastNoiseLite built
## with the generator's exact seed and frequency (F13 closed form).
##
## Immutable after construction, so one instance is safe to read from voxel
## generator worker threads.

var _def: TerrainGenDef = null
var _image: Image = null
var _noise: FastNoiseLite = null


# =================
# Primary Functions
# =================

## Sampler for the def, or null when there is no def (the map has no natural terrain).
static func from_def(def: TerrainGenDef) -> TerrainHeightSampler:
	if def == null:
		return null
	var sampler := TerrainHeightSampler.new()
	sampler._def = def
	# Snapped heightmap pixels for image-driven defs; null means this def is on the noise path.
	sampler._image = prepare_heightmap_image(def)
	if sampler._image == null:
		# Noise path: mirror the generator's seed and frequency so both describe one surface.
		sampler._noise = _make_noise(def)
	return sampler


## Natural ground height in meters at integer world column (x, z), or NAN when
## the image is empty. Voxel samples sit at integer coordinates, so a blocky
## cell (x, z) spans the four columns (x, z) (x+1, z) (x, z+1) (x+1, z+1).
func sample_height(x: int, z: int) -> float:
	if _image != null:
		# Wrapped pixel read: image origin is the world origin, repeating past the edge.
		return _sample_image(x, z)
	# Closed-form noise read: no image, so the def's seed and span give the height directly.
	return _sample_noise(x, z)


## Prepared heightmap image the smooth generator consumes, or null on the noise path.
func get_heightmap_image() -> Image:
	return _image


## Heightmap pixels as the generator wants them: uncompressed, float, and
## snapped to whole-meter physical heights. Null def or null heightmap gives
## null (the caller falls back to noise); unreadable pixels also give null and
## the error is reported here.
static func prepare_heightmap_image(def: TerrainGenDef) -> Image:
	if def == null or def.heightmap == null:
		return null
	# Readable pixels regardless of the source texture's format or compression.
	var image := _read_uncompressed_image(def.heightmap)
	if image == null:
		return null
	# Editor L8 quantization leaves ~0.2 m offsets; snapping recovers the authored integer heights.
	_snap_to_whole_meters(image, def)
	return image


# ===================
# Auxiliary Functions
# ===================

static func _make_noise(def: TerrainGenDef) -> FastNoiseLite:
	## Auxiliary: Builds the noise sampler that matches VoxelGeneratorNoise2D's inputs.
	var noise := FastNoiseLite.new()
	noise.seed = def.noise_seed
	noise.frequency = def.noise_frequency
	return noise


static func _read_uncompressed_image(texture: Texture2D) -> Image:
	## Auxiliary: Pixel data of the texture, decompressed; null (with an error) when unreadable.
	var image := texture.get_image()
	if image == null:
		push_error("TerrainHeightSampler: terrain_gen.heightmap has no readable pixels — falling back to noise")
		return null
	if image.is_compressed() and image.decompress() != OK:
		push_error("TerrainHeightSampler: terrain_gen.heightmap is compressed and cannot decompress — falling back to noise")
		return null
	return image


static func _snap_to_whole_meters(image: Image, def: TerrainGenDef) -> void:
	## Auxiliary: Rewrites every pixel so it encodes the nearest whole-meter height (RF format).
	image.convert(Image.FORMAT_RF)
	for y: int in image.get_height():
		for x: int in image.get_width():
			var grey := _snapped_grey(image.get_pixel(x, y).r, def)
			image.set_pixel(x, y, Color(grey, grey, grey, 1.0))


static func _snapped_grey(grey: float, def: TerrainGenDef) -> float:
	## Auxiliary: Grey level of the whole meter nearest to the height this grey level encodes.
	var height: float = def.height_start + grey * def.height_range
	return (roundf(height) - def.height_start) / def.height_range


func _sample_image(x: int, z: int) -> float:
	## Auxiliary: Height at world column (x, z) from the snapped image, wrapping at the edges.
	var size := _image.get_size()
	if size.x <= 0 or size.y <= 0:
		return NAN
	var px := wrapi(x + size.x / 2, 0, size.x)
	var pz := wrapi(z + size.y / 2, 0, size.y)
	return _def.height_start + _image.get_pixel(px, pz).r * _def.height_range


func _sample_noise(x: int, z: int) -> float:
	## Auxiliary: Height at world column (x, z) from the def's noise field.
	var n: float = _noise.get_noise_2d(x, z)
	return _def.height_start + (n * 0.5 + 0.5) * _def.height_range
