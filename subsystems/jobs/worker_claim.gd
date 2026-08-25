class_name WorkerClaim
extends RefCounted
## Lightweight reservation token issued to a worker claiming fractional work units
## or item batches on a JobInstance.

## The parent JobInstance this claim belongs to
var job: JobInstance = null

## The unique ID of the colonist holding this claim
var colonist_id: String = ""

## Number of work units or items reserved by this worker
var claimed_units: int = 0

## Number of work units or items successfully completed by this worker
var completed_units: int = 0

## Target world-space position where work or deposit takes place
var target_pos: Vector3 = Vector3.ZERO

## Source world-space position (for hauling / item pickup)
var source_pos: Vector3 = Vector3.ZERO


func _init(
	p_job: JobInstance = null,
	p_colonist_id: String = "",
	p_claimed_units: int = 0,
	p_target_pos: Vector3 = Vector3.ZERO,
	p_source_pos: Vector3 = Vector3.ZERO
) -> void:
	job = p_job
	colonist_id = p_colonist_id
	claimed_units = p_claimed_units
	completed_units = 0
	target_pos = p_target_pos
	source_pos = p_source_pos


## Applies completed work units to this claim and forwards progress to the parent JobInstance.
func apply_work(units: int, _worker: Node = null) -> int:
	if job == null:
		return 0
	return job.complete_claim(colonist_id, units)


## Alias for apply_work to match BTActionPerformWork task interface.
func apply_work_units(units: int, worker: Node = null) -> int:
	return apply_work(units, worker)


## Abandons this claim, returning any uncompleted units back to the parent JobInstance.
func abandon() -> void:
	if job != null:
		job.abandon_claim(colonist_id)


## True if this claim's reserved units have been fully completed.
func is_finished() -> bool:
	return completed_units >= claimed_units


## Remaining unworked units in this claim.
func get_remaining_units() -> int:
	return maxi(0, claimed_units - completed_units)


## Animation to play during work, derived from JobDef if available.
func get_work_animation() -> StringName:
	if job != null and job.job_def != null and job.job_def.work_animation != &"":
		return job.job_def.work_animation
	return &"interact"


## Work duration in seconds, derived from JobDef if available.
func get_work_duration() -> float:
	if job != null and job.job_def != null and job.job_def.work_duration > 0.0:
		return job.job_def.work_duration
	return 1.2


## Tool tag required for this work, derived from JobDef if available.
func get_required_tool_tag() -> StringName:
	if job != null and job.job_def != null:
		return job.job_def.required_tool_tag
	return &""


## Which labor category this job belongs to.
func get_labor_id() -> StringName:
	if job != null:
		return job.labor_id
	return &""


## Item ID being transported if this is a haul job.
func get_item_id() -> StringName:
	if job != null:
		return job.item_id
	return &""


func _to_string() -> String:
	return "WorkerClaim(worker=%s, units=%d/%d, job=%s)" % [
		colonist_id,
		completed_units,
		claimed_units,
		job.id if job else "null"
	]
