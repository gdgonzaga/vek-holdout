class_name OpenCraftingAction
extends GameAction
## Opens the crafting UI for the targeted furniture's CraftingStation — a
## line-for-line mirror of OpenStorageAction (data/actions/open_storage_action.gd):
## resolve the capability child by its exact name, mount the panel on the same
## CanvasLayer the InteractionComponent uses, hand it the station. Panel
## lifetime is the panel's own (frees on close, re-captures the mouse).

const _craft_panel_scene: PackedScene = preload("res://ui/crafting/craft_panel.tscn")

func execute(actor: Node, target: Node) -> void:
	var furniture := target as Furniture
	if furniture == null:
		return
	var station := furniture.get_node_or_null("CraftingStation") as CraftingStation
	if station == null:
		return
	var panel: Control = _craft_panel_scene.instantiate()
	var layer := _find_ui_layer(actor)
	if layer != null:
		layer.add_child(panel)
	else:
		push_warning("OpenCraftingAction: no hud/ui CanvasLayer found, parenting to actor")
		actor.add_child(panel)
	panel.setup(station, actor as Player)


static func _find_ui_layer(node: Node) -> CanvasLayer:
	var tree := node.get_tree()
	var layer := tree.get_first_node_in_group("hud_layer") as CanvasLayer
	if layer == null:
		layer = tree.get_first_node_in_group("ui_layer") as CanvasLayer
	return layer
