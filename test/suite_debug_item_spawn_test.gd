## Test suite for DebugItemSpawn screen. ItemDB lookup itself (get_all_defs,
## get_all_ids) is covered by suite_item_display_name_test — this suite only
## exercises the screen's own row/filter/spawn behavior, against synthetic
## items registered through ItemDbSandbox so it never depends on the shipped
## res://data/items catalog.
extends GdUnitTestSuite

const _SpawnerScene := preload("res://ui/debug_item_spawn/debug_item_spawn.tscn")
const _RowScene := preload("res://ui/debug_item_spawn/debug_item_row.tscn")
const ItemDbSandbox = preload("res://test/helpers/item_db_sandbox.gd")

var _items: ItemDbSandbox


func before_test() -> void:
	_items = ItemDbSandbox.new(self)


func after_test() -> void:
	_items.restore()


func test_debug_item_row_setup_and_signals() -> void:
	var row := auto_free(_RowScene.instantiate()) as DebugItemRow
	add_child(row)

	var def := ItemDef.new()
	def.id = "test_gadget"
	def.weight = 2.5
	def.tags = ["tool", "electric"]

	row.setup(def)

	assert_str(row.item_id).is_equal("test_gadget")
	assert_int(row.tags.size()).is_equal(2)

	var spawned_events: Array[Dictionary] = []
	row.spawn_requested.connect(func(p_id: String, count: int) -> void:
		spawned_events.append({"id": p_id, "count": count})
	)

	var btn_1: Button = row.get_node("%Spawn1Button") as Button
	var btn_10: Button = row.get_node("%Spawn10Button") as Button

	btn_1.emit_signal("pressed")
	assert_int(spawned_events.size()).is_equal(1)
	assert_str(spawned_events[0]["id"]).is_equal("test_gadget")
	assert_int(spawned_events[0]["count"]).is_equal(1)

	btn_10.emit_signal("pressed")
	assert_int(spawned_events.size()).is_equal(2)
	assert_str(spawned_events[1]["id"]).is_equal("test_gadget")
	assert_int(spawned_events[1]["count"]).is_equal(10)


func test_debug_item_spawner_populate_and_filter() -> void:
	# "alpha"/"beta" are ids no shipped item uses, so the filter below can only
	# ever match these two synthetic rows (populate() runs off ItemDB._ready-time
	# content plus whatever the sandbox added before this scene entered the tree).
	_items.add_item("test_alpha_widget", "Alpha Widget")
	_items.add_item("test_beta_widget", "Beta Widget")

	var spawner := auto_free(_SpawnerScene.instantiate()) as DebugItemSpawn
	add_child(spawner)

	var item_list: VBoxContainer = spawner.get_node("%ItemList") as VBoxContainer
	assert_object(item_list).is_not_null()

	# Filter down to the one synthetic row whose id contains "alpha".
	spawner.filter_entries("alpha")

	var visible_rows: Array[DebugItemRow] = []
	for child in item_list.get_children():
		var row := child as DebugItemRow
		if row != null and row.visible:
			visible_rows.append(row)

	assert_int(visible_rows.size()).is_equal(1)
	assert_str(visible_rows[0].item_id).is_equal("test_alpha_widget")

	# Clearing the filter must restore both synthetic rows to visible.
	spawner.filter_entries("")
	var restored_ids: Array[String] = []
	for child in item_list.get_children():
		var row := child as DebugItemRow
		if row != null and row.visible:
			restored_ids.append(row.item_id)

	assert_array(restored_ids).contains(["test_alpha_widget", "test_beta_widget"])


func test_debug_item_spawner_search_submitted_spawns_top_match() -> void:
	# A synthetic item that filter_entries can match exactly, so the submitted
	# search always resolves to it — no dependence on the shipped catalog having
	# any entries at all.
	_items.add_item("test_spawn_target", "Spawn Target")

	var spawner := auto_free(_SpawnerScene.instantiate()) as DebugItemSpawn
	add_child(spawner)

	var query := "test_spawn_target"
	spawner.filter_entries(query)

	# Submit search to trigger spawn on top match
	spawner._on_search_text_submitted(query)

	var status_label: Label = spawner.get_node("%StatusLabel") as Label
	assert_object(status_label).is_not_null()
	assert_bool(status_label.text.contains(query) or status_label.text.contains("Spawned")).is_true()

	# Clean up any WorldItem spawned in the root
	for child in get_tree().root.get_children():
		if child is WorldItem:
			child.queue_free()
