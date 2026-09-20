extends GdUnitTestSuite

## ItemStackOrder: stable, categorized ordering for item-stack lists (gear, then food,
## then everything else, each by natural-case display name then id), so a list never
## depends on dictionary insertion order. Content-agnostic: in-memory defs only.

var _previous_defs: Dictionary = {}


func after_test() -> void:
	for item_id: String in _previous_defs:
		if _previous_defs[item_id] != null:
			ItemDB._defs_by_id[item_id] = _previous_defs[item_id]
		else:
			ItemDB._defs_by_id.erase(item_id)
	_previous_defs.clear()


func _make_def(item_id: String, tags: Array[String] = [], is_food: bool = false, display: String = "") -> ItemDef:
	var def: ItemDef = auto_free(ItemDef.new())
	def.id = item_id
	def.tags = tags
	def.resource_name = display
	if is_food:
		def.food = auto_free(FoodParams.new())
	return def


func _register(def: ItemDef) -> ItemDef:
	if not _previous_defs.has(def.id):
		_previous_defs[def.id] = ItemDB._defs_by_id.get(def.id, null)
	ItemDB._defs_by_id[def.id] = def
	return def


func test_category_of_recognises_gear_food_and_other() -> void:
	assert_int(ItemStackOrder.category_of(_make_def("t", ["tool"]))).is_equal(ItemStackOrder.Category.GEAR)
	assert_int(ItemStackOrder.category_of(_make_def("f", [], true))).is_equal(ItemStackOrder.Category.FOOD)
	assert_int(ItemStackOrder.category_of(_make_def("o", ["material"]))).is_equal(ItemStackOrder.Category.OTHER)


func test_gear_outranks_food_when_an_item_is_both() -> void:
	assert_int(ItemStackOrder.category_of(_make_def("both", ["tool"], true))).is_equal(ItemStackOrder.Category.GEAR)


func test_is_before_orders_by_category_first() -> void:
	var gear := _make_def("zzz_gear", ["weapon"])
	var food := _make_def("mmm_food", [], true)
	var other := _make_def("aaa_other")
	assert_bool(ItemStackOrder.is_before(gear, food)).is_true()
	assert_bool(ItemStackOrder.is_before(food, other)).is_true()
	assert_bool(ItemStackOrder.is_before(other, gear)).is_false()


func test_is_before_orders_within_a_category_by_natural_name() -> void:
	var two := _make_def("id_b", [], false, "Plank 2")
	var ten := _make_def("id_a", [], false, "Plank 10")
	assert_bool(ItemStackOrder.is_before(two, ten)).is_true()
	assert_bool(ItemStackOrder.is_before(ten, two)).is_false()


func test_is_before_breaks_a_name_tie_by_id() -> void:
	var a := _make_def("id_a", [], false, "Same")
	var b := _make_def("id_b", [], false, "Same")
	assert_bool(ItemStackOrder.is_before(a, b)).is_true()
	assert_bool(ItemStackOrder.is_before(b, a)).is_false()


func test_sorted_item_ids_ignores_dictionary_insertion_order() -> void:
	# Break caught: iterating the dictionary directly reorders a list whenever a stack is re-added.
	_register(_make_def("test_ord_rock", ["material"]))
	_register(_make_def("test_ord_ration", [], true))
	_register(_make_def("test_ord_axe", ["tool"]))
	var expected: Array[String] = ["test_ord_axe", "test_ord_ration", "test_ord_rock"]

	assert_array(ItemStackOrder.sorted_item_ids({"test_ord_rock": 1, "test_ord_axe": 1, "test_ord_ration": 1})).is_equal(expected)
	assert_array(ItemStackOrder.sorted_item_ids({"test_ord_ration": 1, "test_ord_rock": 1, "test_ord_axe": 1})).is_equal(expected)


func test_sorted_item_ids_puts_unresolvable_ids_last_by_id() -> void:
	_register(_make_def("test_ord_rock", ["material"]))
	var sorted: Array[String] = ItemStackOrder.sorted_item_ids({"test_ord_zz_gone": 1, "test_ord_rock": 1, "test_ord_aa_gone": 1})
	assert_array(sorted).is_equal(["test_ord_rock", "test_ord_aa_gone", "test_ord_zz_gone"])
