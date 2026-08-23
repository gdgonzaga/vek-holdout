extends GdUnitTestSuite

## Unit tests for VoxelPathfinder's stepped neighbor model (ARCH "Subsystem:
## Colonists"): flat routing, one-block climbs, headroom rejection, multi-cell
## drops, and cost preference of flat detours over jumps. Walkability is a stub
## mirroring MapWiring._compose_walkability over a Dictionary mini-grid.

const _DOWN := Vector3i(0, -1, 0)
const _UP := Vector3i(0, 1, 0)


## Finder whose predicate mirrors the composed production one: air at the cell,
## solid floor below, air above (head clearance for the 2-cell capsule).
func _make_finder(solid: Dictionary) -> VoxelPathfinder:
	var finder: VoxelPathfinder = auto_free(VoxelPathfinder.new())
	var predicate := func(cell: Vector3i) -> bool:
		return not solid.has(cell) and solid.has(cell + _DOWN) and not solid.has(cell + _UP)
	finder.set_walkability(predicate)
	return finder


func _fill_floor(solid: Dictionary, x_min: int, x_max: int, z_min: int, z_max: int, y: int) -> void:
	for x in range(x_min, x_max + 1):
		for z in range(z_min, z_max + 1):
			solid[Vector3i(x, y, z)] = true


func test_flat_route_stays_on_level() -> void:
	var solid := {}
	_fill_floor(solid, -5, 5, -5, 5, 0)
	var finder := _make_finder(solid)
	var path := finder.find_path(Vector3i(0, 1, 0), Vector3i(3, 1, 0))
	assert_int(path.size()).is_equal(4)


## A block on the floor is climbed via dy+1: the colonist stands on cells
## (x,1,z) west of it and on (x,2,z) above it.
func test_climbs_one_block() -> void:
	var solid := {}
	_fill_floor(solid, -5, 5, -5, 5, 0)
	solid[Vector3i(2, 1, 0)] = true
	var finder := _make_finder(solid)
	var path := finder.find_path(Vector3i(0, 1, 0), Vector3i(2, 2, 0))
	assert_int(path.size()).is_equal(3)
	assert_bool(path.has(Vector3i(1, 1, 0))).is_true()
	assert_bool(path.has(Vector3i(2, 2, 0))).is_true()


## A solid cell above the block's top removes head clearance, so the climb
## (and the target) becomes unwalkable and no path is returned.
func test_headroom_blocks_climb() -> void:
	var solid := {}
	_fill_floor(solid, -5, 5, -5, 5, 0)
	solid[Vector3i(2, 1, 0)] = true
	solid[Vector3i(2, 3, 0)] = true
	var finder := _make_finder(solid)
	var path := finder.find_path(Vector3i(0, 1, 0), Vector3i(2, 2, 0))
	assert_int(path.size()).is_equal(0)


## A two-cell cliff routes via a dy-2 drop: the column past the edge has no
## floor at the current level, only two cells down.
func test_routes_two_cell_drop() -> void:
	var solid := {}
	_fill_floor(solid, -5, 0, -5, 5, 0)
	_fill_floor(solid, 1, 5, -5, 5, -2)
	var finder := _make_finder(solid)
	var path := finder.find_path(Vector3i(0, 1, 0), Vector3i(2, -1, 0))
	assert_int(path.size()).is_equal(3)
	assert_bool(path.has(Vector3i(1, -1, 0))).is_true()


## Jumping costs 3.0 + a 1.5 landing drop, so a 6-step flat detour (6.0) beats
## hopping the block (6.5): the returned route stays on the level.
func test_prefers_flat_detour_over_jump() -> void:
	var solid := {}
	_fill_floor(solid, -5, 5, -5, 5, 0)
	solid[Vector3i(2, 1, 0)] = true
	var finder := _make_finder(solid)
	var path := finder.find_path(Vector3i(0, 1, 0), Vector3i(4, 1, 0))
	assert_bool(path.has(Vector3i(2, 2, 0))).is_false()
	assert_int(path.size()).is_equal(7)


