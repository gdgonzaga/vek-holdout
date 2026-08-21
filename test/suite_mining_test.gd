extends GdUnitTestSuite

## Unit tests for the Phase 5 mining dig (docs/TODO.md Phase 5):
## - Data shape: DigToolParams (box/sphere shapes, grid snapping), mining skill,
##   TerrainMaterialDef.yields on the ground material
## - DigAction._apply: carve at the given center/radius or box bounds + yields
##   from the material AT THE DIG POSITION (the RecordingSmoothGrid.material_def seam)
##   + mining XP (the HarvestAction._apply testing seam)
## - DigAction timed path: busy lock while the gauge runs, completion carves
## - SmoothGrid.box_samples: the box-to-samples math the carve and ghost share
## - BuildController._calculate_dig_target: cell-center snapping of the BOX dig

const DIG_TOOL: DigToolParams = preload("res://data/mining/dig_tool.tres")
const GROUND: TerrainMaterialDef = preload("res://data/terrain/materials/ground.tres")
const ROCK: TerrainMaterialDef = preload("res://data/terrain/materials/rock.tres")

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")
const Doubles = preload("res://test/helpers/doubles.gd")

var _sandbox: ColonySandbox


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)


func after_test() -> void:
	_sandbox.restore()


func test_dig_tool_params_shape() -> void:
	assert_float(DIG_TOOL.work_time).is_greater(0.0)
	assert_int(DIG_TOOL.shape).is_equal(DigToolParams.Shape.BOX)
	assert_vector(DIG_TOOL.box_size).is_equal(Vector3(1.0, 1.0, 1.0))
	assert_bool(DIG_TOOL.snap_grid).is_true()


func test_mining_skill_in_catalog_with_labor() -> void:
	var skill_set := SkillSet.new()
	auto_free(skill_set)
	add_child(skill_set)
	# Fresh set: L1, the 1.0 unskilled baseline — and mining records via labor.
	assert_float(skill_set.get_multiplier("mining")).is_equal(1.0)
	assert_bool(skill_set.record_use_for_labor("mining")).is_true()
	assert_int(skill_set.get_level("mining")).is_equal(1)


func test_ground_material_has_yields() -> void:
	assert_bool(GROUND.yields.is_empty()).is_false()
	for entry: ItemAmount in GROUND.yields:
		assert_object(entry.item_def).is_not_null()
		assert_int(entry.count).is_greater(0)


func test_apply_box_carves_and_grants_yields() -> void:
	var player := _sandbox.make_player()
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	grid.material_def = GROUND
	var center := Vector3(4.5, 2.5, 4.5)

	var action := DigAction.new()
	action._apply(player, grid, center, DIG_TOOL)

	assert_int(grid.box_carves.size()).is_equal(1)
	assert_vector(grid.box_carves[0]["min"]).is_equal(Vector3(4.0, 2.0, 4.0))
	assert_vector(grid.box_carves[0]["max"]).is_equal(Vector3(5.0, 3.0, 5.0))
	var yield_entry: ItemAmount = GROUND.yields[0]
	assert_bool(player.inventory.has_item(yield_entry.item_def.id, yield_entry.count)).is_true()
	assert_int(_sandbox.skill_uses(player.skill_set, "mining")).is_equal(1)


func test_apply_sphere_carves_when_configured() -> void:
	var player := _sandbox.make_player()
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	grid.material_def = GROUND
	var center := Vector3(4.0, 2.0, 4.0)

	var sphere_tool := DigToolParams.new()
	auto_free(sphere_tool)
	sphere_tool.shape = DigToolParams.Shape.SPHERE
	sphere_tool.carve_radius = 1.5

	var action := DigAction.new()
	action._apply(player, grid, center, sphere_tool)

	assert_int(grid.carves.size()).is_equal(1)
	assert_vector(grid.carves[0]["pos"]).is_equal(center)
	assert_float(grid.carves[0]["radius"]).is_equal(1.5)


## Per-position identity: the def at the dig position decides the yields —
## a rock-position dig drops stone even when the grid's default is ground.
func test_apply_yields_come_from_the_dig_position_not_the_default() -> void:
	var player := _sandbox.make_player()
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	grid.default_material = GROUND
	grid.material_def = ROCK

	var action := DigAction.new()
	action._apply(player, grid, Vector3(0.0, -10.0, 0.0), DIG_TOOL)

	var ground_yield: ItemAmount = GROUND.yields[0]
	assert_bool(player.inventory.has_item(ground_yield.item_def.id, ground_yield.count)).is_false()
	var rock_yield: ItemAmount = ROCK.yields[0]
	assert_bool(player.inventory.has_item(rock_yield.item_def.id, rock_yield.count)).is_true()


func test_apply_without_default_material_still_carves() -> void:
	var player := _sandbox.make_player()
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	grid.default_material = null
	var center := Vector3(1.5, 3.5, 1.5)

	var action := DigAction.new()
	action._apply(player, grid, center, DIG_TOOL)

	# No material identity = no yields, but the carve (and the labor) happened.
	assert_int(grid.box_carves.size()).is_equal(1)
	assert_int(_sandbox.skill_uses(player.skill_set, "mining")).is_equal(1)


