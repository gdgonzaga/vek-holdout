## Subsystem: AI Tasks
## Checks if any living node in a specific group is within range, and stores the closest in blackboard.
@tool
class_name BTConditionInGroup
extends BTCondition

## Target node group to scan for
@export var group: StringName = &"enemies"

## Proximity detection radius in meters
@export var radius: float = 12.0

## Blackboard variable where the closest matching node is written
@export var result_var: StringName = &"threat_target"


func _generate_name() -> String:
	return "In Group  %s within %.1fm -> %s" % [
		group,
		radius,
		LimboUtility.decorate_var(result_var)
	]


func _tick(_delta: float) -> Status:
	if not agent or not agent.get_tree():
		return FAILURE

	var agent_pos: Vector3 = agent.global_position if agent is Node3D else Vector3.ZERO
	# 1. Proximity Scan: Finds the closest live, non-agent node in `group` within radius.
	var closest_node: Node3D = AIUtils.find_nearest_in_group(
		agent.get_tree(), group, agent_pos, agent, radius * radius
	)
	if closest_node == null:
		return FAILURE

	if blackboard and result_var != &"":
		blackboard.set_var(result_var, closest_node)
	return SUCCESS
