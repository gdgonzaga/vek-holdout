extends GdUnitTestSuite

## Unit tests for the Farming Subsystem (GDD §6 / Farming, ARCH "Farming"):
## - FurnitureLayer attaching Growable and Harvestable to farm plots
## - Crop growth, hydration decay, and state transitions
## - Milestone and decay-based tending mechanics
## - Dynamic yield tiers, early harvesting, and neglect penalties
## - Skill and equipment gating on planting/tending
## - Colony JobBoard dispatch (Sow, Water, Tend, and unified Harvest)
## - Player manual context-sensitive farming (FarmManualAction)
## - Persistence round-trip for farm plots and crops
##
## Content-agnostic per AGENTS.md: every FurnitureDef and CropDef used here is
## built in memory (the bed_test/harvesting_test pattern). Nothing asserts
## against data/furniture/farming/*.tres or data/crops/*.tres, whose balance
## values are expected to move.

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")
const ItemDbSandbox = preload("res://test/helpers/item_db_sandbox.gd")

var _sandbox: ColonySandbox
var _items: ItemDbSandbox
var _furniture_layer: FurnitureLayer
var _preexisting_world_items: Array[Node] = []

## crop id (String) -> CropDef or null (nothing was registered under that id
## before this test). Snapshotted by _register_crop, undone by _restore_crops —
## the ItemDbSandbox pattern, CropLibrary-side (a shared static registry, not a
## per-suite helper, so it stays local to this one file per R7's Interfaces).
var _crop_previous: Dictionary = {}


func before_test() -> void:
	GameLog.clear() # plant()/harvest log into the persistent autoload
	# Harvest drops are parented to the current scene, not the sandbox container, so remember what was already there.
	_preexisting_world_items = get_tree().get_nodes_in_group("world_items")
	_sandbox = ColonySandbox.new(self)
	_items = ItemDbSandbox.new(self)
	_furniture_layer = FurnitureLayer.new()
	_furniture_layer.set_container(_sandbox.container)
	CropLibrary.reload()


func after_test() -> void:
	_sandbox.restore()
	_items.restore()
	_restore_crops()
	# A leaked edible drop (a crop yield) would be found as ground food by any later suite's StorageRegistry search.
	_free_world_items_added_by_test()


func _free_world_items_added_by_test() -> void:
	for node: Node in get_tree().get_nodes_in_group("world_items"):
		if is_instance_valid(node) and not _preexisting_world_items.has(node):
			node.free()
	_preexisting_world_items.clear()


# ── Fixtures (in-memory stand-ins for growing_trough.tres and data/crops/*.tres) ──

## In-memory farm-plot FurnitureDef standing in for growing_trough.tres:
## farm_plot_params alone is enough for FurnitureLayer to attach Growable +
## Harvestable + the plot's own interaction options (FarmPlotParams.
## collect_action_options, production code — untouched here).
func _make_trough_def() -> FurnitureDef:
	var def: FurnitureDef = auto_free(FurnitureDef.new())
	def.id = "test_trough"
	def.display_name = "Test Trough"
	def.dimensions = Vector3i.ONE
	def.mesh = BoxMesh.new()
	def.farm_plot_params = auto_free(FarmPlotParams.new())
	return def


## A CropYieldTier granting `count` of a fresh synthetic item at `min_progress`.
func _yield_tier(min_progress: float, item_id: String, count: int) -> CropYieldTier:
	var tier: CropYieldTier = auto_free(CropYieldTier.new())
	tier.min_growth_progress = min_progress
	var amount: ItemAmount = auto_free(ItemAmount.new())
	amount.item_def = _items.add_item(item_id)
	amount.count = count
	tier.yields = [amount]
	return tier


## Bare CropDef with only id/display_name set — every other field keeps CropDef's own default.
func _basic_crop(id: String) -> CropDef:
	var def: CropDef = auto_free(CropDef.new())
	def.id = id
	def.display_name = id
	return def


## A MILESTONE-tending CropDef that requires tending once progress crosses `milestone`.
func _milestone_crop(id: String, milestone: float) -> CropDef:
	var def := _basic_crop(id)
	def.tending_mode = CropDef.TendingMode.MILESTONE
	def.tending_milestones = [milestone]
	return def


