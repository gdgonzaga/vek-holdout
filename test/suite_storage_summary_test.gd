extends GdUnitTestSuite

## StorageSummary (ui/storage/storage_summary): the one-line "Priority N - Accepts ..."
## description of a container. Content-agnostic: in-memory defs registered in ItemDB.

var _previous_defs: Dictionary = {}


func after_test() -> void:
	for item_id: String in _previous_defs:
		if _previous_defs[item_id] != null:
			ItemDB._defs_by_id[item_id] = _previous_defs[item_id]
		else:
			ItemDB._defs_by_id.erase(item_id)
	_previous_defs.clear()


func _register(item_id: String, display: String) -> void:
	var def: ItemDef = auto_free(ItemDef.new())
	def.id = item_id
	def.resource_name = display
	if not _previous_defs.has(item_id):
		_previous_defs[item_id] = ItemDB._defs_by_id.get(item_id, null)
	ItemDB._defs_by_id[item_id] = def


func test_priority_text_names_the_level() -> void:
	assert_str(StorageSummary.priority_text(3)).is_equal("Priority 3")


func test_unrestricted_container_accepts_anything() -> void:
	assert_str(StorageSummary.filter_text([], [])).is_equal("Accepts anything")


func test_item_filter_lists_display_names() -> void:
	_register("test_sum_a", "Alpha")
	_register("test_sum_b", "Beta")
	assert_str(StorageSummary.filter_text(["test_sum_a", "test_sum_b"], [])).is_equal("Accepts: Alpha, Beta")


func test_long_item_filter_is_cut_with_a_count_of_the_rest() -> void:
	for suffix: String in ["a", "b", "c", "d", "e"]:
		_register("test_sum_" + suffix, suffix.to_upper())
	var ids: Array[String] = ["test_sum_a", "test_sum_b", "test_sum_c", "test_sum_d", "test_sum_e"]
	assert_str(StorageSummary.filter_text(ids, [])).is_equal("Accepts: A, B, C +2 more")


func test_tag_filter_lists_the_tags() -> void:
	assert_str(StorageSummary.filter_text([], ["food", "ammo"])).is_equal("Accepts tagged: food, ammo")


func test_item_and_tag_filters_are_both_shown_because_either_admits_an_item() -> void:
	# Break caught: StorageInventory.is_item_allowed ORs ids and tags, so hiding the tags misstates what fits.
	_register("test_sum_a", "Alpha")
	assert_str(StorageSummary.filter_text(["test_sum_a"], ["food"])).is_equal("Accepts: Alpha; tagged: food")


func test_unknown_item_id_falls_back_to_the_id() -> void:
	assert_str(StorageSummary.filter_text(["test_sum_gone"], [])).is_equal("Accepts: test_sum_gone")


func test_describe_joins_priority_and_filter() -> void:
	var storage := auto_free(StorageInventory.new()) as StorageInventory
	storage.priority = 4
	assert_str(StorageSummary.describe(storage)).is_equal("Priority 4 - Accepts anything")


func test_status_text_unrestricted() -> void:
	assert_str(StorageSummary.status_text([], [])).is_equal("Status: Unrestricted (accepts all items)")


func test_status_text_counts_whitelisted_items() -> void:
	assert_str(StorageSummary.status_text(["a"], [])).is_equal("Status: Restricted (1 item allowed)")
	assert_str(StorageSummary.status_text(["a", "b"], [])).is_equal("Status: Restricted (2 items allowed)")


func test_status_text_never_calls_a_tag_restricted_container_unrestricted() -> void:
	# Break caught: counting only the whitelist reports "Unrestricted" for a container the tag rule limits.
	assert_str(StorageSummary.status_text([], ["food"])).is_equal("Status: Restricted (tagged: food)")
	assert_str(StorageSummary.status_text(["a"], ["food", "ammo"])).is_equal("Status: Restricted (1 item allowed; tagged: food, ammo)")
