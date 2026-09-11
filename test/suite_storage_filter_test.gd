## Test suite for StorageInventory whitelist filters and StorageFilterPanel UI.
extends GdUnitTestSuite

const Doubles = preload("res://test/helpers/doubles.gd")
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


func test_storage_inventory_serialization_preserves_whitelist_and_priority() -> void:
	var storage := auto_free(StorageInventory.new()) as StorageInventory
	storage.capacity = 50.0
	storage.priority = 5
	storage.allowed_item_ids = ["item_alpha", "item_beta"]
	storage.allowed_tags = ["tag_special"]

	var serialized := storage.serialize()
	assert_bool(serialized.has("allowed_item_ids")).is_true()
	assert_bool(serialized.has("allowed_tags")).is_true()
	assert_int(int(serialized.get("priority", 0))).is_equal(5)

	var restored := auto_free(StorageInventory.new()) as StorageInventory
	restored.deserialize(serialized)

	assert_int(restored.priority).is_equal(5)
	assert_int(restored.allowed_item_ids.size()).is_equal(2)
	assert_bool(restored.allowed_item_ids.has("item_alpha")).is_true()
	assert_bool(restored.allowed_item_ids.has("item_beta")).is_true()
	assert_int(restored.allowed_tags.size()).is_equal(1)
	assert_bool(restored.allowed_tags.has("tag_special")).is_true()


func test_storage_registry_find_storage_for_priority_and_distance_tiebreak() -> void:
	var registry := auto_free(StorageRegistry.new()) as StorageRegistry
	var container := auto_free(Node3D.new()) as Node3D
	add_child(container)
	registry.on_map_wired(container)

	var any_item := _make_test_item("any_item", 1.0, [])
	ItemDB._defs_by_id["any_item"] = any_item

	# Crate 1: Close (dist 5m), priority 2
	var crate1 := auto_free(Furniture.new()) as Furniture
	var inv1 := auto_free(StorageInventory.new()) as StorageInventory
	inv1.name = "StorageInventory"
	inv1.capacity = 100.0
	inv1.priority = 2
	crate1.add_child(inv1)
	container.add_child(crate1)
	crate1.global_position = Vector3(5, 0, 0)

	# Crate 2: Far (dist 20m), priority 5 (Highest)
	var crate2 := auto_free(Furniture.new()) as Furniture
	var inv2 := auto_free(StorageInventory.new()) as StorageInventory
	inv2.name = "StorageInventory"
	inv2.capacity = 100.0
	inv2.priority = 5
	crate2.add_child(inv2)
	container.add_child(crate2)
	crate2.global_position = Vector3(20, 0, 0)

	# Crate 3: Farther (dist 30m), priority 5
	var crate3 := auto_free(Furniture.new()) as Furniture
	var inv3 := auto_free(StorageInventory.new()) as StorageInventory
	inv3.name = "StorageInventory"
	inv3.capacity = 100.0
	inv3.priority = 5
	crate3.add_child(inv3)
	container.add_child(crate3)
	crate3.global_position = Vector3(30, 0, 0)

	# Origin at (0, 0, 0)
	# 1. Higher priority wins over close low priority (Crate 2 over Crate 1)
	var chosen := registry.find_storage_for("any_item", Vector3.ZERO, 1)
	assert_object(chosen).is_equal(crate2)

	# 2. Tie-break between equal priority 5 (Crate 2 at 20m vs Crate 3 at 30m)
	# When crate 2 fills up, crate 3 is chosen
	inv2.capacity = 0.0 # Full
	var chosen_tiebreak := registry.find_storage_for("any_item", Vector3.ZERO, 1)
	assert_object(chosen_tiebreak).is_equal(crate3)


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

	# Priority selection
	var priority_opt: OptionButton = panel.get_node("%PriorityOption") as OptionButton
	assert_object(priority_opt).is_not_null()
	assert_int(priority_opt.get_item_count()).is_equal(5)

	# Select level 5 (index 4)
	panel._on_priority_selected(4)
	assert_int(storage.priority).is_equal(5)

	# Select level 1 (index 0)
	panel._on_priority_selected(0)
	assert_int(storage.priority).is_equal(1)


func test_storage_filter_action_execution() -> void:
	var canvas_layer := auto_free(CanvasLayer.new()) as CanvasLayer
	canvas_layer.add_to_group("hud_layer")
	add_child(canvas_layer)

	var furniture := auto_free(Furniture.new()) as Furniture
	var storage := auto_free(StorageInventory.new()) as StorageInventory
	storage.name = "StorageInventory"
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
	assert_str(btn2.text).is_equal("Storage Options")


func _make_test_item(p_id: String, p_weight: float, p_tags: Array[String]) -> ItemDef:
	var def := auto_free(ItemDef.new()) as ItemDef
	def.id = p_id
	def.weight = p_weight
	def.tags = p_tags
	return def
