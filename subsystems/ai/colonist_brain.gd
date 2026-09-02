## Subsystem: AI / Brain
## Utility AI goal arbitration component that evaluates needs and sets blackboard goals (ARCH §6).
class_name ColonistBrain
extends Node

const EVAL_INTERVAL: float = 1.5

@export var bt_player: BTPlayer

var _needs: ColonistNeeds
## Starts at EVAL_INTERVAL so the very first _process frame evaluates goals:
## until it runs, current_goal/target_smart_object don't exist on the
## blackboard, and the needs-branch NavigateTo's generic fallbacks would grab
## active_job the instant the work branch claims one.
var _poll_timer: float = EVAL_INTERVAL


func _ready() -> void:
	var colonist := get_parent()
	if colonist:
		if _needs == null:
			_needs = colonist.get_node_or_null("ColonistNeeds") as ColonistNeeds
		if not bt_player:
			bt_player = colonist.get_node_or_null("BTPlayer") as BTPlayer


func _process(delta: float) -> void:
	_poll_timer += delta
	if _poll_timer >= EVAL_INTERVAL:
		_poll_timer = 0.0
		evaluate_goals()


## Evaluates current desires and writes winning goal and target to LimboAI Blackboard.
func evaluate_goals() -> void:
	var colonist := get_parent()
	if colonist and _needs == null:
		_needs = colonist.get_node_or_null("ColonistNeeds") as ColonistNeeds
	if colonist and bt_player == null:
		bt_player = colonist.get_node_or_null("BTPlayer") as BTPlayer

	if not bt_player or not bt_player.blackboard:
		return

	var scores: Dictionary = {}
	var best_targets: Dictionary = {}

	# 1. Evaluate need-based goals
	if _needs != null:
		var defs := ColonistNeeds.get_need_defs()
		for need_id in defs:
			var def: Resource = defs[need_id]
			var deficit: float = _needs.get_deficit(need_id)
			var base_score: float = 0.0
			if def.response_curve != null:
				base_score = def.response_curve.sample(deficit)
			else:
				base_score = deficit # Linear deficit fallback
			base_score = clampf(base_score, 0.0, 1.0)

			var dist_penalty: float = 1.0
			var nearest_target: Node3D = null
			if is_inside_tree() and colonist and colonist is Node3D and def.target_group != &"":
				var objects := get_tree().get_nodes_in_group(def.target_group)
				if not objects.is_empty():
					var min_dist := INF
					var parent_pos: Vector3 = colonist.global_position
					for obj in objects:
						if is_instance_valid(obj) and not obj.is_queued_for_deletion() and obj is Node3D:
							var d := parent_pos.distance_to(obj.global_position)
							if d < min_dist:
								min_dist = d
								nearest_target = obj as Node3D
					if min_dist != INF:
						dist_penalty = clampf(1.0 - (min_dist / 100.0), 0.2, 1.0)

			var final_score: float = base_score * dist_penalty
			if nearest_target == null:
				final_score = 0.0

			var goal_name: StringName = def.goal_name
			if not scores.has(goal_name) or final_score > scores[goal_name]:
				scores[goal_name] = final_score
				if nearest_target != null:
					best_targets[goal_name] = nearest_target

	# 2. Evaluate work goal
	var work_score := _get_work_score(colonist)
	if not scores.has(&"work") or work_score > scores[&"work"]:
		scores[&"work"] = work_score

	# 3. Apply Action Commitment inertia (+0.30 bonus to active goal if not critical)
	var active_goal: StringName = &"none"
	if bt_player.blackboard.has_var(&"current_goal"):
		active_goal = bt_player.blackboard.get_var(&"current_goal")

	var has_critical_need := false
	if _needs != null:
		var defs := ColonistNeeds.get_need_defs()
		for need_id in defs:
			var def: Resource = defs[need_id]
			var val: float = _needs.get_need(need_id)
			if val <= def.emergency_threshold:
				has_critical_need = true
				break

	if active_goal != &"none" and not has_critical_need:
		if scores.has(active_goal) and scores[active_goal] > 0.0:
			scores[active_goal] += 0.30

	# 4. Find winning goal (defaults to &"work" if all scores are <= 0.0)
	var winning_goal: StringName = &"work"
	var max_score: float = 0.0
	for goal in scores:
		var s: float = scores[goal]
		if s > max_score:
			max_score = s
			winning_goal = goal

	bt_player.blackboard.set_var(&"current_goal", winning_goal)
	if best_targets.has(winning_goal):
		bt_player.blackboard.set_var(&"target_smart_object", best_targets[winning_goal])
	else:
		bt_player.blackboard.set_var(&"target_smart_object", null)


func _get_work_score(actor: Node) -> float:
	if not is_inside_tree() or not is_instance_valid(actor):
		return 0.0
	var colony = get_node_or_null("/root/Colony")
	if colony == null or not "job_board" in colony or colony.job_board == null:
		return 0.0
	if not (actor is Colonist):
		return 0.5 # Default fallback score for mock/generic actors in unit tests
		
	var colonist := actor as Colonist
	var best_job = colony.job_board.get_best_job_for(colonist)
	if best_job == null:
		return 0.0

	var def_obj: Resource = null
	if "def" in best_job:
		def_obj = best_job.def
	elif "job_def" in best_job:
		def_obj = best_job.job_def
	if def_obj is DeployJobDef or ("labor_id" in best_job and str(best_job.labor_id) == "deploy"):
		return 2.0
	var labor_priority: int = int(colonist.labor_priorities.get(best_job.labor_id, 0))
	var base_priority: float = def_obj.base_priority if def_obj != null and "base_priority" in def_obj else 0.5
	return (float(labor_priority) / 5.0) * base_priority
