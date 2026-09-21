class_name SuiteSpawnMarkerRulesTest
extends GdUnitTestSuite


func test_kind_of_classifies_by_name() -> void:
	assert_int(SpawnMarkerRules.kind_of("PlayerSpawn")).is_equal(SpawnMarkerRules.Kind.PLAYER)
	assert_int(SpawnMarkerRules.kind_of("ColonistSpawn_3")).is_equal(SpawnMarkerRules.Kind.COLONIST)
	assert_int(SpawnMarkerRules.kind_of("EnemySpawn")).is_equal(SpawnMarkerRules.Kind.ENEMY)
	assert_int(SpawnMarkerRules.kind_of("Furniture_x_0")).is_equal(SpawnMarkerRules.Kind.NONE)
	assert_int(SpawnMarkerRules.kind_of("SpawnVisualizer")).is_equal(SpawnMarkerRules.Kind.NONE)


func test_next_index_continues_after_the_highest_suffix() -> void:
	assert_int(SpawnMarkerRules.next_index([], "EnemySpawn")).is_equal(1)
	assert_int(SpawnMarkerRules.next_index(["EnemySpawn_1", "EnemySpawn_4", "Other"], "EnemySpawn")).is_equal(5)
	# A bare legacy name without a numeric suffix still reserves index 1, so the next one is 2.
	assert_int(SpawnMarkerRules.next_index(["EnemySpawn"], "EnemySpawn")).is_equal(2)
