class_name AllOf
extends Condition

@export var conditions: Array[Condition] = []

func is_met(actor, target) -> bool:
	for c in conditions:
		if not c.is_met(actor, target): return false
	return true