## A CropDef with explicit yield tiers ([min_progress, item_id, count] triples)
## and, optionally, a neglect grace period (hours) + per-period yield penalty.
func _tiered_crop(id: String, tiers: Array, neglect_hours: float = 0.0, neglect_penalty: float = 0.0) -> CropDef:
	var def := _basic_crop(id)
	var built: Array[CropYieldTier] = []
	for entry: Array in tiers:
		built.append(_yield_tier(entry[0], entry[1], entry[2]))
	def.yield_tiers = built
	def.neglect_hours = neglect_hours
	def.neglect_yield_penalty = neglect_penalty
	return def


## Registers `def` into CropLibrary, remembering what was there under its id
## (or that nothing was) so _restore_crops can undo exactly this.
func _register_crop(def: CropDef) -> CropDef:
	if not _crop_previous.has(def.id):
		_crop_previous[def.id] = CropLibrary._crops_by_id.get(def.id, null)
	CropLibrary._crops_by_id[def.id] = def
	return def


## Undoes every _register_crop call this test made — run unconditionally in
## after_test so a failing assertion mid-test can't skip the erase.
func _restore_crops() -> void:
	for id: String in _crop_previous:
		if _crop_previous[id] != null:
			CropLibrary._crops_by_id[id] = _crop_previous[id]
		else:
			CropLibrary._crops_by_id.erase(id)
	_crop_previous.clear()


func test_furniture_layer_spawns_farm_plot_with_components() -> void:
	var anchor := Vector3i(2, 0, 2)
	var trough: Furniture = _furniture_layer.spawn(_make_trough_def(), anchor, 0)
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
	var crop := _register_crop(_basic_crop("test_crop_lifecycle"))
	var anchor := Vector3i(4, 0, 4)
	var trough: Furniture = _furniture_layer.spawn(_make_trough_def(), anchor, 0)
	var growable := trough.get_node_or_null("Growable") as Growable
	var harvestable := trough.get_node_or_null("Harvestable") as Harvestable

	# 1. Plant
	var planted := growable.plant(crop.id)
	assert_bool(planted).is_true()
	assert_int(growable.get_crop_state()).is_equal(int(Growable.CropState.GROWING))
	assert_str(growable.get_current_crop_id()).is_equal(crop.id)
	assert_float(growable.get_growth_progress()).is_equal_approx(0.0, 0.01)
	assert_float(growable.get_water_level()).is_equal_approx(100.0, 0.01)

	# 2. Hydration decay & thirsty check
	growable.set_water_level(25.0) # below the 30% default thirsty threshold
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
	var crop := _register_crop(_milestone_crop("test_crop_milestone", 0.5))
	var anchor := Vector3i(6, 0, 6)
	var trough: Furniture = _furniture_layer.spawn(_make_trough_def(), anchor, 0)
	var growable := trough.get_node_or_null("Growable") as Growable

	# Milestone tending fires at 50% progress.
	growable.plant(crop.id)
	growable.set_growth_progress(0.4)
	assert_bool(growable.needs_tending()).is_false()

	# Cross the 50% milestone
	growable.set_growth_progress(0.55)
	growable.set_is_tended(false)
	assert_bool(growable.needs_tending()).is_true()

	# Tend clears the untended state
	var colonist := _sandbox.make_colonist()
	growable.tend(colonist)
	assert_bool(growable.needs_tending()).is_false()


