## Subsystem: AI Tasks
## Validates whether an active job or claim still needs execution (used to exit repeat loops cleanly).
@tool
class_name BTConditionJobStillNeeded
extends BTCondition

## Blackboard variable storing the job or claim
@export var job_var: StringName = &"active_job"


func _generate_name() -> String:
	return "Job Still Needed  job: %s" % LimboUtility.decorate_var(job_var)


func _tick(_delta: float) -> Status:
	if not blackboard:
		return FAILURE
		
	var job: Variant = null
	if blackboard.has_var(job_var):
		job = blackboard.get_var(job_var)
	elif blackboard.has_var(&"active_claim"):
		job = blackboard.get_var(&"active_claim")
		
	if job == null:
		return FAILURE
		
	if job is Dictionary:
		if job.has("target_node"):
			var tn = job.get("target_node")
			if not is_instance_valid(tn) or tn == null:
				return FAILURE
			if tn is Node and tn.is_queued_for_deletion():
				return FAILURE
		return SUCCESS
		
	if not is_instance_valid(job):
		return FAILURE
		
	# Check target node validity
	if "target_node" in job:
		var tn = job.target_node
		if not is_instance_valid(tn) or tn == null:
			return FAILURE
		if tn is Node and tn.is_queued_for_deletion():
			return FAILURE
			
		var sink = tn
		if sink.has_method("has_complete_materials") and sink.has_complete_materials():
			return FAILURE
			
	# Check def availability
	if "def" in job and job.def != null and job.def.has_method("is_available"):
		if not job.def.is_available(job):
			return FAILURE
	elif job.has_method("is_available"):
		if not job.is_available():
			return FAILURE
			
	return SUCCESS
