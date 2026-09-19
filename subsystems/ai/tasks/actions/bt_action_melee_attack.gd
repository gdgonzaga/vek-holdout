## Subsystem: AI Tasks
## Performs a melee attack against a threat target with windup, damage application, and cooldown.
@tool
class_name BTActionMeleeAttack
extends BTAction

## Blackboard variable storing the threat target node
@export var target_var: StringName = &"threat_target"

## Damage dealt per attack strike
@export var damage: int = 15

## Range within which melee strikes can connect
@export var attack_range: float = 1.8

## Windup duration before damage connects (seconds)
@export var windup_duration: float = 0.4

## Total cooldown duration between attacks (seconds)
@export var cooldown_duration: float = 1.0

## When true, resolves damage/attack_range/windup_duration/cooldown_duration
## from the agent's resolved combat source (EnemyDef.attack_params via
## EnemyBase, mirroring BTActionScanThreats's use_weapon_range) instead of
## the exports above -- one shared tree can then serve multiple archetypes
## that only differ in these numbers. The exports above remain in effect
## when false (default), or as the fallback if the agent's attack_params
## isn't a MeleeActionParams.
@export var use_agent_attack_params: bool = false

var _elapsed: float = 0.0
var _damage_applied: bool = false
var _effective_damage: int = 0
var _effective_attack_range: float = 0.0
var _effective_windup: float = 0.0
var _effective_cooldown: float = 0.0


func _generate_name() -> String:
	return "Melee Attack  target: %s (dmg: %d, r: %.1fm)" % [
		LimboUtility.decorate_var(target_var),
		damage,
		attack_range
	]


func _enter() -> void:
	_elapsed = 0.0
	_damage_applied = false
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

	_elapsed += delta
	if not _damage_applied and _elapsed >= _effective_windup:
		_damage_applied = true
		ColonistLogger.log_msg(agent as Node, &"COMBAT", "Melee attack connects on %s" % target.name)
		if _effective_damage > 0 and target.has_method("take_damage"):
			target.take_damage(_effective_damage, agent)

	if _elapsed < (_effective_windup + _effective_cooldown):
		return RUNNING

	# 1. Blackboard Cleanup: Erase target after attack completion to trigger re-evaluation of closest target.
	_clear_target_variable()
	return SUCCESS


func _resolve_effective_params() -> void:
	## Auxiliary: Resolves effective attack numbers from the agent's
	## EnemyDef-driven combat action when opted in, else from this task's own
	## authored exports (see use_agent_attack_params doc comment above).
	if use_agent_attack_params:
		var source: Node = AIUtils.resolve_combat_source(agent)
		var action: CombatActionParams = source.get_combat_action() if source != null and source.has_method("get_combat_action") else null
		if action is MeleeActionParams:
			var melee := action as MeleeActionParams
			_effective_damage = int(melee.damage)
			_effective_attack_range = melee.range_meters
			_effective_windup = melee.windup_seconds
			_effective_cooldown = melee.active_seconds + melee.cooldown_seconds
			return
	_effective_damage = damage
	_effective_attack_range = attack_range
	_effective_windup = windup_duration
	_effective_cooldown = cooldown_duration


func _clear_target_variable() -> void:
	## Auxiliary: Clears the assigned target variable on the blackboard.
	if blackboard and blackboard.has_var(target_var):
		blackboard.erase_var(target_var)

