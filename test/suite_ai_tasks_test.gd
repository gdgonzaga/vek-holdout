extends GdUnitTestSuite

## Unit tests for Phase 1-4 LimboAI tasks, master behavior trees, and Utility AI.

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")

const BTActionNavigateToScript = preload("res://subsystems/ai/tasks/actions/bt_action_navigate_to.gd")
const BTActionPerformWorkScript = preload("res://subsystems/ai/tasks/actions/bt_action_perform_work.gd")
const BTActionCalcHaulBatchScript = preload("res://subsystems/ai/tasks/actions/bt_action_calc_haul_batch.gd")
const BTActionWanderScript = preload("res://subsystems/ai/tasks/actions/bt_action_wander.gd")
const BTActionClaimJobScript = preload("res://subsystems/ai/tasks/actions/bt_action_claim_job.gd")
const BTActionUseSmartObjectScript = preload("res://subsystems/ai/tasks/actions/bt_action_use_smart_object.gd")
const BTActionHaulBatchScript = preload("res://subsystems/ai/tasks/actions/bt_action_haul_batch.gd")

const BTConditionHasToolScript = preload("res://subsystems/ai/tasks/conditions/bt_condition_has_tool.gd")
const BTConditionInGroupScript = preload("res://subsystems/ai/tasks/conditions/bt_condition_in_group.gd")
const BTConditionJobStillNeededScript = preload("res://subsystems/ai/tasks/conditions/bt_condition_job_still_needed.gd")

const BTActionScanThreatsScript = preload("res://subsystems/ai/tasks/actions/bt_action_scan_threats.gd")
const BTActionMeleeAttackScript = preload("res://subsystems/ai/tasks/actions/bt_action_melee_attack.gd")
const BTActionBreachVoxelScript = preload("res://subsystems/ai/tasks/actions/bt_action_breach_voxel.gd")
const BTConditionPathBlockedScript = preload("res://subsystems/ai/tasks/conditions/bt_condition_path_blocked.gd")

const BTTreeFactoryScript = preload("res://subsystems/ai/bt_tree_factory.gd")
const ColonistNeedsScript = preload("res://subsystems/ai/colonist_needs.gd")
const ColonistBrainScript = preload("res://subsystems/ai/colonist_brain.gd")

const CONSTRUCTION_DEF: JobDef = preload("res://data/jobs/construction.tres")
const HAULING_DEF: JobDef = preload("res://data/jobs/hauling.tres")

var _sandbox: ColonySandbox
var _blackboard: Blackboard
var _actor: CharacterBody3D


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)
	_blackboard = Blackboard.new()
	_actor = auto_free(CharacterBody3D.new()) as CharacterBody3D
	add_child(_actor)
	ColonistNeeds._defs_loaded = false
	ColonistNeeds._cached_need_defs.clear()
	if Colony.job_board != null:
		Colony.job_board.clear_blacklists()


func after_test() -> void:
	_sandbox.restore()
	ColonistNeeds._defs_loaded = false
	ColonistNeeds._cached_need_defs.clear()
	if Colony.job_board != null:
		Colony.job_board.clear_blacklists()


# ── BTActionNavigateTo ───────────────────────────────────────────────────────

func test_navigate_to_generates_descriptive_name() -> void:
	var task: BTAction = auto_free(BTActionNavigateToScript.new()) as BTAction
	task.target_var = &"custom_target"
	task.arrival_distance = 2.5
	var name_str: String = task._generate_name()
	assert_bool(name_str.contains("custom_target")).is_true()
	assert_bool(name_str.contains("2.5")).is_true()


func test_navigate_to_returns_failure_without_target() -> void:
	var task: BTAction = auto_free(BTActionNavigateToScript.new()) as BTAction
	task.initialize(_actor, _blackboard, _actor)
	var status: int = task.execute(0.1)
	assert_int(status).is_equal(BTAction.FAILURE)


func test_navigate_to_succeeds_when_within_arrival_distance() -> void:
	var task: BTAction = auto_free(BTActionNavigateToScript.new()) as BTAction
	_actor.global_position = Vector3(10, 0, 10)
	_blackboard.set_var(&"target_pos", Vector3(10.5, 0, 10))
	task.arrival_distance = 1.8
	task.initialize(_actor, _blackboard, _actor)
	
	var status: int = task.execute(0.1)
	assert_int(status).is_equal(BTAction.SUCCESS)


# ── BTActionPerformWork ──────────────────────────────────────────────────────

func test_perform_work_runs_for_duration_and_applies_units() -> void:
	var task: BTAction = auto_free(BTActionPerformWorkScript.new()) as BTAction
	task.default_duration = 0.5
	
	var work_applied: Array[int] = []
	var mock_job := {
		"apply_work_units": func(units: int, _worker: Node) -> void: work_applied.append(units)
	}
	
	_blackboard.set_var(&"active_job", mock_job)
	task.initialize(_actor, _blackboard, _actor)
	
	assert_int(task.execute(0.2)).is_equal(BTAction.RUNNING)
	assert_int(task.execute(0.4)).is_equal(BTAction.SUCCESS)
	assert_int(work_applied.size()).is_equal(1)
	assert_int(work_applied[0]).is_equal(20)


func test_perform_work_reads_job_def_parameters() -> void:
	var task: BTAction = auto_free(BTActionPerformWorkScript.new()) as BTAction

	var mock_job_def: JobDef = auto_free(JobDef.new()) as JobDef
	mock_job_def.work_duration = 0.8
	mock_job_def.default_units_per_cycle = 35

	var mock_job := {
		"job_def": mock_job_def,
		"apply_work_units": func(units: int, _worker: Node) -> void: pass
	}

	_blackboard.set_var(&"active_job", mock_job)
	task.initialize(_actor, _blackboard, _actor)

	assert_int(task.execute(0.4)).is_equal(BTAction.RUNNING)
	assert_int(task.execute(0.5)).is_equal(BTAction.SUCCESS)


