class_name GiveItemAction
extends GameAction

func execute(actor: Node, target: Node) -> void:
	var furniture := target as Furniture
	if furniture == null:
		return
	var params := furniture.def.item_dispenser_params as ItemDispenserParams
	if params == null:
		return
	for entry in params.items:
		var item_id := entry.item_def.resource_path.get_file().trim_suffix(".tres")
		actor.add_item(item_id, entry.count)
		GameLog.log("Received %d %s from %s" % [entry.count, item_id, furniture.def.display_name])