func test_timed_dig_locks_busy_then_carves_on_completion() -> void:
	var player := _sandbox.make_player()
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	grid.material_def = GROUND
	var center := Vector3(1.5, 3.5, 1.5)

	var fast_tool := DigToolParams.new()
	auto_free(fast_tool)
	fast_tool.work_time = 0.05
	fast_tool.shape = DigToolParams.Shape.BOX
	fast_tool.box_size = Vector3(1.0, 1.0, 1.0)

	var action := DigAction.new()
	action.begin(player, grid, center, fast_tool)
	assert_bool(player.is_busy()).is_true()
	assert_int(grid.box_carves.size()).is_equal(0)

	var waited := 0.0
	while player.is_busy() and waited < 3.0:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05

	assert_bool(player.is_busy()).is_false()
	assert_int(grid.box_carves.size()).is_equal(1)
	assert_vector(grid.box_carves[0]["min"]).is_equal(Vector3(1.0, 3.0, 1.0))
	assert_vector(grid.box_carves[0]["max"]).is_equal(Vector3(2.0, 4.0, 2.0))
	var yield_entry: ItemAmount = GROUND.yields[0]
	assert_bool(player.inventory.has_item(yield_entry.item_def.id, yield_entry.count)).is_true()


## box_samples: a snapped 1x1x1 dig (bounds exactly on cell edges) clears ALL
## 8 corner samples of the struck cell — the regression pin for incline-edge
## digs. On a steep face the min-corner sample is already air and the surface
## is held up by a higher corner; clearing only the min corner left the mound
## standing (the silent no-op dig).
func test_box_samples_clears_all_corners_of_the_struck_cell() -> void:
	var samples := SmoothGrid.box_samples(Vector3(4.0, 2.0, 4.0), Vector3(5.0, 3.0, 5.0))
	assert_int(samples.size()).is_equal(8)
	assert_bool(samples.has(Vector3i(4, 2, 4))).is_true()
	assert_bool(samples.has(Vector3i(5, 3, 5))).is_true()
	# The corner above the min sample — the one holding an incline-edge
	# surface up when the min sample is on the air side.
	assert_bool(samples.has(Vector3i(4, 3, 4))).is_true()
	assert_bool(samples.has(Vector3i(5, 2, 5))).is_true()


## box_samples: a snapped 3x3x3 dig covers the 4x4x4 sample span matching the
## ghost's world extent — nothing beyond it.
func test_box_samples_covers_world_extent_for_3x3x3() -> void:
	var samples := SmoothGrid.box_samples(Vector3(3.0, 3.0, 3.0), Vector3(6.0, 6.0, 6.0))
	assert_int(samples.size()).is_equal(64)
	assert_bool(samples.has(Vector3i(3, 3, 3))).is_true()
	assert_bool(samples.has(Vector3i(6, 6, 6))).is_true()
	assert_bool(samples.has(Vector3i(2, 3, 3))).is_false()
	assert_bool(samples.has(Vector3i(7, 6, 6))).is_false()


## box_samples: negative coordinates — a box on the [-3, -2] edges covers the
## samples -3 and -2 per axis (ceil/floor must not truncate the wrong way).
func test_box_samples_negative_coordinates() -> void:
	var samples := SmoothGrid.box_samples(Vector3(-3.0, -3.0, -3.0), Vector3(-2.0, -2.0, -2.0))
	assert_int(samples.size()).is_equal(8)
	assert_bool(samples.has(Vector3i(-3, -2, -3))).is_true()
	assert_bool(samples.has(Vector3i(-2, -3, -2))).is_true()


## box_samples: unsnapped fractional bounds cover the integer samples INSIDE
## the closed box only — sample 4 sits below 4.2 and stays.
func test_box_samples_fractional_bounds() -> void:
	var samples := SmoothGrid.box_samples(Vector3(4.2, 2.0, 4.0), Vector3(5.1, 3.0, 5.0))
	assert_int(samples.size()).is_equal(4)
	assert_bool(samples.has(Vector3i(5, 2, 4))).is_true()
	assert_bool(samples.has(Vector3i(5, 3, 5))).is_true()
	assert_bool(samples.has(Vector3i(4, 2, 4))).is_false()


## The BOX dig target snaps to the CENTER of the struck cell (floor + 0.5) —
## never the nearest lattice vertex — so the ghost box outlines exactly the
## cells carve_box clears. Both call sites (ghost + dig) share this math.
func test_calculate_dig_target_snaps_to_struck_cell_center() -> void:
	var controller := BuildController.new()
	auto_free(controller)
	var straight := {"point": Vector3(4.6, 2.3, -3.7), "normal": Vector3.UP}
	assert_vector(controller._calculate_dig_target(straight)).is_equal(Vector3(4.5, 2.5, -3.5))
	# Diagonal normal nudging the sample across the origin: floor must land in
	# cell (-1, -1, -1), i.e. the negative-side cell, not round-to-zero.
	var diagonal := {"point": Vector3(0.0, 0.0, 0.0), "normal": Vector3(1.0, 1.0, 1.0).normalized()}
	assert_vector(controller._calculate_dig_target(diagonal)).is_equal(Vector3(-0.5, -0.5, -0.5))
