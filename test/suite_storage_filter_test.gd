## Test suite for StorageInventory whitelist filters and StorageFilterPanel UI.
extends GdUnitTestSuite

const _FilterPanelScene := preload("res://ui/storage_filter/storage_filter_panel.tscn")
const _ConfigureActionScene := preload("res://data/actions/configure_storage_filter_action.gd")


func test_storage_inventory_allowed_item_ids_whitelist_behavior() -> void:
	var defs := {
		"item_a": _make_test_item("item_a", 1.0, []),
		"item_b": _make_test_item("item_b", 1.0, []),
		"item_c": _make_test_item("item_c", 1.0, [])
	}

	var furniture := auto_free(Furniture.new()) as Furniture
	var storage := auto_free(Doubles.MockStorageInventory.new()) as Doubles.MockStorageInventory
	storage._defs = defs
	storage.capacity = 100.0
	furniture.add_child(storage)

	# Initially unrestricted
	assert_bool(storage.is_item_allowed("item_a")).is_true()
	assert_bool(storage.is_item_allowed("item_b")).is_true()

	# Add item_a to whitelist
	storage.set_item_allowed("item_a", true)
	assert_bool(storage.is_item_allowed("item_a")).is_true()
	assert_bool(storage.is_item_allowed("item_b")).is_false()
	assert_bool(storage.is_item_allowed("item_c")).is_false()

	# Add item_b to whitelist
	storage.set_item_allowed("item_b", true)
	assert_bool(storage.is_item_allowed("item_a")).is_true()
	assert_bool(storage.is_item_allowed("item_b")).is_true()
	assert_bool(storage.is_item_allowed("item_c")).is_false()

	# Remove item_a from whitelist
	storage.set_item_allowed("item_a", false)
	assert_bool(storage.is_item_allowed("item_a")).is_false()
	assert_bool(storage.is_item_allowed("item_b")).is_true()

	# Clear all restrictions
	storage.clear_allowed_items()
	assert_bool(storage.is_item_allowed("item_a")).is_true()
	assert_bool(storage.is_item_allowed("item_b")).is_true()
	assert_bool(storage.is_item_allowed("item_c")).is_true()


func test_storage_inventory_serialization_preserves_whitelist() -> void:
	var storage := auto_free(StorageInventory.new()) as StorageInventory
	storage.capacity = 50.0
	storage.allowed_item_ids = ["item_alpha", "item_beta"]
	storage.allowed_tags = ["tag_special"]

	var serialized := storage.serialize()
	assert_bool(serialized.has("allowed_item_ids")).is_true()
	assert_bool(serialized.has("allowed_tags")).is_true()

	var restored := auto_free(StorageInventory.new()) as StorageInventory
	restored.deserialize(serialized)

	assert_int(restored.allowed_item_ids.size()).is_equal(2)
	assert_bool(restored.allowed_item_ids.has("item_alpha")).is_true()
	assert_bool(restored.allowed_item_ids.has("item_beta")).is_true()
	assert_int(restored.allowed_tags.size()).is_equal(1)
	assert_bool(restored.allowed_tags.has("tag_special")).is_true()


func test_storage_filter_panel_setup_and_checkbox_toggles() -> void:
	var fdef := auto_free(FurnitureDef.new()) as FurnitureDef
	fdef.id = "test_crate"
	fdef.display_name = "Test Crate"

	var furniture := auto_free(Furniture.new()) as Furniture
	furniture.def = fdef
	furniture.def_id = "test_crate"

	var storage := auto_free(StorageInventory.new()) as StorageInventory
	storage.capacity = 100.0
	furniture.add_child(storage)

	var panel := auto_free(_FilterPanelScene.instantiate()) as StorageFilterPanel
	add_child(panel)
	panel.setup(furniture, storage)

	# Initially unrestricted
	assert_int(storage.allowed_item_ids.size()).is_equal(0)

	# Toggle an item on
	panel._on_item_toggled("test_item_x", true)
	assert_int(storage.allowed_item_ids.size()).is_equal(1)
	assert_bool(storage.allowed_item_ids.has("test_item_x")).is_true()

	# Toggle another item on
	panel._on_item_toggled("test_item_y", true)
	assert_int(storage.allowed_item_ids.size()).is_equal(2)
	assert_bool(storage.allowed_item_ids.has("test_item_y")).is_true()

	# Toggle first item off
	panel._on_item_toggled("test_item_x", false)
	assert_int(storage.allowed_item_ids.size()).is_equal(1)
	assert_bool(storage.allowed_item_ids.has("test_item_x")).is_false()
	assert_bool(storage.allowed_item_ids.has("test_item_y")).is_true()

	# Clear pressed
	panel._on_clear_pressed()
	assert_int(storage.allowed_item_ids.size()).is_equal(0)


func test_storage_filter_action_execution() -> void:
	var canvas_layer := auto_free(CanvasLayer.new()) as CanvasLayer
	canvas_layer.add_to_group("hud_layer")
	add_child(canvas_layer)

	var furniture := auto_free(Furniture.new()) as Furniture
	var storage := auto_free(StorageInventory.new()) as StorageInventory
	furniture.add_child(storage)
	add_child(furniture)

	var actor := auto_free(Node.new()) as Node
	add_child(actor)

	var action := auto_free(ConfigureStorageFilterAction.new()) as ConfigureStorageFilterAction
	action.execute(actor, furniture)

	var found_panel := false
	for child in canvas_layer.get_children():
		if child is StorageFilterPanel:
			found_panel = true
			child.queue_free()
			break

	assert_bool(found_panel).is_true()


func test_interaction_ui_displays_all_options() -> void:
	var ui_scene := preload("res://ui/interaction/interaction_ui.tscn")
	var ui := auto_free(ui_scene.instantiate()) as Control
	add_child(ui)

	var furniture := auto_free(Furniture.new()) as Furniture
	var actor := auto_free(Node.new()) as Node
	add_child(actor)

	var opt1 := auto_free(load("res://data/action_options/open_storage_action_option.tres")) as ActionOption
	var opt2 := auto_free(load("res://data/action_options/configure_storage_action_option.tres")) as ActionOption

	var options: Array[ActionOption] = [opt1, opt2]
	var comp := auto_free(InteractionComponent.new()) as InteractionComponent
	comp.action_options = options

	ui.setup(actor, furniture, options, comp)

	var list: VBoxContainer = ui.get_node("Panel/VBox/List") as VBoxContainer
	assert_int(list.get_child_count()).is_equal(2)

	var btn1 := list.get_child(0) as Button
	var btn2 := list.get_child(1) as Button

	assert_str(btn1.text).is_equal("Open Storage")
	assert_str(btn2.text).is_equal("Configure Filter")


func _make_test_item(p_id: String, p_weight: float, p_tags: Array[String]) -> ItemDef:
	var def := auto_free(ItemDef.new()) as ItemDef
	def.id = p_id
	def.weight = p_weight
	def.tags = p_tags
	return def
