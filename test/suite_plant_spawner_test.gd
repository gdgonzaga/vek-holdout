class_name SuitePlantSpawnerTest
extends GdUnitTestSuite
## Unit tests for PlantSpawner, Furniture tags, and flora regeneration invariants.

const TEMPLATE_PATH: String = "res://subsystems/maps/map_template.tscn"


func _create_test_flora_def(id: String = "test_tree") -> FurnitureDef:
	var def: FurnitureDef = auto_free(FurnitureDef.new())
	def.id = id
	def.display_name = "Test Tree"
	def.dimensions = Vector3i(1, 1, 1)
	def.tags = ["live_flora", "tree"]
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 2.0, 1.0)
	def.mesh = mesh
	return def


func _create_test_non_flora_def(id: String = "test_crate") -> FurnitureDef:
	var def: FurnitureDef = auto_free(FurnitureDef.new())
	def.id = id
	def.display_name = "Test Crate"
	def.dimensions = Vector3i(1, 1, 1)
	def.tags = ["storage"]
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 1.0, 1.0)
	def.mesh = mesh
	return def


func _create_test_map() -> Map:
	var packed := load(TEMPLATE_PATH) as PackedScene
	var map: Map = auto_free(packed.instantiate() as Map)
	add_child(map)
	return map


func test_furniture_tag_methods_and_groups() -> void:
	var def := _create_test_flora_def()
	var furniture: Furniture = auto_free(Furniture.new())
	furniture.def = def
	furniture.def_id = def.id
	add_child(furniture)

	assert_bool(furniture.has_tag("live_flora")).is_true()
	assert_bool(furniture.has_tag("tree")).is_true()
	assert_bool(furniture.has_tag("non_existent")).is_false()
	assert_array(furniture.get_tags()).contains_exactly(["live_flora", "tree"])
	assert_bool(furniture.is_in_group(&"live_flora")).is_true()
	assert_bool(furniture.is_in_group(&"tag_live_flora")).is_true()


func test_live_flora_count_tracking() -> void:
	var map := _create_test_map()
	var fl: FurnitureLayer = auto_free(FurnitureLayer.new())
	fl.set_container(map.get_furniture_container())

	var flora_def := _create_test_flora_def("pine_tree")
	var other_def := _create_test_non_flora_def("metal_crate")

	var map_def: MapDef = auto_free(MapDef.new())
	map_def.id = "test_map"
	map_def.flora_palette = [flora_def]
	map_def.flora_spawn_cap = 5
	map_def.flora_spawns_per_day = 2

	var spawner: PlantSpawner = auto_free(PlantSpawner.new())
	add_child(spawner)
	spawner.setup(map, map_def, fl)

	assert_int(spawner.get_live_flora_count()).is_equal(0)

	# 1. Spawn flora piece.
	fl.spawn(flora_def, Vector3i(5, 0, 5), 0)
	assert_int(spawner.get_live_flora_count()).is_equal(1)

	# 2. Spawn non-flora piece (should not increment flora count).
	fl.spawn(other_def, Vector3i(10, 0, 10), 0)
	assert_int(spawner.get_live_flora_count()).is_equal(1)

	# 3. Spawn another flora piece.
	fl.spawn(flora_def, Vector3i(15, 0, 15), 0)
	assert_int(spawner.get_live_flora_count()).is_equal(2)

	# 4. Remove a flora piece.
	fl.remove_at(Vector3i(5, 0, 5))
	assert_int(spawner.get_live_flora_count()).is_equal(1)


func test_spawn_cap_prevents_spawning_when_reached() -> void:
	var map := _create_test_map()
	var fl: FurnitureLayer = auto_free(FurnitureLayer.new())
	fl.set_container(map.get_furniture_container())

	var flora_def := _create_test_flora_def()

	var map_def: MapDef = auto_free(MapDef.new())
	map_def.id = "test_map"
	map_def.flora_palette = [flora_def]
	map_def.flora_spawn_cap = 2
	map_def.flora_spawns_per_day = 2
	map_def.flora_max_spawn_attempts = 10

	var spawner: PlantSpawner = auto_free(PlantSpawner.new())
	add_child(spawner)
	spawner.setup(map, map_def, fl)

	# Manually spawn up to the cap (2 items).
	fl.spawn(flora_def, Vector3i(0, 0, 0), 0)
	fl.spawn(flora_def, Vector3i(10, 0, 10), 0)
	assert_int(spawner.get_live_flora_count()).is_equal(2)

	# attempt_spawn should reject since count >= cap.
	var spawned := spawner.attempt_spawn()
	assert_bool(spawned).is_false()
	assert_int(spawner.get_live_flora_count()).is_equal(2)


func test_attempt_spawn_places_node_when_below_cap() -> void:
	var map := _create_test_map()
	var fl: FurnitureLayer = auto_free(FurnitureLayer.new())
	fl.set_container(map.get_furniture_container())

	var flora_def := _create_test_flora_def()

	var map_def: MapDef = auto_free(MapDef.new())
	map_def.id = "test_map"
	map_def.flora_palette = [flora_def]
	map_def.flora_spawn_cap = 5
	map_def.flora_spawns_per_day = 2
	map_def.flora_max_spawn_attempts = 30
	map_def.world_bounds = AABB(Vector3(-20, -10, -20), Vector3(40, 20, 40))
	map_def.player_spawn = Vector3(100, 0, 100) # Far away to not block placement

	var spawner: PlantSpawner = auto_free(PlantSpawner.new())
	add_child(spawner)
	spawner.setup(map, map_def, fl)

	assert_int(spawner.get_live_flora_count()).is_equal(0)

	var success := spawner.attempt_spawn()
	assert_bool(success).is_true()
	assert_int(spawner.get_live_flora_count()).is_equal(1)


func test_day_rollover_resets_spawn_timer_and_syncs_count() -> void:
	var map := _create_test_map()
	var fl: FurnitureLayer = auto_free(FurnitureLayer.new())
	fl.set_container(map.get_furniture_container())

	var flora_def := _create_test_flora_def()

	var map_def: MapDef = auto_free(MapDef.new())
	map_def.id = "test_map"
	map_def.flora_palette = [flora_def]
	map_def.flora_spawn_cap = 10
	map_def.flora_spawns_per_day = 4

	var spawner: PlantSpawner = auto_free(PlantSpawner.new())
	add_child(spawner)
	spawner.setup(map, map_def, fl)

	spawner._spawn_timer = 250.0
	EventBus.day_rolled_over.emit(2)

	assert_float(spawner._spawn_timer).is_equal(0.0)
