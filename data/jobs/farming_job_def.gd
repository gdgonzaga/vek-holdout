extends JobDef
class_name FarmingJobDef
## Shared skeleton for the farm-plot labors (GDD §6 / Farming, ARCH "Farming"):
## Sow, Water, Tend. Each is one WORK leg against the plot's Growable — the
## subclasses differ only in the needs-predicate and the one completion call.
## Resource-with-virtuals per AGENTS.md (composition over inheritance); a future
## FertilizeJobDef (job-extensions.md) drops in by overriding _needs/_apply.
## Skill XP is ColonistAI._end_job's alone — nothing here records (skills.md).

## Seconds of WORK before the skill multiplier (authored per .tres — rule 1).
@export var work_time := 2.0


## Whether the plot currently needs this labor. Drives the leg, claimability,
## and lifetime — the shared is_available reads "a valid Growable that needs it".
func _needs(_growable: Growable) -> bool:
	return false


## Apply the labor's effect on completion.
func _apply(_growable: Growable, _actor: Node) -> void:
	pass


func get_next_leg(_actor: Node, job: Job) -> JobLeg:
	var growable := _growable_from(job.target_node)
	if growable == null or not is_instance_valid(growable):
		return null
	if not _needs(growable):
		return null
	var leg := JobLeg.new()
	leg.location = job.location
	leg.target_node = job.target_node
	return leg


func begin(actor: Node, _leg: JobLeg, _job: Job) -> float:
	var duration := work_time
	var colonist := actor as Colonist
	if colonist != null and colonist.skill_set != null:
		duration = work_time / colonist.skill_set.get_multiplier(labor_id)
	return duration


func complete(actor: Node, leg: JobLeg, _job: Job) -> void:
	var growable := _growable_from(leg.target_node)
	if growable == null or not is_instance_valid(growable):
		return
	_apply(growable, actor)


func is_available(job: Job) -> bool:
	var growable := _growable_from(job.target_node)
	return growable != null and is_instance_valid(growable) and _needs(growable)


func should_close(job: Job) -> bool:
	return not is_available(job)


## Resolve a job target to its Growable — the node itself or its "Growable"
## child (farm-plot furniture carries the component).
func _growable_from(node: Variant) -> Growable:
	if not is_instance_valid(node):
		return null
	var n := node as Node
	if n == null:
		return null
	var g := n as Growable
	if g != null:
		return g
	return n.get_node_or_null("Growable") as Growable
