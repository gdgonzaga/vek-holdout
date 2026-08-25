extends JobDef
class_name DigJobDef
## Mining/Digging labor (GDD §6.10, ARCH "Mining"): declarative job template for
## voxel digging work executed by LimboAI behavior trees.

const BASE_DIG_TIME: float = 2.0


func complete(actor: Node, _unused: Variant, job: Variant) -> void:
	if "anchor_cell" in job:
		EventBus.dig_job_completed.emit(job.anchor_cell)
		
	var colony = actor.get_node_or_null("/root/Colony")
	if colony and "job_board" in colony:
		colony.job_board.remove_job(job.id)
