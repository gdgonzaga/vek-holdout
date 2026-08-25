extends JobDef
class_name FarmingJobDef
## Shared skeleton for the farm-plot labors (Sow, Water, Tend) driven by the
## universal work tree. Each is one WORK cycle against the plot's Growable —
## subclasses differ only in the needs-predicate and the one completion call
## (_needs/_apply). Resource-with-virtuals per AGENTS.md (composition over
## inheritance); a future FertilizeJobDef (job-extensions.md) drops in by
## overriding _needs/_apply. Cycle duration is the authored work_duration
## (skill scaling applied by PerformWork); skill XP is base _finish's alone
## (skills.md: single XP entry point).


## Whether the plot currently needs this labor. Drives claimability and
## lifetime — the shared is_available reads "a valid Growable that needs it".
func _needs(_growable: Growable) -> bool:
	return false


## Apply the labor's effect on completion.
func _apply(_growable: Growable, _actor: Node) -> void:
	pass


func complete(actor: Node, job: Variant) -> void:
	var growable := _growable_of_job(job)
	if growable != null:
		_apply(growable, actor)
	_finish(actor, job)


func is_available(job: Variant) -> bool:
	var growable := _growable_of_job(job)
	return growable != null and _needs(growable)


func should_close(job: Variant) -> bool:
	return not is_available(job)


## Resolve a job target to its Growable — the node itself or its "Growable"
## child (farm-plot furniture carries the component).
static func growable_from(node: Variant) -> Growable:
	if not is_instance_valid(node):
		return null
	var n := node as Node
	if n == null:
		return null
	var g := n as Growable
	if g != null:
		return g
	return n.get_node_or_null("Growable") as Growable


func _growable_of_job(job: Variant) -> Growable:
	if job == null or not "target_node" in job:
		return null
	return growable_from(job.target_node)
