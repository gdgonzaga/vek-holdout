extends Node
class_name ColonistAI
## Colonist job loop over a leg sequence (ARCH "Subsystem: Colonists", GDD §6.10).
## Polls the JobBoard for an available job, assigns via Job.try_assign, and walks
## the job's JobLeg stream — for each leg: path to leg.location, on arrival run
## the JobDef's begin/complete (0-duration begin = instant), then advance to the
## next leg or end. The job's def owns the leg behaviour (which leg, what each
## does); this node owns the per-frame tick and the state machine.
##
## Three persistent states: IDLE polls the board on a throttle and runs the
## synchronous assign+leg-0+path step; MOVE follows the current leg's path (and
## aborts if that leg's target is freed out from under us); WORK ticks a timed
## leg's duration. Hauling is all MOVE + instant legs (no WORK); construction is
## one timed leg. An inline enum keeps the loop in one place (no separate
## state-machine class).
##
## Multi-assign: this colonist joins a job that may have other colonists too
## (hauling). When this colonist is done with its legs (or aborts), it unassigns;
## the job leaves the board only when should_close() — no assignees left AND the
## def considers it dead (a drought-waiting haul job stays registered) — so one
## colonist finishing ≠ job done.

enum State {IDLE, MOVE, WORK}

const _POLL_INTERVAL := 0.5 # seconds between JobBoard polls while idle

@onready var _colonist: Colonist = get_parent()

var _state: State = State.IDLE
var _poll_clock: float = 0.0
# The leg currently being walked/worked. Set on claim (leg 0) and in _advance.
var _leg: JobLeg = null
# WORK scratch: the elapsed/duration pair this AI ticks against job.def.begin().
var _work_elapsed: float = 0.0
var _work_duration: float = 0.0


func _process(delta: float) -> void:
	if not is_instance_valid(_colonist):
		return
	match _state:
		State.IDLE:
			_poll_clock += delta
			if _poll_clock >= _POLL_INTERVAL:
				_poll_clock = 0.0
				_try_claim_and_path()
		State.MOVE:
			# Freed-target guard: if the current leg's node vanished while we
			# walked (crate destroyed, blueprint cancelled), abort cleanly.
			if _leg != null and _leg.target_node != null and not is_instance_valid(_leg.target_node):
				_abort_job("leg target freed")
				return
			if _colonist.has_arrived() or _is_in_work_range():
				_begin_work()
		State.WORK:
			_tick_work(delta)


## IDLE tick (throttled): find the best available job, assign to it, get its
## first leg, and path there. On any miss (no job, lost assign race, no first
## leg, or no reachable adjacent cell) release and stay IDLE; the throttle bounds
## retries.
func _try_claim_and_path() -> void:
	if _colonist.pathfinder == null:
		return
	var job := Colony.job_board.get_best_job_for(_colonist)
	if job == null:
		return
	if not job.try_assign(_colonist):
		return # lost the assign race (rare — get_best_job_for filters is_available)
	_colonist.current_job = job
	var leg: JobLeg = job.def.get_next_leg(_colonist, job) if job.def != null else null
	if leg == null:
		# Available but nothing for us right now (e.g. a source race, or carried
		# items clogging capacity). Release — running on_end first so def-side
		# cleanup fires (hauling's surplus dump clears the clog; _end_job skips
		# the no-leg path by design). The leg is null by contract here.
		if job.def != null:
			job.def.on_end(false, _colonist, null, job, 0.0)
		job.unassign(_colonist)
		_colonist.current_job = null
		return
	var path := _path_for_leg(leg)
	if path.is_empty():
		# No reachable adjacent cell — release and record a failure: three
		# failures auto-remove the job, bounding the claim→release thrash the
		# flat-base-map MVP previously tolerated.
		if job.def != null:
			job.def.on_end(false, _colonist, null, job, 0.0)
		job.unassign(_colonist)
		_colonist.current_job = null
		Colony.job_board.fail(job.id, "no reachable cell")
		return
	_leg = leg
	_colonist.set_path(path)
	_state = State.MOVE


## MOVE arrival: run the current leg. Ask the def how long the work takes; if
## instant (<=0) fire complete() now and advance; otherwise enter WORK and tick.
func _is_in_work_range() -> bool:
	if _colonist.current_job == null or _leg == null:
		return false
	var target_pos := _leg.location
	if _leg.target_node != null and is_instance_valid(_leg.target_node):
		var node3d := _leg.target_node as Node3D
		if node3d != null:
			target_pos = node3d.global_position
	elif _colonist.current_job.anchor_cell != Vector3i.MAX:
		target_pos = Vector3(_colonist.current_job.anchor_cell) + Vector3(0.5, 0.5, 0.5)
	return _colonist.global_position.distance_to(target_pos) <= 1.8