## Regression (colonists stuck in WORK, walking in place): a needs-branch
## NavigateTo failing on a null target must not clear the agent's path owned
## by the work branch, and must not erase the work branch's job state.
func test_navigate_failure_does_not_clear_path_owned_by_another_branch() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	_blackboard.set_var(&"target_smart_object", null)
	_blackboard.set_var(&"active_job", {"keep": true})
	colonist.set_path([Vector3(5.0, 0.0, 5.0)])

	# Simulate the work branch's NavigateTo owning the path slot.
	colonist.set_meta(BTActionNavigateToScript._PATH_OWNER_META, 999999)

	var needs_nav: BTAction = auto_free(BTActionNavigateToScript.new()) as BTAction
	needs_nav.target_var = &"target_smart_object"
	needs_nav.initialize(colonist, _blackboard, colonist)

	assert_int(needs_nav.execute(0.1)).is_equal(BTAction.FAILURE)
	assert_bool(colonist.has_arrived()).is_false()
	assert_array(colonist.get("_path")).is_not_empty()
	assert_bool(_blackboard.has_var(&"active_job")).is_true()

	# Same protection without any owner meta set (pre-first-path state).
	colonist.set_path([Vector3(6.0, 0.0, 6.0)])
	colonist.remove_meta(BTActionNavigateToScript._PATH_OWNER_META)
	assert_int(needs_nav.execute(0.1)).is_equal(BTAction.FAILURE)
	assert_bool(colonist.has_arrived()).is_false()


## Regression (colonists stuck in WORK): a completed job left on the
## blackboard must be dropped and replaced by a fresh claim, not re-satisfied
## forever.
func test_claim_job_drops_completed_job_and_claims_fresh() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	colonist.set_labor_priority("mining", 3)

	var def: JobDef = auto_free(JobDef.new()) as JobDef
	def.id = "dig"
	def.display_name = "Dig"
	def.labor_id = "mining"

	var done_job: JobInstance = preload("res://subsystems/jobs/job_instance.gd").create(def, 10, Vector3(2, 1, 2))
	done_job.is_completed = true
	_blackboard.set_var(&"active_job", done_job)

	var fresh_job: JobInstance = preload("res://subsystems/jobs/job_instance.gd").create(def, 10, Vector3(4, 1, 4))
	Colony.job_board.add_job(fresh_job)

	var claim_task: BTAction = auto_free(BTActionClaimJobScript.new()) as BTAction
	claim_task.initialize(colonist, _blackboard, colonist)

	assert_int(claim_task.execute(0.1)).is_equal(BTAction.SUCCESS)
	assert_object(_blackboard.get_var(&"active_job")).is_same(fresh_job)
	assert_bool(_blackboard.get_var(&"active_job") == done_job).is_false()


## Regression (colonists stuck in WORK): completing a terminal (legacy) job
## must release active_job so the next tick claims new work instead of
## re-completing the finished one at the same spot forever.
func test_perform_work_releases_job_reference_on_terminal_complete() -> void:
	var colonist: Colonist = _sandbox.make_colonist()

	var stub_def: StubCompletingJobDef = auto_free(StubCompletingJobDef.new()) as StubCompletingJobDef
	stub_def.work_duration = 0.2
	var job := Job.new()
	job.def = stub_def
	job.labor_id = "mining"
	_blackboard.set_var(&"active_job", job)

	var task: BTAction = auto_free(BTActionPerformWorkScript.new()) as BTAction
	task.initialize(colonist, _blackboard, colonist)

	assert_int(task.execute(0.1)).is_equal(BTAction.RUNNING)
	assert_int(task.execute(0.2)).is_equal(BTAction.SUCCESS)
	assert_int(stub_def.complete_calls).is_equal(1)
	assert_bool(_blackboard.has_var(&"active_job")).is_false()


## Regression (blueprint never finishes): ConstructionJobDef.complete must
## materialize the blueprint and drop the job from the board. Before the def
## contract existed, PerformWork had no effect path for construction and
## colonists looped at the blueprint forever.
func test_construction_def_completes_blueprint_and_drops_job() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var bp: Blueprint = auto_free(Blueprint.new()) as Blueprint
	_sandbox.container.add_child(bp)
	var layer := StubBlueprintLayer.new()
	bp.layer = layer

	var job := Job.from_def(CONSTRUCTION_DEF)
	job.target_node = bp
	Colony.job_board.add_job(job)

	CONSTRUCTION_DEF.complete(colonist, job)
	assert_int(layer.completed.size()).is_equal(1)
	assert_object(layer.completed[0]).is_same(bp)
	assert_object(Colony.job_board.get_job(job.id)).is_null()


## An occupied blueprint (someone standing in its volume) hides the job and
## blocks complete() — the job waits on the board instead of entombing them.
func test_construction_def_holds_job_while_blueprint_occupied() -> void:
	var builder: Colonist = _sandbox.make_colonist()
	var occupant: Colonist = _sandbox.make_colonist()
	var bp: Blueprint = auto_free(Blueprint.new()) as Blueprint
	_sandbox.container.add_child(bp)
	occupant.global_position = Vector3(0.5, 0.0, 0.5)  # inside cell (0,0,0)
	var layer := StubBlueprintLayer.new()
	bp.layer = layer

	var job := Job.from_def(CONSTRUCTION_DEF)
	job.target_node = bp
	Colony.job_board.add_job(job)

	assert_bool(CONSTRUCTION_DEF.is_available(job)).is_false()
	CONSTRUCTION_DEF.complete(builder, job)
	assert_int(layer.completed.size()).is_equal(0)
	assert_object(Colony.job_board.get_job(job.id)).is_not_null()


