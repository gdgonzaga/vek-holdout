extends FarmingJobDef
class_name TendJobDef
## Tending labor (GDD §6 / Farming, ARCH "Farming"): colonist weeds/prunes a crop.
## Evaluates CropDef.tend_conditions (skills + tool requirements).

func meets_requirements_any(actor: Node, job: Variant) -> bool:
	if not super.meets_requirements_any(actor, job):
		return false
	var t_node: Node = job.target_node if job != null and "target_node" in job else null
	var growable := FarmingJobDef.growable_from(t_node)
	if growable == null:
		return false
	var crop_def := growable.get_crop_def()
	if crop_def != null:
		for condition in crop_def.tend_conditions:
			if not condition.is_met(actor, t_node):
				return false
	return true
