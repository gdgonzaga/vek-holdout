extends GdUnitTestSuite

const _DOWN := Vector3i(0, -1, 0)
const _UP := Vector3i(0, 1, 0)

const _AStar4WayScript = preload("res://subsystems/colonists/pathfinding/a_star_4_way_strategy.gd")
const _AStar8WayScript = preload("res://subsystems/colonists/pathfinding/a_star_8_way_strategy.gd")
const _SmoothedAStarScript = preload("res://subsystems/colonists/pathfinding/smoothed_a_star_strategy.gd")
const _ThetaStarScript = preload("res://subsystems/colonists/pathfinding/theta_star_strategy.gd")


func _fill_floor(solid: Dictionary, x0: int, x1: int, z0: int, z1: int, y: int = 0) -> void:
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			solid[Vector3i(x, y, z)] = true


func _make_finder(solid: Dictionary, strategy: PathfindingStrategy = null) -> VoxelPathfinder:
	var finder: VoxelPathfinder = auto_free(VoxelPathfinder.new(strategy))
	var predicate := func(cell: Vector3i) -> bool:
		return not solid.has(cell) and solid.has(cell + _DOWN) and not solid.has(cell + _UP)
	finder.set_walkability(predicate)
	return finder


## AStar4WayStrategy generates orthogonal stepped paths.
func test_astar_4_way_strategy_orthogonal_path() -> void:
	var solid := {}
	_fill_floor(solid, -5, 5, -5, 5, 0)
	var strategy: PathfindingStrategy = _AStar4WayScript.new()
	var finder := _make_finder(solid, strategy)

	var path := finder.find_path(Vector3i(0, 1, 0), Vector3i(2, 1, 2))
	# Chebyshev distance 2 -> 4-way path has 5 points: (0,0)->(1,0)->(2,0)->(2,1)->(2,2)
	assert_int(path.size()).is_equal(5)
	assert_str(strategy.get_strategy_name()).is_equal("AStar4Way")


## AStar8WayStrategy generates diagonal steps across open floor.
func test_astar_8_way_strategy_diagonal_path() -> void:
	var solid := {}
	_fill_floor(solid, -5, 5, -5, 5, 0)
	var strategy: PathfindingStrategy = _AStar8WayScript.new()
	var finder := _make_finder(solid, strategy)

	var path := finder.find_path(Vector3i(0, 1, 0), Vector3i(2, 1, 2))
	# 8-way diagonal path has 3 points: (0,1,0) -> (1,1,1) -> (2,1,2)
	assert_int(path.size()).is_equal(3)
	assert_bool(path.has(Vector3i(1, 1, 1))).is_true()
	assert_str(strategy.get_strategy_name()).is_equal("AStar8Way")


## AStar8WayStrategy prevents cutting corners through solid walls.
func test_astar_8_way_strategy_avoids_corner_cutting() -> void:
	var solid := {}
	_fill_floor(solid, -5, 5, -5, 5, 0)
	# Place wall blocks that make diagonal step from (0,1,0) to (1,1,1) impossible without clipping
	solid[Vector3i(1, 1, 0)] = true # solid wall
	solid[Vector3i(0, 1, 1)] = true # solid wall
	var strategy: PathfindingStrategy = _AStar8WayScript.new()
	var finder := _make_finder(solid, strategy)

	var path := finder.find_path(Vector3i(0, 1, 0), Vector3i(2, 1, 2))
	# Path cannot cut through the diagonal between walls at (1,1,0) and (0,1,1) on first step
	assert_bool(path.size() > 1 and path[1] == Vector3i(1, 1, 1)).is_false()


## SmoothedAStarStrategy collapses waypoints across open flat ground into direct line.
func test_smoothed_astar_strategy_collapses_open_field() -> void:
	var solid := {}
	_fill_floor(solid, -10, 10, -10, 10, 0)
	var strategy: PathfindingStrategy = _SmoothedAStarScript.new()
	var finder := _make_finder(solid, strategy)

	var waypoints := finder.find_path_world(Vector3(0.5, 1.0, 0.5), Vector3(5.5, 1.0, 5.5))
	# Open field from (0,0) to (5,5) should smooth into 2 endpoints: start and target
	assert_int(waypoints.size()).is_equal(2)
	assert_vector(waypoints[0]).is_equal(Vector3(0.5, 1.5, 0.5))
	assert_vector(waypoints[1]).is_equal(Vector3(5.5, 1.5, 5.5))


## SmoothedAStarStrategy preserves waypoints at elevation changes (steps/drops).
func test_smoothed_astar_strategy_preserves_elevation_steps() -> void:
	var solid := {}
	_fill_floor(solid, -5, 1, -5, 5, 0)
	_fill_floor(solid, 2, 5, -5, 5, 1) # Raised floor step at x=2
	solid[Vector3i(2, 1, 0)] = true # step block
	var strategy: PathfindingStrategy = _SmoothedAStarScript.new()
	var finder := _make_finder(solid, strategy)

	var waypoints := finder.find_path_world(Vector3(0.5, 1.0, 0.5), Vector3(4.5, 2.0, 0.5))
	assert_int(waypoints.size()).is_greater_equal(3) # start -> step anchor -> target


## ThetaStarStrategy finds any-angle direct paths.
func test_theta_star_strategy_direct_path() -> void:
	var solid := {}
	_fill_floor(solid, -10, 10, -10, 10, 0)
	var strategy: PathfindingStrategy = _ThetaStarScript.new()
	var finder := _make_finder(solid, strategy)

	var path := finder.find_path(Vector3i(0, 1, 0), Vector3i(4, 1, 2))
	assert_int(path.size()).is_equal(2) # Direct start -> target
	assert_str(strategy.get_strategy_name()).is_equal("ThetaStar")


## VoxelPathfinder allows runtime switching of strategies.
func test_voxel_pathfinder_strategy_switching() -> void:
	var solid := {}
	_fill_floor(solid, -5, 5, -5, 5, 0)
	var finder := _make_finder(solid, _AStar4WayScript.new())

	var path_4way := finder.find_path(Vector3i(0, 1, 0), Vector3i(2, 1, 2))
	assert_int(path_4way.size()).is_equal(5)

	finder.set_strategy(_AStar8WayScript.new())
	var path_8way := finder.find_path(Vector3i(0, 1, 0), Vector3i(2, 1, 2))
	assert_int(path_8way.size()).is_equal(3)


## GameState manages the global strategy and creates the corresponding strategy instance.
func test_game_state_strategy_management_and_serialization() -> void:
	var initial_strat := GameState.create_pathfinding_strategy()
	assert_str(initial_strat.get_strategy_name()).is_equal("SmoothedAStar (AStar8Way)")

	GameState.set_pathfinding_strategy(GameState.PathfindingStrategyType.A_STAR_4_WAY)
	var strat_4way := GameState.create_pathfinding_strategy()
	assert_str(strat_4way.get_strategy_name()).is_equal("AStar4Way")

	# Serialization roundtrip
	var serialized := GameState.serialize()
	assert_int(int(serialized.get("pathfinding_strategy", -1))).is_equal(int(GameState.PathfindingStrategyType.A_STAR_4_WAY))

	# Restore to SmoothedAStar
	GameState.set_pathfinding_strategy(GameState.PathfindingStrategyType.SMOOTHED_A_STAR)
	assert_int(int(GameState.pathfinding_strategy)).is_equal(int(GameState.PathfindingStrategyType.SMOOTHED_A_STAR))