## The base JobDef contract's default terminal effect: drop the job from the
## board so ClaimJob claims fresh work next tick.
func test_base_def_complete_drops_job_from_board() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var def: JobDef = auto_free(JobDef.new()) as JobDef
	def.labor_id = "hauling"  # unmapped labor: skill recording is a no-op
	var job := Job.from_def(def)
	Colony.job_board.add_job(job)

	def.complete(colonist, job)
	assert_object(Colony.job_board.get_job(job.id)).is_null()


## Hauling picks its walk target from carry state: the stocking crate while
## empty-handed, the sink while carrying a still-needed material.
func test_hauling_def_picks_work_site_by_carry_state() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var crate: Furniture = _sandbox.make_crate("plank", 5)
	crate.global_position = Vector3(10.0, 0.0, 10.0)
	var sink := FakeMaterialSink.new()
	auto_free(sink)
	_sandbox.container.add_child(sink)

	var job := Job.from_def(HAULING_DEF)
	job.target_node = sink
	job.location = Vector3(3.0, 0.0, 3.0)
	Colony.job_board.add_job(job)

	assert_bool(HAULING_DEF.is_available(job)).is_true()
	assert_vector(HAULING_DEF.work_site(colonist, job) as Vector3).is_equal(Vector3(10.0, 0.0, 10.0))

	colonist.inventory.add("plank", 2)
	assert_vector(HAULING_DEF.work_site(colonist, job) as Vector3).is_equal(Vector3(3.0, 0.0, 3.0))


## One full hauling run through the def's fetch/deliver cycles: withdraw up to
## the sink's need from the crate, then deposit into the sink — the job ends by
## satisfaction (should_close), never by a terminal complete.
func test_hauling_def_complete_fetches_then_delivers() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var crate: Furniture = _sandbox.make_crate("plank", 5)
	crate.global_position = Vector3(10.0, 0.0, 10.0)
	var sink := FakeMaterialSink.new()
	auto_free(sink)
	_sandbox.container.add_child(sink)

	var job := Job.from_def(HAULING_DEF)
	job.target_node = sink
	job.location = Vector3(3.0, 0.0, 3.0)

	HAULING_DEF.complete(colonist, job)  # FETCH
	assert_int(colonist.inventory.get_item_count("plank")).is_equal(3)
	assert_int(_sandbox.test_registry.inventory_of(crate).get_item_count("plank")).is_equal(2)

	HAULING_DEF.complete(colonist, job)  # DELIVER
	assert_int(sink.deposited).is_equal(3)
	assert_bool(sink.satisfied).is_true()
	assert_bool(HAULING_DEF.job_complete(job)).is_true()
	assert_bool(HAULING_DEF.should_close(job)).is_true()


## The work cycle releases the legacy multi-assign slot so the board's
## should_close prune can retire a satisfied job and other colonists can take
## the next cycle.
## Hauling picks work_site correctly for fractional JobInstance when carrying material.
func test_hauling_def_work_site_with_job_instance() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var crate: Furniture = _sandbox.make_crate("plank", 5)
	crate.global_position = Vector3(10.0, 0.0, 10.0)
	var sink := FakeMaterialSink.new()
	auto_free(sink)
	_sandbox.container.add_child(sink)

	var job_inst := JobInstance.create_haul(
		HAULING_DEF,
		&"plank",
		3,
		Vector3(10.0, 0.0, 10.0),
		Vector3(4.0, 0.0, 4.0),
		sink
	)
	Colony.job_board.add_job(job_inst)

	assert_vector(HAULING_DEF.work_site(colonist, job_inst) as Vector3).is_equal(Vector3(10.0, 0.0, 10.0))

	colonist.inventory.add("plank", 2)
	assert_vector(HAULING_DEF.work_site(colonist, job_inst) as Vector3).is_equal(Vector3(4.0, 0.0, 4.0))


## When the sink becomes satisfied before hauler arrives, complete() does not deposit surplus to crate (retains it).
func test_hauling_def_retains_surplus_when_sink_satisfied_early() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var crate: Furniture = _sandbox.make_crate("plank", 0)
	crate.global_position = Vector3(10.0, 0.0, 10.0)
	var sink := FakeMaterialSink.new()
	sink.satisfied = true
	auto_free(sink)
	_sandbox.container.add_child(sink)

	var job := Job.from_def(HAULING_DEF)
	job.target_node = sink
	job.location = Vector3(3.0, 0.0, 3.0)

	colonist.inventory.add("plank", 3)
	HAULING_DEF.complete(colonist, job)
	assert_int(colonist.inventory.get_item_count("plank")).is_equal(3)
	assert_int(_sandbox.test_registry.inventory_of(crate).get_item_count("plank")).is_equal(0)


