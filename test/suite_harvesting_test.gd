extends GdUnitTestSuite

## Unit tests for the Harvesting feature (GDD §6.10, ARCH "Harvesting", job-extensions.md):
## - HarvestParams capability sub-resource on FurnitureDef
## - FurnitureLayer attaching Harvestable and ToggleHarvestAction option
## - Toggling the harvest mark and Colony job board synchronization
## - HarvestJobDef lifecycle (is_available, should_close, begin, complete)
## - Player direct harvesting via HarvestAction
## - Partial progress accumulation via set_work_done
## - Cleanup on furniture removal

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")
const ItemDbSandbox = preload("res://test/helpers/item_db_sandbox.gd")

var _sandbox: ColonySandbox
var _items: ItemDbSandbox
var _furniture_layer: FurnitureLayer


func before_test() -> void:
	GameLog.clear() # set_marked/complete log into the persistent autoload
	_sandbox = ColonySandbox.new(self)
	_items = ItemDbSandbox.new(self)
	_furniture_layer = FurnitureLayer.new()
	_furniture_layer.set_container(_sandbox.container)


func after_test() -> void:
	_sandbox.restore()
	_items.restore()


func _make_harvestable_def(p_id: String = "test_harvestable", p_work_time: float = 3.0) -> FurnitureDef:
	var def := FurnitureDef.new()
	def.id = p_id
	def.display_name = "Harvestable Node"
	def.hp = 100
	def.mesh = BoxMesh.new()

	var item_amount := ItemAmount.new()
	# Register through the sandbox so the entry is undone in after_test rather
	# than leaking into ItemDB for every later suite.
	var item_def := _items.add_item("test_resource")
	item_def.weight = 1.0
	item_amount.item_def = item_def
	item_amount.count = 3

	var hparams := HarvestParams.new()
	hparams.work_time = p_work_time
	hparams.yields = [item_amount]

	def.harvest_params = hparams
	return def


func test_harvestable_def_has_harvest_params() -> void:
	var def := _make_harvestable_def()
	assert_object(def).is_not_null()
	assert_object(def.harvest_params).is_not_null()
	assert_float(def.harvest_params.work_time).is_greater(0.0)
	assert_bool(def.harvest_params.yields.is_empty()).is_false()


func test_furniture_layer_attaches_harvestable_and_action() -> void:
	var def := _make_harvestable_def("test_attach")
	var anchor := Vector3i(2, 0, 2)
	var node: Furniture = _furniture_layer.spawn(def, anchor, 0)
	assert_object(node).is_not_null()

	var harvestable := node.get_node_or_null("Harvestable") as Harvestable
	assert_object(harvestable).is_not_null()

	var interaction := node.get_node_or_null("InteractionComponent") as InteractionComponent
	assert_object(interaction).is_not_null()
	assert_int(interaction.action_options.size()).is_greater_equal(1)
	assert_object(interaction.action_options[0].action).is_not_null()


func test_toggle_mark_and_colony_job_sync() -> void:
	var def := _make_harvestable_def("test_sync")
	var anchor := Vector3i(4, 0, 4)
	var node: Furniture = _furniture_layer.spawn(def, anchor, 0)
	var harvestable := node.get_node_or_null("Harvestable") as Harvestable

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
	assert_object(job.target_node).is_same(node)

	# Unmark -> Colony removes job
	harvestable.set_marked(false)
	assert_bool(harvestable.is_marked_for_harvest()).is_false()
	assert_int(Colony.job_board.get_jobs().size()).is_equal(0)


func test_partial_progress_reduces_begin_duration() -> void:
	# 10 s job with 4 s already done begins with 6 s remaining (HarvestJobDef.begin
	# itself, not a locally recomputed formula — the tautology this replaces).
	var def := _make_harvestable_def("test_duration", 10.0)
	var anchor := Vector3i(7, 0, 7)
	var node: Furniture = _furniture_layer.spawn(def, anchor, 0)
	var harvestable := node.get_node_or_null("Harvestable") as Harvestable
	harvestable.set_marked(true)
	harvestable.set_work_done(4.0)

	var job := Job.new()
	job.target_node = node
	var remaining := HarvestJobDef.new().begin(null, job)
	assert_float(remaining).is_equal(6.0)


func test_harvestable_get_stat_ratio_tracks_work_progress() -> void:
	var def := _make_harvestable_def("test_stat_ratio")
	var anchor := Vector3i(12, 0, 12)
	var node: Furniture = _furniture_layer.spawn(def, anchor, 0)
	var harvestable := node.get_node_or_null("Harvestable") as Harvestable

	assert_float(harvestable.get_stat_ratio(&"work_progress")).is_equal_approx(0.0, 0.001)

	harvestable.set_work_done(1.5)
	var expected: float = 1.5 / def.harvest_params.work_time
	assert_float(harvestable.get_stat_ratio(&"work_progress")).is_equal_approx(expected, 0.001)
	assert_float(harvestable.get_stat_value(&"work_progress")).is_equal_approx(1.5, 0.001)

	assert_float(harvestable.get_stat_ratio(&"nonexistent_stat")).is_equal_approx(-1.0, 0.001)
	assert_float(harvestable.get_stat_value(&"nonexistent_stat")).is_equal_approx(-1.0, 0.001)


