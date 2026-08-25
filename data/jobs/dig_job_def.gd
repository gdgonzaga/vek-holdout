extends JobDef
class_name DigJobDef
## Mining/Digging labor (GDD §6.10, ARCH "Mining"): work a designated terrain
## voxel for dig.tres work_duration, then emit completion so the voxel terrain
## removes the solid block and clears the designation. Single-colonist.
##
## Claimable while the cell still holds terrain AND has a walkable neighbour
## stand cell — buried voxels wait on the board (unclaimable, not dead) until
## excavation exposes them.


func complete(_actor: Node, job: Variant) -> void:
	if "anchor_cell" in job:
		EventBus.dig_job_completed.emit(job.anchor_cell)
	_finish(_actor, job)


func is_available(job: Variant) -> bool:
	if not Colony.is_terrain_at(job.anchor_cell):
		return false
	return Colony.has_walkable_neighbor(job.anchor_cell)


## Leaves the board when the terrain is gone (dug by hand, another colonist,
## or world edit). A merely-buried job stays registered — see is_available.
func should_close(job: Variant) -> bool:
	return not Colony.is_terrain_at(job.anchor_cell)
