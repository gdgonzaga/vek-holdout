class_name SuiteMapTerrainAuthoringTest
extends GdUnitTestSuite

const Sandbox = preload("res://test/helpers/map_editor_sandbox.gd")
const MTA = preload("res://tools/map_editor/map_terrain_authoring.gd")

const FIXTURE_DIR: String = "user://map_terrain_authoring_test/"
const MAPS_FIXTURE_DIR: String = "user://map_terrain_authoring_test/maps/"


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(MAPS_FIXTURE_DIR + "m1")


func after_test() -> void:
	for f in DirAccess.get_files_at(MAPS_FIXTURE_DIR + "m1"):
		DirAccess.remove_absolute(MAPS_FIXTURE_DIR + "m1/" + f)
	for f in DirAccess.get_files_at(FIXTURE_DIR):
		DirAccess.remove_absolute(FIXTURE_DIR + f)


func test_shared_def_is_not_map_owned_and_is_localized_by_copy() -> void:
	var shared := Sandbox.save_noise_def(FIXTURE_DIR + "shared.tres", 42, 0.02)
	assert_bool(MTA.is_map_owned(shared, MAPS_FIXTURE_DIR, "m1")).is_false()

	var owned := MTA.ensure_map_owned(shared, "m1")
	assert_object(owned).is_not_same(shared)
	assert_int(owned.noise_seed).is_equal(42)

	MTA.apply_edits(owned, {"noise_seed": 999})
	assert_int(shared.noise_seed).is_equal(42)


func test_ensure_map_owned_returns_same_object_when_already_owned() -> void:
	var def := TerrainGenDef.new()
	MTA.persist_owned(def, MAPS_FIXTURE_DIR, "m1")
	assert_bool(MTA.is_map_owned(def, MAPS_FIXTURE_DIR, "m1")).is_true()
	assert_object(MTA.ensure_map_owned(def, "m1")).is_same(def)


func test_persist_owned_makes_load_return_the_saved_instance() -> void:
	var first := TerrainGenDef.new()
	first.noise_seed = 1
	MTA.persist_owned(first, MAPS_FIXTURE_DIR, "m1")

	var second := TerrainGenDef.new()
	second.noise_seed = 2
	MTA.persist_owned(second, MAPS_FIXTURE_DIR, "m1")

	var loaded := load(MTA.map_terrain_path(MAPS_FIXTURE_DIR, "m1")) as TerrainGenDef
	assert_object(loaded).is_same(second)
	assert_int(loaded.noise_seed).is_equal(2)


func test_apply_edits_applies_span_to_heightmap_defs_and_noise_to_noise_defs() -> void:
	var noise := TerrainGenDef.new()
	noise.noise_seed = 5
	noise.height_start = -3.0
	MTA.apply_edits(noise, {"height_start": -8.0, "noise_seed": 9})
	# A noise def keeps its height band; only seed and frequency are editable.
	assert_float(noise.height_start).is_equal(-3.0)
	assert_int(noise.noise_seed).is_equal(9)

	var heightmap_def := TerrainGenDef.new()
	heightmap_def.noise_seed = 5
	heightmap_def.height_start = -3.0
	heightmap_def.heightmap = ImageTexture.create_from_image(Image.create(16, 16, false, Image.FORMAT_L8))
	MTA.apply_edits(heightmap_def, {"height_start": -8.0, "noise_seed": 9})
	assert_float(heightmap_def.height_start).is_equal(-8.0)
	assert_int(heightmap_def.noise_seed).is_equal(5)


func test_apply_edits_with_no_keys_changes_nothing() -> void:
	var def := TerrainGenDef.new()
	def.noise_seed = 5
	def.noise_frequency = 0.0125
	def.height_start = -3.0
	def.height_range = 9.0
	MTA.apply_edits(def, {})
	assert_int(def.noise_seed).is_equal(5)
	assert_float(def.noise_frequency).is_equal(0.0125)
	assert_float(def.height_start).is_equal(-3.0)
	assert_float(def.height_range).is_equal(9.0)


func test_build_heightmap_def_carries_span_and_embeds_image() -> void:
	var image := Image.create(32, 32, false, Image.FORMAT_RGB8)
	image.fill(Color(0.5, 0.5, 0.5))
	var def := MTA.build_heightmap_def("m1", image, -7.0, 21.0, false)
	assert_float(def.height_start).is_equal(-7.0)
	assert_float(def.height_range).is_equal(21.0)
	assert_object(def.heightmap).is_not_null()
	assert_bool(def.heightmap is ImageTexture).is_true()


func test_apply_water_ignores_null_def() -> void:
	# The guard returns before touching anything; there is no def field left
	# to inspect, so the observable is simply that this call raises nothing.
	MTA.apply_water(null, true, -2.0)


func test_apply_water_sets_the_toggle_and_level_on_a_valid_def() -> void:
	var def := TerrainGenDef.new()
	def.water_enabled = false
	def.water_level = 0.0
	MTA.apply_water(def, true, 3.0)
	assert_bool(def.water_enabled).is_true()
	assert_float(def.water_level).is_equal(3.0)
