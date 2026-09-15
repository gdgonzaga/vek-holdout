extends GdUnitTestSuite

## Unit tests for AreaDesignationController.compute_area_bounds static helper.
## Verifies corner order normalization across X, Y, Z, and multi-Y level inclusion.

func test_corner_order_normalization_xyz() -> void:
	var corner_a := Vector3i(10, 8, -2)
	var corner_b := Vector3i(2, 3, 5)
	var bounds: Dictionary = AreaDesignationController.compute_area_bounds(corner_a, corner_b)

	var min_c: Vector3i = bounds["min_cell"]
	var max_c: Vector3i = bounds["max_cell"]

	assert_int(min_c.x).is_equal(2)
	assert_int(max_c.x).is_equal(10)
	assert_int(min_c.y).is_equal(3)
	assert_int(max_c.y).is_equal(8)
	assert_int(min_c.z).is_equal(-2)
	assert_int(max_c.z).is_equal(5)


func test_corner_b_higher_y_level_included() -> void:
	var corner_a := Vector3i(0, 2, 0)
	var corner_b := Vector3i(5, 7, 5)
	var bounds: Dictionary = AreaDesignationController.compute_area_bounds(corner_a, corner_b)

	var min_c: Vector3i = bounds["min_cell"]
	var max_c: Vector3i = bounds["max_cell"]

	assert_int(min_c.y).is_equal(2)
	assert_int(max_c.y).is_equal(7)


func test_corner_b_lower_y_level_included() -> void:
	var corner_a := Vector3i(0, 10, 0)
	var corner_b := Vector3i(5, 3, 5)
	var bounds: Dictionary = AreaDesignationController.compute_area_bounds(corner_a, corner_b)

	var min_c: Vector3i = bounds["min_cell"]
	var max_c: Vector3i = bounds["max_cell"]

	assert_int(min_c.y).is_equal(3)
	assert_int(max_c.y).is_equal(10)


func test_same_y_level_is_single_layer() -> void:
	var corner_a := Vector3i(0, 5, 0)
	var corner_b := Vector3i(4, 5, 4)
	var bounds: Dictionary = AreaDesignationController.compute_area_bounds(corner_a, corner_b)

	var min_c: Vector3i = bounds["min_cell"]
	var max_c: Vector3i = bounds["max_cell"]

	assert_int(min_c.y).is_equal(5)
	assert_int(max_c.y).is_equal(5)


func test_single_cell_area_bounds() -> void:
	var corner := Vector3i(3, 7, -4)
	var bounds: Dictionary = AreaDesignationController.compute_area_bounds(corner, corner)

	var min_c: Vector3i = bounds["min_cell"]
	var max_c: Vector3i = bounds["max_cell"]

	assert_int(min_c.x).is_equal(3)
	assert_int(max_c.x).is_equal(3)
	assert_int(min_c.y).is_equal(7)
	assert_int(max_c.y).is_equal(7)
	assert_int(min_c.z).is_equal(-4)
	assert_int(max_c.z).is_equal(-4)
