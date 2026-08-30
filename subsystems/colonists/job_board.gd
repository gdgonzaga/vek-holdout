extends Node
class_name JobBoard

const HAULING_DEF := preload("res://data/jobs/hauling.tres")
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
##   └→ _prune_dead_jobs sweeps should_close() jobs during selection
##      (drought-persistent haul jobs survive — see JobDef.should_close)
##
## Signals: job_failed is local (board-internal + direct listeners). Only
## job_logged is relayed through EventBus (ARCH signals table), to the Job Log.

signal job_failed(job_id: String, reason: String)

# job.id (String) -> Job.
var _jobs: Dictionary = {}

# job_id (String) -> Dictionary of { colonist_id (String): expiry_msec (int) }
var _colonist_blacklists: Dictionary = {}


func _ready() -> void:
	EventBus.dig_job_completed.connect(_on_world_changed.unbind(1))
	EventBus.furniture_placed.connect(_on_world_changed.unbind(2))
	EventBus.furniture_removed.connect(_on_world_changed.unbind(2))
	EventBus.blueprint_placed.connect(_on_world_changed.unbind(3))
	EventBus.blueprint_removed.connect(_on_world_changed.unbind(2))


func _on_world_changed() -> void:
	var now := Time.get_ticks_msec()
	for job_id in _jobs:
		var job: Variant = _jobs[job_id]
		if job.sleep_until_msec > now:
			job.sleep_until_msec = 0


func add_job(job: RefCounted) -> void:
	# Assign an id if the creator didn't, so two id-less jobs can't collide.
	if job.id == "":
		job.id = Tools.generate_uuid()
	_jobs[job.id] = job


func remove_job(job_id: String) -> void:
	_jobs.erase(job_id)


func get_job(job_id: String) -> RefCounted:
	return _jobs.get(job_id)


func has_jobs() -> bool:
	return not _jobs.is_empty()


## All current jobs. For inspection/debug + future UI.
func get_jobs() -> Array[Job]:
	var out: Array[Job] = []
	for job in _jobs.values():
		if job is Job:
			out.append(job as Job)
	return out


## All registered jobs (including fractional JobInstance).
func get_all_jobs() -> Array:
	var out: Array = []
	out.assign(_jobs.values())
	return out


## Best available job for `colonist`, or null. Selection (ARCH "Colonist works a
## job"): among available jobs whose labor is enabled for the colonist
## (labor_priorities[labor_id] > 0) and whose def requirements the colonist
## meets (JobDef.meets_requirements — skill/item conditions, evaluated fresh
## every poll), pick the highest-priority labor, then the nearest by proximity.
## Does NOT assign — call Job.try_assign to join (it re-checks requirements as
## the authoritative gate).
##
## First prunes dead jobs (no assignees AND the def says close — satisfied,
## cancelled, or invalid) so they can't linger and starve selection. A
## source-drought haul job is NOT dead: selection skips it via is_available
## while JobDef.should_close keeps it registered, and a restocked crate makes
## it claimable again on a later poll.
func get_best_job_for(colonist: Colonist) -> RefCounted:
	_prune_dead_jobs()
	var best: RefCounted = null
	var best_priority: int = -1
	var best_dist_sq: float = 0.0
	var from: Vector3 = colonist.global_position
	for job_id in _jobs:
		var job: Variant = _jobs[job_id]
		if "target_node" in job and job.target_node != null and (not is_instance_valid(job.target_node) or job.target_node.is_queued_for_deletion()):
			continue
		if not job.is_available():
			# Bypass: hauling jobs for sinks where this colonist already
			# carries the needed materials are still claimable — the source
			# check fails because materials moved from the crate to the
			# colonist's pocket during the FETCH leg.
			var bypass := false
			var _def: Resource = null
			if "def" in job:
				_def = job.def
			elif "job_def" in job:
				_def = job.job_def
			if _def is HaulingJobDef:
				var _sink = _def._sink_of(job)
				if _sink != null and _def._carries_needed_material(colonist, _sink):
					bypass = true
			if not bypass:
				continue
		if is_job_blacklisted_for(job_id, colonist.colonist_id):
			continue
		var labor_id_str: String = ""
		if "labor_id" in job:
			labor_id_str = str(job.labor_id)
		elif "def" in job and job.def != null and "labor_id" in job.def:
			labor_id_str = str(job.def.labor_id)
		elif "job_def" in job and job.job_def != null and "labor_id" in job.job_def:
			labor_id_str = str(job.job_def.labor_id)
		var priority: int = int(colonist.labor_priorities.get(labor_id_str, colonist.labor_priorities.get(StringName(labor_id_str), 0)))
		if priority <= 0:
			continue
		var def_obj: Resource = null
		if "def" in job:
			def_obj = job.def
		elif "job_def" in job:
			def_obj = job.job_def
		if def_obj != null:
			if def_obj.has_method("meets_requirements_any"):
				if not def_obj.meets_requirements_any(colonist, job):
					continue
			elif job is Job and def_obj.has_method("meets_requirements"):
				if not def_obj.meets_requirements(colonist, job):
					continue
		# If colonist is already carrying materials for this haul job, give it continuation bonus
		if def_obj is HaulingJobDef and def_obj.has_method("_carries_item"):
			var wi = def_obj._world_item_of(job)
			if wi != null and def_obj._carries_item(colonist, wi.item_id):
				priority += 100
			var sink = def_obj._sink_of(job)
			if sink != null and def_obj._carries_needed_material(colonist, sink):
				priority += 100

		var loc: Vector3 = Vector3.ZERO
		if "world_position" in job:
			loc = job.world_position
		elif "location" in job:
			loc = job.location
		var dist_sq: float = from.distance_squared_to(loc)
		if priority > best_priority:
			best = job
			best_priority = priority
			best_dist_sq = dist_sq
		elif priority == best_priority:
			if dist_sq < best_dist_sq:
				best = job
				best_dist_sq = dist_sq

	# If no job was selected, but colonist is carrying non-tool items AND is
	# not currently assigned to any haul job (which would mean a FETCH/DELIVER
	# cycle is in progress), route to nearest crate to dump surplus.
	if best == null and colonist.hands_full():
		# Don't generate a store job if the colonist already has an active
		# hauling assignment on the board (they're mid-cycle, e.g. just
		# fetched materials for a blueprint and walking to deliver them).
		var already_hauling := false
		if colonist.current_job != null and is_instance_valid(colonist.current_job):
			already_hauling = true
		if not already_hauling:
			for j in _jobs.values():
				if j is Job and j.def is HaulingJobDef:
					if "_assigned_colonists" in j:
						var assigned: Array = j._assigned_colonists
						if assigned.has(colonist) or assigned.has(str(colonist)):
							already_hauling = true
							break
		if not already_hauling:
			var has_non_tool := false
			if colonist.inventory != null:
				for item_id in colonist.inventory.items.keys():
					var def := ItemDB.get_def(str(item_id)) if ItemDB != null else null
					if def == null or not def.tags.has("tool"):
						if colonist.inventory.get_item_count(str(item_id)) > 0:
							has_non_tool = true
							break
			if has_non_tool:
				var colony: Node = colonist.get_node_or_null("/root/Colony")
				if colony != null and "storage_registry" in colony and colony.storage_registry != null:
					var crate = colony.storage_registry.nearest_crate(colonist.global_position)
					if crate != null:
						var haul_job := Job.from_def(HAULING_DEF)
						haul_job.title = "Store Carried Items"
						haul_job.target_node = crate
						haul_job.location = crate.global_position
						haul_job.max_assignees = 1
						return haul_job

	return best


