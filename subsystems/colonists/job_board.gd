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

# sequence_id (String) -> JobSequence.
var _sequences: Dictionary = {}

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


## Registers a multi-step JobSequence.
func add_sequence(seq: JobSequence) -> void:
	if seq.id == "":
		seq.id = Tools.generate_uuid()
	_sequences[seq.id] = seq


## Retrieves a registered JobSequence by ID, or null.
func get_sequence(sequence_id: String) -> JobSequence:
	return _sequences.get(sequence_id)


## Cancels a sequence and all its child jobs.
func cancel_sequence(sequence_id: String) -> void:
	var seq: JobSequence = _sequences.get(sequence_id)
	if seq != null:
		seq.cancel()
		for jid in seq.step_job_ids:
			remove_job(jid)
		_sequences.erase(sequence_id)


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
	var best_needs_fetch: bool = false
	var best_fetch_item_id: String = ""
	var from: Vector3 = colonist.global_position
	for job_id in _jobs:
		var job: Variant = _jobs[job_id]
		if "target_node" in job and job.target_node != null and (not is_instance_valid(job.target_node) or job.target_node.is_queued_for_deletion()):
			continue
		var is_avail := false
		if job.has_method("is_available_for"):
			is_avail = bool(job.is_available_for(colonist))
		else:
			is_avail = bool(job.is_available())
		if not is_avail:
			continue
		if is_job_blacklisted_for(job_id, colonist.colonist_id):
			continue
		if "target_colonist_id" in job and str(job.target_colonist_id) != "" and str(job.target_colonist_id) != colonist.colonist_id:
			continue
		var labor_id_str: String = ""
		if "labor_id" in job:
			labor_id_str = str(job.labor_id)
		elif "def" in job and job.def != null and "labor_id" in job.def:
			labor_id_str = str(job.def.labor_id)
		elif "job_def" in job and job.job_def != null and "labor_id" in job.job_def:
			labor_id_str = str(job.job_def.labor_id)
		var is_deploy: bool = labor_id_str == "deploy" or ("def" in job and job.def is DeployJobDef) or ("job_def" in job and job.job_def is DeployJobDef)
		var is_fetch_equip: bool = ("def" in job and job.def is FetchEquipmentJobDef) or ("job_def" in job and job.job_def is FetchEquipmentJobDef)
		var priority: int
		if is_deploy:
			# Deploy (stationing) always wins — highest urgency.
			priority = 1000
		elif is_fetch_equip:
			# Fetch-equipment beats all labor but yields to deploy.
			priority = FetchEquipmentJobDef.FETCH_EQUIP_PRIORITY
		else:
			priority = int(colonist.labor_priorities.get(labor_id_str, colonist.labor_priorities.get(StringName(labor_id_str), 0)))
		if priority <= 0 and not is_deploy and not is_fetch_equip:
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

		# 1. Tool Requirement Check: Evaluates whether the colonist holds the required tool or if one is in storage.
		var needs_fetch: bool = false
		var fetch_item_id: String = ""
		if def_obj != null and not is_fetch_equip and not is_deploy:
			var req_status: Dictionary = _evaluate_tool_requirement(colonist, def_obj)
			if not req_status["eligible"]:
				continue
			if req_status["needs_fetch"]:
				needs_fetch = true
				fetch_item_id = str(req_status["resolved_item_id"])

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
			best_needs_fetch = needs_fetch
			best_fetch_item_id = fetch_item_id
		elif priority == best_priority:
			if dist_sq < best_dist_sq:
				best = job
				best_dist_sq = dist_sq
				best_needs_fetch = needs_fetch
				best_fetch_item_id = fetch_item_id

	# 1. Fetch Equipment Intercept: If selected labor needs equipment from storage, post and claim targeted fetch job.
	if best != null and best_needs_fetch:
		return _create_and_post_intercept_fetch_job(colonist, best_fetch_item_id)

	# 2. Idle Equipment Audit: Reconcile desired loadout and equip carried gear before hygiene runs.
	if best == null:
		# Auxiliary Call: Reconciles equipment loadout slots and queries newly-posted fetch jobs.
		var fetch_job: FetchEquipmentJob = _audit_equipment_for_colonist(colonist)
		if fetch_job != null:
			return fetch_job

	# 3. Carried Item Hygiene: Route surplus carried items in pockets to capable storage crates.
	if best == null and colonist.hands_full():
		# Auxiliary Call: Creates a Store Carried Items haul job for loose pocket items.
		var store_job: Job = _try_create_store_carried_items_job(colonist)
		if store_job != null:
			return store_job

	return best


func _audit_equipment_for_colonist(colonist: Colonist) -> FetchEquipmentJob:
	## Auxiliary: Runs equipment audit for an idle colonist to equip carried desired gear
	##            or return an assigned FetchEquipmentJob posted by the audit pass.
	EquipmentAudit.run_audit(colonist, self)
	# 1. Fetch Job Resolution: Query for a designated fetch job generated by the audit pass.
	return _find_fetch_job_for(colonist)