## BTActionClaimJob retains surplus items in inventory when the held claim is spent.
func test_claim_job_retains_surplus_when_claim_is_spent() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	colonist.global_position = Vector3(5.0, 0.0, 5.0)
	var crate: Furniture = _sandbox.make_crate("plank", 0)
	crate.global_position = Vector3(5.0, 0.0, 5.0)
	
	colonist.inventory.add("plank", 2)
	
	var job_inst := JobInstance.create_haul(
		HAULING_DEF,
		&"plank",
		2,
		Vector3(0, 0, 0),
		Vector3(0, 0, 0)
	)
	var claim := job_inst.try_claim_units(colonist, 2)
	claim.completed_units = 2
	
	_blackboard.set_var(&"active_claim", claim)
	_blackboard.set_var(&"active_job", job_inst)
	
	var task: BTAction = auto_free(BTActionClaimJobScript.new()) as BTAction
	task.initialize(colonist, _blackboard, colonist)
	
	task.execute(0.1)
	
	assert_bool(_blackboard.has_var(&"active_claim")).is_false()
	assert_int(colonist.inventory.get_item_count("plank")).is_equal(2)
	assert_int(_sandbox.test_registry.inventory_of(crate).get_item_count("plank")).is_equal(0)


## Claiming an unrelated job drops unneeded non-tool items on the floor to free capacity.
func test_cleanup_incompatible_held_items_drops_unneeded_items_on_new_job() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	colonist.inventory.add("plank", 5)
	colonist.inventory.add("axe", 1)

	var stub_def: StubCompletingJobDef = auto_free(StubCompletingJobDef.new()) as StubCompletingJobDef
	var job := Job.new()
	job.def = stub_def

	var task: BTAction = auto_free(BTActionClaimJobScript.new()) as BTAction
	task.initialize(colonist, _blackboard, colonist)
	task._cleanup_incompatible_held_items(colonist, job)

	# Planks are dropped because the stub job does not need them; axe (tool) is kept.
	assert_int(colonist.inventory.get_item_count("plank")).is_equal(0)
	assert_int(colonist.inventory.get_item_count("axe")).is_equal(1)


## Navigation failure for a Store Carried Items job drops carried non-tool items on floor.
func test_unreachable_store_carried_items_drops_items_on_nav_failure() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	colonist.inventory.add("plank", 4)
	colonist.inventory.add("axe", 1)

	var store_job := Job.from_def(HAULING_DEF)
	store_job.title = "Store Carried Items"
	_blackboard.set_var(&"active_job", store_job)

	var nav_task: BTAction = auto_free(BTActionNavigateToScript.new()) as BTAction
	nav_task.initialize(colonist, _blackboard, colonist)
	nav_task._handle_navigation_failure()

	# Planks dropped to floor; axe kept.
	assert_int(colonist.inventory.get_item_count("plank")).is_equal(0)
	assert_int(colonist.inventory.get_item_count("axe")).is_equal(1)


func test_perform_work_unassigns_legacy_job_after_cycle() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var stub_def: StubCompletingJobDef = auto_free(StubCompletingJobDef.new()) as StubCompletingJobDef
	stub_def.work_duration = 0.1
	var job := Job.new()
	job.def = stub_def
	assert_bool(job.try_assign(colonist)).is_true()
	_blackboard.set_var(&"active_job", job)

	var task: BTAction = auto_free(BTActionPerformWorkScript.new()) as BTAction
	task.initialize(colonist, _blackboard, colonist)

	assert_int(task.execute(0.2)).is_equal(BTAction.SUCCESS)
	assert_bool(job.is_assigned(colonist.colonist_id)).is_false()


# ── BTActionCalcHaulBatch ───────────────────────────────────────────────────

func test_calc_haul_batch_clamps_to_capacity_and_need() -> void:
	var task: BTAction = auto_free(BTActionCalcHaulBatchScript.new()) as BTAction
	var colonist: Colonist = _sandbox.make_colonist()
	
	var mock_job := { "remaining_amount": 100 }
	_blackboard.set_var(&"active_job", mock_job)
	task.initialize(colonist, _blackboard, colonist)
	
	var status: int = task.execute(0.1)
	assert_int(status).is_equal(BTAction.SUCCESS)
	
	var batch_amount: int = int(_blackboard.get_var(&"haul_batch_amount"))
	assert_int(batch_amount).is_equal(int(colonist.remaining_capacity()))


func test_calc_haul_batch_fails_when_no_remaining_need() -> void:
	var task: BTAction = auto_free(BTActionCalcHaulBatchScript.new()) as BTAction
	var colonist: Colonist = _sandbox.make_colonist()
	
	var mock_job := { "remaining_amount": 0 }
	_blackboard.set_var(&"active_job", mock_job)
	task.initialize(colonist, _blackboard, colonist)
	
	assert_int(task.execute(0.1)).is_equal(BTAction.FAILURE)


# ── BTActionWander ──────────────────────────────────────────────────────────

func test_wander_fails_gracefully_without_pathfinder() -> void:
	var task: BTAction = auto_free(BTActionWanderScript.new()) as BTAction
	task.initialize(_actor, _blackboard, _actor)
	
	var status: int = task.execute(0.1)
	assert_int(status).is_equal(BTAction.FAILURE)


# ── BTConditionHasTool ──────────────────────────────────────────────────────

func test_has_tool_passes_when_no_requirement() -> void:
	var condition: BTCondition = auto_free(BTConditionHasToolScript.new()) as BTCondition
	var mock_colonist: Colonist = _sandbox.make_colonist()
	condition.initialize(mock_colonist, _blackboard, mock_colonist)
	
	var status: int = condition.execute(0.1)
	assert_int(status).is_equal(BTCondition.SUCCESS)


func test_has_tool_checks_specific_item_id() -> void:
	var condition: BTCondition = auto_free(BTConditionHasToolScript.new()) as BTCondition
	var colonist: Colonist = _sandbox.make_colonist()
	condition.default_tool_id = "axe"
	condition.initialize(colonist, _blackboard, colonist)
	
	assert_int(condition.execute(0.1)).is_equal(BTCondition.FAILURE)
	
	colonist.add_item("axe", 1)
	assert_int(condition.execute(0.1)).is_equal(BTCondition.SUCCESS)