## Drop dead jobs that have no assignees left to drain them (a haul job whose
## target was satisfied, cancelled, or freed — anything JobDef.should_close
## reports). Called at the top of get_best_job_for. Iterates a snapshot since
## it mutates _jobs. Source-drought haul jobs survive here by design: their def
## keeps them registered (unclaimable, not dead) until restock or removal.
func _prune_dead_jobs() -> void:
	if _jobs.is_empty():
		return
	var dead: Array[String] = []
	for job_id in _jobs:
		var job: Variant = _jobs[job_id]
		if "target_node" in job and job.target_node != null and (not is_instance_valid(job.target_node) or job.target_node.is_queued_for_deletion()):
			dead.append(job_id)
		elif job.has_method("should_close"):
			if job.should_close():
				dead.append(job_id)
		elif "is_completed" in job and "is_cancelled" in job:
			if job.is_completed or job.is_cancelled:
				dead.append(job_id)
	for job_id in dead:
		_jobs.erase(job_id)


## Record a failure: increment the count, release any assignees, emit job_failed
## locally, and relay a job_logged entry through EventBus. Applies an exponential
## backoff cooldown (sleep_until_msec) instead of auto-removing the job. Called
## by ColonistAI on aborts (freed leg target, unreachable leg).
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
	var delay_ms := 0
	if job.failure_count <= 3:
		delay_ms = 0
	elif job.failure_count < 6:
		delay_ms = 10_000
	elif job.failure_count < 10:
		delay_ms = 60_000
	else:
		delay_ms = 300_000

	if delay_ms > 0:
		job.sleep_until_msec = Time.get_ticks_msec() + delay_ms


## Blacklists a job temporarily for a specific colonist (e.g. after unreachable pathfinding).
func blacklist_job_for(job_id: String, colonist_id: String, duration_sec: float = 10.0) -> void:
	if job_id == "" or colonist_id == "":
		return
	var expiry: int = Time.get_ticks_msec() + int(duration_sec * 1000.0)
	if not _colonist_blacklists.has(job_id):
		_colonist_blacklists[job_id] = {}
	_colonist_blacklists[job_id][colonist_id] = expiry


## True if this job is currently on unreachable cooldown for this colonist.
func is_job_blacklisted_for(job_id: String, colonist_id: String) -> bool:
	if not _colonist_blacklists.has(job_id):
		return false
	var expiry: int = int(_colonist_blacklists[job_id].get(colonist_id, 0))
	if Time.get_ticks_msec() < expiry:
		return true
	_colonist_blacklists[job_id].erase(colonist_id)
	if _colonist_blacklists[job_id].is_empty():
		_colonist_blacklists.erase(job_id)
	return false


## Clears all colonist blacklists (e.g. on map load or test reset).
func clear_blacklists() -> void:
	_colonist_blacklists.clear()


## Clears all registered jobs and blacklists.
func clear() -> void:
	_jobs.clear()
	_colonist_blacklists.clear()
