extends GdUnitTestSuite

## Test suite verifying discrete world bounds invariants for colony maps.
## Checks MapDef helpers, Map boundary colliders generation, SpawnHelpers clamping,
## and pathfinding bounds pruning.


func test_map_def_bounds_defaults_and_helpers() -> void:
	var def := MapDef.new()
	auto_free(def)

	var default_bounds := AABB(Vector3(-96.0, -48.0, -96.0), Vector3(192.0, 64.0, 192.0))
	assert_object(def.world_bounds).is_equal(default_bounds)
	assert_float(def.get_horizontal_size().x).is_equal(192.0)
	assert_float(def.get_horizontal_size().y).is_equal(192.0)
	assert_float(def.get_depth()).is_equal(48.0)
	assert_float(def.get_ceiling()).is_equal(16.0)


func test_map_bounds_propagation_and_colliders() -> void:
	var map := preload("res://subsystems/maps/map_template.tscn").instantiate() as Map
	add_child(map)
	auto_free(map)

	var custom_bounds := AABB(Vector3(-64.0, -32.0, -64.0), Vector3(128.0, 48.0, 128.0))
	map.set_world_bounds(custom_bounds)

	assert_object(map.get_world_bounds()).is_equal(custom_bounds)
	assert_object(map.blocky_grid.get_world_bounds()).is_equal(custom_bounds)

	var boundaries := map.get_node_or_null("MapBoundaries") as Node3D
	assert_that(boundaries).is_not_null()

	var children := boundaries.get_children()
	# Expecting 5 barriers: Floor, West, East, North, South
	assert_int(children.size()).is_equal(5)

	var floor_body := boundaries.get_node_or_null("FloorBarrier") as StaticBody3D
	assert_that(floor_body).is_not_null()
	assert_int(floor_body.collision_layer).is_equal(1)
	assert_int(floor_body.collision_mask).is_equal(0)

	var col := floor_body.get_node_or_null("CollisionShape") as CollisionShape3D
	assert_that(col).is_not_null()
	var box := col.shape as BoxShape3D
	assert_that(box).is_not_null()


func test_spawn_helpers_clamps_out_of_bounds_markers() -> void:
	var map := preload("res://subsystems/maps/map_template.tscn").instantiate() as Map
	add_child(map)
	auto_free(map)

	var test_bounds := AABB(Vector3(-50.0, -20.0, -50.0), Vector3(100.0, 40.0, 100.0))
	map.set_world_bounds(test_bounds)

	var spawn_points := map.find_child("SpawnPoints") as Node3D
	assert_that(spawn_points).is_not_null()

	# Reposition player spawn far out-of-bounds at X = 200, Z = 200
	var player_marker := spawn_points.get_node_or_null("PlayerSpawn") as Marker3D
	if player_marker == null:
		player_marker = Marker3D.new()
		player_marker.name = "PlayerSpawn"
		spawn_points.add_child(player_marker)
	player_marker.position = Vector3(200.0, 0.0, 200.0)

	# Create enemy spawn far out-of-bounds at X = -300
	var enemy_marker := Marker3D.new()
	enemy_marker.name = "EnemySpawn_Far"
	enemy_marker.position = Vector3(-300.0, 0.0, 0.0)
	spawn_points.add_child(enemy_marker)

	var spawns := SpawnHelpers.read_spawns(map)

	# Clamped with inward margin (1.0)
	var max_x := test_bounds.position.x + test_bounds.size.x - 1.0
	var min_x := test_bounds.position.x + 1.0

	assert_float(spawns.player.x).is_equal_approx(max_x, 0.01)
	assert_float(spawns.player.z).is_equal_approx(max_x, 0.01)

	var enemy_pos: Vector3 = spawns.enemies[0]
	assert_float(enemy_pos.x).is_equal_approx(min_x, 0.01)


func test_map_wiring_walkability_respects_world_bounds() -> void:
	var map := preload("res://subsystems/maps/map_template.tscn").instantiate() as Map
	add_child(map)
	auto_free(map)

	var test_bounds := AABB(Vector3(-20.0, -10.0, -20.0), Vector3(40.0, 20.0, 40.0))
	map.set_world_bounds(test_bounds)

	var walkability := MapWiring._compose_walkability(map)
	# Cell outside bounds must return false
	assert_bool(walkability.call(Vector3i(50, 0, 0))).is_false()
	assert_bool(walkability.call(Vector3i(-50, 0, 0))).is_false()
	assert_bool(walkability.call(Vector3i(0, 50, 0))).is_false()


func test_pathfinder_prunes_out_of_bounds() -> void:
	var pathfinder := VoxelPathfinder.new()
	auto_free(pathfinder)

	# Set a mock walkability predicate that accepts everything
	pathfinder.set_walkability(func(_cell: Vector3i) -> bool: return true)

	var bounds := AABB(Vector3(-10.0, -10.0, -10.0), Vector3(20.0, 20.0, 20.0))
	pathfinder.set_world_bounds(bounds)

	# Inside cell
	assert_bool(pathfinder.is_walkable(Vector3i(0, 0, 0))).is_true()
	assert_bool(pathfinder.is_walkable(Vector3i(5, 5, 5))).is_true()

	# Outside cells
	assert_bool(pathfinder.is_walkable(Vector3i(15, 0, 0))).is_false()
	assert_bool(pathfinder.is_walkable(Vector3i(-15, 0, 0))).is_false()
	assert_bool(pathfinder.is_walkable(Vector3i(0, 15, 0))).is_false()
