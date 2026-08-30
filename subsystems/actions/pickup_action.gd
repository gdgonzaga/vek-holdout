class_name PickupAction
extends GameAction
## Action allowing an actor (Player or Colonist) to pick up a WorldItem.

func _init() -> void:
	label = "Pick up"


func execute(actor: Node, target: Node) -> void:
	var world_item := target as WorldItem
	if world_item == null or not is_instance_valid(world_item):
		return

	var inventory: Inventory = _resolve_inventory(actor)
	if inventory == null:
		return

	var remaining_count := world_item.count
	if remaining_count <= 0:
		if world_item.is_reserved():
			world_item.hide_item()
		else:
			world_item.queue_free()
		return

	var overflow := inventory.add(world_item.item_id, remaining_count)
	var taken := remaining_count - overflow

	if taken > 0:
		world_item.count -= taken
		var item_name := world_item.item_id
		var def := ItemDB.get_def(world_item.item_id) if ItemDB != null else null
		if def != null and def.id != "":
			item_name = def.id

		if actor is Player or actor.is_in_group("player"):
			GameLog.info("Picked up %s (x%d)" % [item_name, taken])

		if world_item.count <= 0:
			if world_item.is_reserved():
				world_item.hide_item()
			else:
				world_item.queue_free()
		else:
			world_item.update_visuals_and_interaction()
	else:
		if actor is Player or actor.is_in_group("player"):
			GameLog.warning("Inventory is full!")


func _resolve_inventory(actor: Node) -> Inventory:
	if actor == null:
		return null
	if "inventory" in actor:
		var inv = actor.get("inventory") as Inventory
		if inv != null:
			return inv
	for child in actor.get_children():
		if child is Inventory:
			return child
	return actor.get_node_or_null("CharacterInventory") as Inventory
