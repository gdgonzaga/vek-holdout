extends GdUnitTestSuite

## System logic tests for fluid block registration, fixed indexing, and mesher attributes.

const Fixtures := preload("res://test/helpers/rotation_fixtures.gd")
const HeightFixtures := preload("res://test/helpers/height_fixtures.gd")

## Every user:// fixture dir a test in this suite writes into; after_test
## sweeps all of them so a crashed or interrupted run leaves nothing behind.
const _FIXTURE_DIRS := [
	"user://fixture_blocks_fixed_idx/",
	"user://fixture_blocks_fluid_query/",
	"user://fixture_blocks_water_wiring/",
]


func after_test() -> void:
	for dir_path: String in _FIXTURE_DIRS:
		_remove_fixture_dir(dir_path)


## Auxiliary: Removes a fixture dir and its files, tolerating a missing dir
func _remove_fixture_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not fname.begins_with("."):
			dir.remove(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(dir_path.trim_suffix("/"))


## BlockyGrid mounting a fixture library, so the wiring test needs no data/blocks/.
class FixtureBlockyGrid extends BlockyGrid:
	var fixture_dir: String = ""

	func _make_library() -> BlockLibrary:
		return BlockLibrary.new(fixture_dir)


func test_fixed_index_ordering() -> void:
	var dir := "user://fixture_blocks_fixed_idx/"
	DirAccess.make_dir_recursive_absolute(dir)
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			d.remove(f)

	# Write defs where alphabetical order (a, b, c) conflicts with fixed_index (3, 1, 2).
	_write_custom_def(dir + "a_third.tres", "third", 3, false)
	_write_custom_def(dir + "b_first.tres", "first", 1, false)
	_write_custom_def(dir + "c_second.tres", "second", 2, true)

	var lib := BlockLibrary.new(dir)
	# Verify that fixed_index dictates the base index rather than filename sorting.
	assert_int(lib.get_index("first")).is_equal(1)
	assert_int(lib.get_index("second")).is_equal(2)
	assert_int(lib.get_index("third")).is_equal(3)


func test_fluid_block_properties() -> void:
	var def := BlockDef.new()
	def.id = "fluid_fixture"
	def.display_name = "Fluid Fixture"
	def.mesh = Fixtures.wedge_mesh()
	def.is_fluid = true
	def.collision_enabled = false
	def.transparency_index = 1
	def.culls_neighbors_of_same_type = true

	var model := VoxelLibraryGenerator.create_block_model(def, 0)
	assert_object(model).is_not_null()
	if "collision_enabled_0" in model:
		assert_bool(bool(model.get("collision_enabled_0"))).is_false()
	if "transparency_index" in model:
		assert_int(int(model.get("transparency_index"))).is_equal(1)
	if "culls_neighbors_of_same_type" in model:
		assert_bool(bool(model.get("culls_neighbors_of_same_type"))).is_true()


func test_is_fluid_query() -> void:
	var dir := "user://fixture_blocks_fluid_query/"
	DirAccess.make_dir_recursive_absolute(dir)
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			d.remove(f)

	_write_custom_def(dir + "solid.tres", "solid", 1, false)
	_write_custom_def(dir + "fluid.tres", "fluid", 2, true)

	var lib := BlockLibrary.new(dir)
	var solid_idx := lib.get_index("solid")
	var fluid_idx := lib.get_index("fluid")

	assert_bool(lib.is_fluid(solid_idx)).is_false()
	assert_bool(lib.is_fluid(fluid_idx)).is_true()


func test_smooth_grid_surface_height_analytical_fallback() -> void:
	var grid := SmoothGrid.new()
	var gen := TerrainGenDef.new()
	gen.id = "test_gen"
	gen.height_start = -10.0
	gen.height_range = 20.0
	gen.noise_seed = 12345
	gen.noise_frequency = 0.01

	grid.terrain_gen = gen
	var h := grid.get_surface_height(0.0, 0.0)
	assert_bool(is_nan(h)).is_false()
	assert_float(h).is_greater_equal(-10.0)
	assert_float(h).is_less_equal(10.0)
	auto_free(grid)


func test_water_generator_does_not_exceed_water_level() -> void:
	var gen: WaterGenerator = auto_free(WaterGenerator.new())
	var def := TerrainGenDef.new()
	def.id = "test_gen"
	def.height_start = -10.0
	def.height_range = 0.0
	gen.setup(TerrainHeightSampler.from_def(def), -2.0, 14)

	var buf := VoxelBuffer.new()
	buf.create(1, 16, 1)
	gen._generate_block(buf, Vector3i(0, -16, 0), 0)

	# With water_level = -2.0, max_water_y is -3 (top face at -2.0).
	# world_y = -2 (buf y index 14) must be empty air (0).
	# world_y = -3 (buf y index 13) must be water (14).
	assert_int(buf.get_voxel(0, 14, 0, VoxelBuffer.CHANNEL_TYPE)).is_equal(0)
	assert_int(buf.get_voxel(0, 13, 0, VoxelBuffer.CHANNEL_TYPE)).is_equal(14)
	assert_int(buf.get_voxel(0, 6, 0, VoxelBuffer.CHANNEL_TYPE)).is_equal(14)
	assert_int(buf.get_voxel(0, 5, 0, VoxelBuffer.CHANNEL_TYPE)).is_equal(0)


func test_water_generator_skips_chunk_above_water_level() -> void:
	var gen: WaterGenerator = auto_free(WaterGenerator.new())
	var def := TerrainGenDef.new()
	def.id = "test_gen"
	def.height_start = -10.0
	def.height_range = 0.0
	gen.setup(TerrainHeightSampler.from_def(def), -2.0, 14)

	var buf := VoxelBuffer.new()
	buf.create(1, 16, 1)
	gen._generate_block(buf, Vector3i(0, 0, 0), 0)

	for y in 16:
		assert_int(buf.get_voxel(0, y, 0, VoxelBuffer.CHANNEL_TYPE)).is_equal(0)


func test_water_generator_dry_land_has_no_water() -> void:
	var gen: WaterGenerator = auto_free(WaterGenerator.new())
	var def := TerrainGenDef.new()
	def.id = "test_gen"
	def.height_start = 2.0
	def.height_range = 0.0
	gen.setup(TerrainHeightSampler.from_def(def), -2.0, 14)

	var buf := VoxelBuffer.new()
	buf.create(1, 16, 1)
	gen._generate_block(buf, Vector3i(0, -16, 0), 0)

	for y in 16:
		assert_int(buf.get_voxel(0, y, 0, VoxelBuffer.CHANNEL_TYPE)).is_equal(0)


## Water level -2.0 puts the water top at -2, so the highest water cell is y = -3.
## Buffer index = world y + 16 for the origin (x, -16, z) used below.
func test_water_generator_column_is_wet_when_any_corner_is_below_water_top() -> void:
	# Only corner (0,0) is low; cell (0,0) still gets water because the cube must
	# overshoot into the bank for the smooth ground to bury its edge.
	var def := HeightFixtures.make_heightmap_def(8, {Vector2i(0, 0): -6}, 5)
	var gen: WaterGenerator = auto_free(WaterGenerator.new())
	gen.setup(TerrainHeightSampler.from_def(def), -2.0, 14)

	var buf := VoxelBuffer.new()
	buf.create(2, 16, 1)
	gen._generate_block(buf, Vector3i(0, -16, 0), 0)

	assert_int(buf.get_voxel(0, 9, 0, VoxelBuffer.CHANNEL_TYPE)).is_equal(0)
	assert_int(buf.get_voxel(0, 10, 0, VoxelBuffer.CHANNEL_TYPE)).is_equal(14)
	assert_int(buf.get_voxel(0, 13, 0, VoxelBuffer.CHANNEL_TYPE)).is_equal(14)
	assert_int(buf.get_voxel(0, 14, 0, VoxelBuffer.CHANNEL_TYPE)).is_equal(0)
	# Cell (1,0) has no corner below the top: it stays dry all the way up.
	for y in 16:
		assert_int(buf.get_voxel(1, y, 0, VoxelBuffer.CHANNEL_TYPE)).is_equal(0)


func test_water_generator_column_is_dry_when_every_corner_is_at_or_above_water_top() -> void:
	# Ground exactly at the water top is not below it: no water.
	var def := HeightFixtures.make_heightmap_def(8, {
		Vector2i(0, 0): -2,
		Vector2i(1, 0): -2,
		Vector2i(0, 1): 3,
		Vector2i(1, 1): 3,
	}, 5)
	var gen: WaterGenerator = auto_free(WaterGenerator.new())
	gen.setup(TerrainHeightSampler.from_def(def), -2.0, 14)

	var buf := VoxelBuffer.new()
	buf.create(1, 16, 1)
	gen._generate_block(buf, Vector3i(0, -16, 0), 0)

	for y in 16:
		assert_int(buf.get_voxel(0, y, 0, VoxelBuffer.CHANNEL_TYPE)).is_equal(0)


func test_water_generator_fill_starts_at_the_lowest_corner() -> void:
	var def := HeightFixtures.make_heightmap_def(8, {
		Vector2i(0, 0): -4,
		Vector2i(1, 0): -9,
		Vector2i(0, 1): -5,
		Vector2i(1, 1): -7,
	}, 5)
	var gen: WaterGenerator = auto_free(WaterGenerator.new())
	gen.setup(TerrainHeightSampler.from_def(def), -2.0, 14)

	var buf := VoxelBuffer.new()
	buf.create(1, 16, 1)
	gen._generate_block(buf, Vector3i(0, -16, 0), 0)

	# Lowest corner is -9, so water spans world y -9 (index 7) up to -3 (index 13).
	assert_int(buf.get_voxel(0, 6, 0, VoxelBuffer.CHANNEL_TYPE)).is_equal(0)
	assert_int(buf.get_voxel(0, 7, 0, VoxelBuffer.CHANNEL_TYPE)).is_equal(14)
	assert_int(buf.get_voxel(0, 13, 0, VoxelBuffer.CHANNEL_TYPE)).is_equal(14)
	assert_int(buf.get_voxel(0, 14, 0, VoxelBuffer.CHANNEL_TYPE)).is_equal(0)


func test_water_generator_without_a_sampler_generates_nothing() -> void:
	var gen: WaterGenerator = auto_free(WaterGenerator.new())
	gen.setup(null, -2.0, 14)

	var buf := VoxelBuffer.new()
	buf.create(1, 16, 1)
	gen._generate_block(buf, Vector3i(0, -16, 0), 0)

	for y in 16:
		assert_int(buf.get_voxel(0, y, 0, VoxelBuffer.CHANNEL_TYPE)).is_equal(0)


## map.tscn readies BlockyGrid before SmoothGrid, yet the water generator must
## still read the smooth grid's own ground so the shoreline follows the bank.
func test_blocky_grid_water_generator_follows_the_smooth_grids_ground() -> void:
	var dir := "user://fixture_blocks_water_wiring/"
	DirAccess.make_dir_recursive_absolute(dir)
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	_write_custom_def(dir + "water.tres", "water", 14, true)

	var ground := HeightFixtures.make_heightmap_def(8, {Vector2i(0, 0): -6}, 5)
	ground.water_enabled = true
	ground.water_level = -2.0

	# Whole subtree built detached, blocky first, so both _ready calls run on tree entry in scene order.
	var root: Node3D = auto_free(Node3D.new())
	var blocky: FixtureBlockyGrid = auto_free(FixtureBlockyGrid.new())
	blocky.name = "BlockyGrid"
	blocky.fixture_dir = dir
	var blocky_terrain := VoxelTerrain.new()
	blocky_terrain.name = "VoxelTerrain"
	blocky.add_child(blocky_terrain)
	root.add_child(blocky)
	var smooth: SmoothGrid = auto_free(SmoothGrid.new())
	smooth.name = "SmoothGrid"
	smooth.terrain_gen = ground
	var smooth_terrain := VoxelTerrain.new()
	smooth_terrain.name = "VoxelTerrain"
	smooth.add_child(smooth_terrain)
	root.add_child(smooth)
	add_child(root)

	var generator: Resource = blocky.get_terrain().get("generator")
	assert_bool(generator is WaterGenerator).is_true()

	var buf := VoxelBuffer.new()
	buf.create(1, 16, 1)
	generator._generate_block(buf, Vector3i(0, -16, 0), 0)

	# Ground corner (0,0) sits at -6, so water fills world y -6..-3 (buffer index 10..13).
	assert_int(buf.get_voxel(0, 9, 0, VoxelBuffer.CHANNEL_TYPE)).is_equal(0)
	assert_int(buf.get_voxel(0, 10, 0, VoxelBuffer.CHANNEL_TYPE)).is_not_equal(0)
	assert_int(buf.get_voxel(0, 13, 0, VoxelBuffer.CHANNEL_TYPE)).is_not_equal(0)
	assert_int(buf.get_voxel(0, 14, 0, VoxelBuffer.CHANNEL_TYPE)).is_equal(0)


func _write_custom_def(path: String, block_id: String, fixed_idx: int, is_fluid: bool) -> void:
	var def := BlockDef.new()
	def.id = block_id
	def.display_name = block_id
	def.mesh = Fixtures.wedge_mesh()
	def.fixed_index = fixed_idx
	def.is_fluid = is_fluid
	if is_fluid:
		def.collision_enabled = false
		def.transparency_index = 1
		def.culls_neighbors_of_same_type = true
	var err := ResourceSaver.save(def, path)
	assert(err == OK, "fixture save failed at %s (err %d)" % [path, err])