func test_has_tool_checks_tool_tag() -> void:
	var condition: BTCondition = auto_free(BTConditionHasToolScript.new()) as BTCondition
	var colonist: Colonist = _sandbox.make_colonist()
	condition.default_tool_tag = &"tool"
	condition.initialize(colonist, _blackboard, colonist)
	
	assert_int(condition.execute(0.1)).is_equal(BTCondition.FAILURE)
	
	colonist.add_item("axe", 1)
	assert_int(condition.execute(0.1)).is_equal(BTCondition.SUCCESS)


# ── BTConditionInGroup ───────────────────────────────────────────────────────

func test_in_group_detects_nearby_target() -> void:
	var condition: BTCondition = auto_free(BTConditionInGroupScript.new()) as BTCondition
	condition.group = &"test_enemies"
	condition.radius = 10.0
	condition.initialize(_actor, _blackboard, _actor)
	
	assert_int(condition.execute(0.1)).is_equal(BTCondition.FAILURE)
	
	var enemy: Node3D = auto_free(Node3D.new()) as Node3D
	add_child(enemy)
	enemy.add_to_group(&"test_enemies")
	enemy.global_position = _actor.global_position + Vector3(3, 0, 0)
	
	assert_int(condition.execute(0.1)).is_equal(BTCondition.SUCCESS)
	assert_object(_blackboard.get_var(&"threat_target")).is_equal(enemy)


# ── BTConditionJobStillNeeded ────────────────────────────────────────────────

func test_job_still_needed_validates_target_node() -> void:
	var condition: BTCondition = auto_free(BTConditionJobStillNeededScript.new()) as BTCondition
	condition.initialize(_actor, _blackboard, _actor)
	
	var target_node: Node3D = auto_free(Node3D.new()) as Node3D
	add_child(target_node)
	
	_blackboard.set_var(&"active_job", { "target_node": target_node })
	assert_int(condition.execute(0.1)).is_equal(BTCondition.SUCCESS)
	
	target_node.free()
	assert_int(condition.execute(0.1)).is_equal(BTCondition.FAILURE)


# ── ColonistNeeds & ColonistBrain ────────────────────────────────────────────

func test_colonist_needs_get_and_set() -> void:
	var needs: ColonistNeeds = auto_free(ColonistNeedsScript.new()) as ColonistNeeds
	assert_float(needs.get_need(&"hunger")).is_equal(1.0)
	assert_float(needs.get_deficit(&"hunger")).is_equal(0.0)
	
	needs.set_need(&"hunger", 0.4)
	assert_float(needs.get_need(&"hunger")).is_equal_approx(0.4, 0.001)
	assert_float(needs.get_deficit(&"hunger")).is_equal_approx(0.6, 0.001)


func test_colonist_needs_serialization() -> void:
	var needs: ColonistNeeds = auto_free(ColonistNeedsScript.new()) as ColonistNeeds
	needs.set_need(&"hunger", 0.25)
	needs.set_need(&"rest", 0.75)
	
	var data: Dictionary = needs.serialize()
	var restored: ColonistNeeds = auto_free(ColonistNeedsScript.new()) as ColonistNeeds
	restored.deserialize(data)
	
	assert_float(restored.get_need(&"hunger")).is_equal_approx(0.25, 0.001)
	assert_float(restored.get_need(&"rest")).is_equal_approx(0.75, 0.001)


func test_colonist_brain_sets_work_goal() -> void:
	var brain: ColonistBrain = auto_free(ColonistBrainScript.new()) as ColonistBrain
	var bt_player: BTPlayer = auto_free(BTPlayer.new()) as BTPlayer
	bt_player.blackboard = Blackboard.new()
	brain.bt_player = bt_player
	
	brain.evaluate_goals()
	assert_str(String(bt_player.blackboard.get_var(&"current_goal"))).is_equal("work")


func test_colonist_needs_decay() -> void:
	ColonistNeeds._cached_need_defs.clear()
	ColonistNeeds._defs_loaded = true
	
	var needs: ColonistNeeds = auto_free(ColonistNeedsScript.new()) as ColonistNeeds
	var mock_def: Resource = preload("res://data/schemas/need_def.gd").new() as Resource
	mock_def.id = &"hunger"
	mock_def.decay_per_second = 0.1
	ColonistNeeds._cached_need_defs[&"hunger"] = mock_def
		
	needs._ready()
	needs.set_need(&"hunger", 1.0)
	needs._process(1.0)
	assert_float(needs.get_need(&"hunger")).is_less(1.0)


func test_colonist_brain_ignores_unfulfillable_need_without_smart_object() -> void:
	ColonistNeeds._cached_need_defs.clear()
	ColonistNeeds._defs_loaded = true
	
	var brain: ColonistBrain = auto_free(ColonistBrainScript.new()) as ColonistBrain
	var bt_player: BTPlayer = auto_free(BTPlayer.new()) as BTPlayer
	bt_player.blackboard = Blackboard.new()
	brain.bt_player = bt_player
	
	var needs: ColonistNeeds = auto_free(ColonistNeedsScript.new()) as ColonistNeeds
	needs.name = "ColonistNeeds"
	
	var mock_def: Resource = preload("res://data/schemas/need_def.gd").new() as Resource
	mock_def.id = &"rest"
	mock_def.decay_per_second = 0.05
	mock_def.goal_name = &"sleep"
	mock_def.target_group = &"non_existent_bed_group"
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(1, 1))
	mock_def.response_curve = curve
	
	ColonistNeeds._cached_need_defs[&"rest"] = mock_def
	
	var parent: Node3D = auto_free(Node3D.new()) as Node3D
	add_child(parent)
	parent.add_child(needs)
	parent.add_child(brain)
	var mock_target = auto_free(Node3D.new())
	mock_target.add_to_group(&"test_food")
	parent.add_child(mock_target)
	brain._ready()
	
	needs.set_need(&"rest", 0.0) # Fully depleted rest
	brain.evaluate_goals()
	
	# Since no smart object in group "non_existent_bed_group" exists, goal stays "work"
	assert_str(String(bt_player.blackboard.get_var(&"current_goal"))).is_equal("work")
	assert_object(bt_player.blackboard.get_var(&"target_smart_object")).is_null()

