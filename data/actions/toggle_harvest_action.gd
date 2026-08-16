class_name ToggleHarvestAction
extends GameAction
## Toggles the harvest mark on the targeted furniture node (e.g. tree).

func execute(_actor: Node, target: Node) -> void:
	var harvestable := _harvestable_of(target)
	if harvestable != null:
		harvestable.toggle_mark()


func _harvestable_of(target: Node) -> Harvestable:
	if target == null or not is_instance_valid(target):
		return null
	var harvestable := target as Harvestable
	if harvestable != null:
		return harvestable
	return target.get_node_or_null("Harvestable") as Harvestable
