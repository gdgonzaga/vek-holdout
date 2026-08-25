extends JobDef
class_name HarvestJobDef
## Harvesting labor (GDD §6.10, ARCH "Harvesting", ARCH "Farming"): work a
## marked resource node / mature farm plot, then resolve yields into the
## harvester's carry inventory (Harvestable.complete handles both node kinds
## and emits the signals that drop this job from the board). Single-colonist;
## claimable while the target is valid and still marked.

## Cycle duration: the target's effective work time (a farm plot's crop
## decides the effort, not the plot) minus work already persisted from aborted
## attempts — skill scaling is applied by PerformWork on top.
func begin(_actor: Node, job: Variant) -> float:
	var harvestable := _harvestable_of_job(job)
	if harvestable == null:
		return 0.0
	return maxf(0.0, harvestable.effective_work_time() - harvestable.work_done())


func complete(actor: Node, job: Variant) -> void:
	var harvestable := _harvestable_of_job(job)
	if harvestable != null:
		harvestable.complete(actor)
	_finish(actor, job)


## Claimable while the target is a live, still-marked Harvestable.
func is_available(job: Variant) -> bool:
	var harvestable := _harvestable_of_job(job)
	return harvestable != null and harvestable.is_marked_for_harvest()


## Leaves the board when the target is gone or unmarked (Harvestable.complete
## emits both cases for Colony's listeners; this covers a manual unmark).
func should_close(job: Variant) -> bool:
	return not is_available(job)


## Preempted mid-harvest: persist the partial work so the next attempt resumes
## instead of restarting (the Harvestable.work_done resume seam).
func on_abort(_actor: Node, job: Variant, elapsed: float) -> void:
	var harvestable := _harvestable_of_job(job)
	if harvestable != null:
		harvestable.set_work_done(harvestable.work_done() + elapsed)


static func harvestable_from(node: Variant) -> Harvestable:
	if not is_instance_valid(node):
		return null
	var n := node as Node
	if n == null:
		return null
	var h := n as Harvestable
	if h != null:
		return h
	return n.get_node_or_null("Harvestable") as Harvestable


func _harvestable_of_job(job: Variant) -> Harvestable:
	if job == null or not "target_node" in job:
		return null
	return harvestable_from(job.target_node)
