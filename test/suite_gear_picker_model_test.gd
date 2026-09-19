extends GdUnitTestSuite
## Tests for GearPickerModel: grouping, sorting and filtering of the Gear picker list.
## Content-agnostic: slot tags and ItemDefs are synthetic, ItemDB is never queried.

const TAG_A: String = "tag_a"
const TAG_B: String = "tag_b"


func _make_item(id_val: String, item_tags: Array[String], display: String = "") -> ItemDef:
	var def: ItemDef = auto_free(ItemDef.new())
	def.id = id_val
	def.tags = item_tags
	def.resource_name = display
	return def


func _build(
		defs: Array[ItemDef],
		filter: String = "",
		in_colony_only: bool = false,
		stock: Dictionary = {},
		target_id: String = "",
		equipped_id: String = "") -> Array[GearPickerModel.Entry]:
	return GearPickerModel.build_entries(
			defs, [TAG_A, TAG_B], filter, in_colony_only, stock, target_id, equipped_id)


func _ids(entries: Array[GearPickerModel.Entry]) -> Array[String]:
	var out: Array[String] = []
	for e: GearPickerModel.Entry in entries:
		out.append(e.def.id)
	return out


# ==============================
# Grouping
# ==============================

func test_groups_follow_accepted_tag_order() -> void:
	var b_item: ItemDef = _make_item("b_item", [TAG_B])
	var a_item: ItemDef = _make_item("a_item", [TAG_A])

	var entries: Array[GearPickerModel.Entry] = _build([b_item, a_item])

	assert_array(_ids(entries)).is_equal(["a_item", "b_item"])
	assert_str(entries[0].group).is_equal("Tag A")
	assert_str(entries[1].group).is_equal("Tag B")


func test_item_with_two_accepted_tags_uses_first_in_slot_order() -> void:
	var both: ItemDef = _make_item("both", [TAG_B, TAG_A])

	var entries: Array[GearPickerModel.Entry] = _build([both])

	assert_str(entries[0].group).is_equal("Tag A")


func test_item_without_accepted_tag_lands_in_other_group_last() -> void:
	var stray: ItemDef = _make_item("stray", ["unrelated"])
	var a_item: ItemDef = _make_item("a_item", [TAG_A])

	var entries: Array[GearPickerModel.Entry] = _build([stray, a_item])

	assert_array(_ids(entries)).is_equal(["a_item", "stray"])
	assert_str(entries[1].group).is_equal("Other")


func test_null_defs_are_skipped() -> void:
	var a_item: ItemDef = _make_item("a_item", [TAG_A])

	var entries: Array[GearPickerModel.Entry] = _build([null, a_item])

	assert_array(_ids(entries)).is_equal(["a_item"])


# ==============================
# Sorting
# ==============================

func test_items_sort_by_display_name_within_group() -> void:
	var zed: ItemDef = _make_item("z", [TAG_A], "zed")
	var alpha: ItemDef = _make_item("a", [TAG_A], "Alpha")
	var mid: ItemDef = _make_item("m", [TAG_A], "mid")

	var entries: Array[GearPickerModel.Entry] = _build([zed, alpha, mid])

	assert_array(_ids(entries)).is_equal(["a", "m", "z"])


func test_stocked_items_sort_before_unstocked_within_group() -> void:
	var alpha: ItemDef = _make_item("a", [TAG_A], "Alpha")
	var beta: ItemDef = _make_item("b", [TAG_A], "Beta")

	var entries: Array[GearPickerModel.Entry] = _build([alpha, beta], "", false, {"b": 2})

	assert_array(_ids(entries)).is_equal(["b", "a"])


# ==============================
# Text filter
# ==============================

func test_blank_filter_returns_everything() -> void:
	var entries: Array[GearPickerModel.Entry] = _build(
			[_make_item("a", [TAG_A]), _make_item("b", [TAG_A])], "   ")

	assert_int(entries.size()).is_equal(2)


func test_filter_matches_display_name_case_insensitively() -> void:
	var axe: ItemDef = _make_item("x1", [TAG_A], "Stone Axe")
	var pick: ItemDef = _make_item("x2", [TAG_A], "Pickaxe")

	var entries: Array[GearPickerModel.Entry] = _build([axe, pick], "STONE")

	assert_array(_ids(entries)).is_equal(["x1"])


func test_filter_matches_id() -> void:
	var one: ItemDef = _make_item("needle_id", [TAG_A], "Alpha")
	var two: ItemDef = _make_item("other", [TAG_A], "Beta")

	var entries: Array[GearPickerModel.Entry] = _build([one, two], "needle")

	assert_array(_ids(entries)).is_equal(["needle_id"])


func test_filter_matches_tags() -> void:
	var tagged: ItemDef = _make_item("one", [TAG_A, "sharp"], "Alpha")
	var plain: ItemDef = _make_item("two", [TAG_A], "Beta")

	var entries: Array[GearPickerModel.Entry] = _build([tagged, plain], "sharp")

	assert_array(_ids(entries)).is_equal(["one"])


# ==============================
# In-colony filter and pinning
# ==============================

func test_in_colony_only_hides_items_with_no_stock() -> void:
	var owned: ItemDef = _make_item("owned", [TAG_A])
	var missing: ItemDef = _make_item("missing", [TAG_A])

	var entries: Array[GearPickerModel.Entry] = _build(
			[owned, missing], "", true, {"owned": 1})

	assert_array(_ids(entries)).is_equal(["owned"])


func test_in_colony_only_keeps_target_and_equipped_even_without_stock() -> void:
	var target: ItemDef = _make_item("target", [TAG_A])
	var worn: ItemDef = _make_item("worn", [TAG_A])
	var missing: ItemDef = _make_item("missing", [TAG_A])

	var entries: Array[GearPickerModel.Entry] = _build(
			[target, worn, missing], "", true, {}, "target", "worn")

	assert_array(_ids(entries)).contains_exactly_in_any_order(["target", "worn"])


func test_text_filter_still_hides_a_pinned_target() -> void:
	var target: ItemDef = _make_item("target", [TAG_A], "Alpha")
	var other: ItemDef = _make_item("other", [TAG_A], "Beta")

	var entries: Array[GearPickerModel.Entry] = _build(
			[target, other], "beta", true, {"other": 1}, "target")

	assert_array(_ids(entries)).is_equal(["other"])


# ==============================
# Entry flags
# ==============================

func test_entry_carries_stock_and_target_and_equipped_flags() -> void:
	var target: ItemDef = _make_item("target", [TAG_A])
	var worn: ItemDef = _make_item("worn", [TAG_A])

	var entries: Array[GearPickerModel.Entry] = _build(
			[target, worn], "", false, {"target": 3}, "target", "worn")

	var by_id: Dictionary = {}
	for e: GearPickerModel.Entry in entries:
		by_id[e.def.id] = e
	assert_int(by_id["target"].stock).is_equal(3)
	assert_bool(by_id["target"].is_target).is_true()
	assert_bool(by_id["target"].is_equipped).is_false()
	assert_int(by_id["worn"].stock).is_equal(0)
	assert_bool(by_id["worn"].is_equipped).is_true()
