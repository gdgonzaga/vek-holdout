extends GdUnitTestSuite

## Unit tests for Phase 1 LimboAI action & condition tasks, and AI stub components.

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")

const BTActionNavigateToScript = preload("res://subsystems/ai/tasks/actions/bt_action_navigate_to.gd")
const BTActionPerformWorkScript = preload("res://subsystems/ai/tasks/actions/bt_action_perform_work.gd")
const BTActionCalcHaulBatchScript = preload("res://subsystems/ai/tasks/actions/bt_action_calc_haul_batch.gd")
const BTActionWanderScript = preload("res://subsystems/ai/tasks/actions/bt_action_wander.gd")

const BTConditionHasToolScript = preload("res://subsystems/ai/tasks/conditions/bt_condition_has_tool.gd")
const BTConditionInGroupScript = preload("res://subsystems/ai/tasks/conditions/bt_condition_in_group.gd")
const BTConditionJobStillNeededScript = preload("res://subsystems/ai/tasks/conditions/bt_condition_job_still_needed.gd")

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


func after_test() -> void:
	_sandbox.restore()


# ── BTActionNavigateTo ───────────────────────────────────────────────────────

func test_navigate_to_generates_descriptive_name() -> void:
	var task: BTActionNavigateTo = auto_free(BTActionNavigateToScript.new()) as BTActionNavigateTo
	task.target_var = &"custom_target"
	task.arrival_distance = 2.5
	var name_str: String = task._generate_name()
	assert_bool(name_str.contains("custom_target")).is_true()
	assert_bool(name_str.contains("2.5")).is_true()


func test_navigate_to_returns_failure_without_target() -> void:
	var task: BTActionNavigateTo = auto_free(BTActionNavigateToScript.new()) as BTActionNavigateTo
	task.initialize(_actor, _blackboard, _actor)
	var status: int = task.execute(0.1)
	assert_int(status).is_equal(BTAction.FAILURE)


func test_navigate_to_returns_success_when_already_at_target() -> void:
	var task: BTActionNavigateTo = auto_free(BTActionNavigateToScript.new()) as BTActionNavigateTo
	_blackboard.set_var(&"target_pos", _actor.global_position)
	task.arrival_distance = 2.0
	task.initialize(_actor, _blackboard, _actor)
	var status: int = task.execute(0.1)
	assert_int(status).is_equal(BTAction.SUCCESS)


# ── BTActionPerformWork ──────────────────────────────────────────────────────

func test_perform_work_generates_descriptive_name() -> void:
	var task: BTActionPerformWork = auto_free(BTActionPerformWorkScript.new()) as BTActionPerformWork
	task.job_var = &"mine_job"
	task.default_duration = 2.0
	var name_str: String = task._generate_name()
	assert_bool(name_str.contains("mine_job")).is_true()
	assert_bool(name_str.contains("2.0s")).is_true()


func test_perform_work_runs_and_completes_after_duration() -> void:
	var task: BTActionPerformWork = auto_free(BTActionPerformWorkScript.new()) as BTActionPerformWork
	task.default_duration = 0.5
	task.initialize(_actor, _blackboard, _actor)
	
	# First tick is within duration
	var status_running: int = task.execute(0.2)
	assert_int(status_running).is_equal(BTAction.RUNNING)
	
	# Second tick crosses duration
	var status_success: int = task.execute(0.35)
	assert_int(status_success).is_equal(BTAction.SUCCESS)


# ── BTActionCalcHaulBatch ────────────────────────────────────────────────────

func test_calc_haul_batch_clamps_to_capacity() -> void:
	var task: BTActionCalcHaulBatch = auto_free(BTActionCalcHaulBatchScript.new()) as BTActionCalcHaulBatch
	var mock_colonist: Colonist = _sandbox.make_colonist()
	_blackboard.set_var(&"active_job", { "remaining_amount": 50 })
	task.initialize(mock_colonist, _blackboard, mock_colonist)
	
	var status: int = task.execute(0.1)
	assert_int(status).is_equal(BTAction.SUCCESS)
	
	var batch_amount: int = int(_blackboard.get_var(&"haul_batch_amount", 0))
	assert_int(batch_amount).is_greater(0)
	assert_int(batch_amount).is_less_equal(50)


