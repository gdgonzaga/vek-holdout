## Subsystem: AI Tasks
## Interacts with a designated smart object, waits for interaction duration, and replenishes colonist needs.
@tool
class_name BTActionUseSmartObject
extends BTAction

## Blackboard variable storing the target smart object
@export var smart_object_var: StringName = &"target_smart_object"

## Blackboard variable storing the active goal name (e.g. &"eat", &"sleep", &"recreation")
@export var goal_var: StringName = &"current_goal"

## Duration of the smart object interaction in seconds
@export var default_duration: float = 2.0

## Animation to play during interaction
@export var default_animation: StringName = &"Interact"

## Amount of need value to restore (0.0 to 1.0, 1.0 = fully replenished)
@export var restore_amount: float = 1.0

var _elapsed: float = 0.0
var _anim_controller: Node = null


func _generate_name() -> String:
	return "Use Smart Object  target: %s, goal: %s (%.1fs)" % [
		LimboUtility.decorate_var(smart_object_var),
		LimboUtility.decorate_var(goal_var),
		default_duration
	]


func _enter() -> void:
	_elapsed = 0.0
	_resolve_anim_controller()
	if _anim_controller and _anim_controller.has_method("play_animation_override"):
		_anim_controller.play_animation_override(default_animation)


func _tick(delta: float) -> Status:
	_elapsed += delta
	if _elapsed < default_duration:
		return RUNNING
		
	# Replenish need on ColonistNeeds
	var goal: StringName = &""
	if blackboard and blackboard.has_var(goal_var):
		goal = blackboard.get_var(goal_var)
		
	var needs: ColonistNeeds = null
	if agent:
		needs = agent.get_node_or_null("ColonistNeeds") as ColonistNeeds
		if not needs and "needs" in agent:
			needs = agent.needs
			
	if needs != null and goal != &"":
		var defs := ColonistNeeds.get_need_defs()
		for need_id in defs:
			var def: Resource = defs[need_id]
			if def.goal_name == goal or need_id == goal:
				var current_val: float = needs.get_need(need_id)
				needs.set_need(need_id, clampf(current_val + restore_amount, 0.0, 1.0))
				break
				
	# Clear active goal so ColonistBrain re-evaluates
	if blackboard:
		blackboard.set_var(goal_var, &"none")
		if blackboard.has_var(smart_object_var):
			blackboard.set_var(smart_object_var, null)
			
	return SUCCESS


func _exit() -> void:
	if _anim_controller and _anim_controller.has_method("clear_override"):
		_anim_controller.clear_override()


func _resolve_anim_controller() -> void:
	if _anim_controller and is_instance_valid(_anim_controller):
		return
	if agent:
		_anim_controller = agent.get_node_or_null("ColonistAnimationController")
		if not _anim_controller:
			_anim_controller = agent.find_child("ColonistAnimationController", true, false)
