extends GdUnitTestSuite

## Unit tests for the Phase 5 smooth-material placement (docs/TODO.md Phase 5):
## - BuildLibrary's terrain-material catalog (scanned from data/terrain/materials)
## - TerrainMaterialDef shape (place_radius for the add-sphere/blob ghost)
## - SmoothPlacementStrategy.commit: add_material with the def's radius at the
##   committed origin; fail-safe when unwired or the id is unknown

const Doubles = preload("res://test/helpers/doubles.gd")


func test_catalog_lists_ground_material() -> void:
	assert_bool(BuildLibrary.is_terrain_material("ground")).is_true()
	assert_bool(BuildLibrary.is_terrain_material("wood_block")).is_false()
	var mat := BuildLibrary.get_terrain_material("ground")
	assert_object(mat).is_not_null()
	assert_int(mat.hardness).is_greater_equal(1)
	var found := false
	for entry in BuildLibrary.get_terrain_materials():
		if entry.id == "ground":
			found = true
	assert_bool(found).is_true()


func test_material_defs_shape() -> void:
	var materials := BuildLibrary.get_terrain_materials()
	assert_int(materials.size()).is_greater_equal(1)
	for mat: TerrainMaterialDef in materials:
		assert_float(mat.place_radius).is_greater(0.0)
		assert_str(mat.id).is_not_empty()


func test_strategy_commits_add_sphere_at_origin() -> void:
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	var strategy := SmoothPlacementStrategy.new()
	strategy.set_smooth_grid(grid)

	var t := Transform3D.IDENTITY
	t.origin = Vector3(2.5, 1.0, 3.5)
	assert_bool(strategy.commit(t, null, "ground")).is_true()

	assert_int(grid.adds.size()).is_equal(1)
	assert_that(grid.adds[0]["pos"]).is_equal(Vector3(2.5, 1.0, 3.5))
	assert_str(grid.adds[0]["material_id"]).is_equal("ground")
	assert_float(grid.adds[0]["radius"]).is_equal(BuildLibrary.get_terrain_material("ground").place_radius)


func test_strategy_fails_safe_unwired() -> void:
	var strategy := SmoothPlacementStrategy.new()
	assert_bool(strategy.commit(Transform3D.IDENTITY, null, "ground")).is_false()


func test_strategy_fails_safe_unknown_material() -> void:
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	var strategy := SmoothPlacementStrategy.new()
	strategy.set_smooth_grid(grid)
	assert_bool(strategy.commit(Transform3D.IDENTITY, null, "not_a_material")).is_false()
	assert_int(grid.adds.size()).is_equal(0)
