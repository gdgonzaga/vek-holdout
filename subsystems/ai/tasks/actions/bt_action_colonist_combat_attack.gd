## Subsystem: AI Tasks
## Fires/swings the colonist's equipped weapon at a threat already found by
## BTActionScanThreats (GDD §6.7). Never moves the agent (halts any in-progress
## job navigation instead) -- MVP has zero pursuit distance.
@tool
class_name BTActionColonistCombatAttack
extends BTAction

## Blackboard variable storing the threat target node (shared with BTActionScanThreats).
@export var target_var: StringName = &"threat_target"


func _generate_name() -> String:
	return "Colonist Combat Attack  target: %s" % LimboUtility.decorate_var(target_var)


func _tick(delta: float) -> Status:
	if not agent or not blackboard:
		return FAILURE

	# 1. Stale Target Guard: Validity must be checked on the raw Variant before
	# any typed cast -- casting an already-freed object directly throws
	# "Trying to cast a freed object" instead of failing gracefully.
	var target: Node3D = null
	if blackboard.has_var(target_var):
		var raw_target: Variant = blackboard.get_var(target_var)
		if is_instance_valid(raw_target) and raw_target is Node3D:
			target = raw_target
	if target == null or target.is_queued_for_deletion():
		return FAILURE
	if "is_dead" in target and bool(target.is_dead):
		return FAILURE

	var combat: ColonistCombat = agent.get_node_or_null("ColonistCombat") as ColonistCombat
	if combat == null or not combat.is_target_in_range(target):
		return FAILURE

	# 1. Movement Halt: Stops in-progress job navigation so the colonist holds
	# position while engaged (GDD §6.7 max pursuit distance = 0).
	if agent.has_method("set_path"):
		agent.set_path([])

	# 2. Target Facing: Continuously orient the colonist towards the combat target and look at its center mass.
	_face_target(target, delta)

	if not combat.is_on_cooldown():
		# 3. Weapon Dispatch: Fires/swings the equipped weapon's primary action.
		combat.attack(target)
	return RUNNING


func _exit() -> void:
	# 1. Look Release: Stop looking at the threat once this task is no longer engaged.
	var anim_ctrl := _anim_controller()
	if anim_ctrl != null:
		anim_ctrl.clear_look_target()


func _face_target(target: Node3D, delta: float) -> void:
	## Auxiliary: Faces the threat target and keeps the colonist looking at its center mass.
	var anim_ctrl := _anim_controller()
	if anim_ctrl != null:
		anim_ctrl.face_target(target.global_position, delta)
		anim_ctrl.set_look_target(target)


func _anim_controller() -> ColonistAnimationController:
	## Auxiliary: The agent's colonist animation controller, or null when it has none.
	if not is_instance_valid(agent) or not (agent is Node):
		return null
	return (agent as Node).get_node_or_null("ColonistAnimationController") as ColonistAnimationController
