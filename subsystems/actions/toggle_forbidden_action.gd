class_name ToggleForbiddenAction
extends GameAction
## Action allowing the player to forbid/unforbid a WorldItem from being hauled.

func _init() -> void:
	label = "Toggle Forbidden"


func execute(actor: Node, target: Node) -> void:
	var world_item := target as WorldItem
	if world_item == null or not is_instance_valid(world_item):
		return

	world_item.set_forbidden(not world_item.forbidden)
