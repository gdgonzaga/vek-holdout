extends Node
class_name ColonistAI

## Colonist build-job loop (Phase 4): poll the JobBoard for a construction job,
## claim it, pathfind to a stand-adjacent cell of the blueprint, and on arrival
## complete the job and return to idle. The sprint goal is "a colonist walks to
## the blueprint" — arrival completes the JOB only; the blueprint stays placed
## (the player builds it manually), and the real build (work-tick ->
## BlueprintLayer.complete_blueprint) is deferred to the GDD §6 work phase.
##
## Two persistent states: IDLE polls the board on a throttle and runs the
## synchronous claim+path step (the conceptual "CLAIM"); MOVE watches arrival and
## runs the synchronous complete step (the conceptual "ARRIVE"). An inline enum
## keeps the MVP loop in one place (no separate state-machine class).

enum State { IDLE, MOVE }

const _POLL_INTERVAL := 0.5  # seconds between JobBoard polls while idle

@onready var _colonist: Colonist = get_parent()

var _state: State = State.IDLE
var _poll_clock: float = 0.0


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
				_finish_job()


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
		return  # lost the claim race; another colonist (or a retry) takes it
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


## MOVE arrival: drop the job from the board and return to idle. Does NOT build
## the blueprint (sprint scope is "walks to it"); the blueprint stays placed.
func _finish_job() -> void:
	if _colonist.current_job != null:
		Colony.job_board.complete(_colonist.current_job.id)
		_colonist.current_job = null
	_state = State.IDLE
	_poll_clock = 0.0
