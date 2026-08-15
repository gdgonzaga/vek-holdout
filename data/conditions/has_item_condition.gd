class_name HasItemCondition
extends Condition

## Actor must carry `count` of an item — by exact `item_id`, or any item whose
## ItemDef carries `item_tag` (e.g. "tool"). `item_id` wins when both are set;
## both empty is a misconfiguration and fails closed. Reads the actor's
## inventory (Colonist or Player carry inventory).

@export var item_id: String = ""
@export var item_tag: String = ""
@export var count: int = 1

func is_met(actor: Node, _target: Node) -> bool:
    if actor == null or (item_id == "" and item_tag == ""):
        return false
    var inventory = actor.get("inventory")
    if inventory == null or not inventory is Inventory:
        return false
    if item_id != "":
        return inventory.has_item(item_id, count)
    return inventory.has_item_tag(item_tag, count)
