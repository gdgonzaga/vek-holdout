## Subsystem: AI Tasks
## Plays a work animation for a specified or job-derived duration and applies work units / effects.
@tool
class_name BTActionPerformWork
extends BTAction

## Blackboard variable storing the active job or claim
@export var job_var: StringName = &"active_job"

## Default work cycle duration in seconds if not specified by the job definition
@export var default_duration: float = 1.2

## Default animation to play during work
@export var default_animation: StringName = &"Interact"

var _elapsed: float = 0.0
var _target_duration: float = 1.2
var _anim_controller: Node = null

## Job/claim resolved at _enter — _exit needs it for on_abort after the
## blackboard reference was already released (or was never there).
var _job_ref: Variant = null

## False while the current work cycle is still pending; set once the terminal
## effect ran. _exit fires def.on_abort only for preempted (mid-work) exits.
var _cycle_finished: bool = false


func _generate_name() -> String:
	return "Perform Work  job: %s (%.1fs)" % [
		LimboUtility.decorate_var(job_var),
		default_duration
	]


func _enter() -> void:
	_elapsed = 0.0
	_target_duration = default_duration
	var anim_to_play: StringName = default_animation
	_cycle_finished = false
	_job_ref = null

	var job: Variant = null
	if blackboard:
		if blackboard.has_var(job_var):
			job = blackboard.get_var(job_var)
		elif blackboard.has_var(&"active_claim"):
			job = blackboard.get_var(&"active_claim")
	_job_ref = job
		
	if job is Dictionary:
		if job.has("work_animation") and job["work_animation"] != &"":
			anim_to_play = job["work_animation"]
		elif job.has("job_def") and job["job_def"] != null and job["job_def"].work_animation != &"":
			anim_to_play = job["job_def"].work_animation
		if job.has("work_duration") and float(job["work_duration"]) > 0.0:
			_target_duration = float(job["work_duration"])
		elif job.has("job_def") and job["job_def"] != null and float(job["job_def"].work_duration) > 0.0:
			_target_duration = float(job["job_def"].work_duration)
	elif job != null and is_instance_valid(job):
		# Resolve animation name
		if job.has_method("get_work_animation"):
			anim_to_play = job.get_work_animation()
		elif "work_animation" in job and job.work_animation != &"":
			anim_to_play = job.work_animation
		elif "job_def" in job and job.job_def != null and job.job_def.work_animation != &"":
			anim_to_play = job.job_def.work_animation
		elif "def" in job and job.def != null and "work_animation" in job.def and job.def.work_animation != &"":
			anim_to_play = job.def.work_animation
			
		# Resolve work duration
		if job.has_method("get_work_duration"):
			_target_duration = float(job.get_work_duration())
		elif "work_duration" in job and float(job.work_duration) > 0.0:
			_target_duration = float(job.work_duration)
		elif "job_def" in job and job.job_def != null and float(job.job_def.work_duration) > 0.0:
			_target_duration = float(job.job_def.work_duration)
		elif "def" in job and job.def != null:
				if "work_duration" in job.def and float(job.def.work_duration) > 0.0:
					_target_duration = float(job.def.work_duration)
				elif job.def.has_method("begin"):
					# begin reports UNSKILLED seconds (JobDef contract) — the
					# multiplier below does the scaling.
					var duration: float = float(job.def.begin(agent, job))
					if duration > 0.0:
						_target_duration = duration
					
		# Factor in skill multiplier if present
		var labor: String = ""
		if job.has_method("get_labor_id"):
			labor = str(job.get_labor_id())
		elif "labor_id" in job:
			labor = str(job.labor_id)
			
		if agent and "skill_set" in agent and agent.skill_set != null and labor != "":
			var mult: float = float(agent.skill_set.get_multiplier(labor))
			if mult > 0.0:
				_target_duration = _target_duration / mult

	# Trigger animation override
	_resolve_anim_controller()
	if _anim_controller and _anim_controller.has_method("play_animation_override"):
		_anim_controller.play_animation_override(anim_to_play)

	# 1. Work Look Target: Face and lean toward what this cycle actually works on.
	_look_at_work_target(job)


