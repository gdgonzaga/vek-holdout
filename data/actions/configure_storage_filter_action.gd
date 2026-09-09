class_name ConfigureStorageFilterAction
extends GameAction
## Opens the storage item whitelist configuration UI for the targeted furniture's StorageInventory.
## Mounted on the same CanvasLayer the InteractionComponent uses (group "hud_layer" / "ui_layer").

const _filter_panel_scene: PackedScene = preload("res://ui/storage_filter/storage_filter_panel.tscn")

func _init() -> void:
	label = "Configure Filter"

# =================
# Primary Functions
# =================

func execute(actor: Node, target: Node) -> void:
	var furniture := target as Furniture
	if furniture == null:
		return
	var storage := furniture.get_node_or_null("StorageInventory") as StorageInventory
	if storage == null:
		return
		
	var panel: Control = _filter_panel_scene.instantiate()
	
	# 1. UI Layer Resolution: Find HUD or UI CanvasLayer to mount the modal panel.
	var layer := _find_ui_layer(actor)
	if layer != null:
		layer.add_child(panel)
	else:
		push_warning("ConfigureStorageFilterAction: no hud/ui CanvasLayer found, parenting to actor")
		actor.add_child(panel)
		
	# 2. Panel Setup: Initialize panel with furniture and storage inventory references.
	panel.setup(furniture, storage)


# ===================
# Auxiliary Functions
# ===================

static func _find_ui_layer(node: Node) -> CanvasLayer:
	## Auxiliary: Resolves the active CanvasLayer in group hud_layer or ui_layer.
	var tree := node.get_tree()
	if tree == null:
		return null
	var layer := tree.get_first_node_in_group("hud_layer") as CanvasLayer
	if layer == null:
		layer = tree.get_first_node_in_group("ui_layer") as CanvasLayer
	return layer