func test_early_harvest_dynamic_yields_and_neglect_penalty() -> void:
	# Yield tiers 4/8/12 at progress 0.34/0.67/1.0; a 4h neglect grace with a
	# 50% yield penalty per grace period exceeded (neglect_time is _process-
	# owned, so it's set through the state bag exactly as the simulation loop
	# would).
	var crop := _register_crop(_tiered_crop("test_yield_crop", [
		[0.34, "test_yield_low", 4],
		[0.67, "test_yield_mid", 8],
		[1.0, "test_yield_high", 12],
	], 4.0, 0.5))

	var anchor := Vector3i(8, 0, 8)
	var trough: Furniture = _furniture_layer.spawn(_make_trough_def(), anchor, 0)
	var growable := trough.get_node_or_null("Growable") as Growable
	var harvestable := trough.get_node_or_null("Harvestable") as Harvestable

	growable.plant(crop.id)

	# Below the lowest tier -> no yields.
	growable.set_growth_progress(0.2)
	assert_int(growable.get_harvest_yields().size()).is_equal(0)

	# 50% progress -> tier 1 (4).
	growable.set_growth_progress(0.5)
	var low_yields := growable.get_harvest_yields()
	assert_int(low_yields.size()).is_equal(1)
	assert_str(low_yields[0].item_def.id).is_equal("test_yield_low")
	assert_int(low_yields[0].count).is_equal(4)

	# 100% progress, unneglected -> tier 3 (12).
	growable.set_growth_progress(1.0)
	var full_yields := growable.get_harvest_yields()
	assert_int(full_yields.size()).is_equal(1)
	assert_int(full_yields[0].count).is_equal(12)

	# Neglect penalty on a second plot of the same crop, at full progress.
	var neglect_trough: Furniture = _furniture_layer.spawn(_make_trough_def(), Vector3i(9, 0, 9), 0)
	var neglect_growable := neglect_trough.get_node_or_null("Growable") as Growable
	neglect_growable.plant(crop.id)
	neglect_growable.set_growth_progress(1.0)
	# 8h = one full 4h period past grace: round(12 * (1.0 - 1 * 0.5)) = 6.
	neglect_trough.state["growable"]["neglect_time"] = 8.0
	assert_int(neglect_growable.get_harvest_yields()[0].count).is_equal(6)
	# 20h = four periods past grace: the penalty floors at zero.
	neglect_trough.state["growable"]["neglect_time"] = 20.0
	assert_int(neglect_growable.get_harvest_yields().size()).is_equal(0)

	# Complete harvest via Harvestable on the unneglected plot (spawns WorldItem on ground).
	var colonist := _sandbox.make_colonist()
	var completed := harvestable.complete(colonist)
	assert_bool(completed).is_true()

	var world_items := get_tree().get_nodes_in_group("world_items")
	assert_int(world_items.size()).is_greater_equal(1)
	var dropped_item := world_items[-1] as WorldItem
	assert_str(dropped_item.item_id).is_equal("test_yield_high")
	assert_int(dropped_item.count).is_equal(12)

	# Verify pickup into inventory
	var pickup := PickupAction.new()
	pickup.execute(colonist, dropped_item)
	assert_bool(colonist.inventory.has_item("test_yield_high", 12)).is_true()

	# Farm plot remains intact and resets to EMPTY
	assert_bool(is_instance_valid(trough)).is_true()
	assert_int(growable.get_crop_state()).is_equal(int(Growable.CropState.EMPTY))
	assert_str(growable.get_current_crop_id()).is_equal("")


func test_gating_conditions_on_sow_and_tend_jobs() -> void:
	var skill_gate: MinSkillCondition = auto_free(MinSkillCondition.new())
	skill_gate.skill_id = "farming"
	skill_gate.min_level = 2
	var tool_gate: HasItemCondition = auto_free(HasItemCondition.new())
	tool_gate.item_tag = "gardening_tool"
	tool_gate.count = 1
	var crop := _register_crop(_basic_crop("test_crop_gated"))
	crop.tend_conditions = [skill_gate, tool_gate]

	var anchor := Vector3i(10, 0, 10)
	var trough: Furniture = _furniture_layer.spawn(_make_trough_def(), anchor, 0)
	var growable := trough.get_node_or_null("Growable") as Growable

	growable.set_selected_crop(crop.id)
	growable.plant(crop.id)
	growable.set_is_tended(false)

	var colonist := _sandbox.make_colonist()
	# Unskilled colonist (farming L1, no tool)
	assert_int(colonist.skill_set.get_level("farming")).is_equal(1)

	var tend_def := TendJobDef.new()
	var job := Job.from_def(tend_def)
	job.target_node = trough
	assert_bool(tend_def.meets_requirements(colonist, job)).is_false()

	# Level up colonist farming to 2
	for i in range(20):
		colonist.skill_set.record_use("farming")
	assert_int(colonist.skill_set.get_level("farming")).is_greater_equal(2)

	# Still lacks tool
	assert_bool(tend_def.meets_requirements(colonist, job)).is_false()

	# Give the gated tool (tag: gardening_tool)
	_items.add_item("test_gardening_tool", "", ["gardening_tool"])
	colonist.inventory.add("test_gardening_tool", 1)
	assert_bool(tend_def.meets_requirements(colonist, job)).is_true()


