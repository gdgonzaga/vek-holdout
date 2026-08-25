## Subsystem: AI Tasks
## Selects a nearby walkable cell and navigates to it, providing natural idle wandering.
@tool
class_name BTActionWander
extends BTAction

## Maximum wander radius in cells
@export var radius: int = 4

## Distance to target required to consider arrival successful
@export var arrival_distance: float = 0.5

var _target_world_pos: Vector3 = Vector3.ZERO
var _has_valid_path: bool = false


func _generate_name() -> String:
	return "Wander  radius: %d" % radius


func _enter() -> void:
	_has_valid_path = false
	_target_world_pos = Vector3.ZERO
	
	if not agent or not ("pathfinder" in agent) or agent.pathfinder == null or not (agent is Node3D):
		return
		
	var pathfinder = agent.pathfinder
	var agent_pos: Vector3 = (agent as Node3D).global_position
	var center_cell: Vector3i = pathfinder.find_stand_cell(agent_pos)
	var stand_cell: Vector3i = pathfinder.find_stand_near_cell(center_cell, radius)
	
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


func _tick(_delta: float) -> Status:
	if not agent or not _has_valid_path:
		return FAILURE
		
	if _target_world_pos != Vector3.ZERO and agent is Node3D:
		var curr_pos: Vector3 = (agent as Node3D).global_position
		if curr_pos.distance_to(_target_world_pos) <= arrival_distance:
			return SUCCESS
		
	if agent.has_method("has_arrived") and bool(agent.has_arrived()):
		return SUCCESS
		
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
