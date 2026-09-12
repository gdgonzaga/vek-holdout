## Subsystem: AI Tasks
## Selects a nearby walkable cell and navigates to it, providing natural idle wandering.
@tool
class_name BTActionWander
extends BTAction

## Maximum wander radius in cells
@export var radius: int = 4

## Distance to target required to consider arrival successful
@export var arrival_distance: float = 0.5

## Seconds to stand still at the destination before wandering again
@export var wait_duration: float = 3.0

var _target_world_pos: Vector3 = Vector3.ZERO
var _has_valid_path: bool = false
var _waiting: bool = false
var _wait_elapsed: float = 0.0


func _generate_name() -> String:
	return "Wander  radius: %d  wait: %.1fs" % [radius, wait_duration]


func _enter() -> void:
	_has_valid_path = false
	_target_world_pos = Vector3.ZERO
	_waiting = false
	_wait_elapsed = 0.0

	if not agent or not ("pathfinder" in agent) or agent.pathfinder == null or not (agent is Node3D):
		return
		
	var pathfinder = agent.pathfinder
	var agent_pos: Vector3 = (agent as Node3D).global_position
	var center_cell: Vector3i = pathfinder.find_stand_cell(agent_pos)

	# Roll a random horizontal offset so the search base isn't the colonist's
	# own (always-walkable) cell -- otherwise find_stand_near_cell just hands
	# that same cell back and the colonist never actually moves.
	var search_base: Vector3i = center_cell + _roll_horizontal_offset(radius)
	var stand_cell: Vector3i = pathfinder.find_stand_near_cell(search_base, radius)

	if stand_cell == Vector3i.MAX:
		return
		
	_target_world_pos = Vector3(stand_cell) + Vector3(0.5, 0.0, 0.5)
	var path: Array[Vector3] = pathfinder.find_path_world(agent_pos, _target_world_pos)
	
	if path.is_empty():
		return
		
	_has_valid_path = true
	if agent.has_method("set_path"):
		agent.set_path(path)
		if agent is Node:
			(agent as Node).set_meta(BTActionNavigateTo._PATH_OWNER_META, get_instance_id())


func _tick(delta: float) -> Status:
	if not agent or not _has_valid_path:
		return FAILURE

	# Once at the destination, hold position for wait_duration before this
	# task reports SUCCESS -- without this, the root selector immediately
	# re-enters wander every frame and colonists never actually stop.
	if _waiting:
		return _tick_wait_phase(delta)

	if _has_arrived_at_target():
		return _enter_wait_phase()

	return RUNNING


func _exit() -> void:
	# Only clear the agent's path when this instance owns it (the meta token is
	# shared with BTActionNavigateTo): the root BTDynamicSelector ticks sibling
	# branches and a wander exit must not wipe a path another branch set.
	if agent == null or not agent is Node:
		return
	if (agent as Node).has_meta(BTActionNavigateTo._PATH_OWNER_META) \
			and (agent as Node).get_meta(BTActionNavigateTo._PATH_OWNER_META) == get_instance_id():
		if agent.has_method("set_path"):
			agent.set_path([])
		if "pathfinder" in agent and agent.pathfinder != null and agent.pathfinder.has_method("clear_diagnostics"):
			agent.pathfinder.clear_diagnostics()


func _roll_horizontal_offset(max_radius: int) -> Vector3i:
	## Auxiliary: rolls a random x/z offset within +/- max_radius, nudged off
	## Vector3i.ZERO so the search base handed to find_stand_near_cell is never
	## the agent's own (always-walkable) cell -- that would just hand the same
	## cell back and reproduce the "wander never moves" bug for this tick.
	if max_radius <= 0:
		return Vector3i.ZERO
	var dx := randi_range(-max_radius, max_radius)
	var dz := randi_range(-max_radius, max_radius)
	if dx == 0 and dz == 0:
		dx = max_radius
	return Vector3i(dx, 0, dz)


func _has_arrived_at_target() -> bool:
	## Auxiliary: true once the agent is within arrival_distance of the rolled
	## target, or the agent's own movement independently reports arrival.
	if _target_world_pos != Vector3.ZERO and agent is Node3D:
		var curr_pos: Vector3 = (agent as Node3D).global_position
		if curr_pos.distance_to(_target_world_pos) <= arrival_distance:
			return true
	return agent.has_method("has_arrived") and bool(agent.has_arrived())


func _enter_wait_phase() -> Status:
	## Auxiliary: starts the post-arrival pause, or skips it when wait_duration
	## is non-positive so that configuration preserves the old immediate-
	## SUCCESS-on-arrival behavior.
	if wait_duration <= 0.0:
		return SUCCESS
	_waiting = true
	_wait_elapsed = 0.0
	return RUNNING


func _tick_wait_phase(delta: float) -> Status:
	## Auxiliary: counts down the post-arrival pause, reporting SUCCESS once
	## wait_duration has elapsed so the tree can roll a fresh destination.
	_wait_elapsed += delta
	if _wait_elapsed >= wait_duration:
		return SUCCESS
	return RUNNING
