extends GdUnitTestSuite

## BlockLibrary's per-block wading lookup: how much a body's lower torso is slowed while inside a
## block. Fluids carry the multiplier on their BlockDef; solids and air never slow anyone.
## Content-agnostic: the defs are written to a fixture dir, never data/blocks/.

const Fixtures := preload("res://test/helpers/rotation_fixtures.gd")

const FLUID_ID := "test_fluid"
const SOLID_ID := "test_solid"
const FLUID_DRAG := 0.4

const _FIXTURE_DIR := "user://fixture_blocks_wading/"


func after_test() -> void:
	# _library() writes into a fixed user:// fixture dir every test; remove it
	# so a crashed or interrupted run leaves nothing behind (Step 9).
	_remove_fixture_dir(_FIXTURE_DIR)


func test_a_fluid_reports_its_own_wading_multiplier() -> void:
	# Break caught: a fluid ignoring its def (the old code hardcoded one drag for one block id).
	var lib := _library()

	assert_float(lib.get_wading_speed_mult(FLUID_ID)).is_equal_approx(FLUID_DRAG, 0.0001)


func test_a_solid_never_slows_even_if_its_def_carries_a_multiplier() -> void:
	# Break caught: a solid block (the torso cell overlapping a wall) dragging the player because
	# the multiplier is read without checking that the block is a fluid. The solid's def carries a
	# trap value of 0.1 that must be ignored.
	var lib := _library()

	assert_float(lib.get_wading_speed_mult(SOLID_ID)).is_equal(1.0)


func test_air_and_unknown_blocks_do_not_slow() -> void:
	# Break caught: an empty cell or an id the library doesn't know crashing or slowing the player.
	var lib := _library()

	assert_float(lib.get_wading_speed_mult("")).is_equal(1.0)
	assert_float(lib.get_wading_speed_mult("not_a_block")).is_equal(1.0)


## Auxiliary: A library over a fixture dir holding one fluid (with a multiplier) and one solid
## (with a trap multiplier).
func _library() -> BlockLibrary:
	var dir := _FIXTURE_DIR
	DirAccess.make_dir_recursive_absolute(dir)
	var existing := DirAccess.open(dir)
	if existing != null:
		for file_name in existing.get_files():
			existing.remove(file_name)
	_write_def(dir + "a_fluid.tres", FLUID_ID, true, FLUID_DRAG)
	_write_def(dir + "b_solid.tres", SOLID_ID, false, 0.1)
	return BlockLibrary.new(dir)


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


func _write_def(path: String, block_id: String, fluid: bool, wading: float) -> void:
	var def := BlockDef.new()
	def.id = block_id
	def.display_name = block_id
	def.mesh = Fixtures.wedge_mesh()
	def.is_fluid = fluid
	def.wading_speed_mult = wading
	var err := ResourceSaver.save(def, path)
	assert_int(err).is_equal(OK)
