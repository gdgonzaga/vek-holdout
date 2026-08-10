class_name CanCarryDispensedItems
extends Condition

func is_met(actor: Node, target: Node) -> bool:
	var furniture := target as Furniture

	if furniture == null:
		return true

	var params := furniture.def.item_dispenser_params as ItemDispenserParams

	if params == null:
		return true # no dispenser params → nothing to check

	var total_weight := 0.0
	for entry in params.items:
		total_weight += entry.item_def.weight * entry.count

	return actor.inventory.current_weight() + total_weight <= actor.inventory.capacity
