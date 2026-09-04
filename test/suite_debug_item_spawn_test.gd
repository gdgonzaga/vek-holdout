## Test suite for DebugItemSpawn screen and ItemDB querying.
extends GdUnitTestSuite

const _SpawnerScene := preload("res://ui/debug_item_spawn/debug_item_spawn.tscn")
const _RowScene := preload("res://ui/debug_item_spawn/debug_item_row.tscn")


func test_item_db_get_all_defs_and_ids() -> void:
	var defs: Array[ItemDef] = ItemDB.get_all_defs()
	var ids: Array[String] = ItemDB.get_all_ids()

	assert_int(defs.size()).is_equal(ids.size())
	for def in defs:
		assert_object(def).is_not_null()
		assert_bool(def.id != "").is_true()
		assert_bool(ids.has(def.id)).is_true()


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
	var spawner := auto_free(_SpawnerScene.instantiate()) as DebugItemSpawn
	add_child(spawner)

	var item_list: VBoxContainer = spawner.get_node("%ItemList") as VBoxContainer
	assert_object(item_list).is_not_null()

	var total_count: int = item_list.get_child_count()
	var all_defs := ItemDB.get_all_defs()
	assert_int(total_count).is_equal(all_defs.size())

	if total_count > 0:
		var first_row := item_list.get_child(0) as DebugItemRow
		var query: String = first_row.item_id

		# Filter for the first row's ID
		spawner.filter_entries(query)

		var visible_count := 0
		for child in item_list.get_children():
			var row := child as DebugItemRow
			if row != null and row.visible:
				visible_count += 1
				assert_bool(
					row.item_id.contains(query) or
					row.display_name.to_lower().contains(query.to_lower())
				).is_true()

		assert_int(visible_count).is_greater(0)

		# Clear filter
		spawner.filter_entries("")
		var restored_count := 0
		for child in item_list.get_children():
			var row := child as DebugItemRow
			if row != null and row.visible:
				restored_count += 1

		assert_int(restored_count).is_equal(total_count)


func test_debug_item_spawner_search_submitted_spawns_top_match() -> void:
	var spawner := auto_free(_SpawnerScene.instantiate()) as DebugItemSpawn
	add_child(spawner)

	var all_defs := ItemDB.get_all_defs()
	if all_defs.is_empty():
		return

	var target_def: ItemDef = all_defs[0]
	var query: String = target_def.id

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
