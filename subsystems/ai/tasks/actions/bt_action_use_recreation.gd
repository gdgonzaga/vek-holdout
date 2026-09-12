## Subsystem: AI Tasks
## Occupies a recreation object and accrues the recreation need over time.
@tool
class_name BTActionUseRecreation
extends BTAction

## Blackboard variable storing the target recreation furniture.
@export var smart_object_var: StringName = &"target_smart_object"

## Blackboard variable storing the active goal name.
@export var goal_var: StringName = &"current_goal"

## Blackboard variable storing the resolved standing position, cleared on success
## so the next goal can never navigate to a stale spot.
@export var stand_pos_var: StringName = &"target_stand_pos"

## Need this action replenishes. Matches NeedDef.id, not NeedDef.goal_name.
@export var need_id: StringName = &"recreation"

## Animation used when the furniture authors none.
@export var fallback_animation: StringName = &"Interact"

var _elapsed: float = 0.0
var _need_at_entry: float = 0.0
var _component: Node = null
var _params: RecreationParams = null
var _furniture: Node3D = null
var _anim_controller: Node = null


func _generate_name() -> String:
	return "Use Recreation  target: %s, need: %s" % [
		LimboUtility.decorate_var(smart_object_var),
		need_id
	]


# =================
# Primary Functions
# =================

func _enter() -> void:
	_elapsed = 0.0
	_component = null
	_params = null

	# 1. Target Resolution: Bind the furniture and its occupancy component up
	# front so every subsequent tick is a cheap arithmetic step.
	_furniture = _resolve_target_furniture()
	if _furniture == null:
		return
	_component = _resolve_recreation_component(_furniture)
	if _component == null:
		return
	_params = _component.call(&"params") as RecreationParams

	# 2. Slot Promotion: Convert the brain's reservation into active use. A refusal
	# means another colonist took the last slot while this one walked over.
	if not bool(_component.call(&"begin_use", agent)):
		_component = null
		return

	_need_at_entry = _read_need()
	_play_use_animation()


func _tick(delta: float) -> Status:
	if _component == null or _params == null or not is_instance_valid(_furniture):
		return FAILURE

	# 1. Range Enforcement: The authored use_radius is what lets a statue be
	# admired from across a room while an arcade cabinet demands adjacency.
	if not _is_agent_in_range():
		return FAILURE

	_elapsed += delta

	# 2. Need Accrual: Restore at the furniture's authored rate rather than a flat
	# amount, so object quality is expressed purely as data.
	var current := _read_need()
	_write_need(clampf(current + _params.recreation_per_second * delta, 0.0, 1.0))

	if not _is_session_complete():
		return RUNNING

	# 3. Goal Handover: Clear the goal before reporting success so ColonistBrain
	# re-arbitrates on its next poll instead of re-entering this branch.
	_clear_blackboard_goal()
	_log_session_result()
	return SUCCESS


func _exit() -> void:
	# Runs on interruption as well as success, which is what guarantees a slot is
	# never leaked when a raid or a critical need preempts this branch.
	if _component != null and is_instance_valid(_component):
		_component.call(&"end_use", agent)
	_component = null
	if _anim_controller and _anim_controller.has_method("clear_override"):
		_anim_controller.clear_override()


# ===================
# Auxiliary Functions
# ===================

func _resolve_target_furniture() -> Node3D:
	## Auxiliary: Reads the target furniture node from the blackboard.
	if blackboard == null or not blackboard.has_var(smart_object_var):
		return null
	var target: Variant = blackboard.get_var(smart_object_var)
	if target is Node3D and is_instance_valid(target):
		return target as Node3D
	return null


func _resolve_recreation_component(furniture: Node) -> Node:
	## Auxiliary: Finds the furniture's RecreationComponent child.
	for child in furniture.get_children():
		if child is RecreationComponent:
			return child
	return null


func _is_agent_in_range() -> bool:
	## Auxiliary: Compares agent-to-furniture distance against the authored radius.
	if not (agent is Node3D):
		return true
	var dist: float = (agent as Node3D).global_position.distance_to(_furniture.global_position)
	return dist <= _params.use_radius


func _is_session_complete() -> bool:
	## Auxiliary: A session ends once the committed minimum has elapsed AND either
	## the need is full or the ceiling is reached. The minimum is what stops a
	## high-rate object from producing a visible one-frame twitch.
	if _elapsed < _params.min_session_seconds:
		return false
	return _read_need() >= 1.0 or _elapsed >= _params.session_ceiling_seconds()


func _read_need() -> float:
	## Auxiliary: Reads the current need value from the agent's ColonistNeeds.
	var needs := _resolve_needs()
	if needs == null:
		return 0.0
	return needs.get_need(need_id)


func _write_need(value: float) -> void:
	## Auxiliary: Writes the need value back to the agent's ColonistNeeds.
	var needs := _resolve_needs()
	if needs != null:
		needs.set_need(need_id, value)


func _resolve_needs() -> ColonistNeeds:
	## Auxiliary: Resolves ColonistNeeds by node name, then by property, matching
	## how BTActionUseSmartObject reaches it on mock actors in tests.
	if agent == null:
		return null
	var needs := agent.get_node_or_null("ColonistNeeds") as ColonistNeeds
	if needs == null and "needs" in agent:
		needs = agent.needs
	return needs


func _play_use_animation() -> void:
	## Auxiliary: Starts the authored idle/use animation for the session.
	_anim_controller = AIUtils.resolve_anim_controller(_anim_controller, agent)
	if _anim_controller == null or not _anim_controller.has_method("play_animation_override"):
		return
	var anim: StringName = _params.use_animation if _params.use_animation != &"" else fallback_animation
	_anim_controller.play_animation_override(anim)


func _clear_blackboard_goal() -> void:
	## Auxiliary: Releases the goal and both target keys for re-arbitration.
	if blackboard == null:
		return
	blackboard.set_var(goal_var, &"none")
	if blackboard.has_var(smart_object_var):
		blackboard.set_var(smart_object_var, null)
	if blackboard.has_var(stand_pos_var):
		blackboard.set_var(stand_pos_var, null)


func _log_session_result() -> void:
	## Auxiliary: Emits buffered telemetry for the completed session.
	ColonistLogger.log_need(
		agent,
		need_id,
		_need_at_entry,
		_read_need(),
		"recreation session %.1fs" % _elapsed
	)