## With 2-high walls funnelling the corridor, the only competitive route is
## over the block itself — the jump is used when nothing cheaper exists.
func test_jump_used_when_no_detour() -> void:
	var solid := {}
	_fill_floor(solid, -5, 5, -5, 5, 0)
	solid[Vector3i(2, 1, 0)] = true
	for x in range(0, 5):
		solid[Vector3i(x, 1, 1)] = true
		solid[Vector3i(x, 1, -1)] = true
		solid[Vector3i(x, 2, 1)] = true
		solid[Vector3i(x, 2, -1)] = true
	var finder := _make_finder(solid)
	var path := finder.find_path(Vector3i(0, 1, 0), Vector3i(4, 1, 0))
	assert_bool(path.has(Vector3i(2, 2, 0))).is_true()


## Short steppable furniture is treated as walkable so colonists route through it,
## while tall furniture remains blocking.
func test_routes_across_steppable_furniture() -> void:
	var solid := {}
	_fill_floor(solid, -5, 5, -5, 5, 0)
	var steppable_furniture := {Vector3i(2, 1, 0): true}
	var tall_furniture := {Vector3i(2, 1, 1): true}
	var finder: VoxelPathfinder = auto_free(VoxelPathfinder.new())
	var predicate := func(cell: Vector3i) -> bool:
		if solid.has(cell) or not solid.has(cell + _DOWN) or solid.has(cell + _UP):
			return false
		if tall_furniture.has(cell):
			return false
		return true
	finder.set_walkability(predicate)

	# Direct route across the cell with steppable furniture (2, 1, 0)
	var path := finder.find_path(Vector3i(0, 1, 0), Vector3i(4, 1, 0))
	assert_int(path.size()).is_equal(5)
	assert_bool(path.has(Vector3i(2, 1, 0))).is_true()

	# Route blocked by tall furniture at (2, 1, 1) has to go around
	var path_around := finder.find_path(Vector3i(0, 1, 1), Vector3i(4, 1, 1))
	assert_bool(path_around.has(Vector3i(2, 1, 1))).is_false()


## A blueprint placed on top of an existing block sits one Y above the walkable
## floor (blueprint ghost occupancy overlaid like production's BlueprintLayer):
## every same-Y neighbour column is air with no floor, so the footprint
## expansion must resolve the ground cell one below the footprint.
func test_footprint_adjacent_stands_below_raised_blueprint() -> void:
	var solid := {}
	_fill_floor(solid, -5, 5, -5, 5, 0)
	solid[Vector3i(2, 1, 0)] = true # existing block the blueprint sits on
	var blueprint := {Vector3i(2, 2, 0): true}
	var finder: VoxelPathfinder = auto_free(VoxelPathfinder.new())
	var predicate := func(cell: Vector3i) -> bool:
		if blueprint.has(cell):
			return false
		return not solid.has(cell) and solid.has(cell + _DOWN) and not solid.has(cell + _UP)
	finder.set_walkability(predicate)

	var path := finder.find_path_to_footprint_adjacent(
			Vector3(0.5, 1.5, 0.5), [Vector3i(2, 2, 0)])
	assert_int(path.size()).is_greater(0)
	if path.is_empty():
		return
	var final := path[path.size() - 1]
	assert_int(int(floor(final.y))).is_equal(1) # ground floor, one below the bp
	assert_int(max(absi(int(floor(final.x)) - 2), absi(int(floor(final.z))))).is_equal(1)