func _begin_work() -> void:
	var job: Variant = _colonist.current_job
	if job == null or job.def == null or _leg == null:
		_end_job(true) # nothing to work — close out cleanly
		return
	_work_duration = job.def.begin(_colonist, _leg, job)
	_work_elapsed = 0.0
	if _work_duration <= 0.0:
		job.def.complete(_colonist, _leg, job)
		_advance()
		return
	_state = State.WORK


## WORK tick: accumulate elapsed against the def's duration; on elapse, fire the
## def's complete() and advance. If the leg's target was freed mid-build, abort.
func _tick_work(delta: float) -> void:
	var job: Variant = _colonist.current_job
	if job == null or _leg == null:
		_end_job(false)
		return
	if _leg.target_node != null and not is_instance_valid(_leg.target_node):
		_abort_job("work target freed")
		return
	_work_elapsed += delta
	if _work_elapsed >= _work_duration:
		job.def.complete(_colonist, _leg, job)
		_advance()


## After a leg's complete: ask the def for the next leg. If there is one, re-path
## and keep moving (legs are how a hauler loops crate→blueprint→crate…). If not,
## this colonist is done with the job — cleanly only when the def says the job
## itself is complete; a stall short of completion (a hauler that drained every
## crate below the sink's need) is logged, not booked as success. An unreachable
## next leg aborts the job.
func _advance() -> void:
	var job: Variant = _colonist.current_job
	if job == null or job.def == null:
		_end_job(true)
		return
	var leg: JobLeg = job.def.get_next_leg(_colonist, job)
	if leg == null:
		var finished: bool = job.def.job_complete(job)
		if not finished:
			GameLog.colony("%s stalled — waiting for materials" % job.title)
		_end_job(finished)
		return
	var path := _path_for_leg(leg)
	if path.is_empty():
		_abort_job("next leg unreachable") # give the job up for this colonist
		return
	_leg = leg
	_colonist.set_path(path)
	_state = State.MOVE


## Build a path to `leg`. If the leg's target is a Furniture node, paths to
## the nearest walkable cell adjacent to its full footprint (multi-target A*).
## Falls back to find_path_to_adjacent for non-furniture / unknown targets.
func _path_for_leg(leg: JobLeg) -> Array[Vector3]:
	var furniture := leg.target_node as Furniture
	if furniture != null and is_instance_valid(furniture):
		var fp := furniture.get_footprint_cells()
		if not fp.is_empty():
			return _colonist.pathfinder.find_path_to_footprint_adjacent(
					_colonist.global_position, fp)
	return _colonist.pathfinder.find_path_to_adjacent(
			_colonist.global_position, leg.location)


## Abort the current job (leg target freed, leg unreachable): run the normal
## end-of-job cleanup first — on_end must still return carried items and
## persist partial progress — then record a failure on the board (failure
## counter + job_logged; auto-removes at _MAX_FAILURES). A no-op fail for a
## job _end_job already removed. Multi-assign note: fail clears the remaining
## assignees too; their own AI loops self-correct on their next tick.
func _abort_job(reason: String) -> void:
	var job: Variant = _colonist.current_job
	_end_job(false)
	if job != null:
		Colony.job_board.fail(job.id, reason)


## This colonist is leaving the job (clean finish when get_next_leg returned
## null and the def reports the job complete, or abort when the target freed /
## a leg was unreachable). Run the def's on_end cleanup (return carried items,
## persist partial progress), unassign, and remove the job from the board iff it
## should now close (last assignee out AND the def says dead). Then return to
## the idle poll.
func _end_job(success: bool) -> void:
	var job: Variant = _colonist.current_job
	if job != null:
		# on_end is per-leg cleanup; skip it on the degenerate no-leg path (and
		# for ad-hoc def-less jobs) so a def that reads leg.target_node can't crash.
		if job.def != null and _leg != null:
			job.def.on_end(success, _colonist, _leg, job, _work_elapsed)
		# Use-based skill XP: a clean finish trains the skill governing the
		# labor (no-op for unskilled labors — hauling maps to no skill).
		if success and job.def != null and _colonist.skill_set != null:
			_colonist.skill_set.record_use_for_labor(job.labor_id)
		job.unassign(_colonist)
		if job.should_close():
			Colony.job_board.remove_job(job.id)
	_colonist.current_job = null
	_leg = null
	# Drop any unconsumed waypoints too (dig jobs routinely enter work range with
	# the path unfinished): a leftover _path keeps the debug visualizer's tether,
	# path strip and target box redrawing at the closed job site, and would let
	# locomotion drift along stale waypoints (pathfinding.md §6).
	_colonist.set_path([])
	if _colonist.pathfinder != null:
		_colonist.pathfinder.clear_diagnostics()
	_work_elapsed = 0.0
	_state = State.IDLE
	_poll_clock = 0.0
