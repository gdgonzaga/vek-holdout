extends Node
class_name JobBoard
## The colony's job registry + lifecycle (ARCH "Subsystem: Colonists").
##
## Owned by the Colony autoload as a child Node (Colony.job_board). Producers
## (Colony, listening to EventBus.blueprint_placed) add Jobs; consumers
## (ColonistAI) query get_best_job_for + claim. This class holds the registry and
## the atomic claim/fail/complete transitions — it does no pathfinding or work.
##
## Lifecycle (early-MVP):
##   add_job → (get_best_job_for → claim) → complete   (happy path)
##                                  └→ fail (×3 → auto-remove)   (skipped path)
##
## Signals: job_claimed / job_failed are local (board-internal + direct listeners).
## Only job_logged is relayed through EventBus (ARCH signals table), to the Job Log.

signal job_claimed(job_id: String, colonist_id: String)
signal job_failed(job_id: String, reason: String)

## After this many failures a job is auto-removed from the board (early-MVP
## policy, ARCH "Job failure Handling"). The blueprint stays placed if construction.
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


## All current jobs (claimed + unclaimed). For inspection/debug + future UI.
func get_jobs() -> Array[Job]:
	var out: Array[Job] = []
	out.assign(_jobs.values())
	return out


## Best available job for `colonist`, or null. Selection (ARCH "Colonist works a
## job"): among unclaimed jobs whose labor is enabled for the colonist
## (labor_priorities[labor_id] > 0), pick the highest-priority labor, then the
## nearest by proximity. Does NOT claim — call claim() to atomically acquire.
##
## Note: the documented L1 skill gate (skill_set.meets_requirement) is deferred
## until skills are wired into the work loop; ignored here.
func get_best_job_for(colonist: Colonist) -> Job:
	var best: Job = null
	var best_priority: int = -1
	var best_dist_sq: float = 0.0
	var from: Vector3 = colonist.global_position
	for job_id in _jobs:
		var job: Job = _jobs[job_id]
		if job.claimed_by != "":
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


## Atomically claim a job for `colonist_id`. Returns the Job on success, or null
## if it's missing or already claimed (race lost). Emits job_claimed on success.
func claim(job_id: String, colonist_id: String) -> Job:
	var job: Job = _jobs.get(job_id)
	if job == null or job.claimed_by != "":
		return null
	job.claimed_by = colonist_id
	job_claimed.emit(job_id, colonist_id)
	return job


## Release a claim back to the board (colonist gave up without failing, e.g.
## reassigned). No-op if the job isn't held by `colonist_id`.
func unclaim(job_id: String, colonist_id: String) -> void:
	var job: Job = _jobs.get(job_id)
	if job != null and job.claimed_by == colonist_id:
		job.claimed_by = ""


## Job finished successfully — drop it from the board.
func complete(job_id: String) -> void:
	_jobs.erase(job_id)


## Record a failure: increment the count, release the claim so another colonist
## (or a retry) can pick it up, emit job_failed locally, and relay a job_logged
## entry through EventBus. Auto-removes the job once it hits _MAX_FAILURES.
func fail(job_id: String, reason: String) -> void:
	var job: Job = _jobs.get(job_id)
	if job == null:
		return
	job.failure_count += 1
	job.claimed_by = ""
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
