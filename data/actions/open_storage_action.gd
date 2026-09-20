class_name OpenStorageAction
extends GameAction
## Opens the storage transfer UI between the acting player and the targeted
## furniture's StorageInventory. Mounted on the same CanvasLayer the
## InteractionComponent uses (group "hud_layer" / "ui_layer"). Mirrors
## GiveItemAction's `target as Furniture` + child-lookup pattern. The panel's
## Options button opens the filter/priority panel over it (ConfigureStorageFilterAction),
## so the player can adjust a container without leaving the transfer view.

const _storage_panel_scene: PackedScene = preload("res://ui/storage/storage_panel.tscn")

func _init() -> void:
	label = "Open Storage"

func execute(actor: Node, target: Node) -> void:
	var furniture := target as Furniture
	if furniture == null:
		return
	var storage := furniture.get_node_or_null("StorageInventory") as StorageInventory
	if storage == null:
		return
	var player_inv := actor.get("inventory") as Inventory
	if player_inv == null:
		return
	var panel := _storage_panel_scene.instantiate() as StoragePanel
	var layer := _find_ui_layer(actor)
	if layer != null:
		layer.add_child(panel)
	else:
		push_warning("OpenStorageAction: no hud/ui CanvasLayer found, parenting to actor")
		actor.add_child(panel)
	panel.setup(player_inv, storage)
	# The options panel mounts later on the same layer, so it sits above and takes input first.
	panel.configure_requested.connect(_on_configure_requested.bind(actor, furniture))


func _on_configure_requested(actor: Node, furniture: Furniture) -> void:
	## Auxiliary: Opens the filter/priority panel for the same container.
	ConfigureStorageFilterAction.new().execute(actor, furniture)


static func _find_ui_layer(node: Node) -> CanvasLayer:
	var tree := node.get_tree()
	var layer := tree.get_first_node_in_group("hud_layer") as CanvasLayer
	if layer == null:
		layer = tree.get_first_node_in_group("ui_layer") as CanvasLayer
	return layer
