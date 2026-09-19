extends GdUnitTestSuite
## Test suite for ContentDirLoader (subsystems/core/content_dir_loader.gd), the
## shared recursive content-directory scanner behind ItemDB, EnemyLibrary,
## CropLibrary, ColonistNeeds, BuildLibrary, and BlockLibrary.
## Content-agnostic per CLAUDE.md: fixture dirs under user://, never real
## data/ content.

const Loader := preload("res://subsystems/core/content_dir_loader.gd")


func test_find_resource_paths_recurses_into_subdirectories() -> void:
	var dir := _make_fixture_dir("paths")
	_write_def(dir + "a.tres", "a")
	_write_def(dir + "sub/b.tres", "b")
	_write_def(dir + "sub/deeper/c.tres", "c")

	var paths := Loader.find_resource_paths(dir)

	assert_int(paths.size()).is_equal(3)
	assert_bool(paths.has(dir + "a.tres")).is_true()
	assert_bool(paths.has(dir + "sub/b.tres")).is_true()
	assert_bool(paths.has(dir + "sub/deeper/c.tres")).is_true()


func test_find_resource_paths_returns_empty_for_missing_dir() -> void:
	var paths := Loader.find_resource_paths("user://fixture_cdl_does_not_exist/")
	assert_int(paths.size()).is_equal(0)


func test_load_by_id_indexes_resources_recursively_by_id() -> void:
	var dir := _make_fixture_dir("index")
	_write_def(dir + "root.tres", "root_enemy")
	_write_def(dir + "melee/brawler.tres", "melee_enemy")

	var loaded := Loader.load_by_id(dir, func(res: Variant) -> bool: return res is EnemyDef)

	assert_int(loaded.size()).is_equal(2)
	assert_bool(loaded.has("root_enemy")).is_true()
	assert_bool(loaded.has("melee_enemy")).is_true()
	assert_object(loaded["melee_enemy"]).is_instanceof(EnemyDef)


func test_load_by_id_skips_empty_id_without_dropping_siblings() -> void:
	var dir := _make_fixture_dir("emptyid")
	_write_def(dir + "valid.tres", "valid_enemy")
	_write_def(dir + "sub/no_id.tres", "")

	var loaded := Loader.load_by_id(dir, func(res: Variant) -> bool: return res is EnemyDef)

	assert_int(loaded.size()).is_equal(1)
	assert_bool(loaded.has("valid_enemy")).is_true()


func test_load_by_id_filters_out_resources_failing_the_type_predicate() -> void:
	var dir := _make_fixture_dir("typefilter")
	_write_def(dir + "enemy.tres", "typed_enemy")

	var loaded := Loader.load_by_id(dir, func(res: Variant) -> bool: return res is ItemDef)

	assert_int(loaded.size()).is_equal(0)


func _make_fixture_dir(tag: String) -> String:
	var dir := "user://fixture_cdl_%s/" % tag
	# Clears leftovers from a prior run so recursion counts stay exact —
	# these fixtures nest subdirectories, unlike the flat dirs in
	# enemy_def_fixtures.gd / rotation_fixtures.gd, so a plain top-level
	# file sweep isn't enough.
	_clear_dir_recursive(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


func _clear_dir_recursive(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not fname.begins_with("."):
			var full_path := dir_path.path_join(fname)
			if dir.current_is_dir():
				_clear_dir_recursive(full_path)
				DirAccess.remove_absolute(full_path)
			else:
				dir.remove(fname)
		fname = dir.get_next()
	dir.list_dir_end()


func _write_def(rel_path: String, enemy_id: String) -> void:
	var full_dir := rel_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(full_dir)
	var def := EnemyDef.new()
	def.id = enemy_id
	def.display_name = enemy_id
	var err := ResourceSaver.save(def, rel_path)
	assert(err == OK, "fixture save failed at %s (err %d)" % [rel_path, err])
