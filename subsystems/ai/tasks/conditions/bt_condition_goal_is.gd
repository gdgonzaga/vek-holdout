## Subsystem: AI Tasks
## Gates a behavior tree branch on the goal ColonistBrain arbitrated this cycle.
@tool
class_name BTConditionGoalIs
extends BTCondition

## Blackboard variable holding the active goal written by ColonistBrain.
@export var goal_var: StringName = &"current_goal"

## Goal this branch serves. Empty matches any goal (branch is ungated).
@export var expected_goal: StringName = &""


func _generate_name() -> String:
	return "Goal Is  %s == %s" % [
		LimboUtility.decorate_var(goal_var),
		expected_goal if expected_goal != &"" else "(any)"
	]


func _tick(_delta: float) -> Status:
	if expected_goal == &"":
		return SUCCESS
	if blackboard == null or not blackboard.has_var(goal_var):
		return FAILURE

	# Returning FAILURE here is the intended fall-through for the root
	# BTDynamicSelector, not the "never fail mid-task" case in ai-brain.md §7 —
	# this branch simply isn't the one the brain asked for this cycle.
	var active_goal: StringName = StringName(blackboard.get_var(goal_var))
	return SUCCESS if active_goal == expected_goal else FAILURE
