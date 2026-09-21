extends GdUnitTestSuite

## TerrainHeightSampler: the one source of "how high is the ground at column
## (x, z)" shared by SmoothGrid (strata depth) and WaterGenerator (shoreline),
## so water and ground can never disagree about where the bank is.

const HeightFixtures := preload("res://test/helpers/height_fixtures.gd")


func test_from_def_null_returns_null() -> void:
	assert_object(TerrainHeightSampler.from_def(null)).is_null()


func test_noise_def_reads_flat_height_and_has_no_heightmap_image() -> void:
	var sampler := TerrainHeightSampler.from_def(HeightFixtures.make_flat_noise_def(-7.0))

	assert_object(sampler).is_not_null()
	assert_object(sampler.get_heightmap_image()).is_null()
	assert_float(sampler.sample_height(0, 0)).is_equal_approx(-7.0, 0.0001)
	assert_float(sampler.sample_height(-13, 40)).is_equal_approx(-7.0, 0.0001)


func test_noise_sample_stays_inside_def_span() -> void:
	var def := TerrainGenDef.new()
	def.height_start = -3.0
	def.height_range = 9.0
	def.noise_seed = 4242
	def.noise_frequency = 0.05
	var sampler := TerrainHeightSampler.from_def(def)

	for x in range(-20, 20, 7):
		var h := sampler.sample_height(x, x * 2)
		assert_float(h).is_between(-3.0, 6.0)


func test_heightmap_sample_is_centered_on_world_origin() -> void:
	# 4x4 image: world (0,0) is pixel (2,2); world (-2,-2) is pixel (0,0).
	var def := HeightFixtures.make_heightmap_def(4, {
		Vector2i(0, 0): 10,
		Vector2i(-2, -2): 3,
		Vector2i(1, 0): 11,
	}, 0)
	var sampler := TerrainHeightSampler.from_def(def)

	assert_float(sampler.sample_height(0, 0)).is_equal_approx(10.0, 0.0001)
	assert_float(sampler.sample_height(-2, -2)).is_equal_approx(3.0, 0.0001)
	assert_float(sampler.sample_height(1, 0)).is_equal_approx(11.0, 0.0001)


func test_heightmap_sample_wraps_past_the_image_edge() -> void:
	var def := HeightFixtures.make_heightmap_def(4, {Vector2i(-2, -2): 3}, 0)
	var sampler := TerrainHeightSampler.from_def(def)

	# One full image width away in either axis lands on the same pixel.
	assert_float(sampler.sample_height(2, -2)).is_equal_approx(3.0, 0.0001)
	assert_float(sampler.sample_height(-2, 2)).is_equal_approx(3.0, 0.0001)
	assert_float(sampler.sample_height(-6, -6)).is_equal_approx(3.0, 0.0001)


func test_heightmap_sample_reads_snapped_whole_meter_height() -> void:
	# 0.052 * 100 = 5.2 m authored; the ground snaps to 5.0 m, and so must the sampler.
	var def := TerrainGenDef.new()
	def.height_start = 0.0
	def.height_range = 100.0
	var rgb := Image.create(2, 2, false, Image.FORMAT_RGB8)
	rgb.fill(Color(0.052, 0.052, 0.052))
	def.heightmap = ImageTexture.create_from_image(rgb)
	var sampler := TerrainHeightSampler.from_def(def)

	assert_float(sampler.sample_height(0, 0)).is_equal_approx(5.0, 0.01)


## prepare_heightmap_image: whatever the source texture's format, callers
## receive Image.FORMAT_RF (snapped to whole-meter physical heights).
func test_prepare_heightmap_image_normalizes_and_snaps() -> void:
	var def := TerrainGenDef.new()
	def.height_start = 0.0
	def.height_range = 100.0
	var rgb := Image.create(2, 2, false, Image.FORMAT_RGB8)
	# Value of 0.052 * 100 = 5.2 meters -> snaps to 5.0 meters -> 0.05 pixel value
	rgb.fill(Color(0.052, 0.052, 0.052))
	def.heightmap = ImageTexture.create_from_image(rgb)

	var prepared: Image = TerrainHeightSampler.prepare_heightmap_image(def)
	assert_that(prepared).is_not_null()
	assert_int(prepared.get_format()).is_equal(Image.FORMAT_RF)
	assert_float(prepared.get_pixel(0, 0).r).is_equal_approx(0.05, 0.001)


## prepare_heightmap_image: null def or null heightmap stays null so
## the caller falls back to the noise path.
func test_prepare_heightmap_image_null_and_passthrough() -> void:
	assert_that(TerrainHeightSampler.prepare_heightmap_image(null)).is_null()
	var def := TerrainGenDef.new()
	assert_that(TerrainHeightSampler.prepare_heightmap_image(def)).is_null()
