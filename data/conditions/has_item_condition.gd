class_name HasItemCondition
extends Condition

## Actor must have `count` of an item on them — by exact `item_id`, or any item
## whose ItemDef carries `item_tag` (e.g. "tool"). `item_id` wins when both are
## set; both empty is a misconfiguration and fails closed. Counts the actor's
## carry inventory (Colonist or Player) PLUS whatever they hold in Equipment,
## because an equipped item lives in the equipment slots, not the inventory: a
## player holding the required tool must still pass.

@export var item_id: String = ""
@export var item_tag: String = ""
@export var count: int = 1

func is_met(actor: Node, _target: Node) -> bool:
	if actor == null or (item_id == "" and item_tag == ""):
		return false
	var inventory = actor.get("inventory")
	if inventory == null or not inventory is Inventory:
		return false
	# 1. Carried Count: Units of the item (or tag) in the actor's carry inventory.
	var held := _carried_count(inventory as Inventory)
	# 2. Equipped Count: Units in the actor's equipment slots, which the inventory no longer lists.
	held += _equipped_count(actor.get("equipment"))
	return held >= count


func _carried_count(inventory: Inventory) -> int:
	## Auxiliary: Inventory units matching item_id, else matching item_tag.
	if item_id != "":
		return inventory.get_item_count(item_id)
	return inventory.count_items_with_tag(item_tag)


func _equipped_count(equipment: Variant) -> int:
	## Auxiliary: Equipped slots matching item_id, else matching item_tag (0 when the actor has no Equipment).
	if not equipment is Equipment:
		return 0
	if item_id != "":
		return (equipment as Equipment).count_equipped_item(item_id)
	return (equipment as Equipment).count_equipped_tag(item_tag)
