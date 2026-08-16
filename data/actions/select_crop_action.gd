class_name SelectCropAction
extends GameAction
## Opens the Crop Picker selector for the targeted farm plot furniture.

const _picker_scene: PackedScene = preload("res://ui/crop_picker/crop_picker.tscn")

func execute(actor: Node, target: Node) -> void:
	var furniture := target as Furniture
	if furniture == null:
		return
	var growable := furniture.get_node_or_null("Growable") as Growable
	if growable == null:
		return
	var panel: Control = _picker_scene.instantiate()
	var layer := _find_ui_layer(actor)
	if layer != null:
		layer.add_child(panel)
	else:
		actor.add_child(panel)
	panel.setup(actor, growable)


static func _find_ui_layer(node: Node) -> CanvasLayer:
	var tree := node.get_tree()
	var layer := tree.get_first_node_in_group("hud_layer") as CanvasLayer
	if layer == null:
		layer = tree.get_first_node_in_group("ui_layer") as CanvasLayer
	return layer
