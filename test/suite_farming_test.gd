extends GdUnitTestSuite

## Unit tests for the Farming Subsystem (GDD §6 / Farming, ARCH "Farming"):
## - CropDef catalog and CropYieldTier definitions
## - FurnitureLayer attaching Growable and Harvestable to farm plots
## - Crop growth, hydration decay, and state transitions
## - Milestone and decay-based tending mechanics
## - Dynamic yield tiers, early harvesting, and neglect penalties
## - Skill and equipment gating on planting/tending
## - Colony JobBoard dispatch (Sow, Water, Tend, and unified Harvest)
## - Player manual context-sensitive farming (FarmManualAction)
## - Persistence round-trip for farm plots and crops

const TROUGH_DEF: FurnitureDef = preload("res://data/furniture/growing_trough.tres")
const SOW_JOB_DEF: JobDef = preload("res://data/jobs/sow.tres")
const WATER_JOB_DEF: JobDef = preload("res://data/jobs/water.tres")
const TEND_JOB_DEF: JobDef = preload("res://data/jobs/tend.tres")
const HARVEST_JOB_DEF: JobDef = preload("res://data/jobs/harvest.tres")
const PRUNING_KIT_DEF: ItemDef = preload("res://data/items/pruning_kit.tres")

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")

var _sandbox: ColonySandbox
var _furniture_layer: FurnitureLayer


func before_test() -> void:
	GameLog.clear() # plant()/harvest log into the persistent autoload
	_sandbox = ColonySandbox.new(self)
	_furniture_layer = FurnitureLayer.new()
	_furniture_layer.set_container(_sandbox.container)
	CropLibrary.reload()


func after_test() -> void:
	_sandbox.restore()


func test_crop_definitions_and_yield_tiers() -> void:
	var spud := CropLibrary.get_crop("cave_spud")
	assert_object(spud).is_not_null()
	assert_str(spud.display_name).is_equal("Cave Spud")
	assert_float(spud.water_decay_per_hour).is_equal_approx(1.0, 0.01)
	assert_int(spud.tending_mode).is_equal(0) # NONE
	assert_int(spud.yield_tiers.size()).is_equal(2)

	var wheat := CropLibrary.get_crop("holdout_wheat")
	assert_object(wheat).is_not_null()
	assert_int(wheat.tending_mode).is_equal(1) # MILESTONE
	assert_int(wheat.tending_milestones.size()).is_equal(1)
	assert_float(wheat.tending_milestones[0]).is_equal_approx(0.5, 0.01)

	var orchid := CropLibrary.get_crop("bio_gel_orchid")
	assert_object(orchid).is_not_null()
	assert_int(orchid.tending_mode).is_equal(2) # DECAY
	assert_int(orchid.tend_conditions.size()).is_equal(2)


func test_furniture_layer_spawns_farm_plot_with_components() -> void:
	var anchor := Vector3i(2, 0, 2)
	var trough: Furniture = _furniture_layer.spawn(TROUGH_DEF, anchor, 0)
	assert_object(trough).is_not_null()

	var growable := trough.get_node_or_null("Growable") as Growable
	assert_object(growable).is_not_null()
	assert_int(growable.get_crop_state()).is_equal(int(Growable.CropState.EMPTY))

	var harvestable := trough.get_node_or_null("Harvestable") as Harvestable
	assert_object(harvestable).is_not_null()

	var interaction := trough.get_node_or_null("InteractionComponent") as InteractionComponent
	assert_object(interaction).is_not_null()
	assert_int(interaction.action_options.size()).is_greater_equal(2)


func test_growable_lifecycle_plant_water_mature() -> void:
	var anchor := Vector3i(4, 0, 4)
	var trough: Furniture = _furniture_layer.spawn(TROUGH_DEF, anchor, 0)
	var growable := trough.get_node_or_null("Growable") as Growable
	var harvestable := trough.get_node_or_null("Harvestable") as Harvestable

	# 1. Plant Cave Spud
	var planted := growable.plant("cave_spud")
	assert_bool(planted).is_true()
	assert_int(growable.get_crop_state()).is_equal(int(Growable.CropState.GROWING))
	assert_str(growable.get_current_crop_id()).is_equal("cave_spud")
	assert_float(growable.get_growth_progress()).is_equal_approx(0.0, 0.01)
	assert_float(growable.get_water_level()).is_equal_approx(100.0, 0.01)

	# 2. Hydration decay & thirsty check
	growable.set_water_level(25.0) # below 30% thirsty threshold
	assert_bool(growable.needs_water()).is_true()

	# 3. Water restores hydration
	var colonist := _sandbox.make_colonist()
	growable.water(colonist)
	assert_float(growable.get_water_level()).is_equal_approx(100.0, 0.01)
	assert_bool(growable.needs_water()).is_false()

	# 4. Advance growth to 1.0 (Mature)
	growable.set_growth_progress(1.0)
	growable.set_crop_state(Growable.CropState.MATURE)
	harvestable.set_marked(true) # auto-marked by growable at maturity

	assert_bool(harvestable.is_marked_for_harvest()).is_true()
	assert_bool(growable.can_be_harvested()).is_true()


