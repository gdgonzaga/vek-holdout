extends GdUnitTestSuite

## StorageItemRow (ui/storage/storage_item_row): a shared ItemRow plus 1 / 10 / All move
## buttons, disabled and dimmed with an explanatory tooltip when nothing can be moved.
## Content-agnostic: in-memory ItemDefs.

const _RowScene: PackedScene = preload("res://ui/storage/storage_item_row.tscn")


func _make_def(weight: float = 2.0, tags: Array[String] = []) -> ItemDef:
	var def: ItemDef = auto_free(ItemDef.new())
	def.id = "test_srow_item"
	def.weight = weight
	def.tags = tags
	return def


func _make_row(count: int, movable: int, reason: String = "") -> StorageItemRow:
	var row := auto_free(_RowScene.instantiate()) as StorageItemRow
	add_child(row)
	row.setup_transfer(_make_def(), count, movable, reason)
	return row


func _button(row: StorageItemRow, node_name: String) -> Button:
	return row.get_node("%" + node_name) as Button


func test_a_big_movable_stack_enables_all_three_buttons() -> void:
	var row := _make_row(25, 25)
	assert_bool(_button(row, "MoveOneButton").disabled).is_false()
	assert_bool(_button(row, "MoveTenButton").disabled).is_false()
	assert_bool(_button(row, "MoveAllButton").disabled).is_false()


func test_ten_is_disabled_when_the_stack_has_ten_or_fewer_because_all_covers_it() -> void:
	var row := _make_row(10, 10)
	assert_bool(_button(row, "MoveTenButton").disabled).is_true()
	assert_bool(_button(row, "MoveAllButton").disabled).is_false()


func test_nothing_movable_disables_every_button_and_explains_why() -> void:
	# Break caught: a button that silently does nothing when the target refuses the item.
	var row := _make_row(25, 0, "Crate doesn't accept Item.")
	for node_name: String in ["MoveOneButton", "MoveTenButton", "MoveAllButton"]:
		assert_bool(_button(row, node_name).disabled).is_true()
	assert_str(row.tooltip_text).is_equal("Crate doesn't accept Item.")
	assert_float(row.modulate.a).is_less(1.0)


func test_partial_room_keeps_the_buttons_enabled() -> void:
	var row := _make_row(25, 4)
	assert_bool(_button(row, "MoveAllButton").disabled).is_false()
	assert_float(row.modulate.a).is_equal(1.0)


func test_buttons_request_one_ten_and_the_whole_stack() -> void:
	var row := _make_row(25, 25)
	var requested: Array[int] = []
	row.move_requested.connect(func(count: int) -> void: requested.append(count))

	_button(row, "MoveOneButton").pressed.emit()
	_button(row, "MoveTenButton").pressed.emit()
	_button(row, "MoveAllButton").pressed.emit()

	assert_array(requested).is_equal([1, 10, 25])


func test_a_movable_row_has_an_item_details_tooltip() -> void:
	var row := auto_free(_RowScene.instantiate()) as StorageItemRow
	add_child(row)
	row.setup_transfer(_make_def(2.0, ["tool"]), 3, 3, "")
	assert_str(row.tooltip_text).contains("2.0 kg each")
	assert_str(row.tooltip_text).contains("tool")