func test_colony_job_board_farming_dispatch() -> void:
	var crop := _register_crop(_basic_crop("test_crop_dispatch"))
	var anchor := Vector3i(12, 0, 12)
	var trough: Furniture = _furniture_layer.spawn(_make_trough_def(), anchor, 0)
	var growable := trough.get_node_or_null("Growable") as Growable

	# 1. Select crop on empty plot -> SOW job spawned
	growable.set_selected_crop(crop.id)
	var jobs := Colony.job_board.get_jobs()
	assert_int(jobs.size()).is_equal(1)
	assert_str(jobs[0].labor_id).is_equal("farming")
	assert_bool(jobs[0].def is SowJobDef).is_true()

	# 2. SOW job completion
	var colonist := _sandbox.make_colonist()
	growable.plant(crop.id)
	assert_int(growable.get_crop_state()).is_equal(int(Growable.CropState.GROWING))

	# 3. Thirsty crop -> WATER job spawned
	growable.set_water_level(20.0)
	EventBus.plot_needs_water.emit(growable, anchor, true)
	var water_jobs: Array[Job] = []
	for j in Colony.job_board.get_jobs():
		if j.def is WaterJobDef:
			water_jobs.append(j)
	assert_int(water_jobs.size()).is_equal(1)

	growable.water(colonist)
	assert_float(growable.get_water_level()).is_equal_approx(100.0, 0.01)


func test_job_defs_and_growable_record_no_xp() -> void:
	var crop := _register_crop(_basic_crop("test_crop_no_xp"))
	var anchor := Vector3i(20, 0, 20)
	var trough: Furniture = _furniture_layer.spawn(_make_trough_def(), anchor, 0)
	var growable := trough.get_node_or_null("Growable") as Growable
	var colonist := _sandbox.make_colonist()
	var player := _sandbox.make_player()

	growable.set_selected_crop(crop.id)
	growable.plant(crop.id)
	assert_int(_sandbox.skill_uses(colonist.skill_set, "farming")).is_equal(0)

	growable.set_water_level(20.0)
	growable.water(colonist)
	assert_float(growable.get_water_level()).is_equal_approx(100.0, 0.01)
	assert_int(_sandbox.skill_uses(colonist.skill_set, "farming")).is_equal(0)

	growable.set_is_tended(false)
	growable.tend(colonist)
	assert_bool(growable.is_tended()).is_true()
	assert_int(_sandbox.skill_uses(colonist.skill_set, "farming")).is_equal(0)

	# The player path is XP-free for the same reason: water()/tend() never
	# record — only FarmManualAction's own gauge callback does (skills.md:
	# single XP entry point, not the component).
	assert_int(_sandbox.skill_uses(player.skill_set, "farming")).is_equal(0)
	growable.set_water_level(20.0)
	growable.water(player)
	growable.set_is_tended(false)
	growable.tend(player)
	assert_int(_sandbox.skill_uses(player.skill_set, "farming")).is_equal(0)