func test_calc_haul_batch_fails_when_no_need() -> void:
	var task: BTActionCalcHaulBatch = auto_free(BTActionCalcHaulBatchScript.new()) as BTActionCalcHaulBatch
	var mock_colonist: Colonist = _sandbox.make_colonist()
	_blackboard.set_var(&"active_job", { "remaining_amount": 0 })
	task.initialize(mock_colonist, _blackboard, mock_colonist)
	
	var status: int = task.execute(0.1)
	assert_int(status).is_equal(BTAction.FAILURE)


# ── BTActionWander ───────────────────────────────────────────────────────────

func test_wander_generates_descriptive_name() -> void:
	var task: BTActionWander = auto_free(BTActionWanderScript.new()) as BTActionWander
	task.radius = 5
	var name_str: String = task._generate_name()
	assert_bool(name_str.contains("radius: 5")).is_true()


func test_wander_returns_failure_without_pathfinder() -> void:
	var task: BTActionWander = auto_free(BTActionWanderScript.new()) as BTActionWander
	task.initialize(_actor, _blackboard, _actor)
	var status: int = task.execute(0.1)
	assert_int(status).is_equal(BTAction.FAILURE)


# ── BTConditionHasTool ───────────────────────────────────────────────────────

func test_has_tool_passes_when_no_requirement() -> void:
	var condition: BTConditionHasTool = auto_free(BTConditionHasToolScript.new()) as BTConditionHasTool
	var mock_colonist: Colonist = _sandbox.make_colonist()
	condition.initialize(mock_colonist, _blackboard, mock_colonist)
	
	var status: int = condition.execute(0.1)
	assert_int(status).is_equal(BTCondition.SUCCESS)


func test_has_tool_checks_specific_item_id() -> void:
	var condition: BTConditionHasTool = auto_free(BTConditionHasToolScript.new()) as BTConditionHasTool
	var colonist: Colonist = _sandbox.make_colonist()
	condition.default_tool_id = "axe"
	condition.initialize(colonist, _blackboard, colonist)
	
	assert_int(condition.execute(0.1)).is_equal(BTCondition.FAILURE)
	
	colonist.add_item("axe", 1)
	assert_int(condition.execute(0.1)).is_equal(BTCondition.SUCCESS)


func test_has_tool_checks_tool_tag() -> void:
	var condition: BTConditionHasTool = auto_free(BTConditionHasToolScript.new()) as BTConditionHasTool
	var colonist: Colonist = _sandbox.make_colonist()
	condition.default_tool_tag = &"tool"
	condition.initialize(colonist, _blackboard, colonist)
	
	assert_int(condition.execute(0.1)).is_equal(BTCondition.FAILURE)
	
	colonist.add_item("axe", 1)
	assert_int(condition.execute(0.1)).is_equal(BTCondition.SUCCESS)


# ── BTConditionInGroup ───────────────────────────────────────────────────────

func test_in_group_detects_nearby_target() -> void:
	var condition: BTConditionInGroup = auto_free(BTConditionInGroupScript.new()) as BTConditionInGroup
	condition.group = &"test_enemies"
	condition.radius = 10.0
	condition.initialize(_actor, _blackboard, _actor)
	
	# No nodes in group
	assert_int(condition.execute(0.1)).is_equal(BTCondition.FAILURE)
	
	# Add a node to the group
	var enemy: Node3D = auto_free(Node3D.new()) as Node3D
	add_child(enemy)
	enemy.add_to_group(&"test_enemies")
	enemy.global_position = _actor.global_position + Vector3(3, 0, 0)
	
	assert_int(condition.execute(0.1)).is_equal(BTCondition.SUCCESS)
	assert_object(_blackboard.get_var(&"threat_target")).is_equal(enemy)


# ── BTConditionJobStillNeeded ────────────────────────────────────────────────

func test_job_still_needed_validates_target_node() -> void:
	var condition: BTConditionJobStillNeeded = auto_free(BTConditionJobStillNeededScript.new()) as BTConditionJobStillNeeded
	condition.initialize(_actor, _blackboard, _actor)
	
	var target_node: Node3D = auto_free(Node3D.new()) as Node3D
	add_child(target_node)
	
	_blackboard.set_var(&"active_job", { "target_node": target_node })
	assert_int(condition.execute(0.1)).is_equal(BTCondition.SUCCESS)
	
	target_node.free()
	assert_int(condition.execute(0.1)).is_equal(BTCondition.FAILURE)


# ── ColonistNeeds & ColonistBrain Stubs ───────────────────────────────────────

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