func test_tending_milestones_and_decay() -> void:
	var anchor := Vector3i(6, 0, 6)
	var trough: Furniture = _furniture_layer.spawn(TROUGH_DEF, anchor, 0)
	var growable := trough.get_node_or_null("Growable") as Growable

	# Wheat has milestone tending at 50%
	growable.plant("holdout_wheat")
	growable.set_growth_progress(0.4)
	assert_bool(growable.needs_tending()).is_false()

	# Cross 50% milestone
	growable.set_growth_progress(0.55)
	growable.set_is_tended(false)
	assert_bool(growable.needs_tending()).is_true()

	# Tend clears untended state
	var colonist := _sandbox.make_colonist()
	growable.tend(colonist)
	assert_bool(growable.needs_tending()).is_false()


func test_early_harvest_dynamic_yields_and_neglect_penalty() -> void:
	var anchor := Vector3i(8, 0, 8)
	var trough: Furniture = _furniture_layer.spawn(TROUGH_DEF, anchor, 0)
	var growable := trough.get_node_or_null("Growable") as Growable
	var harvestable := trough.get_node_or_null("Harvestable") as Harvestable

	growable.plant("cave_spud")

	# Below 50% progress -> no yields
	growable.set_growth_progress(0.3)
	assert_int(growable.get_harvest_yields().size()).is_equal(0)

	# 50% progress -> tier 1 (4 spuds)
	growable.set_growth_progress(0.6)
	var half_yields := growable.get_harvest_yields()
	assert_int(half_yields.size()).is_equal(1)
	assert_str(half_yields[0].item_def.id).is_equal("cave_spud")
	assert_int(half_yields[0].count).is_equal(4)

	# 100% progress -> tier 2 (10 spuds)
	growable.set_growth_progress(1.0)
	var full_yields := growable.get_harvest_yields()
	assert_int(full_yields.size()).is_equal(1)
	assert_int(full_yields[0].count).is_equal(10)

	# Neglect penalty (holdout_wheat: 6h grace, -25% yield per 6h past it, full
	# tier 15). neglect_time is _process-owned, so it's set through the state
	# bag exactly as the simulation loop would.
	var wheat_trough: Furniture = _furniture_layer.spawn(TROUGH_DEF, Vector3i(9, 0, 9), 0)
	var wheat_growable := wheat_trough.get_node_or_null("Growable") as Growable
	wheat_growable.plant("holdout_wheat")
	wheat_growable.set_growth_progress(1.0)
	assert_int(wheat_growable.get_harvest_yields()[0].count).is_equal(15) # tended baseline
	# 12h untended = one full period past the grace: round(15 * 0.75) = 11
	wheat_trough.state["growable"]["neglect_time"] = 12.0
	assert_int(wheat_growable.get_harvest_yields()[0].count).is_equal(11)
	# 30h = four periods: the penalty floors at zero — nothing left to harvest
	wheat_trough.state["growable"]["neglect_time"] = 30.0
	assert_int(wheat_growable.get_harvest_yields().size()).is_equal(0)

	# Complete harvest via Harvestable (spawns WorldItem on ground)
	var colonist := _sandbox.make_colonist()
	var completed := harvestable.complete(colonist)
	assert_bool(completed).is_true()

	var world_items := get_tree().get_nodes_in_group("world_items")
	assert_int(world_items.size()).is_greater_equal(1)
	var dropped_item := world_items[-1] as WorldItem
	assert_str(dropped_item.item_id).is_equal("cave_spud")
	assert_int(dropped_item.count).is_equal(10)

	# Verify pickup into inventory
	var pickup := PickupAction.new()
	pickup.execute(colonist, dropped_item)
	assert_bool(colonist.inventory.has_item("cave_spud", 10)).is_true()

	# Farm plot remains intact and resets to EMPTY
	assert_bool(is_instance_valid(trough)).is_true()
	assert_int(growable.get_crop_state()).is_equal(int(Growable.CropState.EMPTY))
	assert_str(growable.get_current_crop_id()).is_equal("")


func test_gating_conditions_on_sow_and_tend_jobs() -> void:
	var anchor := Vector3i(10, 0, 10)
	var trough: Furniture = _furniture_layer.spawn(TROUGH_DEF, anchor, 0)
	var growable := trough.get_node_or_null("Growable") as Growable

	# Bio-Gel Orchid requires Farming Lvl 2 + gardening_tool item
	growable.set_selected_crop("bio_gel_orchid")
	growable.plant("bio_gel_orchid")
	growable.set_is_tended(false)

	var colonist := _sandbox.make_colonist()
	# Unskilled colonist (farming lvl 1, no tool)
	assert_int(colonist.skill_set.get_level("farming")).is_equal(1)

	var job := Job.from_def(TEND_JOB_DEF)
	job.target_node = trough
	assert_bool(TEND_JOB_DEF.meets_requirements(colonist, job)).is_false()

	# Level up colonist farming to 2
	for i in range(20):
		colonist.skill_set.record_use("farming")
	assert_int(colonist.skill_set.get_level("farming")).is_greater_equal(2)

	# Still lacks tool
	assert_bool(TEND_JOB_DEF.meets_requirements(colonist, job)).is_false()

	# Give pruning kit (tag: gardening_tool)
	colonist.inventory.add("pruning_kit", 1)
	assert_bool(TEND_JOB_DEF.meets_requirements(colonist, job)).is_true()


