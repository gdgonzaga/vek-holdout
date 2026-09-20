extends GdUnitTestSuite

## Unit tests for the player <-> container transfer panel (ui/storage/storage_panel).
## Content-agnostic: in-memory inventories and defs only, no real item ids.

const Doubles = preload("res://test/helpers/doubles.gd")
const _PanelScene: PackedScene = preload("res://ui/storage/storage_panel.tscn")

var _previous_defs: Dictionary = {}


func after_test() -> void:
	for item_id: String in _previous_defs:
		if _previous_defs[item_id] != null:
			ItemDB._defs_by_id[item_id] = _previous_defs[item_id]
		else:
			ItemDB._defs_by_id.erase(item_id)
	_previous_defs.clear()


## Registers an in-memory item in ItemDB (the panel names rows from it) and returns it.
func _register_item(item_id: String, tags: Array[String] = [], weight: float = 1.0) -> ItemDef:
	var def: ItemDef = auto_free(ItemDef.new())
	def.id = item_id
	def.tags = tags
	def.weight = weight
	if not _previous_defs.has(item_id):
		_previous_defs[item_id] = ItemDB._defs_by_id.get(item_id, null)
	ItemDB._defs_by_id[item_id] = def
	return def


## Builds a panel wired to a player inventory and a container inventory that sits under
## its own parent node (as a StorageInventory sits under Furniture). `defs` maps
## item_id -> ItemDef for both inventories' weight lookups. Options: storage_capacity
## (default 50), allowed_ids (container whitelist), plain_storage (a bare Inventory).
## Returns {"panel", "player_inv", "storage_inv", "crate"}.
func _make_panel(defs: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	var player_inv := auto_free(Doubles.MockInventory.new()) as Doubles.MockInventory
	player_inv.capacity = 50.0
	player_inv._defs = defs
	var crate := auto_free(Node.new()) as Node
	add_child(crate)
	var storage_inv: Inventory
	if options.get("plain_storage", false):
		var plain := Doubles.MockInventory.new()
		plain._defs = defs
		storage_inv = plain
	else:
		var storage := Doubles.MockStorageInventory.new()
		storage._defs = defs
		var allowed: Array[String] = []
		allowed.assign(options.get("allowed_ids", []))
		storage.allowed_item_ids = allowed
		storage_inv = storage
	storage_inv.capacity = options.get("storage_capacity", 50.0)
	crate.add_child(storage_inv)
	var panel := auto_free(_PanelScene.instantiate()) as StoragePanel
	add_child(panel)
	panel.setup(player_inv, storage_inv)
	return {"panel": panel, "player_inv": player_inv, "storage_inv": storage_inv, "crate": crate}


func _rows(panel: StoragePanel, list_name: String) -> Array[Node]:
	return panel.get_node("%" + list_name).get_children()


func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame


func _row_button(row: Node, node_name: String) -> Button:
	return row.get_node("%" + node_name) as Button


# ── lifecycle ──────────────────────────────────────────────────────────────────

func test_panel_closes_when_its_container_is_freed() -> void:
	# Break caught: a panel left open over a deconstructed crate keeps a dead inventory reference.
	var parts := _make_panel()
	var closed_counter := Doubles.SignalCounter.new((parts["panel"] as StoragePanel).closed)

	(parts["crate"] as Node).free()

	assert_int(closed_counter.read()).is_equal(1)


func test_escape_inventory_key_and_interact_key_each_close_the_panel() -> void:
	for action: String in ["ui_cancel", "inventory_toggle", "interact"]:
		var parts := _make_panel()
		var panel := parts["panel"] as StoragePanel

		await _press(action)

		# close() queue_frees, and the frame we awaited has usually already freed it.
		var closed: bool = not is_instance_valid(panel) or panel.is_queued_for_deletion()
		assert_bool(closed).override_failure_message("%s did not close the panel" % action).is_true()


func test_inventory_key_does_not_close_a_panel_that_has_another_panel_on_top() -> void:
	# Break caught: I or E pressed in the options panel must not close the panel underneath it.
	var parts := _make_panel()
	var panel := parts["panel"] as StoragePanel
	var on_top := auto_free(Control.new()) as Control
	panel.get_parent().add_child(on_top)

	await _press("inventory_toggle")

	assert_bool(is_instance_valid(panel) and not panel.is_queued_for_deletion()).is_true()


# ── rows and moves ─────────────────────────────────────────────────────────────

func test_rows_are_ordered_by_category_then_name_whatever_the_insertion_order() -> void:
	# Break caught: iterating the inventory dictionary reorders rows whenever a stack is re-added.
	var defs := {
		"test_spanel_aaa_rock": _register_item("test_spanel_aaa_rock", ["material"]),
		"test_spanel_zzz_axe": _register_item("test_spanel_zzz_axe", ["tool"]),
	}
	var parts := _make_panel(defs)
	var player_inv := parts["player_inv"] as Inventory
	player_inv.add("test_spanel_aaa_rock", 1)
	player_inv.add("test_spanel_zzz_axe", 1)
	await get_tree().process_frame

	var names: Array[String] = []
	for row: Node in _rows(parts["panel"], "PlayerList"):
		names.append((row.get_node("%NameLabel") as Label).text)
	assert_array(names).is_equal(["test_spanel_zzz_axe", "test_spanel_aaa_rock"])


func test_one_ten_and_all_buttons_move_that_many() -> void:
	var defs := {"test_spanel_wood": _register_item("test_spanel_wood")}
	var parts := _make_panel(defs)
	var player_inv := parts["player_inv"] as Inventory
	var storage_inv := parts["storage_inv"] as Inventory
	player_inv.add("test_spanel_wood", 30)
	await get_tree().process_frame

	_row_button(_rows(parts["panel"], "PlayerList")[0], "MoveOneButton").pressed.emit()
	assert_int(storage_inv.get_item_count("test_spanel_wood")).is_equal(1)
	await get_tree().process_frame

	_row_button(_rows(parts["panel"], "PlayerList")[0], "MoveTenButton").pressed.emit()
	assert_int(storage_inv.get_item_count("test_spanel_wood")).is_equal(11)
	await get_tree().process_frame

	_row_button(_rows(parts["panel"], "PlayerList")[0], "MoveAllButton").pressed.emit()
	assert_int(storage_inv.get_item_count("test_spanel_wood")).is_equal(30)
	assert_int(player_inv.get_item_count("test_spanel_wood")).is_equal(0)


func test_keyboard_focus_stays_on_the_same_button_after_a_move() -> void:
	# Break caught: every move rebuilds the rows, so a keyboard user would lose focus after each Enter.
	var defs := {"test_spanel_wood": _register_item("test_spanel_wood")}
	var parts := _make_panel(defs)
	(parts["player_inv"] as Inventory).add("test_spanel_wood", 30)
	await get_tree().process_frame
	var one_button := _row_button(_rows(parts["panel"], "PlayerList")[0], "MoveOneButton")
	one_button.grab_focus()

	one_button.pressed.emit()
	await get_tree().process_frame

	var focused := get_viewport().gui_get_focus_owner()
	assert_object(focused).is_same(_row_button(_rows(parts["panel"], "PlayerList")[0], "MoveOneButton"))


func test_container_rows_move_items_back_to_the_player() -> void:
	var defs := {"test_spanel_wood": _register_item("test_spanel_wood")}
	var parts := _make_panel(defs)
	var storage_inv := parts["storage_inv"] as Inventory
	storage_inv.add("test_spanel_wood", 5)
	await get_tree().process_frame

	_row_button(_rows(parts["panel"], "StorageList")[0], "MoveAllButton").pressed.emit()

	assert_int((parts["player_inv"] as Inventory).get_item_count("test_spanel_wood")).is_equal(5)


func test_a_move_that_only_partly_fits_says_how_much_moved() -> void:
	var defs := {"test_spanel_wood": _register_item("test_spanel_wood", [], 2.0)}
	var parts := _make_panel(defs, {"storage_capacity": 8.0})  # room for 4 of the 10
	(parts["player_inv"] as Inventory).add("test_spanel_wood", 10)
	await get_tree().process_frame

	_row_button(_rows(parts["panel"], "PlayerList")[0], "MoveAllButton").pressed.emit()

	var status := (parts["panel"] as StoragePanel).get_node("%StatusLabel") as Label
	assert_bool(status.visible).is_true()
	assert_str(status.text).contains("Moved 4 of 10")
	assert_str(status.text).contains("No room")
	assert_int((parts["player_inv"] as Inventory).get_item_count("test_spanel_wood")).is_equal(6)


func test_a_complete_move_leaves_the_status_line_hidden() -> void:
	var defs := {"test_spanel_wood": _register_item("test_spanel_wood")}
	var parts := _make_panel(defs)
	(parts["player_inv"] as Inventory).add("test_spanel_wood", 3)
	await get_tree().process_frame

	_row_button(_rows(parts["panel"], "PlayerList")[0], "MoveAllButton").pressed.emit()

	assert_bool(((parts["panel"] as StoragePanel).get_node("%StatusLabel") as Label).visible).is_false()


func test_a_row_the_container_rejects_is_disabled_and_says_so() -> void:
	# Break caught: a click that silently does nothing when the container's filter refuses the item.
	var defs := {
		"test_spanel_wood": _register_item("test_spanel_wood"),
		"test_spanel_ammo": _register_item("test_spanel_ammo"),
	}
	var parts := _make_panel(defs, {"allowed_ids": ["test_spanel_ammo"]})
	(parts["player_inv"] as Inventory).add("test_spanel_wood", 3)
	await get_tree().process_frame

	var row := _rows(parts["panel"], "PlayerList")[0]
	assert_bool(_row_button(row, "MoveAllButton").disabled).is_true()
	assert_str((row as Control).tooltip_text).contains("doesn't accept")


func test_a_row_for_a_full_container_is_disabled_with_a_no_room_reason() -> void:
	var defs := {"test_spanel_wood": _register_item("test_spanel_wood", [], 2.0)}
	var parts := _make_panel(defs, {"storage_capacity": 0.0})
	(parts["player_inv"] as Inventory).add("test_spanel_wood", 3)
	await get_tree().process_frame

	var row := _rows(parts["panel"], "PlayerList")[0]
	assert_bool(_row_button(row, "MoveOneButton").disabled).is_true()
	assert_str((row as Control).tooltip_text).contains("No room")


func test_empty_lists_show_a_placeholder() -> void:
	var parts := _make_panel()
	var panel := parts["panel"] as StoragePanel
	assert_bool((panel.get_node("%PlayerEmptyLabel") as Control).visible).is_true()
	assert_bool((panel.get_node("%StorageEmptyLabel") as Control).visible).is_true()


func test_placeholder_hides_once_a_list_has_rows() -> void:
	var defs := {"test_spanel_wood": _register_item("test_spanel_wood")}
	var parts := _make_panel(defs)
	(parts["player_inv"] as Inventory).add("test_spanel_wood", 1)
	await get_tree().process_frame

	var panel := parts["panel"] as StoragePanel
	assert_bool((panel.get_node("%PlayerEmptyLabel") as Control).visible).is_false()
	assert_bool((panel.get_node("%StorageEmptyLabel") as Control).visible).is_true()


# ── header, capacity, options ──────────────────────────────────────────────────

func test_header_describes_the_containers_priority_and_filter() -> void:
	var defs := {"test_spanel_ammo": _register_item("test_spanel_ammo")}
	var parts := _make_panel(defs, {"allowed_ids": ["test_spanel_ammo"]})

	var info := (parts["panel"] as StoragePanel).get_node("%InfoLabel") as Label

	assert_bool(info.visible).is_true()
	assert_str(info.text).contains("Priority 3")
	assert_str(info.text).contains("test_spanel_ammo")


func test_header_info_and_options_button_are_hidden_for_a_plain_inventory() -> void:
	var parts := _make_panel({}, {"plain_storage": true})
	var panel := parts["panel"] as StoragePanel
	assert_bool((panel.get_node("%InfoLabel") as Control).visible).is_false()
	assert_bool((panel.get_node("%ConfigureButton") as Control).visible).is_false()


func test_options_button_asks_for_the_options_panel() -> void:
	var parts := _make_panel()
	var panel := parts["panel"] as StoragePanel
	var counter := Doubles.SignalCounter.new(panel.configure_requested)

	(panel.get_node("%ConfigureButton") as Button).pressed.emit()

	assert_int(counter.read()).is_equal(1)


func test_header_updates_when_the_containers_rules_change() -> void:
	var parts := _make_panel()
	var panel := parts["panel"] as StoragePanel
	var storage := parts["storage_inv"] as StorageInventory

	storage.set_priority(5)
	await get_tree().process_frame

	assert_str((panel.get_node("%InfoLabel") as Label).text).contains("Priority 5")


func test_capacity_bar_shows_the_fill_and_tints_when_nearly_full() -> void:
	var defs := {"test_spanel_wood": _register_item("test_spanel_wood", [], 2.0)}
	var parts := _make_panel(defs, {"storage_capacity": 20.0})
	var panel := parts["panel"] as StoragePanel
	var bar := panel.get_node("%StorageBar") as ProgressBar
	assert_float(bar.value).is_equal(0.0)
	assert_object(bar.modulate).is_equal(Color.WHITE)

	(parts["storage_inv"] as Inventory).add("test_spanel_wood", 9)  # 18 of 20 kg
	await get_tree().process_frame

	assert_float(bar.value).is_equal(90.0)
	assert_object(bar.modulate).is_not_equal(Color.WHITE)


# ── pure text and ratio helpers ────────────────────────────────────────────────

func test_capacity_ratio_is_clamped_to_zero_and_one() -> void:
	assert_float(StoragePanel.capacity_ratio(25.0, 50.0)).is_equal(0.5)
	assert_float(StoragePanel.capacity_ratio(80.0, 50.0)).is_equal(1.0)
	assert_float(StoragePanel.capacity_ratio(0.0, 50.0)).is_equal(0.0)


func test_capacity_ratio_of_a_zero_capacity_container_is_full_only_if_it_holds_something() -> void:
	assert_float(StoragePanel.capacity_ratio(0.0, 0.0)).is_equal(0.0)
	assert_float(StoragePanel.capacity_ratio(3.0, 0.0)).is_equal(1.0)


func test_block_reason_distinguishes_a_filter_from_a_full_container() -> void:
	assert_str(StoragePanel.block_reason_text("the crate", "Plank", false)).is_equal("The crate doesn't accept Plank.")
	assert_str(StoragePanel.block_reason_text("the crate", "Plank", true)).is_equal("No room in the crate.")


func test_transfer_status_is_silent_when_everything_moved() -> void:
	assert_str(StoragePanel.transfer_status_text("Plank", 10, 10, "")).is_empty()


func test_transfer_status_reports_a_partial_move() -> void:
	assert_str(StoragePanel.transfer_status_text("Plank", 10, 4, "No room in the crate.")).is_equal("Moved 4 of 10 Plank. No room in the crate.")


func test_transfer_status_reports_nothing_moved() -> void:
	assert_str(StoragePanel.transfer_status_text("Plank", 10, 0, "No room in the crate.")).is_equal("Couldn't move Plank. No room in the crate.")


# ── OpenStorageAction wiring ───────────────────────────────────────────────────

class ActorWithInventory extends Node:
	var inventory: Inventory


func test_options_button_opens_the_filter_panel_over_the_open_transfer_panel() -> void:
	var layer := auto_free(CanvasLayer.new()) as CanvasLayer
	layer.add_to_group("hud_layer")
	add_child(layer)
	var furniture := auto_free(Furniture.new()) as Furniture
	var storage := StorageInventory.new()
	storage.name = "StorageInventory"
	storage.capacity = 50.0
	furniture.add_child(storage)
	add_child(furniture)
	var actor := auto_free(ActorWithInventory.new()) as ActorWithInventory
	actor.inventory = auto_free(Inventory.new()) as Inventory
	add_child(actor)

	var action := auto_free(OpenStorageAction.new()) as OpenStorageAction
	action.execute(actor, furniture)
	var transfer_panel: StoragePanel = null
	for child: Node in layer.get_children():
		if child is StoragePanel:
			transfer_panel = child
	assert_object(transfer_panel).is_not_null()

	(transfer_panel.get_node("%ConfigureButton") as Button).pressed.emit()

	var filter_panel_found := false
	for child: Node in layer.get_children():
		if child is StorageFilterPanel:
			filter_panel_found = true
			# The filter panel must sit above the transfer panel so it takes input first.
			assert_int(child.get_index()).is_greater(transfer_panel.get_index())
	assert_bool(filter_panel_found).is_true()
	assert_bool(is_instance_valid(transfer_panel) and not transfer_panel.is_queued_for_deletion()).is_true()
