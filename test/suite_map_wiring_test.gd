extends GdUnitTestSuite

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")

## The walkability seam (MapWiring.blocky_ground_probe / compose_walkability):
## ground rules come from an injectable probe; occupancy layers AND on top.
## Stubbed get_block_at keeps this a pure-logic suite — no terrain or build
## layers needed. Production behavior is unchanged by the seam refactor
## (dual-voxel conversion Phase 1, docs/TODO.md D4); these tests pin it.

func _probe_from(cells: Dictionary) -> Callable:
	return MapWiring.blocky_ground_probe(func(cell: Vector3i) -> String: return cells.get(cell, ""))


func test_blocky_probe_ground_rules() -> void:
	var cells := {
		Vector3i(0, 0, 0): "wood",    # floor
		Vector3i(5, 0, 0): "",         # no floor under the stand cell
		Vector3i(9, 0, 0): "wood",
		Vector3i(9, 1, 0): "wood",    # solid stand cell
		Vector3i(20, 0, 0): "wood",
		Vector3i(20, 2, 0): "stone",   # no head clearance above the stand cell
	}
	var probe := _probe_from(cells)
	var ok: bool = probe.call(Vector3i(0, 1, 0))       # air over floor, clear head
	assert_bool(ok).is_true()
	ok = probe.call(Vector3i(5, 1, 0))                 # nothing below
	assert_bool(ok).is_false()
	ok = probe.call(Vector3i(9, 1, 0))                 # cell itself solid
	assert_bool(ok).is_false()
	ok = probe.call(Vector3i(20, 1, 0))                # ceiling one above
	assert_bool(ok).is_false()


func test_compose_ands_probe_with_occupancy() -> void:
	# No build layers on a map → the predicate is exactly the probe.
	var always := MapWiring.compose_walkability(
		func(_cell: Vector3i) -> bool: return true, null, null)
	var ok: bool = always.call(Vector3i(3, 1, 3))
	assert_bool(ok).is_true()
	var never := MapWiring.compose_walkability(
		func(_cell: Vector3i) -> bool: return false, null, null)
	ok = never.call(Vector3i(3, 1, 3))
	assert_bool(ok).is_false()


func test_wire_enemies_instantiates_swarmer() -> void:
	var map := preload("res://subsystems/maps/map_template.tscn").instantiate() as Map
	add_child(map)
	auto_free(map)

	var spawn_points := map.find_child("SpawnPoints") as Node3D
	var marker := Marker3D.new()
	marker.name = "EnemySpawn_1"
	marker.position = Vector3(10, 5, 10)
	spawn_points.add_child(marker)

	var container := MapWiring.wire_enemies(map)
	assert_that(container).is_not_null()
	assert_int(container.get_child_count()).is_equal(1)
	var enemy := container.get_child(0) as Node3D
	assert_that(enemy).is_not_null()
	assert_str(enemy.name).contains("EnemySwarmer")


# --- wire_build / wire_mining / wire_day_night / wire_flora / wire_player /
# wire_colonists / wire_enemy_pathfinder: each attaches its documented child
# (or wires its documented dependency) and tolerates a second call without
# duplicating anything — R15. None of these were exercised by any suite
# before this phase (only reachable in production via SceneManager.swap_map,
# which no suite calls).

func _template_map() -> Map:
	## Auxiliary: a fresh map_template.tscn instance, parented and auto-freed.
	var map := preload("res://subsystems/maps/map_template.tscn").instantiate() as Map
	add_child(map)
	auto_free(map)
	return map


## wire_build wires BuildController's grid adapter, furniture/blueprint layers
## and both placement strategies; a second call re-wires cleanly (fresh
## objects, never a stale mix) rather than leaving any dependency null.
func test_wire_build_wires_controller_dependencies_and_rewires_cleanly() -> void:
	var map := _template_map()

	# 1. First wire: every BuildController dependency must resolve.
	var fl := MapWiring.wire_build(map)
	var ctrl := map.find_child("BuildController") as BuildController
	assert_object(ctrl).is_not_null()
	assert_object(fl).is_not_null()
	assert_object(ctrl.furniture_layer).is_same(fl)
	assert_object(ctrl.grid_adapter).is_not_null()
	assert_object(ctrl.blueprint_layer).is_not_null()
	assert_bool(ctrl.strategy is BlueprintPlacementStrategy).is_true()
	assert_bool(ctrl.smooth_strategy is SmoothPlacementStrategy).is_true()

	# 2. Second wire (e.g. a map re-load): dependencies stay fully wired, not left null.
	var fl2 := MapWiring.wire_build(map)
	assert_object(ctrl.furniture_layer).is_same(fl2)
	assert_object(ctrl.grid_adapter).is_not_null()
	assert_object(ctrl.blueprint_layer).is_not_null()


