## Subsystem: AI / Trees
## Programmatic factory and generator for master LimboAI BehaviorTrees.
class_name BTTreeFactory
extends RefCounted

const BTActionNavigateToScript = preload("res://subsystems/ai/tasks/actions/bt_action_navigate_to.gd")
const BTActionPerformWorkScript = preload("res://subsystems/ai/tasks/actions/bt_action_perform_work.gd")
const BTActionClaimJobScript = preload("res://subsystems/ai/tasks/actions/bt_action_claim_job.gd")
const BTActionUseBedScript = preload("res://subsystems/ai/tasks/actions/bt_action_use_bed.gd")
const BTActionHaulBatchScript = preload("res://subsystems/ai/tasks/actions/bt_action_haul_batch.gd")
const BTActionWanderScript = preload("res://subsystems/ai/tasks/actions/bt_action_wander.gd")
const BTActionEquipToolScript = preload("res://subsystems/ai/tasks/actions/bt_action_equip_tool.gd")
const BTActionFindFoodScript = preload("res://subsystems/ai/tasks/actions/bt_action_find_food.gd")
const BTActionFetchFoodScript = preload("res://subsystems/ai/tasks/actions/bt_action_fetch_food.gd")
const BTActionEatFoodScript = preload("res://subsystems/ai/tasks/actions/bt_action_eat_food.gd")
const BTActionUseRecreationScript = preload("res://subsystems/ai/tasks/actions/bt_action_use_recreation.gd")

const BTConditionHasToolScript = preload("res://subsystems/ai/tasks/conditions/bt_condition_has_tool.gd")
const BTConditionInGroupScript = preload("res://subsystems/ai/tasks/conditions/bt_condition_in_group.gd")
const BTConditionGoalIsScript = preload("res://subsystems/ai/tasks/conditions/bt_condition_goal_is.gd")

