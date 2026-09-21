class_name SuiteSpawnAuthoringTest
extends GdUnitTestSuite
## Tests for SpawnAuthoring: binding, caching, placing, removing, and query operations
## on map spawn markers while ignoring non-spawn (furniture) markers.


func test_bind_caches_markers_and_ignores_furniture() -> void:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var spawn_points: Node3D = Node3D.new()
	spawn_points.name = "SpawnPoints"
	root.add_child(spawn_points)

	var p_spawn: Marker3D = Marker3D.new()
	p_spawn.name = SpawnMarkerRules.PLAYER_NAME
	p_spawn.position = Vector3(1, 2, 3)
	spawn_points.add_child(p_spawn)

	var c_spawn: Marker3D = Marker3D.new()
	c_spawn.name = "ColonistSpawn_2"
	c_spawn.position = Vector3(4, 5, 6)
	spawn_points.add_child(c_spawn)

	var e_spawn: Marker3D = Marker3D.new()
	e_spawn.name = "EnemySpawn_1"
	e_spawn.position = Vector3(7, 8, 9)
	spawn_points.add_child(e_spawn)

	var furniture: Marker3D = Marker3D.new()
	furniture.name = "Furniture_zz_0"
	furniture.position = Vector3(10, 11, 12)
	spawn_points.add_child(furniture)

	var spawns: SpawnAuthoring = SpawnAuthoring.new()
	spawns.bind(root)

	var c: Dictionary = spawns.counts()
	assert_bool(c["player"]).is_true()
	assert_int(c["colonists"]).is_equal(1)
	assert_int(c["enemies"]).is_equal(1)
	assert_object(p_spawn.get_node_or_null("SpawnVisualizer")).is_not_null()
	assert_object(c_spawn.get_node_or_null("SpawnVisualizer")).is_not_null()
	assert_object(e_spawn.get_node_or_null("SpawnVisualizer")).is_not_null()
	assert_object(furniture.get_node_or_null("SpawnVisualizer")).is_null()


func test_place_enemy_increments_numbered_name() -> void:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var spawn_points: Node3D = Node3D.new()
	spawn_points.name = "SpawnPoints"
	root.add_child(spawn_points)

	var e_spawn: Marker3D = Marker3D.new()
	e_spawn.name = "EnemySpawn_1"
	spawn_points.add_child(e_spawn)

	var spawns: SpawnAuthoring = SpawnAuthoring.new()
	spawns.bind(root)

	var marker: Marker3D = spawns.place(SpawnMarkerRules.Kind.ENEMY, Vector3(20, 0, 20))
	assert_object(marker).is_not_null()
	assert_str(marker.name).is_equal("EnemySpawn_2")
	assert_int(spawns.counts()["enemies"]).is_equal(2)
	assert_vector(marker.global_position).is_equal(Vector3(20, 0, 20))


func test_place_player_twice_reuses_single_marker() -> void:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var spawns: SpawnAuthoring = SpawnAuthoring.new()
	spawns.bind(root)

	var first: Marker3D = spawns.place(SpawnMarkerRules.Kind.PLAYER, Vector3(5, 0, 5))
	assert_object(first).is_not_null()
	assert_str(first.name).is_equal(SpawnMarkerRules.PLAYER_NAME)
	assert_vector(first.global_position).is_equal(Vector3(5, 0, 5))
	assert_bool(spawns.counts()["player"]).is_true()

	var second: Marker3D = spawns.place(SpawnMarkerRules.Kind.PLAYER, Vector3(10, 0, 10))
	assert_object(second).is_same(first)
	assert_vector(second.global_position).is_equal(Vector3(10, 0, 10))
	assert_bool(spawns.counts()["player"]).is_true()
	assert_vector(spawns.player_position()).is_equal(Vector3(10, 0, 10))


func test_remove_nearest_never_removes_furniture() -> void:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var spawn_points: Node3D = Node3D.new()
	spawn_points.name = "SpawnPoints"
	root.add_child(spawn_points)

	var furniture: Marker3D = Marker3D.new()
	furniture.name = "Furniture_zz_0"
	furniture.position = Vector3(1, 0, 1)
	spawn_points.add_child(furniture)

	var enemy: Marker3D = Marker3D.new()
	enemy.name = "EnemySpawn_1"
	enemy.position = Vector3(5, 0, 5)
	spawn_points.add_child(enemy)

	var spawns: SpawnAuthoring = SpawnAuthoring.new()
	spawns.bind(root)

	# Try removing nearest to furniture position; should ignore furniture and not remove anything
	var removed_kind: SpawnMarkerRules.Kind = spawns.remove_nearest(Vector3(1, 0, 1), 2.0)
	assert_int(removed_kind).is_equal(SpawnMarkerRules.Kind.NONE)
	assert_bool(is_instance_valid(furniture)).is_true()

	# Remove enemy when within distance
	removed_kind = spawns.remove_nearest(Vector3(5, 0, 5), 2.0)
	assert_int(removed_kind).is_equal(SpawnMarkerRules.Kind.ENEMY)
	assert_int(spawns.counts()["enemies"]).is_equal(0)


func test_enemy_spawns_and_unbind() -> void:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var spawns: SpawnAuthoring = SpawnAuthoring.new()
	spawns.bind(root)

	spawns.place(SpawnMarkerRules.Kind.ENEMY, Vector3(15, 2, 25))
	spawns.place(SpawnMarkerRules.Kind.PLAYER, Vector3(0, 1, 0))

	var list: Array[Dictionary] = spawns.enemy_spawns()
	assert_int(list.size()).is_equal(1)
	assert_vector(list[0]["pos"]).is_equal(Vector3(15, 2, 25))
	assert_int(list[0]["count"]).is_equal(1)

	spawns.unbind()
	var c: Dictionary = spawns.counts()
	assert_bool(c["player"]).is_false()
	assert_int(c["colonists"]).is_equal(0)
	assert_int(c["enemies"]).is_equal(0)
	assert_object(spawns.player_position()).is_null()
	assert_int(spawns.enemy_spawns().size()).is_equal(0)
