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


var _unreachable_food_blacklist: Dictionary = {}

## Smart object this colonist currently holds a claim on (a bed, a recreation
## object). Held here rather than on the blackboard because the claim must be
## released when the colonist leaves the tree, which the blackboard can't observe.
var _reserved_object: Node = null

## Node the claim was taken for. Recorded rather than re-derived from get_parent()
## at release time so the release always reaches the same slot the reserve took,
## even while the brain is being detached.
var _reservation_holder: Node = null


func _ready() -> void:
	var colonist := get_parent()
	if colonist:
		if _needs == null:
			_needs = colonist.get_node_or_null("ColonistNeeds") as ColonistNeeds
		if not bt_player:
			bt_player = colonist.get_node_or_null("BTPlayer") as BTPlayer


func _process(delta: float) -> void:
	# 1. Blacklist Maintenance: Advance cooldown timers on temporarily unreachable food sources.
	_tick_unreachable_food_blacklist(delta)

	_poll_timer += delta
	if _poll_timer >= EVAL_INTERVAL:
		_poll_timer = 0.0
		evaluate_goals()


func _exit_tree() -> void:
	# 1. Claim Cleanup: A colonist that dies or despawns mid-approach would
	# otherwise hold a bed or recreation slot forever, permanently shrinking the
	# colony's usable furniture.
	_release_reservation()


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
	var deficits: Dictionary = {}
	var defs := ColonistNeeds.get_need_defs()

	# 1. Evaluate need-based goals
	if _needs != null:
		for need_id in defs:
			var def: Resource = defs[need_id]
			var deficit: float = _needs.get_deficit(need_id)
			deficits[need_id] = deficit
			var base_score: float = 0.0
			if def.response_curve != null:
				base_score = def.response_curve.sample(deficit)
			else:
				base_score = deficit # Linear deficit fallback
			base_score = clampf(base_score, 0.0, 1.0)

			var dist_penalty: float = 1.0
			var nearest_target: Node3D = null

			if def.goal_name == &"eat" or need_id == &"hunger":
				# 1. Food Target Resolution: Checks inventory first, then unblacklisted colony food sources.
				nearest_target = _resolve_best_food_target(colonist)
				if nearest_target == null and is_inside_tree() and colonist is Node3D and def.target_group != &"":
					# 2. Smart Object Group Fallback: Inspect group nodes if storage search yielded nothing.
					nearest_target = _resolve_nearest_group_target(colonist, def.target_group)

				if nearest_target != null and colonist is Node3D:
					if nearest_target == colonist:
						dist_penalty = 1.0
					else:
						var d: float = (colonist as Node3D).global_position.distance_to(nearest_target.global_position)
						dist_penalty = clampf(1.0 - (d / 100.0), 0.2, 1.0)
			elif is_inside_tree() and colonist and colonist is Node3D and def.target_group != &"":
				# 1. Group Target Resolution: Finds nearest smart object in the need's target group.
				nearest_target = _resolve_nearest_group_target(colonist, def.target_group)
				if nearest_target != null:
					var d := (colonist as Node3D).global_position.distance_to(nearest_target.global_position)
					dist_penalty = clampf(1.0 - (d / 100.0), 0.2, 1.0)

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
	var winning_target: Variant = best_targets.get(winning_goal, null)
	bt_player.blackboard.set_var(&"target_smart_object", winning_target)

	# 1. Claim Handover: Take the winner's slot and drop any stale one now that a
	# winner exists, so rival colonists stop scoring this object on their next poll.
	_sync_reservation(winning_target as Node, colonist)

	# 2. Stand Position Publication: Resolve the exact spot this colonist should
	# occupy. Written every cycle (null included) so the recreation branch can
	# never navigate to a position left over from a previous target.
	bt_player.blackboard.set_var(&"target_stand_pos", _resolve_stand_pos(winning_target as Node, colonist))

	# 3. Utility AI Evaluation Logging: Record evaluated desires and chosen behavior.
	ColonistLogger.log_brain_eval(colonist, winning_goal, scores, deficits, winning_target, has_critical_need, active_goal != &"none")


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


## Blacklists a food source from being selected by this colonist for a given duration.
func blacklist_food_source(source: Node, duration: float = 10.0) -> void:
	if source != null and is_instance_valid(source):
		_unreachable_food_blacklist[source] = duration


## Returns an array of currently blacklisted food source nodes.
func get_blacklisted_food_sources() -> Array:
	return _unreachable_food_blacklist.keys()


