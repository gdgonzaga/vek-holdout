extends JobDef
class_name WaterJobDef
## Watering labor (GDD §6 / Farming, ARCH "Farming"): colonist waters a thirsty crop.

func get_next_leg(_actor: Node, job: Job) -> JobLeg:
	var growable := _growable_from(job.target_node)
	if growable == null or not is_instance_valid(growable):
		return null
	if not growable.needs_water():
		return null
	var leg := JobLeg.new()
	leg.location = job.location
	leg.target_node = job.target_node
	return leg


func begin(actor: Node, _leg: JobLeg, _job: Job) -> float:
	var base_time := 2.0
	var colonist := actor as Colonist
	var duration := base_time
	if colonist != null and colonist.skill_set != null:
		duration = base_time / colonist.skill_set.get_multiplier(labor_id)
	return duration


func complete(actor: Node, leg: JobLeg, _job: Job) -> void:
	var growable := _growable_from(leg.target_node)
	if growable == null or not is_instance_valid(growable):
		return
	growable.water(actor)


func is_available(job: Job) -> bool:
	var growable := _growable_from(job.target_node)
	return growable != null and is_instance_valid(growable) and growable.needs_water()


func should_close(job: Job) -> bool:
	return not is_available(job)


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
