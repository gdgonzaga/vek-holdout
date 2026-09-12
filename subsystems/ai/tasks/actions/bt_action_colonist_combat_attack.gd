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

	# 2. Target Facing: Continuously orient the colonist visual mesh towards the combat target.
	_face_target(target, delta)

	if not combat.is_on_cooldown():
		# 3. Weapon Dispatch: Fires/swings the equipped weapon's primary action.
		combat.attack(target)
	return RUNNING


func _face_target(target: Node3D, delta: float) -> void:
	## Auxiliary: Commands the colonist animation controller to face the threat target.
	if not (agent is Node):
		return
	var anim_ctrl: ColonistAnimationController = (agent as Node).get_node_or_null("ColonistAnimationController") as ColonistAnimationController
	if anim_ctrl != null:
		anim_ctrl.face_target(target.global_position, delta)
