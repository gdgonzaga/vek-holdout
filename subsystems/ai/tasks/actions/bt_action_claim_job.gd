## Subsystem: AI Tasks
## Claims the best available job or work units from Colony.job_board and stores it in the Blackboard.
@tool
class_name BTActionClaimJob
extends BTAction

## Blackboard variable where the active job instance is stored
@export var job_var: StringName = &"active_job"

## Blackboard variable where the worker claim is stored (if fractional)
@export var claim_var: StringName = &"active_claim"

## Blackboard variable where the target world position is written
@export var target_pos_var: StringName = &"target_pos"

## How often an already-held job's is_available_for() is allowed to re-scan
## (crates, storage sources, reservations) instead of every single 60Hz tick.
## is_available_for() is a live scan that other colonists' concurrent claims
## are also mutating; checking it every tick meant a single-frame flicker
## (contested crate capacity, a rival hauler mid-delivery) unclaimed and
## reclaimed the same job every frame, visible as the colonist repeatedly
## turning back toward the same spot.
const AVAILABILITY_RECHECK_INTERVAL_MSEC: int = 500

var _last_checked_job: Variant = null
var _next_availability_check_msec: int = 0


func _generate_name() -> String:
	return "Claim Job  -> %s, %s" % [
		LimboUtility.decorate_var(job_var),
		LimboUtility.decorate_var(claim_var)
	]


func _tick(_delta: float) -> Status:
	if not agent or not blackboard:
		return FAILURE
		
	var colonist: Colonist = agent as Colonist if agent is Colonist else null
	
	# Check if we already hold a valid active claim or job. Spent ones (claim
	# finished, parent job completed/cancelled/freed) are dropped so a fresh
	# claim is made next — holding them made this task return SUCCESS forever
	# for work that was already done.
	if blackboard.has_var(claim_var):
		var existing_claim: Variant = blackboard.get_var(claim_var)
		if existing_claim != null and is_instance_valid(existing_claim):
			if _claim_is_spent(existing_claim):
				ColonistLogger.log_msg(colonist, &"JOB", "Claim spent, clearing active_claim and job")
				blackboard.erase_var(claim_var)
				blackboard.erase_var(job_var)
				if agent is Colonist:
					(agent as Colonist).current_job = null
			else:
				var active_job_inst: Variant = blackboard.get_var(job_var) if blackboard.has_var(job_var) else null
				# 1. Target Synchronization: Updates target_pos if multi-leg job changes site.
				_update_active_job_target_pos(colonist, active_job_inst)
				_cleanup_incompatible_held_items(colonist, active_job_inst)
				return SUCCESS

	if blackboard.has_var(job_var):
		var existing_job: Variant = blackboard.get_var(job_var)
		if existing_job != null and is_instance_valid(existing_job):
			var is_dead: bool = _job_is_dead(existing_job)
			if not is_dead and colonist != null and existing_job.has_method("is_available_for"):
				# 2. Recheck Throttling: Skip the (expensive, scan-based)
				# availability re-check unless the debounce window elapsed —
				# see AVAILABILITY_RECHECK_INTERVAL_MSEC above.
				if _should_recheck_availability(existing_job) and not existing_job.is_available_for(colonist):
					# 3. Unavailability Diagnostics: Explain exactly which gate
					# tripped, so rapid claim/drop churn on the same site can
					# be traced to its root cause instead of just its symptom.
					_log_job_unavailable(colonist, existing_job)
					ColonistLogger.log_msg(colonist, &"JOB", "Job no longer available for colonist")
					is_dead = true
					if existing_job.has_method("unassign"):
						existing_job.unassign(colonist)
			if is_dead:
				ColonistLogger.log_msg(colonist, &"JOB", "Job dead, clearing active_job")
				blackboard.erase_var(job_var)
				if agent is Colonist:
					(agent as Colonist).current_job = null
			else:
				# 1. Target Synchronization: Updates target_pos if multi-leg job changes site.
				_update_active_job_target_pos(colonist, existing_job)
				_cleanup_incompatible_held_items(colonist, existing_job)
				return SUCCESS

	var colony: Node = agent.get_node_or_null("/root/Colony")
	if colony == null or not "job_board" in colony or colony.job_board == null:
		return FAILURE
		
	var job_board = colony.job_board
	if not (agent is Colonist):
		return FAILURE
		
	var best_job = job_board.get_best_job_for(colonist)
	if best_job == null:
		ColonistLogger.log_job_claim(colonist, &"REJECT", "", "", "No available eligible jobs on board")
		return FAILURE
		
	# Fractional JobInstance support
	if best_job.has_method("try_claim_units"):
		var claim = best_job.try_claim_units(colonist)
		if claim == null:
			ColonistLogger.log_job_claim(colonist, &"REJECT", str(best_job.id) if "id" in best_job else "", str(best_job.labor_id) if "labor_id" in best_job else "", "try_claim_units returned null")
			return FAILURE
		blackboard.set_var(claim_var, claim)
		blackboard.set_var(job_var, best_job)
		colonist.current_job = best_job
		if "world_position" in best_job:
			blackboard.set_var(target_pos_var, best_job.world_position)
		elif "target_pos" in claim:
			blackboard.set_var(target_pos_var, claim.target_pos)
		elif "target_position" in best_job:
			blackboard.set_var(target_pos_var, best_job.target_position)
			
		var def_obj: Resource = best_job.job_def if "job_def" in best_job else null
		_sync_tool_requirements_to_blackboard(def_obj)
		_cleanup_incompatible_held_items(colonist, best_job)
		ColonistLogger.log_job_claim(colonist, &"CLAIMED", str(best_job.id) if "id" in best_job else "", str(best_job.labor_id) if "labor_id" in best_job else "", "Fractional claim")
		return SUCCESS
		
	# Legacy Job support
	if best_job.has_method("try_assign"):
		if not best_job.try_assign(colonist):
			ColonistLogger.log_job_claim(colonist, &"REJECT", str(best_job.id) if "id" in best_job else "", str(best_job.labor_id) if "labor_id" in best_job else "", "try_assign returned false")
			return FAILURE
		blackboard.set_var(job_var, best_job)
		colonist.current_job = best_job
		# Multi-site labors (hauling: crate vs sink by carry state) pick this
		# cycle's walk target from the def; single-site defs return null and
		# fall through to the anchor/target placement.
		var site: Variant = best_job.def.work_site(colonist, best_job) if best_job.def != null else null
		if site is Vector3:
			blackboard.set_var(target_pos_var, site)
		elif best_job.anchor_cell != Vector3i.MAX:
			blackboard.set_var(target_pos_var, Vector3(best_job.anchor_cell) + Vector3(0.5, 0.5, 0.5))
		elif best_job.target_node != null and is_instance_valid(best_job.target_node):
			blackboard.set_var(target_pos_var, (best_job.target_node as Node3D).global_position if best_job.target_node is Node3D else Vector3.ZERO)
		
		# 1. Tool Requirement Synchronization: Populates blackboard with tool ID and tags.
		_sync_tool_requirements_to_blackboard(best_job.def if "def" in best_job else null)
		_cleanup_incompatible_held_items(colonist, best_job)
		ColonistLogger.log_job_claim(colonist, &"CLAIMED", str(best_job.id) if "id" in best_job else "", str(best_job.labor_id) if "labor_id" in best_job else "", "Legacy assignment")
		return SUCCESS
		
	return FAILURE


