extends GdUnitTestSuite
## Test suite for EnemyDef schema and EnemyLibrary registry (ARCH combat.md).

const Fixtures := preload("res://test/helpers/enemy_def_fixtures.gd")


func test_enemy_def_defaults() -> void:
	var def: EnemyDef = auto_free(EnemyDef.new()) as EnemyDef
	assert_str(def.id).is_equal("")
	assert_str(def.display_name).is_equal("Enemy")
	assert_int(def.max_hp).is_equal(100)
	assert_int(def.max_durability).is_equal(0)
	assert_float(def.base_move_speed).is_equal_approx(5.0, 0.001)
	assert_float(def.detect_range).is_equal_approx(16.0, 0.001)
	assert_float(def.los_loss_timeout).is_equal_approx(5.0, 0.001)
	assert_object(def.behavior_tree).is_null()
	assert_object(def.attack_params).is_null()
	assert_object(def.loot_table).is_null()
	assert_array(def.moodlet_defs).is_empty()


func test_enemy_def_field_assignment() -> void:
	var def: EnemyDef = auto_free(EnemyDef.new()) as EnemyDef
	def.id = "test_enemy"
	def.max_hp = 140
	assert_str(def.id).is_equal("test_enemy")
	assert_int(def.max_hp).is_equal(140)


func test_library_loads_valid_defs_and_skips_empty_id() -> void:
	var dir := Fixtures.make_enemy_dir("basic")
	var lib: Node = auto_free(Fixtures.make_library(dir)) as Node
	assert_bool(lib.has_def("valid_enemy")).is_true()
	assert_int(lib.get_all_ids().size()).is_equal(1)


func test_library_get_def_returns_matching_resource() -> void:
	var dir := Fixtures.make_enemy_dir("getdef")
	var lib: Node = auto_free(Fixtures.make_library(dir)) as Node
	var def: EnemyDef = lib.get_def("valid_enemy")
	assert_object(def).is_not_null()
	assert_str(def.id).is_equal("valid_enemy")


func test_library_has_def_false_for_unknown_id() -> void:
	var dir := Fixtures.make_enemy_dir("unknown")
	var lib: Node = auto_free(Fixtures.make_library(dir)) as Node
	assert_bool(lib.has_def("does_not_exist")).is_false()


func test_library_get_all_defs_returns_only_loaded_enemy_defs() -> void:
	var dir := Fixtures.make_enemy_dir("alldefs")
	var lib: Node = auto_free(Fixtures.make_library(dir)) as Node
	var defs: Array[EnemyDef] = lib.get_all_defs()
	assert_int(defs.size()).is_equal(1)
	assert_object(defs[0]).is_instanceof(EnemyDef)


## Content-agnostic sanity check against the real EnemyLibrary autoload and
## whatever's actually authored under data/enemies/ (mirrors ItemDB's
## equivalent in suite_debug_item_spawn_test.gd) -- catches authoring
## mistakes (bad ext_resource paths, missing required fields) in real
## content .tres files without asserting on specific content IDs.
func test_real_enemy_library_defs_have_required_fields() -> void:
	var defs: Array[EnemyDef] = EnemyLibrary.get_all_defs()
	var ids: Array[String] = EnemyLibrary.get_all_ids()

	assert_int(defs.size()).is_equal(ids.size())
	for def in defs:
		assert_object(def).is_not_null()
		assert_bool(def.id != "").is_true()
		assert_bool(ids.has(def.id)).is_true()
		assert_bool(def.max_hp > 0).is_true()
		assert_bool(def.base_move_speed > 0.0).is_true()
