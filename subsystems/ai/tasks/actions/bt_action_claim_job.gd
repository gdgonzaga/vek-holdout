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
		
	# Check if we already hold a valid active claim or job
	if blackboard.has_var(claim_var):
		var existing_claim: Variant = blackboard.get_var(claim_var)
		if existing_claim != null and is_instance_valid(existing_claim):
			return SUCCESS
			
	if blackboard.has_var(job_var):
		var existing_job: Variant = blackboard.get_var(job_var)
		if existing_job != null and is_instance_valid(existing_job):
			return SUCCESS

	var colony: Node = agent.get_node_or_null("/root/Colony")
	if colony == null or not "job_board" in colony or colony.job_board == null:
		return FAILURE
		
	var job_board = colony.job_board
	if not (agent is Colonist):
		return FAILURE
		
	var colonist := agent as Colonist
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
		return SUCCESS
		
	return FAILURE
