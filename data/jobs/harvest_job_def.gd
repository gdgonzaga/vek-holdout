extends JobDef
class_name HarvestJobDef
## Harvesting labor (GDD §6.10, ARCH "Harvesting"): chop or gather a marked
## resource node over its HarvestParams.work_time, then resolve yields into the
## harvester's carry inventory and remove the node.
##
## Expressed as a single-leg job: get_next_leg returns the node leg once (the
## colonist walks to a stand-adjacent cell), begin reports the skill-scaled
## duration, complete applies the harvest work and awards skill XP.
##
## Single-colonist (max_assignees=1, the JobDef default). A job is available
## while its target node is valid AND is_marked_for_harvest is true.

func get_next_leg(_actor: Node, job: Job) -> JobLeg:
	var harvestable := _harvestable_from(job.target_node)
	if harvestable == null or not is_instance_valid(harvestable):
		return null
	if not harvestable.is_marked_for_harvest():
		return null
	var leg := JobLeg.new()
	leg.location = job.location
	leg.target_node = job.target_node
	return leg


func begin(actor: Node, leg: JobLeg, _job: Job) -> float:
	var harvestable := _harvestable_from(leg.target_node)
	if harvestable == null:
		return 0.0
	var params := harvestable.params()
	if params == null:
		return 0.0
	var colonist := actor as Colonist
	var duration: float = params.work_time
	if colonist != null and colonist.skill_set != null:
		duration = params.work_time / colonist.skill_set.get_multiplier(labor_id)
	return maxf(0.0, duration - harvestable.work_done())


func complete(actor: Node, leg: JobLeg, _job: Job) -> void:
	var harvestable := _harvestable_from(leg.target_node)
	if harvestable == null or not is_instance_valid(harvestable):
		return
	var completed := harvestable.complete(actor)
	if completed:
		var colonist := actor as Colonist
		if colonist != null and colonist.skill_set != null:
			colonist.skill_set.record_use_for_labor(labor_id)


func on_end(success: bool, _actor: Node, leg: JobLeg, _job: Job, elapsed: float) -> void:
	if success or leg == null:
		return
	var harvestable := _harvestable_from(leg.target_node)
	if is_instance_valid(harvestable):
		harvestable.set_work_done(harvestable.work_done() + elapsed)


func is_available(job: Job) -> bool:
	var harvestable := _harvestable_from(job.target_node)
	return harvestable != null and is_instance_valid(harvestable) and harvestable.is_marked_for_harvest()


func should_close(job: Job) -> bool:
	var harvestable := _harvestable_from(job.target_node)
	return harvestable == null or not is_instance_valid(harvestable) or not harvestable.is_marked_for_harvest()


func _harvestable_from(node: Variant) -> Harvestable:
	if not is_instance_valid(node):
		return null
	var n := node as Node
	if n == null:
		return null
	var h := n as Harvestable
	if h != null:
		return h
	return n.get_node_or_null("Harvestable") as Harvestable
