extends GdUnitTestSuite

## Unit tests for the Phase 5 mining dig (docs/TODO.md Phase 5):
## - Data shape: DigToolParams, the mining skill + labor catalog entries,
##   TerrainMaterialDef.yields on the ground material
## - DigAction._apply: carve at the given center/radius + yields from the
##   material AT THE DIG POSITION (the RecordingSmoothGrid.material_def seam)
##   + mining XP (the HarvestAction._apply testing seam)
## - DigAction timed path: busy lock while the gauge runs, completion carves

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
	assert_float(DIG_TOOL.carve_radius).is_greater(0.0)


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


func test_apply_carves_and_grants_yields() -> void:
	var player := _sandbox.make_player()
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	grid.material_def = GROUND
	var center := Vector3(4.0, 2.0, 4.0)

	var action := DigAction.new()
	action._apply(player, grid, center, DIG_TOOL)

	assert_int(grid.carves.size()).is_equal(1)
	assert_that(grid.carves[0]["pos"]).is_equal(center)
	assert_float(grid.carves[0]["radius"]).is_equal(DIG_TOOL.carve_radius)
	var yield_entry: ItemAmount = GROUND.yields[0]
	assert_bool(player.inventory.has_item(yield_entry.item_def.id, yield_entry.count)).is_true()
	assert_int(_sandbox.skill_uses(player.skill_set, "mining")).is_equal(1)


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
	var center := Vector3(1.0, 3.0, 1.0)

	var action := DigAction.new()
	action._apply(player, grid, center, DIG_TOOL)

	# No material identity = no yields, but the carve (and the labor) happened.
	assert_int(grid.carves.size()).is_equal(1)
	assert_int(_sandbox.skill_uses(player.skill_set, "mining")).is_equal(1)


func test_timed_dig_locks_busy_then_carves_on_completion() -> void:
	var player := _sandbox.make_player()
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	grid.material_def = GROUND
	var center := Vector3(1.0, 3.0, 1.0)

	var fast_tool := DigToolParams.new()
	auto_free(fast_tool)
	fast_tool.work_time = 0.05
	fast_tool.carve_radius = DIG_TOOL.carve_radius

	var action := DigAction.new()
	action.begin(player, grid, center, fast_tool)
	assert_bool(player.is_busy()).is_true()
	assert_int(grid.carves.size()).is_equal(0)

	var waited := 0.0
	while player.is_busy() and waited < 3.0:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05

	assert_bool(player.is_busy()).is_false()
	assert_int(grid.carves.size()).is_equal(1)
	assert_that(grid.carves[0]["pos"]).is_equal(center)
	var yield_entry: ItemAmount = GROUND.yields[0]
	assert_bool(player.inventory.has_item(yield_entry.item_def.id, yield_entry.count)).is_true()