func _try_create_store_carried_items_job(colonist: Colonist) -> Job:
	## Auxiliary: Evaluates carried items and generates a Store Carried Items haul job if an accepting crate exists.
	# 1. Active Hauling Check: Prevent assigning store jobs while a colonist is actively executing a haul run.
	if _is_colonist_hauling(colonist):
		return null

	# 2. Storage Search: Find a capable crate that can accept at least one carried item.
	var best_crate: Furniture = _find_best_crate_for_inventory(colonist)
	if best_crate == null:
		return null

	var haul_job := Job.from_def(HAULING_DEF)
	haul_job.title = "Store Carried Items"
	haul_job.target_node = best_crate
	haul_job.location = best_crate.global_position
	haul_job.max_assignees = 1
	return haul_job


func _is_colonist_hauling(colonist: Colonist) -> bool:
	## Auxiliary: Returns true if the colonist currently holds an active hauling assignment.
	if colonist.current_job != null and is_instance_valid(colonist.current_job):
		return true
	for j: Variant in _jobs.values():
		if j is Job and j.def is HaulingJobDef:
			if "_assigned_colonists" in j:
				var assigned: Array = j._assigned_colonists
				if assigned.has(colonist) or assigned.has(str(colonist)):
					return true
		elif j != null and is_instance_valid(j) and j.has_method("is_claimed_by"):
			if j.is_claimed_by(colonist):
				return true
	return false


func _find_best_crate_for_inventory(colonist: Colonist) -> Furniture:
	## Auxiliary: Queries the colony storage registry for the best crate that can accept any carried item.
	if colonist.inventory == null or colonist.inventory.items.is_empty():
		return null
	var colony: Node = colonist.get_node_or_null("/root/Colony")
	if colony == null or not ("storage_registry" in colony) or colony.storage_registry == null:
		return null

	for item_id: Variant in colonist.inventory.items.keys():
		var id_str := str(item_id)
		# 1. Desired Loadout Guard: Colonists keep their configured loadout gear in pockets.
		if _is_item_desired_by_colonist(colonist, id_str):
			continue
		var count: int = colonist.inventory.get_item_count(id_str)
		if count <= 0:
			continue
		var crate: Furniture = colony.storage_registry.find_storage_for(id_str, colonist.global_position, count)
		if crate != null:
			return crate
	return null


func _is_item_desired_by_colonist(colonist: Colonist, item_id: String) -> bool:
	## Auxiliary: Returns true if item_id matches any desired slot target for this colonist.
	if colonist == null or colonist.equipment == null:
		return false
	var desired_dict: Dictionary = colonist.equipment.get_all_desired_items()
	for slot_id: String in desired_dict:
		if desired_dict[slot_id] == item_id:
			return true
	return false


## Returns the first available FetchEquipmentJob on the board designated for
## this colonist, or null. Used immediately after the idle-fallback audit run.
func _find_fetch_job_for(colonist: Colonist) -> FetchEquipmentJob:
	for job: Variant in _jobs.values():
		if not (job is FetchEquipmentJob):
			continue
		var fj: FetchEquipmentJob = job as FetchEquipmentJob
		if fj.target_colonist_id != colonist.colonist_id:
			continue
		var is_avail := false
		if fj.has_method("is_available_for"):
			is_avail = bool(fj.is_available_for(colonist))
		elif fj.has_method("is_available"):
			is_avail = bool(fj.is_available())
		if is_avail:
			return fj
	return null


func _evaluate_tool_requirement(colonist: Colonist, def_obj: Resource) -> Dictionary:
	## Auxiliary: Checks if colonist satisfies tool requirements or if an item in storage can be fetched.
	var req_id: String = ""
	var req_tags: Array[StringName] = []
	if "required_equipped" in def_obj and str(def_obj.required_equipped) != "":
		req_id = str(def_obj.required_equipped)
	if def_obj.has_method("get_effective_required_tags"):
		req_tags = def_obj.get_effective_required_tags()
	elif "required_equipped_tags" in def_obj and def_obj.required_equipped_tags is Array:
		for t: Variant in def_obj.required_equipped_tags:
			if t is StringName or t is String:
				req_tags.append(StringName(str(t)))

	# No tool requirements defined for this job.
	if req_id == "" and req_tags.is_empty():
		return {"eligible": true, "needs_fetch": false, "resolved_item_id": ""}

	# 1. Held Possession Check: Checks if colonist already has matching tool equipped or in inventory.
	if _colonist_has_required_tool(colonist, req_id, req_tags):
		return {"eligible": true, "needs_fetch": false, "resolved_item_id": ""}

	# 2. Storage Search: Queries colony crates for an available unreserved tool.
	var resolved_id: String = _find_available_tool_in_storage(colonist, req_id, req_tags)
	if resolved_id != "":
		return {"eligible": true, "needs_fetch": true, "resolved_item_id": resolved_id}

	return {"eligible": false, "needs_fetch": false, "resolved_item_id": ""}