func test_player_farm_manual_action() -> void:
	var crop := _register_crop(_basic_crop("test_crop_manual"))
	var anchor := Vector3i(14, 0, 14)
	var trough: Furniture = _furniture_layer.spawn(_make_trough_def(), anchor, 0)
	var growable := trough.get_node_or_null("Growable") as Growable

	growable.set_selected_crop(crop.id)
	var player := _sandbox.make_player()

	# Player plants directly
	growable.plant(crop.id)
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
	var crop := _register_crop(_basic_crop("test_crop_persist"))
	var anchor := Vector3i(16, 0, 16)
	var trough: Furniture = _furniture_layer.spawn(_make_trough_def(), anchor, 0)
	var growable := trough.get_node_or_null("Growable") as Growable

	growable.plant(crop.id)
	growable.set_growth_progress(0.72)
	growable.set_water_level(65.0)

	var serialized := trough.serialize()
	assert_dict(serialized).contains_keys(["def_id", "state"])

	# Create a fresh trough and deserialize
	var restored_trough: Furniture = _furniture_layer.spawn(_make_trough_def(), Vector3i(18, 0, 18), 0)
	restored_trough.deserialize(serialized)

	var restored_growable := restored_trough.get_node_or_null("Growable") as Growable
	assert_object(restored_growable).is_not_null()
	assert_str(restored_growable.get_current_crop_id()).is_equal(crop.id)
	assert_float(restored_growable.get_growth_progress()).is_equal_approx(0.72, 0.01)
	assert_float(restored_growable.get_water_level()).is_equal_approx(65.0, 0.01)


func test_a_four_stage_crop_advances_through_every_stage() -> void:
	var crop := _register_crop(_tiered_crop("test_crop_stages", [
		[1.0, "test_stage_yield", 10],
	]))
	crop.growth_stages = 4

	var anchor := Vector3i(22, 0, 22)
	var trough: Furniture = _furniture_layer.spawn(_make_trough_def(), anchor, 0)
	var growable := trough.get_node_or_null("Growable") as Growable

	var planted := growable.plant(crop.id)
	assert_bool(planted).is_true()
	assert_int(growable.get_crop_state()).is_equal(int(Growable.CropState.GROWING))

	# Stage 0: 0.1 progress (newly planted)
	growable.set_growth_progress(0.1)
	assert_int(growable._current_visual_stage).is_equal(0)

	# Stage 1: 0.4 progress (growing #1)
	growable.set_growth_progress(0.4)
	assert_int(growable._current_visual_stage).is_equal(1)

	# Stage 2: 0.7 progress (growing #2)
	growable.set_growth_progress(0.7)
	assert_int(growable._current_visual_stage).is_equal(2)

	# Stage 3: 1.0 progress (mature)
	growable.set_growth_progress(1.0)
	growable.set_crop_state(Growable.CropState.MATURE)
	assert_int(growable._current_visual_stage).is_equal(3)

	var yields := growable.get_harvest_yields()
	assert_int(yields.size()).is_equal(1)
	assert_str(yields[0].item_def.id).is_equal("test_stage_yield")
	assert_int(yields[0].count).is_equal(10)


func test_crop_stage_scenes_instantiation() -> void:
	var custom_crop := _register_crop(_basic_crop("test_custom_crop"))
	custom_crop.growth_stages = 2

	var stage_node_0 := Node3D.new()
	stage_node_0.name = "CustomStage0"
	var scene_0 := PackedScene.new()
	scene_0.pack(stage_node_0)
	stage_node_0.free()

	var stage_node_1 := Node3D.new()
	stage_node_1.name = "CustomStage1"
	var scene_1 := PackedScene.new()
	scene_1.pack(stage_node_1)
	stage_node_1.free()

	custom_crop.stage_scenes = [scene_0, scene_1]

	var anchor := Vector3i(24, 0, 24)
	var trough: Furniture = _furniture_layer.spawn(_make_trough_def(), anchor, 0)
	var growable := trough.get_node_or_null("Growable") as Growable

	var planted := growable.plant(custom_crop.id)
	assert_bool(planted).is_true()
	assert_int(growable._current_visual_stage).is_equal(0)
	assert_object(growable._crop_visual_instance).is_not_null()
	assert_str(growable._crop_visual_instance.name).is_equal("CropVisual")

	# Progress to mature stage
	growable.set_growth_progress(1.0)
	growable.set_crop_state(Growable.CropState.MATURE)
	assert_int(growable._current_visual_stage).is_equal(1)
	assert_object(growable._crop_visual_instance).is_not_null()
	# _crop_previous still holds "test_custom_crop" -> after_test's
	# _restore_crops erases it, even if an assertion above had failed.
