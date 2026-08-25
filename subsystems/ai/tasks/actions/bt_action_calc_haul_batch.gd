## Subsystem: AI Tasks
## Calculates and clamps a batch size for hauling based on agent capacity and job need.
@tool
class_name BTActionCalcHaulBatch
extends BTAction

## Blackboard variable storing the haul job or claim
@export var job_var: StringName = &"active_job"

## Blackboard variable where the calculated batch amount is written
@export var batch_amount_var: StringName = &"haul_batch_amount"


func _generate_name() -> String:
	return "Calc Haul Batch  job: %s -> %s" % [
		LimboUtility.decorate_var(job_var),
		LimboUtility.decorate_var(batch_amount_var)
	]


func _tick(_delta: float) -> Status:
	if not agent or not blackboard:
		return FAILURE
		
	var job: Variant = null
	if blackboard.has_var(job_var):
		job = blackboard.get_var(job_var)
	elif blackboard.has_var(&"active_claim"):
		job = blackboard.get_var(&"active_claim")
		
	if job == null:
		return FAILURE
		
	var remaining_need: int = 0
	if job is Dictionary:
		remaining_need = int(job.get("remaining_amount", 0))
	elif is_instance_valid(job):
		if job.has_method("get_remaining_units"):
			remaining_need = int(job.get_remaining_units())
		elif "unclaimed_units" in job:
			remaining_need = int(job.unclaimed_units)
		elif "remaining_amount" in job:
			remaining_need = int(job.remaining_amount)
		elif "target_node" in job and job.target_node != null and is_instance_valid(job.target_node):
			var sink = job.target_node
			if sink.has_method("needed_item_ids") and sink.has_method("remaining_need"):
				var item_id: String = ""
				if "item_id" in job and job.item_id != "":
					item_id = str(job.item_id)
				else:
					var ids = sink.needed_item_ids()
					if not ids.is_empty():
						item_id = ids[0]
				if item_id != "":
					remaining_need = sink.remaining_need(item_id)
				
	if remaining_need <= 0:
		return FAILURE
		
	var carry_capacity: int = 10
	if agent.has_method("remaining_capacity"):
		carry_capacity = int(agent.remaining_capacity())
	elif "inventory" in agent and agent.inventory != null and agent.inventory.has_method("remaining_capacity"):
		carry_capacity = int(agent.inventory.remaining_capacity())
		
	if carry_capacity <= 0:
		return FAILURE
		
	var batch_amount: int = mini(remaining_need, carry_capacity)
	blackboard.set_var(batch_amount_var, batch_amount)
	return SUCCESS
