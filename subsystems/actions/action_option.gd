class_name ActionOption
extends Resource

@export var conditions: Array[Condition] = []
@export var action: GameAction


func is_available(actor: Node, target: Node) -> bool:
	for c in conditions:
		if not c.is_met(actor, target): return false
	return true
