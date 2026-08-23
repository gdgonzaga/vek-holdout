extends JobDef
class_name DigJobDef
## Mining/Digging labor (GDD §6.10, ARCH "Mining"): colonist travels to a designated
## terrain voxel coordinate and digs it out over a duration, then emits completion
## so the voxel terrain removes the solid block and clears visual designation.
##
## Single-colonist (max_assignees=1, the JobDef default). A job is available
## while its terrain cell is designated and not yet dug, and the cell still contains terrain.

const BASE_DIG_TIME: float = 2.0

var _completed_job_ids: Dictionary = {}


func get_next_leg(_actor: Node, job: Job) -> JobLeg:
	if _completed_job_ids.has(job.id) or not Colony.is_terrain_at(job.anchor_cell) or not Colony.has_walkable_neighbor(job.anchor_cell):
		return null
	var leg := JobLeg.new()
	leg.location = job.location
	leg.target_node = job.target_node
	return leg


func begin(actor: Node, _leg: JobLeg, _job: Job) -> float:
	var colonist := actor as Colonist
	if colonist != null and colonist.skill_set != null and labor_id != "":
		return BASE_DIG_TIME / colonist.skill_set.get_multiplier(labor_id)
	return BASE_DIG_TIME


func complete(_actor: Node, _leg: JobLeg, job: Job) -> void:
	_completed_job_ids[job.id] = true
	EventBus.dig_job_completed.emit(job.anchor_cell)


func is_available(job: Job) -> bool:
	return not _completed_job_ids.has(job.id) and Colony.is_terrain_at(job.anchor_cell) and Colony.has_walkable_neighbor(job.anchor_cell)


func should_close(job: Job) -> bool:
	if _completed_job_ids.has(job.id):
		return true
	if not Colony.is_terrain_at(job.anchor_cell):
		return true
	return false
