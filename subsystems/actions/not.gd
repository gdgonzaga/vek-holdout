class_name NotCondition
extends Condition

@export var condition: Condition
func is_met(actor, target) -> bool:
    return not condition.is_met(actor, target)
