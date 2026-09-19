## Subsystem: AI Tasks
## Fires the agent's ranged attack (EnemyDef.attack_params, resolved via
## AIUtils.resolve_combat_source/ICombatSource) at a threat already found by
## BTActionScanThreats. Applies damage directly to the already-selected
## target rather than delegating to RangedActionParams.execute()'s
## camera/facing-dependent hitscan+tracer path -- that path is designed for
## Player/Colonist, and EnemyBase doesn't rotate to face targets, so it would
## fire in a fixed, usually-wrong direction. Mirrors BTActionMeleeAttack's
## target-locked model (see its use_agent_attack_params doc comment); no
## legacy standalone-export fallback here since this task is new, not a
## rework of an existing one.
@tool
class_name BTActionRangedAttack
extends BTAction

## Blackboard variable storing the threat target node (shared with BTActionScanThreats).
@export var target_var: StringName = &"threat_target"

var _elapsed: float = 0.0
var _fired: bool = false
var _effective_damage: int = 0
var _effective_attack_range: float = 0.0
var _effective_cooldown: float = 0.0


func _generate_name() -> String:
	return "Ranged Attack  target: %s" % LimboUtility.decorate_var(target_var)


func _enter() -> void:
	_elapsed = 0.0
	_fired = false
	_resolve_effective_params()


func _tick(delta: float) -> Status:
	if not agent or not blackboard:
		return FAILURE

	var target: Node3D = null
	if blackboard.has_var(target_var):
		target = blackboard.get_var(target_var) as Node3D

	if not is_instance_valid(target) or target.is_queued_for_deletion():
		return FAILURE

	var agent_pos: Vector3 = (agent as Node3D).global_position if agent is Node3D else Vector3.ZERO
	if agent_pos.distance_to(target.global_position) > _effective_attack_range:
		return FAILURE

	if not _fired:
		_fired = true
		ColonistLogger.log_msg(agent as Node, &"COMBAT", "Ranged attack connects on %s" % target.name)
		if _effective_damage > 0 and target.has_method("take_damage"):
			target.take_damage(_effective_damage, agent)

	_elapsed += delta
	if _elapsed < _effective_cooldown:
		return RUNNING

	# 1. Blackboard Cleanup: Erase target after attack completion to trigger re-evaluation of closest target.
	_clear_target_variable()
	return SUCCESS


func _resolve_effective_params() -> void:
	## Auxiliary: Resolves effective damage/range/cooldown from the agent's
	## EnemyDef-driven RangedActionParams. Leaves everything at 0 (causing an
	## immediate range-check FAILURE next tick) if the agent has no ranged
	## attack authored -- there is no standalone-export fallback to fall back to.
	var source: Node = AIUtils.resolve_combat_source(agent)
	var action: CombatActionParams = source.get_combat_action() if source != null and source.has_method("get_combat_action") else null
	if action is RangedActionParams:
		var ranged := action as RangedActionParams
		_effective_damage = int(ranged.damage)
		_effective_attack_range = ranged.range_meters
		_effective_cooldown = ranged.get_lockout_duration()
	else:
		_effective_damage = 0
		_effective_attack_range = 0.0
		_effective_cooldown = 0.0


func _clear_target_variable() -> void:
	## Auxiliary: Clears the assigned target variable on the blackboard.
	if blackboard and blackboard.has_var(target_var):
		blackboard.erase_var(target_var)