## wire_mining mounts MiningSystem + DigBoxController and binds Colony's
## terrain predicate; a second call reuses both nodes instead of mounting
## duplicates.
func test_wire_mining_mounts_systems_once_and_binds_terrain_predicate() -> void:
	var _sandbox := ColonySandbox.new(self)
	var map := _template_map()

	# 1. First wire: both nodes mounted, Colony's terrain predicate bound.
	MapWiring.wire_mining(map)
	var mining_sys := map.find_child("MiningSystem", true, false) as MiningSystem
	var dig_ctrl := map.find_child("DigBoxController", true, false) as DigBoxController
	assert_object(mining_sys).is_not_null()
	assert_object(dig_ctrl).is_not_null()
	assert_bool(Colony._is_terrain_at.is_valid()).is_true()

	# 2. Second wire: same nodes reused, not duplicated.
	MapWiring.wire_mining(map)
	var mining_count := 0
	var dig_count := 0
	for child in map.get_children():
		if child is MiningSystem:
			mining_count += 1
		if child is DigBoxController:
			dig_count += 1
	assert_int(mining_count).is_equal(1)
	assert_int(dig_count).is_equal(1)
	assert_object(map.find_child("MiningSystem", true, false)).is_same(mining_sys)
	assert_object(map.find_child("DigBoxController", true, false)).is_same(dig_ctrl)

	_sandbox.restore()


## wire_day_night creates exactly one DayNightCycle under EnvironmentContainer
## when none exists yet, and a second call finds the one it just made instead
## of mounting a duplicate.
func test_wire_day_night_creates_cycle_once_and_is_idempotent() -> void:
	var map := _template_map()
	# The template ships its own authored DayNightCycle; remove it so this test
	# exercises the "absent -> create" branch, not the "already present" early
	# return the shipped scene would otherwise always take.
	var existing := map.find_child("DayNightCycle", true, false)
	if existing != null:
		existing.free()

	# 1. First wire: a DayNightCycle appears under EnvironmentContainer.
	MapWiring.wire_day_night(map)
	var env := map.find_child("EnvironmentContainer", true, false)
	assert_object(env).is_not_null()
	var cycle := map.find_child("DayNightCycle", true, false)
	assert_object(cycle).is_not_null()
	assert_object(cycle.get_parent()).is_same(env)
	var count_after_first := env.get_child_count()

	# 2. Second wire: the existing cycle is found, no duplicate mounted.
	MapWiring.wire_day_night(map)
	assert_int(env.get_child_count()).is_equal(count_after_first)
	assert_object(map.find_child("DayNightCycle", true, false)).is_same(cycle)


## wire_flora mounts exactly one PlantSpawner under EnvironmentContainer and
## configures it via setup(); a second call reuses the same spawner instead of
## mounting a duplicate.
func test_wire_flora_mounts_plant_spawner_once_and_is_idempotent() -> void:
	var map := _template_map()
	var map_def := MapDef.new()
	var fl := FurnitureLayer.new()
	fl.set_container(map.get_furniture_container())

	# 1. First wire: a PlantSpawner appears under EnvironmentContainer.
	var spawner := MapWiring.wire_flora(map, map_def, fl)
	assert_object(spawner).is_not_null()
	var env := map.find_child("EnvironmentContainer", true, false)
	assert_object(spawner.get_parent()).is_same(env)

	# 2. Second wire: same spawner instance, no duplicate mounted.
	var spawner2 := MapWiring.wire_flora(map, map_def, fl)
	assert_object(spawner2).is_same(spawner)
	var count := 0
	for child in env.get_children():
		if child is PlantSpawner:
			count += 1
	assert_int(count).is_equal(1)


