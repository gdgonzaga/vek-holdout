class_name AddMaterialsAction
extends GameAction
## Deposits the actor's carried materials toward the targeted blueprint's
## material_cost (GDD §7.4). Bound to a Blueprint node via its "Add materials"
## ActionOption. Forwards to Blueprint.deposit_from — partial fulfillment is
## allowed, and the blueprint swaps to its Build option once the cost is met.

func execute(actor: Node, target: Node) -> void:
	var bp := target as Blueprint
	if bp == null:
		return
	bp.deposit_from(actor)
