extends GdUnitTestSuite

## ItemRow (ui/shared/item_row): the one icon / name / count / stack-weight line shared
## by the inventory panel and crate listings. Content-agnostic: in-memory ItemDefs.

const _RowScene: PackedScene = preload("res://ui/shared/item_row.tscn")


func _make_def(item_id: String, weight: float, display: String = "") -> ItemDef:
	var def: ItemDef = auto_free(ItemDef.new())
	def.id = item_id
	def.weight = weight
	def.resource_name = display
	return def


func _make_row() -> ItemRow:
	var row := auto_free(_RowScene.instantiate()) as ItemRow
	add_child(row)
	return row


func test_setup_shows_the_display_name_count_and_stack_weight() -> void:
	var row := _make_row()

	row.setup(_make_def("test_row_id", 2.5, "Fancy Name"), 4)

	assert_str((row.get_node("%NameLabel") as Label).text).is_equal("Fancy Name")
	assert_str((row.get_node("%CountLabel") as Label).text).is_equal("4")
	assert_str((row.get_node("%WeightLabel") as Label).text).is_equal("10.0 kg")


func test_setup_falls_back_to_the_id_when_no_name_is_authored() -> void:
	var row := _make_row()

	row.setup(_make_def("test_row_id", 1.0), 1)

	assert_str((row.get_node("%NameLabel") as Label).text).is_equal("test_row_id")


func test_setup_copes_with_an_item_that_has_no_icon() -> void:
	var row := _make_row()

	row.setup(_make_def("test_row_id", 1.0), 1)

	assert_object((row.get_node("%Icon") as TextureRect).texture).is_null()


func test_compact_mode_shrinks_the_icon_and_can_be_undone() -> void:
	var row := _make_row()
	var icon := row.get_node("%Icon") as TextureRect
	var full_size: Vector2 = icon.custom_minimum_size

	row.set_compact(true)
	assert_float(icon.custom_minimum_size.x).is_less(full_size.x)

	row.set_compact(false)
	assert_float(icon.custom_minimum_size.x).is_equal(full_size.x)