## wire_player wires BuildController's camera/player/exclude-body refs and
## reuses an existing VoxelViewer on repeated wiring (docs: "so repeated map
## swaps don't stack viewers").
func test_wire_player_wires_camera_refs_and_reuses_the_viewer() -> void:
	var map := _template_map()
	var player: Player = auto_free(preload("res://subsystems/player/player.tscn").instantiate())
	add_child(player)
	# CameraRig builds its camera in its own _ready; wire_player needs it built first.
	await get_tree().process_frame

	# 1. First wire: BuildController's camera/player/exclude refs resolve.
	MapWiring.wire_player(map, player)
	var viewer := player.get_node_or_null("VoxelViewer")
	assert_object(viewer).is_not_null()
	var ctrl := map.find_child("BuildController") as BuildController
	assert_object(ctrl._camera).is_same(player.get_camera())
	assert_object(ctrl.player).is_same(player)
	assert_bool(ctrl.exclude_bodies.has(player)).is_true()

	# 2. Second wire (a base<->POI swap): the same viewer is reused, not stacked.
	MapWiring.wire_player(map, player)
	var viewer_count := 0
	for child in player.get_children():
		if child is VoxelViewer:
			viewer_count += 1
	assert_int(viewer_count).is_equal(1)
	assert_object(player.get_node_or_null("VoxelViewer")).is_same(viewer)


## wire_colonists wires Colony's walkability/ground-query/cell-cost predicates
## and world bounds, and returns the map's colonist container. Run with an
## emptied roster and a spawnless map (map_template's SpawnPoints has no
## ColonistSpawn_* markers) so this stays a pure wiring check, never touching
## the real Colony roster other suites depend on.
func test_wire_colonists_wires_predicates_and_returns_container() -> void:
	var _sandbox := ColonySandbox.new(self)
	var real_colonists := Colony.colonists.duplicate()
	var real_pending := Colony._pending_colonist_records.duplicate()
	Colony.colonists = []
	Colony._pending_colonist_records = []

	var map := _template_map()
	await get_tree().process_frame

	# 1. First wire: predicates + bounds land on Colony, container returned.
	var container := MapWiring.wire_colonists(map)
	assert_object(container).is_same(map.get_colonist_container())
	assert_bool(Colony._walkability_predicate.is_valid()).is_true()
	assert_bool(Colony._ground_query.is_valid()).is_true()
	assert_bool(Colony._cell_cost_fn.is_valid()).is_true()
	assert_object(Colony.get_world_bounds()).is_equal(map.get_world_bounds())
	# No ColonistSpawn_* markers on the template -> nothing spawns.
	assert_int(Colony.colonists.size()).is_equal(0)

	# 2. Second wire: same empty-roster outcome, predicates still valid.
	MapWiring.wire_colonists(map)
	assert_int(Colony.colonists.size()).is_equal(0)
	assert_bool(Colony._walkability_predicate.is_valid()).is_true()

	Colony.colonists = real_colonists
	Colony._pending_colonist_records = real_pending
	_sandbox.restore()


## wire_enemy_pathfinder binds an enemy's VoxelPathfinder to the map's
## walkability predicate and cell-cost function (and, on a smooth-terrain map,
## the stand-cell hint — not exercised here since the bare template's
## SmoothGrid has no terrain_gen). Safe to call twice (re-binds, no growth).
func test_wire_enemy_pathfinder_binds_walkability_and_cell_cost() -> void:
	var map := _template_map()
	var enemy: EnemyBase = auto_free(EnemyBase.new())
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	enemy.add_child(health)
	add_child(enemy)

	MapWiring.wire_enemy_pathfinder(enemy, map)
	assert_bool(enemy.pathfinder._is_walkable.is_valid()).is_true()
	assert_bool(enemy.pathfinder._cell_cost.is_valid()).is_true()

	# Idempotent: a second call just re-binds, no error, still valid.
	MapWiring.wire_enemy_pathfinder(enemy, map)
	assert_bool(enemy.pathfinder._is_walkable.is_valid()).is_true()
	assert_bool(enemy.pathfinder._cell_cost.is_valid()).is_true()