func _cleanup_incompatible_held_items(colonist: Colonist, job: Variant = null) -> void:
	if colonist == null:
		return

	# Equipment audit: reconcile desired loadout slots before item hygiene so the
	# colonist equips correct gear and unequips wrong gear on every claim boundary.
	var colony_node: Node = colonist.get_node_or_null("/root/Colony")
	if colony_node != null and "job_board" in colony_node and colony_node.job_board != null:
		EquipmentAudit.run_audit(colonist, colony_node.job_board)

	if colonist.inventory == null or not colonist.hands_full():
		return

	# 1. Tool check
	var req_tag: StringName = &""
	if blackboard.has_var(&"required_tool_tag"):
		req_tag = blackboard.get_var(&"required_tool_tag")
	var req_tags: Array[StringName] = []
	if blackboard.has_var(&"required_equipped_tags"):
		var raw: Variant = blackboard.get_var(&"required_equipped_tags")
		if raw is Array:
			for t: Variant in raw:
				req_tags.append(StringName(str(t)))
	if req_tag != &"" and not req_tags.has(req_tag):
		req_tags.append(req_tag)

	if not req_tags.is_empty():
		var has_matching: bool = false
		if colonist.equipment != null and colonist.equipment.has_required_equipment("", req_tags):
			has_matching = true
		else:
			for t: StringName in req_tags:
				if colonist.inventory.has_item_tag(String(t)):
					has_matching = true
					break
		if not has_matching:
			colonist.drop_held_item()

	# 2. Inventory hygiene for non-tool items
	if job == null:
		return

	if "title" in job and job.title == "Store Carried Items":
		return

	var needed_ids: Array[String] = []
	var def: Resource = AIUtils.resolve_job_def(job)

	if def is HaulingJobDef:
		if def._storage_crate_of(job) != null:
			return
		var sink = def._sink_of(job)
		if sink != null:
			for nid in sink.needed_item_ids():
				needed_ids.append(str(nid))
		var wi = def._world_item_of(job)
		if wi != null:
			needed_ids.append(str(wi.item_id))

	AIUtils.drop_unneeded_items(colonist, needed_ids)