func test_colonist_brain_utility_scoring() -> void:
	ColonistNeeds._cached_need_defs.clear()
	ColonistNeeds._defs_loaded = true
	
	var brain: ColonistBrain = auto_free(ColonistBrainScript.new()) as ColonistBrain
	var bt_player: BTPlayer = auto_free(BTPlayer.new()) as BTPlayer
	bt_player.blackboard = Blackboard.new()
	brain.bt_player = bt_player
	
	var needs: ColonistNeeds = auto_free(ColonistNeedsScript.new()) as ColonistNeeds
	needs.name = "ColonistNeeds"
	
	var mock_def: Resource = preload("res://data/schemas/need_def.gd").new() as Resource
	mock_def.id = &"hunger"
	mock_def.decay_per_second = 0.05
	mock_def.goal_name = &"eat"
	mock_def.target_group = &"test_food"
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(1, 1))
	mock_def.response_curve = curve
	
	ColonistNeeds._cached_need_defs[&"hunger"] = mock_def
	
	var parent: Node3D = auto_free(Node3D.new()) as Node3D
	add_child(parent)
	parent.add_child(needs)
	parent.add_child(brain)
	var mock_target = auto_free(Node3D.new())
	mock_target.add_to_group(&"test_food")
	parent.add_child(mock_target)
	brain._ready()
	
	needs.set_need(&"hunger", 1.0)
	brain.evaluate_goals()
	assert_str(String(bt_player.blackboard.get_var(&"current_goal"))).is_equal("work")
	
	needs.set_need(&"hunger", 0.0)
	brain.evaluate_goals()
	assert_str(String(bt_player.blackboard.get_var(&"current_goal"))).is_equal("eat")


func test_colonist_brain_commitment_bonus() -> void:
	ColonistNeeds._cached_need_defs.clear()
	ColonistNeeds._defs_loaded = true
	
	var brain: ColonistBrain = auto_free(ColonistBrainScript.new()) as ColonistBrain
	var bt_player: BTPlayer = auto_free(BTPlayer.new()) as BTPlayer
	bt_player.blackboard = Blackboard.new()
	brain.bt_player = bt_player
	
	var needs: ColonistNeeds = auto_free(ColonistNeedsScript.new()) as ColonistNeeds
	needs.name = "ColonistNeeds"
	
	var mock_def: Resource = preload("res://data/schemas/need_def.gd").new() as Resource
	mock_def.id = &"hunger"
	mock_def.decay_per_second = 0.05
	mock_def.target_group = &"test_food"
	mock_def.goal_name = &"eat"
	mock_def.emergency_threshold = 0.10
	# Linear response curve: Curve's default zero tangents bend sample() below
	# the diagonal, which made the +0.30 commitment bonus (0.1137 + 0.30) lose
	# to the 0.5 work fallback this test exists to flip (0.21 + 0.30 = 0.51).
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0, 0), 0.0, 1.0)
	curve.add_point(Vector2(1, 1), 1.0, 0.0)
	mock_def.response_curve = curve
	
	ColonistNeeds._cached_need_defs[&"hunger"] = mock_def
	
	var parent: Node3D = auto_free(Node3D.new()) as Node3D
	add_child(parent)
	parent.add_child(needs)
	parent.add_child(brain)
	var mock_target = auto_free(Node3D.new())
	mock_target.add_to_group(&"test_food")
	parent.add_child(mock_target)
	brain._ready()
	
	bt_player.blackboard.set_var(&"current_goal", &"eat")
	
	needs.set_need(&"hunger", 0.79)
	brain.evaluate_goals()
	assert_str(String(bt_player.blackboard.get_var(&"current_goal"))).is_equal("eat")


func test_furniture_group_registration() -> void:
	var furniture: Furniture = auto_free(preload("res://subsystems/furniture/furniture.gd").new()) as Furniture
	furniture.def_id = "test_bed"
	furniture._ready()
	assert_bool(furniture.is_in_group(&"test_bed")).is_true()
	assert_bool(furniture.is_in_group(&"furniture")).is_true()


# ── Phase 4: Universal Tasks & Tree Tests ────────────────────────────────────

func test_claim_job_claims_from_job_board() -> void:
	var task: BTAction = auto_free(BTActionClaimJobScript.new()) as BTAction
	var colonist: Colonist = _sandbox.make_colonist()
	
	# Empty board -> fails
	task.initialize(colonist, _blackboard, colonist)
	assert_int(task.execute(0.1)).is_equal(BTAction.FAILURE)
	
	# Add available job
	var def: JobDef = auto_free(JobDef.new()) as JobDef
	def.id = "mining"
	def.display_name = "Mining"
	def.labor_id = "mining"
	var job: Job = Job.from_def(def)
	Colony.job_board.add_job(job)
	
	assert_int(task.execute(0.1)).is_equal(BTAction.SUCCESS)
	assert_object(_blackboard.get_var(&"active_job")).is_equal(job)