## Hint-less (blocky-only map) ring search: a blueprint cell one Y above the
## floor resolves to the walkable ground cell one below — the +/-1 column
## probes are not gated on the smooth-terrain hint.
func test_stand_near_cell_without_hint_finds_floor_below() -> void:
	var solid := {}
	_fill_floor(solid, -5, 5, -5, 5, 0)
	solid[Vector3i(0, 1, 0)] = true # existing block
	var blueprint := {Vector3i(0, 2, 0): true}
	var finder: VoxelPathfinder = auto_free(VoxelPathfinder.new())
	var predicate := func(cell: Vector3i) -> bool:
		if blueprint.has(cell):
			return false
		return not solid.has(cell) and solid.has(cell + _DOWN) and not solid.has(cell + _UP)
	finder.set_walkability(predicate)

	var stand := finder.find_stand_near_cell(Vector3i(0, 2, 0))
	assert_int(stand.y).is_equal(1)
	assert_int(max(absi(stand.x), absi(stand.z))).is_equal(1)


## Telemetry clock (pathfinding.md §6): every telemetry-writing query stamps
## last_query_time so the debug visualizer can expire stale diagnostics;
## clear_diagnostics() resets it to the never-fresh sentinel.
func test_query_stamps_and_clear_resets_telemetry_time() -> void:
	var solid := {}
	_fill_floor(solid, -5, 5, -5, 5, 0)
	var finder := _make_finder(solid)
	assert_float(finder.last_query_time).is_less(0.0)

	var before := float(Time.get_ticks_msec()) * 0.001
	finder.find_path(Vector3i(0, 1, 0), Vector3i(3, 1, 0))
	finder.find_stand_near_cell(Vector3i(3, 1, 0), 2)
	var after := float(Time.get_ticks_msec()) * 0.001
	assert_float(finder.last_query_time).is_greater_equal(before)
	assert_float(finder.last_query_time).is_less_equal(after)

	finder.clear_diagnostics()
	assert_float(finder.last_query_time).is_less(0.0)


## When a colonist starts inside an unwalkable cell (e.g. blueprint placed on top of it),
## find_path relaxes the unwalkable start constraint and routes outward to a walkable neighbor first.
func test_unwalkable_start_cell_routes_to_walkable_neighbor() -> void:
	var solid := {}
	_fill_floor(solid, -5, 5, -5, 5, 0)
	var blueprint := {Vector3i(0, 1, 0): true} # start cell is covered by blueprint
	var finder: VoxelPathfinder = auto_free(VoxelPathfinder.new())
	var predicate := func(cell: Vector3i) -> bool:
		if blueprint.has(cell):
			return false
		return not solid.has(cell) and solid.has(cell + _DOWN) and not solid.has(cell + _UP)
	finder.set_walkability(predicate)

	var path := finder.find_path(Vector3i(0, 1, 0), Vector3i(3, 1, 0))
	assert_int(path.size()).is_greater(0)
	assert_bool(path.has(Vector3i(0, 1, 0))).is_true()
	assert_bool(blueprint.has(path[1])).is_false() # step 1 exits the blueprint


## When find_stand_cell queries a position in an unwalkable column (e.g. inside a tall blueprint),
## it falls back to a ring search to locate the nearest exterior standable cell.
func test_find_stand_cell_ring_search_fallback_when_column_unwalkable() -> void:
	var solid := {}
	_fill_floor(solid, -5, 5, -5, 5, 0)
	# Column (0, 0) is blocked for all Y levels by blueprints/walls
	var blueprint := {}
	for y in range(-3, 6):
		blueprint[Vector3i(0, y, 0)] = true
	var finder: VoxelPathfinder = auto_free(VoxelPathfinder.new())
	var predicate := func(cell: Vector3i) -> bool:
		if blueprint.has(cell):
			return false
		return not solid.has(cell) and solid.has(cell + _DOWN) and not solid.has(cell + _UP)
	finder.set_walkability(predicate)

	var stand := finder.find_stand_cell(Vector3(0.5, 1.5, 0.5))
	assert_bool(blueprint.has(stand)).is_false()
	assert_int(stand.y).is_equal(1)
	assert_int(max(absi(stand.x), absi(stand.z))).is_equal(1)
