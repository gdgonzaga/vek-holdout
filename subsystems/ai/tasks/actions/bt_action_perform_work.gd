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


func _generate_name() -> String:
	return "Perform Work  job: %s (%.1fs)" % [
		LimboUtility.decorate_var(job_var),
		default_duration
	]


func _enter() -> void:
	_elapsed = 0.0
	_target_duration = default_duration
	var anim_to_play: StringName = default_animation
	
	var job: Variant = null
	if blackboard:
		if blackboard.has_var(job_var):
			job = blackboard.get_var(job_var)
		elif blackboard.has_var(&"active_claim"):
			job = blackboard.get_var(&"active_claim")
		
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
				var duration: float = float(job.def.begin(agent, null, job))
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


func _tick(delta: float) -> Status:
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
		elif "def" in job and job.def != null and job.def.has_method("complete"):
			job.def.complete(agent, null, job)
			finished = true
		elif job.has_method("complete"):
			job.complete(agent)
			finished = true

		if finished:
			_release_job_reference()

	return SUCCESS


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
## same spot.
func _release_job_reference() -> void:
	if blackboard:
		blackboard.erase_var(job_var)
		blackboard.erase_var(&"active_claim")
	if agent is Colonist:
		(agent as Colonist).current_job = null


func _exit() -> void:
	if _anim_controller and _anim_controller.has_method("clear_override"):
		_anim_controller.clear_override()


func _resolve_anim_controller() -> void:
	if _anim_controller and is_instance_valid(_anim_controller):
		return
	if agent:
		_anim_controller = agent.get_node_or_null("ColonistAnimationController")
		if not _anim_controller:
			_anim_controller = agent.find_child("ColonistAnimationController", true, false)