func test_use_smart_object_replenishes_need_and_resets_goal() -> void:
	var task: BTAction = auto_free(BTActionUseSmartObjectScript.new()) as BTAction
	task.default_duration = 0.5
	task.restore_amount = 0.6
	
	var colonist: Colonist = _sandbox.make_colonist()
	colonist.needs.set_need(&"hunger", 0.2)
	
	_blackboard.set_var(&"current_goal", &"eat")
	task.initialize(colonist, _blackboard, colonist)
	
	assert_int(task.execute(0.2)).is_equal(BTAction.RUNNING)
	assert_int(task.execute(0.4)).is_equal(BTAction.SUCCESS)
	
	assert_float(colonist.needs.get_need(&"hunger")).is_equal_approx(0.8, 0.01)
	assert_str(String(_blackboard.get_var(&"current_goal"))).is_equal("none")


func test_haul_batch_transfers_items() -> void:
	var task: BTAction = auto_free(BTActionHaulBatchScript.new()) as BTAction
	var colonist: Colonist = _sandbox.make_colonist()
	
	var crate: Furniture = _sandbox.make_crate("plank", 10)
	var crate2: Furniture = _sandbox.make_crate("planks", 0)
	
	_blackboard.set_var(&"source_node", crate)
	_blackboard.set_var(&"target_node", crate2)
	_blackboard.set_var(&"haul_item_id", &"plank")
	
	# 1. LOAD into colonist
	task.mode = 0 # Mode.LOAD
	task.initialize(colonist, _blackboard, colonist)
	assert_int(task.execute(0.1)).is_equal(BTAction.SUCCESS)
	assert_int(colonist.inventory.get_item_count("plank")).is_equal(10)
	
	# 2. UNLOAD to crate2
	task.mode = 1 # Mode.UNLOAD
	assert_int(task.execute(0.1)).is_equal(BTAction.SUCCESS)
	assert_int(colonist.inventory.get_item_count("plank")).is_equal(0)
	var inv2 = Colony.storage_registry.inventory_of(crate2)
	assert_int(inv2.get_item_count("plank")).is_equal(10)


func test_scan_threats_detects_colonist() -> void:
	var task: BTAction = auto_free(BTActionScanThreatsScript.new()) as BTAction
	task.radius = 20.0
	task.initialize(_actor, _blackboard, _actor)
	
	var colonist: Colonist = _sandbox.make_colonist()
	colonist.global_position = _actor.global_position + Vector3(5, 0, 0)
	
	assert_int(task.execute(0.1)).is_equal(BTAction.SUCCESS)
	assert_object(_blackboard.get_var(&"threat_target")).is_equal(colonist)


func test_melee_attack_damages_target() -> void:
	var task: BTAction = auto_free(BTActionMeleeAttackScript.new()) as BTAction
	task.windup_duration = 0.2
	task.cooldown_duration = 0.2
	task.damage = 25
	task.attack_range = 3.0
	
	var colonist: Colonist = _sandbox.make_colonist()
	colonist.global_position = _actor.global_position + Vector3(1, 0, 0)
	var initial_hp: int = colonist.get_hp()
	
	_blackboard.set_var(&"threat_target", colonist)
	task.initialize(_actor, _blackboard, _actor)
	
	assert_int(task.execute(0.1)).is_equal(BTAction.RUNNING)
	assert_int(task.execute(0.2)).is_equal(BTAction.RUNNING)
	assert_int(colonist.get_hp()).is_equal(initial_hp - 25)
	assert_int(task.execute(0.2)).is_equal(BTAction.SUCCESS)


func test_tree_factory_generates_and_saves_trees() -> void:
	var work_tree: BehaviorTree = BTTreeFactoryScript.create_generic_work_tree()
	assert_object(work_tree).is_not_null()
	assert_object(work_tree.root_task).is_not_null()
	
	var haul_tree: BehaviorTree = BTTreeFactoryScript.create_haul_tree()
	assert_object(haul_tree).is_not_null()
	assert_object(haul_tree.root_task).is_not_null()
	
	var colonist_tree: BehaviorTree = BTTreeFactoryScript.create_colonist_root_tree(work_tree)
	assert_object(colonist_tree).is_not_null()
	assert_object(colonist_tree.root_task).is_not_null()
	
	var enemy_tree: BehaviorTree = BTTreeFactoryScript.create_enemy_swarmer_tree()
	assert_object(enemy_tree).is_not_null()
	assert_object(enemy_tree.root_task).is_not_null()
	
	# Save .tres resources
	var err1: int = ResourceSaver.save(work_tree, "res://data/ai/trees/bt_generic_work.tres")
	var err2: int = ResourceSaver.save(haul_tree, "res://data/ai/trees/bt_haul_single_trip.tres")
	var err3: int = ResourceSaver.save(colonist_tree, "res://data/ai/trees/colonist_root.tres")
	var err4: int = ResourceSaver.save(enemy_tree, "res://data/ai/trees/enemy_swarmer.tres")
	
	assert_int(err1).is_equal(OK)
	assert_int(err2).is_equal(OK)
	assert_int(err3).is_equal(OK)
	assert_int(err4).is_equal(OK)


# ── Phase 5: Hardening, Persistence & Verification Tests ─────────────────────

