extends GdUnitTestSuite

## System logic tests for fluid block registration, fixed indexing, and mesher attributes.

const Fixtures := preload("res://test/helpers/rotation_fixtures.gd")


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
	grid.free()


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
