class_name SuiteMapRepositoryTest
extends GdUnitTestSuite
## Invariant tests for MapRepository disk operations and queries.

const Sandbox = preload("res://test/helpers/map_editor_sandbox.gd")

const TEST_MAP_ID := "zz_sandbox_repo_test"
const TEST_NOISE_MAP_ID := "zz_sandbox_repo_noise"
const TEST_NONE_MAP_ID := "zz_sandbox_repo_none"


func before_test() -> void:
	Sandbox.remove_map(TEST_MAP_ID)
	Sandbox.remove_map(TEST_NOISE_MAP_ID)
	Sandbox.remove_map(TEST_NONE_MAP_ID)


func after_test() -> void:
	Sandbox.remove_map(TEST_MAP_ID)
	Sandbox.remove_map(TEST_NOISE_MAP_ID)
	Sandbox.remove_map(TEST_NONE_MAP_ID)


func test_create_map_files_and_scan_maps() -> void:
	var payload := Sandbox.heightmap_payload(TEST_MAP_ID)
	var scene_path := MapRepository.create_map_files(payload, null)

	var expected_path := MapRepository.MAPS_DIR + TEST_MAP_ID + "/map.tscn"
	assert_str(scene_path).is_equal(expected_path)
	assert_bool(FileAccess.file_exists(scene_path)).is_true()
	assert_bool(FileAccess.file_exists(MapRepository.MAPS_DIR + TEST_MAP_ID + "/map_def.tres")).is_true()
	assert_bool(FileAccess.file_exists(MapRepository.MAPS_DIR + TEST_MAP_ID + "/terrain_gen.tres")).is_true()

	var maps := MapRepository.scan_maps()
	var found := false
	for m in maps:
		if m != null and m.id == TEST_MAP_ID:
			found = true
			break
	assert_bool(found).is_true()


func test_create_map_files_invalid_id_rejected() -> void:
	var invalid_id := "Invalid-Name-Capital"
	var payload := Sandbox.heightmap_payload(invalid_id)
	var scene_path := MapRepository.create_map_files(payload, null)

	assert_str(scene_path).is_empty()
	assert_bool(DirAccess.dir_exists_absolute(MapRepository.MAPS_DIR + invalid_id + "/")).is_false()


func test_create_map_files_existing_map_rejected() -> void:
	var payload := Sandbox.heightmap_payload(TEST_MAP_ID)
	var first_path := MapRepository.create_map_files(payload, null)
	assert_str(first_path).is_not_empty()

	var duplicate_path := MapRepository.create_map_files(payload, null)
	assert_str(duplicate_path).is_empty()


func test_delete_map_removes_folder_and_scan() -> void:
	var payload := Sandbox.heightmap_payload(TEST_MAP_ID)
	var scene_path := MapRepository.create_map_files(payload, null)
	assert_str(scene_path).is_not_empty()

	var dir_path := MapRepository.MAPS_DIR + TEST_MAP_ID + "/"
	assert_bool(DirAccess.dir_exists_absolute(dir_path)).is_true()

	var deleted := MapRepository.delete_map(TEST_MAP_ID)
	assert_bool(deleted).is_true()
	assert_bool(DirAccess.dir_exists_absolute(dir_path)).is_false()

	var maps := MapRepository.scan_maps()
	var found := false
	for m in maps:
		if m != null and m.id == TEST_MAP_ID:
			found = true
			break
	assert_bool(found).is_false()


func test_delete_map_nonexistent_returns_false() -> void:
	var deleted := MapRepository.delete_map("zz_sandbox_nonexistent_id_abc")
	assert_bool(deleted).is_false()


func test_scan_noise_defs_excludes_heightmap_defs() -> void:
	var defs := MapRepository.scan_noise_defs()
	assert_bool(defs.is_empty()).is_false()

	var has_default := false
	var has_heightmap_def := false
	for entry in defs:
		assert_str(entry.get("id", "")).is_not_empty()
		assert_str(entry.get("path", "")).is_not_empty()
		if entry["id"] == "ground_default":
			has_default = true
		if entry["id"] == "heightmap_valley":
			has_heightmap_def = true

	assert_bool(has_default).is_true()
	assert_bool(has_heightmap_def).is_false()


func test_create_map_files_terrain_mode_none() -> void:
	var payload := Sandbox.blocky_only_payload(TEST_NONE_MAP_ID)
	var scene_path := MapRepository.create_map_files(payload, null)
	assert_str(scene_path).is_not_empty()

	var def_path := MapRepository.MAPS_DIR + TEST_NONE_MAP_ID + "/map_def.tres"
	assert_bool(FileAccess.file_exists(def_path)).is_true()

	var def := load(def_path) as MapDef
	assert_object(def).is_not_null()
	assert_object(def.terrain_gen).is_null()