func test_unreachable_navigation_blacklists_job_for_colonist() -> void:
	var colonist_a: Colonist = _sandbox.make_colonist()
	var colonist_b: Colonist = _sandbox.make_colonist()
	colonist_a.set_labor_priority("mining", 3)
	colonist_b.set_labor_priority("mining", 3)
	
	var def: JobDef = auto_free(JobDef.new()) as JobDef
	def.id = "mine_ore"
	def.display_name = "Mine Ore"
	def.labor_id = "mining"
	def.work_animation = &"digging"
	def.default_units_per_cycle = 20
	
	var job = preload("res://subsystems/jobs/job_instance.gd").create(def, 100, Vector3(999, 999, 999))
	job.id = "mine_ore_1"
	Colony.job_board.add_job(job)
	
	# Colonist A claims the job
	var claim_task: BTAction = auto_free(BTActionClaimJobScript.new()) as BTAction
	claim_task.initialize(colonist_a, _blackboard, colonist_a)
	assert_int(claim_task.execute(0.1)).is_equal(BTAction.SUCCESS)
	assert_object(_blackboard.get_var(&"active_claim")).is_not_null()
	
	# Colonist A attempts to navigate to unreachable location (pathfinder will fail)
	var nav_task: BTAction = auto_free(BTActionNavigateToScript.new()) as BTAction
	nav_task.initialize(colonist_a, _blackboard, colonist_a)
	assert_int(nav_task.execute(0.1)).is_equal(BTAction.FAILURE)
	
	# Assert claim was abandoned, blackboard cleared, and job blacklisted for Colonist A only
	assert_bool(_blackboard.has_var(&"active_claim")).is_false()
	assert_bool(_blackboard.has_var(&"active_job")).is_false()
	assert_bool(Colony.job_board.is_job_blacklisted_for("mine_ore_1", colonist_a.colonist_id)).is_true()
	assert_bool(Colony.job_board.is_job_blacklisted_for("mine_ore_1", colonist_b.colonist_id)).is_false()
	
	# Colonist A cannot claim it again during blacklist cooldown
	assert_object(Colony.job_board.get_best_job_for(colonist_a)).is_null()
	
	# Colonist B CAN claim it
	var best_b = Colony.job_board.get_best_job_for(colonist_b)
	assert_object(best_b).is_equal(job)


func test_interruption_contract_and_lazy_tool_drop() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	colonist.set_labor_priority("farming", 3)
	
	# Add a pruning kit (tag: gardening_tool) to inventory
	colonist.add_item("pruning_kit", 1)
	assert_bool(colonist.inventory.has_item("pruning_kit", 1)).is_true()
	assert_bool(colonist.hands_full()).is_true()
	
	# Simulate interruption / combat flee: tool is NOT dropped
	assert_bool(colonist.inventory.has_item("pruning_kit", 1)).is_true()
	
	# Now claim a job requiring an 'axe' tool tag
	var def: JobDef = auto_free(JobDef.new()) as JobDef
	def.id = "chop_wood"
	def.display_name = "Chop Wood"
	def.labor_id = "farming"
	def.required_tool_tag = &"axe"
	var job: Job = Job.from_def(def)
	Colony.job_board.add_job(job)
	
	var claim_task: BTAction = auto_free(BTActionClaimJobScript.new()) as BTAction
	claim_task.initialize(colonist, _blackboard, colonist)
	assert_int(claim_task.execute(0.1)).is_equal(BTAction.SUCCESS)
	
	# Lazy cleanup dropped incompatible pruning kit
	assert_bool(colonist.inventory.has_item("pruning_kit", 1)).is_false()


func test_stateless_colonist_save_load() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	colonist.global_position = Vector3(12.0, 3.5, -8.0)
	colonist.inventory.items["wood_plank"] = 7
	colonist.needs.set_need(&"hunger", 0.42)
	colonist.needs.set_need(&"rest", 0.88)
	
	var data: Dictionary = colonist.serialize()
	assert_bool(data.has("needs")).is_true()
	assert_bool(data.has("inventory")).is_true()
	assert_bool(data.has("pos")).is_true()
	assert_int(data["inventory"]["items"]["wood_plank"]).is_equal(7)
	
	# Deserialize into another colonist
	var loaded_colonist: Colonist = _sandbox.make_colonist()
	loaded_colonist.deserialize(data)
	
	assert_vector(loaded_colonist.global_position).is_equal(Vector3(12.0, 3.5, -8.0))
	assert_int(loaded_colonist.inventory.get_item_count("wood_plank")).is_equal(7)
	assert_float(loaded_colonist.needs.get_need(&"hunger")).is_equal_approx(0.42, 0.001)
	assert_float(loaded_colonist.needs.get_need(&"rest")).is_equal_approx(0.88, 0.001)


class StubCompletingJobDef extends JobDef:
	var complete_calls: int = 0

	func complete(_actor: Node, _job: Variant) -> void:
		complete_calls += 1


## Records BlueprintLayer.complete_blueprint calls without touching the voxel
## world (construction def tests).
class StubBlueprintLayer extends RefCounted:
	var completed: Array = []

	func complete_blueprint(bp: Blueprint, _builder: Node) -> bool:
		completed.append(bp)
		return true


## MaterialSink duck-type for hauling def tests (the suite_jobs FakeSink
## pattern, plus a real withdraw on deposit_from).
class FakeMaterialSink extends Node:
	var satisfied := false
	var deposited := 0

	func needed_item_ids() -> Array[String]:
		var out: Array[String] = []
		if not satisfied:
			out.append("plank")
		return out

	func remaining_need(_item_id: String) -> int:
		return 0 if satisfied else 3

	func has_complete_materials() -> bool:
		return satisfied

	func deposit_from(actor: Node) -> int:
		var need: int = remaining_need("plank")
		var short: int = actor.remove_item("plank", need)
		var taken: int = need - short
		deposited += taken
		if taken > 0:
			satisfied = true
		return taken
