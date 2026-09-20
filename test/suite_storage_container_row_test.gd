extends GdUnitTestSuite

## Colony Management storage card (ui/colony_management/storage_container_row): its
## contents list is built from shared ItemRows in stable display order.
## Content-agnostic: in-memory ItemDefs registered in ItemDB for the test only.

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")
const _RowScene: PackedScene = preload("res://ui/colony_management/storage_container_row.tscn")

var _sandbox: ColonySandbox
var _previous_defs: Dictionary = {}


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)


func after_test() -> void:
	_sandbox.restore()
	for item_id: String in _previous_defs:
		if _previous_defs[item_id] != null:
			ItemDB._defs_by_id[item_id] = _previous_defs[item_id]
		else:
			ItemDB._defs_by_id.erase(item_id)
	_previous_defs.clear()


func _register_item(item_id: String, tags: Array[String]) -> void:
	var def: ItemDef = auto_free(ItemDef.new())
	def.id = item_id
	def.tags = tags
	def.weight = 1.0
	if not _previous_defs.has(item_id):
		_previous_defs[item_id] = ItemDB._defs_by_id.get(item_id, null)
	ItemDB._defs_by_id[item_id] = def


func _make_row(furniture: Furniture) -> StorageContainerRow:
	var row := auto_free(_RowScene.instantiate()) as StorageContainerRow
	add_child(row)
	row.setup(furniture)
	return row


func test_contents_are_item_rows_in_display_order() -> void:
	# Break caught: iterating the dictionary lists stacks in whatever order they were deposited.
	_register_item("test_crate_aaa_rock", ["material"])
	_register_item("test_crate_zzz_axe", ["tool"])
	var crate := _sandbox.make_crate("test_crate_aaa_rock", 3)
	(crate.get_node("StorageInventory") as StorageInventory).add("test_crate_zzz_axe", 1)

	var row := _make_row(crate)

	var names: Array[String] = []
	for child: Node in (row.get_node("%ItemList") as Node).get_children():
		assert_bool(child is ItemRow).is_true()
		names.append((child.get_node("%NameLabel") as Label).text)
	assert_array(names).is_equal(["test_crate_zzz_axe", "test_crate_aaa_rock"])


func test_contents_refresh_when_the_crate_changes_without_waiting_for_a_poll() -> void:
	# Break caught: a 0.5 s poll rebuilt every card whether or not anything changed, and lagged behind hauls.
	_register_item("test_crate_aaa_rock", ["material"])
	var crate := _sandbox.make_crate("test_crate_aaa_rock", 1)
	var row := _make_row(crate)
	var list := row.get_node("%ItemList") as Node
	assert_int(list.get_child_count()).is_equal(1)

	_register_item("test_crate_bbb_ore", ["material"])
	(crate.get_node("StorageInventory") as StorageInventory).add("test_crate_bbb_ore", 2)
	await get_tree().process_frame

	assert_int(list.get_child_count()).is_equal(2)


func test_card_shows_the_containers_priority_and_filter() -> void:
	_register_item("test_crate_aaa_rock", ["material"])
	var crate := _sandbox.make_crate("test_crate_aaa_rock", 1)
	var storage := crate.get_node("StorageInventory") as StorageInventory
	storage.priority = 5

	var row := _make_row(crate)

	assert_str((row.get_node("%FilterLabel") as Label).text).is_equal("Priority 5 - Accepts anything")


func test_card_summary_follows_a_priority_change() -> void:
	_register_item("test_crate_aaa_rock", ["material"])
	var crate := _sandbox.make_crate("test_crate_aaa_rock", 1)
	var row := _make_row(crate)

	(crate.get_node("StorageInventory") as StorageInventory).set_priority(1)
	await get_tree().process_frame

	assert_str((row.get_node("%FilterLabel") as Label).text).contains("Priority 1")
