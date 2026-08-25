## Subsystem: AI Tasks
## Claims the best available job or work units from Colony.job_board and stores it in the Blackboard.
@tool
class_name BTActionClaimJob
extends BTAction

## Blackboard variable where the active job instance is stored
@export var job_var: StringName = &"active_job"

## Blackboard variable where the worker claim is stored (if fractional)
@export var claim_var: StringName = &"active_claim"

## Blackboard variable where the target world position is written
@export var target_pos_var: StringName = &"target_pos"


func _generate_name() -> String:
	return "Claim Job  -> %s, %s" % [
		LimboUtility.decorate_var(job_var),
		LimboUtility.decorate_var(claim_var)
	]


func _tick(_delta: float) -> Status:
	if not agent or not blackboard:
		return FAILURE
		
	var colonist: Colonist = agent as Colonist if agent is Colonist else null
	
	# Check if we already hold a valid active claim or job. Spent ones (claim
	# finished, parent job completed/cancelled/freed) are dropped so a fresh
	# claim is made next — holding them made this task return SUCCESS forever
	# for work that was already done.
	if blackboard.has_var(claim_var):
		var existing_claim: Variant = blackboard.get_var(claim_var)
		if existing_claim != null and is_instance_valid(existing_claim):
			if _claim_is_spent(existing_claim):
				blackboard.erase_var(claim_var)
				blackboard.erase_var(job_var)
				if agent is Colonist:
					(agent as Colonist).current_job = null
			else:
				_cleanup_incompatible_held_items(colonist)
				return SUCCESS

	if blackboard.has_var(job_var):
		var existing_job: Variant = blackboard.get_var(job_var)
		if existing_job != null and is_instance_valid(existing_job):
			if _job_is_dead(existing_job):
				blackboard.erase_var(job_var)
				if agent is Colonist:
					(agent as Colonist).current_job = null
			else:
				_cleanup_incompatible_held_items(colonist)
				return SUCCESS

	var colony: Node = agent.get_node_or_null("/root/Colony")
	if colony == null or not "job_board" in colony or colony.job_board == null:
		return FAILURE
		
	var job_board = colony.job_board
	if not (agent is Colonist):
		return FAILURE
		
	var best_job = job_board.get_best_job_for(colonist)
	if best_job == null:
		return FAILURE
		
	# Fractional JobInstance support
	if best_job.has_method("try_claim_units"):
		var claim = best_job.try_claim_units(colonist)
		if claim == null:
			return FAILURE
		blackboard.set_var(claim_var, claim)
		blackboard.set_var(job_var, best_job)
		colonist.current_job = best_job
		if "world_position" in best_job:
			blackboard.set_var(target_pos_var, best_job.world_position)
		elif "target_pos" in claim:
			blackboard.set_var(target_pos_var, claim.target_pos)
		elif "target_position" in best_job:
			blackboard.set_var(target_pos_var, best_job.target_position)
			
		if "job_def" in best_job and best_job.job_def != null and "required_tool_tag" in best_job.job_def:
			blackboard.set_var(&"required_tool_tag", best_job.job_def.required_tool_tag)
			_cleanup_incompatible_held_items(colonist)
		return SUCCESS
		
	# Legacy Job support
	if best_job.has_method("try_assign"):
		if not best_job.try_assign(colonist):
			return FAILURE
		blackboard.set_var(job_var, best_job)
		colonist.current_job = best_job
		if best_job.anchor_cell != Vector3i.MAX:
			blackboard.set_var(target_pos_var, Vector3(best_job.anchor_cell) + Vector3(0.5, 0.5, 0.5))
		elif best_job.target_node != null and is_instance_valid(best_job.target_node):
			blackboard.set_var(target_pos_var, (best_job.target_node as Node3D).global_position if best_job.target_node is Node3D else Vector3.ZERO)
		if best_job.def != null and "required_tool_tag" in best_job.def:
			blackboard.set_var(&"required_tool_tag", best_job.def.required_tool_tag)
			_cleanup_incompatible_held_items(colonist)
		return SUCCESS
		
	return FAILURE


func _cleanup_incompatible_held_items(colonist: Colonist) -> void:
	if colonist == null or colonist.inventory == null or not colonist.hands_full():
		return
	var req_tag: StringName = &""
	if blackboard.has_var(&"required_tool_tag"):
		req_tag = blackboard.get_var(&"required_tool_tag")
	if req_tag != &"":
		if not colonist.inventory.has_item_tag(String(req_tag)):
			colonist.drop_held_item()


## True when a held claim can no longer be worked: its units are finished, or
## its parent job is freed/completed/cancelled.
func _claim_is_spent(claim: Variant) -> bool:
	if claim.has_method("is_finished") and bool(claim.is_finished()):
		return true
	if "job" in claim:
		var claim_job: Variant = claim.job
		if claim_job == null or not is_instance_valid(claim_job):
			return true
		return _job_is_dead(claim_job)
	return false


## True when a job object is completed or cancelled (missing flags = alive).
func _job_is_dead(job: Variant) -> bool:
	if "is_completed" in job and bool(job.is_completed):
		return true
	if "is_cancelled" in job and bool(job.is_cancelled):
		return true
	return false
