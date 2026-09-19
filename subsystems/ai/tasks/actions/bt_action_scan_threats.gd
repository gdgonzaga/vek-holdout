## Subsystem: AI Tasks
## Scans for valid threats (Player > Core > Colonists) within sensory radius.
@tool
class_name BTActionScanThreats
extends BTAction

## Sensory detection radius in meters
@export var radius: float = 16.0

## When true, dynamically resolves the scan radius from the agent's ColonistCombat attack range.
@export var use_weapon_range: bool = false

## Blackboard variable where the selected threat node is stored
@export var result_var: StringName = &"threat_target"

## Groups to scan in priority order
@export var threat_groups: Array[StringName] = [&"player", &"players", &"colonists"]



func _generate_name() -> String:
	if use_weapon_range:
		return "Scan Threats  weapon_range -> %s" % LimboUtility.decorate_var(result_var)
	return "Scan Threats  radius: %.1fm -> %s" % [
		radius,
		LimboUtility.decorate_var(result_var)
	]


func _tick(_delta: float) -> Status:
	if not agent or not agent.get_tree() or not (agent is Node3D):
		_clear_result_var()
		return FAILURE

	var agent_node := agent as Node3D
	var effective_radius: float = radius
	if use_weapon_range:
		# 1. Weapon Range Query: Resolves attack reach from agent's ColonistCombat component.
		var weapon_range: float = _resolve_weapon_range(agent_node)
		if weapon_range <= 0.0:
			_clear_result_var()
			return FAILURE
		effective_radius = weapon_range

	var max_dist_sq: float = effective_radius * effective_radius

	# 2. Threat Acquisition: Finding the closest target across all threat groups within sensory radius.
	var closest_target: Node3D = _find_closest_threat(agent_node, max_dist_sq)
	if closest_target == null:
		_clear_result_var()
		return FAILURE

	if blackboard and result_var != &"":
		blackboard.set_var(result_var, closest_target)
	return SUCCESS


func _resolve_weapon_range(agent_node: Node3D) -> float:
	## Auxiliary: Queries the attack range from the agent's resolved combat
	## source (ColonistCombat sibling, or the agent itself for EnemyBase --
	## see AIUtils.resolve_combat_source / ICombatSource).
	var source: Node = AIUtils.resolve_combat_source(agent_node)
	if source != null and source.has_method("get_attack_range"):
		return source.get_attack_range()
	return 0.0


func _clear_result_var() -> void:
	## Auxiliary: Erases a stale threat on scan failure — a previous sighting
	## must not read as "still present" once a rescan comes back empty. Both
	## BTActionColonistCombatAttack and ColonistBrain's need-lock suspension
	## depend on this being an accurate current-presence signal, not a memory.
	if blackboard and result_var != &"":
		blackboard.erase_var(result_var)



func _find_closest_threat(agent_node: Node3D, max_dist_sq: float) -> Node3D:
	## Auxiliary: Scans nodes in all threat_groups and returns the closest valid target Node3D.
	var agent_pos: Vector3 = agent_node.global_position
	var closest_node: Node3D = null
	var closest_dist_sq: float = max_dist_sq

	for group_name in threat_groups:
		# 1. Group Scan: Finds this group's nearest live, non-agent, non-dead node within range.
		var candidate: Node3D = AIUtils.find_nearest_in_group(
			agent_node.get_tree(), group_name, agent_pos, agent_node, closest_dist_sq, true
		)
		if candidate != null:
			closest_node = candidate
			closest_dist_sq = agent_pos.distance_squared_to(candidate.global_position)

	return closest_node

