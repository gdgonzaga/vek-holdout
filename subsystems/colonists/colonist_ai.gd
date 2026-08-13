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
## the job leaves the board only when should_close() — no assignees left AND not
## accepting more — so one colonist finishing ≠ job done.

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
				_end_job(false)
				return
			if _colonist.has_arrived():
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
		# Available but nothing for us right now (e.g. source race). Release.
		job.unassign(_colonist)
		_colonist.current_job = null
		return
	var path := _colonist.pathfinder.find_path_to_adjacent(_colonist.global_position, leg.location)
	if path.is_empty():
		# No reachable adjacent cell — release without penalty and let a later
		# poll retry. (True-unreachable thrash is a known MVP gap; the flat base
		# map always has a path.)
		job.unassign(_colonist)
		_colonist.current_job = null
		return
	_leg = leg
	_colonist.set_path(path)
	_state = State.MOVE


## MOVE arrival: run the current leg. Ask the def how long the work takes; if
## instant (<=0) fire complete() now and advance; otherwise enter WORK and tick.
func _begin_work() -> void:
	var job := _colonist.current_job
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
	var job := _colonist.current_job
	if job == null or _leg == null:
		_end_job(false)
		return
	if _leg.target_node != null and not is_instance_valid(_leg.target_node):
		_end_job(false)
		return
	_work_elapsed += delta
	if _work_elapsed >= _work_duration:
		job.def.complete(_colonist, _leg, job)
		_advance()


## After a leg's complete: ask the def for the next leg. If there is one, re-path
## and keep moving (legs are how a hauler loops crate→blueprint→crate…). If not,
## this colonist is done with the job. An unreachable next leg aborts the job.
func _advance() -> void:
	var job := _colonist.current_job
	if job == null or job.def == null:
		_end_job(true)
		return
	var leg: JobLeg = job.def.get_next_leg(_colonist, job)
	if leg == null:
		_end_job(true)
		return
	var path := _colonist.pathfinder.find_path_to_adjacent(_colonist.global_position, leg.location)
	if path.is_empty():
		_end_job(false) # next leg unreachable — give the job up for this colonist
		return
	_leg = leg
	_colonist.set_path(path)
	_state = State.MOVE


## This colonist is leaving the job (clean finish when get_next_leg returned
## null, or abort when the target freed / a leg was unreachable). Run the def's
## on_end cleanup (return carried items, persist partial progress), unassign,
## and remove the job from the board iff it should now close (last assignee out
## AND not accepting more). Then return to the idle poll.
func _end_job(success: bool) -> void:
	var job := _colonist.current_job
	if job != null:
		# on_end is per-leg cleanup; skip it on the degenerate no-leg path (and
		# for ad-hoc def-less jobs) so a def that reads leg.target_node can't crash.
		if job.def != null and _leg != null:
			job.def.on_end(success, _colonist, _leg, job, _work_elapsed)
		job.unassign(_colonist)
		if job.should_close():
			Colony.job_board.remove_job(job.id)
	_colonist.current_job = null
	_leg = null
	_work_elapsed = 0.0
	_state = State.IDLE
	_poll_clock = 0.0