func test_player_harvest_action_completes() -> void:
	var def := _make_harvestable_def("test_player_action")
	var anchor := Vector3i(8, 0, 8)
	var node: Furniture = _furniture_layer.spawn(def, anchor, 0)
	var harvestable := node.get_node_or_null("Harvestable") as Harvestable

	var player := _sandbox.make_player()
	var yield_def := def.harvest_params.yields[0]
	assert_bool(player.inventory.has_item(yield_def.item_def.id, 1)).is_false()

	var action := HarvestAction.new()
	action._apply(player, harvestable)

	# Verify WorldItem drop was spawned in the world
	var world_items := get_tree().get_nodes_in_group("world_items")
	assert_int(world_items.size()).is_greater_equal(1)
	var dropped_item := world_items[-1] as WorldItem
	assert_str(dropped_item.item_id).is_equal(yield_def.item_def.id)
	assert_int(dropped_item.count).is_equal(yield_def.count)

	# Verify player picking up the dropped item
	var pickup := PickupAction.new()
	pickup.execute(player, dropped_item)
	assert_bool(player.inventory.has_item(yield_def.item_def.id, yield_def.count)).is_true()
	assert_int(player.skill_set.get_level("harvesting")).is_greater_equal(1)


func test_furniture_removal_cleans_up_job() -> void:
	var def := _make_harvestable_def("test_cleanup")
	var anchor := Vector3i(10, 0, 10)
	var node: Furniture = _furniture_layer.spawn(def, anchor, 0)
	var harvestable := node.get_node_or_null("Harvestable") as Harvestable
	harvestable.set_marked(true)
	assert_int(Colony.job_board.get_jobs().size()).is_equal(1)

	_furniture_layer.remove_at(anchor)
	assert_int(Colony.job_board.get_jobs().size()).is_equal(0)


# --- Wild Flora chop/removal (ARCH "Wild Flora") -----------------------------

func _make_wild_flora_def(p_id: String, p_required_tool_tag: String = "", p_can_chop: bool = true) -> WildFloraDef:
	var def := WildFloraDef.new()
	def.id = p_id
	def.display_name = "Test Flora"
	def.hp = 50
	def.growth_time_hours = 0.0
	def.required_tool_tag = p_required_tool_tag
	def.chop_work_time = 5.0

	var item_amount := ItemAmount.new()
	var item_def := _items.add_item("test_flora_drop")
	item_def.weight = 1.0
	item_amount.item_def = item_def
	item_amount.count = 2

	var stage := WildFloraStage.new()
	stage.max_hp = 50
	stage.can_chop = p_can_chop
	stage.fell_yields = [item_amount]
	def.stages = [stage]
	return def


func test_wild_flora_marked_routes_to_chop_def_when_tool_required() -> void:
	var def := _make_wild_flora_def("test_chop_route", "axe")
	var anchor := Vector3i(20, 0, 20)
	var node: Furniture = _furniture_layer.spawn(def, anchor, 0)
	var harvestable := node.get_node_or_null("Harvestable") as Harvestable

	harvestable.set_marked(true)
	var jobs := Colony.job_board.get_jobs()
	assert_int(jobs.size()).is_equal(1)
	assert_str(jobs[0].def.id).is_equal("chop")


func test_wild_flora_marked_routes_to_harvest_def_when_no_tool_required() -> void:
	var def := _make_wild_flora_def("test_removal_route", "")
	var anchor := Vector3i(22, 0, 22)
	var node: Furniture = _furniture_layer.spawn(def, anchor, 0)
	var harvestable := node.get_node_or_null("Harvestable") as Harvestable

	harvestable.set_marked(true)
	var jobs := Colony.job_board.get_jobs()
	assert_int(jobs.size()).is_equal(1)
	assert_str(jobs[0].def.id).is_equal("harvest")


func test_wild_flora_effective_work_time_uses_chop_work_time() -> void:
	var def := _make_wild_flora_def("test_flora_work_time")
	var anchor := Vector3i(24, 0, 24)
	var node: Furniture = _furniture_layer.spawn(def, anchor, 0)
	var harvestable := node.get_node_or_null("Harvestable") as Harvestable

	assert_float(harvestable.effective_work_time()).is_equal_approx(def.chop_work_time, 0.01)


func test_harvestable_complete_fells_wild_flora_and_grants_yields() -> void:
	var def := _make_wild_flora_def("test_flora_complete")
	var anchor := Vector3i(26, 0, 26)
	var node: Furniture = _furniture_layer.spawn(def, anchor, 0)
	var flora := node as WildFlora
	var harvestable := node.get_node_or_null("Harvestable") as Harvestable

	var result := harvestable.complete(null)
	assert_bool(result).is_true()
	assert_bool(flora.health_component.is_dead).is_true()
	assert_bool(_furniture_layer.has_at(anchor)).is_false()

	var items := get_tree().get_nodes_in_group("world_items")
	var found := false
	for it in items:
		var wi := it as WorldItem
		if wi != null and is_instance_valid(wi) and wi.item_id == "test_flora_drop":
			found = true
			break
	assert_bool(found).is_true()


func test_wild_flora_unmark_cleans_up_job() -> void:
	var def := _make_wild_flora_def("test_flora_unmark", "axe")
	var anchor := Vector3i(28, 0, 28)
	var node: Furniture = _furniture_layer.spawn(def, anchor, 0)
	var harvestable := node.get_node_or_null("Harvestable") as Harvestable

	harvestable.set_marked(true)
	assert_int(Colony.job_board.get_jobs().size()).is_equal(1)
	harvestable.set_marked(false)
	assert_int(Colony.job_board.get_jobs().size()).is_equal(0)


func test_is_claimable_false_when_stage_not_choppable() -> void:
	var def := _make_wild_flora_def("test_flora_unclaimable", "", false)
	var anchor := Vector3i(30, 0, 30)
	var node: Furniture = _furniture_layer.spawn(def, anchor, 0)
	var harvestable := node.get_node_or_null("Harvestable") as Harvestable

	harvestable.set_marked(true)
	assert_bool(harvestable.is_marked_for_harvest()).is_true()
	assert_bool(harvestable.is_claimable()).is_false()
