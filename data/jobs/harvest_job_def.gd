extends JobDef
class_name HarvestJobDef
## Harvesting labor (GDD §6.10, ARCH "Harvesting", ARCH "Farming"): chop or gather
## a marked resource node over its work_time, then resolve yields into the
## harvester's carry inventory.
##
## Expressed as a single-leg job: get_next_leg returns the node leg once (the
## colonist walks to a stand-adjacent cell), begin reports the skill-scaled
## duration, complete applies the harvest work. Skill XP is ColonistAI._end_job's
## alone — the def never records (skills.md: single XP entry point).
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
	var base_time: float = 0.0
	var target_node := leg.target_node as Node
	var growable: Growable = null
	if target_node != null:
		growable = target_node.get_node_or_null("Growable") as Growable
	if growable != null:
		var cdef := growable.get_crop_def()
		base_time = cdef.base_harvest_time if cdef != null else 3.0
	else:
		var params := harvestable.params()
		if params == null:
			return 0.0
		base_time = params.work_time

	var colonist := actor as Colonist
	var duration: float = base_time
	if colonist != null and colonist.skill_set != null:
		duration = base_time / colonist.skill_set.get_multiplier(labor_id)
	return maxf(0.0, duration - harvestable.work_done())


func complete(actor: Node, leg: JobLeg, _job: Job) -> void:
	var harvestable := _harvestable_from(leg.target_node)
	if harvestable == null or not is_instance_valid(harvestable):
		return
	harvestable.complete(actor)


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
