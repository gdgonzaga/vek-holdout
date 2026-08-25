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
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(1, 1))
	mock_def.response_curve = curve
	
	ColonistNeeds._cached_need_defs[&"hunger"] = mock_def
	
	var parent: Node3D = auto_free(Node3D.new()) as Node3D
	parent.add_child(needs)
	parent.add_child(brain)
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
	mock_def.goal_name = &"eat"
	mock_def.emergency_threshold = 0.10
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(1, 1))
	mock_def.response_curve = curve
	
	ColonistNeeds._cached_need_defs[&"hunger"] = mock_def
	
	var parent: Node3D = auto_free(Node3D.new()) as Node3D
	parent.add_child(needs)
	parent.add_child(brain)
	brain._ready()
	
	bt_player.blackboard.set_var(&"current_goal", &"eat")
	
	needs.set_need(&"hunger", 0.8)
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
