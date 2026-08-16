extends JobDef
class_name SowJobDef
## Sowing labor (GDD §6 / Farming, ARCH "Farming"): colonist travels to an empty
## farm plot and plants the configured crop seed.

func meets_requirements(actor: Node, job: Job) -> bool:
	if not super.meets_requirements(actor, job):
		return false
	var growable := _growable_from(job.target_node)
	if growable == null:
		return false
	var sel_def := CropLibrary.get_crop(growable.get_selected_crop_id())
	if sel_def != null:
		for condition in sel_def.plant_conditions:
			if not condition.is_met(actor, job.target_node):
				return false
	return true


func get_next_leg(_actor: Node, job: Job) -> JobLeg:
	var growable := _growable_from(job.target_node)
	if growable == null or not is_instance_valid(growable):
		return null
	if growable.get_crop_state() != Growable.CropState.EMPTY or growable.get_selected_crop_id() == "":
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
	var crop_id := growable.get_selected_crop_id()
	if crop_id != "":
		growable.plant(crop_id)
		var colonist := actor as Colonist
		if colonist != null and colonist.skill_set != null:
			colonist.skill_set.record_use_for_labor(labor_id)


func is_available(job: Job) -> bool:
	var growable := _growable_from(job.target_node)
	return growable != null and is_instance_valid(growable) and growable.get_crop_state() == Growable.CropState.EMPTY and growable.get_selected_crop_id() != ""


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