func test_colony_job_board_farming_dispatch() -> void:
	var anchor := Vector3i(12, 0, 12)
	var trough: Furniture = _furniture_layer.spawn(TROUGH_DEF, anchor, 0)
	var growable := trough.get_node_or_null("Growable") as Growable

	# 1. Select crop on empty plot -> SOW job spawned
	growable.set_selected_crop("cave_spud")
	var jobs := Colony.job_board.get_jobs()
	assert_int(jobs.size()).is_equal(1)
	assert_str(jobs[0].labor_id).is_equal("farming")
	assert_object(jobs[0].def).is_same(SOW_JOB_DEF)

	# 2. SOW job completion
	var colonist := _sandbox.make_colonist()
	growable.plant("cave_spud")
	assert_int(growable.get_crop_state()).is_equal(int(Growable.CropState.GROWING))

	# 3. Thirsty crop -> WATER job spawned
	growable.set_water_level(20.0)
	EventBus.plot_needs_water.emit(growable, anchor, true)
	var water_jobs: Array[Job] = []
	for j in Colony.job_board.get_jobs():
		if j.def == WATER_JOB_DEF:
			water_jobs.append(j)
	assert_int(water_jobs.size()).is_equal(1)

	growable.water(colonist)
	assert_float(growable.get_water_level()).is_equal_approx(100.0, 0.01)


func test_job_defs_and_growable_record_no_xp() -> void:
	var anchor := Vector3i(20, 0, 20)
	var trough: Furniture = _furniture_layer.spawn(TROUGH_DEF, anchor, 0)
	var growable := trough.get_node_or_null("Growable") as Growable
	var colonist := _sandbox.make_colonist()
	var player := _sandbox.make_player()

	growable.set_selected_crop("cave_spud")
	growable.plant("cave_spud")
	assert_int(_sandbox.skill_uses(colonist.skill_set, "farming")).is_equal(0)

	growable.set_water_level(20.0)
	growable.water(colonist)
	assert_float(growable.get_water_level()).is_equal_approx(100.0, 0.01)
	assert_int(_sandbox.skill_uses(colonist.skill_set, "farming")).is_equal(0)

	growable.set_is_tended(false)
	growable.tend(colonist)
	assert_bool(growable.is_tended()).is_true()
	assert_int(_sandbox.skill_uses(colonist.skill_set, "farming")).is_equal(0)

	growable.set_water_level(20.0)
	growable.water(player)
	growable.set_is_tended(false)
	growable.tend(player)


func test_player_farm_manual_action() -> void:
	var anchor := Vector3i(14, 0, 14)
	var trough: Furniture = _furniture_layer.spawn(TROUGH_DEF, anchor, 0)
	var growable := trough.get_node_or_null("Growable") as Growable

	growable.set_selected_crop("cave_spud")
	var player := _sandbox.make_player()
	var action := FarmManualAction.new()

	# Player plants directly
	growable.plant("cave_spud")
	assert_int(growable.get_crop_state()).is_equal(int(Growable.CropState.GROWING))

	# Player waters directly
	growable.set_water_level(10.0)
	growable.water(player)
	assert_float(growable.get_water_level()).is_equal_approx(100.0, 0.01)

	# Player tends directly
	growable.set_is_tended(false)
	growable.tend(player)
	assert_bool(growable.is_tended()).is_true()


func test_farm_plot_persistence() -> void:
	var anchor := Vector3i(16, 0, 16)
	var trough: Furniture = _furniture_layer.spawn(TROUGH_DEF, anchor, 0)
	var growable := trough.get_node_or_null("Growable") as Growable

	growable.plant("holdout_wheat")
	growable.set_growth_progress(0.72)
	growable.set_water_level(65.0)

	var serialized := trough.serialize()
	assert_dict(serialized).contains_keys(["def_id", "state"])

	# Create a fresh trough and deserialize
	var restored_trough: Furniture = _furniture_layer.spawn(TROUGH_DEF, Vector3i(18, 0, 18), 0)
	restored_trough.deserialize(serialized)

	var restored_growable := restored_trough.get_node_or_null("Growable") as Growable
	assert_object(restored_growable).is_not_null()
	assert_str(restored_growable.get_current_crop_id()).is_equal("holdout_wheat")
	assert_float(restored_growable.get_growth_progress()).is_equal_approx(0.72, 0.01)
	assert_float(restored_growable.get_water_level()).is_equal_approx(65.0, 0.01)
