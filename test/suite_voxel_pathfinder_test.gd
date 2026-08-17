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