func _tick(delta: float) -> Status:
	# 1. Equipment Continuity Check: Verifies the tool has not broken or been disarmed mid-cycle.
	if not _is_required_tool_equipped():
		return FAILURE

	_elapsed += delta
	if _elapsed < _target_duration:
		return RUNNING
		
	# Complete work effect
	var job: Variant = null
	if blackboard:
		if blackboard.has_var(job_var):
			job = blackboard.get_var(job_var)
		elif blackboard.has_var(&"active_claim"):
			job = blackboard.get_var(&"active_claim")
		
	if job is Dictionary:
		var units: int = 20
		if job.has("job_def") and job["job_def"] != null and job["job_def"].default_units_per_cycle > 0:
			units = job["job_def"].default_units_per_cycle
		if job.has("apply_work_units"):
			job["apply_work_units"].call(units, agent)
	elif job != null and is_instance_valid(job):
		var units: int = 20
		if "job_def" in job and job.job_def != null and job.job_def.default_units_per_cycle > 0:
			units = job.job_def.default_units_per_cycle
		elif "job" in job and job.job != null and job.job.job_def != null and job.job.job_def.default_units_per_cycle > 0:
			units = job.job.job_def.default_units_per_cycle

		# Terminal effect paths complete the job outright; progressive paths
		# only release the blackboard reference once nothing remains to work.
		# Every def-level JobDef.complete IS terminal for the cycle (the def
		# itself decides via _finish whether the job also leaves the board —
		# hauling's fetch/deliver loop keeps it registered).
		var finished: bool = false
		if job.has_method("apply_work_units"):
			job.apply_work_units(units, agent)
			finished = _nothing_left_to_work(job)
		elif job.has_method("apply_work"):
			job.apply_work(units, agent)
			finished = _nothing_left_to_work(job)
		elif job.has_method("complete_work"):
			job.complete_work(agent)
			finished = true
		elif "def" in job and job.def != null:
			job.def.complete(agent, job)
			# 1. Multi-Leg Completion Check: Verifies if multi-leg or single-shot JobDef is fully satisfied.
			finished = _is_job_def_completed(job)
		elif job.has_method("complete"):
			job.complete(agent)
			finished = true

		if finished:
			_release_job_reference(job)

	_cycle_finished = true
	return SUCCESS


func _is_job_def_completed(job: Variant) -> bool:
	## Auxiliary: Checks if a Job with a JobDef is completed and should release its claim.
	if job == null or not is_instance_valid(job):
		return true
	if "is_completed" in job and bool(job.is_completed):
		return true
	if job.has_method("is_finished") and bool(job.is_finished()):
		return true
	if "id" in job and str(job.id) != "" and agent is Node:
		var colony := (agent as Node).get_node_or_null("/root/Colony")
		if colony != null and "job_board" in colony and colony.job_board != null:
			if colony.job_board.has_method("has_job") and not colony.job_board.has_job(str(job.id)):
				return true
			elif colony.job_board.has_method("get_job") and colony.job_board.get_job(str(job.id)) == null:
				return true
	if "def" in job and job.def != null:
		var def: Variant = job.def
		if def is HaulingJobDef:
			return bool(def.job_complete(job)) or bool(def.should_close(job))
		if def.has_method("job_complete"):
			return bool(def.job_complete(job))
		if def.has_method("should_close"):
			return bool(def.should_close(job))
	return true


## True when the worked object has no remaining progress: a JobInstance that
## is_completed, or a WorkerClaim whose reserved units are done. Objects with
## no progress flags (legacy Jobs completed via def.complete) are handled by
## the caller treating their effect path as terminal.
func _nothing_left_to_work(job: Variant) -> bool:
	if "is_completed" in job:
		return bool(job.is_completed)
	if job.has_method("is_finished"):
		return bool(job.is_finished())
	return false


## Drop active_job/active_claim from the blackboard so the next ClaimJob tick
## claims fresh work. Without this the stale reference kept ClaimJob returning
## SUCCESS for a finished job and the work loop re-completed it forever at the
## same spot. Legacy multi-assign jobs also release their slot, so the board's
## should_close prune can retire a satisfied job and another colonist may take
## the next cycle.
func _release_job_reference(job: Variant = null) -> void:
	if agent is Node:
		ColonistLogger.log_msg(agent as Node, &"JOB", "PerformWork: Releasing job reference %s" % str(job))
	if blackboard:
		blackboard.erase_var(job_var)
		blackboard.erase_var(&"active_claim")
	if agent is Colonist:
		(agent as Colonist).current_job = null
		if job != null and job.has_method("unassign"):
			job.unassign(agent)