func _colonist_has_required_tool(colonist: Colonist, req_id: String, req_tags: Array[StringName]) -> bool:
	## Auxiliary: True if colonist currently has required equipment equipped or in carry bag.
	if colonist == null:
		return false
	if colonist.equipment != null and colonist.equipment.has_required_equipment(req_id, req_tags):
		return true
	return _colonist_carries_matching_tool(colonist, req_id, req_tags)


func _colonist_carries_matching_tool(colonist: Colonist, req_id: String, req_tags: Array[StringName]) -> bool:
	## Auxiliary: True if colonist carry inventory holds an item matching req_id or tags.
	if colonist == null or colonist.inventory == null:
		return false
	if req_id != "" and colonist.inventory.has_item(req_id, 1):
		return true
	for tag: StringName in req_tags:
		if tag != &"" and colonist.inventory.has_item_tag(String(tag)):
			return true
	return false


func _find_available_tool_in_storage(colonist: Colonist, req_id: String, req_tags: Array[StringName]) -> String:
	## Auxiliary: Searches storage for matching item ID, ensuring unreserved count > 0.
	var colony_node: Node = colonist.get_node_or_null("/root/Colony")
	if colony_node == null or not ("storage_registry" in colony_node) or colony_node.storage_registry == null:
		return ""
	var reg: StorageRegistry = colony_node.storage_registry
	var candidate_id: String = reg.find_closest_item_matching(req_id, req_tags, colonist.global_position)
	if candidate_id == "":
		return ""

	var stock_count: int = reg.colony_stock(candidate_id)
	var pending_fetches: int = _count_pending_fetches_for(candidate_id)
	if stock_count - pending_fetches <= 0:
		return ""
	return candidate_id


func _count_pending_fetches_for(item_id: String) -> int:
	## Auxiliary: Counts active FetchEquipmentJobs targeting this item ID.
	var count: int = 0
	for job: Variant in _jobs.values():
		if job is FetchEquipmentJob:
			var fj := job as FetchEquipmentJob
			if fj.target_item_id == item_id:
				count += 1
	return count


func _create_and_post_intercept_fetch_job(colonist: Colonist, item_id: String) -> FetchEquipmentJob:
	## Auxiliary: Creates, registers, and returns a targeted FetchEquipmentJob for the colonist.
	var fetch_def: FetchEquipmentJobDef = preload("res://data/jobs/fetch_equipment.tres")
	var fetch_job: FetchEquipmentJob = FetchEquipmentJobDef.create_job(
		colonist, Equipment.SLOT_MAIN_HAND, item_id, fetch_def, true
	)
	add_job(fetch_job)
	return fetch_job


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
		var is_dead := false
		if "target_node" in job and job.target_node != null and (not is_instance_valid(job.target_node) or job.target_node.is_queued_for_deletion()):
			is_dead = true
		elif job.has_method("should_close"):
			if job.should_close():
				is_dead = true
		elif "is_completed" in job and "is_cancelled" in job:
			if job.is_completed or job.is_cancelled:
				is_dead = true

		if is_dead:
			dead.append(job_id)
			# 1. Sequence Advancement: If completed step was part of an active sequence, advance it.
			_advance_owning_sequence(job_id, job)

	for job_id in dead:
		_jobs.erase(job_id)


func _advance_owning_sequence(job_id: String, job: Variant) -> void:
	## Auxiliary: Advances sequence step if the pruned job was an active step.
	var seq_id: String = str(job.sequence_id) if "sequence_id" in job else ""
	if seq_id == "":
		return
	var seq: JobSequence = _sequences.get(seq_id)
	if seq != null and seq.is_step_active(job_id):
		seq.advance_step()
		if seq.status == JobSequence.Status.COMPLETED:
			_sequences.erase(seq_id)


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


## Clears all registered jobs, sequences, and blacklists.
func clear() -> void:
	_jobs.clear()
	_sequences.clear()
	_colonist_blacklists.clear()


# --- SaveSystem contract -----------------------------------------------------

func serialize() -> Dictionary:
	var seq_data: Array[Dictionary] = []
	for seq: JobSequence in _sequences.values():
		if is_instance_valid(seq):
			seq_data.append(seq.serialize())
	return {
		"sequences": seq_data,
	}


func deserialize(data: Dictionary) -> void:
	_sequences.clear()
	for s_entry: Dictionary in data.get("sequences", []):
		var seq := JobSequence.new()
		seq.deserialize(s_entry)
		if seq.id != "":
			_sequences[seq.id] = seq
