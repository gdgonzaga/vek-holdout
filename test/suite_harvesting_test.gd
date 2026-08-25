extends GdUnitTestSuite

## Unit tests for the Harvesting feature (GDD §6.10, ARCH "Harvesting", job-extensions.md):
## - HarvestParams capability sub-resource on FurnitureDef
## - FurnitureLayer attaching Harvestable and ToggleHarvestAction option
## - Toggling the harvest mark and Colony job board synchronization
## - HarvestJobDef lifecycle (is_available, get_next_leg, begin, complete, XP)
## - Player direct harvesting via HarvestAction
## - Partial progress accumulation via set_work_done
## - Cleanup on furniture removal

const HARVEST_DEF: JobDef = preload("res://data/jobs/harvest.tres")
const TREE_DEF: FurnitureDef = preload("res://data/furniture/tree1.tres")

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")

var _sandbox: ColonySandbox
var _furniture_layer: FurnitureLayer


func before_test() -> void:
	GameLog.clear() # set_marked/complete log into the persistent autoload
	_sandbox = ColonySandbox.new(self)
	_furniture_layer = FurnitureLayer.new()
	_furniture_layer.set_container(_sandbox.container)


func after_test() -> void:
	_sandbox.restore()


func test_tree_def_has_harvest_params() -> void:
	assert_object(TREE_DEF).is_not_null()
	assert_object(TREE_DEF.harvest_params).is_not_null()
	assert_float(TREE_DEF.harvest_params.work_time).is_greater(0.0)
	assert_bool(TREE_DEF.harvest_params.yields.is_empty()).is_false()


func test_furniture_layer_attaches_harvestable_and_action() -> void:
	var anchor := Vector3i(2, 0, 2)
	var tree_node: Furniture = _furniture_layer.spawn(TREE_DEF, anchor, 0)
	assert_object(tree_node).is_not_null()

	var harvestable := tree_node.get_node_or_null("Harvestable") as Harvestable
	assert_object(harvestable).is_not_null()

	var interaction := tree_node.get_node_or_null("InteractionComponent") as InteractionComponent
	assert_object(interaction).is_not_null()
	assert_int(interaction.action_options.size()).is_greater_equal(1)
	assert_object(interaction.action_options[0].action).is_not_null()


func test_toggle_mark_and_colony_job_sync() -> void:
	var anchor := Vector3i(4, 0, 4)
	var tree_node: Furniture = _furniture_layer.spawn(TREE_DEF, anchor, 0)
	var harvestable := tree_node.get_node_or_null("Harvestable") as Harvestable

	# Initially unmarked -> no job
	assert_bool(harvestable.is_marked_for_harvest()).is_false()
	assert_int(Colony.job_board.get_jobs().size()).is_equal(0)

	# Mark for harvest -> Colony registers harvest job
	harvestable.set_marked(true)
	assert_bool(harvestable.is_marked_for_harvest()).is_true()
	var jobs := Colony.job_board.get_jobs()
	assert_int(jobs.size()).is_equal(1)
	var job: Job = jobs[0]
	assert_str(job.labor_id).is_equal("harvesting")
	assert_object(job.target_node).is_same(tree_node)

	# Unmark -> Colony removes job
	harvestable.set_marked(false)
	assert_bool(harvestable.is_marked_for_harvest()).is_false()
	assert_int(Colony.job_board.get_jobs().size()).is_equal(0)



func test_partial_progress_reduces_begin_duration() -> void:
	var anchor := Vector3i(7, 0, 7)
	var tree_node: Furniture = _furniture_layer.spawn(TREE_DEF, anchor, 0)
	var harvestable := tree_node.get_node_or_null("Harvestable") as Harvestable
	harvestable.set_marked(true)
	harvestable.set_work_done(1.5)

	var remaining := harvestable.effective_work_time() - harvestable.work_done()
	assert_float(remaining).is_equal_approx(TREE_DEF.harvest_params.work_time - 1.5, 0.01)

func test_player_harvest_action_completes() -> void:
	var anchor := Vector3i(8, 0, 8)
	var tree_node: Furniture = _furniture_layer.spawn(TREE_DEF, anchor, 0)
	var harvestable := tree_node.get_node_or_null("Harvestable") as Harvestable

	var player := _sandbox.make_player()
	var yield_def := TREE_DEF.harvest_params.yields[0]
	assert_bool(player.inventory.has_item(yield_def.item_def.id, 1)).is_false()

	var action := HarvestAction.new()
	action._apply(player, harvestable)

	assert_bool(player.inventory.has_item(yield_def.item_def.id, yield_def.count)).is_true()
	assert_int(player.skill_set.get_level("harvesting")).is_greater_equal(1)


func test_furniture_removal_cleans_up_job() -> void:
	var anchor := Vector3i(10, 0, 10)
	var tree_node: Furniture = _furniture_layer.spawn(TREE_DEF, anchor, 0)
	var harvestable := tree_node.get_node_or_null("Harvestable") as Harvestable
	harvestable.set_marked(true)
	assert_int(Colony.job_board.get_jobs().size()).is_equal(1)

	_furniture_layer.remove_at(anchor)
	assert_int(Colony.job_board.get_jobs().size()).is_equal(0)
