class_name AnyOf
extends Condition

@export var conditions: Array[Condition] = []
func is_met(actor, target) -> bool:
    for c in conditions:
        if c.is_met(actor, target): return true
    return false
