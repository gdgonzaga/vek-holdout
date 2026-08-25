## Subsystem: AI / Trees
## Programmatic factory and generator for master LimboAI BehaviorTrees.
class_name BTTreeFactory
extends RefCounted

const BTActionNavigateToScript = preload("res://subsystems/ai/tasks/actions/bt_action_navigate_to.gd")
const BTActionPerformWorkScript = preload("res://subsystems/ai/tasks/actions/bt_action_perform_work.gd")
const BTActionClaimJobScript = preload("res://subsystems/ai/tasks/actions/bt_action_claim_job.gd")
const BTActionUseSmartObjectScript = preload("res://subsystems/ai/tasks/actions/bt_action_use_smart_object.gd")
const BTActionHaulBatchScript = preload("res://subsystems/ai/tasks/actions/bt_action_haul_batch.gd")
const BTActionWanderScript = preload("res://subsystems/ai/tasks/actions/bt_action_wander.gd")

const BTConditionHasToolScript = preload("res://subsystems/ai/tasks/conditions/bt_condition_has_tool.gd")
const BTConditionInGroupScript = preload("res://subsystems/ai/tasks/conditions/bt_condition_in_group.gd")

const BTActionScanThreatsScript = preload("res://subsystems/ai/tasks/actions/bt_action_scan_threats.gd")
const BTActionMeleeAttackScript = preload("res://subsystems/ai/tasks/actions/bt_action_melee_attack.gd")
const BTActionBreachVoxelScript = preload("res://subsystems/ai/tasks/actions/bt_action_breach_voxel.gd")
const BTConditionPathBlockedScript = preload("res://subsystems/ai/tasks/conditions/bt_condition_path_blocked.gd")


## Builds the universal work sequence behavior tree
static func create_generic_work_tree() -> BehaviorTree:
	var tree := BehaviorTree.new()
	tree.description = "Universal work sequence executing claims and work units"
	
	var root := BTSequence.new()
	
	# 1. Claim Job
	var claim_task = BTActionClaimJobScript.new()
	root.add_child(claim_task)
	
	# 2. Check Tool (Condition has tool)
	var tool_selector := BTSelector.new()
	var has_tool_cond = BTConditionHasToolScript.new()
	tool_selector.add_child(has_tool_cond)
	root.add_child(tool_selector)
	
	# 3. Navigate to work site
	var nav_task = BTActionNavigateToScript.new()
	nav_task.target_var = &"target_pos"
	nav_task.arrival_distance = 1.8
	root.add_child(nav_task)
	
	# 4. Perform Work
	var work_task = BTActionPerformWorkScript.new()
	work_task.job_var = &"active_job"
	root.add_child(work_task)
	
	tree.root_task = root
	return tree


## Builds the single-trip haul sequence behavior tree
static func create_haul_tree() -> BehaviorTree:
	var tree := BehaviorTree.new()
	tree.description = "Single-trip hauling sequence for material transport"
	
	var root := BTSequence.new()
	
	# 1. Claim haul job
	var claim_task = BTActionClaimJobScript.new()
	root.add_child(claim_task)
	
	# 2. Navigate to source
	var nav_source = BTActionNavigateToScript.new()
	nav_source.target_var = &"source_node"
	nav_source.arrival_distance = 1.8
	root.add_child(nav_source)
	
	# 3. Load items
	var load_task = BTActionHaulBatchScript.new()
	load_task.mode = 0
	root.add_child(load_task)
	
	# 4. Navigate to destination
	var nav_target = BTActionNavigateToScript.new()
	nav_target.target_var = &"target_node"
	nav_target.arrival_distance = 1.8
	root.add_child(nav_target)
	
	# 5. Unload items
	var unload_task = BTActionHaulBatchScript.new()
	unload_task.mode = 1
	root.add_child(unload_task)
	
	tree.root_task = root
	return tree


## Builds the colonist master behavior tree
static func create_colonist_root_tree(work_tree: BehaviorTree = null) -> BehaviorTree:
	var tree := BehaviorTree.new()
	tree.description = "Colonist master behavior tree with dynamic needs, work delegation, and idle wander"
	
	var root := BTDynamicSelector.new()
	
	# 1. Dynamic Need Satisfier (Sequence)
	var need_seq := BTSequence.new()
	var nav_smart = BTActionNavigateToScript.new()
	nav_smart.target_var = &"target_smart_object"
	nav_smart.arrival_distance = 1.5
	need_seq.add_child(nav_smart)
	
	var use_smart = BTActionUseSmartObjectScript.new()
	need_seq.add_child(use_smart)
	root.add_child(need_seq)
	
	# 2. Work Goal Runner
	if work_tree == null:
		work_tree = create_generic_work_tree()
	var work_subtree := BTSubtree.new()
	work_subtree.subtree = work_tree
	root.add_child(work_subtree)
	
	# 3. Idle Wander (Fallback)
	var wander_task = BTActionWanderScript.new()
	wander_task.radius = 4
	root.add_child(wander_task)
	
	tree.root_task = root
	return tree


## Builds the enemy swarmer behavior tree
static func create_enemy_swarmer_tree() -> BehaviorTree:
	var tree := BehaviorTree.new()
	tree.description = "Enemy swarmer tree with breach, attack, chase, and threat scan"
	
	var root := BTSelector.new()
	
	# 1. Voxel Wall Breach
	var breach_seq := BTSequence.new()
	var breach_cond = BTConditionPathBlockedScript.new()
	breach_seq.add_child(breach_cond)
	var breach_action = BTActionBreachVoxelScript.new()
	breach_seq.add_child(breach_action)
	root.add_child(breach_seq)
	
	# 2. Melee Attack
	var attack_action = BTActionMeleeAttackScript.new()
	root.add_child(attack_action)
	
	# 3. Chase Threat
	var chase_nav = BTActionNavigateToScript.new()
	chase_nav.target_var = &"threat_target"
	chase_nav.arrival_distance = 1.5
	root.add_child(chase_nav)
	
	# 4. Aggro Scan
	var scan_threats = BTActionScanThreatsScript.new()
	root.add_child(scan_threats)
	
	tree.root_task = root
	return tree
