extends FarmingJobDef
class_name SowJobDef
## Sowing labor (GDD §6 / Farming, ARCH "Farming"): colonist travels to an empty
## farm plot and plants the configured crop seed.

func meets_requirements_any(actor: Node, job: Variant) -> bool:
	if not super.meets_requirements_any(actor, job):
		return false
	var t_node: Node = job.target_node if job != null and "target_node" in job else null
	var growable := FarmingJobDef.growable_from(t_node)
	if growable == null:
		return false
	var sel_def := CropLibrary.get_crop(growable.get_selected_crop_id())
	if sel_def != null:
		for condition in sel_def.plant_conditions:
			if not condition.is_met(actor, t_node):
				return false
	return true
