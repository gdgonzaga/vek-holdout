extends GdUnitTestSuite

## ColonySandbox (test/helpers/colony_sandbox.gd): the map-wiring caches on Colony start
## unbound inside a sandbox and are put back afterwards, so one suite's map wiring can
## never change another suite's job-gating results. An "outer" sandbox plays the earlier
## suite that leaves wiring behind; the "inner" one is the sandbox under test.

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")
const CELL: Vector3i = Vector3i(3, 4, 5)

var _outer: ColonySandbox


func before_test() -> void:
	_outer = ColonySandbox.new(self)
	Colony.set_walkability_predicate(func(_cell: Vector3i) -> bool: return false)
	Colony.set_terrain_predicate(func(_cell: Vector3i) -> bool: return false)
	Colony.set_ground_query(func(_x: float, _z: float) -> float: return 7.0)
	Colony.set_world_bounds(AABB(Vector3.ZERO, Vector3.ONE))


func after_test() -> void:
	_outer.restore()


func test_a_new_sandbox_starts_from_the_unbound_defaults() -> void:
	var inner := ColonySandbox.new(self)

	assert_bool(Colony.is_walkable(CELL)).is_true()
	assert_bool(Colony.is_terrain_at(CELL)).is_true()
	assert_bool(is_nan(Colony.get_ground_height_at(1.0, 2.0))).is_true()
	assert_bool(Colony.get_world_bounds() == AABB()).is_true()

	inner.restore()


func test_restore_puts_back_what_was_there_before() -> void:
	var inner := ColonySandbox.new(self)
	Colony.set_walkability_predicate(func(_cell: Vector3i) -> bool: return true)
	Colony.set_ground_query(func(_x: float, _z: float) -> float: return 99.0)

	inner.restore()

	assert_bool(Colony.is_walkable(CELL)).is_false()
	assert_bool(Colony.is_terrain_at(CELL)).is_false()
	assert_float(Colony.get_ground_height_at(1.0, 2.0)).is_equal(7.0)
	assert_bool(Colony.get_world_bounds() == AABB(Vector3.ZERO, Vector3.ONE)).is_true()


func test_restore_is_safe_to_call_twice() -> void:
	var inner := ColonySandbox.new(self)

	inner.restore()
	inner.restore()

	assert_bool(Colony.is_walkable(CELL)).is_false()
