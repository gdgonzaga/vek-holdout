extends Node
class_name ColonistAI

## Colonist build-job loop: poll the JobBoard for a construction job, claim it,
## pathfind to a stand-adjacent cell of the blueprint, and on arrival WORK it —
## ticking the JobDef's begin/complete over its build_time so the blueprint
## actually materializes (Blueprint.complete), then return to idle. The job's def
## owns the work behaviour (ConstructionJobDef); this node owns the per-frame
## tick and the state machine.
##
## Three persistent states: IDLE polls the board on a throttle and runs the
## synchronous claim+path step; MOVE watches arrival and enters WORK; WORK ticks
## the job def's duration, then completes the job (or aborts if the target
## vanished mid-build). An inline enum keeps the MVP loop in one place (no
## separate state-machine class).

enum State {IDLE, MOVE, WORK}

const _POLL_INTERVAL := 0.5 # seconds between JobBoard polls while idle

@onready var _colonist: Colonist = get_parent()

var _state: State = State.IDLE
var _poll_clock: float = 0.0
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
			if _colonist.has_arrived():
				_begin_work()
		State.WORK:
			_tick_work(delta)


## IDLE tick (throttled): find the best construction job, claim it, and path to
## the nearest stand-adjacent cell of its blueprint. On success -> MOVE. On any
## miss (no job, lost claim race, or no reachable adjacent cell) release and stay
## IDLE; the throttle bounds retries.
func _try_claim_and_path() -> void:
	if _colonist.pathfinder == null:
		return
	var job := Colony.job_board.get_best_job_for(_colonist)
	if job == null:
		return
	var claimed := Colony.job_board.claim(job.id, _colonist.colonist_id)
	if claimed == null:
		return # lost the claim race; another colonist (or a retry) takes it
	_colonist.current_job = claimed
	var path := _colonist.pathfinder.find_path_to_adjacent(_colonist.global_position, claimed.location)
	if path.is_empty():
		# No reachable adjacent cell — release without penalty and let a later
		# poll retry. (True-unreachable thrash is a known MVP gap; the flat base
		# map always has a path.)
		Colony.job_board.unclaim(claimed.id, _colonist.colonist_id)
		_colonist.current_job = null
		return
	_colonist.set_path(path)
	_state = State.MOVE


## MOVE arrival: enter WORK. Ask the job's def how long the work takes; if it's
## instant (<=0) fire complete() now and finish; otherwise let _tick_work run it.
func _begin_work() -> void:
	var job := _colonist.current_job
	if job == null or job.def == null:
		_finish_job() # no def/behaviour -> nothing to work, just close
		return
	_work_duration = job.def.begin(_colonist, job.target_node)
	_work_elapsed = 0.0
	if _work_duration <= 0.0:
		job.def.complete(_colonist, job.target_node)
		_finish_job()
		return
	_state = State.WORK


## WORK tick: accumulate elapsed against the def's duration; on elapse, fire the
## def's complete() and finish. If the target node was freed out from under us
## (blueprint cancelled/completed elsewhere), abort cleanly.
func _tick_work(delta: float) -> void:
	var job := _colonist.current_job
	if job == null or not is_instance_valid(job.target_node):
		_abort_work()
		return
	_work_elapsed += delta
	if _work_elapsed >= _work_duration:
		job.def.complete(_colonist, job.target_node)
		_finish_job()


## Drop a job whose target vanished mid-build: persist the partial work so a
## later attempt resumes if the target survived (future reassignment; a freed
## target has nothing to persist), release the claim, and idle.
func _abort_work() -> void:
	var job := _colonist.current_job
	if job != null:
		if is_instance_valid(job.target_node) and job.target_node is Blueprint:
			(job.target_node as Blueprint).work_done = _work_elapsed
		if job.id != "":
			Colony.job_board.unclaim(job.id, _colonist.colonist_id)
		_colonist.current_job = null
	_state = State.IDLE
	_poll_clock = 0.0


## WORK completion / instant finish: drop the job from the board and return to
## the idle poll. Does NOT build the blueprint — the def's complete() did that.
func _finish_job() -> void:
	if _colonist.current_job != null:
		Colony.job_board.complete(_colonist.current_job.id)
		_colonist.current_job = null
	_state = State.IDLE
	_poll_clock = 0.0
