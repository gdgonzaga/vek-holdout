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

var _elapsed: float = 0.0
var _damage_applied: bool = false


func _generate_name() -> String:
	return "Melee Attack  target: %s (dmg: %d, r: %.1fm)" % [
		LimboUtility.decorate_var(target_var),
		damage,
		attack_range
	]


func _enter() -> void:
	_elapsed = 0.0
	_damage_applied = false


func _tick(delta: float) -> Status:
	if not agent or not blackboard:
		return FAILURE
		
	var target: Node3D = null
	if blackboard.has_var(target_var):
		target = blackboard.get_var(target_var) as Node3D
		
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		return FAILURE
		
	var agent_pos: Vector3 = (agent as Node3D).global_position if agent is Node3D else Vector3.ZERO
	if agent_pos.distance_to(target.global_position) > attack_range:
		return FAILURE
		
	_elapsed += delta
	if not _damage_applied and _elapsed >= windup_duration:
		_damage_applied = true
		if target.has_method("take_damage"):
			target.take_damage(damage, agent)
			
	if _elapsed < (windup_duration + cooldown_duration):
		return RUNNING
		
	return SUCCESS