func _exit() -> void:
	if _anim_controller and _anim_controller.has_method("clear_override"):
		_anim_controller.clear_override()
	if _anim_controller and _anim_controller.has_method("clear_look_target"):
		_anim_controller.clear_look_target()
	# Preempted mid-cycle (a need won the dynamic selector, agent freed, ...):
	# let the def persist partial progress / release held claims (JobDef
	# on_abort). A finished cycle already resolved everything.
	if not _cycle_finished and agent != null and _job_ref != null and is_instance_valid(_job_ref):
		var def: Resource = AIUtils.resolve_job_def(_job_ref)
		if def != null and def.has_method("on_abort"):
			def.on_abort(agent, _job_ref, _elapsed)
	_job_ref = null


func _resolve_anim_controller() -> void:
	_anim_controller = AIUtils.resolve_anim_controller(_anim_controller, agent)


func _look_at_work_target(job: Variant) -> void:
	## Auxiliary: Points the colonist's look at the node or world point this work cycle acts on.
	if _anim_controller == null or not _anim_controller.has_method("set_look_target"):
		return
	# 1. Target Resolution: Resolve the worked node (center mass) or a fixed point.
	var look_at: Variant = _resolve_work_look_target(job)
	if look_at is Node3D:
		_anim_controller.set_look_target(look_at)
	elif look_at is Vector3:
		_anim_controller.set_look_point(look_at)


func _resolve_work_look_target(job: Variant) -> Variant:
	## Auxiliary: The Node3D or Vector3 this work cycle acts on, or null when the job exposes neither.
	if job == null or job is Dictionary or not is_instance_valid(job) or not (agent is Node3D):
		return null
	var def: Resource = AIUtils.resolve_job_def(job)
	var site: Variant = def.work_site(agent, job) if def != null and def.has_method("work_site") else null
	if site is Vector3:
		# Multi-site legs (hauling, fetching, deploying) only report a floor-level
		# position; face it at aim height so the colonist doesn't hunch over the floor.
		return _level_with_agent(site)
	var node: Variant = job.target_node if "target_node" in job else null
	if not is_instance_valid(node):
		node = null
	if node is Node3D:
		return node
	if node is Node and node.get_parent() is Node3D:
		# Component targets (e.g. CraftingStation) hang off the furniture node that has the mesh.
		return node.get_parent()
	if "location" in job and job.location != Vector3.ZERO:
		return job.location
	return null


func _level_with_agent(point: Vector3) -> Vector3:
	## Auxiliary: The point moved to the agent's aim height, so looking at it adds no lean.
	var aim_y: float = agent.get_aim_origin().y if agent.has_method("get_aim_origin") else (agent as Node3D).global_position.y
	return Vector3(point.x, aim_y, point.z)


func _is_required_tool_equipped() -> bool:
	## Auxiliary: Returns true if the agent still holds any tool required by the active job.
	var def_obj: Resource = _resolve_active_job_def()
	if def_obj == null:
		return true

	var reqs: Dictionary = AIUtils.extract_tool_requirements(def_obj)
	var req_id: String = str(reqs.get("item_id", ""))
	var req_tags: Array[StringName] = reqs.get("tags", [] as Array[StringName])
	if req_id == "" and req_tags.is_empty():
		return true

	if not (agent is Node):
		return false
	var eq: Equipment = (agent as Node).get_node_or_null("Equipment") as Equipment
	if eq == null:
		return false
	return eq.has_required_equipment(req_id, req_tags)


func _resolve_active_job_def() -> Resource:
	## Auxiliary: Resolves the JobDef Resource associated with the currently worked job.
	var job: Variant = _job_ref
	if job == null and blackboard:
		if blackboard.has_var(job_var):
			job = blackboard.get_var(job_var)
		elif blackboard.has_var(&"active_claim"):
			job = blackboard.get_var(&"active_claim")
	return AIUtils.resolve_job_def(job)