## True when a held claim can no longer be worked: its units are finished, or
## its parent job is freed/completed/cancelled.
func _claim_is_spent(claim: Variant) -> bool:
	if claim.has_method("is_finished") and bool(claim.is_finished()):
		return true
	if "job" in claim:
		var claim_job: Variant = claim.job
		if claim_job == null or not is_instance_valid(claim_job):
			return true
		return _job_is_dead(claim_job)
	return false


## True when a job object is completed or cancelled (missing flags = alive).
func _job_is_dead(job: Variant) -> bool:
	if "is_completed" in job and bool(job.is_completed):
		return true
	if "is_cancelled" in job and bool(job.is_cancelled):
		return true
	return false


func _should_recheck_availability(job: Variant) -> bool:
	## Auxiliary: Throttles is_available_for() to once per
	## AVAILABILITY_RECHECK_INTERVAL_MSEC instead of every tick. A newly-seen
	## job (just claimed, or this task instance's first tick on it) always
	## checks immediately — only a job already held across ticks gets debounced.
	var now := Time.get_ticks_msec()
	if job != _last_checked_job:
		_last_checked_job = job
		_next_availability_check_msec = now + AVAILABILITY_RECHECK_INTERVAL_MSEC
		return true
	if now < _next_availability_check_msec:
		return false
	_next_availability_check_msec = now + AVAILABILITY_RECHECK_INTERVAL_MSEC
	return true


func _log_job_unavailable(colonist: Colonist, job: Variant) -> void:
	## Auxiliary: Logs why an already-held job just failed its per-tick
	## availability re-check, so rapid claim/drop churn on the same site can be
	## traced to the specific gate that tripped (crate full, reserved, freed,
	## no source, etc) instead of just the "no longer available" symptom.
	if not ColonistLogger.is_enabled():
		return
	var reason := "unknown (def has no diagnostic)"
	var def_obj: Resource = AIUtils.resolve_job_def(job)
	if def_obj != null and def_obj.has_method("describe_unavailable_reason"):
		reason = str(def_obj.call("describe_unavailable_reason", job, colonist))
	ColonistLogger.log_msg(colonist, &"JOB", "Job unavailable diagnostic | %s" % reason)


func _sync_tool_requirements_to_blackboard(def_obj: Resource) -> void:
	## Auxiliary: Populates blackboard with tool ID and tag requirements from job def.
	if blackboard == null:
		return
	# 1. Def Requirement Extraction: Reads item id/tags off the job's def, if any.
	var reqs: Dictionary = AIUtils.extract_tool_requirements(def_obj)
	var req_id: String = str(reqs.get("item_id", ""))
	var req_tags: Array[StringName] = reqs.get("tags", [] as Array[StringName])

	if req_id != "":
		blackboard.set_var(&"required_equipped", req_id)
	else:
		blackboard.erase_var(&"required_equipped")

	if not req_tags.is_empty():
		blackboard.set_var(&"required_equipped_tags", req_tags)
		blackboard.set_var(&"required_tool_tag", req_tags[0])
	else:
		blackboard.erase_var(&"required_equipped_tags")
		blackboard.erase_var(&"required_tool_tag")


func _update_active_job_target_pos(colonist: Colonist, job: Variant) -> void:
	## Auxiliary: Dynamically updates target_pos on blackboard for continuing multi-leg jobs.
	if blackboard == null or colonist == null or job == null:
		return
	var job_def_obj: Resource = AIUtils.resolve_job_def(job)
	if job_def_obj != null and job_def_obj.has_method("work_site"):
		var site: Variant = job_def_obj.work_site(colonist, job)
		if site is Vector3:
			blackboard.set_var(target_pos_var, site)
			return
		elif site is Node3D:
			blackboard.set_var(target_pos_var, (site as Node3D).global_position)
			return
	if "target_pos" in job:
		blackboard.set_var(target_pos_var, job.target_pos)
	elif "target_position" in job:
		blackboard.set_var(target_pos_var, job.target_position)
	elif "world_position" in job:
		blackboard.set_var(target_pos_var, job.world_position)
	elif "anchor_cell" in job and job.anchor_cell != Vector3i.MAX:
		blackboard.set_var(target_pos_var, Vector3(job.anchor_cell) + Vector3(0.5, 0.5, 0.5))
	elif "target_node" in job and job.target_node != null and is_instance_valid(job.target_node):
		if job.target_node is Node3D:
			blackboard.set_var(target_pos_var, (job.target_node as Node3D).global_position)