func _tick_unreachable_food_blacklist(delta: float) -> void:
	## Auxiliary: Ticks down blacklist timers and removes expired entries.
	if _unreachable_food_blacklist.is_empty():
		return

	var expired: Array = []
	for src in _unreachable_food_blacklist.keys():
		if not is_instance_valid(src):
			expired.append(src)
			continue
		var rem: float = _unreachable_food_blacklist[src] - delta
		if rem <= 0.0:
			expired.append(src)
		else:
			_unreachable_food_blacklist[src] = rem

	for exp_src in expired:
		_unreachable_food_blacklist.erase(exp_src)


func _resolve_best_food_target(actor: Node) -> Node3D:
	## Auxiliary: Resolves nearest food target, checking pockets first then storage.
	if not is_instance_valid(actor):
		return null

	# 1. Pocket Food Check: If colonist carries food, actor itself is the target (0-dist).
	if _actor_has_food_in_pockets(actor) and actor is Node3D:
		return actor as Node3D

	# 2. Colony Storage Search: Query StorageRegistry for closest valid food container.
	var colony: Node = get_node_or_null("/root/Colony")
	if colony != null and "storage_registry" in colony and colony.storage_registry != null:
		var registry: StorageRegistry = colony.storage_registry
		var pos: Vector3 = (actor as Node3D).global_position if actor is Node3D else Vector3.ZERO
		var best_data: Dictionary = registry.find_best_food_source(pos, get_blacklisted_food_sources())
		if not best_data.is_empty() and best_data.has("source_node"):
			var src: Node = best_data["source_node"]
			if src is Node3D and is_instance_valid(src):
				return src as Node3D

	return null
	

func _resolve_nearest_group_target(colonist: Node3D, target_group: StringName) -> Node3D:
	## Auxiliary: Resolves the nearest Node3D in target_group this colonist can
	## actually claim, so a full bed or an occupied single-user recreation object
	## is skipped rather than drawing every colonist to the same piece of furniture.
	if not is_inside_tree() or colonist == null:
		return null
	return AIUtils.find_nearest_in_group_where(
		get_tree(),
		target_group,
		colonist.global_position,
		func(node: Node3D) -> bool: return _is_smart_object_usable_by(node, colonist)
	)


func _is_smart_object_usable_by(node: Node, colonist: Node) -> bool:
	## Auxiliary: Applies a smart object's IOccupiable gate when it has one.
	## Nodes with no occupancy component (food crates, plain furniture) are always
	## usable, which is what keeps existing need targeting behaviour unchanged.
	var occupancy := _find_occupancy_component(node)
	if occupancy == null:
		return true
	return bool(occupancy.call(&"is_usable_by", colonist))


func _find_occupancy_component(node: Node) -> Node:
	## Auxiliary: Returns the first child implementing the IOccupiable contract.
	if node == null or not is_instance_valid(node):
		return null
	for child in node.get_children():
		if child.has_method(&"is_usable_by"):
			return child
	return null


func _sync_reservation(winning_target: Node, colonist: Node) -> void:
	## Auxiliary: Moves this colonist's claim onto the winning target, releasing
	## whatever it held before. Called once per evaluation after the winner is
	## known — never during scoring, where reserving a loser would starve rivals.
	if winning_target == _reserved_object and is_instance_valid(_reserved_object):
		return

	# 1. Stale Claim Release: Hand back the previous slot before taking a new one,
	# otherwise a colonist that changes its mind leaks a slot for the whole run.
	_release_reservation()

	if winning_target == null or colonist == null:
		return
	var occupancy := _find_occupancy_component(winning_target)
	if occupancy == null:
		return
	if bool(occupancy.call(&"reserve", colonist)):
		_reserved_object = winning_target
		_reservation_holder = colonist


func _release_reservation() -> void:
	## Auxiliary: Drops the held claim if the object still exists.
	if _reserved_object != null and is_instance_valid(_reserved_object):
		var occupancy := _find_occupancy_component(_reserved_object)
		if occupancy != null:
			occupancy.call(&"release", _reservation_holder)
	_reserved_object = null
	_reservation_holder = null


func _resolve_stand_pos(winning_target: Node, colonist: Node) -> Variant:
	## Auxiliary: Resolves the exact world position this colonist should stand at
	## to use the winning target, or null when the target has no opinion.
	if winning_target == null or colonist == null:
		return null
	var occupancy := _find_occupancy_component(winning_target)
	if occupancy == null or not occupancy.has_method(&"use_position_for"):
		return null
	return occupancy.call(&"use_position_for", colonist)


func _actor_has_food_in_pockets(actor: Node) -> bool:
	## Auxiliary: Returns true if actor has any edible food in carry inventory.
	var inv: CharacterInventory = AIUtils.resolve_character_inventory(actor)
	if inv == null or inv.items == null or not (inv.items is Dictionary):
		return false

	for key in inv.items.keys():
		var item_id := str(key)
		if inv.get_item_count(item_id) > 0 and AIUtils.is_edible_item(item_id):
			return true
	return false