const BTActionScanThreatsScript = preload("res://subsystems/ai/tasks/actions/bt_action_scan_threats.gd")
const BTActionMeleeAttackScript = preload("res://subsystems/ai/tasks/actions/bt_action_melee_attack.gd")
const BTActionRangedAttackScript = preload("res://subsystems/ai/tasks/actions/bt_action_ranged_attack.gd")
const BTActionBreachVoxelScript = preload("res://subsystems/ai/tasks/actions/bt_action_breach_voxel.gd")
const BTConditionPathBlockedScript = preload("res://subsystems/ai/tasks/conditions/bt_condition_path_blocked.gd")
const BTActionColonistCombatAttackScript = preload("res://subsystems/ai/tasks/actions/bt_action_colonist_combat_attack.gd")


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

	# 3. Equip Tool (Ensure tool in main_hand, swapping/stowing as necessary)
	var equip_tool = BTActionEquipToolScript.new()
	root.add_child(equip_tool)
	
	# 4. Navigate to work site
	var nav_task = BTActionNavigateToScript.new()
	nav_task.target_var = &"target_pos"
	nav_task.arrival_distance = 1.8
	root.add_child(nav_task)
	
	# 5. Perform Work
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

	# 1. Reactive Combat (GDD §6.7 "Fight" stance, MVP subset -- any armed
	# colonist fights back from wherever it is, no pursuit). Highest priority
	# so it interrupts eating/needs/work/wander whenever a threat is in range.
	var combat_seq := BTSequence.new()
	var scan_threats = BTActionScanThreatsScript.new()
	var combat_threat_groups: Array[StringName] = [&"enemies"]
	scan_threats.threat_groups = combat_threat_groups
	scan_threats.use_weapon_range = true
	scan_threats.radius = 60.0
	scan_threats.result_var = &"threat_target"
	combat_seq.add_child(scan_threats)
	var combat_attack = BTActionColonistCombatAttackScript.new()
	combat_attack.target_var = &"threat_target"
	combat_seq.add_child(combat_attack)
	root.add_child(combat_seq)

	# 2. Autonomous Eating Loop (Sequence)
	var eat_seq := BTSequence.new()
	var find_food = BTActionFindFoodScript.new()
	find_food.goal_var = &"current_goal"
	find_food.expected_goal = &"eat"
	find_food.target_smart_object_var = &"target_smart_object"
	eat_seq.add_child(find_food)
	
	var nav_food = BTActionNavigateToScript.new()
	nav_food.target_var = &"target_smart_object"
	nav_food.arrival_distance = 1.5
	eat_seq.add_child(nav_food)
	
	var fetch_food = BTActionFetchFoodScript.new()
	eat_seq.add_child(fetch_food)
	
	var eat_food = BTActionEatFoodScript.new()
	eat_seq.add_child(eat_food)
	root.add_child(eat_seq)

	# 3. Sleep / Generic Smart Object Satisfier. The goal guard is load-bearing:
	# without it, an eat goal whose food vanished mid-cycle falls through from
	# branch 2 into this sequence, walks to the food crate, and matches
	# goal_name == "eat" and refills hunger without consuming anything.
	var need_seq := BTSequence.new()
	var sleep_goal_guard = BTConditionGoalIsScript.new()
	sleep_goal_guard.goal_var = &"current_goal"
	sleep_goal_guard.expected_goal = &"sleep"
	need_seq.add_child(sleep_goal_guard)

	var nav_smart = BTActionNavigateToScript.new()
	nav_smart.target_var = &"target_stand_pos"
	nav_smart.arrival_distance = 1.5
	need_seq.add_child(nav_smart)

	var use_bed = BTActionUseBedScript.new()
	need_seq.add_child(use_bed)
	root.add_child(need_seq)

	# 4. Recreation Satisfier. Kept separate from branch 3 because recreation
	# accrues per second against an authored capacity and session window, none of
	# which the flat-restore generic smart-object action models.
	var rec_seq := BTSequence.new()
	var rec_goal_guard = BTConditionGoalIsScript.new()
	rec_goal_guard.goal_var = &"current_goal"
	rec_goal_guard.expected_goal = &"recreation"
	rec_seq.add_child(rec_goal_guard)

	# Navigates to the stand position ColonistBrain resolved from the object's
	# occupancy slot, which is the furniture origin when no offsets are authored.
	var nav_rec = BTActionNavigateToScript.new()
	nav_rec.target_var = &"target_stand_pos"
	nav_rec.arrival_distance = 1.5
	rec_seq.add_child(nav_rec)

	var use_rec = BTActionUseRecreationScript.new()
	rec_seq.add_child(use_rec)
	root.add_child(rec_seq)

	# 5. Work Goal Runner
	if work_tree == null:
		work_tree = create_generic_work_tree()
	var work_subtree := BTSubtree.new()
	work_subtree.subtree = work_tree
	root.add_child(work_subtree)

	# 6. Idle Wander (Fallback)
	var wander_task = BTActionWanderScript.new()
	wander_task.radius = 4
	root.add_child(wander_task)
	
	tree.root_task = root
	return tree


