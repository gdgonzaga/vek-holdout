extends FarmingJobDef
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


func _needs(growable: Growable) -> bool:
	return growable.get_crop_state() == Growable.CropState.EMPTY and growable.get_selected_crop_id() != ""


func _apply(growable: Growable, _actor: Node) -> void:
	var crop_id := growable.get_selected_crop_id()
	if crop_id != "":
		growable.plant(crop_id)
