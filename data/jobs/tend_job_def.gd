extends FarmingJobDef
class_name TendJobDef
## Tending labor (GDD §6 / Farming, ARCH "Farming"): colonist weeds/prunes a crop.
## Evaluates CropDef.tend_conditions (skills + tool requirements).

func meets_requirements(actor: Node, job: Job) -> bool:
	if not super.meets_requirements(actor, job):
		return false
	var growable := _growable_from(job.target_node)
	if growable == null:
		return false
	var crop_def := growable.get_crop_def()
	if crop_def != null:
		for condition in crop_def.tend_conditions:
			if not condition.is_met(actor, job.target_node):
				return false
	return true


func _needs(growable: Growable) -> bool:
	return growable.needs_tending()


func _apply(growable: Growable, actor: Node) -> void:
	growable.tend(actor)