## Builds the generic melee-enemy behavior tree: closest target scan,
## voxel-breach-if-blocked, chase, and attack. Archetype-agnostic -- combat
## numbers (damage/range/timing) come from the agent's EnemyDef.attack_params
## (BTActionMeleeAttack.use_agent_attack_params), so this one tree serves any
## melee archetype (Swarmer, Brawler) rather than needing a per-archetype copy.
static func create_enemy_melee_tree() -> BehaviorTree:
	var tree := BehaviorTree.new()
	tree.description = "Melee enemy tree with closest target scan, approach, attack, and breach"
	
	var root := BTSequence.new()
	
	# 1. Target Acquisition: Scan for nearest target (player or colonist)
	var scan_threats = BTActionScanThreatsScript.new()
	var target_groups: Array[StringName] = [&"player", &"players", &"colonists"]
	scan_threats.threat_groups = target_groups
	scan_threats.radius = 128.0
	scan_threats.result_var = &"threat_target"
	root.add_child(scan_threats)


	
	# 2. Approach & Engagement Selector
	var engage_selector := BTSelector.new()
	
	# 2a. Voxel Wall Breach (if path is blocked)
	var breach_seq := BTSequence.new()
	var breach_cond = BTConditionPathBlockedScript.new()
	breach_seq.add_child(breach_cond)
	var breach_action = BTActionBreachVoxelScript.new()
	breach_seq.add_child(breach_action)
	engage_selector.add_child(breach_seq)
	
	# 2b. Navigate to target & Execute attack
	var attack_seq := BTSequence.new()
	
	var chase_nav = BTActionNavigateToScript.new()
	chase_nav.target_var = &"threat_target"
	chase_nav.arrival_distance = 1.2
	attack_seq.add_child(chase_nav)
	
	var attack_action = BTActionMeleeAttackScript.new()
	attack_action.target_var = &"threat_target"
	# EnemyDef.attack_params-driven (data/enemies/*.tres) instead of hardcoded
	# here, so this same tree serves any melee archetype (swarmer, brawler).
	attack_action.use_agent_attack_params = true
	attack_seq.add_child(attack_action)
	
	engage_selector.add_child(attack_seq)
	root.add_child(engage_selector)

	tree.root_task = root
	return tree


## Builds the ranged/kiting enemy tree (Shooter archetype, GDD S5): scans for
## the closest target, fires whenever within its authored holding range
## (RangedActionParams.range_meters), and otherwise closes distance to reach
## that range -- reusing BTActionNavigateTo's arrival_distance_from_agent_attack_range
## mode (same mechanism the melee tree uses for chasing) so the "close enough
## to fire" distance stays in sync with attack_params.range_meters instead of
## being a second, independently-authored number.
##
## Known MVP simplification vs. the full GDD Reposition/MeleeFallback state
## machine: this never backs away once a target closes inside holding range.
## The GDD's own "never advances... only holds or back-pedals" note has no
## corresponding RangedAttack-state transition for a target that closes
## further (Reposition -> MeleeFallback is only reachable from Reposition,
## not from an active RangedAttack), and the design intent explicitly wants
## an aggressive push to end the threat -- "reaching it ends the ranged
## threat immediately, rewarding aggressive play" -- so a Shooter that just
## keeps firing at point-blank range until killed matches intent, not an
## oversight. Back-pedaling/melee-fallback deliberately deferred; see
## docs/architecture/tech-debt.md if it turns out to be needed later.
static func create_enemy_ranged_kiter_tree() -> BehaviorTree:
	var tree := BehaviorTree.new()
	tree.description = "Ranged/kiter enemy tree: closest target scan, hold-range fire, close distance to reach range"

	var root := BTSequence.new()

	# 1. Target Acquisition: Scan for nearest target (player or colonist)
	var scan_threats = BTActionScanThreatsScript.new()
	var target_groups: Array[StringName] = [&"player", &"players", &"colonists"]
	scan_threats.threat_groups = target_groups
	scan_threats.radius = 16.0
	scan_threats.result_var = &"threat_target"
	root.add_child(scan_threats)

	# 2. Fire-or-Close-Distance Selector
	var engage_selector := BTSelector.new()

	# 2a. Fire whenever within the agent's authored holding range (fails,
	# falling through to 2b, when the target is currently out of range).
	var ranged_attack = BTActionRangedAttackScript.new()
	ranged_attack.target_var = &"threat_target"
	engage_selector.add_child(ranged_attack)

	# 2b. Close distance to reach holding range.
	var reposition_nav = BTActionNavigateToScript.new()
	reposition_nav.target_var = &"threat_target"
	reposition_nav.arrival_distance_from_agent_attack_range = true
	engage_selector.add_child(reposition_nav)

	root.add_child(engage_selector)

	tree.root_task = root
	return tree
