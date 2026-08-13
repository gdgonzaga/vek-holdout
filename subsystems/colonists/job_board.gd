extends Node
class_name JobBoard
## The colony's job registry + lifecycle (ARCH "Subsystem: Colonists").
##
## Owned by the Colony autoload as a child Node (Colony.job_board). Producers
## (Colony, listening to EventBus.blueprint_placed) add Jobs; consumers
## (ColonistAI) query get_best_job_for, then assign via Job.try_assign directly.
## This class holds the registry and selection; it does no pathfinding, work, or
## assignment bookkeeping (that lives on the Job + JobDef — multi-assign).
##
## Lifecycle (multi-assign):
##   add_job → (get_best_job_for → Job.try_assign → … → Job.unassign) → remove_job
##   └→ _prune_dead_jobs sweeps !is_available && unassigned jobs during selection
##
## Signals: job_failed is local (board-internal + direct listeners). Only
## job_logged is relayed through EventBus (ARCH signals table), to the Job Log.

signal job_failed(job_id: String, reason: String)

## After this many failures a job is auto-removed from the board (early-MVP
## policy, ARCH "Job failure handling"). The blueprint stays placed if construction.
const _MAX_FAILURES := 3

# job.id (String) -> Job.
var _jobs: Dictionary = {}


func add_job(job: Job) -> void:
	# Assign an id if the creator didn't, so two id-less jobs can't collide.
	if job.id == "":
		job.id = Tools.generate_uuid()
	_jobs[job.id] = job


func remove_job(job_id: String) -> void:
	_jobs.erase(job_id)


func get_job(job_id: String) -> Job:
	return _jobs.get(job_id)


func has_jobs() -> bool:
	return not _jobs.is_empty()


## All current jobs. For inspection/debug + future UI.
func get_jobs() -> Array[Job]:
	var out: Array[Job] = []
	out.assign(_jobs.values())
	return out


## Best available job for `colonist`, or null. Selection (ARCH "Colonist works a
## job"): among available jobs whose labor is enabled for the colonist
## (labor_priorities[labor_id] > 0), pick the highest-priority labor, then the
## nearest by proximity. Does NOT assign — call Job.try_assign to join.
##
## First prunes dead jobs (no assignees AND not accepting more) so a no-source
## haul job, a satisfied-but-drained one, or a cancelled one can't linger and
## starve selection.
##
## Note: the documented L1 skill gate (skill_set.meets_requirement) is deferred
## until skills are wired into the work loop; ignored here.
func get_best_job_for(colonist: Colonist) -> Job:
	_prune_dead_jobs()
	var best: Job = null
	var best_priority: int = -1
	var best_dist_sq: float = 0.0
	var from: Vector3 = colonist.global_position
	for job_id in _jobs:
		var job: Job = _jobs[job_id]
		if not job.is_available():
			continue
		var priority: int = int(colonist.labor_priorities.get(job.labor_id, 0))
		if priority <= 0:
			continue
		if priority > best_priority:
			best = job
			best_priority = priority
			best_dist_sq = from.distance_squared_to(job.location)
		elif priority == best_priority:
			var d: float = from.distance_squared_to(job.location)
			if d < best_dist_sq:
				best = job
				best_dist_sq = d
	return best


## Drop jobs that can no longer be worked and have no assignees to drain them
## (a haul job whose source dried up, one whose target was satisfied/cancelled,
## etc.). Called at the top of get_best_job_for. Iterates a snapshot since it
## mutates _jobs.
func _prune_dead_jobs() -> void:
	if _jobs.is_empty():
		return
	var dead: Array[String] = []
	for job_id in _jobs:
		var job: Job = _jobs[job_id]
		if job._assigned_colonists.is_empty() and not job.is_available():
			dead.append(job_id)
	for job_id in dead:
		_jobs.erase(job_id)


## Record a failure: increment the count, release any assignees, emit job_failed
## locally, and relay a job_logged entry through EventBus. Auto-removes the job
## once it hits _MAX_FAILURES. (Currently no caller wires the failure path into
## the leg loop — the dead-job prune handles removal for haul's no-source case.
## Kept as the documented failure-handling seam.)
func fail(job_id: String, reason: String) -> void:
	var job: Job = _jobs.get(job_id)
	if job == null:
		return
	job.failure_count += 1
	job.clear_assigned()
	job_failed.emit(job_id, reason)
	EventBus.job_logged.emit({
		"job_id": job_id,
		"title": job.title,
		"labor_id": job.labor_id,
		"reason": reason,
		"failure_count": job.failure_count,
	})
	if job.failure_count >= _MAX_FAILURES:
		_jobs.erase(job_id)
